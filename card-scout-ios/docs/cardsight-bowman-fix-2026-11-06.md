# CardSight Bowman pricing repair — 6 November 2026

The live account was reachable, its existing key was valid, and its November
ledger started at 25 calls against the existing 720-call stop. The 46 server
assessments were all Bowman. The pricing adapter excluded that release, leaving
the phone with `unsupported` statuses and old SportsCardsPro/eBay errors.

Two additional adapter gaps would have blocked pricing after enabling Bowman:
the owned `Chrome Base` subset is named `Chrome` by CardSight, and the release
has 430 parallel records, above the previous 400-row metadata limit.

## Change

- Enable confirmed, high-confidence Topps Bowman 2026 `Base`, `Chrome Base`,
  `Paper Prospects` and `Chrome Prospects`.
- Resolve `Chrome Base` against the observed `Chrome` provider subset, and
  `Paper Prospects` against `Prospects`, without changing the saved identity.
  Require the exact release, player and number.
- Keep paper numeric #1–200 separate from Chrome BCV-1–BCV-200. Reject Sapphire,
  University/U, Draft, Best, other products, graded cards, lots, numbered tiers
  and parallel finishes when they do not match the owned card. Prospect BPP/BCP
  prefixes cannot match a paper NFL numeric card number. BPP paper and BCP Chrome
  remain separate; their full catalog-confirmed numbers establish the prospect
  family even when a seller omits the word "Prospects".
- Read at most 1,000 variant metadata rows in validated 100-row pages. Cache only
  the bounded name vocabulary for 24 hours. Incomplete or oversized catalogs fail.
- Replace old scraping errors with the active CardSight status even before a
  cached price exists. Explain identity and unsupported-family gaps separately.

Autograph and other unverified families remain outside this repair. Unconfirmed
identities remain unpriced. Existing exact parallel matching, the 720-call stop, transient caches,
and disabled paid web search remain in force. No new service or subscription was
added. Pricing refreshes send identity fields, not photos.

## Verification

All 250 Python worker tests passed, including eight Bowman pricing regressions.
They cover paper/Chrome lookup, wrong-product rejection, unchanged owned identity,
pending source status, 430-row pagination, caching, incomplete/oversized data,
exact prospect subset aliases and number-prefix rejection.

The two production modules were backed up under
`/var/lib/cardscout/data/upgrade-backups/cardsight-bowman-20261106T202819Z`.
Deployment checked the queue was idle before restarting only Card Scout.
Authenticated HTTPS health returned 200 with the existing certificate trust.
The 46 saved assessment rows retained their pre-deployment SHA-256 digest:
`e586d16577e96c317d1d575291b1be367d8afcfee299a01ee8992a9e3f501d6f`.
The prospect extension also has a private backup under
`/var/lib/cardscout/data/upgrade-backups/cardsight-prospects-20261106T203405Z`.

A live three-card canary recovered an exact raw Jahmyr Gibbs #30 auction. Micah
Parsons paper and Justin Jefferson Chrome returned candidates, but none passed
the exact raw sale checks. Their rejected parallels did not become base prices.
Pricing-only refreshes were then queued through the existing authenticated API
for 24 eligible saved jobs. No analysis, capture or collection reset was needed.

The existing iPhone build 39 was reopened. Its live connection receipt confirmed
accepted trust, connected and writable state. The 20:29:49 UTC price receipt
confirmed two cards with fresh CardSight prices and two references, compared
with zero fresh prices and 45 unsupported jobs in its prior receipt. At a later
server checkpoint, 16 checks had completed: 10 ready and six without exact sales,
with usage 111/720. These were intermediate results while hydration continued.

The final authenticated API audit covered all 46 saved jobs: **13 with exact
sales / 38 references**, **13 checked without acceptable exact sales**, and
**20 awaiting identity review**. Both confirmed prospect cards reached the
catalog and auction/title-search stages; their candidates were rejected rather
than mislabelled as base sales. Usage ended at **155/720**. All API responses
showed CardSight as the active source, both deployed module hashes matched the
local files, and Card Scout and the existing Caddy service remained active.
The saved assessment digest was still unchanged.

The final on-device receipt at **20:35:44 UTC** confirmed **13 cards / 38
references** reached build 39, matching server price coverage. This is delivery
evidence, not a screenshot or independent confirmation of every original sale.
The app was reopened after enabling the two prospect families to retry their
old unsupported state. Its owned-card count remained 46.
