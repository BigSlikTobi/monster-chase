from copy import deepcopy
import json
import unittest
import tempfile
from analysis import validate_result, merge_market_refresh
from schema import MARKET_FIELDS, MARKET_INSIGHT_FIELDS
from test_pipeline import result, PHOTO, IDENTITY
from server import Repository
from test_insights import reference


def market_result():
    a = result()["analysis"]
    value = {k: a[k] for k in MARKET_FIELDS}
    value.update({k: a["insights"][k] for k in MARKET_INSIGHT_FIELDS})
    value["marketReferences"] = [reference()]
    value["sourceChecks"][0]["status"] = "found"
    return value


class MarketEvidenceTests(unittest.TestCase):
    def test_refresh_accepts_saved_match_routing_without_forwarding_it(self):
        previous = validate_result(result(), [])
        previous.update(matches=[{"collectionID": previous["collection"]["id"], "number": "60"}],
                        matchNotice="catalog")
        before = deepcopy(previous)
        output = merge_market_refresh(previous, market_result(), [])
        self.assertEqual(output["analysis"]["player"], previous["analysis"]["player"])
        self.assertEqual(output["collection"], previous["collection"])
        self.assertNotIn("matches", output)
        self.assertNotIn("matchNotice", output)
        self.assertEqual(previous, before)

    def test_refresh_still_rejects_unexpected_saved_fields(self):
        for extra in ({"unexpected": True}, {"analysis": {"unexpected": True}}):
            previous = validate_result(result(), [])
            if "analysis" in extra:
                previous["analysis"].update(extra["analysis"])
            else:
                previous.update(extra)
            with self.assertRaises(ValueError):
                merge_market_refresh(previous, market_result(), [])

    def test_sportscardspro_guide_works_when_ebay_is_unavailable(self):
        previous = validate_result(result(), [])
        output = merge_market_refresh(previous, market_result(), [])
        self.assertEqual(output["analysis"]["insights"]["marketReferences"][0]["provider"], "SportsCardsPro")
        self.assertIsNone(output["analysis"]["marketLowCents"])

    def test_refresh_preserves_identity_condition_and_binder(self):
        previous = validate_result(result(), [])
        before = deepcopy(previous)
        output = merge_market_refresh(previous, market_result(), [])
        for key in ("player", "parallel", "serialNumber", "collectionID", "conditionNotes", "licenseScope"):
            self.assertEqual(output["analysis"][key], before["analysis"][key])
        for key in ("rarityTier", "rarityBullets", "conditionStatus", "conditionIssues", "conditionLimitations"):
            self.assertEqual(output["analysis"]["insights"][key], before["analysis"]["insights"][key])
        self.assertEqual(previous, before)

    def test_market_only_contract_cannot_change_identity(self):
        value = market_result(); value["player"] = "Another Player"
        with self.assertRaises(ValueError): merge_market_refresh(validate_result(result(), []), value, [])

    def test_aggregated_sale_requires_real_underlying_item_and_excludes_shipping(self):
        value = market_result()
        sale = reference(kind="sold", saleDate="2026-09-01", highCents=100, listingURL="https://www.ebay.com/itm/card-title/123456789012?tracking=1")
        value["marketReferences"] = [sale]
        merge_market_refresh(validate_result(result(), []), value, [])
        for changes in ({"listingURL": None}, {"listingURL": "https://ebay.com.evil.test/itm/123456789012"}, {"listingURL": "https://www.ebay.com/sch/i.html"}, {"shipping": "included"}):
            bad = deepcopy(value); bad["marketReferences"][0].update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError): merge_market_refresh(validate_result(result(), []), bad, [])

    def test_same_sale_cannot_be_counted_again_from_ebay(self):
        value = market_result()
        value["sourceChecks"][1]["status"] = "found"
        value["marketReferences"] += [reference(kind="sold", highCents=100, saleDate="2026-09-01", listingURL="https://www.ebay.com/itm/123456789012"),
                                      reference(provider="eBay", url="https://www.ebay.de/itm/title/123456789012?foo=bar", kind="sold", highCents=100, saleDate="2026-09-01")]
        with self.assertRaises(ValueError): merge_market_refresh(validate_result(result(), []), value, [])

    def test_ebay_cannot_supply_guide_or_search_page_as_sold(self):
        for changes in ({"kind": "guide"}, {"url": "https://www.ebay.com/sch/i.html?LH_Sold=1"}):
            value = market_result(); value["sourceChecks"][0]["status"] = "no_match"; value["sourceChecks"][1]["status"] = "found"
            sale = reference(provider="eBay", url="https://www.ebay.com/itm/123456789012", kind="sold", saleDate="2026-09-01", highCents=100)
            sale.update(changes); value["marketReferences"] = [sale]
            with self.assertRaises(ValueError): merge_market_refresh(validate_result(result(), []), value, [])

    def test_extrapolated_graded_prices_and_stale_sales_are_rejected(self):
        for changes in ({"grade": "PSA 10"}, {"kind": "sold", "saleDate": "2024-01-01", "highCents": 100, "listingURL": "https://www.ebay.com/itm/123456789012"}):
            value = market_result(); value["marketReferences"][0].update(changes)
            with self.assertRaises(ValueError): merge_market_refresh(validate_result(result(), []), value, [])


class MarketRefreshQueueTests(unittest.TestCase):
    def setUp(self): self.temp = tempfile.TemporaryDirectory(); self.repo = Repository(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def submit(self): return self.repo.submit({"id": IDENTITY, "front": PHOTO})
    def test_identical_photos_reuse_only_server_owned_assessment(self):
        self.submit(); previous = validate_result(result(), [])
        previous.update(matches=[], matchNotice="catalog")
        self.repo.finish(IDENTITY, previous); self.repo.ack(IDENTITY)
        new_id = "33333333-3333-4333-a333-333333333333"
        self.repo.submit({"id": new_id, "front": PHOTO, "refreshOf": IDENTITY, "analysis": {"player": "Fake player"}})
        saved = json.loads((self.repo.jobroot / new_id / "refresh.json").read_text())
        self.assertEqual(saved, previous)
        self.repo.finish(new_id, merge_market_refresh(saved, market_result(), [])); self.repo.ack(new_id)
        self.assertFalse((self.repo.jobroot / new_id / "refresh.json").exists())

    def test_different_or_unknown_photos_fall_back_to_full_analysis(self):
        self.submit(); self.repo.finish(IDENTITY, validate_result(result(), []))
        new_id = "33333333-3333-4333-a333-333333333333"
        self.repo.submit({"id": new_id, "front": PHOTO, "back": PHOTO, "refreshOf": IDENTITY})
        self.assertFalse((self.repo.jobroot / new_id / "refresh.json").exists())

    def test_unconfirmed_identity_must_be_reidentified(self):
        self.submit(); r = result(); r["analysis"]["identityConfirmed"] = False; self.repo.finish(IDENTITY, validate_result(r, []))
        new_id = "33333333-3333-4333-a333-333333333333"
        self.repo.submit({"id": new_id, "front": PHOTO, "refreshOf": IDENTITY})
        self.assertFalse((self.repo.jobroot / new_id / "refresh.json").exists())


if __name__ == "__main__": unittest.main()
