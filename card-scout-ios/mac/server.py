#!/usr/bin/env python3
"""Private TLS Mac companion. Images are temporary; iPhone owns the photo library."""
import argparse
from contextlib import contextmanager
import base64
import datetime as dt
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import signal
import sqlite3
import ssl
import threading
import time
from analysis import run_codex, run_identification, slug
from schema import ANALYSIS_VERSION
from scan_matches import rank_matches, candidates, capture_hints, review_notice
from reference_images import load as load_references, overlay as reference_overlay, coverage as reference_coverage
from chases import load_catalog
from cardsight import Market, PRODUCTS
from card_prices import PriceResearch
from catalog_supplement import load_all

MAX_BODY = 24_000_000
MAX_IMAGE = 8_000_000
MAX_QUEUE = 250
UUID = re.compile(r"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")
def now(): return dt.datetime.now(dt.timezone.utc).isoformat()
def read_json(path, default): return json.loads(path.read_text()) if path.exists() else default
def atomic_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temporary.chmod(0o600); temporary.replace(path)

def image_bytes(value):
    if not isinstance(value, str) or len(value) > MAX_IMAGE * 4 / 3 + 4: raise ValueError("Foto zu groß.")
    data = base64.b64decode(value, validate=True)
    if not data or len(data) > MAX_IMAGE or not (data.startswith(b"\xff\xd8\xff") or data.startswith(b"\x89PNG\r\n\x1a\n")): raise ValueError("Ungültiges Foto. JPEG oder PNG verwenden.")
    return data

class QueueFull(ValueError): pass

class Repository:
    def __init__(self, root):
        self.root = Path(root); self.root.mkdir(parents=True, exist_ok=True); self.root.chmod(0o700)
        self.jobroot = self.root / "jobs"; self.jobroot.mkdir(exist_ok=True)
        self.lock = threading.RLock()
        with self.db() as db:
            db.execute("CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY, digest TEXT NOT NULL, status TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, result TEXT, error TEXT, ack INTEGER NOT NULL DEFAULT 0)")
            if "pipeline" not in {row[1] for row in db.execute("PRAGMA table_info(jobs)")}:
                db.execute("ALTER TABLE jobs ADD COLUMN pipeline TEXT NOT NULL DEFAULT 'full'")
            db.execute("UPDATE jobs SET status='queued', error=NULL WHERE status='processing'")
            db.execute("UPDATE jobs SET status='identified', error=NULL WHERE status='enriching'")
        self.catalog_file = self.root / "collections.json"
        self.catalog = read_json(self.catalog_file, [])
        self.catalog, self.catalog_coverage = load_all(self.catalog, self.root)
        try: self.chases = load_catalog(self.root / "chases.json")
        except (ValueError, KeyError, TypeError, OSError): self.chases = None
        self.market = Market(self.root)
        self.card_prices = PriceResearch(self.root)
        self.card_prices_enabled = read_json(self.root / "config.json", {}).get("cardSightResearchEnabled", False)
    @contextmanager
    def db(self):
        connection = sqlite3.connect(self.root / "queue.sqlite3", timeout=10)
        connection.row_factory = sqlite3.Row; connection.execute("PRAGMA journal_mode=WAL")
        try:
            with connection: yield connection
        finally: connection.close()
    def references(self):
        try: return load_references(self.root / "reference-images.json")
        except (OSError, ValueError, TypeError, KeyError): return {"version": 1, "records": [], "revision": "invalid"}
    def checklists(self):
        return reference_overlay(self.catalog, self.references())
    def submit(self, payload):
        identity = payload.get("id", "")
        if not isinstance(identity, str) or not UUID.fullmatch(identity): raise ValueError("Ungültige Karten-ID.")
        front = image_bytes(payload.get("front")); back = image_bytes(payload["back"]) if payload.get("back") else None
        digest = hashlib.sha256(front + b"\0SIDE\0" + (back or b"")).hexdigest()
        refresh_of = payload.get("refreshOf")
        if refresh_of is not None and (not isinstance(refresh_of, str) or not UUID.fullmatch(refresh_of)):
            raise ValueError("Ungültige vorherige Analyse.")
        pipeline = payload.get("pipeline", "full")
        if pipeline not in ("fast", "full", "match"): raise ValueError("Ungültiger Analysemodus.")
        text = payload.get("captureText")
        if text is not None and (not isinstance(text, str) or len(text) > 2000): raise ValueError("Ungültiger Lesetext.")
        assignment = None
        if payload.get("assignment") is not None:
            choice = payload["assignment"]
            if not isinstance(choice, dict) or set(choice) != {"collectionID", "number"}: raise ValueError("Ungültige Zuordnung.")
            collection = next((c for c in self.catalog if c["id"] == choice["collectionID"]), None)
            entry = next((c for c in collection["cards"] if c["number"] == choice["number"]), None) if collection else None
            if not entry: raise ValueError("Zuordnung fehlt in der geprüften Checkliste.")
            assignment = {"year": collection["year"], "brand": collection["brand"], "setName": collection["name"],
                          "subset": collection["subset"], "parallel": collection["parallel"], "cardNumber": entry["number"],
                          "player": entry["player"], "team": entry["team"], "rookie": entry["rookie"]}
            pipeline = "full"  # User corrections are locked; only their assessment is researched.
            digest = hashlib.sha256((digest + json.dumps(assignment, sort_keys=True)).encode()).hexdigest()
        with self.lock, self.db() as db:
            existing = db.execute("SELECT * FROM jobs WHERE id=?", (identity,)).fetchone()
            if existing:
                if existing["status"] == "cancelled": return self.public(existing)
                if existing["digest"] != digest: raise ValueError("Diese Karten-ID gehört zu anderen Fotos.")
                if pipeline == "fast" and existing["status"] == "queued":
                    db.execute("UPDATE jobs SET pipeline='fast' WHERE id=?", (identity,))
                return self.public(existing)
            if db.execute("SELECT COUNT(*) FROM jobs WHERE status IN ('queued','processing','identified','enriching')").fetchone()[0] >= MAX_QUEUE: raise QueueFull("Warteschlange voll. Bitte später erneut versuchen.")
            folder = self.jobroot / identity; folder.mkdir(exist_ok=True); folder.chmod(0o700)
            (folder / "front.jpg").write_bytes(front)
            if back: (folder / "back.jpg").write_bytes(back)
            if text: (folder / "capture-text.txt").write_text(text, encoding="utf-8")
            if assignment: atomic_json(folder / "identity.json", assignment)
            if refresh_of:
                prior = db.execute("SELECT * FROM jobs WHERE id=? AND status='analyzed' AND digest=?", (refresh_of, digest)).fetchone()
                previous = json.loads(prior["result"]) if prior and prior["result"] else None
                a = previous.get("analysis", {}) if previous else {}
                # Only server-owned evidence for identical pixels can skip identification/condition.
                if a.get("identityConfirmed") and a.get("insights") and previous.get("collection"):
                    atomic_json(folder / "refresh.json", previous)
            db.execute("INSERT INTO jobs(id,digest,status,created_at,updated_at,pipeline) VALUES(?,?,'queued',?,?,?)", (identity, digest, now(), now(), pipeline))
            row = db.execute("SELECT * FROM jobs WHERE id=?", (identity,)).fetchone()
            return self.public(row)
    def public(self, row):
        result = json.loads(row["result"]) if row["result"] else {}
        if self.card_prices_enabled:
            result = self.card_prices.attach(result)
            a = result.get("analysis") or {}
            if a and not (a.get("insights") or {}).get("marketReferences"):
                with self.db() as db:
                    records = db.execute("SELECT result FROM jobs WHERE status='analyzed' AND result IS NOT NULL ORDER BY updated_at DESC LIMIT 2000").fetchall()
                peers = [json.loads(r["result"]).get("analysis", {}) for r in records]
                result = self.card_prices.attach_comparable(result, peers)
        if result.get("collection"):
            result["collection"] = reference_overlay([result["collection"]], self.references())[0]
        response = {"matchNotice": result.get("matchNotice"), "matches": result.get("matches"), "id": row["id"], "status": row["status"], "analysis": result.get("analysis"), "collection": result.get("collection"), "error": row["error"]}
        if self.card_prices_enabled and result.get("analysis"):
            response["priceStatus"] = self.card_prices.status(result["analysis"])
            if result["analysis"].get("comparableEstimate") and response["priceStatus"] != "refreshing":
                response["priceStatus"] = "estimate"
        return response
    def get(self, identity):
        with self.db() as db:
            row = db.execute("SELECT * FROM jobs WHERE id=?", (identity,)).fetchone()
            return self.public(row) if row else None
    def next(self):
        with self.lock, self.db() as db:
            row = db.execute("SELECT * FROM jobs WHERE (status='identified' AND pipeline!='match') OR (status='queued' AND pipeline='full') ORDER BY created_at LIMIT 1").fetchone()
            if row: db.execute("UPDATE jobs SET status=?,updated_at=? WHERE id=?", ("enriching" if row["status"] == "identified" else "processing", now(), row["id"]))
            return row["id"] if row else None
    def wants_matches(self, identity):
        with self.db() as db:
            row = db.execute("SELECT pipeline FROM jobs WHERE id=?", (identity,)).fetchone()
            return row is not None and row[0] == "match"
    def next_identification(self):
        with self.lock, self.db() as db:
            row = db.execute("SELECT id FROM jobs WHERE status='queued' AND pipeline IN ('fast','match') ORDER BY created_at LIMIT 1").fetchone()
            if row: db.execute("UPDATE jobs SET status='processing',updated_at=? WHERE id=?", (now(), row["id"]))
            return row["id"] if row else None
    def identify(self, identity, result):
        with self.lock, self.db() as db:
            row = db.execute("SELECT status FROM jobs WHERE id=?", (identity,)).fetchone()
            if not row or row[0] != "processing": return
            if result["analysis"].get("identityConfirmed") and result.get("collection"):
                atomic_json(self.jobroot / identity / "refresh.json", result)
            db.execute("UPDATE jobs SET status='identified',result=?,error=NULL,updated_at=? WHERE id=?", (json.dumps(result, ensure_ascii=False), now(), identity))
    def defer_identification(self, identity):
        with self.lock, self.db() as db:
            db.execute("UPDATE jobs SET status=CASE WHEN pipeline='match' THEN 'failed' ELSE 'queued' END,pipeline=CASE WHEN pipeline='match' THEN 'match' ELSE 'full' END,error=NULL,updated_at=? WHERE id=? AND status='processing'", (now(), identity))
    def finish(self, identity, result):
        with self.lock, self.db() as db:
            row = db.execute("SELECT status FROM jobs WHERE id=?", (identity,)).fetchone()
            if not row or row[0] == "cancelled": return
            if result.get("collection"):
                self.catalog = [c for c in self.catalog if c["id"] != result["collection"]["id"]] + [result["collection"]]
                self.catalog, self.catalog_coverage = load_all(self.catalog, self.root)
                atomic_json(self.catalog_file, self.catalog)
            db.execute("UPDATE jobs SET status='analyzed', result=?,error=NULL,updated_at=? WHERE id=?", (json.dumps(result, ensure_ascii=False), now(), identity))
    def fail(self, identity, message):
        with self.db() as db: db.execute("UPDATE jobs SET status='failed',error=?,updated_at=? WHERE id=? AND status!='cancelled'", (message, now(), identity))
    def retry(self, identity):
        with self.lock, self.db() as db:
            row = db.execute("SELECT status,result,pipeline FROM jobs WHERE id=?", (identity,)).fetchone()
            if not row: raise ValueError("Karte nicht gefunden.")
            if row["status"] == "failed": db.execute("UPDATE jobs SET status=?,error=NULL,updated_at=? WHERE id=?", ("identified" if row["pipeline"] == "fast" and row["result"] else "queued", now(), identity))
        return self.get(identity)
    def requeue(self, identity):
        with self.db() as db: db.execute("UPDATE jobs SET status=CASE WHEN status='enriching' THEN 'identified' ELSE 'queued' END,error=NULL,updated_at=? WHERE id=? AND status IN ('processing','enriching')", (now(), identity))
    def is_discarded(self, identity):
        with self.db() as db:
            row = db.execute("SELECT status FROM jobs WHERE id=?", (identity,)).fetchone()
            return row is not None and row[0] == "cancelled"
    def cleanup_transport(self, identity):
        for name in ("front.jpg", "back.jpg", "worker.log", "result.json", "schema.json", "refresh.json", "identity.json", "capture-text.txt", "identification.json", "retrieval.json"):
            (self.jobroot / identity / name).unlink(missing_ok=True)
    def discard(self, identity):
        with self.lock, self.db() as db:
            row = db.execute("SELECT status FROM jobs WHERE id=?", (identity,)).fetchone()
            # A tombstone also blocks an earlier upload that arrives after the replacement.
            if not row:
                db.execute("INSERT INTO jobs(id,digest,status,created_at,updated_at,ack) VALUES(?,'','cancelled',?,?,1)", (identity, now(), now()))
            else: db.execute("UPDATE jobs SET status='cancelled',error=NULL,updated_at=? WHERE id=?", (now(), identity))
            if not row or row[0] not in ("processing", "enriching"): self.cleanup_transport(identity)
    def ack(self, identity):
        with self.lock, self.db() as db:
            row = db.execute("SELECT status FROM jobs WHERE id=?", (identity,)).fetchone()
            if not row or row[0] != "analyzed": raise ValueError("Analyse noch nicht gespeichert.")
            db.execute("UPDATE jobs SET ack=1 WHERE id=?", (identity,))
            # Delete only generated transport copies after the phone has persisted the result.
            self.cleanup_transport(identity)
    def bootstrap(self):
        legacy = read_json(self.root / "legacy.json", {"cards": [], "hunts": [], "hotCards": [], "hotCheckedAt": None})
        legacy["collections"] = self.checklists()
        for item in legacy["cards"]:
            job = self.get(item["record"]["id"])
            if job:
                item["record"]["state"] = job["status"]
                item["record"]["analysis"] = job["analysis"]
                item["record"]["error"] = job["error"]
        return legacy

class JobStop:
    def __init__(self, stop, repo, identity): self.stop = stop; self.repo = repo; self.identity = identity
    def is_set(self): return self.stop.is_set() or self.repo.is_discarded(self.identity)

class Worker(threading.Thread):
    def __init__(self, repo, config, stop): super().__init__(daemon=True); self.repo = repo; self.config = config; self.stop = stop
    def run(self):
        while not self.stop.is_set():
            try: identity = self.repo.next()
            except Exception:
                # A dead worker must not leave an apparently healthy listener behind.
                self.stop.set(); return
            if not identity: self.stop.wait(2); continue
            try:
                pending = self.repo.get(identity)
                if pending and pending.get("analysis"):
                    # public() can contain a transient price view. Never copy it
                    # into transport files that can outlive the provider TTL.
                    if self.repo.card_prices_enabled:
                        pending["analysis"]["insights"]["marketReferences"] = []
                        pending["analysis"]["insights"]["marketBullets"] = []
                        pending["analysis"]["insights"]["sourceChecks"] = []
                    atomic_json(self.repo.jobroot / identity / "identification.json", {"analysis": pending["analysis"]})
                result = run_codex(self.repo.jobroot / identity, self.repo.catalog, self.config, JobStop(self.stop, self.repo, identity))
                if not result["analysis"].get("identityConfirmed"):
                    result["matches"] = [row[1] for row in candidates(result["analysis"], self.repo.checklists(), capture_hints(self.repo.jobroot / identity))[:5]]
                    result["matchNotice"] = review_notice(result["analysis"], self.repo.catalog)
                if self.repo.card_prices_enabled and not JobStop(self.stop, self.repo, identity).is_set():
                    self.repo.card_prices.lookup(result["analysis"])
                if JobStop(self.stop, self.repo, identity).is_set(): raise InterruptedError("Job stopped")
                self.repo.finish(identity, result)
            except InterruptedError:
                self.repo.requeue(identity)
                if self.stop.is_set(): return
            except RuntimeError as error: self.repo.fail(identity, str(error))
            except Exception: self.repo.fail(identity, "Analyse konnte nicht sicher geprüft werden. Bitte erneut versuchen.")
            finally:
                if self.repo.is_discarded(identity): self.repo.cleanup_transport(identity)

class IdentificationWorker(threading.Thread):
    """An independent photo-only lane. A long market job cannot block new scans."""
    def __init__(self, repo, config, stop): super().__init__(daemon=True); self.repo = repo; self.config = config; self.stop = stop
    def run(self):
        while not self.stop.is_set():
            try: identity = self.repo.next_identification()
            except Exception: self.stop.set(); return
            if not identity: self.stop.wait(0.4); continue
            try:
                output = run_identification(self.repo.jobroot / identity, self.repo.catalog, self.config, JobStop(self.stop, self.repo, identity))
                if self.repo.wants_matches(identity):
                    diagnostics = {}
                    output["matches"] = rank_matches(self.repo.jobroot / identity, output["analysis"], self.repo.checklists(), self.config, JobStop(self.stop, self.repo, identity), diagnostics=diagnostics)
                    output["matchNotice"] = diagnostics.get("status", "catalog")
                else:
                    output["matches"] = [row[1] for row in candidates(output["analysis"], self.repo.checklists(), capture_hints(self.repo.jobroot / identity))[:5]]
                    output["matchNotice"] = review_notice(output["analysis"], self.repo.catalog)
                self.repo.identify(identity, output)
            except InterruptedError:
                self.repo.requeue(identity)
                if self.stop.is_set(): return
            except Exception: self.repo.defer_identification(identity)
            finally:
                if self.repo.is_discarded(identity): self.repo.cleanup_transport(identity)

def handler(repo, token):
    class Handler(BaseHTTPRequestHandler):
        server_version = "CardScout/1"
        def log_message(self, *args): pass
        def setup(self): super().setup(); self.connection.settimeout(30)
        def send(self, status, body):
            data = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status); self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
        def authorized(self):
            supplied = self.headers.get("Authorization", "")
            if not hmac.compare_digest(supplied.encode(), ("Bearer " + token).encode()): self.send(401, {"error": "Mac oder Server neu verbinden."}); return False
            return True
        def do_GET(self):
            if not self.authorized(): return
            if self.path == "/v1/ping": return self.send(200, {"status": "ok", "version": "1", "analysisVersion": str(ANALYSIS_VERSION), "fastPipelineVersion": "1", "matchPipelineVersion": "1", "catalogRevision": hashlib.sha256(json.dumps(repo.catalog, sort_keys=True).encode()).hexdigest(), "referenceImagesRevision": repo.references()["revision"], "queueCapacity": str(MAX_QUEUE), "chaseRevision": repo.chases["revision"] if repo.chases else ""})
            if self.path == "/v1/chases": return self.send(200, repo.chases) if repo.chases else self.send(503, {"error": "Preiskatalog nicht verfügbar."})
            if self.path.startswith("/v1/market/"):
                product = self.path.removeprefix("/v1/market/")
                if product in PRODUCTS: return self.send(200, repo.market.status(product))
            if self.path == "/v1/reference-images/coverage": return self.send(200, reference_coverage(repo.catalog, repo.references()))
            if self.path == "/v1/checklists": return self.send(200, repo.checklists())
            if self.path == "/v1/bootstrap": return self.send(200, repo.bootstrap())
            if self.path.startswith("/v1/jobs/"):
                identity = self.path.removeprefix("/v1/jobs/")
                if UUID.fullmatch(identity):
                    job = repo.get(identity)
                    return self.send(200 if job else 404, job or {"error": "Karte nicht gefunden."})
            self.send(404, {"error": "Nicht gefunden."})
        def do_POST(self):
            if not self.authorized(): return
            try:
                if self.headers.get("Transfer-Encoding"): raise ValueError("Nicht unterstützte Übertragung.")
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= MAX_BODY: return self.send(413, {"error": "Fotos zu groß."})
                if self.headers.get_content_type() != "application/json": return self.send(415, {"error": "JSON erwartet."})
                body = self.rfile.read(length)
                if len(body) != length: raise ValueError("Übertragung unvollständig.")
                data = json.loads(body)
                if not isinstance(data, dict): raise ValueError("Ungültige Anfrage.")
                if self.path == "/v1/jobs": return self.send(202, repo.submit(data))
                if self.path.startswith("/v1/market/"):
                    product = self.path.removeprefix("/v1/market/")
                    if product in PRODUCTS: return self.send(202, repo.market.refresh(product))
                parts = self.path.strip("/").split("/")
                if len(parts) == 4 and parts[:2] == ["v1", "jobs"] and UUID.fullmatch(parts[2]):
                    if parts[3] == "prices" and repo.card_prices_enabled:
                        job = repo.get(parts[2])
                        if not job or job["status"] == "cancelled": return self.send(404, {"error": "Karte nicht gefunden."})
                        if job["status"] == "analyzed" and job.get("analysis"): repo.card_prices.start(job["analysis"])
                        return self.send(202, repo.get(parts[2]))
                    if parts[3] == "retry": return self.send(200, repo.retry(parts[2]))
                    if parts[3] == "ack": repo.ack(parts[2]); return self.send(200, {"status": "ok"})
                    if parts[3] == "discard": repo.discard(parts[2]); return self.send(200, {"status": "cancelled"})
                self.send(404, {"error": "Nicht gefunden."})
            except QueueFull: self.send(429, {"error": "Analyse-Dienst ausgelastet. Deine Fotos bleiben auf dem iPhone und werden später hochgeladen."})
            except (ValueError, KeyError, TypeError): self.send(400, {"error": "Anfrage ungültig oder Foto nicht lesbar."})
            except (BrokenPipeError, ConnectionResetError, TimeoutError): pass
            except Exception: self.send(500, {"error": "Analyse-Dienst konnte die Karte nicht speichern."})
    return Handler

def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--data", type=Path, required=True); args = parser.parse_args()
    os.umask(0o077)
    config = read_json(args.data / "config.json", {})
    # A single launch agent owns the queue. Refuse duplicate processes before recovering jobs.
    import fcntl
    lockfile = (args.data / "service.lock").open("a")
    fcntl.flock(lockfile, fcntl.LOCK_EX | fcntl.LOCK_NB)
    repo = Repository(args.data)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(args.data / "server.crt", args.data / "server.key")
    class TLSServer(ThreadingHTTPServer):
        daemon_threads = True
        def get_request(self):
            connection, address = super().get_request(); connection.settimeout(10)
            try: return context.wrap_socket(connection, server_side=True), address
            except Exception: connection.close(); raise
    http = TLSServer((config.get("bind", "0.0.0.0"), config["port"]), handler(repo, config["token"]))
    http.timeout = 1
    stop = threading.Event(); worker = Worker(repo, config, stop); worker.start()
    identity_worker = IdentificationWorker(repo, config, stop); identity_worker.start()
    for sig in (signal.SIGTERM, signal.SIGINT): signal.signal(sig, lambda *_: stop.set())
    last_purge = time.monotonic()
    try:
        while not stop.is_set():
            http.handle_request()
            if time.monotonic() - last_purge >= 60:
                # Expire temporary market data even when no phone is connected.
                try:
                    with repo.market.condition: repo.market.purge()
                    repo.card_prices.purge()
                except OSError: pass
                last_purge = time.monotonic()
    finally:
        stop.set(); repo.market.stop.set()
        repo.card_prices.executor.shutdown(wait=False, cancel_futures=True)
        with repo.market.condition: repo.market.condition.notify_all()
        http.server_close(); worker.join(timeout=15); identity_worker.join(timeout=15)

if __name__ == "__main__": main()
