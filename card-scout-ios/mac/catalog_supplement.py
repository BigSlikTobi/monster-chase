"""Add source-backed missing checklist rows without replacing collector assignments."""
from copy import deepcopy
import json
from pathlib import Path
import re
from analysis import validate_schema
from schema import COLLECTION

SOURCE_HASH = "590ad763a6695b43db60dd1395a271c47b262f8084a40b2ef3511cd8001b9ae5"


def comparable(value):
    return re.sub(r"[^a-z0-9]", "", (value or "").casefold())


def merge(existing, supplement):
    optic = supplement.get("sourceEdition") == "2025-optic-orange-scope-reviewed-2026-10-20"
    bowman = supplement.get("sourceEdition") in ("2026-bowman-nfl-base", "2026-bowman-football-base")
    prospects = supplement.get("sourceEdition") == "2026-bowman-football-base"
    expected_hash = "acc2dadf884b603f889445367671b6817eebb1f51a0101d7c014a946cd1a1b6b" if bowman else SOURCE_HASH
    if supplement.get("version") != 1 or (not optic and supplement.get("sourceSHA256") != expected_hash):
        raise ValueError("Unrecognized checklist edition")
    additions = supplement["collections"]
    if not isinstance(additions, list) or len(additions) != (4 if prospects else 2 if bowman else 1 if optic else 22): raise ValueError("Incomplete supplement")
    seen = set()
    for c in additions:
        validate_schema(c, COLLECTION)
        if c["id"] in seen or c["year"] != (2026 if bowman else 2025) or c["brand"] != ("Panini" if optic else "Topps") or c["name"] != ("Bowman" if bowman else "Donruss Optic" if optic else "Topps Chrome"):
            raise ValueError("Wrong release or duplicate collection")
        if bowman:
            prefixes = {"Base": "", "Chrome Base": "BCV-"}
            if prospects: prefixes.update({"Paper Prospects": "BPP-", "Chrome Prospects": "BCP-"})
            if c["subset"] not in prefixes: raise ValueError("Wrong Bowman family")
            prefix = prefixes[c["subset"]]
            expected = {prefix + str(n) for n in range(1, 201)}
            count = 200
            if "Prospects" in c["subset"]:
                expected.add("BPP-ALT1" if prefix == "BPP-" else "ALT-1")
                count = 201
            if not prefix: expected -= {"66", "68"}
            if (c["parallel"] is not None
                    or c["id"] != "2026-topps-bowman-" + c["subset"].lower().replace(" ", "-")
                    or {r["number"] for r in c["cards"]} != expected or c["expectedCount"] != count
                    or c["checklistComplete"] != bool(prefix)
                    or c["sourceURL"] != "https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2026_Bowman_Football_Checklist.pdf?v=1790867994"):
                raise ValueError("Wrong Bowman membership")
        if optic and (c["id"] != "2025-panini-donruss-optic-base-orange-scope" or c["parallel"] != "Orange Scope"
                      or c["subset"] != "Base" or c["expectedCount"] != 300
                      or {r["number"] for r in c["cards"]} != {str(n) for n in range(1, 301)}
                      or c["sourceURL"] != "https://www.beckett.com/news/2025-donruss-optic-football-cards/"):
            raise ValueError("Wrong Optic membership")
        seen.add(c["id"])
        if c["sourceURL"] != supplement["sourceURL"] or len(c["cards"]) != (len(expected) if bowman else c["expectedCount"]):
            raise ValueError("Incomplete source provenance or count")
        if len({r["number"] for r in c["cards"]}) != len(c["cards"]): raise ValueError("Duplicate checklist row")
    result = deepcopy(existing)
    by_id = {c["id"]: c for c in result}
    report = dict(addedCollections=0, addedRows=0, conflicts=[])
    for incoming in additions:
        current = by_id.get(incoming["id"])
        if current is None:
            result.append(deepcopy(incoming))
            report["addedCollections"] += 1; report["addedRows"] += len(incoming["cards"])
            continue
        if any(current.get(k) != incoming.get(k) for k in ("year", "brand", "name", "subset", "parallel")):
            report["conflicts"].append({"collectionID": incoming["id"], "reason": "scope"}); continue
        old = {r["number"]: r for r in current["cards"]}
        conflict = [r["number"] for r in incoming["cards"] if r["number"] in old
                    and any(comparable(old[r["number"]].get(k)) != comparable(r.get(k)) for k in ("player", "team"))]
        if conflict:
            report["conflicts"].append({"collectionID": incoming["id"], "numbers": conflict}); continue
        missing = [deepcopy(r) for r in incoming["cards"] if r["number"] not in old]
        current["cards"].extend(missing); report["addedRows"] += len(missing)
        current["expectedCount"] = incoming["expectedCount"]
        current["checklistComplete"] = len(current["cards"]) == incoming["expectedCount"]
        current["sourceURL"] = incoming["sourceURL"]; current["checkedAt"] = incoming["checkedAt"]
    return result, report


def load_into(existing, path):
    path = Path(path)
    if not path.exists(): return existing, {"status": "absent"}
    try:
        if path.stat().st_size > 4_000_000: raise ValueError("Oversized supplement")
        return merge(existing, json.loads(path.read_text()))
    except (OSError, ValueError, KeyError, TypeError):
        return existing, {"status": "invalid"}


def load_all(existing, root):
    reports = {}
    for name in ("chrome", "optic", "bowman"):
        existing, reports[name] = load_into(existing, Path(root) / f"{name}-checklist-supplement.json")
    return existing, reports
