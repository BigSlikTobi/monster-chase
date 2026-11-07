"""Bounded, exact raw-guide retrieval. No search, model, key or graded conversion."""
from decimal import Decimal
from html.parser import HTMLParser
from html import unescape
import datetime as dt
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request

# Only individually checked identities/pages. Never construct URLs from model text.
PACHECO = dict(player="Isiah Pacheco", year=2025, brand="Panini", setName="Donruss Optic",
               subset="Base", cardNumber="147", parallel=None, serialNumber=None)
PACHECO_URL = "https://slabline.ai/cards/2025-donruss-optic-football-isiah-pacheco-147-psa-10"
VERSION = 3
_blocked_until = {}
_release_links = {}
MIDPOINT_RELEASES = {("Topps Chrome", 2025, "Base"): "/sets/football/2025-topps-chrome"}


def supported(a):
    return all(a.get(k) == v for k, v in PACHECO.items())


def can_lookup(a):
    return (a.get("setName") in ("Donruss Optic", "Select", "Prizm", "Topps Chrome", "Topps Flagship Football")
            and a.get("brand") == ("Panini" if a["setName"] in ("Donruss Optic", "Select", "Prizm") else "Topps")
            and type(a.get("year")) is int and 1980 <= a["year"] <= dt.date.today().year
            and all(isinstance(a.get(k), str) and a[k] for k in ("player", "subset", "cardNumber"))
            and (not a.get("serialNumber") or (bool(a.get("parallel")) and serial_tier(a) is not None)))


def serial_tier(a):
    match = re.fullmatch(r"\s*(\d{1,6})\s*/\s*(\d{1,6})\s*", a.get("serialNumber") or "")
    return int(match[2]) if match and 0 < int(match[1]) <= int(match[2]) else None


def tier_matches(text, a):
    if not a.get("serialNumber"): return True
    tier = serial_tier(a)
    # Numbered cards need explicit source print-run evidence, not a color multiplier.
    stated = {int(n) for n in re.findall(r"(?:serial numbered to|print run:?\s*/?|numbered to)\s*(\d+)", text, re.I)}
    return tier is not None and stated == {tier}


def normalized(text):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", text.lower().replace("’", "").replace("'", "").replace(".", "")).split())


def finish(text):
    return re.sub(r" variations?$", "", normalized(text or ""))


def exact_name(name, a):
    m = re.fullmatch(r"(.+?)(?: \[([^\]]+)\])? #([A-Za-z0-9-]+)", name)
    return bool(m and normalized(m[1]) == normalized(a["player"])
                and m[3].casefold() == a["cardNumber"].casefold()
                and finish(m[2]) == finish(a.get("parallel")))


def release_names(a):
    # Explicit spelling aliases for the same release, never Sapphire/Black/college.
    product = a["setName"]
    bases = ([f"Panini {product}", product + " Football", product]
             if a.get("brand") == "Panini" else [product, product + " Football"])
    suffix = "" if a["subset"] == "Base" else " " + a["subset"]
    return {normalized(str(a["year"]) + " " + p + suffix) for p in bases}


def public_get(url, *, limit=2_000_000):
    host = urllib.parse.urlsplit(url).hostname
    if host not in ("slabline.ai", "www.cardcenteringtool.com"): raise ValueError("Unsupported guide host")
    if time.monotonic() < _blocked_until.get(host, 0): raise ValueError("Guide host cooling down")
    request = urllib.request.Request(url, headers={"User-Agent": "CardScout/1.1 (private collector price research)",
                                                  "Accept": "text/html,text/plain,application/json"})
    try:
        with urllib.request.build_opener(NoRedirects()).open(request, timeout=12) as response:
            if response.status != 200 or response.url != url: raise ValueError("Guide response changed URL")
            raw = response.read(limit + 1)
            if len(raw) > limit: raise ValueError("Guide response too large")
    except urllib.error.HTTPError as error:
        if error.code in (401, 403, 429): _blocked_until[host] = time.monotonic() + 3600
        error.close(); raise
    return raw.decode("utf-8", errors="replace")


class GuidePage(HTMLParser):
    def __init__(self):
        super().__init__(); self.headings = []; self.rows = []; self.text = []
        self.heading = None; self.row = None; self.cell = None; self.hidden = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "noscript"): self.hidden += 1
        if self.hidden: return
        if tag == "h1": self.heading = []
        if tag == "tr": self.row = []
        if tag in ("td", "th") and self.row is not None: self.cell = []

    def handle_endtag(self, tag):
        if tag in ("script", "style", "noscript"):
            self.hidden = max(0, self.hidden - 1); return
        if self.hidden: return
        if tag == "h1" and self.heading is not None:
            self.headings.append(" ".join("".join(self.heading).split())); self.heading = None
        if tag in ("td", "th") and self.cell is not None:
            self.row.append(" ".join("".join(self.cell).split())); self.cell = None
        if tag == "tr" and self.row is not None:
            self.rows.append(self.row); self.row = None

    def handle_data(self, data):
        if self.hidden: return
        self.text.append(data)
        if self.heading is not None: self.heading.append(data)
        if self.cell is not None: self.cell.append(data)


def parse_guide(html, headings=None):
    page = GuidePage(); page.feed(html)
    headings = headings or {normalized("2025 Donruss Optic Isiah Pacheco #147")}
    if len(page.headings) != 1 or normalized(page.headings[0]) not in headings: return None
    rows = [row for row in page.rows if row and row[0] == "Raw / Ungraded"]
    if len(rows) != 1 or len(rows[0]) != 3 or rows[0][2].lower() != "price guide": return None
    if not re.search(r"Price guide data:\s*SportsCardsPro", " ".join(" ".join(page.text).split())): return None
    if not re.fullmatch(r"\$\d{1,6}(?:,\d{3})*(?:\.\d{2})?", rows[0][1]): return None
    cents = int(Decimal(rows[0][1].replace("$", "").replace(",", "")) * 100)
    return cents if 0 < cents <= 100_000_000 else None


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None


def reference(provider, url, cents, a, checked_at, expires_at, title):
    return dict(provider=provider, url=url, kind="guide", grade="raw", condition=None,
                matchQuality="exact", lowCents=cents, highCents=cents, currency="USD", saleDate=None,
                checkedAt=checked_at, shipping="not_applicable", expiresAt=expires_at,
                title=title, listingURL=None)


def parse_midpoint(text, a):
    header = re.findall(r"^# (.+?) — (.+)$", text, re.M)
    if len(header) != 1 or not exact_name(header[0][0], a): return None
    if not header[0][1].startswith("Football Cards "): return None
    if normalized(header[0][1][len("Football Cards "):]) not in release_names(a): return None
    dates = re.findall(r"^- Last price capture: (\d{4}-\d{2}-\d{2})$", text, re.M)
    if len(dates) != 1: return None
    age = (dt.date.today() - dt.date.fromisoformat(dates[0])).days
    if not 0 <= age <= 730 or "Prices are USD" not in text or not tier_matches(text, a): return None
    sections = re.findall(r"^## Raw \(ungraded\) prices\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if len(sections) != 1: return None
    amounts = re.findall(r"^- Ungraded: \$(\d[\d,]*(?:\.\d{1,2})?)$", sections[0], re.M)
    if len(amounts) != 1: return None
    cents = int(Decimal(amounts[0].replace(",", "")) * 100)
    return (cents, dates[0]) if 0 < cents <= 100_000_000 else None


def midpoint(a, checked_at, expires_at):
    base = "https://www.cardcenteringtool.com"
    queries = [a["player"] + (" [" + a["parallel"] + "]" if a.get("parallel") else "") + " #" + a["cardNumber"]]
    if a.get("parallel"): queries.append(a["player"] + " #" + a["cardNumber"])
    for query in queries:
        data = json.loads(public_get(base + "/api/value-check?q=" + urllib.parse.quote(query)))
        rows = data.get("cards")
        if not isinstance(rows, list) or len(rows) > 10: raise ValueError("Guide search changed")
        candidates = [r for r in rows if r.get("game") == "football" and exact_name(r.get("name", ""), a)
                      and isinstance(r.get("set"), str) and r["set"].startswith("Football Cards ")
                      and normalized(r["set"][len("Football Cards "):]) in release_names(a)]
        if len(candidates) > 1: return None
        if not candidates: continue
        path = candidates[0].get("url", "")
        if not re.fullmatch(r"/prices/pricecharting-\d+", path): return None
        value = parse_midpoint(public_get(base + path + ".md"), a)
        if value:
            cents, captured = value
            return reference("Midpoint", base + path, cents, a, captured, expires_at,
                             f"{a['year']} {a['setName']} {a['player']} #{a['cardNumber']} · Raw guide · Midpoint")
    # The public search returns only ten candidates. A published exact-release
    # page can expose an exact card that was crowded out. Retain links in memory
    # briefly; never persist the page, unrelated prices or a provider catalog.
    path = MIDPOINT_RELEASES.get((a["setName"], a["year"], a["subset"]))
    if path:
        cached = _release_links.get(path)
        if not cached or cached[0] <= time.monotonic():
            html = public_get(base + path)
            links = [(href, unescape(re.sub(r"<[^>]*>", "", label)))
                     for href, label in re.findall(r'<a[^>]*href="(/prices/pricecharting-\d+)"[^>]*>(.*?)</a>', html, re.S)]
            _release_links[path] = (time.monotonic() + 600, links)
        else: links = cached[1]
        candidates = {href for href, name in links if exact_name(name, a)}
        if len(candidates) == 1:
            href = candidates.pop()
            value = parse_midpoint(public_get(base + href + ".md"), a)
            if value:
                cents, captured = value
                return reference("Midpoint", base + href, cents, a, captured, expires_at,
                                 f"{a['year']} {a['setName']} {a['player']} #{a['cardNumber']} · Raw guide · Midpoint")
    return None


def slabline(a, checked_at, expires_at):
    base = "https://slabline.ai"
    player = re.sub(r"[^a-z0-9]+", "-", a["player"].lower().replace("’", "").replace("'", "")).strip("-")
    index = public_get(base + "/cards/player/" + player)
    links = list(dict.fromkeys(re.findall(r'href="(/cards/[^"?#]+-psa-10)"', index)))
    # Inspect only a few published detail links for this year and card number.
    suffix = "-" + a["cardNumber"].lower() + "-psa-10"
    candidates = [x for x in links if re.fullmatch(r"/cards/[a-z0-9-]+-psa-10", x)
                  and x.startswith("/cards/" + str(a["year"]) + "-") and x.endswith(suffix)]
    parallel = " [" + a["parallel"] + "]" if a.get("parallel") else ""
    headings = {normalized(p + " " + a["player"] + parallel + " #" + a["cardNumber"]) for p in release_names(a)}
    for path in candidates[:3]:
        html = public_get(base + path)
        cents = parse_guide(html, headings) if tier_matches(re.sub(r"<[^>]*>", " ", html), a) else None
        if cents is not None:
            return reference("Slabline", base + path, cents, a, checked_at, expires_at,
                             f"{a['year']} {a['setName']} {a['player']} #{a['cardNumber']} · Raw guide · SportsCardsPro via Slabline")
    return None


def fetch_guide(a, checked_at, expires_at):
    if not can_lookup(a): return None
    if supported(a):
        try:
            cents = parse_guide(public_get(PACHECO_URL))
            if cents is not None:
                return reference("Slabline", PACHECO_URL, cents, a, checked_at, expires_at,
                                 "2025 Donruss Optic Isiah Pacheco #147 · Raw guide · SportsCardsPro via Slabline")
        except (OSError, ValueError): pass
    for source in (midpoint, slabline):
        try:
            value = source(a, checked_at, expires_at)
            if value: return value
        except (OSError, ValueError, KeyError, TypeError): continue
    return None
