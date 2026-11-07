from copy import deepcopy
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from analysis import validate_identification, validate_result, local_identity_excerpts, identity_conflict
from catalog_supplement import merge
from import_bowman_checklist import parse, SECTIONS
from scan_matches import candidates
from server import Repository
from test_fast_capture import identity
from test_pipeline import result


class BowmanTests(unittest.TestCase):
    def setUp(self):
        self.path = Path(__file__).parent / "data/bowman-checklist-supplement.json"
        self.source = json.loads(self.path.read_text())
        self.catalog, self.report = merge([], self.source)

    def test_source_conflict_is_quarantined_without_guessing_number(self):
        paper, chrome, prospects, chrome_prospects = self.catalog
        self.assertEqual(self.report["addedRows"], 800)
        for c in (prospects, chrome_prospects):
            self.assertEqual(len(c["cards"]), 201)
            self.assertTrue(c["checklistComplete"])
        self.assertEqual(len(self.source["conflicts"]), 2)
        self.assertFalse(paper["checklistComplete"])
        self.assertEqual(paper["expectedCount"], 200)
        self.assertFalse({"66", "68"} & {r["number"] for r in paper["cards"]})
        self.assertTrue(chrome["checklistComplete"])
        self.assertEqual(merge(self.catalog, self.source)[1]["addedRows"], 0)

    def test_both_photographed_identities_enter_distinct_binders(self):
        for player, team, number, subset, rookie in (
                ("KC Concepcion", "Cleveland Browns", "131", "Base", True),
                ("Justin Jefferson", "Minnesota Vikings", "BCV-69", "Chrome Base", False)):
            a = identity()
            a.update(player=player, playerNameOnCard=player, team=team, year=2026,
                     brand="Topps", setName="Bowman", subset=subset, cardNumber=number,
                     rookie=rookie, parallel=None, serialNumber=None)
            output = validate_identification(a, self.catalog)["analysis"]
            self.assertTrue(output["identityConfirmed"])
            self.assertEqual(output["collectionID"], "2026-topps-bowman-" + subset.lower().replace(" ", "-"))
            self.assertEqual(candidates(a, self.catalog)[0][1]["number"], number)
            # The right player cannot confirm a paper/Chrome family mismatch.
            a["subset"] = "Base" if subset == "Chrome Base" else "Chrome Base"
            self.assertFalse(validate_identification(a, self.catalog)["analysis"]["identityConfirmed"])

    def test_repository_loads_supplement_after_restart(self):
        with tempfile.TemporaryDirectory() as tmp:
            shutil.copy2(self.path, Path(tmp) / self.path.name)
            for _ in range(2):
                repo = Repository(Path(tmp))
                self.assertEqual(sum(len(c["cards"]) for c in repo.catalog), 800)

    def test_college_cards_confirm_in_separate_families_and_full_analysis(self):
        for subset, number, player in (("Paper Prospects", "BPP-72", "Jaron Tibbs"),
                                      ("Chrome Prospects", "BCP-43", "Alex Perry"),
                                      ("Paper Prospects", "BPP-ALT1", "Arch Manning"),
                                      ("Chrome Prospects", "ALT-1", "Arch Manning")):
            c = next(c for c in self.catalog if c["subset"] == subset)
            row = next(r for r in c["cards"] if r["number"] == number)
            a = identity()
            a.update(year=2026, brand="Topps", setName="Bowman", subset=subset, cardNumber=number,
                     player=player, playerNameOnCard=player, team=row["team"], rookie=False,
                     licenseScope="college")
            output = validate_identification(a, self.catalog)
            self.assertTrue(output["analysis"]["identityConfirmed"])
            self.assertFalse(output["analysis"]["needsReview"])
            self.assertEqual(output["analysis"]["collectionID"], c["id"])
            full = result()
            full["analysis"].update({k: output["analysis"][k] for k in a if k in full["analysis"]})
            full["analysis"]["identityConfirmed"] = True
            full["collection"] = deepcopy(c)
            self.assertEqual(validate_result(full, self.catalog)["analysis"]["collectionID"], c["id"])
            for scope in ("nfl_and_nflpa", "unknown", "unlicensed"):
                bad = validate_identification(dict(a, licenseScope=scope), self.catalog)
                self.assertFalse(bad["analysis"]["identityConfirmed"])
                self.assertIsNone(bad["collection"])

    def test_paper_prospect_aliases_keep_exact_prefix_and_product(self):
        a = identity()
        a.update(year=2026, brand="Topps", setName="Bowman", subset="Prospects",
                 cardNumber="BPP-72", player="Jaron Tibbs", playerNameOnCard="Jaron Tibbs",
                 licenseScope="college")
        for alias in ("Prospects", "Bowman Prospect Paper", "Bowman Paper Prospects"):
            identified = validate_identification(dict(a, subset=alias), self.catalog)
            self.assertTrue(identified["analysis"]["identityConfirmed"])
            full = result()
            full["analysis"].update({k: identified["analysis"][k] for k in a if k in full["analysis"]})
            full["analysis"].update(subset=alias, identityConfirmed=True)
            full["collection"] = dict(identified["collection"], subset=alias)
            self.assertEqual(validate_result(full, self.catalog)["analysis"]["subset"], "Paper Prospects")
        for patch in ({"cardNumber": "BCP-72"}, {"setName": "Bowman University"}, {"year": 2025},
                      {"subset": "Base"}, {"cardNumber": "72"}):
            self.assertFalse(validate_identification(dict(a, **patch), self.catalog)["analysis"]["identityConfirmed"])
        self.assertIsNotNone(identity_conflict(dict(a, subset="Base")))
        self.assertIsNotNone(identity_conflict(dict(a, subset="Base", cardNumber="72")))

    def test_sourced_rows_from_incomplete_nfl_family_are_available_as_evidence(self):
        excerpts = local_identity_excerpts({}, self.catalog, "2026 Bowman Amon-Ra St. Brown 32")
        paper = next(e for e in excerpts if e["id"] == "2026-topps-bowman-base")
        self.assertTrue(any(r["number"] == "32" for r in paper["cards"]))
        self.assertFalse(any(r["number"] in ("66", "68") for r in paper["cards"]))

    def test_wrong_release_missing_membership_and_fake_complete_rejected(self):
        for field, value in (("name", "Topps Chrome"), ("year", 2025),
                             ("checklistComplete", True), ("parallel", "Refractor")):
            changed = deepcopy(self.source)
            changed["collections"][0][field] = value
            with self.assertRaises(ValueError):
                merge([], changed)
        changed = deepcopy(self.source)
        changed["collections"][1]["cards"].pop()
        with self.assertRaises(ValueError): merge([], changed)
        with self.assertRaises(ValueError): parse("BASE NFL\n1 Player  Team", "2026-11-06")

    def test_parser_roundtrip_and_changed_numbering_fail_closed(self):
        # Build all six PDF sections from the stored facts and quarantined rows.
        text = []
        for heading, subset in SECTIONS.items():
            rookie = "ROOKIE" in heading
            text.append(heading)
            collection = next(c for c in self.catalog if c["subset"] == subset)
            rows = collection["cards"] + ([{k: r[k] for k in ("number", "player", "team", "rookie", "imageURL")}
                                          for r in self.source["conflicts"]] if subset == "Base" else [])
            for row in rows:
                if row["rookie"] == rookie:
                    text.append(f"{row['number']} {row['player']}  {row['team']}" + ("  Rookie" if rookie else ""))
        rebuilt = parse("\n".join(text), "2026-11-06")
        self.assertEqual(rebuilt["collections"], self.catalog)
        with self.assertRaises(ValueError):
            parse("\n".join(text).replace("68 Tua", "66 Tua"), "2026-11-06")
