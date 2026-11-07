"""Offline safety checks. Never load real credentials or call CardSight."""

import contextlib
import io
import json
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import Mock, patch

from cardsight_pilot import Pilot, REQUEST_BUDGET, load_key, save_secret, validate_request


FAKE_KEY = "fake-card-scout-test-key-not-a-credential"


def price_request(**overrides):
    body = {"card_ids": ["11111111-1111-4111-8111-111111111111"],
            "parallel_id": None, "grade_id": None, "period": "90d",
            "listing_type": "auction", "limit": 25}
    body.update(overrides)
    return {"method": "POST", "path": "/v1/pricing/", "body": body}


class CardSightRequestSafetyTests(unittest.TestCase):
    def test_allows_only_catalog_usage_and_read_only_pricing(self):
        for request in ({"path": "/v1/subscription/"},
                        {"path": "/v1/catalog/cards", "params": {"take": 5}},
                        price_request()):
            validate_request(request)

    def test_rejects_writes_uploads_and_external_destinations(self):
        for request in ({"method": "DELETE", "path": "/v1/catalog/cards"},
                        {"method": "POST", "path": "/v1/identify"},
                        {"method": "POST", "path": "/v1/collections"},
                        {"path": "https://example.com/v1/catalog/cards"},
                        {"path": "/v1/catalog/cards/../../../account"},
                        {"method": "POST", "path": "/v1/subscription/"}):
            with self.subTest(request=request), self.assertRaises(ValueError):
                validate_request(request)

    def test_requires_raw_auction_explicit_variant_and_small_sample(self):
        for change in ({"grade_id": "graded"}, {"listing_type": "both"},
                       {"listing_type": "fixed"}, {"period": "all"},
                       {"limit": 101}, {"card_ids": []},
                       {"card_ids": ["one"] * 13}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                validate_request(price_request(**change))
        for field in ("parallel_id", "grade_id"):
            request = price_request()
            del request["body"][field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                validate_request(request)

    def test_limits_catalog_page_size(self):
        for take in (0, 101):
            with self.assertRaises(ValueError):
                validate_request({"path": "/v1/catalog/cards", "params": {"take": take}})

    def test_budget_stops_before_opening_connection(self):
        pilot = Pilot(FAKE_KEY)
        pilot.calls = REQUEST_BUDGET
        with patch("cardsight_pilot.http.client.HTTPSConnection") as connection:
            with self.assertRaises(ValueError):
                pilot.query({"path": "/v1/subscription/"})
            connection.assert_not_called()

    @patch("cardsight_pilot.time.sleep")
    @patch("cardsight_pilot.http.client.HTTPSConnection")
    def test_usage_response_does_not_expose_key(self, connection, _sleep):
        response = Mock(status=200)
        response.read.return_value = json.dumps({"calls": 18,
            "api_keys": [{"key": FAKE_KEY, "calls": 18}]}).encode()
        connection.return_value.getresponse.return_value = response
        result = Pilot(FAKE_KEY).query({"path": "/v1/subscription/"})
        self.assertEqual(result["data"], {"calls": 18, "this_key_calls": [18]})
        self.assertNotIn(FAKE_KEY, json.dumps(result))
        self.assertEqual(connection.call_args.args[0], "api.cardsight.ai")
        self.assertIsNotNone(connection.call_args.kwargs["context"])

    @patch("cardsight_pilot.time.sleep")
    @patch("cardsight_pilot.http.client.HTTPSConnection")
    def test_auth_billing_rate_and_redirect_errors_halt_without_retry(self, connection, _sleep):
        for status in (301, 302, 307, 401, 402, 403, 429):
            with self.subTest(status=status):
                connection.reset_mock()
                response = Mock(status=status)
                response.read.return_value = json.dumps({"error": FAKE_KEY}).encode()
                connection.return_value.getresponse.return_value = response
                pilot = Pilot(FAKE_KEY)
                result = pilot.query({"path": "/v1/subscription/"})
                self.assertNotIn(FAKE_KEY, json.dumps(result))
                with self.assertRaises(ValueError):
                    pilot.query({"path": "/v1/subscription/"})
                connection.assert_called_once()


class CardSightCredentialSafetyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="card-scout-key-test-")
        self.path = Path(self.directory.name) / "test-key"
        self.path.parent.chmod(0o700)

    def tearDown(self):
        self.directory.cleanup()

    def test_saves_private_file_and_does_not_print_secret(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            save_secret(FAKE_KEY, self.path)
        self.assertEqual(stat.S_IMODE(self.path.stat().st_mode), 0o600)
        self.assertEqual(load_key(self.path), FAKE_KEY)
        self.assertNotIn(FAKE_KEY, output.getvalue())

    def test_existing_key_is_never_overwritten(self):
        with contextlib.redirect_stdout(io.StringIO()):
            save_secret(FAKE_KEY, self.path)
        with self.assertRaises(ValueError):
            save_secret("another-fake-card-scout-test-key", self.path)
        self.assertEqual(load_key(self.path), FAKE_KEY)

    def test_refuses_shared_parent_directory(self):
        self.path.parent.chmod(0o755)
        with self.assertRaises(ValueError):
            save_secret(FAKE_KEY, self.path)

    def test_refuses_insecure_file_permissions(self):
        with contextlib.redirect_stdout(io.StringIO()):
            save_secret(FAKE_KEY, self.path)
        self.path.chmod(0o644)
        with self.assertRaises(ValueError):
            load_key(self.path)

    def test_refuses_symlink(self):
        self.path.symlink_to(self.path.parent / "nonexistent")
        with self.assertRaises(ValueError):
            save_secret(FAKE_KEY, self.path)
        with self.assertRaises(OSError):
            load_key(self.path)


if __name__ == "__main__":
    unittest.main()
