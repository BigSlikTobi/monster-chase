#!/usr/bin/env python3
"""Private Linux worker setup and ChatGPT device login. No API credentials."""
import argparse
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlencode

from analysis import worker_environment
from chases import load_catalog
from setup import configure_models
from server import atomic_json


def private_address(value):
    address = ipaddress.IPv4Address(value)
    if address not in ipaddress.IPv4Network("100.64.0.0/10"):
        raise ValueError("Use the server's Tailscale IPv4 address (100.64.0.0/10), not its public IP.")
    return str(address)


def auth_command(config, *args):
    return [config["codex"], "-c", 'forced_login_method="chatgpt"',
            "-c", 'cli_auth_credentials_store="file"', "login", *args]


def check_login(config):
    result = subprocess.run(auth_command(config, "status"), env=worker_environment(config),
                            capture_output=True, text=True, timeout=30)
    if result.returncode or "chatgpt" not in (result.stdout + result.stderr).lower():
        raise ValueError("ChatGPT login is missing. Run the Linux login command as the cardscout user.")


def initialize(root, address, codex):
    root = root.expanduser().resolve()
    address = private_address(address)
    executable = shutil.which(codex)
    if executable is None:
        raise ValueError("Codex CLI not found. Install it before setting up the worker.")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    # Do not change certificates, configuration or catalogs under a running worker.
    with (root / "service.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        path = root / "config.json"
        config = json.loads(path.read_text()) if path.exists() else {
            "port": 8743, "token": secrets.token_urlsafe(36)}
        if config.get("host", address) != address:
            raise ValueError("Address changed. Use a new data directory and pair again.")
        config.update(host=address, bind=address, codex=str(Path(executable).absolute()),
                      codexHome=str(root / "codex"))
        configure_models(config)
        auth_home = Path(config["codexHome"])
        auth_home.mkdir(mode=0o700, exist_ok=True)
        auth_home.chmod(0o700)
        # The auth store must also match exec --ignore-user-config in analysis.py.
        (auth_home / "config.toml").write_text(
            'cli_auth_credentials_store = "file"\nforced_login_method = "chatgpt"\n')
        (auth_home / "config.toml").chmod(0o600)
        cert, key = root / "server.crt", root / "server.key"
        if cert.exists() != key.exists():
            raise ValueError("Incomplete TLS certificate/key pair. Restore both before continuing.")
        if not cert.exists():
            with tempfile.TemporaryDirectory(dir=root) as temporary:
                folder = Path(temporary)
                subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256",
                                "-nodes", "-days", "365", "-keyout", str(folder / "key"),
                                "-out", str(folder / "cert"), "-subj", "/CN=" + address,
                                "-addext", "subjectAltName=IP:" + address,
                                "-addext", "extendedKeyUsage=serverAuth",
                                "-addext", "basicConstraints=critical,CA:TRUE"],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                (folder / "key").chmod(0o600)
                (folder / "cert").chmod(0o600)
                (folder / "key").replace(key)
                (folder / "cert").replace(cert)
        der = subprocess.check_output(["openssl", "x509", "-in", str(cert), "-outform", "DER"])
        query = urlencode({"url": f"https://{address}:{config['port']}", "token": config["token"],
                           "pin": hashlib.sha256(der).hexdigest()})
        pairing = root / "pairing.txt"
        pairing.write_text("cardscout://pair?" + query)
        pairing.chmod(0o600)
        source = Path(__file__).resolve().parent / "data"
        for name in ("collections.json", "chases.json", "reference-images.json"):
            if not (root / name).exists():
                value = load_catalog(source / name) if name == "chases.json" else json.loads((source / name).read_text())
                atomic_json(root / name, value)
        for name in ("chrome", "optic", "bowman"):
            supplement = source / f"{name}-checklist-supplement.json"
            if supplement.exists():
                atomic_json(root / supplement.name, json.loads(supplement.read_text()))
        atomic_json(path, config)
    return config


def load_config(root):
    root = root.expanduser().resolve()
    config = json.loads((root / "config.json").read_text())
    private_address(config["bind"])
    if config["bind"] != config["host"] or Path(config["codexHome"]) != root / "codex":
        raise ValueError("Invalid server address or isolated login directory. Run setup again.")
    return config


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("setup", "login", "check", "pair", "serve"))
    parser.add_argument("--data", type=Path, default=Path("/var/lib/cardscout/data"))
    parser.add_argument("--address", help="Server Tailscale IPv4; required for setup")
    parser.add_argument("--codex", default="/opt/cardscout/node_modules/.bin/codex")
    parser.add_argument("--browser", action="store_true", help="Use normal browser login instead of a device code (login only)")
    args = parser.parse_args()
    if args.browser and args.command != "login":
        parser.error("--browser is only valid with login")
    os.umask(0o077)
    root = args.data.expanduser().resolve()
    try:
        if args.command == "setup":
            if not args.address:
                parser.error("setup requires --address")
            initialize(root, args.address, args.codex)
            print("Server configured. Next: login, check, then start the service.")
            return
        config = load_config(root)
        if args.command == "login":
            # Login URL/code goes directly to the operator's terminal, never a web endpoint.
            login_args = () if args.browser else ("--device-auth",)
            subprocess.run(auth_command(config, *login_args), env=worker_environment(config), check=True)
            check_login(config)
            print("ChatGPT login ready. No API billing configured.")
        elif args.command == "check":
            check_login(config)
            print("ChatGPT login ready.")
        elif args.command == "pair":
            print((root / "pairing.txt").read_text())
        elif args.command == "serve":
            check_login(config)
            os.execve(sys.executable, [sys.executable, str(Path(__file__).with_name("server.py")),
                                     "--data", str(root)], worker_environment(config))
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        # Do not dump subprocess output, authentication material or config values.
        message = str(error) if isinstance(error, ValueError) else "Server command failed. Check setup, service ownership and ChatGPT login."
        parser.exit(1, message + "\n")


if __name__ == "__main__":
    main()
