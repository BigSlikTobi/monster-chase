#!/usr/bin/env python3
"""One-way import. Never changes or deletes the hosted collection."""
import argparse
import base64
import json
from pathlib import Path
from server import Repository, atomic_json, read_json

def migrate(folder, root):
    cards = read_json(folder / "cards.json", {})["cards"]
    if len(cards) >= 100: raise ValueError("Export may be paginated; obtain the full export first.")
    hot = read_json(folder / "hot.json", {})
    hunts = read_json(folder / "hunts.json", {})
    repo = Repository(root)
    existing = read_json(root / "legacy.json", {"cards": [], "hunts": [], "hotCards": [], "hotCheckedAt": None})
    for c in cards:
        if any(i["record"]["id"] == c["id"] for i in existing["cards"]): continue
        front = base64.b64encode((folder / (c["id"] + "-front.jpg")).read_bytes()).decode()
        back_path = folder / (c["id"] + "-back.jpg")
        back = base64.b64encode(back_path.read_bytes()).decode() if back_path.exists() else None
        # Re-analyze through the same production queue; no manual draft or canned AI result.
        job = repo.submit({"id": c["id"], "front": front, "back": back})
        record = {"id": c["id"], "createdAt": c["createdAt"], "state": job["status"], "frontFile": c["id"] + "-front.jpg", "backFile": c["id"] + "-back.jpg" if back else None, "analysis": job["analysis"], "error": job["error"]}
        existing["cards"].append({"record": record, "front": front, "back": back})
    for p in hunts.get("products", []):
        for h in p.get("targets", []):
            if any(i["id"] == h["id"] for i in existing["hunts"]): continue
            existing["hunts"].append({"id": h["id"], "label": h["label"], "productName": p["name"], "player": h.get("player"), "imageURL": None, "sourceURL": h.get("sourceUrl"), "status": h["status"]})
    existing["hotCards"] = hot.get("cards", [])
    existing["hotCheckedAt"] = (hot.get("board") or {}).get("researchedAt")
    atomic_json(root / "legacy.json", existing)
    print(json.dumps({"cards": len(existing["cards"]), "hunts": len(existing["hunts"]), "hotCards": len(existing["hotCards"])}))

if __name__ == "__main__":
    p = argparse.ArgumentParser(); p.add_argument("--input", type=Path, required=True); p.add_argument("--data", type=Path, required=True); a = p.parse_args(); migrate(a.input, a.data)
