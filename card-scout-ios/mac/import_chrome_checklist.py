"""Import the pinned official 2025 Chrome PDF's explicit unsigned checklist rows.

Run pdftotext -layout first. No multiplication of base rows into parallel families.
Autographs/relics require a separate adapter (multi-player and unnumbered rows).
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

SOURCE = "https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2025_Chrome_Football_Checklist_040826.pdf?v=1775678965"
SECTIONS = {
    "BASE CARDS": ("Base", None, 300),
    "ROOKIES": ("Base", None, 100),
    "BASE CARDS TEAM CAMO VARIATION": ("Base", "Team Camo Variation", 300),
    "ROOKIES TEAM CAMO VARIATION": ("Base", "Team Camo Variation", 96),
    "BASE CARDS LIGHTBOARD LOGO VARIATION": ("Base", "Lightboard Logo Variation", 400),
    "FUTURE STARS": ("Future Stars", None, 25),
    "1975 TOPPS": ("1975 Topps", None, 35),
    "POWER PLAYERS": ("Power Players", None, 40),
    "LEGENDS OF THE GRIDIRON": ("Legends of the Gridiron", None, 40),
    "FORTUNE 15": ("Fortune 15", None, 35),
    "ALL CHROME TEAM": ("All-Chrome Team", None, 25),
    "CHROME RADIATING ROOKIES": ("Radiating Rookies", None, 20),
    "URBAN LEGENDS": ("Urban Legends", None, 30),
    "HELIX": ("Helix", None, 30),
    "CHROME BASE ETCH VARIATION": ("Base", "Etch Variation", 50),
    "CHROME ROOKIES ETCH VARIATION": ("Base", "Etch Variation", 50),
    "BASE CARDS IMAGE VARIATION": ("Base", "Image Variation", 30),
    "ROOKIES IMAGE VARIATION": ("Base", "Image Variation", 20),
    "SHADOW ETCH": ("Shadow Etch", None, 30),
    "GAME GENIES": ("Game Genies", None, 25),
    "KAIJU": ("Kaiju", None, 10),
    "LETS GO": ("Let's Go", None, 5),
    "ULTRA VIOLET": ("Ultra Violet", None, 20),
    "LIGHTNING LEADERS": ("Lightning Leaders", None, 20),
    "FANATICAL": ("Fanatical", None, 30),
    "TECMO": ("Tecmo", None, 23),
}


def parse(text, checked_at):
    sections, current = {}, None
    for line in text.replace("\f", "\n").splitlines():
        line = line.strip()
        if line == "AUTOGRAPH": break
        if line in SECTIONS:
            if line in sections: raise ValueError("Repeated section: " + line)
            current = line; sections[current] = []
        elif line in ("BASE", "INSERT") or not line:
            continue
        elif current:
            match = re.fullmatch(r"([A-Z0-9-]+)\s+(.+?)\s{2,}(.+?)(?:\s{2,}(Rookie))?", line)
            if not match: raise ValueError("Unexpected checklist row: " + line)
            sections[current].append(dict(number=match[1], player=match[2], team=match[3],
                                          rookie=bool(match[4]), imageURL=None))
    if set(sections) != set(SECTIONS): raise ValueError("Missing checklist sections")
    collections = {}
    for heading, (subset, parallel, count) in SECTIONS.items():
        rows = sections[heading]
        if len(rows) != count: raise ValueError("Changed row count: " + heading)
        key = "2025-topps-topps-chrome-" + re.sub(r"[^a-z0-9]+", "-", subset.lower()).strip("-")
        if parallel: key += "-" + re.sub(r"[^a-z0-9]+", "-", parallel.lower()).strip("-")
        c = collections.setdefault(key, dict(id=key, name="Topps Chrome", year=2025, brand="Topps",
            subset=subset, parallel=parallel, expectedCount=0, checklistComplete=True,
            sourceURL=SOURCE, checkedAt=checked_at, cards=[]))
        c["cards"].extend(rows); c["expectedCount"] += count
    for c in collections.values():
        if len({r["number"] for r in c["cards"]}) != len(c["cards"]): raise ValueError("Duplicate card number")
    return list(collections.values())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pdf", type=Path); parser.add_argument("output", type=Path)
    parser.add_argument("--checked-at", required=True)
    args = parser.parse_args()
    text = subprocess.check_output(["pdftotext", "-layout", str(args.pdf), "-"], text=True)
    rows = parse(text, args.checked_at)
    payload = {"version": 1, "sourceURL": SOURCE, "sourceSHA256": hashlib.sha256(args.pdf.read_bytes()).hexdigest(),
               "collections": rows}
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"collections": len(rows), "rows": sum(len(c["cards"]) for c in rows),
                      "sourceSHA256": payload["sourceSHA256"]}))
