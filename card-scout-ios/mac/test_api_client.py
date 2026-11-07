import io
import json
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error

from api_client import load_api_key, run_response, NoRedirects
from analysis import _run_model, validate_identification, worker_environment
from schema import IDENTITY_RESULT, RESULT, MARKET_RESULT
from test_fast_capture import identity
from test_pipeline import result


class APIClientTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.secret = self.root / "private.env"
        self.secret.write_text("OPENAI_API_KEY=sk-fixture-never-log\n")
        self.secret.chmod(0o600)
        self.config = {"apiKeyFile": str(self.secret), "apiEnabled": True, "apiModel": "gpt-6-luna"}
        (self.root / "front.jpg").write_bytes(b"\xff\xd8\xfffixture")

    def tearDown(self): self.temporary.cleanup()

    def response(self, value=None, **extra):
        return io.BytesIO(json.dumps(dict(status="completed", service_tier="fast", usage={"input_tokens": 20, "output_tokens": 30},
            output=[{"type": "message", "content": [{"type": "output_text", "text": json.dumps(value if value is not None else identity())}]}], **extra)).encode())

    def call(self, **options):
        return run_response(self.root, self.config, "fixture", IDENTITY_RESULT, "gpt-6-luna", "medium",
                            photo_only=options.get("photo_only", True), attach_images=options.get("attach_images", True), stop=options.get("stop"))

    def test_private_file_required_and_no_symlink(self):
        self.assertEqual(load_api_key(self.config), "sk-fixture-never-log")
        self.secret.chmod(0o644)
        with self.assertRaises(RuntimeError): load_api_key(self.config)
        self.secret.chmod(0o600)
        link = self.root / "link"; link.symlink_to(self.secret)
        with self.assertRaises(RuntimeError): load_api_key({"apiKeyFile": str(link)})

    def test_identification_is_image_structured_fast_and_without_tools(self):
        with patch("api_client.urllib.request.build_opener") as build:
            build.return_value.open.return_value = self.response()
            value = self.call()
        self.assertEqual(value, identity())
        request = build.return_value.open.call_args.args[0]
        payload = json.loads(request.data)
        self.assertEqual(payload["model"], "gpt-6-luna")
        self.assertEqual(payload["service_tier"], "fast")
        self.assertFalse(payload["store"])
        self.assertEqual(payload["tools"], [])
        self.assertTrue(payload["input"][0]["content"][1]["image_url"].startswith("data:image/jpeg;base64,"))
        self.assertTrue(payload["text"]["format"]["strict"])
        self.assertNotIn("sk-fixture", (self.root / "worker.log").read_text())
        self.assertNotIn("playerNameOnCard", (self.root / "worker.log").read_text())

    def test_market_refresh_never_searches_even_with_legacy_live_setting(self):
        self.config["webSearch"] = "live"
        with patch("api_client.urllib.request.build_opener") as build:
            build.return_value.open.return_value = self.response()
            self.call(photo_only=False, attach_images=False)
        payload = json.loads(build.return_value.open.call_args.args[0].data)
        self.assertEqual(payload["tools"], [])
        self.assertEqual(len(payload["input"][0]["content"]), 1)
        self.assertNotIn("max_tool_calls", payload)

    def test_missing_photo_fails_before_paid_call_and_png_mime_is_correct(self):
        photo = self.root / "front.jpg"
        photo.unlink()
        with patch("api_client.urllib.request.build_opener") as build:
            with self.assertRaises(ValueError): self.call()
            build.assert_not_called()
        photo.write_bytes(b"\x89PNG\r\n\x1a\nfixture")
        with patch("api_client.urllib.request.build_opener") as build:
            build.return_value.open.return_value = self.response()
            self.call()
        payload = json.loads(build.return_value.open.call_args.args[0].data)
        self.assertTrue(payload["input"][0]["content"][1]["image_url"].startswith("data:image/png;base64,"))

    def test_http_errors_never_echo_key_or_retry(self):
        with patch("api_client.urllib.request.build_opener") as build:
            build.return_value.open.side_effect = urllib.error.HTTPError("https://api.openai.com", 429, "sk-fixture", {}, io.BytesIO(b"sk-fixture"))
            with self.assertRaisesRegex(RuntimeError, "HTTP 429") as caught: self.call()
            self.assertNotIn("sk-fixture", str(caught.exception))
            self.assertEqual(build.return_value.open.call_count, 1)

    def test_incomplete_refused_and_cancelled_results_are_not_accepted(self):
        for value in [{"status": "incomplete", "output": []}, {"status": "completed", "output": [{"type": "message", "content": [{"type": "refusal"}]}]}]:
            with patch("api_client.urllib.request.build_opener") as build:
                build.return_value.open.return_value = io.BytesIO(json.dumps(value).encode())
                with self.assertRaises(RuntimeError): self.call()
        stop = threading.Event(); stop.set()
        with patch("api_client.urllib.request.build_opener") as build:
            with self.assertRaises(InterruptedError): self.call(stop=stop)
            build.assert_not_called()

    def test_luna_uses_api_and_keeps_identity_validation(self):
        guessed = identity(); guessed.update(player="Tutu Atwell", playerNameOnCard="FERGUSON")
        with patch("api_client.run_response", return_value=guessed) as api, patch("analysis.subprocess.Popen") as cli:
            output = _run_model(self.root, [], self.config, "fixture", IDENTITY_RESULT, None, "gpt-6-luna", "medium")
        self.assertIsNone(output["analysis"]["player"])
        self.assertEqual(api.call_count, 1); cli.assert_not_called()

    def test_full_luna_and_market_refresh_use_api_but_sol_stays_codex(self):
        for contract in (RESULT, MARKET_RESULT):
            with patch("api_client.run_response", return_value={}) as api, patch("analysis.validate_model_output", return_value={}), patch("analysis.subprocess.Popen") as cli:
                _run_model(self.root, [], self.config, "fixture", contract, {} if contract is MARKET_RESULT else None, "gpt-6-luna", "medium")
            self.assertEqual(api.call_count, 1); cli.assert_not_called()
        config = dict(self.config, codex="fixture")
        with patch("api_client.run_response") as api, patch("analysis.subprocess.Popen", side_effect=RuntimeError("CLI selected")) as cli:
            with self.assertRaisesRegex(RuntimeError, "CLI selected"):
                _run_model(self.root, [], config, "fixture", RESULT, None, "gpt-5.6-sol", "max")
        api.assert_not_called(); self.assertEqual(cli.call_count, 1)

    def test_redirect_cannot_forward_authorization(self):
        self.assertIsNone(NoRedirects().redirect_request(None, None, 302, "", {}, "https://other.example"))
