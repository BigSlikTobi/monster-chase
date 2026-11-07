"""Source-backed identity context, independent of owned cards and price data.

Catalog imports preserve claims as unverified. Source checks detect changes;
they never parse a changed page into facts or change the active catalog.
"""
import argparse
from copy import deepcopy
import datetime as dt
import fcntl
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import tempfile
import urllib.error
import urllib.request
from urllib.parse import urlsplit

HOSTS = ("topps.com", "cdn.shopify.com", "paniniamerica.net", "beckett.com", "tcdb.com",
         "breakninja.com", "checklistcenter.com", "checklistinsider.com", "steelcitycollectibles.com",
         "setlistcards.com", "tracenchase.com")
STATES = {"imported_unverified", "reviewed", "disputed", "retired"}
MAX_BYTES = 8_000_000


def digest(value):
    raw = value if isinstance(value, bytes) else json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()


def slug(value):
    return re.sub(r"[^a-z0-9]+", "-", str(value).lower()).strip("-")


def today():
    return dt.datetime.now(dt.timezone.utc).date().isoformat()


def source_url(value):
    try:
        u = urlsplit(value)
        host = u.hostname or ""
        if u.scheme != "https" or u.username or u.password or u.port not in (None, 443):
            raise ValueError("Source must use public HTTPS without credentials")
        if not any(host == h or host.endswith("." + h) for h in HOSTS):
            raise ValueError("Source host needs explicit registration")
        try:
            ipaddress.ip_address(host)
        except ValueError:
            pass
        else:
            raise ValueError("IP sources are not allowed")
        return value
    except (TypeError, AttributeError) as error:
        raise ValueError("Invalid source URL") from error


def seal(catalog):
    catalog = deepcopy(catalog)
    catalog.pop("revision", None)
    catalog["revision"] = digest(catalog)
    return catalog


def read(path):
    path = Path(path)
    if path.stat().st_size > 64_000_000:
        raise ValueError("Catalog/input too large")
    return json.loads(path.read_text())


def atomic_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix="." + path.name)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def product_key(year, brand, name):
    # Only explicit spelling aliases. Never merge years or neighboring products.
    if brand == "Topps" and name == "Topps Flagship Football":
        name = "Topps Flagship"
    return f"{year}-{slug(brand)}-{slug(name)}"


def bootstrap(inputs, chase_catalog=None, reference_audit=None):
    products, families, binders, variants, sources, imports = {}, {}, {}, {}, {}, []
    issues = []

    def register_source(url, kind="checklist"):
        if not url:
            return None
        sid = "source-" + digest(url.encode())[:20]
        try:
            source_url(url)
            fetchable = True
        except ValueError:
            fetchable = False
        sources.setdefault(sid, {"id": sid, "url": url, "kind": kind, "fetchAllowed": fetchable,
            "verification": "imported_unverified", "priority": "manufacturer" if (urlsplit(url).hostname or "").endswith(("topps.com", "paniniamerica.net")) else "secondary_or_hosted_document",
            "lastSuccessfulCheck": None})
        return sid

    for label, document in inputs:
        collections = document.get("collections", []) if isinstance(document, dict) else document
        if not isinstance(collections, list):
            raise ValueError("Expected binder list or library collections")
        iid = "import-" + digest({"label": label, "collections": collections})[:20]
        imports.append({"id": iid, "label": label, "snapshotSHA256": digest(collections), "importedAt": today()})
        for c in collections:
            if not all(c.get(k) for k in ("id", "name", "brand", "year", "subset")):
                raise ValueError("Missing binder identity")
            pid = product_key(c["year"], c["brand"], c["name"])
            fid = pid + ":" + slug(c["subset"])
            vid = fid + ":" + slug(c.get("parallel") or "Base")
            sid = register_source(c.get("sourceURL"))
            products.setdefault(pid, {"id": pid, "name": c["name"], "brand": c["brand"], "year": c["year"], "discoveryOnly": False})
            family = families.setdefault(fid, {"id": fid, "productID": pid, "name": c["subset"], "verification": "imported_unverified", "rows": []})
            rows = [{k: e.get(k) for k in ("number", "player", "team", "rookie")} for e in c["cards"]]
            for e in rows:
                if not isinstance(e["number"], str) or not e["number"] or not isinstance(e["player"], str) or not e["player"]:
                    raise ValueError("Incomplete checklist row")
            claim = {"importID": iid, "sourceID": sid, "declaredComplete": c.get("checklistComplete", False),
                     "expectedCount": c.get("expectedCount"), "declaredCheckedAt": c.get("checkedAt"), "rowCount": len(rows), "rowsSHA256": digest(rows)}
            binder = binders.setdefault(c["id"], {"id": c["id"], "productID": pid, "familyID": fid, "variantID": vid,
                      "verification": "imported_unverified", "membershipVerified": False, "claims": []})
            if (binder["productID"], binder["familyID"], binder["variantID"]) != (pid, fid, vid):
                raise ValueError("Binder ID reused for a different identity")
            if binder["claims"] and any(x["rowsSHA256"] != claim["rowsSHA256"] for x in binder["claims"]):
                binder["verification"] = "disputed"
                issues.append({"kind": "binder_snapshot_disagreement", "entityID": c["id"], "importID": iid})
            binder["claims"].append(claim)
            unique = {digest({k: e[k] for k in ("number", "player", "team", "rookie")}): e for e in family["rows"]}
            for e in rows:
                key = digest(e)
                if key not in unique:
                    unique[key] = dict(e, evidence=[])
                unique[key]["evidence"].append({"importID": iid, "sourceID": sid, "binderID": c["id"]})
            family["rows"] = sorted(unique.values(), key=lambda e: (e["number"], e["player"]))
            variants.setdefault(vid, {"id": vid, "familyID": fid, "name": c.get("parallel") or "Base", "verification": "imported_unverified",
                    "rules": [], "references": [], "membershipVerified": False})
            if claim["declaredComplete"] and (len(rows) != claim["expectedCount"] or not sid):
                issues.append({"kind": "invalid_completeness_claim", "entityID": c["id"], "importID": iid})
                binder["verification"] = "disputed"

    for f in families.values():
        by_number = {}
        for row in f["rows"]:
            by_number.setdefault(row["number"], set()).add(row["player"])
        if any(len(names) > 1 for names in by_number.values()):
            # Multi-player cards can be legitimate; flag, do not overwrite or merge people.
            issues.append({"kind": "shared_number_needs_review", "entityID": f["id"]})
            f["verification"] = "disputed"

    for p in (chase_catalog or {}).get("products", []):
        pid = product_key(p["year"], "Topps" if p["name"].startswith("Topps") else "Panini", p["name"])
        products.setdefault(pid, {"id": pid, "name": p["name"], "brand": "Topps" if p["name"].startswith("Topps") else "Panini", "year": p["year"], "discoveryOnly": True})
        # Identity/product link only. Never import guide prices or provider images.
        sid = register_source(p.get("sourceURL"), "product_discovery")
        if sid:
            products[pid].setdefault("discoverySourceIDs", []).append(sid)
    # Watch discovery pages as well as pinned files: a publisher can replace a
    # download link without changing the old file at all.
    discovery = {
        "2025-panini-donruss-optic": ["https://blog.paniniamerica.net/2025-donruss-optic-nfl-adds-to-thrilling-championship-chase/", "https://tracenchase.com/_public/catalogs/25DonrussOpticFB_PIS_NPP.pdf"],
        "2026-topps-topps-flagship": ["https://www.topps.com/pages/topps-flagship-football", "https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2026_Topps_Football_Odds.pdf?v=1789491381"],
        "2025-topps-topps-chrome": ["https://www.topps.com/pages/topps-chrome-football"],
    }
    for pid, urls in discovery.items():
        if pid not in products: continue
        for url in urls:
            sid = register_source(url, "discovery_not_identity_proof")
            products[pid].setdefault("discoverySourceIDs", []).append(sid)
            sources[sid]["expectedProductYear"] = products[pid]["year"]
            sources[sid]["newLinksRequireProductIdentityReview"] = True
    if "2025-topps-topps-chrome" in products:
        issues.append({"kind": "discovery_page_year_drift", "entityID": "2025-topps-topps-chrome",
            "url": "https://www.topps.com/pages/topps-chrome-football", "expectedYear": 2025, "observedYear": 2026,
            "observedAt": "2026-10-16", "action": "Retain pinned 2025 documents. Never replace the 2025 checklist with the generic page's current 2026 download."})
    if reference_audit:
        evidence_id = "audit-" + digest(reference_audit)[:20]
        for card in reference_audit["cards"]:
            pid = product_key(2025, "Panini", "Donruss Optic")
            fid = pid + ":base"
            if fid not in families:
                continue
            vid = fid + ":" + slug(card["parallel"])
            variant = variants.setdefault(vid, {"id": vid, "familyID": fid, "name": card["parallel"],
                "verification": "imported_unverified", "rules": [], "references": [], "membershipVerified": False})
            source_ids = [register_source(url, "variant_evidence") for url in card["sources"]]
            variant["references"].append({"id": "photo-" + digest(card["originalPhotoSHA256"])[:20],
                "player": card["player"], "cardNumber": card["cardNumber"], "serialNumber": card.get("serialNumber"),
                "photoSHA256": list(card["originalPhotoSHA256"].values()), "proposedConfidence": card["confidence"],
                "verification": "imported_unverified", "assetStatus": "not_installed", "evidenceID": evidence_id,
                "sourceIDs": source_ids, "useForDecisions": False})
            if card.get("serialNumber"):
                variant["rules"].append({"kind": "serial_denominator", "value": int(card["serialNumber"].split("/")[1]),
                    "verification": "corroborated", "observedCardNumbers": [card["cardNumber"]], "sourceIDs": source_ids,
                    "evidenceID": evidence_id, "note": "A print tier alone does not prove the variant. Validate visual pattern and checklist applicability too."})
        issues.append({"kind": "incorrect_historical_reference_label", "entityID": "2025-panini-donruss-optic:base:fire",
            "evidenceID": evidence_id, "detail": reference_audit["originalReferenceLabelError"],
            "action": "Never use the Derrick Harmon Orange Scope photo as a Fire reference. Existing binder/checklist identity and owned cards are unchanged."})
    catalog = {"schemaVersion": 1, "generatedAt": today(), "imports": imports,
        "policy": {"includeUnknownChoice": True, "maxDecisionChoices": 255, "sourceChangeNeverAutoPublishes": True,
                   "newReleaseCheckDays": 1, "activeProductCheckDays": 7, "stableProductCheckDays": 30,
                   "automaticAssignmentEnabled": False},
        "products": list(products.values()), "families": list(families.values()), "binders": list(binders.values()),
        "variants": list(variants.values()), "sources": list(sources.values()), "issues": issues, "reviewEvidence": []}
    for key in ("products", "families", "binders", "variants", "sources", "imports"):
        catalog[key].sort(key=lambda x: x["id"])
    return validate(seal(catalog))


def validate(c):
    if c.get("schemaVersion") != 1 or c.get("revision") != seal(c)["revision"]:
        raise ValueError("Invalid schema or catalog revision")
    indexes = {}
    for key in ("products", "families", "binders", "variants", "sources", "imports"):
        records = c[key]
        indexes[key] = {x["id"]: x for x in records}
        if len(indexes[key]) != len(records):
            raise ValueError("Duplicate catalog ID")
    for f in c["families"]:
        if f["productID"] not in indexes["products"] or f["verification"] not in STATES:
            raise ValueError("Invalid family")
        if len({digest({k: r[k] for k in ("number", "player", "team", "rookie")}) for r in f["rows"]}) != len(f["rows"]):
            raise ValueError("Duplicate checklist rows")
        for r in f["rows"]:
            if not r["evidence"] or any(e["importID"] not in indexes["imports"] or (e["sourceID"] is not None and e["sourceID"] not in indexes["sources"]) for e in r["evidence"]):
                raise ValueError("Checklist row lacks source lineage")
    for v in c["variants"]:
        if v["familyID"] not in indexes["families"] or v["verification"] not in STATES:
            raise ValueError("Invalid variant")
    for b in c["binders"]:
        v = indexes["variants"].get(b["variantID"])
        if not v or v["familyID"] != b["familyID"] or indexes["families"][b["familyID"]]["productID"] != b["productID"]:
            raise ValueError("Cross-product binder link")
        if b["verification"] not in STATES:
            raise ValueError("Invalid binder verification")
    # Review status cannot be raised just by editing a flag in a JSON file.
    reviewed = {}
    for evidence in c.get("reviewEvidence", []):
        if evidence.get("reviewer") and evidence.get("sourceIDs") and all(s in indexes["sources"] for s in evidence["sourceIDs"]) and evidence.get("scope") and evidence.get("reviewedAt"):
            reviewed[evidence["entityID"]] = evidence
    for key in ("families", "variants", "binders"):
        for entity in c[key]:
            if entity["verification"] == "reviewed":
                evidence = reviewed.get(entity["id"], {})
                expected_scope = {"families": "checklist_rows", "variants": "variant_rules", "binders": "binder_membership"}[key]
                content = {k:v for k,v in entity.items() if k != "verification"}
                if evidence.get("scope") != expected_scope or evidence.get("entitySHA256") != digest(content):
                    raise ValueError("Reviewed facts need a matching, scoped review receipt")
    for v in c["variants"]:
        for ref in v["references"]:
            if ref.get("useForDecisions"):
                evidence = reviewed.get(ref["id"], {})
                if ref.get("verification") != "reviewed" or ref.get("assetStatus") != "installed" or evidence.get("scope") != "reference_photo" or evidence.get("entitySHA256") != digest({k:x for k,x in ref.items() if k != "verification"}):
                    raise ValueError("Decision reference photos need installed assets and a matching review receipt")
    if c["policy"].get("automaticAssignmentEnabled") is not False:
        raise ValueError("Automatic assignment is not enabled by this catalog version")
    return c


def coverage(c):
    validate(c)
    return {"revision": c["revision"], "products": [{"id": p["id"], "product": f'{p["year"]} {p["name"]}',
        "binders": sum(b["productID"] == p["id"] for b in c["binders"]),
        "families": sum(f["productID"] == p["id"] for f in c["families"]),
        "candidateRows": sum(len(f["rows"]) for f in c["families"] if f["productID"] == p["id"]),
        "discoveryOnly": p["discoveryOnly"]} for p in c["products"]],
        "binderCount": len(c["binders"]), "sourceCount": len(c["sources"]), "issueCount": len(c["issues"]),
        "reviewedFamilies": sum(f["verification"] == "reviewed" for f in c["families"]),
        "variantsWithReviewedRules": sum(v["verification"] == "reviewed" and bool(v["rules"]) for v in c["variants"]),
        "variantsWithReviewedImages": sum(any(r.get("verification") == "reviewed" for r in v["references"]) for v in c["variants"])}


def context(c, binder_id, *, player=None, number=None, offset=0, limit=200):
    validate(c)
    if not 1 <= limit <= 254 or offset < 0:
        raise ValueError("Reserve one of 255 choices for unknown; invalid page")
    b = next(b for b in c["binders"] if b["id"] == binder_id)
    f = next(f for f in c["families"] if f["id"] == b["familyID"])
    rows = [r for r in f["rows"] if (not player or slug(player) in slug(r["player"])) and (not number or r["number"] == number)]
    return {"catalogRevision": c["revision"], "binder": b, "family": {k:v for k,v in f.items() if k != "rows"},
        "candidates": [{k:r[k] for k in ("number", "player", "team", "rookie")} for r in rows[offset:offset+limit]], "totalCandidates": len(rows),
        "sourceIDs": sorted({e["sourceID"] for r in rows[offset:offset+limit] for e in r["evidence"] if e["sourceID"]}),
        "evidenceAvailableInCatalog": True,
        "nextOffset": offset + limit if offset + limit < len(rows) else None,
        "variants": [v for v in c["variants"] if v["familyID"] == f["id"] and v["verification"] != "retired"],
        "includeUnknownChoice": True, "automaticAssignmentAllowed": False,
        "usage": "Provisional candidate context only. A binder match, checklist number, color or serial denominator alone does not prove an exact variant."}


class SourceRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        source_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def check_sources(c, cache_dir, state, source_ids=None, max_sources=4):
    validate(c)
    if not 1 <= max_sources <= 40:
        raise ValueError("Source check budget must be 1–40")
    cache_dir = Path(cache_dir)
    state = deepcopy(state)
    state.setdefault("sources", {})
    chosen = [s for s in c["sources"] if s["fetchAllowed"] and (source_ids is None or s["id"] in source_ids)]
    if source_ids and set(source_ids) - {s["id"] for s in chosen}:
        raise ValueError("Unknown or blocked source requested")
    chosen.sort(key=lambda s: state["sources"].get(s["id"], {}).get("lastAttempt", ""))
    report = []
    for source in chosen[:max_sources]:
        sid, url = source["id"], source_url(source["url"])
        old = state["sources"].get(sid, {})
        entry = dict(old, lastAttempt=dt.datetime.now(dt.timezone.utc).isoformat())
        headers = {"User-Agent": "CardScoutContext/1.0 (bounded source change check)"}
        if old.get("etag"):
            headers["If-None-Match"] = old["etag"]
        if old.get("lastModified"):
            headers["If-Modified-Since"] = old["lastModified"]
        try:
            with urllib.request.build_opener(SourceRedirects()).open(urllib.request.Request(url, headers=headers), timeout=12) as response:
                if response.status != 200:
                    raise ValueError("Unexpected source status")
                data = response.read(MAX_BYTES + 1)
                if not data or len(data) > MAX_BYTES:
                    raise ValueError("Empty/oversized source")
                sha = digest(data)
                cache_dir.mkdir(parents=True, exist_ok=True)
                dest = cache_dir / sha
                if not dest.exists():
                    fd, temp = tempfile.mkstemp(dir=cache_dir)
                    try:
                        with os.fdopen(fd, "wb") as f:
                            f.write(data)
                        os.replace(temp, dest)
                    finally:
                        if os.path.exists(temp): os.unlink(temp)
                status = "unchanged" if old.get("sha256") == sha else ("changed_needs_review" if old.get("sha256") else "first_capture_needs_review")
                entry.update(status=status, sha256=sha, lastSuccess=entry["lastAttempt"], finalURL=response.url,
                    etag=response.headers.get("ETag"), lastModified=response.headers.get("Last-Modified"))
        except urllib.error.HTTPError as error:
            if error.code == 304 and old.get("sha256") and (cache_dir / old["sha256"]).exists() and digest((cache_dir / old["sha256"]).read_bytes()) == old["sha256"]:
                entry.update(status="unchanged", lastSuccess=entry["lastAttempt"])
            else:
                entry.update(status="unavailable", httpStatus=error.code)
            error.close()
        except (ValueError, OSError, urllib.error.URLError) as error:
            entry.update(status="unavailable", errorType=type(error).__name__)
        state["sources"][sid] = entry
        report.append({"sourceID": sid, "url": url, "status": entry["status"], "sha256": entry.get("sha256"),
                       "reviewRequired": bool(entry.get("sha256")) and entry.get("sha256") != entry.get("reviewedSHA256"),
                       "factsVerified": False, "catalogChanged": False})
    return state, report


def catalog_diff(before, after):
    validate(before); validate(after)
    result = {}
    for section in ("products", "families", "binders", "variants", "sources"):
        a, b = ({x["id"]: x for x in c[section]} for c in (before, after))
        result[section] = {"added": sorted(b.keys()-a.keys()), "removed": sorted(a.keys()-b.keys()),
                           "changed": sorted(k for k in a.keys() & b.keys() if a[k] != b[k])}
    return result


def stage_import(base, incoming):
    """Add binder discoveries without deleting existing curated rules or references."""
    validate(base); validate(incoming)
    result = deepcopy(base)
    for section in ("products", "sources", "imports", "families", "variants", "binders"):
        index = {x["id"]: x for x in result[section]}
        for new in incoming[section]:
            old = index.get(new["id"])
            if old is None:
                result[section].append(deepcopy(new)); index[new["id"]] = result[section][-1]
                continue
            if section == "binders":
                if any(old[k] != new[k] for k in ("productID", "familyID", "variantID")):
                    raise ValueError("Existing binder cannot be reassigned by an import")
                if any(a["rowsSHA256"] != b["rowsSHA256"] for a in old["claims"] for b in new["claims"]):
                    old["verification"] = "disputed"
                    result["issues"].append({"kind": "binder_snapshot_disagreement", "entityID": old["id"]})
                old["claims"] += [deepcopy(x) for x in new["claims"] if x not in old["claims"]]
            elif section == "families":
                if old["productID"] != new["productID"]:
                    raise ValueError("Existing family cannot change product")
                keys = {digest({k:r[k] for k in ("number", "player", "team", "rookie")}) for r in old["rows"]}
                for row in new["rows"]:
                    key = digest({k:row[k] for k in ("number", "player", "team", "rookie")})
                    if key not in keys:
                        old["rows"].append(deepcopy(row)); keys.add(key)
                by_number = {}
                for row in old["rows"]: by_number.setdefault(row["number"], set()).add(digest({k:row[k] for k in ("player", "team", "rookie")}))
                if any(len(values) > 1 for values in by_number.values()):
                    old["verification"] = "disputed"
                    result["issues"].append({"kind": "checklist_row_conflict", "entityID": old["id"]})
            elif section == "variants":
                if old["familyID"] != new["familyID"]:
                    raise ValueError("Existing variant cannot change family")
                for field in ("rules", "references"):
                    old[field] += [deepcopy(x) for x in new[field] if x not in old[field]]
            elif section == "products" and not new["discoveryOnly"]:
                old["discoveryOnly"] = False
        result[section].sort(key=lambda x:x["id"])
    result["issues"] += [x for x in incoming["issues"] if x not in result["issues"]]
    # A review of old content never approves added/changed content.
    receipts = {x["entityID"]:x for x in result["reviewEvidence"]}
    for section in ("families", "binders", "variants"):
        for entity in result[section]:
            if entity["verification"] == "reviewed" and receipts[entity["id"]]["entitySHA256"] != digest({k:v for k,v in entity.items() if k != "verification"}):
                entity["verification"] = "imported_unverified"
    result["generatedAt"] = today()
    return validate(seal(result))


def publish(candidate, active, receipt, expected_revision):
    validate(candidate)
    if receipt.get("candidateRevision") != candidate["revision"] or receipt.get("decision") != "approved" or not receipt.get("reviewer"):
        raise ValueError("Publication requires an explicit revision-bound review receipt")
    active = Path(active)
    active.parent.mkdir(parents=True, exist_ok=True)
    with active.with_suffix(active.suffix + ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = validate(read(active)) if active.exists() else None
        if (previous["revision"] if previous else "none") != expected_revision:
            raise ValueError("Active revision changed; review the new diff")
        if previous:
            atomic_json(active.parent/"history"/(previous["revision"]+".json"), previous)
        atomic_json(active.parent/"reviews"/(candidate["revision"]+".json"), receipt)
        atomic_json(active, candidate)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="command", required=True)
    b = sub.add_parser("bootstrap"); b.add_argument("--input", action="append", required=True, help="label=/path/to/binder-list-or-library.json")
    b.add_argument("--chases", type=Path); b.add_argument("--reference-audit", type=Path); b.add_argument("--output", type=Path, required=True)
    b = sub.add_parser("stage-import"); b.add_argument("base", type=Path); b.add_argument("--input", action="append", required=True)
    b.add_argument("--output", type=Path, required=True)
    for name in ("coverage", "validate", "context", "check-sources"):
        q = sub.add_parser(name); q.add_argument("catalog", type=Path)
        if name == "context":
            q.add_argument("binder"); q.add_argument("--player"); q.add_argument("--number"); q.add_argument("--offset", type=int, default=0); q.add_argument("--limit", type=int, default=200)
        if name == "check-sources":
            q.add_argument("--cache", type=Path, required=True); q.add_argument("--state", type=Path, required=True)
            q.add_argument("--source-id", action="append"); q.add_argument("--max-sources", type=int, default=4)
    q = sub.add_parser("diff"); q.add_argument("before", type=Path); q.add_argument("after", type=Path)
    q = sub.add_parser("publish"); q.add_argument("candidate", type=Path); q.add_argument("active", type=Path)
    q.add_argument("--receipt", type=Path, required=True); q.add_argument("--expected-revision", required=True)
    a = p.parse_args()
    if a.command in ("bootstrap", "stage-import"):
        inputs = [(s.partition("=")[0], read(s.partition("=")[2])) for s in a.input]
        if a.command == "bootstrap":
            c = bootstrap(inputs, read(a.chases) if a.chases else None, read(a.reference_audit) if a.reference_audit else None)
        else:
            c = stage_import(read(a.base), bootstrap(inputs))
        atomic_json(a.output, c); result = coverage(c)
    elif a.command == "diff": result = catalog_diff(read(a.before), read(a.after))
    elif a.command == "publish":
        publish(read(a.candidate), a.active, read(a.receipt), a.expected_revision); result = {"published": True}
    else:
        c = validate(read(a.catalog))
        if a.command == "validate": result = {"valid": True, "revision": c["revision"]}
        elif a.command == "coverage": result = coverage(c)
        elif a.command == "context": result = context(c, a.binder, player=a.player, number=a.number, offset=a.offset, limit=a.limit)
        else:
            a.state.parent.mkdir(parents=True, exist_ok=True)
            with a.state.with_suffix(a.state.suffix + ".lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                state, result = check_sources(c, a.cache, read(a.state) if a.state.exists() else {}, a.source_id, a.max_sources)
                atomic_json(a.state, state)
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
