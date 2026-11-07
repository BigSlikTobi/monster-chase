from copy import deepcopy
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from analysis import validate_identification, validate_result, run_codex, _run_model, identity_conflict
from schema import IDENTITY_RESULT, RESULT
from server import Repository, Worker, IdentificationWorker
from test_pipeline import PHOTO, result

def identity():
    analysis = result()["analysis"]
    return {key: deepcopy(analysis["player"] if key == "playerNameOnCard" else analysis[key] if key in analysis else analysis["insights"][key]) for key in IDENTITY_RESULT["properties"]}

def key(number): return f"{number:08x}-1111-4111-a111-111111111111"

class FastCaptureTests(unittest.TestCase):
    def test_broader_candidates_cannot_confirm_known_serial_or_membership_conflicts(self):
        a = dict(year=2025, brand="Panini", setName="Donruss Optic", subset="Base", parallel="Orange", cardNumber="257", serialNumber="20/79")
        self.assertIsNotNone(identity_conflict(a))
        self.assertIsNone(identity_conflict(dict(a, parallel="Orange Scope")))
        self.assertIsNotNone(identity_conflict(dict(a, parallel="Blue Hyper", cardNumber="84")))
        value = identity(); value.update(a)
        c = result()["collection"]; c.update(year=2025, parallel="Orange")
        c["cards"][0]["number"] = "257"
        from analysis import collection_id
        c["id"] = collection_id(value)
        output = validate_identification(value, [c])
        self.assertFalse(output["analysis"]["identityConfirmed"])
        self.assertIsNone(output["collection"])

    def test_guess_conflicting_with_printed_name_is_removed(self):
        value = identity()
        value.update(player="Tutu Atwell", playerNameOnCard="FERGUSON")
        output = validate_identification(value, [])["analysis"]
        self.assertIsNone(output["player"])
        self.assertFalse(output["identityConfirmed"])
        self.assertTrue(output["needsReview"])

    def test_unreadable_name_cannot_support_guessed_player(self):
        value = identity()
        value["playerNameOnCard"] = None
        self.assertIsNone(validate_identification(value, [])["analysis"]["player"])

    def test_low_confidence_guess_is_removed_even_with_claimed_transcription(self):
        value = identity()
        value.update(player="Tyler Higbee", playerNameOnCard="HIGBEE", confidence="low")
        self.assertIsNone(validate_identification(value, [])["analysis"]["player"])

    def test_readable_surname_can_support_full_name(self):
        value = identity()
        value["playerNameOnCard"] = "CULPEPPER"
        self.assertEqual(validate_identification(value, [])["analysis"]["player"], "Daunte Culpepper")

    def test_full_analysis_also_discards_low_confidence_player(self):
        value = result()
        value["playerNameOnCard"] = "CULPEPPER"
        value["analysis"]["confidence"] = "low"
        with patch("analysis.subprocess.Popen") as spawn:
            process = spawn.return_value
            process.returncode = 0
            process.poll.return_value = 0
            process.communicate.side_effect = lambda *args, **kwargs: (self.root / "result.json").write_text(json.dumps(value))
            output = _run_model(self.root, [], {"codex": "fixture"}, "fixture", RESULT, None, "fixture", "medium")
        self.assertIsNone(output["analysis"]["player"])
        self.assertIsNone(output["collection"])
        self.assertNotIn("playerNameOnCard", output)
    def setUp(self): self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name); self.repo = Repository(self.root)
    def tearDown(self): self.temp.cleanup()
    def submit(self, number=1): return self.repo.submit({"id": key(number), "front": PHOTO, "pipeline": "fast"})

    def test_hundred_cards_are_durable_and_idempotent(self):
        for number in range(1, 101): self.submit(number)
        self.submit(1)
        restarted = Repository(self.root)
        with restarted.db() as db: self.assertEqual(db.execute("SELECT COUNT(*) FROM jobs").fetchone()[0], 100)
        self.assertEqual(restarted.next_identification(), key(1))
        self.assertIsNone(restarted.next())  # No expensive research before identification.

    def test_identification_is_visible_without_final_acknowledgement(self):
        self.submit(); self.assertEqual(self.repo.next_identification(), key(1))
        analysis = validate_identification(identity(), [validate_result(result(), [])["collection"]])
        self.repo.identify(key(1), analysis)
        self.assertEqual(self.repo.get(key(1))["status"], "identified")
        self.assertEqual(self.repo.get(key(1))["analysis"]["player"], "Daunte Culpepper")
        with self.assertRaises(ValueError): self.repo.ack(key(1))
        self.assertEqual(self.repo.next(), key(1))
        self.assertEqual(self.repo.get(key(1))["status"], "enriching")
        self.assertTrue((self.repo.jobroot / key(1) / "refresh.json").exists())
        self.repo.finish(key(1), validate_result(result(), [])); self.repo.ack(key(1))
        self.assertFalse((self.repo.jobroot / key(1) / "front.jpg").exists())

    def test_restart_recovers_pricing_without_losing_identification(self):
        self.submit(); self.repo.next_identification()
        self.repo.identify(key(1), validate_identification(identity(), [])); self.repo.next()
        restarted = Repository(self.root)
        self.assertEqual(restarted.get(key(1))["status"], "identified")
        self.assertEqual(restarted.get(key(1))["analysis"]["player"], "Daunte Culpepper")
        self.assertEqual(restarted.next(), key(1))

    def test_failed_market_retries_without_repeating_identification(self):
        self.submit(); self.repo.next_identification()
        self.repo.identify(key(1), validate_identification(identity(), [])); self.repo.next()
        self.repo.fail(key(1), "Market unavailable")
        self.assertEqual(self.repo.retry(key(1))["status"], "identified")
        self.assertIsNone(self.repo.next_identification())
        self.assertEqual(self.repo.next(), key(1))
        self.assertEqual(self.repo.get(key(1))["analysis"]["player"], "Daunte Culpepper")

    def test_new_client_upgrades_an_unstarted_legacy_job(self):
        self.repo.submit({"id": key(1), "front": PHOTO})
        self.submit()
        self.assertIsNone(self.repo.next())
        self.assertEqual(self.repo.next_identification(), key(1))

    def test_manual_assignment_comes_from_server_checklist_and_locks_identity(self):
        collection = validate_result(result(), [])["collection"]
        self.repo.catalog = [collection]
        output = self.repo.submit({"id": key(1), "front": PHOTO, "pipeline": "fast",
                                  "assignment": {"collectionID": collection["id"], "number": "60"}})
        self.assertEqual(output["status"], "queued")
        self.assertIsNone(self.repo.next_identification())
        self.assertEqual(self.repo.next(), key(1))
        locked = json.loads((self.repo.jobroot / key(1) / "identity.json").read_text())
        self.assertEqual(locked["player"], "Daunte Culpepper")
        self.assertEqual(locked["cardNumber"], "60")
        with self.assertRaises(ValueError):
            self.repo.submit({"id": key(2), "front": PHOTO,
                              "assignment": {"collectionID": collection["id"], "number": "999"}})

    def test_unknown_checklist_and_medium_confidence_never_fill_binder(self):
        unknown = validate_identification(identity(), [])
        self.assertFalse(unknown["analysis"]["identityConfirmed"])
        self.assertIsNone(unknown["collection"])
        value = identity(); value["confidence"] = "medium"
        uncertain = validate_identification(value, [validate_result(result(), [])["collection"]])
        self.assertTrue(uncertain["analysis"]["needsReview"])
        self.assertIsNone(uncertain["analysis"]["collectionID"])

    def test_optic_brand_alias_uses_same_binder_without_promoting_uncertainty(self):
        collection = validate_result(result(), [])["collection"]
        value = identity(); value["brand"] = "Donruss"
        matched = validate_identification(value, [collection])
        self.assertEqual(matched["analysis"]["brand"], "Panini")
        self.assertEqual(matched["analysis"]["collectionID"], collection["id"])
        self.assertEqual(value["brand"], "Donruss")
        value["year"] = None; value["cardNumber"] = None; value["confidence"] = "medium"
        uncertain = validate_identification(value, [collection])
        self.assertEqual(uncertain["analysis"]["brand"], "Panini")
        self.assertFalse(uncertain["analysis"]["identityConfirmed"])
        self.assertIsNone(uncertain["collection"])

    def test_full_optic_analysis_normalizes_alias_without_duplicate_binder(self):
        collection = validate_result(result(), [])["collection"]
        value = result(); value["analysis"]["brand"] = "Donruss"; value["collection"]["brand"] = "Donruss"
        output = validate_result(value, [collection])
        self.assertEqual(output["analysis"]["collectionID"], collection["id"])
        self.assertEqual(output["collection"]["brand"], "Panini")

    def test_historical_donruss_is_not_relabelled_as_panini(self):
        value = identity(); value["brand"] = "Donruss"; value["setName"] = "Donruss"; value["year"] = 2001
        output = validate_identification(value, [])
        self.assertEqual(output["analysis"]["brand"], "Donruss")

    def test_uncertain_variant_never_inherits_a_base_checklist(self):
        value = identity(); value["parallel"] = "Unknown parallel"
        output = validate_identification(value, [validate_result(result(), [])["collection"]])
        self.assertIsNone(output["analysis"]["collectionID"])

    def test_identity_lane_keeps_running_while_market_lane_is_busy(self):
        self.submit(); self.repo.next_identification(); self.repo.identify(key(1), validate_identification(identity(), []))
        started, release, stop = threading.Event(), threading.Event(), threading.Event()
        def slow(*args):
            started.set(); release.wait(3); return validate_result(result(), [])
        with patch("server.run_codex", side_effect=slow), patch("server.run_identification", return_value=validate_identification(identity(), [])):
            research = Worker(self.repo, {}, stop); quick = IdentificationWorker(self.repo, {}, stop)
            research.start(); self.assertTrue(started.wait(2)); self.submit(2); quick.start()
            try:
                deadline = time.monotonic() + 2
                while self.repo.get(key(2))["status"] != "identified" and time.monotonic() < deadline: time.sleep(0.01)
                self.assertEqual(self.repo.get(key(2))["status"], "identified")
                self.assertEqual(self.repo.get(key(1))["status"], "enriching")
            finally: stop.set(); release.set(); research.join(3); quick.join(3)

    def test_cancelled_identification_cannot_resurrect_a_retake(self):
        self.submit(); self.repo.next_identification(); self.repo.discard(key(1))
        self.repo.identify(key(1), validate_identification(identity(), []))
        self.assertEqual(self.repo.get(key(1))["status"], "cancelled")

    def test_failed_quick_identification_falls_back_without_losing_photo(self):
        self.submit(); self.repo.next_identification(); self.repo.defer_identification(key(1))
        self.assertEqual(self.repo.get(key(1))["status"], "queued")
        self.assertTrue((self.repo.jobroot / key(1) / "front.jpg").exists())
        self.assertEqual(self.repo.next(), key(1))

    def test_partial_checklists_merge_instead_of_dropping_owned_entries(self):
        previous = validate_result(result(), [])["collection"]
        incoming = result(); incoming["analysis"]["cardNumber"] = "61"; incoming["analysis"]["player"] = "Different Player"
        incoming["collection"]["cards"] = [dict(previous["cards"][0], number="61", player="Different Player")]
        updated = validate_result(incoming, [previous])
        self.assertEqual({card["number"] for card in updated["collection"]["cards"]}, {"60", "61"})

    def test_fallback_failure_keeps_medium_identity_provisional(self):
        value = result(); value["analysis"]["confidence"] = "medium"
        primary = validate_result(value, [])
        with patch("analysis._run_model", side_effect=[primary, RuntimeError("Unavailable")]):
            output = run_codex(self.root, [], {"model": "primary", "fallbackModel": "fallback"})
        self.assertFalse(output["analysis"]["identityConfirmed"])
        self.assertTrue(output["analysis"]["needsReview"])
        self.assertIsNone(output["analysis"]["collectionID"])

if __name__ == "__main__": unittest.main()
