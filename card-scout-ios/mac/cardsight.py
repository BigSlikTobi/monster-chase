"""On-demand, bounded CardSight sale views. Never a permanent provider catalog.

Catalog pages and rejected sales are discarded after each page. Only up to 500
priced result cards / five evidence links each are cached for 24 hours. The
phone keeps these views in memory, separate from its owned-card library.
"""
from copy import deepcopy
from contextlib import contextmanager
import fcntl
import datetime as dt
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP
import hashlib
import http.client
import json
import os
from pathlib import Path
import re
import ssl
import statistics
import threading
import time
import unicodedata
from urllib.parse import urlencode, urlsplit

from cardsight_pilot import load_key

PRODUCTS = {
    "2025-panini-donruss-optic": ("570e5598-06b1-48cf-9053-30375096700e", "2025", "Donruss Optic"),
    "2026-topps-flagship-football": ("7d7b6650-5ea9-4340-b3e7-83a29ec52480", "2026", "Topps Flagship Football"),
}
CACHE_SECONDS = 24 * 60 * 60
MAX_RESULTS = 500
MAX_CALLS_PER_SCAN = 140
MONTHLY_CAP = 720  # User-selected stop below the free plan's 750 calls.
DAILY_CAP = MONTHLY_CAP  # The pilot's extra daily stop must not strand an otherwise free monthly budget.
MAX_CATALOG_CARDS = 5000


class MarketError(RuntimeError):
    """Only safe, user-visible messages may cross the HTTP boundary."""


def atomic(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temporary.chmod(0o600)
    temporary.replace(path)


def normal(value):
    text = unicodedata.normalize("NFKD", str(value)).encode("ascii", "ignore").decode().lower()
    return " ".join(re.findall(r"[a-z0-9]+", text))


def words(value):
    return set(normal(value).split())


def sale_url(value):
    if not isinstance(value, str): return None
    try:
        url = urlsplit(value)
        if url.scheme != "https" or url.username or url.password or url.port not in (None, 443): return None
        if url.hostname not in ("showme.cards", "www.ebay.com", "ebay.com"): return None
        if url.hostname == "showme.cards" and not re.fullmatch(r"/[A-Za-z0-9_-]{3,80}", url.path): return None
        if url.hostname != "showme.cards" and not re.search(r"/itm/(?:[^/]+/)?\d{9,15}/?$", url.path): return None
        return f"https://{url.hostname}{url.path}"
    except ValueError: return None


def image_url(value):
    if not isinstance(value, str): return None
    try:
        url = urlsplit(value)
        if url.scheme == "https" and url.hostname == "i.ebayimg.com" and not url.username and not url.password and url.port in (None, 443):
            return value
    except ValueError: pass
    return None


UNSAFE = re.compile(r"\b(psa|bgs|bvg|sgc|cgc|csg|graded|slab|gem mint|reprint|replica|custom|facsimile|digital|bunt|break|lot|bundle|choose|pick|read|damaged|damage|crease|creased|dent|dented|stain|stained|peeling|trimmed|altered|poor|oversized|jumbo|pack|box)\b|\b\d+\s*x\b|\b(?:insert|parallel|variant)\s*\?", re.I)
PARALLEL = re.compile(r"\b(gold|golden|silver|black|white|blue|red|purple|green|orange|pink|aqua|bronze|teal|yellow|copper|lime|violet|rainbow|holo|hollow|foil|refractor|scope|wave|velocity|pulsar|hyper|ice|shimmer|sparkle|pandora|mojo|disco|diamante|checker|checkerboard|tiger|zebra|camo|cracked|diecut|variation|variations|canvas|parallel|stars|laser|lazer|neon|premium|photon|emoji|electricity|fire)\b|\bdie cut\b", re.I)
SERIAL = re.compile(r"\d*\s*/\s*\d+|\b\d+\s+of\s+\d+\b|\bone of one\b|\bnumbered\b", re.I)
AUTO = re.compile(r"\b(auto|autograph|autographs|signature|signatures|signed|ink)\b")


def set_tokens(name):
    return words(name) - {"the", "card", "cards", "insert", "inserts"}


def matching_sale(card, record, all_set_names, today, parallel_names=(), lookback_days=90):
    """Fail closed on ambiguous identity, variant, grading, source or sale status.

    parallel_id:null is NOT proof of base: the provider misclassifies parallels.
    Initial release supports unnumbered standard versions of base/insert sets.
    No guessed parallel inheritance, autographs, shipping or condition grades.
    """
    if lookback_days not in (90, 365): return None
    title = record.get("title", "")
    if not isinstance(title, str) or not title or len(title) > 1000: return None
    if card.get("variationOf") or card.get("isParallelOnly") or not card.get("number"): return None
    if record.get("parallel_id") is not None or record.get("grade_id") is not None: return None
    if record.get("parallel_name") not in (None, "", "Base", "Base Set"): return None
    if record.get("source") != "ebay" or record.get("listing_type") != "auction": return None
    link = sale_url(record.get("url"))
    if not link or UNSAFE.search(title) or SERIAL.search(title): return None
    n = normal(title); tokens = words(title)
    year = str(card.get("releaseYear", ""))
    if year not in tokens: return None
    # Other modern release years mean an ambiguous multi-year listing.
    if set(re.findall(r"\b20[0-3]\d\b", title)) - {year} - words(card["setName"]): return None
    release = card.get("releaseName")
    if release == "Donruss Optic":
        if not {"donruss", "optic"} <= tokens: return None
    elif release == "Topps Flagship Football":
        if "topps" not in tokens: return None
        forbidden = {"bowman", "finest", "composite", "now", "chrome"} - words(card["setName"])
        if tokens & forbidden: return None
    elif release == "Topps Chrome":
        if not {"topps", "chrome"} <= tokens or tokens & {"sapphire", "bowman", "composite", "etch"}: return None
    elif release == "Bowman":
        # Observed 2026 paper/Chrome families. Identical BCV/BCP numbers also
        # exist in Sapphire, so a number alone is not enough.
        subset = card.get("setName")
        if year != "2026" or subset not in ("Base Set", "Chrome", "Prospects", "Chrome Prospects") or "bowman" not in tokens: return None
        if tokens & {"sapphire", "university", "u", "draft", "best", "sterling", "inception", "baseball"}: return None
        if subset == "Base Set":
            if not re.fullmatch(r"(?:[1-9]|[1-9]\d|1\d\d|200)", str(card["number"])) or "chrome" in tokens: return None
            if re.search(r"\b(?:BCV|BCP|BPP)[\s-]*\d", title, re.I): return None
        elif subset == "Chrome":
            if not re.fullmatch(r"BCV-(?:[1-9]|[1-9]\d|1\d\d|200)", str(card["number"])) or "chrome" not in tokens: return None
        else:
            prefix = "BCP" if subset == "Chrome Prospects" else "BPP"
            if not re.fullmatch(prefix + r"-[1-9]\d{0,2}", str(card["number"])): return None
            if ("chrome" in tokens) != (subset == "Chrome Prospects"): return None
    else: return None
    if re.search(r"\(\s*\d{2,}\s*\)|\b(?:cards|inserts|u get all|you get all|image variation|image variations)\b|\b\d+\s*(?:cards?|ct|count)\b", title, re.I): return None
    player = words(card["name"]) - {"jr", "sr", "ii", "iii", "iv"}
    if not player or not player <= tokens: return None
    number = str(card["number"]).strip()
    pattern = r"(?<![a-z0-9])" + r"[\s-]*".join(map(re.escape, normal(number).split())) + r"(?![a-z0-9])"
    if not re.search(pattern, title.lower()): return None
    subset = card["setName"]
    subset_words = set_tokens(subset)
    base = subset == "Base Set"
    # Bowman BPP/BCP prefixes independently establish the exact prospect family
    # after catalog resolution. Sellers often omit the word "Prospects".
    prospect_number = release == "Bowman" and subset in ("Prospects", "Chrome Prospects")
    if not base and not prospect_number and not subset_words <= tokens: return None
    # Downtown Duos/Legends must never become regular Downtown; likewise autos.
    for other in all_set_names:
        other_words = set_tokens(other)
        if other == "Base Set" or other == subset or not other_words: continue
        if other_words <= tokens and (base or not other_words <= subset_words): return None
    # Remove the actual subject and insert name so Matthew Golden / NFL Stars
    # do not trigger the color/parallel detector themselves.
    # 'Football' is also a Topps parallel name. Remove exactly ONE occurrence
    # of the full release title first, not every occurrence of the word.
    without_release = re.sub(r"\b" + re.escape(normal(release)) + r"\b", "", n, count=1)
    remaining = without_release.split()
    for word in [*player, *(subset_words if not base else ())]:
        if word in remaining: remaining.remove(word)
    remainder = " ".join(remaining)
    if PARALLEL.search(remainder): return None
    remaining_words = words(remainder)
    for parallel in parallel_names:
        variant_words = words(parallel) - {"prizm", "refractor", "parallel", "base", "set", "topps", "panini", "donruss", "optic", "chrome"}
        if variant_words and variant_words <= remaining_words: return None
    expected_auto = bool(AUTO.search(normal(subset))) or "AU" in card.get("attributes", [])
    if bool(AUTO.search(n)) != expected_auto: return None
    try:
        day = dt.datetime.fromisoformat(record["date"].replace("Z", "+00:00")).date()
        if not today - dt.timedelta(days=lookback_days) <= day <= today: return None
        if isinstance(record["price"], bool): return None
        price = Decimal(str(record["price"]))
        if not price.is_finite() or not 0 < price < 10_000_000: return None
        cents = int((price * 100).quantize(Decimal(1), rounding=ROUND_HALF_UP))
        if cents <= 0: return None
    except (KeyError, TypeError, ValueError, AttributeError, InvalidOperation): return None
    return {"priceCents": cents, "date": day.isoformat(), "url": link,
            "imageURL": image_url(record.get("image_url")),
            "fingerprint": (record["date"], normal(title), cents)}


def priced_card(product_id, card, result, all_set_names, today, parallel_names=()):
    if not result.get("success") or result.get("card_id") != card["id"]: return None, 0
    data = result.get("data") or {}
    query = data.get("query", {})
    if any(query.get(k, "missing") != v for k, v in {"parallel_id": None, "grade_id": None, "period": "90d", "listing_type": "auction"}.items()):
        return None, 0
    context = data.get("card", {})
    if context.get("card_id") != card["id"] or context.get("set", {}).get("set_id") != card["setId"]: return None, 0
    records = data.get("raw", {}).get("records", [])
    if not isinstance(records, list) or len(records) > 25: return None, 0
    accepted, urls, fingerprints = [], set(), set()
    for record in records:
        if not isinstance(record, dict): continue
        sale = matching_sale(card, record, all_set_names, today, parallel_names)
        if sale and sale["url"] not in urls and sale["fingerprint"] not in fingerprints:
            accepted.append(sale); urls.add(sale["url"]); fingerprints.add(sale["fingerprint"])
    rejected = len(records) - len(accepted)
    if not accepted: return None, rejected
    accepted.sort(key=lambda sale: sale["date"], reverse=True)
    prices = [sale["priceCents"] for sale in accepted]
    median = int(Decimal(str(statistics.median(prices))).quantize(Decimal(1), rounding=ROUND_HALF_UP))
    kind = "single_sale" if len(accepted) == 1 else "sold_median"
    entry = {"id": product_id + ":cardsight:" + card["id"], "rank": 1,
             "player": card["name"], "variant": card["setName"], "number": card["number"],
             "rarity": "Basis" if card["setName"] == "Base Set" else "Insert",
             "packLabel": "Standardversion · nicht nummeriert", "reason": "Raw · Verkäufe der letzten 90 Tage",
             "sourceURL": accepted[0]["url"], "imageURL": next((sale["imageURL"] for sale in accepted if sale["imageURL"]), None),
             "priceCents": median, "currency": "USD", "priceKind": kind,
             "priceSourceURL": accepted[0]["url"], "priceCheckedAt": today.isoformat(),
             "saleCount": len(accepted), "saleLowCents": min(prices), "saleHighCents": max(prices),
             "sales": [{k: sale[k] for k in ("priceCents", "date", "url")} for sale in accepted[:5]]}
    entry["imageKind"] = "scan" if entry["imageURL"] else "unavailable"
    return entry, rejected


class Client:
    """Fixed-host, no-redirect, no-retry client with durable conservative limits."""
    def __init__(self, root, transport=None):
        self.root = Path(root)
        self.ledger_path = self.root / "cardsight-usage.json"
        self.transport = transport
        self.last_call = 0
        self.lock = threading.Lock()

    def ledger(self):
        now = dt.datetime.now(dt.timezone.utc)
        data = json.loads(self.ledger_path.read_text()) if self.ledger_path.exists() else {}
        if data.get("month") != now.strftime("%Y-%m"): data = {"month": now.strftime("%Y-%m"), "calls": 0}
        if data.get("day") != now.date().isoformat(): data.update(day=now.date().isoformat(), daily=0)
        return data

    @contextmanager
    def budget_lock(self):
        # Shared across ranking/research clients and separate processes. Reserve
        # quota before transport; a crash still counts the uncertain request.
        with self.lock, (self.root / "cardsight-budget.lock").open("a") as handle:
            os.fchmod(handle.fileno(), 0o600)
            fcntl.flock(handle, fcntl.LOCK_EX)
            try: yield
            finally: fcntl.flock(handle, fcntl.LOCK_UN)

    def request(self, method, path, params=None, body=None):
        if (method, path) not in (("GET", "/v1/subscription/"), ("GET", "/v1/catalog/sets"), ("GET", "/v1/catalog/parallels"), ("GET", "/v1/catalog/cards"), ("POST", "/v1/pricing/"), ("GET", "/v1/pricing/search")):
            raise MarketError("CardSight-Anfrage nicht erlaubt.")
        if path == "/v1/pricing/search":
            if (not isinstance(params, dict) or set(params) != {"q", "period", "listing_type", "limit"}
                    or not isinstance(params.get("q"), str) or not 2 <= len(params["q"]) <= 300
                    or params.get("period") not in ("90d", "1y") or params.get("listing_type") != "auction" or params.get("limit") != 25):
                raise MarketError("Unsichere Verkaufssuche abgelehnt.")
        if method == "POST":
            if (not isinstance(body, dict) or not 1 <= len(body.get("card_ids", [])) <= 100
                    or "parallel_id" not in body or (body["parallel_id"] is not None and
                        (not isinstance(body["parallel_id"], str) or not re.fullmatch(r"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", body["parallel_id"])))
                    or body.get("period") not in ("90d", "1y")
                    or any(body.get(k, "missing") != v for k, v in {"grade_id": None, "listing_type": "auction", "limit": 25}.items())):
                raise MarketError("Unsichere Preisanfrage abgelehnt.")
        with self.budget_lock():
            ledger = self.ledger()
            if ledger.get("haltUntil", 0) > time.time(): raise MarketError("CardSight pausiert. Konto oder Gratis-Limit prüfen.")
            if ledger["calls"] >= MONTHLY_CAP or ledger.get("daily", 0) >= DAILY_CAP:
                raise MarketError("Gratis-Budget erreicht. Vorhandene Preise bleiben bis zum Ablauf verfügbar.")
            secret = load_key(self.root / "cardsight-api-key") if self.transport is None else "fixture"
            ledger["calls"] += 1; ledger["daily"] = ledger.get("daily", 0) + 1
            atomic(self.ledger_path, ledger)  # Count even failed/uncertain requests, before sending.
            if self.transport:
                status, data = self.transport(method, path, params, body)
            else:
                time.sleep(max(0, 1 - (time.monotonic() - self.last_call)))
                self.last_call = time.monotonic()
                connection = http.client.HTTPSConnection("api.cardsight.ai", timeout=25, context=ssl.create_default_context())
                payload = json.dumps(body).encode() if body is not None else None
                try:
                    connection.request(method, path + ("?" + urlencode(params) if params else ""), body=payload,
                                       headers={"X-API-Key": secret, "Accept": "application/json", "Content-Type": "application/json"})
                    response = connection.getresponse(); status = response.status
                    raw = response.read(16_000_001)
                    if len(raw) > 16_000_000: raise MarketError("CardSight-Antwort zu groß.")
                    data = json.loads(raw) if status == 200 else {}
                finally: connection.close()
            if status in (401, 402, 403, 429) or 300 <= status < 400:
                ledger["haltUntil"] = time.time() + CACHE_SECONDS
                atomic(self.ledger_path, ledger)
                raise MarketError("CardSight pausiert. Konto oder Gratis-Limit prüfen.")
            if status != 200: raise MarketError("CardSight gerade nicht erreichbar. Später erneut versuchen.")
            if path == "/v1/subscription/":
                # Subscription replies contain the full API key. Never return or log them.
                used = data.get("calls")
                if type(used) is not int or used < 0: raise MarketError("Gratis-Budget konnte nicht geprüft werden.")
                ledger["calls"] = max(ledger["calls"], used + 1)
                atomic(self.ledger_path, ledger)
                return {"calls": ledger["calls"]}
            return data


class Market:
    def __init__(self, root, client=None):
        self.root = Path(root)
        self.cache = self.root / "market-cache"; self.cache.mkdir(exist_ok=True); self.cache.chmod(0o700)
        self.client = client or Client(root)
        self.condition = threading.Condition()
        self.pending = []
        self.states = {}
        self.stop = threading.Event()
        self.worker = None
        self.purge()

    def cache_path(self, product):
        if product not in PRODUCTS: raise ValueError("Unsupported market product")
        return self.cache / (product + ".json")

    def purge(self):
        for product in PRODUCTS:
            path = self.cache_path(product)
            if not path.exists(): continue
            try:
                value = json.loads(path.read_text()) if path.stat().st_size < 4_000_000 else {}
                missing_key = self.client.transport is None and not (self.root / "cardsight-api-key").exists()
                if missing_key or not isinstance(value, dict) or value.get("version") != 1 or value.get("productID") != product or value.get("expiresAt", 0) <= time.time():
                    path.unlink(missing_ok=True)
            except (OSError, ValueError, TypeError): path.unlink(missing_ok=True)

    def status(self, product):
        with self.condition:
            self.purge()
            path = self.cache_path(product)
            cached = json.loads(path.read_text()) if path.exists() else None
            state = deepcopy(self.states.get(product, {}))
            if cached and not state: return cached
            result = cached or {"version": 1, "productID": product, "revision": "empty", "cards": [],
                                "checkedCards": 0, "totalCards": 0, "matchedCards": 0, "excludedSales": 0,
                                "expiresAt": 0, "checkedAt": "", "capped": False}
            result.update(state or {"status": "empty"})
            if not (self.root / "cardsight-api-key").exists() and self.client.transport is None:
                result.update(status="unavailable", message="CardSight ist nicht verbunden.", cards=[])
            return result

    def refresh(self, product):
        with self.condition:
            status = self.status(product)
            if status["status"] in ("ready", "refreshing", "unavailable"): return status
            self.states[product] = {"status": "refreshing", "message": "Verkäufe werden geprüft …"}
            self.pending.append(product)
            if self.worker is None:
                self.worker = threading.Thread(target=self.run, name="cardsight-market", daemon=True); self.worker.start()
            self.condition.notify()
            return self.status(product)

    def run(self):
        while not self.stop.is_set():
            with self.condition:
                if not self.pending:
                    self.condition.wait(timeout=60); self.purge(); continue
                product = self.pending.pop(0)
            try:
                snapshot = self.scan(product)
                with self.condition:
                    atomic(self.cache_path(product), snapshot)
                    self.states.pop(product, None)
            except Exception as error:
                message = str(error) if isinstance(error, MarketError) else "Marktpreise konnten nicht sicher geladen werden. Später erneut versuchen."
                with self.condition: self.states[product] = {"status": "error", "message": message}

    def scan(self, product):
        release, year, name = PRODUCTS[product]
        calls = 0
        def request(method, path, params=None, body=None):
            nonlocal calls
            if self.stop.is_set(): raise MarketError("Aktualisierung unterbrochen.")
            if calls >= MAX_CALLS_PER_SCAN: raise MarketError("Gratis-Budget für diese Aktualisierung erreicht.")
            calls += 1
            return self.client.request(method, path, params, body)
        request("GET", "/v1/subscription/")
        sets = request("GET", "/v1/catalog/sets", {"releaseId": release, "take": 100, "skip": 0})
        set_names = [item["name"] for item in sets.get("sets", [])]
        if not set_names or len(set_names) != sets.get("total_count"):
            raise MarketError("Set-Abdeckung konnte nicht sicher geprüft werden.")
        parallel_names, offset = set(), 0
        while True:
            parallels = request("GET", "/v1/catalog/parallels", {"releaseId": release, "take": 100, "skip": offset})
            page = parallels.get("parallels", [])
            total_parallels = parallels.get("total_count")
            if type(total_parallels) is not int or not 0 <= total_parallels <= 2000 or (not page and offset < total_parallels):
                raise MarketError("Parallel-Varianten konnten nicht geprüft werden.")
            parallel_names.update(item["name"] for item in page)
            offset += len(page)
            if offset >= total_parallels: break
        seen, kept, excluded, matched, skip, total = set(), [], 0, 0, 0, None
        today = dt.datetime.now(dt.timezone.utc).date()
        while total is None or skip < total:
            page = request("GET", "/v1/catalog/cards", {"releaseId": release, "take": 100, "skip": skip, "sort": "name", "order": "asc"})
            count = page.get("total_count")
            if type(count) is not int or not 0 < count <= MAX_CATALOG_CARDS or (total is not None and count != total):
                raise MarketError("Katalog hat sich geändert. Bitte später erneut laden.")
            total = count
            cards = page.get("cards", [])
            if not isinstance(cards, list) or not cards or len(cards) > 100:
                raise MarketError("Katalogseite ist unvollständig.")
            # The API does NOT have a stable tie-breaker for equal player names.
            # Never split a name group between offsets: discard the trailing
            # group and start the next request at that group's first offset.
            # This prevents both missed cards and duplicated prices.
            if skip + len(cards) < total:
                last_name = cards[-1]["name"].casefold()
                while cards and cards[-1]["name"].casefold() == last_name: cards.pop()
                if not cards: raise MarketError("Zu viele gleichnamige Einträge. Katalog konnte nicht vollständig geprüft werden.")
            for card in cards:
                if card["id"] in seen or card.get("releaseId") != release or str(card.get("releaseYear")) != year or card.get("releaseName") != name or card.get("setName") not in set_names:
                    raise MarketError("Widersprüchliche Kartenzuordnung. Preise wurden nicht übernommen.")
                seen.add(card["id"])
            results = request("POST", "/v1/pricing/", body={"card_ids": [card["id"] for card in cards], "parallel_id": None, "grade_id": None, "period": "90d", "listing_type": "auction", "limit": 25})
            items = results.get("results", [])
            by_id = {item["card_id"]: item for item in items}
            if len(by_id) != len(cards) or set(by_id) != {card["id"] for card in cards} or len(items) != len(cards) or any(not item.get("success") for item in items):
                raise MarketError("Preise nur teilweise geliefert. Bitte später erneut laden.")
            for card in cards:
                entry, rejected = priced_card(product, card, by_id[card["id"]], set_names, today, parallel_names)
                excluded += rejected
                if entry: kept.append(entry); matched += 1
            kept.sort(key=lambda entry: (-entry["priceCents"], entry["id"]))
            kept = kept[:MAX_RESULTS]
            skip += len(cards)
            with self.condition:
                self.states[product] = {"status": "refreshing", "checkedCards": skip, "totalCards": total,
                                        "message": f"{skip} / {total} Einträge geprüft"}
        if len(seen) != total: raise MarketError("Katalogabdeckung ist unvollständig.")
        for rank, entry in enumerate(kept, 1): entry["rank"] = rank
        stamp = time.time()
        return {"version": 1, "status": "ready", "productID": product, "revision": hashlib.sha256(json.dumps(kept, sort_keys=True).encode()).hexdigest()[:20],
                "checkedAt": today.isoformat(), "expiresAt": stamp + CACHE_SECONDS,
                "checkedCards": len(seen), "totalCards": total, "matchedCards": matched,
                "excludedSales": excluded, "capped": matched > MAX_RESULTS, "cards": kept}


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--refresh", choices=[*PRODUCTS, "all"], required=True)
    parser.add_argument("--force", action="store_true", help="Rebuild the selected temporary view, within the same free limits")
    args = parser.parse_args()
    market = Market(args.data)
    for product in PRODUCTS if args.refresh == "all" else [args.refresh]:
        current = market.status(product)
        if current["status"] == "ready" and not args.force:
            print(json.dumps({"product": product, "status": "cached", "cards": len(current["cards"])}), flush=True)
            continue
        print(json.dumps({"product": product, "status": "refreshing"}), flush=True)
        snapshot = market.scan(product)
        atomic(market.cache_path(product), snapshot)
        print(json.dumps({"product": product, "status": "ready", "checked": snapshot["checkedCards"],
                          "priced": snapshot["matchedCards"], "shown": len(snapshot["cards"]),
                          "excludedSales": snapshot["excludedSales"]}), flush=True)
