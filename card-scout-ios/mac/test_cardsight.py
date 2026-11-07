from copy import deepcopy
import datetime as dt
import json
from http.server import ThreadingHTTPServer
from pathlib import Path
import tempfile
import time
import threading
import unittest
import urllib.error
import urllib.request

from cardsight import (Client, Market, MarketError, PRODUCTS, DAILY_CAP, MONTHLY_CAP,
                       matching_sale, priced_card, sale_url)

TODAY = dt.date(2026, 9, 8)
OPTIC = next(iter(PRODUCTS))


def card(name="CeeDee Lamb", number="9", subset="Downtown", topps=False):
    product = list(PRODUCTS)[int(topps)]
    release, year, title = PRODUCTS[product]
    return {"id": "card-1", "releaseId": release, "releaseName": title, "releaseYear": year,
            "name": name, "number": number, "setId": "set-1", "setName": subset, "attributes": []}


def sale(title="2025 Donruss Optic Downtown CeeDee Lamb #9", price=350, link="https://showme.cards/abcDE"):
    return {"title": title, "price": price, "url": link, "date": "2026-09-02T11:00:01Z",
            "source": "ebay", "listing_type": "auction", "image_url": "https://i.ebayimg.com/images/example.jpg"}


def result(c, records):
    return {"success": True, "card_id": c["id"], "data": {
        "card": {"card_id": c["id"], "set": {"set_id": c["setId"]}},
        "query": {"parallel_id": None, "grade_id": None, "period": "90d", "listing_type": "auction"},
        "raw": {"records": records}}}


class MatchTests(unittest.TestCase):
    def test_observed_misclassified_emoji_and_uncertain_insert_are_not_base(self):
        c = card("Isiah Pacheco", "147", "Base Set")
        for suffix in ["100 Emoji Prizm", "Fire Prizm", "Electricity", "Insert ? SEE SCAN!"]:
            self.assertIsNone(matching_sale(c, sale("2025 Donruss Optic Isiah Pacheco #147 " + suffix), ["Base Set"], TODAY))

    def test_explicit_one_year_window_preserves_exact_variant_and_auction_rules(self):
        old = dict(sale(), date="2026-01-01T12:00:00Z")
        self.assertIsNone(matching_sale(card(), old, ["Downtown"], TODAY))
        self.assertIsNotNone(matching_sale(card(), old, ["Downtown"], TODAY, lookback_days=365))
        for changes in [{"listing_type": "fixed"}, {"title": old["title"] + " Gold /10"}, {"date": "2024-01-01T00:00:00Z"}]:
            self.assertIsNone(matching_sale(card(), dict(old, **changes), ["Downtown"], TODAY, lookback_days=365))
        self.assertIsNone(matching_sale(card(), old, ["Downtown"], TODAY, lookback_days=10000))

    def test_title_search_client_only_allows_bounded_auction_queries(self):
        with tempfile.TemporaryDirectory() as root:
            calls = []
            client = Client(root, lambda *args: (calls.append(args) or 200, {}))
            params = {"q": "2025 Donruss Optic CeeDee Lamb 9", "period": "1y", "listing_type": "auction", "limit": 25}
            client.request("GET", "/v1/pricing/search", params)
            for changes in [{"listing_type": "fixed"}, {"listing_type": "both"}, {"period": "all"}, {"q": "x"}, {"limit": 500}]:
                with self.assertRaises(MarketError): client.request("GET", "/v1/pricing/search", dict(params, **changes))
            self.assertEqual(len(calls), 1)

    def test_downtown_and_prizm_word_are_standard_optic(self):
        c = card()
        for title in [sale()["title"], "Panini 2025 Donruss Optic Downtown Prizm Insert CeeDee Lamb Cowboys #9"]:
            self.assertIsNotNone(matching_sale(c, sale(title), ["Base Set", "Downtown"], TODAY))

    def test_provider_null_parallel_is_not_proof_of_base(self):
        c = card("Josh Allen", "22", "Base Set", True)
        for variant in ["Gold 1869/2026", "Diamante", "Gold 0837/2026", "Gold /2026", "Holo Foil", "/2026", "Parallel"]:
            s = sale("2026 Topps Flagship Football Josh Allen #22 " + variant)
            s["parallel_id"] = None
            self.assertIsNone(matching_sale(c, s, ["Base Set"], TODAY), variant)

    def test_wrong_insert_year_number_player_and_product(self):
        for title in ["2025 Donruss Optic Downtown Duos CeeDee Lamb #9", "2024 Donruss Optic Downtown CeeDee Lamb #9",
                      "2025 Donruss Optic Downtown CeeDee Lamb #19", "2025 Donruss Optic Downtown Travis Hunter #9",
                      "2025 Panini Prizm Downtown CeeDee Lamb #9"]:
            self.assertIsNone(matching_sale(card(), sale(title), ["Downtown", "Downtown Duos"], TODAY))

    def test_grades_lots_asks_bad_condition_and_review_flags(self):
        for suffix in ["PSA 10", "SGC 9", "BGS 9.5", "graded", "Lot", "2x", "READ", "crease", "damaged", "reprint", "Gold", "White Sparkle", "Jumbo", "/10"]:
            self.assertIsNone(matching_sale(card(), sale(sale()["title"] + " " + suffix), ["Downtown"], TODAY), suffix)
        for field, value in [("listing_type", "fixed"), ("grade_id", "psa10"), ("parallel_id", "gold"), ("date", "2026-01-01"), ("date", "2026-09-09"), ("price", True), ("price", float("nan")), ("price", -1)]:
            s = sale(); s[field] = value
            self.assertIsNone(matching_sale(card(), s, ["Downtown"], TODAY), field)

    def test_mendoza_single_sale_and_golden_player_name(self):
        c = card("Fernando Mendoza", "FFS-FM", "Flagship First Signatures", True)
        entry, _ = priced_card(list(PRODUCTS)[1], c, result(c, [sale("2026 Topps Flagship Football Fernando Mendoza Flagship First Signatures #FFS-FM", 791)]), [c["setName"]], TODAY)
        self.assertEqual(entry["priceKind"], "single_sale")
        self.assertEqual(entry["priceCents"], 79100)
        c = card("Matthew Golden", "301", "Base Set", True)
        self.assertIsNotNone(matching_sale(c, sale("2026 Topps Matthew Golden #301"), ["Base Set"], TODAY))

    def test_title_auto_cannot_turn_base_into_auto_and_variants_fail_closed(self):
        c = card("Josh Allen", "22", "Base Set", True)
        self.assertIsNone(matching_sale(c, sale("2026 Topps Josh Allen Auto #22"), ["Base Set"], TODAY))
        for field in ["variationOf", "isParallelOnly"]:
            altered = card(); altered[field] = True
            self.assertIsNone(matching_sale(altered, sale(), ["Downtown"], TODAY))

    def test_product_football_is_not_the_football_parallel(self):
        c = card("Fernando Mendoza", "FFS-FM", "Flagship First Signatures", True)
        title = "2026 Topps Flagship Football Fernando Mendoza Flagship First Signatures #FFS-FM"
        self.assertIsNotNone(matching_sale(c, sale(title), [c["setName"]], TODAY, ["Football"]))
        self.assertIsNone(matching_sale(c, sale(title + " Football"), [c["setName"]], TODAY, ["Football"]))
        c = card("Matthew Golden", "301", "Base Set", True)
        self.assertIsNone(matching_sale(c, sale("2026 Topps Flagship Football Matthew Golden #301 Golden Mirror"), ["Base Set"], TODAY))

    def test_trailing_name_group_pagination_is_complete_without_duplicates(self):
        with tempfile.TemporaryDirectory() as root:
            cs = [{**card(), "id": f"card-{i}", "name": f"Player {i // 7:03}", "number": str(i)} for i in range(230)]
            offsets = []
            def transport(method, path, params, body):
                if path == "/v1/subscription/": return 200, {"calls": 0}
                if path == "/v1/catalog/sets": return 200, {"total_count": 1, "sets": [{"name": "Downtown"}]}
                if path == "/v1/catalog/parallels": return 200, {"total_count": 0, "parallels": []}
                if path == "/v1/catalog/cards":
                    offsets.append(params["skip"])
                    return 200, {"total_count": len(cs), "cards": deepcopy(cs[params["skip"]:params["skip"]+100])}
                return 200, {"results": [result(next(c for c in cs if c["id"] == identity), []) for identity in body["card_ids"]]}
            market = Market(root, Client(root, transport)); snapshot = market.scan(OPTIC)
            self.assertEqual(snapshot["checkedCards"], 230)
            self.assertEqual(offsets, [0, 98, 196])

    def test_deduplication_and_exact_median(self):
        c = card()
        records = [sale(price=p, link="https://showme.cards/abcd" + str(i)) for i, p in enumerate([344, 336.11, 366.60, 385, 350])]
        records += [deepcopy(records[0]), {**records[1], "url": "https://showme.cards/alias"}]
        entry, excluded = priced_card(OPTIC, c, result(c, records), ["Downtown"], TODAY)
        self.assertEqual((entry["priceCents"], entry["saleCount"], excluded), (35000, 5, 2))
        self.assertEqual((entry["saleLowCents"], entry["saleHighCents"]), (33611, 38500))

    def test_wrong_query_or_response_card_is_rejected(self):
        c = card(); r = result(c, [sale()])
        for key, value in [("parallel_id", "gold"), ("grade_id", "psa"), ("period", "all"), ("listing_type", "fixed")]:
            wrong = deepcopy(r); wrong["data"]["query"][key] = value
            self.assertIsNone(priced_card(OPTIC, c, wrong, ["Downtown"], TODAY)[0])
        r["data"]["card"]["set"]["set_id"] = "other"
        self.assertIsNone(priced_card(OPTIC, c, r, ["Downtown"], TODAY)[0])

    def test_links_cannot_leak_credentials_or_hit_private_hosts(self):
        for url in ["http://showme.cards/test", "https://127.0.0.1/test", "https://secret@showme.cards/test", "https://showme.cards.evil.example/test", "https://showme.cards:444/test", "https://www.ebay.com/search?q=test"]:
            self.assertIsNone(sale_url(url))
        self.assertEqual(sale_url("https://www.ebay.com/itm/168632894525?secret=ignored"), "https://www.ebay.com/itm/168632894525")


class IntegrationTests(unittest.TestCase):
    def test_authenticated_market_status_and_refresh_do_not_touch_analysis_queue(self):
        from server import Repository, handler
        with tempfile.TemporaryDirectory() as root:
            repo = Repository(root)
            calls = []
            repo.market.client = Client(root, lambda *args: calls.append(args))
            ready = {"version": 1, "status": "ready", "productID": OPTIC, "revision": "fixture", "expiresAt": time.time()+60, "cards": []}
            repo.market.cache_path(OPTIC).write_text(json.dumps(ready))
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler(repo, "fixture-token"))
            worker = threading.Thread(target=server.serve_forever, daemon=True); worker.start()
            def request(method, auth=True):
                req = urllib.request.Request(f"http://127.0.0.1:{server.server_port}/v1/market/{OPTIC}",
                    headers={"Authorization": "Bearer fixture-token" if auth else "wrong", "Content-Type": "application/json"},
                    method=method, data=b"{}" if method == "POST" else None)
                with urllib.request.urlopen(req, timeout=3) as response: return json.load(response)
            try:
                for method in ["GET", "POST"]:
                    with self.assertRaises(urllib.error.HTTPError) as error: request(method, False)
                    self.assertEqual(error.exception.code, 401); error.exception.close()
                    self.assertEqual(request(method), ready)
                self.assertEqual(calls, [])
                with repo.db() as db: self.assertEqual(db.execute("SELECT count(*) FROM jobs").fetchone()[0], 0)
            finally: server.shutdown(); server.server_close(); worker.join(2)

    def test_corrupt_cache_is_discarded_without_breaking_the_market_endpoint(self):
        with tempfile.TemporaryDirectory() as root:
            market = Market(root, Client(root, lambda *_: (200, {})))
            for bad in ['[]', '{"expiresAt":"never"}', '{bad json']:
                market.cache_path(OPTIC).write_text(bad)
                self.assertEqual(market.status(OPTIC)["status"], "empty")

    def test_durable_quota_and_secret_redaction(self):
        with tempfile.TemporaryDirectory() as root:
            client = Client(root, lambda *_: (200, {"calls": 20, "api_keys": [{"key": "never-expose-me"}]}))
            self.assertEqual(client.request("GET", "/v1/subscription/"), {"calls": 21})
            self.assertNotIn("never-expose-me", client.ledger_path.read_text())
            ledger = client.ledger(); ledger["daily"] = DAILY_CAP
            client.ledger_path.write_text(json.dumps(ledger))
            with self.assertRaises(MarketError): Client(root, client.transport).request("GET", "/v1/subscription/")
            ledger["daily"] = 0; ledger["calls"] = MONTHLY_CAP; client.ledger_path.write_text(json.dumps(ledger))
            with self.assertRaises(MarketError): client.request("GET", "/v1/subscription/")

    def test_quota_auth_redirect_halt_persists_without_retries(self):
        for status in (401, 402, 403, 429, 302):
            with tempfile.TemporaryDirectory() as root:
                calls = []
                def transport(*args): calls.append(args); return status, {}
                client = Client(root, transport)
                with self.assertRaises(MarketError): client.request("GET", "/v1/subscription/")
                with self.assertRaises(MarketError): Client(root, transport).request("GET", "/v1/subscription/")
                self.assertEqual(len(calls), 1)

    def test_expired_provider_views_are_removed_not_owned_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); owned = root / "collections.json"; owned.write_text('["user data"]')
            market = Market(root, Client(root, lambda *_: (200, {})))
            market.cache_path(OPTIC).write_text(json.dumps({"expiresAt": time.time() - 1}))
            self.assertEqual(market.status(OPTIC)["status"], "empty")
            self.assertFalse(market.cache_path(OPTIC).exists())
            self.assertEqual(owned.read_text(), '["user data"]')

    def test_live_page_flow_more_than_ten_without_catalog_copy(self):
        with tempfile.TemporaryDirectory() as root:
            cs = [{**card(), "id": f"card-{i}", "name": f"Player {i}", "number": str(i)} for i in range(1, 31)]
            def transport(method, path, params, body):
                if path == "/v1/subscription/": return 200, {"calls": 0}
                if path == "/v1/catalog/sets": return 200, {"total_count": 1, "sets": [{"name": "Downtown"}]}
                if path == "/v1/catalog/parallels": return 200, {"total_count": 0, "parallels": []}
                if path == "/v1/catalog/cards": return 200, {"total_count": 30, "cards": cs}
                rs = []
                for c in cs:
                    s = sale(f"2025 Donruss Optic Downtown {c['name']} #{c['number']}", 100 + int(c["number"]))
                    s["date"] = dt.datetime.now(dt.timezone.utc).isoformat()
                    rs.append(result(c, [s]))
                return 200, {"results": rs}
            market = Market(root, Client(root, transport)); snapshot = market.scan(OPTIC)
            self.assertEqual(snapshot["checkedCards"], 30)
            self.assertEqual(len(snapshot["cards"]), 30)
            self.assertEqual(snapshot["cards"][0]["priceCents"], 13000)
            self.assertCountEqual(list(Path(root).iterdir()), [Path(root) / "market-cache", Path(root) / "cardsight-usage.json", Path(root) / "cardsight-budget.lock"])


if __name__ == "__main__": unittest.main()
