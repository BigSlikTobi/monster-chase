# Matching and rough estimates — build 29

The priority is the correct card and variant. Prices are sourced estimates; exact recent sales are optional. A missing price is not zero.

## Catalog and matching

- The worker now adds **1,662 rows across 20 additional binders** to the live catalog: **55 binders / 6,476 rows**, up from 35 / 4,814. Existing assignments and conflicting records are preserved.
- The [official Topps Chrome checklist](https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2025_Chrome_Football_Checklist_040826.pdf?v=1775678965) supplies 1,789 explicit unsigned base, insert and variation entries across 22 families. Of those, 1,362 were missing in the live catalog. Autographs, memorabilia and unlisted color combinations are excluded.
- PDF SHA-256: `590ad763a6695b43db60dd1395a271c47b262f8084a40b2ef3511cd8001b9ae5`. Regenerate with `mac/import_chrome_checklist.py`; edition, sections and counts are checked.
- Orange Scope adds 300 Optic entries. [Beckett](https://www.beckett.com/news/2025-donruss-optic-football-cards/) explicitly lists this /79 parallel for both #1–200 veterans and #201–300 Rated Rookies. [TCDB's Orange Scope checklist](https://www.tcdb.com/Checklist.cfm/sid/589443/2025-Donruss-Optic-Orange-Scope) independently reports 300 entries. The existing base identity rows are reused only for this documented family. Orange /299 stays separate. This is a reviewed snapshot, not a live TCDB connector.
- Matching normalizes punctuation and accents and scores subset/product context. Decisions receives up to six verified reference fronts, including clearly labeled examples of the same finish when an exact card image is unavailable. Downloaded bytes must match the reviewed checksum. Different-player examples never establish checklist membership.
- The existing manifest has 547 exact fronts. More checklist entries do **not** mean complete image coverage. Candidate ranking remains bounded to 40 rows and five suggestions. The collector confirms the choice.
- The phone detects catalog changes independently of image changes.

## Estimates

- Opening the app starts background price requests for saved analyses, at most six pending on the phone. The worker processes its bounded price queue and reuses fresh caches.
- Free raw guides run before CardSight auction research. A valid estimate avoids auction quota use. The existing shared free quota and paid-search prohibition remain in force.
- Confirmed identities can receive estimates even if license recognition is unresolved. Unconfirmed/low-confidence identities remain ineligible. Select and Prizm are accepted lookup products; this does not imply complete catalogs for them.
- Dated guide captures up to 730 days old can be used, with their source date retained and older estimates identified. Provider caches still expire after 24 hours.
- Numbered-card guides must explicitly support the same print tier. Known Orange /299 versus Orange Scope /79 contradictions cannot receive prices. No color multipliers, graded-to-raw conversions or model-generated prices.
- The user explicitly approved sharing identity fields with Slabline, Card Centering Tool and the existing CardSight service for estimates and automatic refresh. Price lookups send no photos.

## Validation and limits

- 223 Python tests passed.
- 134 Swift tests ran: 133 passed, one skipped.
- Signed iPhone build 1.1 (29) succeeded.
- Build 29 was installed and launched on the physical iPhone. Its connection receipt confirmed accepted TLS and a reachable worker. Its saved library contained 45 owned cards and the complete updated 55-binder / 6,476-entry catalog.
- Live worker deployment verified 55 binders / 6,476 entries and unchanged contents of all 160 saved job records. Sources and SQLite were backed up before restart.
- The user approved sending the two existing front/back photo pairs to their worker and existing OpenAI setup. No saved-card assignments were changed by the test.
- Initial test: Harmon could not match Orange Scope because the family was absent. After adding it, #257 Orange Scope ranked first despite first-pass OCR reading #357.
- Amos Blue Hyper ranked first in the initial reference-image run, then second behind Purple Shock on rerun. This remains ambiguous. Two cases do not establish general accuracy or justify automatic variant assignment.
- Free guides returned estimates for **2 of 8** selected confirmed historical identities. This test made zero CardSight calls. It is not a measurement of the phone's current inventory or proof that the reported 60% missing-price rate is fixed.
- The subsequent automatic refresh was measured against hashes of the **45 actual phone identities**. At 10:45 CEST, the worker had prices for **25 / 45 (56%)**; nine identities were ineligible, nine were checked without usable prices, and two remained pending. The nine checked misses comprised six without exact sales, one without sales, one ambiguous provider variant, and one temporary provider failure. CardSight usage was 678 / 720 at that point.
- The last readable phone delivery receipt showed 11 priced cards, including four guide estimates, before the phone locked again. The worker's 25 available prices are not a claim that all 25 had already rendered on screen. Reopen Card Scout to sync the remaining results. No controlled inventory-wide before/after accuracy or price-coverage benchmark was run.
- Temporary VPS copies of the two test photo pairs were removed after testing.

Detailed matching outputs: [test report](matching-test-2026-10-20.json).
