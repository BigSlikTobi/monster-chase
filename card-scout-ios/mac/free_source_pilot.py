"""Read-only free-source pilot. Never changes analysis routing or owned cards.

Uses the existing CardSight client/key and its durable free-budget guard.
Only short summaries reach stdout; catalog pages and raw responses stay in RAM.
"""
import argparse
from collections import Counter
import datetime as dt
from decimal import Decimal, ROUND_HALF_UP
import json
from pathlib import Path
import re
import statistics
import time

from cardsight import Client, words, sale_url, UNSAFE, PARALLEL, SERIAL

SAMPLE = (("Terrance Ferguson", "335"), ("Kamren Kinchens", "174"), ("Jaxson Dart", "306"))
MULTI = re.compile(r"\(\s*\d{2,}\s*\)|\b(?:cards|inserts|sapphire|etch|image variation|image variations|u get all|you get all)\b|\b\d+\s*(?:card|cards|count|ct)\b", re.I)


def reject_reason(card, record, today, set_names=()):
    title = record.get("title")
    if not isinstance(title, str) or not title: return "missing_title"
    if record.get("listing_type") != "auction" or record.get("source") != "ebay": return "not_auction"
    if record.get("parallel_id") is not None or record.get("grade_id") is not None: return "variant_or_grade"
    if record.get("parallel_name") not in (None, "", "Base", "Base Set"): return "variant_or_grade"
    if MULTI.search(title) or UNSAFE.search(title) or SERIAL.search(title): return "lot_grade_or_unsafe"
    tokens = words(title)
    if not words(card["name"]) <= tokens or not {"2025", "topps", "chrome"} <= tokens: return "wrong_identity"
    if set(re.findall(r"\b20\d\d\b", title)) != {"2025"}: return "wrong_year"
    if not re.search(r"(?<![A-Za-z0-9])" + re.escape(card["number"]) + r"(?![A-Za-z0-9])", title): return "wrong_number"
    remainder = tokens - words(card["name"])
    if PARALLEL.search(" ".join(remainder)): return "parallel"
    for subset in set_names:
        if subset != "Base Set" and words(subset) and words(subset) <= tokens: return "insert"
    if not sale_url(record.get("url")): return "missing_sale_link"
    try:
        day = dt.datetime.fromisoformat(record["date"].replace("Z", "+00:00")).date()
        if not today - dt.timedelta(days=90) <= day <= today: return "outside_window"
        price = Decimal(str(record["price"]))
        if isinstance(record["price"], bool) or not price.is_finite() or not 0 < price < 1000000: return "invalid_price"
    except (KeyError, TypeError, ValueError, AttributeError, ArithmeticError): return "missing_date_or_price"
    return None


def summarize(card, result, today, set_names=()):
    if not result.get("success") or result.get("card_id") != card["id"]: raise ValueError("Wrong pricing response")
    data = result["data"]
    query = data["query"]
    if any(query.get(k, "missing") != v for k, v in {"parallel_id": None, "grade_id": None, "period": "90d", "listing_type": "auction"}.items()):
        raise ValueError("Wrong pricing filters")
    context = data["card"]
    if context.get("card_id") != card["id"] or context.get("name") != card["name"] or str(context.get("number")) != card["number"]:
        raise ValueError("Wrong card identity")
    if context.get("set", {}).get("name") != "Base Set" or context["set"].get("release") != "Topps Chrome" or str(context["set"].get("year")) != "2025":
        raise ValueError("Wrong release/variant")
    records = data["raw"]["records"]
    if not isinstance(records, list) or len(records) > 25: raise ValueError("Unexpected price sample")
    accepted, seen, reasons = [], set(), Counter()
    for record in records:
        reason = reject_reason(card, record, today, set_names)
        link = sale_url(record.get("url"))
        if not reason and link in seen: reason = "duplicate"
        if reason: reasons[reason] += 1
        else:
            seen.add(link)
            accepted.append(record)
    prices = [int((Decimal(str(r["price"])) * 100).quantize(Decimal(1), rounding=ROUND_HALF_UP)) for r in accepted]
    median = int(Decimal(str(statistics.median(prices))).quantize(Decimal(1), rounding=ROUND_HALF_UP)) if prices else None
    return {"player": card["name"], "year": 2025, "product": "Topps Chrome", "number": card["number"], "parallel": "Base",
            "records": len(records), "accepted": len(accepted), "rejected": dict(reasons), "currency": "USD", "shipping": "unknown",
            "medianCents": median, "lowCents": min(prices) if prices else None, "highCents": max(prices) if prices else None,
            "newestSale": max((r["date"][:10] for r in accepted), default=None),
            "sampleLimited": bool(data.get("messages")) or len(records) == 25,
            "evidence": "provider-reported completed auctions; titles checked, photos/payment not independently verified"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, required=True)
    args = parser.parse_args()
    client = Client(args.data)
    calls = 0
    def request(method, path, params=None, body=None):
        nonlocal calls
        calls += 1
        if calls > 7: raise RuntimeError("Seven-request pilot cap reached")
        return client.request(method, path, params, body)
    started = time.monotonic()
    usage = request("GET", "/v1/subscription/")
    cards = []
    for name, number in SAMPLE:
        data = request("GET", "/v1/catalog/cards", {"name": name, "number": number, "releaseName": "Topps Chrome", "year": "2025", "take": 10})
        exact = [c for c in data.get("cards", []) if c.get("name") == name and c.get("number") == number and c.get("releaseName") == "Topps Chrome"
                 and c.get("releaseYear") == "2025" and c.get("setName") == "Base Set" and not c.get("variationOf") and not c.get("description")]
        if len(exact) != 1: raise ValueError("Exact base-card match missing or ambiguous")
        cards.append(exact[0])
    release = cards[0]["releaseId"]
    if any(c["releaseId"] != release for c in cards): raise ValueError("Mixed releases")
    sets = request("GET", "/v1/catalog/sets", {"releaseId": release, "take": 100})
    if len(sets.get("sets", [])) != sets.get("total_count"): raise ValueError("Incomplete insert-name coverage")
    set_names = [s["name"] for s in sets["sets"]]
    data = request("POST", "/v1/pricing/", body={"card_ids": [c["id"] for c in cards], "parallel_id": None, "grade_id": None,
                                                           "period": "90d", "listing_type": "auction", "limit": 25})
    results = {r["card_id"]: r for r in data["results"]}
    if len(data["results"]) != len(cards) or set(results) != {c["id"] for c in cards}: raise ValueError("Incomplete price response")
    report = {"checkedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "source": "CardSight", "calls": calls,
              "providerCallsAtStart": usage["calls"], "localCallsAtEnd": client.ledger()["calls"], "seconds": round(time.monotonic() - started, 2),
              "cards": [summarize(c, results[c["id"]], dt.datetime.now(dt.timezone.utc).date(), set_names) for c in cards],
              "openAISearchCalls": 0, "openAIModelCalls": 0, "collectionWrites": 0}
    print(json.dumps(report, indent=2))


if __name__ == "__main__": main()
