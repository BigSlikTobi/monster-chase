import datetime as dt
import unittest
from copy import deepcopy

from free_source_pilot import reject_reason, summarize


class SourcePilotTests(unittest.TestCase):
    def setUp(self):
        self.day = dt.date(2026, 10, 16)
        self.card = {"id": "fixture", "name": "Jaxson Dart", "number": "306"}
        self.sale = {"title": "2025 Topps Chrome Jaxson Dart Rookie RC #306 Giants", "source": "ebay", "listing_type": "auction",
                     "url": "https://showme.cards/fixture", "date": "2026-10-13T23:55:33Z", "price": 4.25}

    def test_real_observed_wrong_variants_and_lot_are_rejected(self):
        for title in ("Topps 2025 Topps Chrome Red White & Blue Refractor Jaxson Dart RC #306",
                      "2025 TOPPS CHROME (12) JAXSON DART ROOKIE CARD #306 & INSERTS ! U GET ALL JR",
                      "2025 Topps Chrome Sapphire Jaxson Dart #306", "2025 Topps Chrome Jaxson Dart Silver Refractor RC #306 Giants",
                      "2025 Topps Chrome Jaxson Dart PSA 10 #306", "2025 Topps Chrome Jaxson Dart RC #306 /99"):
            with self.subTest(title=title): self.assertIsNotNone(reject_reason(self.card, dict(self.sale, title=title), self.day))
        self.assertIsNone(reject_reason(self.card, self.sale, self.day))

    def test_asks_missing_dates_links_future_and_wrong_card_are_rejected(self):
        for change in ({"listing_type": "fixed"}, {"date": None}, {"date": "2027-01-01"}, {"url": None},
                       {"title": "2025 Topps Chrome Jaxson Dart #3060"}, {"price": True}, {"price": float('nan')}):
            with self.subTest(change=change): self.assertIsNotNone(reject_reason(self.card, dict(self.sale, **change), self.day))

    def test_duplicate_sales_do_not_inflate_sample_and_median(self):
        result = {"card_id": "fixture", "success": True, "data": {"card": {"card_id": "fixture", "name": "Jaxson Dart", "number": "306",
                  "set": {"name": "Base Set", "release": "Topps Chrome", "year": "2025"}},
                  "query": {"parallel_id": None, "grade_id": None, "period": "90d", "listing_type": "auction"},
                  "raw": {"records": [self.sale, deepcopy(self.sale)]}}}
        summary = summarize(self.card, result, self.day)
        self.assertEqual(summary["accepted"], 1)
        self.assertEqual(summary["medianCents"], 425)
        self.assertEqual(summary["rejected"], {"duplicate": 1})
        self.assertEqual(summary["shipping"], "unknown")
