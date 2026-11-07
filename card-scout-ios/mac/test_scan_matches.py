from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock

from scan_matches import candidates, rank_matches, reference_content, review_notice
from reference_images import identity
from server import Repository
from test_pipeline import PHOTO, result
from analysis import validate_result


class ScanMatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.catalog = [validate_result(result(), [])["collection"]]
        self.analysis = result()["analysis"]

    def tearDown(self):
        self.temp.cleanup()

    def test_ocr_recovers_candidates_after_both_model_fields_are_wrong(self):
        hint = dict(self.analysis, player="Wrong Player", cardNumber="999", year=1999, parallel="Fire")
        rows = candidates(hint, self.catalog, "Vorderseite: DAUNTE CULPEPPER\nRückseite: 60")
        self.assertTrue(any(r[1]["number"] == "60" for r in rows))
        self.assertEqual(hint["player"], "Wrong Player")

    def test_minor_name_misreading_and_wrong_year_do_not_hide_real_card(self):
        hint = dict(self.analysis, player="Daunte Culpeper", cardNumber=None, year=2024)
        self.assertTrue(candidates(hint, self.catalog))

    def test_no_evidence_does_not_return_arbitrary_product_rows(self):
        self.assertEqual(candidates({"setName": self.analysis["setName"]}, self.catalog), [])
        self.assertEqual(candidates({}, self.catalog, "123 456 789"), [])

    def test_missing_catalog_is_not_a_photo_failure(self):
        a = dict(self.analysis, identityConfirmed=False)
        self.assertEqual(review_notice(a, []), "catalog_missing")
        self.assertEqual(review_notice(a, self.catalog), "variant_unresolved")
        self.assertEqual(review_notice(dict(a, player=None), []), "identity_incomplete")
        self.assertIsNone(review_notice(dict(a, identityConfirmed=True), self.catalog))

    def test_match_pipeline_waits_for_selection_after_restart(self):
        repo = Repository(self.root)
        identity = "11111111-1111-4111-a111-111111111111"
        repo.submit({"id": identity, "front": PHOTO, "pipeline": "match"})
        self.assertEqual(repo.next_identification(), identity)
        output = validate_result(result(), [])
        output["matches"] = [{"collectionID": self.catalog[0]["id"], "number": self.analysis["cardNumber"]}]
        repo.identify(identity, output)
        restarted = Repository(self.root)
        self.assertEqual(restarted.get(identity)["matches"], output["matches"])
        self.assertIsNone(restarted.next())
        self.assertEqual(restarted.get(identity)["status"], "identified")
        # A separate, explicit assignment job can enter assessment.
        restarted.catalog = self.catalog
        selected = "22222222-2222-4222-a222-222222222222"
        restarted.submit({"id": selected, "front": PHOTO, "pipeline": "match", "assignment": {"collectionID": self.catalog[0]["id"], "number": self.analysis["cardNumber"]}})
        self.assertEqual(restarted.next(), selected)

    def test_failed_match_does_not_escalate_to_unselected_full_analysis(self):
        repo = Repository(self.root)
        identity = "11111111-1111-4111-a111-111111111111"
        repo.submit({"id": identity, "front": PHOTO, "pipeline": "match"})
        repo.next_identification(); repo.defer_identification(identity)
        self.assertEqual(repo.get(identity)["status"], "failed")
        self.assertIsNone(repo.next())

    def test_no_generated_parallel_rows_and_unknown_name_does_not_guess(self):
        self.assertEqual(candidates({}, self.catalog), [])
        rows = candidates(self.analysis, self.catalog)
        for row in rows:
            self.assertTrue(any(c["number"] == row[1]["number"] for c in self.catalog[0]["cards"]))
        self.assertEqual(rank_matches(self.root, self.analysis, self.catalog, {}), [r[1] for r in rows[:5]])

    def decision(self, response):
        transport = MagicMock()
        transport.open.return_value.__enter__.return_value.read.return_value = json.dumps(response).encode()
        return transport

    def test_decisions_ranks_only_allowlisted_rows_and_never_assigns(self):
        second = deepcopy(self.catalog[0]); second["id"] += "-scope"; second["parallel"] = "Orange Scope"
        catalog = self.catalog + [second]
        rows = candidates(self.analysis, catalog)
        answer = {"type": "choice", "name": "card", "choice": "1", "probabilities": [{"value": "0", "probability": .05}, {"value": "1", "probability": .9}, {"value": "unknown", "probability": .05}]}
        before = deepcopy(self.analysis)
        with patch("scan_matches.load_api_key", return_value="fixture"), patch("scan_matches.urllib.request.build_opener", return_value=self.decision({"answers": [answer]})):
            output = rank_matches(self.root, self.analysis, catalog, {"apiEnabled": True})
        self.assertEqual(output[0], rows[1][1])
        self.assertEqual(self.analysis, before)

    def test_api_errors_refusal_and_out_of_contract_answers_fall_back(self):
        fallback = [r[1] for r in candidates(self.analysis, self.catalog)[:5]]
        for answer in ({"type": "refusal", "name": "card"}, {"type": "choice", "name": "card", "choice": "injected"}):
            with patch("scan_matches.load_api_key", return_value="fixture"), patch("scan_matches.urllib.request.build_opener", return_value=self.decision({"answers": [answer]})):
                self.assertEqual(rank_matches(self.root, self.analysis, self.catalog, {"apiEnabled": True}), fallback)
        with patch("scan_matches.load_api_key", return_value="fixture"), patch("scan_matches.urllib.request.build_opener", side_effect=OSError("offline")):
            self.assertEqual(rank_matches(self.root, self.analysis, self.catalog, {"apiEnabled": True}), fallback)

    def test_punctuation_and_subset_do_not_hide_the_right_candidate(self):
        catalog = deepcopy(self.catalog)
        catalog[0]["cards"][0].update(player="C.J. Stroud", number="ACT-1")
        catalog[0]["subset"] = "All-Chrome Team"
        wrong = deepcopy(catalog[0]); wrong["id"] += "-other"; wrong["subset"] = "Other Insert"
        hint = dict(self.analysis, player="CJ Stroud", cardNumber=None, subset="All Chrome Team")
        rows = candidates(hint, [wrong] + catalog)
        self.assertEqual(rows[0][1]["collectionID"], catalog[0]["id"])
        self.assertEqual(len(rows), 2)

    def test_reference_bytes_must_match_review_and_examples_are_labeled(self):
        import hashlib
        catalog = deepcopy(self.catalog)
        c = catalog[0]; card = c["cards"][0]
        raw = b"\xff\xd8\xff" + b"fixture"
        ref = dict(identity(c, card), frontURL="https://i.ebayimg.com/images/example.jpg",
                   sha256=hashlib.sha256(raw).hexdigest())
        card["referenceImage"] = ref
        rows = candidates(dict(self.analysis, player=card["player"], cardNumber=card["number"]), catalog)
        response = MagicMock(); response.read.return_value = raw; response.status = 200; response.url = ref["frontURL"]
        transport = MagicMock(); transport.open.return_value.__enter__.return_value = response
        with patch("scan_matches.urllib.request.build_opener", return_value=transport):
            diagnostics = {}
            blocks = reference_content(rows, catalog, diagnostics)
            self.assertEqual(diagnostics["referenceImages"], 1)
            self.assertIn("exact candidate front", blocks[0]["text"])
            ref["sha256"] = "0" * 64
            self.assertEqual(reference_content(rows, catalog, {}), [])
            ref["sha256"] = hashlib.sha256(raw).hexdigest()
            del card["referenceImage"]
            c["referenceExample"] = dict(ref, player="Another Player", number="999")
            self.assertIn("EXAMPLE", reference_content(rows, catalog, {})[0]["text"])
            c["referenceExample"]["parallel"] = "Wrong Finish"
            self.assertEqual(reference_content(rows, catalog, {}), [])

    def test_unsafe_reference_never_fetches(self):
        catalog = deepcopy(self.catalog); c = catalog[0]; card = c["cards"][0]
        card["referenceImage"] = dict(identity(c, card), frontURL="http://127.0.0.1/key", sha256="0" * 64)
        with patch("scan_matches.urllib.request.build_opener", side_effect=AssertionError("No request")):
            self.assertEqual(reference_content(candidates(self.analysis, catalog), catalog, {}), [])
