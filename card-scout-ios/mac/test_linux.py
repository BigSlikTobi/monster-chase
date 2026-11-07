import fcntl
from contextlib import redirect_stdout
import io
import json
import os
from pathlib import Path
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

from analysis import worker_environment, _run_model
from linux import initialize, load_config, check_login, main
from schema import IDENTITY_RESULT


class LinuxTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "data"

    def tearDown(self):
        self.temp.cleanup()

    def setup_server(self):
        return initialize(self.root, "100.100.100.10", sys.executable)

    def test_rejects_public_lan_loopback_and_wildcard_before_writing(self):
        for address in ("0.0.0.0", "127.0.0.1", "192.168.1.2", "8.8.8.8", "100.128.0.1", "::1"):
            with self.subTest(address=address), self.assertRaises(ValueError):
                initialize(self.root, address, sys.executable)
        self.assertFalse(self.root.exists())

    def test_installed_module_bundle_can_start_without_the_source_tree(self):
        source = Path(__file__).resolve().parent
        installer = source.parent / "server/install-linux.sh"
        if not installer.exists():
            self.skipTest("Installer is not present in this copied worker-only test directory")
        modules = re.search(r"for module in ([a-z_ ]+); do", installer.read_text()).group(1).split()
        self.root.mkdir()
        for name in modules:
            shutil.copyfile(source / (name + ".py"), self.root / (name + ".py"))
        # Clean environment excludes the source tree from the service's import path.
        run = subprocess.run([sys.executable, str(self.root / "linux.py"), "--help"],
                             cwd=self.root, env={"PATH": os.environ["PATH"]}, capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_setup_generates_valid_private_pairing_and_preserves_existing_data(self):
        config = self.setup_server()
        original_key = (self.root / "server.key").read_bytes()
        original_pairing = (self.root / "pairing.txt").read_text()
        query = parse_qs(urlsplit(original_pairing).query)
        self.assertEqual(query["url"], ["https://100.100.100.10:8743"])
        self.assertEqual(query["token"], [config["token"]])
        self.assertEqual(len(query["pin"][0]), 64)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(self.root / "server.crt", self.root / "server.key")
        cert = subprocess.check_output(["openssl", "x509", "-in", str(self.root / "server.crt"),
                                        "-noout", "-text"], text=True)
        self.assertIn("IP Address:100.100.100.10", cert)
        for name in ("config.json", "server.key", "pairing.txt", "codex/config.toml"):
            self.assertEqual((self.root / name).stat().st_mode & 0o777, 0o600)
        (self.root / "collections.json").write_text('[{"id":"existing"}]')
        self.assertEqual(self.setup_server(), config)
        self.assertEqual((self.root / "server.key").read_bytes(), original_key)
        self.assertEqual((self.root / "pairing.txt").read_text(), original_pairing)
        self.assertEqual(json.loads((self.root / "collections.json").read_text()), [{"id": "existing"}])
        self.assertEqual(load_config(self.root), config)

    def test_refuses_setup_while_worker_owns_queue(self):
        self.setup_server()
        with (self.root / "service.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.setup_server()

    def test_rejects_address_change_and_incomplete_certificate(self):
        self.setup_server()
        with self.assertRaises(ValueError):
            initialize(self.root, "100.100.100.11", sys.executable)
        (self.root / "server.key").unlink()
        with self.assertRaises(ValueError):
            self.setup_server()

    def test_login_preflight_rejects_api_auth_missing_login_and_errors(self):
        config = {"codex": "/test/codex", "codexHome": str(self.root / "codex")}
        for code, message in ((0, "Logged in using an API key"), (1, "Not logged in"), (1, "ChatGPT error")):
            with patch("linux.subprocess.run", return_value=subprocess.CompletedProcess([], code, "", message)):
                with self.assertRaises(ValueError):
                    check_login(config)
        with patch("linux.subprocess.run", return_value=subprocess.CompletedProcess([], 0, "", "Logged in using ChatGPT")) as run:
            check_login(config)
        self.assertEqual(run.call_args.kwargs["env"]["CODEX_HOME"], config["codexHome"])
        self.assertIn('cli_auth_credentials_store="file"', run.call_args.args[0])
        self.assertIn('forced_login_method="chatgpt"', run.call_args.args[0])

    def test_server_auth_is_isolated_and_api_secrets_are_removed(self):
        with patch.dict(os.environ, {"CODEX_HOME": "/personal", "OPENAI_API_KEY": "fixture",
                                    "CARDSIGHT_API_KEY": "fixture", "OTHER_TOKEN": "fixture"}):
            env = worker_environment({"codexHome": "/server/auth"})
            self.assertEqual(env["CODEX_HOME"], "/server/auth")
            self.assertEqual(worker_environment({})["CODEX_HOME"], "/personal")
        self.assertNotIn("OPENAI_API_KEY", env)
        self.assertNotIn("CARDSIGHT_API_KEY", env)
        self.assertNotIn("OTHER_TOKEN", env)

    def test_browser_login_avoids_device_code_and_checks_same_isolated_store(self):
        config = self.setup_server()
        status = subprocess.CompletedProcess([], 0, "Logged in using ChatGPT", "")
        with patch.object(sys, "argv", ["linux.py", "login", "--browser", "--data", str(self.root)]), \
                patch("linux.subprocess.run", return_value=status) as run, \
                patch("linux.os.umask"), redirect_stdout(io.StringIO()):
            main()
        login = run.call_args_list[0]
        self.assertEqual(login.args[0][-1], "login")
        self.assertNotIn("--device-auth", login.args[0])
        self.assertEqual(login.kwargs["env"]["CODEX_HOME"], config["codexHome"])
        self.assertEqual(run.call_args_list[1].args[0][-2:], ["login", "status"])

    def test_actual_subprocess_uses_same_auth_store_and_keeps_worker_restrictions(self):
        # Run a local fake CLI through the real subprocess boundary. No AI request or login.
        self.root.mkdir()
        script = self.root / "fake-codex"
        script.write_text("#!" + sys.executable + "\n" +
                          "import json, os, pathlib, sys\n" +
                          "args = sys.argv[1:]\n" +
                          "os.chdir(args[args.index('--cd')+1])\n" +
                          "pathlib.Path('observed.json').write_text(json.dumps({'args':args, 'home':os.environ['CODEX_HOME'], 'api':os.getenv('OPENAI_API_KEY')}))\n" +
                          "pathlib.Path(args[args.index('--output-last-message')+1]).write_text('{}')\n")
        script.chmod(0o700)
        with patch("analysis.validate_identification", return_value={}), patch.dict(os.environ, {"OPENAI_API_KEY": "fixture"}):
            _run_model(self.root, [], {"codex": str(script), "codexHome": str(self.root / "codex")},
                       "fixture", IDENTITY_RESULT, None, "test-model", "medium")
        observed = json.loads((self.root / "observed.json").read_text())
        self.assertEqual(observed["home"], str(self.root / "codex"))
        self.assertIsNone(observed["api"])
        self.assertIn('cli_auth_credentials_store="file"', observed["args"])
        self.assertIn('forced_login_method="chatgpt"', observed["args"])
        self.assertIn("--ignore-user-config", observed["args"])
        self.assertIn("read-only", observed["args"])
        self.assertIn("shell_tool", observed["args"])


if __name__ == "__main__":
    unittest.main()
