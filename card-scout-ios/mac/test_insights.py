from copy import deepcopy
import unittest
from analysis import validate_result
from test_pipeline import result


def reference(**changes):
    value = {"provider": "SportsCardsPro", "url": "https://www.sportscardspro.com/game/football-cards-2025-panini-donruss-optic/daunte-culpepper-60", "title": "Daunte Culpepper #60 2025 Panini Donruss Optic", "listingURL": None, "kind": "guide", "grade": "raw", "condition": None, "matchQuality": "exact", "lowCents": 100, "highCents": 300, "currency": "USD", "saleDate": None, "checkedAt": "2026-09-07", "shipping": "excluded"}
    value.update(changes)
    return value


class InsightTests(unittest.TestCase):
    def with_reference(self, **changes):
        value = result()
        value["analysis"]["insights"]["marketReferences"] = [reference(**changes)]
        provider = value["analysis"]["insights"]["marketReferences"][0]["provider"]
        checks = value["analysis"]["insights"]["sourceChecks"]
        if not any(c["provider"] == provider for c in checks): checks.append({"provider": provider, "status": "no_match", "url": None})
        next(c for c in checks if c["provider"] == provider)["status"] = "found"
        return value

    def test_raw_guide_survives_missing_delivery_without_becoming_sold_value(self):
        value = self.with_reference()
        value["analysis"]["needsReview"] = False
        output = validate_result(value, [])["analysis"]
        self.assertIsNone(output["marketLowCents"])
        self.assertEqual(output["insights"]["marketReferences"][0]["lowCents"], 100)
        self.assertFalse(output["needsReview"])

    def test_graded_reference_does_not_value_raw_card(self):
        value = self.with_reference(provider="PSA", url="https://www.psacard.com/auctionprices/fixture", kind="sold", grade="PSA 10", highCents=100, saleDate="2026-09-01", shipping="unknown")
        self.assertIsNone(validate_result(deepcopy(value), [])["analysis"]["marketLowCents"])
        value["analysis"].update(marketLowCents=100, marketHighCents=300)
        with self.assertRaises(ValueError): validate_result(value, [])

    def test_non_official_and_spoofed_provider_urls_rejected(self):
        for url in ("https://psacard.com.evil.test/card", "https://www.beckett.com@evil.test/card", "https://example.com/card", "http://www.beckett.com/card"):
            with self.subTest(url=url), self.assertRaises(ValueError): validate_result(self.with_reference(url=url), [])
        with self.assertRaises(ValueError): validate_result(self.with_reference(provider="PSA"), [])

    def test_unknown_grade_cannot_be_called_raw(self):
        with self.assertRaises(ValueError): validate_result(self.with_reference(grade="unknown"), [])
        with self.assertRaises(ValueError): validate_result(self.with_reference(provider="PSA", url="https://www.psacard.com/card", grade="raw"), [])

    def test_sales_require_real_date_and_single_amount(self):
        for changes in ({"kind": "sold"}, {"kind": "sold", "saleDate": "2026-09-01"}, {"kind": "sold", "saleDate": "2999-01-01", "highCents": 100}):
            with self.subTest(changes=changes), self.assertRaises(ValueError): validate_result(self.with_reference(**changes), [])
        validate_result(self.with_reference(provider="eBay", url="https://www.ebay.de/itm/123456789012", kind="sold", saleDate="2026-09-01", highCents=100, shipping="excluded"), [])

    def test_conditions_only_show_observed_damage(self):
        value = result(); info = value["analysis"]["insights"]
        info["conditionIssues"] = ["Knick oben links."]
        with self.assertRaises(ValueError): validate_result(deepcopy(value), [])
        info["conditionStatus"] = "visible_damage"
        self.assertEqual(validate_result(value, [])["analysis"]["insights"]["conditionIssues"], ["Knick oben links."])

    def test_unusable_photo_does_not_become_clean_condition(self):
        value = result(); info = value["analysis"]["insights"]
        info["conditionStatus"] = "not_assessable"
        info["conditionLimitations"] = ["Karte vollständig verdeckt."]
        value["analysis"]["psa10ChanceLow"] = 90; value["analysis"]["psa10ChanceHigh"] = 95
        with self.assertRaises(ValueError): validate_result(value, [])

    def test_rarity_requires_numbering_evidence(self):
        for tier in ("numbered", "one_of_one"):
            value = result(); value["analysis"]["insights"]["rarityTier"] = tier
            with self.subTest(tier=tier), self.assertRaises(ValueError): validate_result(value, [])
        value = result(); value["analysis"]["serialNumber"] = "1/1"; value["analysis"]["insights"]["rarityTier"] = "one_of_one"
        validate_result(value, [])

    def test_walls_of_text_and_duplicate_source_checks_rejected(self):
        value = result(); value["analysis"]["insights"]["rarityBullets"] = ["x" * 181]
        with self.assertRaises(ValueError): validate_result(value, [])
        value = result(); value["analysis"]["insights"]["sourceChecks"][1]["provider"] = "PSA"
        with self.assertRaises(ValueError): validate_result(value, [])

    def test_paywall_is_not_filled_with_a_made_up_price(self):
        value = self.with_reference()
        value["analysis"]["insights"]["sourceChecks"][0]["status"] = "paywalled"
        with self.assertRaises(ValueError): validate_result(value, [])

    def test_found_status_requires_numeric_reference(self):
        value = result(); value["analysis"]["insights"]["sourceChecks"][0]["status"] = "found"
        with self.assertRaises(ValueError): validate_result(value, [])

    def test_delivered_eur_range_requires_matching_raw_sale_amounts(self):
        value = self.with_reference(provider="eBay", url="https://www.ebay.de/itm/123456789012", kind="sold", saleDate="2026-09-01", highCents=100, currency="EUR", shipping="included")
        value["analysis"].update(marketLowCents=100, marketHighCents=100)
        validate_result(deepcopy(value), [])
        value["analysis"]["marketHighCents"] = 200
        with self.assertRaises(ValueError): validate_result(value, [])


if __name__ == "__main__": unittest.main()
