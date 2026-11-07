#!/usr/bin/env python3
"""Normalize the published Beckett XLSX into a full, attributed 300-card checklist."""
import argparse
import datetime
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

def read_base(path):
    ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as z:
        strings = ["".join(n.itertext()) for n in ET.fromstring(z.read("xl/sharedStrings.xml"))]
        rows = ET.fromstring(z.read("xl/worksheets/sheet1.xml")).findall("s:sheetData/s:row", ns)
    cards = []
    for row in rows:
        cells = {}
        for cell in row:
            value = cell.find("s:v", ns)
            if value is not None:
                col = "".join(c for c in cell.attrib["r"] if c.isalpha())
                cells[col] = strings[int(value.text)] if cell.attrib.get("t") == "s" else value.text
        if not str(cells.get("A", "")).isdigit(): continue
        number = int(cells["A"])
        cards.append({"number": str(number), "player": cells["B"].strip().rstrip(","), "team": cells["C"].strip(), "rookie": number >= 201, "imageURL": None})
    assert len(cards) == 300 and {c["number"] for c in cards} == {str(x) for x in range(1, 301)}, "Checklist incomplete"
    return {"id": "2025-panini-donruss-optic-base", "name": "Donruss Optic", "year": 2025, "brand": "Panini", "subset": "Base", "parallel": None, "expectedCount": 300, "checklistComplete": True, "sourceURL": "https://www.beckett.com/news/2025-donruss-optic-football-cards/", "checkedAt": datetime.date.today().isoformat(), "cards": cards}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(); parser.add_argument("xlsx", type=Path); parser.add_argument("output", type=Path); args = parser.parse_args()
    result = read_base(args.xlsx); args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps([result], ensure_ascii=False, indent=2) + "\n")
    print(f"Verified {len(result['cards'])} entries; saved {args.output}")
