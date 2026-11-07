"""Import NFL base and college prospects from the pinned 2026 Bowman PDF.

Inserts, autographs and parallels need their own verified membership.
The published paper list repeats #68 and omits #66; quarantine both #68 rows.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess

SOURCE = "https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2026_Bowman_Football_Checklist.pdf?v=1790867994"
SOURCE_HASH = "acc2dadf884b603f889445367671b6817eebb1f51a0101d7c014a946cd1a1b6b"
SECTIONS = {"BASE NFL": "Base", "BASE ROOKIE": "Base",
            "CHROME NFL BASE": "Chrome Base", "CHROME ROOKIE BASE": "Chrome Base",
            "PAPER PROSPECTS": "Paper Prospects", "CHROME PROSPECTS": "Chrome Prospects"}


def parse(text, checked_at):
    sections, current = {}, None
    for raw in text.replace("\f", "\n").splitlines():
        line = raw.strip()
        if not line or line.startswith(("Checklists provided", "product at the time")):
            continue
        if line in SECTIONS:
            if line in sections:
                raise ValueError("Repeated section: " + line)
            current = line
            sections[current] = []
        elif re.fullmatch(r"[A-Z][A-Z ]+", line):
            current = None
        elif current:
            match = re.fullmatch(r"([A-Z0-9-]+)\s+(.+?)\s{2,}(.+?)(?:\s{2,}(Rookie))?", line)
            if not match:
                raise ValueError("Unexpected row: " + line)
            sections[current].append(dict(number=match[1], player=match[2], team=match[3],
                                          rookie=bool(match[4]), imageURL=None))
    if set(sections) != set(SECTIONS) or any(len(rows) != (201 if "PROSPECTS" in heading else 100) for heading, rows in sections.items()):
        raise ValueError("Changed Bowman base sections/counts")
    collections, conflicts = [], []
    for subset, prefix in (("Base", ""), ("Chrome Base", "BCV-"),
                           ("Paper Prospects", "BPP-"), ("Chrome Prospects", "BCP-")):
        rows = [r for heading, values in sections.items() if SECTIONS[heading] == subset for r in values]
        counts = Counter(r["number"] for r in rows)
        duplicate = {number for number, count in counts.items() if count > 1}
        expected = {prefix + str(n) for n in range(1, 201)}
        if "Prospects" in subset:
            expected.add("BPP-ALT1" if subset == "Paper Prospects" else "ALT-1")
        if subset == "Base":
            if duplicate != {"68"} or expected - counts.keys() != {"66"}:
                raise ValueError("Paper numbering changed; review the new edition")
        elif duplicate or set(counts) != expected:
            raise ValueError("Invalid Bowman numbering")
        for row in rows:
            if row["number"] in duplicate:
                conflicts.append(dict(subset=subset, reason="duplicate_number", **row))
        rows = [r for r in rows if r["number"] not in duplicate]
        collections.append(dict(id="2026-topps-bowman-" + subset.lower().replace(" ", "-"),
            name="Bowman", year=2026, brand="Topps", subset=subset, parallel=None,
            expectedCount=len(expected), checklistComplete=len(rows) == len(expected),
            sourceURL=SOURCE, checkedAt=checked_at, cards=rows))
    return {"version": 1, "sourceEdition": "2026-bowman-football-base", "sourceURL": SOURCE,
            "sourceSHA256": SOURCE_HASH, "collections": collections, "conflicts": conflicts}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--checked-at", required=True)
    args = parser.parse_args()
    if hashlib.sha256(args.pdf.read_bytes()).hexdigest() != SOURCE_HASH:
        raise SystemExit("Unreviewed Bowman checklist edition")
    text = subprocess.check_output(["pdftotext", "-layout", str(args.pdf), "-"], text=True)
    payload = parse(text, args.checked_at)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"rows": sum(len(c["cards"]) for c in payload["collections"]),
                      "quarantinedRows": len(payload["conflicts"])}))
