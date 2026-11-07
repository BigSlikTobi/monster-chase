import base64
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from analysis import validate_result, collection_id
from server import Repository, Worker, handler

IDENTITY = "11111111-1111-4111-a111-111111111111"
PHOTO = base64.b64encode(b"\xff\xd8\xfftestfixture").decode()

def result():
    a = {"player": "Daunte Culpepper", "year": 2025, "brand": "Panini", "setName": "Donruss Optic", "subset": "Base", "cardNumber": "60", "parallel": None, "team": "Miami Dolphins", "rookie": False, "serialNumber": None, "recommendation": "Bulk", "marketLowCents": None, "marketHighCents": None, "marketCheckedAt": "2026-09-07", "marketSources": [], "confidence": "high", "conditionNotes": "Photo-only", "rationale": "No sold evidence", "needsReview": True, "identityConfirmed": True, "licenseScope": "nfl_and_nflpa", "psa10ChanceLow": None, "psa10ChanceHigh": None, "uncertainties": [], "currency": "EUR"}
    a["insights"] = {"rarityTier": "base", "rarityBullets": ["Basiskarte ohne erkennbare Nummerierung."], "conditionStatus": "no_obvious_damage", "conditionIssues": [], "conditionLimitations": [], "marketBullets": ["Kein frei zugänglicher Raw-Preis gefunden."], "marketReferences": [], "sourceChecks": [{"provider": "SportsCardsPro", "status": "no_match", "url": None}, {"provider": "eBay", "status": "unavailable", "url": None}], "actionReason": "Basiskarte für die Sammlung."}
    c = {"id": "ignored", "name": "Donruss Optic", "year": 2025, "brand": "Panini", "subset": "Base", "parallel": None, "expectedCount": 300, "checklistComplete": False, "sourceURL": "https://example.com/checklist", "checkedAt": "2026-09-07", "cards": [{"number": "60", "player": "Daunte Culpepper", "team": "Miami Dolphins", "rookie": False, "imageURL": None}]}
    return {"analysis": a, "collection": c}

class QueueTests(unittest.TestCase):
    def setUp(self): self.temp = tempfile.TemporaryDirectory(); self.repo = Repository(self.temp.name)
    def tearDown(self): self.temp.cleanup()
    def submit(self): return self.repo.submit({"id": IDENTITY, "front": PHOTO})
    def test_durable_idempotent_upload(self):
        self.assertEqual(self.submit()["status"], "queued")
        self.submit(); self.assertEqual(self.repo.next(), IDENTITY); self.assertIsNone(self.repo.next())
        restarted = Repository(self.temp.name)
        self.assertEqual(restarted.get(IDENTITY)["status"], "queued")
    def test_same_id_different_photo_rejected(self):
        self.submit()
        with self.assertRaises(ValueError): self.repo.submit({"id": IDENTITY, "front": base64.b64encode(b"\xff\xd8\xffdifferent").decode()})
    def test_traversal_and_invalid_image(self):
        for payload in [{"id": "../bad", "front": PHOTO}, {"id": IDENTITY, "front": "bad"}, {"id": IDENTITY, "front": base64.b64encode(b"html").decode()}]:
            with self.assertRaises(ValueError): self.repo.submit(payload)
    def test_ack_only_after_result_and_retains_analysis(self):
        self.submit()
        with self.assertRaises(ValueError): self.repo.ack(IDENTITY)
        self.repo.finish(IDENTITY, validate_result(result(), [])); self.repo.ack(IDENTITY)
        self.assertFalse((self.repo.jobroot / IDENTITY / "front.jpg").exists())
        self.assertEqual(self.repo.get(IDENTITY)["analysis"]["player"], "Daunte Culpepper")
        self.assertEqual(self.submit()["status"], "analyzed")
    def test_failed_retry(self):
        self.submit(); self.repo.fail(IDENTITY, "temporary")
        self.assertEqual(self.repo.retry(IDENTITY)["status"], "queued")
    def test_connection_closed_and_interrupted_work_requeued(self):
        import sqlite3
        with self.repo.db() as db: db.execute("SELECT 1")
        with self.assertRaises(sqlite3.ProgrammingError): db.execute("SELECT 1")
        self.submit(); self.repo.next(); self.repo.requeue(IDENTITY)
        self.assertEqual(self.repo.get(IDENTITY)["status"], "queued")
    def test_discard_queued_job_removes_transport_and_blocks_late_delivery(self):
        self.submit(); self.repo.discard(IDENTITY)
        self.assertIsNone(self.repo.next())
        self.assertFalse((self.repo.jobroot / IDENTITY / "front.jpg").exists())
        self.assertEqual(self.submit()["status"], "cancelled")
        self.assertFalse((self.repo.jobroot / IDENTITY / "front.jpg").exists())
    def test_discard_before_upload_creates_tombstone(self):
        self.repo.discard(IDENTITY)
        self.assertEqual(self.submit()["status"], "cancelled")
        self.assertIsNone(self.repo.next())
    def test_old_completion_or_error_cannot_resurrect_discarded_job(self):
        self.submit(); self.repo.next(); self.repo.discard(IDENTITY)
        self.repo.finish(IDENTITY, validate_result(result(), []))
        self.repo.fail(IDENTITY, "stale failure"); self.repo.requeue(IDENTITY); self.repo.retry(IDENTITY)
        self.assertEqual(self.repo.get(IDENTITY)["status"], "cancelled")
        self.assertIsNone(self.repo.get(IDENTITY)["analysis"])
        self.assertEqual(self.repo.catalog, [])
    def test_worker_cancels_superseded_job_and_processes_retake(self):
        replacement = "22222222-2222-4222-a222-222222222222"
        started, stopped = threading.Event(), threading.Event()
        def analyze(folder, known, config, cancel):
            if folder.name == IDENTITY:
                started.set()
                while not cancel.is_set(): stopped.wait(0.01)
                raise InterruptedError("superseded")
            return validate_result(result(), [])
        self.submit()
        with patch("server.run_codex", side_effect=analyze):
            worker = Worker(self.repo, {}, stopped); worker.start()
            try:
                self.assertTrue(started.wait(2))
                self.repo.discard(IDENTITY)
                self.repo.submit({"id": replacement, "front": PHOTO})
                deadline = time.monotonic() + 3
                while self.repo.get(replacement)["status"] != "analyzed" and time.monotonic() < deadline: stopped.wait(0.02)
                self.assertEqual(self.repo.get(replacement)["status"], "analyzed")
                self.assertEqual(self.repo.get(IDENTITY)["status"], "cancelled")
                self.assertFalse((self.repo.jobroot / IDENTITY / "front.jpg").exists())
            finally: stopped.set(); worker.join(timeout=3)

class EvidenceTests(unittest.TestCase):
    def test_assigns_exact_checklist(self):
        r = validate_result(result(), [])
        self.assertEqual(r["analysis"]["collectionID"], "2025-panini-donruss-optic-base")
    def test_no_false_ownership_for_uncertain_identity(self):
        r = result(); r["analysis"]["identityConfirmed"] = False
        self.assertIsNone(validate_result(r, [])["analysis"]["collectionID"])
    def test_unknown_or_unlicensed_does_not_enter_licensed_binder(self):
        for scope in ("unknown", "unlicensed"):
            r = result(); r["analysis"]["licenseScope"] = scope
            output = validate_result(r, [])
            self.assertIsNone(output["analysis"]["collectionID"])
            self.assertIsNone(output["collection"])
            self.assertTrue(output["analysis"]["needsReview"])
    def test_player_mismatch_cannot_mark_owned(self):
        r = result(); r["analysis"]["player"] = "Joe Burrow"
        self.assertIsNone(validate_result(r, [])["analysis"]["collectionID"])
    def test_parallel_does_not_complete_base(self):
        r = result(); known = [dict(r["collection"], id=collection_id(r["analysis"]), checklistComplete=True, expectedCount=1)]
        known[0]["cards"][0]["imageURL"] = "https://example.com/base-scan.jpg"
        r["analysis"]["parallel"] = "Holo"
        output = validate_result(r, known)
        self.assertEqual(output["analysis"]["collectionID"], "2025-panini-donruss-optic-base-holo")
        self.assertIsNone(output["collection"]["cards"][0]["imageURL"])
    def test_ask_only_or_unknown_delivery_cannot_create_value(self):
        for status, total in [("ask", 100), ("sold", None)]:
            r = result(); r["analysis"].update(marketLowCents=100, marketHighCents=200, marketSources=[{"url":"https://example.com/sale", "title":"test", "status":status, "matchQuality":"exact", "deliveredTotalCents":total, "currency":"EUR", "saleDate":"2026-09-01"}])
            with self.assertRaises(ValueError): validate_result(r, [])
    def test_incomplete_checklist_not_labelled_complete(self):
        r = result(); r["collection"]["checklistComplete"] = True
        with self.assertRaises(ValueError): validate_result(r, [])
    def test_no_unsupported_grading_or_fake_probability(self):
        for update in [{"recommendation":"Grade"}, {"psa10ChanceLow":90, "psa10ChanceHigh":10}]:
            r = result(); r["analysis"].update(update)
            with self.assertRaises(ValueError): validate_result(r, [])

class HTTPTests(unittest.TestCase):
    def test_authentication_and_size_limit(self):
        with tempfile.TemporaryDirectory() as folder:
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler(Repository(folder), "secret-test-token"))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            base = "http://127.0.0.1:" + str(server.server_port)
            try:
                with self.assertRaises(urllib.error.HTTPError) as e: urllib.request.urlopen(base + "/v1/bootstrap")
                self.assertEqual(e.exception.code, 401); e.exception.close()
                request = urllib.request.Request(base + "/v1/ping", headers={"Authorization":"Bearer secret-test-token"})
                with urllib.request.urlopen(request) as response: self.assertEqual(json.load(response)["status"], "ok")
                request = urllib.request.Request(base + "/v1/jobs", data=b"{}", headers={"Authorization":"Bearer secret-test-token", "Content-Length":"99999999", "Content-Type":"application/json"})
                with self.assertRaises(urllib.error.HTTPError) as e: urllib.request.urlopen(request)
                self.assertEqual(e.exception.code, 413); e.exception.close()
                request = urllib.request.Request(base + "/v1/jobs/" + IDENTITY + "/discard", data=b"{}", headers={"Authorization":"Bearer secret-test-token", "Content-Type":"application/json"})
                with urllib.request.urlopen(request) as response: self.assertEqual(json.load(response)["status"], "cancelled")
            finally: server.shutdown(); server.server_close(); thread.join()

if __name__ == "__main__": unittest.main()
