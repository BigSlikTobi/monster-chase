"""Short-lived per-card CardSight evidence, kept out of owned-card storage."""
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
import datetime as dt
import hashlib
import json
import re
from pathlib import Path
import threading
import time

from cardsight import Client, MarketError, atomic, matching_sale, normal, sale_url
import raw_guides

FIELDS = ("player", "year", "brand", "setName", "subset", "cardNumber", "parallel", "serialNumber")
TTL = 86400
MATCHER_VERSION = 4
MAX_VARIANT_ROWS = 1000


class NoExactMatch(ValueError): pass


def variant_name(value, rated_rookie=False):
    # Spelling/descriptor normalization only. Never equate colors or finishes.
    name = re.sub(r"\s+variations?$", "", normal(value or ""))
    # Observed 2025 Optic catalog label. The caller must independently prove
    # both owned and catalog rookie status; this is not a general prefix alias.
    if rated_rookie and name in ("rated rookie blue hyper", "rated rookie purple shock"):
        return name.removeprefix("rated rookie ")
    return name


def serial_tier(value):
    match = re.fullmatch(r"\s*(\d{1,6})\s*/\s*(\d{1,6})\s*", value or "")
    return int(match[2]) if match and 1 <= int(match[1]) <= int(match[2]) else None


def matching_variant_sale(card, record, variant, tier, names, today, variants, lookback_days=90, rated_rookie=False):
    title = record.get("title", "")
    if not isinstance(title, str): return None
    if record.get("parallel_id") not in (None, variant["id"]): return None
    if record.get("parallel_name") is not None and variant_name(record["parallel_name"], rated_rookie) != variant_name(variant["name"], rated_rookie): return None
    # The title must independently state the full resolved finish. A provider
    # parallel UUID alone is not evidence of an exact sale.
    phrase = variant_name(variant["name"], rated_rookie)
    normalized = normal(title)
    pattern = r"\b" + re.escape(phrase) + r"(?: variations?)?\b"
    if not re.search(pattern, normalized): return None
    for other in variants:
        label = variant_name(other, rated_rookie)
        if label and not set(label.split()) <= set(phrase.split()) and re.search(r"\b" + re.escape(label) + r"\b", normalized): return None
    # Match serial print tier, not the individual copy numerator. No conversion
    # from /99 to /50, nor a serial-only guess of the finish.
    serials = list(re.finditer(r"(?<!\d)(?:(\d{1,6})\s*)?/\s*(\d{1,6})(?!\d)", title))
    if tier is not None:
        if not serials or any(int(m[2]) != tier or (m[1] and not 1 <= int(m[1]) <= tier) for m in serials): return None
    elif serials: return None
    stripped = re.sub(r"(?<!\d)(?:(\d{1,6})\s*)?/\s*(\d{1,6})(?!\d)", " ", title)
    stripped = re.sub(pattern, " ", normal(stripped), count=1)
    probe = dict(record, title=stripped, parallel_id=None, parallel_name=None)
    sale = matching_sale(card, probe, names, today, variants, lookback_days)
    if sale: sale["fingerprint"] = (record["date"], normal(title), sale["priceCents"])
    return sale


def identity_key(a):
    return hashlib.sha256(json.dumps({k: a.get(k) for k in FIELDS}, sort_keys=True).encode()).hexdigest()


def eligible(a):
    bowman = (a.get("setName") == "Bowman" and a.get("brand") == "Topps" and a.get("year") == 2026
              and a.get("subset") in ("Base", "Chrome Base", "Chrome Prospects", "Paper Prospects"))
    if (a.get("year"), a.get("brand"), a.get("setName"), a.get("subset")) == (2025, "Panini", "Donruss Optic", "Base"):
        if str(a.get("cardNumber", "")).isdigit() and 1 <= int(a["cardNumber"]) <= 200 and a.get("parallel") in ("Blue Hyper", "Purple Shock"):
            return False
        expected = {"Orange": 299, "Orange Scope": 79}.get(a.get("parallel"))
        if expected and serial_tier(a.get("serialNumber")) != expected:
            return False
    return (a.get("identityConfirmed") is True and a.get("confidence") == "high"
            and all(a.get(k) for k in ("player", "year", "setName", "subset", "cardNumber"))
            and (not a.get("serialNumber") or (a.get("parallel") and serial_tier(a["serialNumber"]) is not None))
            and variant_name(a.get("parallel")) not in ("unknown", "unbekannt", "unklar", "nicht bestimmbar", "nicht sicher bestimmbar")
            and (bowman or a.get("setName") in ("Topps Chrome", "Donruss Optic", "Topps Flagship Football", "Select", "Prizm")))


def catalog_subset(a):
    # Verified 2026 Bowman NFL checklist family -> observed CardSight spelling.
    if a.get("setName") == "Bowman" and a.get("year") == 2026:
        return {"Chrome Base": "Chrome", "Paper Prospects": "Prospects"}.get(a["subset"], "Base Set" if a["subset"] == "Base" else a["subset"])
    return "Base Set" if a["subset"] == "Base" else a["subset"]


class PriceResearch:
    def __init__(self, root, client=None):
        self.root = Path(root)
        self.cache = self.root / "card-price-cache"
        self.cache.mkdir(mode=0o700, exist_ok=True)
        self.client = client or Client(root)
        self.lock = threading.RLock()
        self.pending_lock = threading.Lock()
        self.pending = set()
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="card-price")
        self.purge()

    def purge(self):
        for path in self.cache.glob("*.json"):
            try:
                value = json.loads(path.read_text()) if path.stat().st_size < 100000 else {}
                if value.get("expiresAt", 0) <= time.time() or (self.client.transport is None and not (self.root / "cardsight-api-key").exists()):
                    path.unlink(missing_ok=True)
            except (OSError, ValueError, TypeError): path.unlink(missing_ok=True)

    def cached(self, a):
        if not eligible(a): return None
        path = self.cache / (identity_key(a) + ".json")
        try:
            if self.client.transport is None and not (self.root / "cardsight-api-key").exists():
                path.unlink(missing_ok=True); return None
            value = json.loads(path.read_text()) if path.stat().st_size < 100000 else {}
            compatible = value.get("matcherVersion") == MATCHER_VERSION
            if value.get("reason") == "catalog_not_exact" and value.get("catalogMatchVersion") != 2: compatible = False
            if value.get("reason") == "variant_not_exact" and value.get("variantMatchVersion") != 4: compatible = False
            if (compatible and value.get("key") == identity_key(a)
                    and time.time() < value.get("expiresAt", 0) <= time.time() + TTL + 60): return value
            path.unlink(missing_ok=True)
        except (OSError, ValueError, TypeError): pass
        return None

    def status(self, a):
        if not eligible(a): return "unsupported"
        with self.pending_lock:
            if identity_key(a) in self.pending: return "refreshing"
        value = self.cached(a)
        if value: return value["status"]
        with self.pending_lock: return "refreshing" if identity_key(a) in self.pending else "empty"

    def start(self, a):
        if not eligible(a): return
        existing = self.cached(a)
        if existing and not self.needs_guide(a, existing): return
        key = identity_key(a)
        with self.pending_lock:
            if key in self.pending or len(self.pending) >= 32: return
            self.pending.add(key)
        def work():
            try: self.lookup(a)
            finally:
                with self.pending_lock: self.pending.discard(key)
        self.executor.submit(work)

    def lookup(self, a):
        if not eligible(a): return None
        with self.lock:
            existing = self.cached(a)
            if existing: return self.with_guide(a, existing) if self.needs_guide(a, existing) else existing
            now = time.time()
            value = {"key": identity_key(a), "matcherVersion": MATCHER_VERSION, "checkedAt": dt.datetime.now(dt.timezone.utc).date().isoformat(),
                     "expiresAt": now + TTL, "status": "no_match", "references": [], "sampleLimited": False,
                     "periodDays": 90, "reason": None, "stages": [], "candidateCount": 0, "catalogMatchVersion": 2, "variantMatchVersion": 4}
            # A sourced estimate is sufficient. Try it before spending auction quota.
            value["status"] = "not_checked"
            self.with_guide(a, value, save=False)
            if value["references"]:
                atomic(self.cache / (identity_key(a) + ".json"), value)
                return value
            value["status"] = "no_match"
            try:
                # The usage check is counted and shared with product rankings.
                self.client.request("GET", "/v1/subscription/")
                cards = self.client.request("GET", "/v1/catalog/cards", {"name": a["player"], "number": a["cardNumber"],
                    "releaseName": a["setName"], "year": str(a["year"]), "take": 100})
                candidates = [c for c in cards.get("cards", []) if normal(c.get("name")) == normal(a["player"])
                    and str(c.get("number")) == a["cardNumber"] and c.get("releaseName") == a["setName"]
                    and str(c.get("releaseYear")) == str(a["year"]) and normal(c.get("setName")) == normal(catalog_subset(a))
                    and not c.get("variationOf") and not c.get("isParallelOnly") and not c.get("description")]
                if cards.get("total_count", 0) > 100 or len(candidates) != 1: raise NoExactMatch("catalog_not_exact")
                card = candidates[0]
                rated_rookie = (a.get("rookie") is True and "RC" in card.get("attributes", [])
                                and a["setName"] == "Donruss Optic" and str(a["year"]) == "2025"
                                and a["subset"] == "Base" and card.get("setName") == "Base Set")
                names, variants = self.metadata(card["releaseId"])
                variant = None
                tier = serial_tier(a.get("serialNumber"))
                if a.get("parallel"):
                    labels = [name for name in variants if variant_name(name, rated_rookie) == variant_name(a["parallel"], rated_rookie)]
                    if not labels or len(labels) > (2 if rated_rookie else 1): raise NoExactMatch("variant_not_exact")
                    # Native searches use literal substrings. Reuse the actual
                    # catalog spelling (e.g. Red/White/Blue), not a guessed slug.
                    rows, total = [], None
                    for skip in range(0, 400, 100):
                        matches = self.client.request("GET", "/v1/catalog/parallels", {"releaseId": card["releaseId"], "name": min(labels, key=len), "take": 100,
                            "skip": skip, "sort": "name", "order": "asc"})
                        count, page = matches.get("total_count"), matches.get("parallels", [])
                        if type(count) is not int or count > 400 or count < 0: raise NoExactMatch("variant_not_exact")
                        if total is not None and total != count: raise ValueError("Changing parallel coverage")
                        total = count
                        if not isinstance(page, list) or len(page) != min(100, max(0, count - skip)): raise ValueError("Incomplete parallel coverage")
                        rows += page
                        if len(rows) >= count: break
                    if len({p["id"] for p in rows}) != len(rows): raise ValueError("Repeated parallel page")
                    exact = [p for p in rows if p.get("setId") == card["setId"] and p.get("releaseId") == card["releaseId"]
                             and variant_name(p.get("name"), rated_rookie) == variant_name(a["parallel"], rated_rookie)
                             and ((tier is None and p.get("numberedTo") is None) or (type(p.get("numberedTo")) is int and p["numberedTo"] == tier))]
                    if len(exact) != 1: raise NoExactMatch("variant_not_exact")
                    variant = exact[0]
                parallel_id = variant["id"] if variant else None
                def records_for(requested_parallel, period):
                    response = self.client.request("POST", "/v1/pricing/", body={"card_ids": [card["id"]], "parallel_id": requested_parallel,
                        "grade_id": None, "period": period, "listing_type": "auction", "limit": 25})
                    results = response.get("results", [])
                    if len(results) != 1 or results[0].get("card_id") != card["id"] or not results[0].get("success"): raise ValueError("Incomplete price response")
                    data = results[0]["data"]
                    query = data.get("query", {})
                    if any(query.get(k, "missing") != v for k, v in {"parallel_id": requested_parallel, "grade_id": None, "period": period, "listing_type": "auction"}.items()): raise ValueError("Wrong price filters")
                    context = data.get("card", {})
                    if context.get("card_id") != card["id"] or context.get("set", {}).get("set_id") != card["setId"]: raise ValueError("Wrong card context")
                    if requested_parallel and context.get("parallel", {}).get("parallel_id") != requested_parallel: raise ValueError("Wrong parallel context")
                    records = data.get("raw", {}).get("records", [])
                    if not isinstance(records, list) or len(records) > 25 or any(not isinstance(r, dict) for r in records): raise ValueError("Unexpected record count")
                    return records, bool(data.get("messages")) or len(records) == 25

                def collect(records, days):
                    seen, fingerprints, accepted = set(), set(), []
                    for record in records:
                        if record.get("grade") is not None: continue
                        context = record.get("matched_card")
                        if context is not None:
                            if not isinstance(context, dict) or context.get("card_id") != card["id"]: continue
                            if context.get("set", {}).get("set_id") != card["setId"]: continue
                        today = dt.datetime.now(dt.timezone.utc).date()
                        sale = matching_variant_sale(card, record, variant, tier, names, today, variants, days, rated_rookie) if variant else matching_sale(card, record, names, today, variants, days)
                        if not sale or sale["url"] in seen or sale["fingerprint"] in fingerprints: continue
                        seen.add(sale["url"]); fingerprints.add(sale["fingerprint"])
                        accepted.append({"provider": "CardSight", "url": sale["url"], "kind": "sold", "title": record["title"][:240],
                        "listingURL": sale["url"], "grade": "raw", "condition": None, "matchQuality": "exact", "lowCents": sale["priceCents"],
                        "highCents": sale["priceCents"], "currency": "USD", "saleDate": sale["date"], "checkedAt": value["checkedAt"],
                        "shipping": "unknown", "expiresAt": value["expiresAt"]})
                    return accepted

                for period, days in (("90d", 90), ("1y", 365)):
                    value["stages"].append("catalog_" + period)
                    records, limited = records_for(parallel_id, period)
                    if variant:
                        # General buckets also contain misclassified parallels. Full title proof remains mandatory.
                        general, general_limited = records_for(None, period)
                        records += general; limited = limited or general_limited
                    value["candidateCount"] += len(records)
                    value["sampleLimited"] = value["sampleLimited"] or limited
                    refs = collect(records, 90)
                    if not refs and days == 365: refs = collect(records, 365)
                    if refs:
                        value["references"] = refs
                        value["periodDays"] = 90 if collect(records, 90) else days
                        break
                if not value["references"]:
                    # This pool includes unlinked sales; provider catalog linkage is never a prerequisite.
                    value["stages"].append("title_search_1y")
                    query = f"{a['year']} {a['setName']} {a['player']} {a['cardNumber']}"
                    if variant: query += " " + variant["name"]
                    if tier: query += f" /{tier}"
                    query = query[:300]
                    response = self.client.request("GET", "/v1/pricing/search", {"q": query, "period": "1y", "listing_type": "auction", "limit": 25})
                    echo = response.get("query", {})
                    if any(echo.get(k) != v for k, v in {"q": query, "period": "1y", "listing_type": "auction", "limit": 25}.items()): raise ValueError("Wrong sale search filters")
                    records = response.get("results")
                    if not isinstance(records, list) or len(records) > 25 or any(not isinstance(r, dict) for r in records): raise ValueError("Invalid sale search results")
                    value["candidateCount"] += len(records)
                    value["sampleLimited"] = value["sampleLimited"] or len(records) == 25
                    value["references"] = collect(records, 90)
                    if not value["references"]:
                        value["references"] = collect(records, 365); value["periodDays"] = 365
                value["references"].sort(key=lambda r: r["saleDate"], reverse=True)
                value["status"] = "ready" if value["references"] else "no_match"
                if not value["references"]: value["reason"] = "no_exact_sales" if value["candidateCount"] else "no_sales"
            except NoExactMatch as error:
                value["reason"] = str(error)
            except MarketError as error:
                value["status"] = "unavailable"  # auth/quota/outage: no retries, model switch or search
                value["message"] = str(error)
                value["reason"] = "provider_unavailable"
            except (OSError, ValueError, KeyError, TypeError):
                value["status"] = "unavailable"; value["reason"] = "invalid_response"
            except Exception:
                value["status"] = "unavailable"; value["reason"] = "invalid_response"
            # Failed checks also cool down for 24h. Reopening a screen cannot burn quota.
            return self.with_guide(a, value)

    def needs_guide(self, a, value):
        return (not value["references"] and raw_guides.can_lookup(a)
                and value.get("guideVersion") != raw_guides.VERSION)

    def with_guide(self, a, value, save=True):
        if self.needs_guide(a, value):
            value["guideVersion"] = raw_guides.VERSION
            try:
                guide = raw_guides.fetch_guide(a, value["checkedAt"], value["expiresAt"])
                if guide:
                    value["soldStatus"] = value["status"]
                    value["references"] = [guide]; value["status"] = "ready"
            except Exception:
                # The same TTL cools down failures. Never replace the sold result,
                # retry paid services, infer a price, or widen the identity.
                pass
        if save: atomic(self.cache / (identity_key(a) + ".json"), value)
        return value

    def metadata(self, release):
        # Only the short name vocabulary needed to reject wrong inserts and
        # parallels is cached. No provider card/checklist catalog is retained.
        path = self.cache / ("meta-" + hashlib.sha256(release.encode()).hexdigest() + ".json")
        try:
            data = json.loads(path.read_text())
            if data["expiresAt"] > time.time(): return data["sets"], data["parallels"]
        except (OSError, ValueError, KeyError, TypeError): pass
        sets = self.client.request("GET", "/v1/catalog/sets", {"releaseId": release, "take": 100})
        if len(sets.get("sets", [])) != sets.get("total_count"): raise ValueError("Incomplete set coverage")
        variants, total = set(), None
        for skip in range(0, MAX_VARIANT_ROWS, 100):
            page = self.client.request("GET", "/v1/catalog/parallels", {"releaseId": release, "take": 100, "skip": skip, "sort": "name", "order": "asc"})
            count = page.get("total_count")
            rows = page.get("parallels", [])
            if type(count) is not int or not 0 <= count <= MAX_VARIANT_ROWS or (total is not None and total != count): raise ValueError("Incomplete variant coverage")
            total = count
            if len(rows) != min(100, max(0, count - skip)): raise ValueError("Incomplete variant page")
            variants.update(p["name"] for p in rows)
            if skip + len(rows) >= count: break
        names = [s["name"] for s in sets["sets"]]
        atomic(path, {"expiresAt": time.time() + TTL, "sets": names, "parallels": sorted(variants)})
        return names, sorted(variants)

    def attach(self, result):
        output = deepcopy(result)
        a = output.get("analysis")
        if not a or not a.get("insights"): return output
        price = self.cached(a)
        if not price:
            info = a["insights"]
            info["marketReferences"] = []
            info["sourceChecks"] = [{"provider": "CardSight", "status": "not_checked", "url": "https://cardsight.ai"}]
            if not a.get("identityConfirmed") or a.get("confidence") != "high":
                message = "Preisrecherche wartet auf eine bestätigte, eindeutige Kartenidentität."
            elif not eligible(a):
                info["sourceChecks"][0]["status"] = "no_match"
                message = "Diese genaue Produktfamilie oder Variante wird von der Preisrecherche noch nicht unterstützt."
            else:
                message = "CardSight-Preisrecherche läuft oder steht noch aus."
            info["marketBullets"] = [message]
            a["marketLowCents"] = a["marketHighCents"] = None
            a["marketSources"] = []
            return output
        info = a["insights"]
        info["marketReferences"] = deepcopy(price["references"])
        guide = bool(price["references"] and price["references"][0]["kind"] == "guide")
        sold_status = price.get("soldStatus", price["status"])
        info["sourceChecks"] = [{"provider": "CardSight", "status": "found" if sold_status == "ready" else sold_status, "url": "https://cardsight.ai"}]
        info["marketBullets"] = ["Von CardSight gemeldete Auktionen; Versandkosten unbekannt."] if price["references"] else []
        if guide:
            provider = price["references"][0]["provider"]
            info["sourceChecks"].append({"provider": provider, "status": "found", "url": price["references"][0]["url"]})
            source = "SportsCardsPro über Slabline" if provider == "Slabline" else provider
            info["marketBullets"] = [f"Geschätzter Raw-Richtwert: {source}. Kein bestätigter Verkauf."]
            captured = price["references"][0].get("checkedAt")
            if captured and captured != price["checkedAt"]:
                info["marketBullets"].append(f"Preisstand der Quelle: {captured}; älterer Schätzwert.")
        if price.get("periodDays") == 365 and price["references"] and not guide:
            info["marketBullets"].append("Keine neueren exakten Auktionen; Vergleich bis zu 12 Monate alt.")
        reasons = {"catalog_not_exact": "Kein eindeutiger Katalogeintrag für diese genaue Karte.",
                   "variant_not_exact": "Diese Variante oder Nummerierung ist im Preiskatalog nicht eindeutig zugeordnet.",
                   "no_sales": "Keine Auktionen gefunden; auch nicht in 12 Monaten oder der zusätzlichen Verkaufssuche.",
                   "no_exact_sales": "Auktionen geprüft, aber keine exakte ungegradete Variante ohne Warnhinweise gefunden.",
                   "invalid_response": "Die Preisquelle konnte nicht sicher ausgewertet werden. Kein Preis geschätzt."}
        if price.get("reason") in reasons:
            if guide and price["reason"] == "invalid_response":
                info["marketBullets"].append("Die Auktionsquelle konnte nicht sicher ausgewertet werden; der Guide wurde getrennt geprüft.")
            else: info["marketBullets"].append(reasons[price["reason"]])
        if price.get("message"): info["marketBullets"].append(price["message"][:180])
        if price["sampleLimited"]: info["marketBullets"].append("Begrenzte Stichprobe; ältere Verkäufe können fehlen.")
        a["marketLowCents"] = a["marketHighCents"] = None
        a["marketSources"] = []
        a["marketCheckedAt"] = price["checkedAt"]
        return output

    def attach_comparable(self, result, peers):
        """Low-confidence cohort range from fresh evidence already in our cache.

        No network calls, new provider catalog, synthetic sale, or durable estimate.
        Restrict the first version to unnumbered base cards, same release/rookie class.
        """
        a = result.get("analysis") or {}
        if not eligible(a) or a.get("parallel") or a.get("serialNumber") or a.get("subset") != "Base":
            return result
        if type(a.get("rookie")) is not bool or (a.get("insights") or {}).get("conditionStatus") != "no_obvious_damage":
            return result
        if (a.get("insights") or {}).get("marketReferences"):
            return result  # Exact evidence always wins.
        scope = ("year", "brand", "setName", "subset", "parallel", "rookie")
        grouped = {}
        now = time.time()
        for peer in peers:
            if not eligible(peer) or peer.get("serialNumber") or any(peer.get(k) != a.get(k) for k in scope):
                continue
            name = normal(peer.get("player"))
            if not name or name == normal(a.get("player")) or (peer.get("insights") or {}).get("conditionStatus") != "no_obvious_damage":
                continue
            cached = self.cached(peer)
            if not cached: continue
            refs = [r for r in cached.get("references", []) if r.get("kind") in ("sold", "guide")
                    and r.get("grade") == "raw" and r.get("matchQuality") == "exact"
                    and type(r.get("lowCents")) is int and type(r.get("highCents")) is int
                    and 0 < r["lowCents"] <= r["highCents"]
                    and now < r.get("expiresAt", 0) <= now + TTL + 60
                    and r.get("url", "").startswith("https://")]
            if not refs: continue
            ref = max(refs, key=lambda r: (r.get("saleDate") or r.get("checkedAt") or "", r["url"]))
            group = grouped.setdefault((ref["currency"], ref["shipping"]), {})
            # Repeated jobs and duplicates of one player count as one comparable.
            if name not in group or ref["checkedAt"] > group[name]["checkedAt"]:
                group[name] = ref
        pools = []
        for key, values in grouped.items():
            distinct = {}
            for name in sorted(values):
                ref = values[name]
                distinct.setdefault(ref["url"], ref)
            refs = list(distinct.values())[:12]
            if len(refs) >= 3: pools.append((key, refs))
        if not pools: return result
        (currency, shipping), refs = sorted(pools, key=lambda x: (-len(x[1]), x[0]))[0]
        output = deepcopy(result)
        output["analysis"]["comparableEstimate"] = {
            "lowCents": min(r["lowCents"] for r in refs), "highCents": max(r["highCents"] for r in refs),
            "currency": currency, "shipping": shipping, "cardCount": len(refs), "confidence": "low",
            "scopeLabel": f"{a['year']} {a['setName']} · Base · {'Rookies' if a['rookie'] else 'Veteranen'}",
            "checkedAt": dt.datetime.now(dt.timezone.utc).date().isoformat(),
            "expiresAt": min(r["expiresAt"] for r in refs),
            "references": [dict(r, matchQuality="near") for r in refs],
        }
        return output
