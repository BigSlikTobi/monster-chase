"""Validate versioned raw-price catalogs independently of the private card queue."""
import datetime as dt
import json
from urllib.parse import urlsplit


def https(value):
    if not isinstance(value, str): return False
    try:
        url = urlsplit(value)
        return url.scheme == "https" and bool(url.hostname) and not url.username and not url.password
    except ValueError: return False


def valid_date(value):
    try: return dt.date.fromisoformat(value).isoformat() == value
    except (TypeError, ValueError): return False


def validate_catalog(catalog):
    if not isinstance(catalog, dict) or type(catalog.get("version")) is not int or catalog.get("version") not in (1, 2) or not isinstance(catalog.get("revision"), str) or not catalog["revision"] or not valid_date(catalog.get("checkedAt")):
        raise ValueError("Invalid chase catalog metadata")
    products = catalog.get("products")
    if not isinstance(products, list) or not 1 <= len(products) <= 50: raise ValueError("Missing chase products")
    product_ids, card_ids = set(), set()
    for product in products:
        identity = product["id"]
        if identity in product_ids or not identity or not product["name"] or product["licenseScope"] != "nfl_and_nflpa": raise ValueError("Invalid chase product")
        product_ids.add(identity)
        if not 2020 <= product["year"] <= 2100 or not https(product["sourceURL"]) or not product["boxSummary"]: raise ValueError("Missing box evidence")
        cards = product["cards"]
        if not isinstance(cards, list) or not 1 <= len(cards) <= 200_000: raise ValueError("Invalid catalog size")
        if catalog["version"] == 1 and len(cards) != 10: raise ValueError("Legacy catalog requires ten cards")
        if any(type(c["rank"]) is not int for c in cards) or {c["rank"] for c in cards} != set(range(1, len(cards) + 1)): raise ValueError("Invalid catalog positions")
        coverage = product.get("coverage")
        if coverage is not None:
            if coverage.get("status") not in ("partial", "imported") or not coverage.get("sourceName") or coverage.get("cardCount") != len(cards) or not coverage.get("sourceURLs") or not all(https(url) for url in coverage["sourceURLs"]): raise ValueError("Invalid catalog coverage")
            if coverage.get("scope") not in (None, "price_guides", "official_chases"): raise ValueError("Invalid catalog scope")
        elif catalog["version"] == 2: raise ValueError("Catalog coverage must be declared")
        for card in cards:
            if card["id"] in card_ids or not card["id"].startswith(identity + ":"): raise ValueError("Duplicate or cross-product chase")
            card_ids.add(card["id"])
            if any(not card.get(key) for key in ("player", "variant", "number", "rarity", "packLabel", "reason")): raise ValueError("Incomplete card identity")
            if not https(card["sourceURL"]) or (card.get("imageURL") is not None and not https(card["imageURL"])): raise ValueError("Unsafe card link")
            if card["imageKind"] not in ("scan", "preview", "unavailable"): raise ValueError("Invalid image kind")
            amount = card.get("priceCents")
            if amount is not None and (type(amount) is not int or not 0 < amount < 1_000_000_000 or card.get("currency") != "USD" or card.get("priceKind") != "guide" or not https(card.get("priceSourceURL")) or not valid_date(card.get("priceCheckedAt"))):
                raise ValueError("Price requires dated raw-guide evidence")
            if card.get("odds") and not https(card.get("oddsSourceURL")): raise ValueError("Odds require a source")
    return catalog


def load_catalog(path):
    if not path.exists(): return None
    if path.stat().st_size > 64_000_000: raise ValueError("Chase catalog too large")
    return validate_catalog(json.loads(path.read_text(encoding="utf-8")))
