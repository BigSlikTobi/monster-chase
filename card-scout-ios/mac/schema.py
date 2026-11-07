"""Strict response contract, shared by the Mac worker and its tests."""
def obj(properties):
    return {"type": "object", "properties": properties, "required": list(properties), "additionalProperties": False}

S = {"type": "string"}
N = {"type": ["string", "null"]}
I = {"type": ["integer", "null"]}
B = {"type": "boolean"}
def enum(*values): return {"type": "string", "enum": list(values)}
def bullets(maximum): return {"type": "array", "items": {"type": "string", "maxLength": 180}, "maxItems": maximum}
REFERENCE = obj({
    "provider": enum("SportsCardsPro", "eBay", "PSA"), "url": S, "kind": enum("guide", "sold"),
    "title": {"type": "string", "maxLength": 240}, "listingURL": N,
    "grade": S, "condition": N, "matchQuality": enum("exact", "near", "proxy"),
    "lowCents": {"type": "integer"}, "highCents": {"type": "integer"}, "currency": S,
    "saleDate": N, "checkedAt": S, "shipping": enum("included", "excluded", "unknown", "not_applicable"),
})
SOURCE_CHECK = obj({"provider": enum("SportsCardsPro", "eBay", "PSA"), "status": enum("found", "no_match", "paywalled", "unavailable", "not_checked"), "url": N})
INSIGHTS = obj({
    "rarityTier": enum("base", "insert", "parallel", "numbered", "one_of_one", "unknown"),
    "rarityBullets": bullets(3),
    "conditionStatus": enum("no_obvious_damage", "visible_damage", "not_assessable"),
    "conditionIssues": bullets(4), "conditionLimitations": bullets(2),
    "marketBullets": bullets(3), "marketReferences": {"type": "array", "items": REFERENCE, "maxItems": 6},
    "sourceChecks": {"type": "array", "items": SOURCE_CHECK, "maxItems": 3},
    "actionReason": {"type": "string", "maxLength": 180},
})
SOURCE = obj({"url": S, "title": S, "status": enum("sold", "ask"), "matchQuality": enum("exact", "near", "proxy"), "deliveredTotalCents": I, "currency": S, "saleDate": N})
CARD = obj({"number": S, "player": S, "team": S, "rookie": B, "imageURL": N})
COLLECTION = obj({"id": S, "name": S, "year": {"type": "integer"}, "brand": S, "subset": S, "parallel": N, "expectedCount": I, "checklistComplete": B, "sourceURL": N, "checkedAt": N, "cards": {"type": "array", "items": CARD}})
ANALYSIS = obj({
    "player": N, "year": I, "brand": N, "setName": N, "subset": N, "cardNumber": N,
    "parallel": N, "team": N, "rookie": {"type": ["boolean", "null"]}, "serialNumber": N,
    "recommendation": enum("Keep", "Sell", "Grade", "Bulk"), "marketLowCents": I, "marketHighCents": I,
    "marketCheckedAt": S, "marketSources": {"type": "array", "items": SOURCE},
    "confidence": enum("low", "medium", "high"), "conditionNotes": S, "rationale": S,
    "needsReview": B, "identityConfirmed": B, "licenseScope": enum("nfl", "nflpa", "nfl_and_nflpa", "college", "unknown", "unlicensed"),
    "psa10ChanceLow": I, "psa10ChanceHigh": I, "uncertainties": {"type": "array", "items": S}, "currency": enum("EUR"),
    "insights": INSIGHTS,
})
RESULT = obj({"analysis": ANALYSIS, "collection": COLLECTION})
MARKET_FIELDS = ("recommendation", "marketLowCents", "marketHighCents", "marketCheckedAt", "marketSources", "rationale")
MARKET_INSIGHT_FIELDS = ("marketBullets", "marketReferences", "sourceChecks", "actionReason")
MARKET_RESULT = obj({**{k: ANALYSIS["properties"][k] for k in MARKET_FIELDS},
                     **{k: INSIGHTS["properties"][k] for k in MARKET_INSIGHT_FIELDS}})
ANALYSIS_VERSION = 3

# The capture lane reads the photos only. No price/checklist research is needed
# to return the first useful identity and visible condition result.
IDENTITY_RESULT = obj({"playerNameOnCard": N, **{key: ANALYSIS["properties"][key] for key in (
    "player", "year", "brand", "setName", "subset", "cardNumber", "parallel", "team", "rookie",
    "serialNumber", "confidence", "licenseScope", "conditionNotes", "uncertainties")},
    **{key: INSIGHTS["properties"][key] for key in (
        "rarityTier", "rarityBullets", "conditionStatus", "conditionIssues", "conditionLimitations")}})
