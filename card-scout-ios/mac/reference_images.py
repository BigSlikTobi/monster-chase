"""Reviewed reference-image overlay. Never rewrites checklists or owned cards."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

IMAGE_HOSTS = {"i.ebayimg.com", "images.production.sportscardinvestor.com"}
SOURCE_HOSTS = {"www.ebay.com", "www.ebay.co.uk", "www.ebay.com.au", "www.sportscardspro.com", "www.sportscardinvestor.com", "www.freshdcards.com", "shopwaynecollection.com"}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def identity(collection, card):
    return {"collectionID": collection["id"], "year": collection["year"], "brand": collection["brand"],
            "product": collection["name"], "subset": collection["subset"], "parallel": collection.get("parallel"),
            "number": card["number"], "player": card["player"]}


def safe_url(value, image=False):
    if not isinstance(value, str) or len(value) > 2048: return False
    try:
        url = urlsplit(value)
        if url.scheme != "https" or url.username or url.password or url.port not in (None, 443) or url.fragment: return False
        if image:
            return url.hostname in IMAGE_HOSTS or (url.hostname == "storage.googleapis.com" and url.path.startswith("/images.pricecharting.com/")) or (url.hostname == "cdn.shopify.com" and url.path.startswith(("/s/files/1/0791/7515/6005/", "/s/files/1/0649/1019/6902/"))) or (url.hostname in {"www.freshdcards.com", "shopwaynecollection.com"} and url.path.startswith("/cdn/shop/files/"))
        return url.hostname in SOURCE_HOSTS
    except ValueError:
        return False


def validate(manifest):
    if manifest.get("version") != 1 or not isinstance(manifest.get("records"), list) or len(manifest["records"]) > 20_000:
        raise ValueError("Invalid reference image manifest")
    if manifest.get("revision") != digest(manifest["records"]): raise ValueError("Reference manifest revision mismatch")
    keys, images = set(), {}
    for record in manifest["records"]:
        scope = record["identity"]
        if set(scope) != {"collectionID", "year", "brand", "product", "subset", "parallel", "number", "player"}: raise ValueError("Incomplete reference scope")
        key = (scope["collectionID"], scope["number"])
        if key in keys: raise ValueError("Duplicate reference identity")
        keys.add(key)
        if record.get("status") != "reviewed" or record.get("kind") != "scan" or record.get("reviewer") != "codex-visual": raise ValueError("Unreviewed reference")
        if not record.get("reviewedAt") or not record.get("sourceTitle") or not safe_url(record.get("sourceURL")): raise ValueError("Missing source evidence")
        if not safe_url(record.get("frontURL"), image=True): raise ValueError("Unsafe reference image URL")
        if record.get("backURL") is not None and not safe_url(record["backURL"], image=True): raise ValueError("Unsafe back image URL")
        sha = record.get("sha256", "")
        if not re.fullmatch(r"[a-f0-9]{64}", sha) or min(record.get("width", 0), record.get("height", 0)) < 150: raise ValueError("Missing pixel evidence")
        if sha in images and images[sha] != scope: raise ValueError("Same pixels assigned to different cards or finishes")
        images[sha] = scope
    return manifest


def load(path):
    path = Path(path)
    if not path.exists(): return {"version": 1, "records": [], "revision": ""}
    if path.stat().st_size > 16_000_000: raise ValueError("Reference manifest too large")
    return validate(json.loads(path.read_text()))


def overlay(collections, manifest):
    result = deepcopy(collections)
    records = {(r["identity"]["collectionID"], r["identity"]["number"]): r for r in manifest["records"]}
    for collection in result:
        collection.pop("referenceExample", None)
        for card in collection["cards"]:
            card.pop("referenceImage", None)
            record = records.get((collection["id"], card["number"]))
            if record and record["identity"] == identity(collection, card):
                card["referenceImage"] = {**record["identity"], **{k: record[k] for k in ("frontURL", "sourceURL", "sourceTitle", "reviewedAt", "sha256")}}
                if record.get("backURL"): card["referenceImage"]["backURL"] = record["backURL"]
                if "referenceExample" not in collection: collection["referenceExample"] = card["referenceImage"]
    return result


def coverage(collections, manifest):
    enriched = overlay(collections, manifest)
    rows = [{"id": c["id"], "slots": len(c["cards"]), "exactImages": sum("referenceImage" in r for r in c["cards"])} for c in enriched]
    return {"revision": manifest["revision"], "slots": sum(r["slots"] for r in rows),
            "exactImages": sum(r["exactImages"] for r in rows), "binders": rows,
            "bindersWithImages": sum(r["exactImages"] > 0 for r in rows)}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--collections", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(coverage(json.loads(args.collections.read_text()), load(args.manifest)), indent=2))
