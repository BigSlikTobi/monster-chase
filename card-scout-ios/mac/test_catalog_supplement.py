from copy import deepcopy
import json
from pathlib import Path
import unittest
from catalog_supplement import merge
from import_chrome_checklist import parse, SECTIONS


class CatalogSupplementTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads((Path(__file__).parent / "data/chrome-checklist-supplement.json").read_text())

    def test_complete_explicit_membership_and_repeat_merge(self):
        catalog, report = merge([], self.source)
        self.assertEqual((report["addedCollections"], report["addedRows"]), (22, 1789))
        camo = next(c for c in catalog if c["parallel"] == "Team Camo Variation")
        self.assertEqual(len(camo["cards"]), 396)
        base = next(c for c in catalog if c["subset"] == "Base" and c["parallel"] is None)
        self.assertEqual(len(base["cards"]), 400)
        self.assertEqual(sum(r["rookie"] for r in base["cards"]), 100)
        self.assertEqual(merge(catalog, self.source)[1]["addedRows"], 0)

    def test_conflicts_do_not_rewrite_existing_rows(self):
        old = deepcopy(self.source["collections"][0]); old["cards"][0]["player"] = "Different Player"
        result, report = merge([old], self.source)
        self.assertEqual(result[0], old)
        self.assertTrue(report["conflicts"])
        self.assertEqual(old["cards"][0]["player"], "Different Player")

    def test_partial_checklist_expands_without_losing_reference_data(self):
        old = deepcopy(self.source["collections"][0]); old["cards"] = old["cards"][:1]
        old["cards"][0]["imageURL"] = "https://example.com/reviewed.jpg"
        old["checklistComplete"] = False
        result, report = merge([old], self.source)
        self.assertEqual(len(result[0]["cards"]), 400)
        self.assertTrue(result[0]["checklistComplete"])
        self.assertEqual(result[0]["cards"][0]["imageURL"], old["cards"][0]["imageURL"])
        self.assertGreater(report["addedRows"], 0)

    def test_changed_edition_or_missing_sections_fail(self):
        changed = deepcopy(self.source); changed["sourceSHA256"] = "0" * 64
        with self.assertRaises(ValueError): merge([], changed)
        with self.assertRaises(ValueError): parse("BASE CARDS\n1 Player  Team\nAUTOGRAPH", "2026-10-20")

    def test_optic_scope_has_explicit_membership_and_is_separate_from_orange(self):
        source = json.loads((Path(__file__).parent / "data/optic-checklist-supplement.json").read_text())
        catalog, report = merge([], source)
        self.assertEqual(report["addedRows"], 300)
        self.assertEqual(catalog[0]["parallel"], "Orange Scope")
        self.assertEqual(next(r["player"] for r in catalog[0]["cards"] if r["number"] == "257"), "Derrick Harmon")
        changed = deepcopy(source); changed["collections"][0]["parallel"] = "Orange"
        with self.assertRaises(ValueError): merge([], changed)
