import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from retrieval import safe_url, VisiblePage, fetch_page, retrieve, evidence_prompt, validate_retrieved_prices
from analysis import run_codex
from test_pipeline import result

URL = "https://www.sportscardspro.com/game/football-cards-2025-topps-chrome/kyle-pitts-14"
IDENTITY = {"player": "Kyle Pitts", "year": 2025, "setName": "Topps Chrome", "cardNumber": "14", "parallel": None}


class RetrievalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()

    def test_rejects_private_urls_credentials_ports_and_unrelated_paths(self):
        for url in ("http://www.ebay.com/itm/123", "https://127.0.0.1/", "https://www.ebay.com.evil.test/itm/123",
                    "https://user@www.ebay.com/itm/123", "https://www.ebay.com:9999/itm/123", "https://www.ebay.com/signin"):
            with self.subTest(url=url), self.assertRaises(ValueError): safe_url(url)
        self.assertEqual(safe_url(URL), URL)

    def test_readable_table_rows_keep_sale_links_and_remove_scripts(self):
        parser = VisiblePage()
        parser.feed('<script>hidden price $999.00</script><h1>Kyle Pitts #14</h1><table><tr><td>2026-10-01</td><td><a href="https://www.ebay.com/itm/123456789012">Sale</a></td><td>$1.25</td></tr></table>')
        text = parser.text()
        self.assertNotIn("999", text)
        self.assertIn("2026-10-01", text)
        self.assertIn("$1.25", text)
        self.assertIn("https://www.ebay.com/itm/123456789012", text)

    def test_cache_reuses_success_and_never_fetches_paid_fallback(self):
        with patch("retrieval.http_fetch", return_value={"status": "ok", "url": URL, "html": "<h1>Kyle Pitts #14</h1><p>Ungraded $1.25</p>"}) as fetch, patch("retrieval.browser_fetch") as browser:
            first = fetch_page(URL, {}, self.root)
            second = fetch_page(URL, {}, self.root)
        self.assertEqual(first, second)
        self.assertEqual(fetch.call_count, 1)
        browser.assert_not_called()

    def test_blocked_browser_page_cannot_become_evidence(self):
        with patch("retrieval.http_fetch", return_value={"status": "blocked", "url": URL}), patch("retrieval.browser_fetch", return_value={"status": "ok", "url": URL, "html": "<h1>Access Denied</h1>"}):
            page = fetch_page(URL, {"retrievalBrowserEnabled": True}, self.root)
        self.assertEqual(page["status"], "blocked")
        self.assertNotIn("text", page)

    def test_discovery_only_follows_real_matching_source_links(self):
        def fetch(url, *args):
            return {"status": "ok", "url": url, "text": "Fixture", "links": [URL, "https://127.0.0.1/game/football-cards-2025-kyle-pitts", URL.replace("kyle-pitts", "other-player")]}
        with patch("retrieval.fetch_page", side_effect=fetch) as fetcher:
            bundle = retrieve(IDENTITY, {}, self.root)
        self.assertEqual(len(bundle["pages"]), 3)
        self.assertEqual(fetcher.call_args_list[-1].args[0], URL)
        self.assertNotIn('"links":', evidence_prompt(bundle))

    def test_missing_identity_does_not_run_broad_search(self):
        with patch("retrieval.fetch_page") as fetch:
            self.assertEqual(retrieve({}, {}, self.root)["reason"], "insufficient_identity")
        fetch.assert_not_called()

    def test_price_requires_readable_page_and_observed_amount_in_full_and_market_contract(self):
        reference = {"url": URL, "kind": "guide", "lowCents": 125, "highCents": 125, "listingURL": None}
        bundle = {"pages": [{"url": URL, "status": "ok", "text": "Ungraded $1.25"}]}
        for value in ({"analysis": {"insights": {"marketReferences": [reference]}}}, {"marketReferences": [reference]}):
            validate_retrieved_prices(value, bundle)
            with self.assertRaises(ValueError): validate_retrieved_prices(value, {"pages": []})
            with self.assertRaises(ValueError): validate_retrieved_prices(value, {"pages": [{"url": URL, "status": "ok", "text": "Ungraded $2.50"}]})

    def test_unbacked_legacy_sale_rejected(self):
        with self.assertRaises(ValueError):
            validate_retrieved_prices({"marketSources": [{"url": URL, "saleDate": "2026-10-01"}]}, {"pages": []})

    def test_retrieval_route_keeps_authorized_sol_and_disables_paid_search(self):
        pending = result()
        (self.root / "identification.json").write_text(json.dumps(pending))
        config = {"retrievalEnabled": True, "model": "gpt-6-luna", "fallbackModel": "gpt-5.6-sol", "webSearch": "live"}
        with patch("retrieval.retrieve", return_value={"pages": []}), patch("analysis._run_model", return_value=pending) as runner:
            run_codex(self.root, [], config)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(runner.call_args_list[0].args[6], "gpt-6-luna")
        self.assertEqual(runner.call_args.args[6], "gpt-5.6-sol")
        self.assertEqual(runner.call_args.args[2]["webSearch"], "disabled")
        self.assertEqual(runner.call_args.args[2]["fallbackModel"], "gpt-5.6-sol")

    def test_retrieval_failure_never_falls_back_to_paid_model_search(self):
        (self.root / "identification.json").write_text(json.dumps(result()))
        with patch("retrieval.retrieve", side_effect=RuntimeError("offline")), patch("analysis._run_model") as runner:
            with self.assertRaises(RuntimeError): run_codex(self.root, [], {"retrievalEnabled": True})
        runner.assert_not_called()
