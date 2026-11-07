#!/usr/bin/env python3
"""Install the per-user companion. Secrets stay in private Application Support, never source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import secrets
import re
import shutil
import subprocess
import sys
import time
import ssl
import urllib.request
import urllib.parse
from chases import load_catalog

MODEL_ROUTING_VERSION = 2
PRIMARY_MODEL = "gpt-6-luna"
FALLBACK_MODEL = "gpt-5.6-sol"
MODEL_REASONING_EFFORT = "max"

def configure_models(config):
    """Apply the Card Scout route once while preserving later explicit operator changes."""
    version = int(config.get("modelRoutingVersion", 0))
    legacy_defaults = (version == 1 and config.get("model") == "gpt-5.6-luna"
                       and config.get("reasoningEffort", "max") == "max"
                       and config.get("fallbackModel", "gpt-5.6-sol") == "gpt-5.6-sol"
                       and config.get("fallbackReasoningEffort", "max") == "max")
    if version < 1 or legacy_defaults:
        config.update(model=PRIMARY_MODEL, reasoningEffort=MODEL_REASONING_EFFORT,
                      fallbackModel=FALLBACK_MODEL, fallbackReasoningEffort=MODEL_REASONING_EFFORT,
                      modelRoutingVersion=MODEL_ROUTING_VERSION)
    else:
        config.setdefault("model", PRIMARY_MODEL)
        config.setdefault("reasoningEffort", MODEL_REASONING_EFFORT)
        config.setdefault("fallbackModel", FALLBACK_MODEL)
        config.setdefault("fallbackReasoningEffort", MODEL_REASONING_EFFORT)
    return config

def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--install", action="store_true"); args = parser.parse_args()
    os.umask(0o077)
    source = Path(__file__).resolve().parent
    chase_seed = load_catalog(source / "data/chases.json")
    root = Path.home() / "Library/Application Support/CardScoutMac"
    root.mkdir(parents=True, exist_ok=True); root.chmod(0o700)
    candidates = [shutil.which("codex"), "/Applications/ChatGPT.app/Contents/Resources/codex", "/Applications/Codex.app/Contents/Resources/codex"]
    versions = []
    for candidate in candidates:
        if not candidate or not Path(candidate).is_file(): continue
        check = subprocess.run([candidate, "--version"], capture_output=True, text=True)
        match = re.search(r"(\d+)\.(\d+)\.(\d+)", check.stdout)
        if check.returncode == 0 and match: versions.append((tuple(map(int, match.groups())), candidate))
    codex = max(versions)[1] if versions else None
    if not codex: raise SystemExit("Codex CLI is not installed.")
    auth = subprocess.run([codex, "login", "status"], capture_output=True, text=True)
    if auth.returncode or "ChatGPT" not in auth.stdout + auth.stderr: raise SystemExit("Sign in to Codex with ChatGPT first.")
    host = subprocess.check_output(["scutil", "--get", "LocalHostName"], text=True).strip() + ".local"
    config_path = root / "config.json"
    config = json.loads(config_path.read_text()) if config_path.exists() else {"port": 8743, "token": secrets.token_urlsafe(36), "bind": "0.0.0.0"}
    config.update(codex=codex, host=host)
    # Card Scout owns a bounded Luna -> Sol route without carrying personal tools or unrelated instructions.
    configure_models(config)
    config_path.write_text(json.dumps(config)); config_path.chmod(0o600)
    if not (root / "server.crt").exists():
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes", "-days", "365", "-keyout", str(root / "server.key"), "-out", str(root / "server.crt"), "-subj", "/CN=" + host, "-addext", f"subjectAltName=DNS:{host},DNS:localhost,IP:127.0.0.1", "-addext", "extendedKeyUsage=serverAuth", "-addext", "basicConstraints=critical,CA:TRUE"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    der = subprocess.check_output(["openssl", "x509", "-in", str(root / "server.crt"), "-outform", "DER"])
    pin = hashlib.sha256(der).hexdigest()
    query = urllib.parse.urlencode({"url": f"https://{host}:{config['port']}", "token": config["token"], "pin": pin})
    (root / "pairing.txt").write_text("cardscout://pair?" + query)
    seed = source / "data/collections.json"
    if seed.exists():
        old = json.loads((root / "collections.json").read_text()) if (root / "collections.json").exists() else []
        for c in json.loads(seed.read_text()):
            old = [v for v in old if v["id"] != c["id"]] + [c]
        (root / "collections.json").write_text(json.dumps(old, ensure_ascii=False))
    reference_seed = source / "data/reference-images.json"
    for name in ("chrome", "optic", "bowman"):
        supplement = source / f"data/{name}-checklist-supplement.json"
        if supplement.exists():
            shutil.copy2(supplement, root / supplement.name)
    if reference_seed.exists() and not (root / "reference-images.json").exists():
        from reference_images import load as load_references
        load_references(reference_seed)
        shutil.copy2(reference_seed, root / "reference-images.json")
    if args.install:
        # Bundled catalogs can be upgraded. Imported/live user catalogs stay untouched.
        chase_path = root / "chases.json"
        existing_chases = load_catalog(chase_path) if chase_path.exists() else None
        bundled_revisions = {"2026-09-08.1"}
        seed_managed = existing_chases is None or existing_chases.get("managedBy") == "cardscout-bundled" or existing_chases.get("revision") in bundled_revisions
        if chase_seed and seed_managed and (existing_chases is None or existing_chases.get("revision") != chase_seed.get("revision")):
            temporary = root / "chases.tmp"
            temporary.write_text(json.dumps(chase_seed, ensure_ascii=False), encoding="utf-8")
            temporary.chmod(0o600); temporary.replace(chase_path)
        # Copy executable code out of iCloud/Documents so a background agent can read it reliably.
        installed = root / "service"; installed.mkdir(exist_ok=True)
        for filename in ("server.py", "scan_matches.py", "reference_images.py", "catalog_supplement.py", "analysis.py", "api_client.py", "retrieval.py", "card_prices.py", "raw_guides.py", "retrieve_page.cjs", "schema.py", "chases.py", "cardsight.py", "cardsight_pilot.py"):
            shutil.copy2(source / filename, installed / filename)
        plist = Path.home() / "Library/LaunchAgents/com.tobiaslatta.cardscout.plist"
        plist.parent.mkdir(parents=True, exist_ok=True)
        payload = {"Label": "com.tobiaslatta.cardscout", "ProgramArguments": [sys.executable, str(installed / "server.py"), "--data", str(root)], "RunAtLoad": True, "KeepAlive": True, "ThrottleInterval": 15, "WorkingDirectory": str(installed), "EnvironmentVariables": {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(Path.home())}, "StandardOutPath": str(root / "service.log"), "StandardErrorPath": str(root / "service-error.log")}
        plist.write_bytes(plistlib.dumps(payload))
        domain = "gui/" + str(os.getuid())
        subprocess.run(["launchctl", "bootout", domain + "/com.tobiaslatta.cardscout"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # bootout can return before launchd finishes retiring the old service registration.
        deadline = time.monotonic() + 20
        while subprocess.run(["launchctl", "print", domain + "/com.tobiaslatta.cardscout"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
            if time.monotonic() > deadline: raise SystemExit("Previous Card Scout service is still stopping. Run setup again in a moment.")
            time.sleep(0.2)
        for attempt in range(5):
            started = subprocess.run(["launchctl", "bootstrap", domain, str(plist)], capture_output=True)
            if started.returncode == 0: break
            time.sleep(0.5)
        else: raise SystemExit("Card Scout could not be started. Check the private service log; no administrator access is required.")
        context = ssl.create_default_context(cafile=str(root / "server.crt"))
        for attempt in range(20):
            try:
                request = urllib.request.Request(f"https://localhost:{config['port']}/v1/ping", headers={"Authorization": "Bearer " + config["token"]})
                with urllib.request.urlopen(request, context=context, timeout=2) as response:
                    if json.load(response).get("status") == "ok": break
            except Exception: pass
            time.sleep(0.25)
        else: raise SystemExit("Card Scout started but is not responding. Check the private service log.")
    print(json.dumps({"dataDirectory": str(root), "pairingFile": str(root / "pairing.txt"),
                      "model": config.get("model", "Codex default"),
                      "fallbackModel": config.get("fallbackModel"), "installed": args.install}))

if __name__ == "__main__": main()
