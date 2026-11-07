from copy import deepcopy
import datetime as dt
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from card_prices import PriceResearch, identity_key, eligible
from cardsight import Client, MONTHLY_CAP, atomic
from server import Repository
from test_pipeline import result, IDENTITY
from analysis import run_codex


class KnownPrintTierTests(unittest.TestCase):
    def test_orange_scope_is_not_plain_orange(self):
        a = dict(player="Derrick Harmon", year=2025, brand="Panini", setName="Donruss Optic",
                 subset="Base", cardNumber="257", parallel="Orange", serialNumber="20/79",
                 identityConfirmed=True, confidence="high")
        self.assertFalse(eligible(a))
        self.assertTrue(eligible(dict(a, parallel="Orange Scope")))
        self.assertFalse(eligible(dict(a, parallel="Orange Scope", serialNumber=None)))


class CardPriceTests(unittest.TestCase):
    def test_confirmed_card_does_not_need_licensing_metadata_for_an_estimate(self):
        a = dict(player="Player", year=2025, brand="Panini", setName="Select", subset="Base",
                 cardNumber="12", identityConfirmed=True, confidence="high", licenseScope="unknown")
        self.assertTrue(eligible(a))
        self.assertFalse(eligible(dict(a, identityConfirmed=False)))
        self.assertFalse(eligible(dict(a, parallel="unknown")))

    def setUp(self):
        mock_guides = patch("raw_guides.fetch_guide", return_value=None)
        mock_guides.start(); self.addCleanup(mock_guides.stop)
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.analysis = result()["analysis"]
        self.analysis.update(player="Terrance Ferguson", year=2025, brand="Topps", setName="Topps Chrome", subset="Base", cardNumber="335",
                             confidence="high", identityConfirmed=True, licenseScope="nfl_and_nflpa")
        self.card = {"id": "fixture", "name": "Terrance Ferguson", "number": "335", "setName": "Base Set", "setId": "base",
                     "releaseName": "Topps Chrome", "releaseYear": "2025", "releaseId": "release"}
        self.sale = {"title": "2025 Topps Chrome Terrance Ferguson Rookie #335", "price": 0.71, "date": dt.datetime.now(dt.timezone.utc).isoformat(),
                     "source": "ebay", "listing_type": "auction", "url": "https://showme.cards/testrecord"}
        self.records = [self.sale]
        self.calls = []
        self.client = Client(self.root, self.transport)
        self.prices = PriceResearch(self.root, self.client)

    def tearDown(self): self.prices.executor.shutdown(wait=True); self.tmp.cleanup()

    def transport(self, method, path, params, body):
        self.calls.append(path)
        if path == "/v1/subscription/": return 200, {"calls": 0}
        if path == "/v1/catalog/cards": return 200, {"cards": [self.card], "total_count": 1}
        if path == "/v1/catalog/sets": return 200, {"sets": [{"name": "Base Set"}], "total_count": 1}
        if path == "/v1/catalog/parallels": return 200, {"parallels": [], "total_count": 0}
        if path == "/v1/pricing/search": return 200, {"query": params, "results": self.records}
        return 200, {"results": [{"card_id": "fixture", "success": True, "data": {"query": {"parallel_id": None, "grade_id": None,
             "period": body["period"], "listing_type": "auction"}, "card": {"card_id": "fixture", "set": {"set_id": "base"}}, "raw": {"records": self.records}}}]}

    def test_prices_are_attributed_cached_and_expire_without_changing_identity(self):
        value = self.prices.lookup(self.analysis)
        self.assertEqual(value["status"], "ready")
        ref = value["references"][0]
        self.assertEqual((ref["provider"], ref["lowCents"], ref["shipping"]), ("CardSight", 71, "unknown"))
        self.assertIsNone(ref["condition"])
        self.assertEqual(self.prices.lookup(self.analysis), value)
        self.assertEqual(len(self.calls), 5)
        with patch("card_prices.time.time", return_value=value["expiresAt"] + 1):
            self.assertIsNone(self.prices.cached(self.analysis))
            self.prices.purge()
        self.assertFalse(list(self.prices.cache.glob("*.json")))

    def test_old_exact_auction_is_explicitly_labelled_and_only_used_when_recent_missing(self):
        self.records = [dict(self.sale, date=(dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=140)).isoformat())]
        value = self.prices.lookup(self.analysis)
        self.assertEqual((value["status"], value["periodDays"]), ("ready", 365))
        self.assertNotIn("/v1/pricing/search", self.calls)
        attached = self.prices.attach({"analysis": self.analysis})
        self.assertTrue(any("12 Monate" in b for b in attached["analysis"]["insights"]["marketBullets"]))

    def test_title_search_recovers_exact_unlinked_sales_but_rejects_conflicting_context_and_grades(self):
        original = self.transport
        def transport(method, path, params, body):
            if path == "/v1/pricing/search":
                self.calls.append(path)
                return 200, {"query": params, "results": [self.sale,
                    dict(self.sale, url="https://showme.cards/wrongcard", matched_card={"card_id": "other", "set": {"set_id": "base"}}),
                    dict(self.sale, url="https://showme.cards/wrongset", matched_card={"card_id": "fixture", "set": {"set_id": "other"}}),
                    dict(self.sale, url="https://showme.cards/gradedrecord", grade={"grade_id": "psa10"}),
                    dict(self.sale, url="https://showme.cards/wrongfinish", title=self.sale["title"] + " 100 Emoji"),
                    dict(self.sale, url="https://showme.cards/askingprice", listing_type="fixed")]}
            status, value = original(method, path, params, body)
            if method == "POST": value["results"][0]["data"]["raw"]["records"] = []
            return status, value
        self.client.transport = transport
        value = self.prices.lookup(self.analysis)
        self.assertEqual((value["status"], len(value["references"]), value["periodDays"]), ("ready", 1, 90))
        self.assertEqual(self.calls.count("/v1/pricing/search"), 1)

    def test_no_exact_sales_is_distinct_from_catalog_absence_and_schema_failure(self):
        self.records = [dict(self.sale, title=self.sale["title"] + " Insert ? SEE SCAN!")]
        value = self.prices.lookup(self.analysis)
        self.assertEqual((value["status"], value["reason"]), ("no_match", "no_exact_sales"))
        self.assertEqual(self.prices.lookup(self.analysis), value)
        self.assertEqual(self.calls.count("/v1/pricing/search"), 1)

    def test_bad_search_filters_are_not_reported_as_no_sales(self):
        original = self.transport
        self.records = []
        def transport(method, path, params, body):
            if path == "/v1/pricing/search": return 200, {"query": dict(params, listing_type="both"), "results": []}
            return original(method, path, params, body)
        self.client.transport = transport
        value = self.prices.lookup(self.analysis)
        self.assertEqual((value["status"], value["reason"]), ("unavailable", "invalid_response"))

    def test_title_search_numbered_parallel_still_requires_exact_finish_and_tier(self):
        original = self.variant_transport()
        def transport(method, path, params, body):
            if path == "/v1/pricing/search":
                self.calls.append(path)
                records = [dict(self.sale, title=self.sale["title"] + suffix, url="https://showme.cards/" + key)
                           for suffix, key in [(" Gold Refractor /50", "exactgold"), (" Gold Refractor /99", "wrongtier"),
                                               (" Gold Wave Refractor /50", "wrongfinish"), ("", "baseprice")]]
                return 200, {"query": params, "results": records}
            status, value = original(method, path, params, body)
            if method == "POST": value["results"][0]["data"]["raw"]["records"] = []
            return status, value
        self.client.transport = transport
        value = self.prices.lookup(dict(self.analysis, parallel="Gold Refractor", serialNumber="1/50"))
        self.assertEqual((value["status"], len(value["references"])), ("ready", 1))
        self.assertEqual(value["references"][0]["url"], "https://showme.cards/exactgold")
        self.assertEqual(self.calls.count("/v1/pricing/search"), 1)

    def test_catalog_absence_is_not_silently_bypassed_by_title_search(self):
        self.card["setName"] = "Other Insert"
        value = self.prices.lookup(self.analysis)
        self.assertEqual((value["status"], value["reason"]), ("no_match", "catalog_not_exact"))
        self.assertNotIn("/v1/pricing/search", self.calls)

    def test_catalog_subset_punctuation_is_not_a_different_insert(self):
        self.analysis["subset"] = "All-Chrome Team"
        self.card["setName"] = "All Chrome Team"
        self.records = [dict(self.sale, title="2025 Topps Chrome All Chrome Team Terrance Ferguson #335")]
        value = self.prices.lookup(self.analysis)
        self.assertEqual(value["status"], "ready")
        self.assertEqual(len(value["references"]), 1)

    def test_only_old_catalog_failure_is_invalidated_by_subset_match_repair(self):
        path = self.prices.cache / (identity_key(self.analysis) + ".json")
        value = {"key": identity_key(self.analysis), "matcherVersion": 4, "expiresAt": time.time() + 80000,
                 "status": "no_match", "reason": "catalog_not_exact", "references": []}
        atomic(path, value)
        self.assertIsNone(self.prices.cached(self.analysis))
        atomic(path, dict(value, reason="no_exact_sales"))
        self.assertEqual(self.prices.cached(self.analysis)["reason"], "no_exact_sales")

    def test_pilot_daily_stop_does_not_block_unused_monthly_budget(self):
        ledger = self.client.ledger(); ledger.update(calls=300, daily=270)
        atomic(self.client.ledger_path, ledger)
        self.client.request("GET", "/v1/catalog/cards")
        self.assertEqual(self.client.ledger()["calls"], 301)
        ledger = self.client.ledger(); ledger["calls"] = 720
        atomic(self.client.ledger_path, ledger)
        with self.assertRaises(RuntimeError): self.client.request("GET", "/v1/catalog/cards")

    def test_old_negative_cache_does_not_hide_improved_lookup(self):
        atomic(self.prices.cache / (identity_key(self.analysis) + ".json"), {"key": identity_key(self.analysis), "matcherVersion": 3,
               "expiresAt": time.time() + 80000, "status": "no_match", "references": []})
        self.assertEqual(self.prices.lookup(self.analysis)["status"], "ready")

    def test_unknown_identity_or_serial_without_named_variant_never_queries(self):
        for changes in ({"identityConfirmed": False}, {"cardNumber": None}, {"parallel": "unbekannt"}, {"serialNumber": "1/99"}, {"confidence": "medium"}):
            self.assertIsNone(self.prices.lookup(dict(self.analysis, **changes)))
        self.assertEqual(self.calls, [])

    def test_misclassified_parallels_lots_and_duplicates_are_rejected(self):
        self.records += [dict(self.sale, title=self.sale["title"] + " Red Refractor", url="https://showme.cards/parallel"),
                         dict(self.sale, title="2025 TOPPS CHROME (12) TERRANCE FERGUSON ROOKIE CARDS #335 U GET ALL", url="https://showme.cards/lot"),
                         deepcopy(self.sale)]
        self.assertEqual(len(self.prices.lookup(self.analysis)["references"]), 1)

    def test_repeated_brand_is_not_a_named_refractor(self):
        from cardsight import matching_sale
        title = "Topps 2025 Topps Chrome Terrance Ferguson Los Angeles Rams #335 Rookie RC"
        matched = matching_sale(self.card, dict(self.sale, title=title), ["Base Set"], dt.datetime.now(dt.timezone.utc).date(), ["Topps Refractor"])
        self.assertIsNotNone(matched)
        self.assertIsNone(matching_sale(self.card, dict(self.sale, title=title + " Topps Refractor"), ["Base Set"], dt.datetime.now(dt.timezone.utc).date(), ["Topps Refractor"]))

    def test_exact_numbered_finish_and_print_tier_required_in_sale_title(self):
        from card_prices import matching_variant_sale
        variant = {"id": "00000000-0000-4000-8000-000000000001", "name": "Gold Refractor"}
        names = ["Gold Refractor", "Gold Wave Refractor", "Football Leather Gold Refractor"]
        def match(suffix, **fields):
            return matching_variant_sale(self.card, dict(self.sale, title=self.sale["title"] + " " + suffix, **fields), variant, 50, ["Base Set"], dt.datetime.now(dt.timezone.utc).date(), names)
        self.assertIsNotNone(match("Gold Refractor 17/50"))
        self.assertIsNotNone(match("Gold Refractor /50"))
        for suffix in ["Gold Refractor /99", "Gold Wave Refractor /50", "Gold Refractor", "Gold /50", "Gold Refractor 0/50",
                       "Football Leather Gold Refractor /50", "Gold Refractor /50 PSA 10", "Gold Refractor /50 Lot"]:
            with self.subTest(suffix=suffix): self.assertIsNone(match(suffix))
        self.assertIsNone(match("Gold Refractor /50", parallel_id="00000000-0000-4000-8000-000000000002"))

    def test_lightboard_descriptor_alias_never_becomes_other_variation(self):
        from card_prices import matching_variant_sale
        variant = {"id": "00000000-0000-4000-8000-000000000001", "name": "Lightboard Logo Variations"}
        day = dt.datetime.now(dt.timezone.utc).date()
        def match(suffix):
            return matching_variant_sale(self.card, dict(self.sale, title=self.sale["title"] + " " + suffix), variant, None, ["Base Set"], day, ["Lightboard Logo Variations", "Refractor"])
        self.assertIsNotNone(match("Lightboard Logo Variation"))
        self.assertIsNone(match("Image Variation"))
        self.assertIsNone(match("Lightboard Logo Refractor"))
        self.assertIsNone(match("Lightboard Logo /50"))

    def variant_transport(self, numbered_to=50):
        original = self.transport
        variant_id = "00000000-0000-4000-8000-000000000001"
        def transport(method, path, params, body):
            if path == "/v1/catalog/parallels":
                self.calls.append(path)
                row = {"id": variant_id, "name": "Gold Refractor", "setId": "base", "releaseId": "release", "numberedTo": numbered_to}
                return 200, {"parallels": [row, dict(row, id="00000000-0000-4000-8000-000000000002", setId="other-insert")], "total_count": 2}
            status, data = original(method, path, params, body)
            if method == "POST":
                d = data["results"][0]["data"]
                d["query"]["parallel_id"] = body["parallel_id"]
                if body["parallel_id"]:
                    d["card"]["parallel"] = {"parallel_id": body["parallel_id"]}
                    d["raw"]["records"] = [dict(self.sale, title=self.sale["title"] + " Gold Refractor 17/50")]
                else:
                    d["raw"]["records"] = [self.sale, dict(self.sale, title=self.sale["title"] + " Gold Refractor /99", url="https://showme.cards/wrongtier")]
            return status, data
        return transport

    def test_variant_lookup_uses_exact_uuid_and_never_substitutes_base_price(self):
        self.client.transport = self.variant_transport()
        a = dict(self.analysis, parallel="Gold Refractor", serialNumber="1/50")
        value = self.prices.lookup(a)
        self.assertEqual(value["status"], "ready")
        self.assertEqual(len(value["references"]), 1)
        self.assertIn("17/50", value["references"][0]["title"])
        self.assertEqual(self.calls.count("/v1/pricing/"), 2)
        self.assertEqual(self.prices.lookup(a), value)
        self.assertEqual(self.calls.count("/v1/pricing/"), 2)

    def rookie_hyper_transport(self):
        self.analysis.update(player="Trey Amos", setName="Donruss Optic", brand="Panini", cardNumber="267", rookie=True, parallel="Blue Hyper")
        self.card.update(name="Trey Amos", number="267", releaseName="Donruss Optic", attributes=["RC"])
        self.sale["title"] = "2025 Donruss Optic Trey Amos Rated Rookie #267 Blue Hyper"
        original = self.transport
        variant_id = "00000000-0000-4000-8000-000000000001"
        def transport(method, path, params, body):
            if path == "/v1/catalog/parallels":
                self.calls.append(path)
                row = dict(id=variant_id, name="Rated Rookie Blue Hyper", setId="base", releaseId="release", numberedTo=None)
                return 200, {"total_count": 2, "parallels": [row, dict(row, id="other", name="Blue Hyper", setId="other")]}
            status, data = original(method, path, params, body)
            if method == "POST":
                d = data["results"][0]["data"]; d["query"]["parallel_id"] = body["parallel_id"]
                if body["parallel_id"]: d["card"]["parallel"] = {"parallel_id": body["parallel_id"]}
            return status, data
        return transport

    def test_observed_rated_rookie_blue_hyper_label_uses_exact_same_set_uuid(self):
        self.client.transport = self.rookie_hyper_transport()
        value = self.prices.lookup(self.analysis)
        self.assertEqual(value["status"], "ready")
        self.assertEqual(len(value["references"]), 1)
        self.assertEqual(value["references"][0]["title"], self.sale["title"])

    def test_rookie_blue_hyper_alias_needs_both_owned_and_catalog_rookie_proof(self):
        self.client.transport = self.rookie_hyper_transport()
        self.analysis["rookie"] = False
        self.assertEqual(self.prices.lookup(self.analysis)["reason"], "variant_not_exact")
        self.analysis["rookie"] = True; self.card["attributes"] = []
        (self.prices.cache / (identity_key(self.analysis) + ".json")).unlink()
        self.assertEqual(self.prices.lookup(self.analysis)["reason"], "variant_not_exact")

    def test_rookie_blue_hyper_alias_never_accepts_wrong_finish(self):
        self.client.transport = self.rookie_hyper_transport()
        self.sale["title"] = self.sale["title"].replace("Blue Hyper", "Green Hyper")
        self.assertEqual(self.prices.lookup(self.analysis)["status"], "no_match")

    def test_observed_rated_rookie_purple_shock_descriptor_keeps_the_exact_finish(self):
        original = self.rookie_hyper_transport()
        self.analysis['parallel'] = 'Purple Shock'
        self.sale['title'] = self.sale['title'].replace('Blue Hyper','Purple Shock')
        def transport(method,path,params,body):
            status,data = original(method,path,params,body)
            if path == '/v1/catalog/parallels':
                for row in data['parallels']:row['name'] = row['name'].replace('Blue Hyper','Purple Shock')
            return status,data
        self.client.transport = transport
        self.assertEqual(self.prices.lookup(self.analysis)['status'],'ready')

    def test_parallel_resolution_reads_bounded_later_pages_for_the_exact_set(self):
        original = self.variant_transport()
        pages = []
        def transport(method, path, params, body):
            if path == "/v1/catalog/parallels" and params.get("name"):
                skip = params.get("skip", 0); pages.append(skip)
                rows = [{"id": f"00000000-0000-4000-8000-{i:012d}", "name": "Gold Refractor", "setId": "base" if i == 150 else "other",
                         "releaseId": "release", "numberedTo": 50} for i in range(skip, min(skip + 100, 272))]
                return 200, {"total_count": 272, "parallels": rows}
            status, value = original(method, path, params, body)
            if method == "POST" and body.get("parallel_id"):
                value["results"][0]["data"]["card"]["parallel"]["parallel_id"] = body["parallel_id"]
            return status, value
        self.client.transport = transport
        a = dict(self.analysis, parallel="Gold Refractor", serialNumber="1/50")
        value = self.prices.lookup(a)
        self.assertEqual(value["status"], "ready")
        self.assertEqual(pages, [0, 100, 200])
        self.assertEqual(len(value["references"]), 1)
        self.assertEqual(self.prices.lookup(a), value)
        self.assertEqual(self.calls.count("/v1/pricing/"), 2)

    def test_missing_or_wrong_numbered_tier_stops_before_prices(self):
        self.client.transport = self.variant_transport()
        for serial in [None, "1/99"]:
            value = self.prices.lookup(dict(self.analysis, parallel="Gold Refractor", serialNumber=serial))
            self.assertEqual(value["status"], "no_match")
        self.assertNotIn("/v1/pricing/", self.calls)

    def test_quota_is_hard_and_cached_failure_does_not_retry(self):
        ledger = self.client.ledger(); ledger["calls"] = MONTHLY_CAP
        atomic(self.client.ledger_path, ledger)
        value = self.prices.lookup(self.analysis)
        self.assertEqual(value["status"], "unavailable")
        self.assertEqual(self.calls, [])
        self.prices.lookup(self.analysis)
        self.assertEqual(self.calls, [])

    def test_provider_quota_error_stops_before_catalog_or_pricing(self):
        self.client.transport = lambda *args: (429, {})
        self.assertEqual(self.prices.lookup(self.analysis)["status"], "unavailable")
        self.assertEqual(self.client.ledger()["calls"], 1)
        self.assertGreater(self.client.ledger()["haltUntil"], time.time())

    def test_response_overlay_never_enters_queue_database(self):
        (self.root / "config.json").write_text(json.dumps({"cardSightResearchEnabled": True}))
        repo = Repository(self.root)
        repo.card_prices = self.prices
        repo.submit({"id": IDENTITY, "front": __import__("test_pipeline").PHOTO})
        base = result(); base["analysis"] = self.analysis
        self.prices.lookup(self.analysis)
        repo.finish(IDENTITY, base)
        self.assertEqual(repo.get(IDENTITY)["analysis"]["insights"]["marketReferences"][0]["provider"], "CardSight")
        with repo.db() as db: saved = db.execute("select result from jobs where id=?", (IDENTITY,)).fetchone()[0]
        self.assertNotIn("testrecord", saved)
        self.assertNotIn('"provider": "CardSight"', saved)

    def test_changed_identity_cannot_receive_cached_price(self):
        self.prices.lookup(self.analysis)
        changed = dict(self.analysis, cardNumber="336")
        self.assertNotEqual(identity_key(changed), identity_key(self.analysis))
        self.assertIsNone(self.prices.cached(changed))

    def test_parallel_vocabulary_spans_pages_and_is_reused(self):
        calls = []
        def transport(method, path, params, body):
            calls.append((path, params))
            if path == "/v1/catalog/sets": return 200, {"sets": [{"name": "Base Set"}], "total_count": 1}
            offset = params.get("skip", 0)
            return 200, {"parallels": [{"name": f"Variant {i}"} for i in range(offset, min(327, offset + 100))], "total_count": 327}
        self.client.transport = transport
        names, variants = self.prices.metadata("release")
        self.assertEqual(len(variants), 327)
        self.assertEqual(len(calls), 5)
        self.assertEqual(self.prices.metadata("release"), (names, variants))
        self.assertEqual(len(calls), 5)

    def test_multiple_clients_cannot_overspend_last_free_request(self):
        self.assertEqual(MONTHLY_CAP, 720)
        ledger = self.client.ledger(); ledger["calls"] = MONTHLY_CAP - 1
        atomic(self.client.ledger_path, ledger)
        clients = [Client(self.root, self.transport), Client(self.root, self.transport)]
        def attempt(client):
            try: client.request("GET", "/v1/catalog/cards")
            except RuntimeError: pass
        threads = [threading.Thread(target=attempt, args=(c,)) for c in clients]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(len(self.calls), 1)
        self.assertEqual(self.client.ledger()["calls"], MONTHLY_CAP)

    def test_luna_route_has_no_browsing_but_keeps_authorized_sol_escalation(self):
        from analysis import validate_result
        with patch("analysis._run_model", return_value=validate_result(result(), [])) as model, patch("retrieval.retrieve") as browse:
            run_codex(self.root, [], {"model": "gpt-6-luna", "apiEnabled": True, "cardSightResearchEnabled": True, "fallbackModel": "gpt-5.6-sol"})
        browse.assert_not_called()
        self.assertEqual(model.call_count, 1)
        self.assertEqual(model.call_args.args[2]["webSearch"], "disabled")
        self.assertEqual(model.call_args.args[2]["fallbackModel"], "gpt-5.6-sol")
