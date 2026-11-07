#!/usr/bin/env python3
"""QA only: download cited public scans and produce a labelled contact sheet. No catalog edits."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from pathlib import Path
import urllib.request
from PIL import Image, ImageDraw, ImageFont, ImageOps
from chases import load_catalog


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    catalog = load_catalog(Path(__file__).parent / "data/chases.json")
    entries = [(product, card) for product in catalog["products"] for card in sorted(product["cards"], key=lambda c: c["rank"])]
    def fetch(entry):
        product, card = entry
        request = urllib.request.Request(card["imageURL"])
        with urllib.request.urlopen(request, timeout=20) as response: data = response.read(15_000_001)
        if len(data) > 15_000_000: raise ValueError("Image too large")
        original = Image.open(BytesIO(data)); original.load()
        if min(original.size) < 100: raise ValueError("Thumbnail only: " + card["id"])
        image = ImageOps.contain(original.convert("RGB"), (200, 270))
        original.save(args.output / (product["id"] + "-" + str(card["rank"]) + ".png"))
        return product, card, image
    with ThreadPoolExecutor(max_workers=3) as pool: fetched = list(pool.map(fetch, entries))
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 13)
    for start in range(0, len(fetched), 10):
        canvas = Image.new("RGB", (1100, 680), "#10131a"); draw = ImageDraw.Draw(canvas)
        for i, (product, card, image) in enumerate(fetched[start:start + 10]):
            x, y = (i % 5) * 220, (i // 5) * 340
            canvas.paste(image, (x + (220 - image.width) // 2, y + 4))
            draw.text((x + 8, y + 279), f"{card['rank']}. {card['player']}", font=font, fill="white")
            draw.text((x + 8, y + 297), card['variant'][:31], font=font, fill="#ef9696")
            draw.text((x + 8, y + 315), "#" + card['number'] + " | " + card['rarity'], font=font, fill="white")
        canvas.save(args.output / (fetched[start][0]["id"] + "-sheet.jpg"))
    print(f"Verified {len(fetched)} source images; contact sheets in {args.output}")


if __name__ == "__main__": main()
