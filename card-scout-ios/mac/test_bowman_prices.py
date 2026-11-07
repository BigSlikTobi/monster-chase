"""Bowman pricing: exact paper/Chrome families and real catalog page sizes."""
from copy import deepcopy
import datetime as dt
import unittest

from card_prices import eligible
from cardsight import matching_sale
import test_card_prices


class BowmanPriceTests(unittest.TestCase):
    tearDown = test_card_prices.CardPriceTests.tearDown
    transport = test_card_prices.CardPriceTests.transport

    def setUp(self):
        test_card_prices.CardPriceTests.setUp(self)
        self.analysis.update(player="Shedeur Sanders", year=2026, setName="Bowman", subset="Base", cardNumber="25")
        self.card.update(name="Shedeur Sanders", releaseName="Bowman", releaseYear="2026", number="25")
        self.sale.update(title="2026 Bowman Football Shedeur Sanders #25")

    def test_paper_and_chrome_prices_preserve_owned_identity(self):
        before = deepcopy(self.analysis)
        self.assertTrue(eligible(self.analysis))
        self.assertEqual(self.prices.lookup(self.analysis)["status"], "ready")
        self.assertEqual(self.analysis, before)
        self.analysis.update(subset="Chrome Base", cardNumber="BCV-25")
        self.card.update(setName="Chrome", number="BCV-25")
        self.sale.update(title="2026 Bowman Chrome Football Shedeur Sanders #BCV-25")
        self.assertEqual(self.prices.lookup(self.analysis)["status"], "ready")
        self.assertEqual(self.analysis["subset"], "Chrome Base")

    def test_same_number_in_sapphire_or_wrong_subset_does_not_match(self):
        self.analysis.update(subset="Chrome Base", cardNumber="BCV-25")
        self.card.update(setName="Base Set", number="BCV-25", releaseName="Bowman Sapphire")
        self.assertEqual(self.prices.lookup(self.analysis)["reason"], "catalog_not_exact")

    def test_unconfirmed_or_other_bowman_families_remain_unpriced(self):
        for changes in [dict(identityConfirmed=False), dict(confidence="medium"), dict(brand="Panini"),
                        dict(year=2025), dict(subset="Prospect Autographs"), dict(subset="Unknown")]:
            self.assertFalse(eligible(dict(self.analysis, **changes)))

    def test_exact_prospect_catalog_aliases_preserve_paper_and_chrome(self):
        for owned, provider, number, title in [
            ("Paper Prospects", "Prospects", "BPP-72", "2026 Bowman Jaron Tibbs #BPP-72"),
            ("Chrome Prospects", "Chrome Prospects", "BCP-43", "2026 Bowman Chrome Alex Perry #BCP-43")]:
            name = "Jaron Tibbs" if provider == "Prospects" else "Alex Perry"
            self.analysis.update(player=name, subset=owned, cardNumber=number)
            self.card.update(name=name, setName=provider, number=number)
            self.sale.update(title=title)
            self.assertTrue(eligible(self.analysis))
            self.assertEqual(self.prices.lookup(self.analysis)["status"], "ready")
            self.assertEqual(self.analysis["subset"], owned)

    def test_pending_card_replaces_old_scraping_errors_without_network_calls(self):
        incoming = {"analysis": self.analysis}
        before = deepcopy(incoming)
        attached = self.prices.attach(incoming)["analysis"]["insights"]
        self.assertEqual(attached["sourceChecks"][0]["provider"], "CardSight")
        self.assertEqual(attached["sourceChecks"][0]["status"], "not_checked")
        self.assertEqual(incoming, before)
        self.assertEqual(self.calls, [])
        self.analysis.update(identityConfirmed=False, confidence="medium")
        self.assertIn("Kartenidentität", self.prices.attach(incoming)["analysis"]["insights"]["marketBullets"][0])

    def test_bowman_430_variant_rows_are_bounded_and_cached(self):
        requests = []
        def transport(method, path, params, body):
            requests.append((path, params))
            if path == "/v1/catalog/sets": return 200, {"sets": [{"name": "Base Set"}, {"name": "Chrome"}], "total_count": 2}
            offset = params["skip"]
            return 200, {"parallels": [{"name": f"Variant {i}"} for i in range(offset, min(430, offset + 100))], "total_count": 430}
        self.client.transport = transport
        names, variants = self.prices.metadata("bowman")
        self.assertEqual(len(variants), 430)
        self.assertEqual(len(requests), 6)
        self.assertEqual(self.prices.metadata("bowman"), (names, variants))
        self.assertEqual(len(requests), 6)

    def test_oversized_or_incomplete_variant_catalog_is_rejected(self):
        for total, rows in [(1001, []), (430, [{"name": "Gold"}])]:
            def transport(method, path, params, body):
                if path == "/v1/catalog/sets": return 200, {"sets": [], "total_count": 0}
                return 200, {"parallels": rows, "total_count": total}
            self.client.transport = transport
            with self.assertRaises(ValueError): self.prices.metadata("incomplete-bowman")


class BowmanSaleTests(unittest.TestCase):
    def test_exact_paper_and_chrome_sales_reject_wrong_products_variants_and_grades(self):
        today = dt.datetime.now(dt.timezone.utc).date()
        for subset, number, title in [("Base Set", "25", "2026 Bowman Football Shedeur Sanders #25"),
                                       ("Chrome", "BCV-25", "2026 Bowman Chrome Football Shedeur Sanders #BCV-25"),
                                       ("Prospects", "BPP-25", "2026 Bowman Shedeur Sanders #BPP-25"),
                                       ("Chrome Prospects", "BCP-25", "2026 Bowman Chrome Shedeur Sanders #BCP-25")]:
            card = dict(name="Shedeur Sanders", releaseYear="2026", releaseName="Bowman", setName=subset, number=number)
            sale = dict(title=title, price=2.5, date=today.isoformat(), source="ebay", listing_type="auction", url="https://showme.cards/bowmantest")
            self.assertIsNotNone(matching_sale(card, sale, ["Base Set", "Chrome", "Chrome Prospects"], today))
            for suffix in [" Sapphire", " University", " U", " Draft", " Best", " Baseball", " PSA 10", " Refractor", " Gold /50", " Lot"]:
                self.assertIsNone(matching_sale(card, dict(sale, title=title + suffix), ["Base Set", "Chrome"], today), suffix)
            self.assertIsNone(matching_sale(card, dict(sale, listing_type="fixed"), ["Base Set", "Chrome"], today))
            wrong_number = "BPP-25" if number.startswith("BC") else "BCP-25"
            self.assertIsNone(matching_sale(card, dict(sale, title=title.replace(number, wrong_number)), ["Base Set", "Chrome"], today))
        card.update(setName="Base Set", number="25")
        self.assertIsNone(matching_sale(card, dict(sale, title="2026 Bowman Chrome Shedeur Sanders #25"), ["Base Set", "Chrome"], today))


if __name__ == "__main__": unittest.main()
