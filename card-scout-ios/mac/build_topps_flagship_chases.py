#!/usr/bin/env python3
"""Build the official 2026 Topps Flagship chase snapshot from Topps' PDF."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unicodedata
import urllib.request


PRODUCT_ID = "2026-topps-flagship-football"
PRODUCT_PAGE = "https://www.topps.com/pages/topps-flagship-football"
CHECKLIST_URL = "https://cdn.shopify.com/s/files/1/0662/9749/5709/files/CheckList_26TFOB_VERSION5_1.pdf?v=1786730315"
CHECKLIST_SHA256 = "ab25d4ceb1d5693dd0e74f82c9a5d716b0d6929f2c2f009ffdc09d223c30b035"
CHECKED_AT = "2026-09-12"


SECTIONS = [
    {
        "heading": "LEAGUE LEADERS GOLDEN MIRROR IMAGE VARIATIONS",
        "variant": "League Leaders Golden Mirror Image Variations",
        "count": 30,
        "rarity": "SSP Image Variation",
        "reason": "Offizielle Golden-Mirror-Chase-Variation von Topps.",
    },
    {
        "heading": "FUTURE STARS GOLDEN MIRROR IMAGE VARIATIONS",
        "variant": "Future Stars Golden Mirror Image Variations",
        "count": 10,
        "rarity": "SSP Image Variation",
        "reason": "Offizielle Golden-Mirror-Chase-Variation von Topps.",
    },
    {
        "heading": "TEAM CARDS GOLDEN MIRROR IMAGE VARIATIONS",
        "variant": "Team Cards Golden Mirror Image Variations",
        "count": 10,
        "rarity": "SSP Image Variation",
        "reason": "Offizielle Golden-Mirror-Chase-Variation von Topps.",
    },
    {
        "heading": "COMBO CARDS GOLDEN MIRROR IMAGE VARIATIONS",
        "variant": "Combo Cards Golden Mirror Image Variations",
        "count": 10,
        "rarity": "SSP Image Variation",
        "reason": "Offizielle Golden-Mirror-Chase-Variation von Topps.",
    },
    {
        "heading": "GOLDEN MIRROR IMAGE VARIATIONS",
        "variant": "Golden Mirror Image Variations",
        "count": 260,
        "rarity": "SSP Image Variation",
        "reason": "Offizielle Golden-Mirror-Chase-Variation von Topps.",
    },
    {
        "heading": "GOLDEN MIRROR ROOKIE IMAGE VARIATIONS",
        "variant": "Golden Mirror Rookie Image Variations",
        "count": 100,
        "rarity": "SSP Rookie Image Variation",
        "reason": "Offizielle Golden-Mirror-Rookie-Chase von Topps.",
    },
    {
        "heading": "ALL KINGS",
        "variant": "All Kings",
        "count": 30,
        "rarity": "Chase Insert",
        "reason": "Von Topps als Chase-Set hervorgehoben.",
    },
    {
        "heading": "1957 ROOKIE VARIATION",
        "variant": "1957 Rookie Variation",
        "count": 50,
        "rarity": "Rookie Variation",
        "reason": "Offizielle 1957-Rookie-Variation von Topps.",
    },
    {
        "heading": "FLAGSHIP FIRST SIGNATURES",
        "variant": "Flagship First Signatures",
        "count": 38,
        "rarity": "Rookie Autograph",
        "reason": "Offizielle Flagship-First-Autograph-Checkliste.",
    },
    {
        "heading": "FLAGSHIP FIRST DUAL SIGNATURES",
        "variant": "Flagship First Dual Signatures",
        "count": 10,
        "rarity": "Dual Rookie Autograph",
        "reason": "Offizielle Flagship-First-Dual-Autograph-Checkliste.",
        "dual": True,
    },
    {
        "heading": "ISLAND INK",
        "variant": "Island Ink",
        "count": 19,
        "rarity": "Autograph",
        "reason": "Von Topps als Autograph-Chase hervorgehoben.",
    },
    {
        "heading": "SUPER BOWL CHAMPION SIGNATURES",
        "variant": "Super Bowl Champion Signatures",
        "count": 48,
        "rarity": "Autograph",
        "reason": "Offizielle Super-Bowl-Champion-Signature-Checkliste.",
    },
    {
        "heading": "RING OF HONOR SIGNATURES",
        "variant": "Ring of Honor Signatures",
        "count": 4,
        "rarity": "Autograph",
        "reason": "Offizielle Ring-of-Honor-Signature-Checkliste.",
    },
    {
        "heading": "REAL ONE RELICS",
        "variant": "Real One Relics",
        "count": 32,
        "rarity": "Relic",
        "reason": "Von Topps als Relic-Chase hervorgehoben.",
    },
    {
        "heading": "ROOKIE REAL ONE RELICS",
        "variant": "Rookie Real One Relics",
        "count": 42,
        "rarity": "Rookie Relic",
        "reason": "Offizielle Rookie-Real-One-Relic-Checkliste.",
    },
]


def slug(value):
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", ascii_value.lower()).strip("-")


def heading_ranges(lines):
    found = []
    for index, line in enumerate(lines):
        text = line.strip().lstrip("\f").strip()
        if re.fullmatch(r"[A-Z0-9][A-Z0-9 &-]+", text):
            found.append((index, text))
    result = {}
    for position, (start, heading) in enumerate(found):
        end = found[position + 1][0] if position + 1 < len(found) else len(lines)
        result[heading] = (start + 1, end)
    return result


def ordinary_rows(lines):
    rows = []
    for raw in lines:
        value = raw.strip().lstrip("\f").strip()
        if not value:
            continue
        value = re.sub(r"\s{2,}Rookie\s*$", "", value)
        match = re.fullmatch(r"(\S+)\s+(.+?)\s{2,}(.+)", value)
        if not match:
            raise ValueError(f"Could not parse checklist row: {raw!r}")
        number, player, team = (part.strip() for part in match.groups())
        rows.append({"number": number, "player": player, "team": team})
    return rows


def dual_rows(lines):
    rows = []
    current = None
    for raw in lines:
        if not raw.strip():
            continue
        value = re.sub(r"\s{2,}Rookie\s*$", "", raw.strip().lstrip("\f").strip())
        parts = re.split(r"\s{2,}", value)
        if len(raw) - len(raw.lstrip()) < 20:
            if len(parts) != 3:
                raise ValueError(f"Could not parse first dual row: {raw!r}")
            current = {"number": parts[0], "players": [parts[1]], "teams": [parts[2]]}
            rows.append(current)
        else:
            if current is None or len(parts) != 2:
                raise ValueError(f"Could not parse second dual row: {raw!r}")
            current["players"].append(parts[0])
            current["teams"].append(parts[1])
            current = None
    if current is not None:
        raise ValueError("Dual-signature checklist ended after only one player")
    return [
        {"number": row["number"], "player": " / ".join(row["players"]), "team": " / ".join(row["teams"])}
        for row in rows
    ]


def cards_from_text(text):
    lines = text.split("\n")
    ranges = heading_ranges(lines)
    cards = []
    for section in SECTIONS:
        if section["heading"] not in ranges:
            raise ValueError(f"Missing section: {section['heading']}")
        start, end = ranges[section["heading"]]
        rows = dual_rows(lines[start:end]) if section.get("dual") else ordinary_rows(lines[start:end])
        if len(rows) != section["count"]:
            raise ValueError(f"{section['heading']}: expected {section['count']} rows, found {len(rows)}")
        for row in rows:
            identifier = ":".join(
                [PRODUCT_ID, "topps", slug(section["variant"]), slug(row["number"]), slug(row["player"])]
            )
            cards.append(
                {
                    "id": identifier,
                    "rank": len(cards) + 1,
                    "player": row["player"],
                    "number": row["number"],
                    "variant": section["variant"],
                    "rarity": section["rarity"],
                    "packLabel": "Topps Flagship Football",
                    "reason": section["reason"],
                    "imageURL": None,
                    "imageKind": "unavailable",
                    "sourceURL": CHECKLIST_URL,
                }
            )
    identifiers = [card["id"] for card in cards]
    if len(cards) != 693 or len(set(identifiers)) != len(identifiers):
        raise ValueError("Official chase snapshot is incomplete or contains duplicate identities")
    return cards


def extract_text(pdf_path):
    digest = hashlib.sha256(pdf_path.read_bytes()).hexdigest()
    if digest != CHECKLIST_SHA256:
        raise ValueError(f"Unexpected Topps checklist digest: {digest}")
    with tempfile.NamedTemporaryFile(suffix=".txt") as output:
        subprocess.run(["pdftotext", "-layout", str(pdf_path), output.name], check=True)
        return Path(output.name).read_text(encoding="utf-8")


def update_catalog(catalog_path, cards):
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    catalog["version"] = 2
    catalog["revision"] = "2026-09-12.1"
    catalog["checkedAt"] = CHECKED_AT
    catalog["managedBy"] = "cardscout-bundled"
    for product in catalog["products"]:
        if product["id"] == PRODUCT_ID:
            product["cards"] = cards
            product["rankingLabel"] = "Verkäufe + offizielle Chase-Liste"
            product["coverage"] = {
                "status": "imported",
                "scope": "official_chases",
                "sourceName": "Topps official checklist",
                "sourceURLs": [PRODUCT_PAGE, CHECKLIST_URL],
                "cardCount": len(cards),
            }
        else:
            product["coverage"] = {
                "status": "partial",
                "scope": "price_guides",
                "sourceName": "SportsCardsPro",
                "sourceURLs": [product["sourceURL"]],
                "cardCount": len(product["cards"]),
            }
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", type=Path)
    parser.add_argument("--catalog", type=Path, default=Path(__file__).parent / "data/chases.json")
    parser.add_argument("--snapshot", type=Path, default=Path(__file__).parent / "data/topps_flagship_chases.json")
    args = parser.parse_args()
    if args.pdf:
        pdf_path = args.pdf
        text = extract_text(pdf_path)
    else:
        with tempfile.TemporaryDirectory() as directory:
            pdf_path = Path(directory) / "topps-checklist.pdf"
            urllib.request.urlretrieve(CHECKLIST_URL, pdf_path)
            text = extract_text(pdf_path)
    cards = cards_from_text(text)
    snapshot = {
        "version": 1,
        "productID": PRODUCT_ID,
        "checkedAt": CHECKED_AT,
        "sourcePageURL": PRODUCT_PAGE,
        "sourceURL": CHECKLIST_URL,
        "sourceSHA256": CHECKLIST_SHA256,
        "highlightedFamilies": [section["heading"] for section in SECTIONS],
        "cards": cards,
    }
    args.snapshot.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    update_catalog(args.catalog, cards)
    print(f"Verified and saved {len(cards)} official Topps chase cards")


if __name__ == "__main__":
    main()
