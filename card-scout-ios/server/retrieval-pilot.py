#!/usr/bin/env python3
"""Read-only production-card pilot; private temporary copies, no queue writes."""
import json
from pathlib import Path
import shutil
import sqlite3
import sys
import tempfile
import time

sys.path.insert(0, "/opt/cardscout/service")
from analysis import run_codex

root = Path("/var/lib/cardscout/data")
config = json.loads((root / "config.json").read_text())
config.update(retrievalEnabled=True, retrievalBrowserEnabled=True, webSearch="disabled", fallbackModel=None)
known = json.loads((root / "collections.json").read_text())
db = sqlite3.connect("file:" + str(root / "queue.sqlite3") + "?mode=ro", uri=True)
rows = [(key, json.loads(raw)) for key, raw in db.execute("SELECT id,result FROM jobs WHERE result IS NOT NULL ORDER BY updated_at DESC")]
db.close()
confirmed = [(key, r) for key, r in rows if r["analysis"].get("identityConfirmed") and r.get("collection")][:2]
photo = next(((key, r) for key, r in rows if (root / "jobs" / key / "front.jpg").exists() and r["analysis"].get("player") and r["analysis"].get("year")), None)
tests = [(key, r, "market-refresh") for key, r in confirmed]
if photo: tests.append((*photo, "photo-analysis"))
summaries = []
for key, previous, mode in tests:
    with tempfile.TemporaryDirectory(prefix="retrieval-pilot-", dir=root.parent) as temporary:
        folder = Path(temporary)
        if mode == "market-refresh": (folder / "refresh.json").write_text(json.dumps(previous))
        else:
            (folder / "identification.json").write_text(json.dumps(previous))
            for side in ("front.jpg", "back.jpg"):
                source = root / "jobs" / key / side
                if source.exists(): shutil.copyfile(source, folder / side)
        started = time.monotonic()
        summary = {"player": previous["analysis"]["player"], "mode": mode}
        try:
            output = run_codex(folder, known, config)
            a = output["analysis"]
            summary.update(status="passed", referenceCount=len(a["insights"]["marketReferences"]),
                           identityConfirmed=a["identityConfirmed"], recommendation=a["recommendation"])
        except Exception as error:
            summary.update(status="failed", errorType=type(error).__name__, error=str(error)[:200])
        summary["seconds"] = round(time.monotonic() - started, 2)
        evidence = folder / "retrieval.json"
        if evidence.exists():
            bundle = json.loads(evidence.read_text())
            summary["pages"] = [{"host": __import__("urllib.parse", fromlist=["urlsplit"]).urlsplit(p["url"]).hostname,
                                  "status": p["status"], "httpStatus": p.get("httpStatus")} for p in bundle["pages"]]
        log = folder / "worker.log"
        if log.exists():
            summary["api"] = [json.loads(line.split("[card-scout] ", 1)[1]) for line in log.read_text().splitlines() if line.startswith("[card-scout] {")]
        summaries.append(summary)
        print(json.dumps(summary), flush=True)
destination = root.parent / "retrieval-pilot-20261016.json"
destination.write_text(json.dumps(summaries, indent=2)); destination.chmod(0o600)
if not tests or any(s["status"] != "passed" for s in summaries): sys.exit(1)
