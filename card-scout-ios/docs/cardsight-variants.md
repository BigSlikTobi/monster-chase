# Exact parallels and numbered-card pricing

**Current coverage update:** [Pricing coverage audit](pricing-coverage-audit.md) adds bounded annual-history and unlinked-auction queries while preserving the exact finish/tier contract below. The 270/day pilot guard described historically below has been removed; the shared 720/month hard stop remains.

Enabled on the VPS on 16 October 2026. The existing iPhone build 20 can display
these price views; no new app install, library migration or photo upload is
needed for a price lookup. Luna remains the analysis model. Paid OpenAI web
search stays hard-disabled, with no automatic model or source fallback.

The shared CardSight stop is now **720 requests/month**, changed from 600 at the
user's request. The free provider allowance remains 750. The existing separate
270/day guard, account-usage checks, pre-request reservations, process-safe file
lock and auth/quota halt behavior remain unchanged. The usage ledger was not
reset and no subscription/call pack was purchased.

## Exact variant contract

The saved card must still have a high-confidence, confirmed, licensed identity,
including player, year, product, subset and number. A parallel must resolve to
one canonical CardSight label and exactly one UUID in that release **and set**.
Names are normalized for case/punctuation and a trailing “Variation(s)”
descriptor only. Colors/finishes are never equated. The catalog's original
spelling is used for the native search; `Red/White/Blue Refractor` cannot be
looked up by inventing a different literal substring.

For numbered cards, both the exact named finish and a valid saved serial are
required. The serial denominator must equal CardSight's numeric `numberedTo`.
A denominator alone cannot select a parallel. An unnumbered saved card cannot
inherit a numbered variant's prices. Ambiguous matches or incomplete metadata
stop before pricing.

The pricing request uses the resolved parallel UUID. Response query/card/set/
parallel IDs must agree. Every accepted sale also needs independent title
evidence for the complete finish. Numbered sales must explicitly show the same
denominator. Different individual serial numerators within the same tier can
be comps—for example 17/50 for an owned 1/50—but /99 is never a /50 comp. No
premium for first/last/jersey-number copies is inferred. Grade, lot, damage,
date, currency, duplicate and source-link checks remain active.

CardSight demonstrably stores some parallels in its general/base-query results.
Therefore the adapter also reads one bounded general result page for the same
card ID. This supplies candidate records only: the exact finish/tier title
checks still apply, and base-card prices are rejected. This is a second query
to the same free-quota provider, not another source or a substitute base price.
At most 25 records per query are considered, and duplicate sales across the two
responses count once. A capped sample remains labeled as limited.

With fresh release metadata, an uncached parallel lookup uses at most five
requests: usage, card ID, parallel ID, exact pricing and general candidates.
The first lookup for a release may add one set-name request and up to four
parallel-name pages (ten total). Fresh price views reuse the existing 24-hour
cache. Existing fresh base-price views remain valid across this extension.
Failures are cooled down; quota/auth failures never cause an automatic retry
through another route. CardSight evidence still stays outside saved card
records and the iPhone's permanent library.

## Existing cards

Opening an existing card starts/reuses price research from its **saved identity**.
Fresh cached views can also reload through the existing collection GET flow.
It does not rerun Luna's photo/condition assessment or overwrite the identity.
No repeat scan or upload is needed just because pricing support changed.

An unresolved identity remains unresolved. In the inspected server records,
several Blue Hyper cards had no card number and medium confidence; a Power Plays
Refractor also remained medium confidence. They cannot be priced as exact
matches. Correct the identity using **Zuordnung korrigieren**, or request
**Neu bewerten** using the existing saved photos. A sharper/back photo is useful
when the stored image cannot establish the number or finish. The new pricing
code never silently upgrades confidence or guesses a missing number.

The already-confirmed Jayden Daniels #295 “Lightboard Logo Variation” resolves
to CardSight's exact “Lightboard Logo Variations” UUID. No accepted auctions
were returned in the tested 90-day/bounded sample, so that card remains unpriced.
It does not receive the base Jayden price.

## Verification

**154 Python tests passed.** New controls cover a positive exact numbered match,
wrong denominator, wrong color/finish, a competing Football Leather variant,
missing title evidence, grading/lots, wrong parallel UUID, wrong subset UUID,
serial/metadata disagreement, cache reuse and rejection of base prices from
the candidate page. The quota-boundary concurrency test asserts the new hard
720 limit. No native code changed for this extension.

Real VPS checks:

- Jaxson Dart #306, 2025 Topps Chrome Red/White/Blue Refractor: **14** accepted
  provider-reported auction records, all with the requested finish in their
  titles. The numbered/other-parallel/base records were not substituted.
- Existing Jayden Daniels Lightboard Logo: exact catalog resolution, **zero**
  accepted records in the bounded sample. No price invented.
- Jaxson Dart Gold Refractor /50 and Blue Refractor /150 target controls:
  **zero** accepted records. The positive numbered matching path is regression
  tested; this live sample does not demonstrate a fresh numbered-card price.

Target-only controls were not added to the owned collection. Temporary control
price-cache files were removed after the test. No photo or grading claims were
made for those control targets. Original listing photos/payment remain
unverified; prices are attributed to CardSight with unknown shipping.

The new constant was verified on the VPS after restart. Luna/API settings,
disabled search and disabled fallback were preserved. The final queue check showed 23 analyzed jobs; no test controls were added to it. The local usage ledger was 216/month and 191/day, below both hard caps. See [the underlying price-view integration](cardsight-price-research.md)
for the server/phone persistence and expiry checks.
