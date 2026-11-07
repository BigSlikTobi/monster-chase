# Pricing coverage audit — 16 October 2026

The collector reported nearly all newly completed scans lacked prices. The audit used saved analyses, live CardSight requests from the VPS, and the app's authenticated price responses. It did not reupload photos or rerun Luna. Historical server jobs are not a count of physical cards; the refresh selected the latest identifiable revision per player/year/product/card number, then required the existing confirmed/high-confidence gate. Unconfirmed latest revisions were skipped.

## Verified problems

- A 90-day-only catalog-linked auction lookup missed older exact sales. Matthew Golden #205 had a clean June auction outside that window.
- CardSight's title search exposes auction records that have never been linked to its card catalog. Andres Borregales #287 returned no catalog-linked records, but the additional pool had two exact auctions. Chase Brown #197 and Tyleik Williams #246 also gained recent exact evidence there.
- Literal subset equality treated the saved `All-Chrome Team` and provider `All Chrome Team` as different. Matching now normalizes punctuation/case, without equating different insert names.
- Exact parallel lookup assumed the name-filtered result fit in 100 rows. The live Chrome `Refractor` query contains 272 entries. The correct All Chrome Team Refractor is on a later page. Resolution now validates at most four complete, nonrepeating pages and still requires exactly one UUID for the same set, name, and print tier.
- The old pilot had an unrelated 270/day stop. It could block free research with hundreds of calls left in the monthly budget. It now follows the shared 720/month stop. Reservation locking, account usage checks, auth/quota halt, and no-purchase behavior remain intact.
- Several different failures previously became the same `no_match`. Cache diagnostics and the app's transient market bullets now distinguish unresolved catalog/variant, no records, nonexact/unsafe records, provider failure, and invalid responses.

## Source limitations remain

The wider window and extra pool do not make every sale usable. Isiah Pacheco #147 returned Stars/Emoji variants or `READ` warnings. Terry Bradshaw Holo search returned a Blue Stars Holo; that is not proof of the owned Holo. Other listings explicitly questioned whether the card was an insert. The matcher now rejects observed Emoji/Fire/Electricity base misclassifications and `Insert ?`/`Parallel ?`/`Variant ?` titles. Existing grading, condition, lot, title, serial-tier, date, source, and deduplication protections remain.

CardSight's `fixed` data represents asking prices, not necessarily completed sales. It remains excluded. See [provider API reference](https://api.cardsight.ai/documentation) and [provider price-data explanation](https://cardsight.ai/solutions/price-data).

## Deployed lookup

1. Require a confirmed, high-confidence saved identity and an exact canonical card/variant resolution.
2. Check at most 25 recent auction records per bucket (plus the general bucket for parallels, which also needs exact finish/tier proof).
3. If no exact sale qualifies, check a bounded 12-month window. Prefer recent exact records if any appear.
4. If still empty, make one bounded, auction-only title query for the complete identity and variant. Reject conflicting canonical IDs and grade metadata. Unlinked rows need full exact title proof.
5. Cache only accepted evidence and diagnostics for 24 hours. Clearly label older-only evidence. Failed/negative checks also cool down. Never try a paid tool, another model, a guessed value, or a substitute variant.

Matcher version 4 invalidates pre-audit views. Separate catalog/variant resolution markers selectively invalidate only negative results affected by the punctuation/page fixes, preserving already refreshed good prices. No source catalog or rejected listing archive is retained. Owned-card SQLite results remain unchanged; the existing transient price overlay delivers the new data.

## Validation and live refresh

168 Python backend tests pass, including recent-versus-old preference, unlinked exact auctions, wrong canonical/grade/variant rejection, numbered tiers, bounded later-page UUID resolution, response diagnostics, cache invalidation, shared quota locking, and Luna with no paid-search/model fallback.

The first completed refresh checked 20 latest confirmed saved identities. Exact price views improved from 5 to 10, with five newly priced identities: Chase Brown #197, Andres Borregales #287, Matthew Golden #205, Tyleik Williams #246, and Tristan Wirfs #287. Older-only evidence was labelled and verified through the actual app API. Other confirmed cards remained unpriced rather than receiving questionable comps. The final additional Refractor check is recorded separately below.

The final parallel-page repair recovered two recent exact Derek Stingley Jr. ACT-19 Refractor auctions. Final coverage is **11 of 20 confirmed identities**, up from 5. Total shared usage at completion was **397/720**, including diagnosis and refresh; the ledger began at 273 before this audit. Nine identities still lacked qualifying exact evidence. No claim of complete source coverage is made.

After restarting the existing iPhone build 24 to hydrate fresh views, its aggregate delivery receipt confirmed **11 cards with fresh prices and 32 references** at 2026-10-16T14:45:01Z. No individual card opening or new app installation was needed for these backend fixes.

Luna remains the configured analysis model. Paid OpenAI search and automatic model fallback remain disabled. The shared ledger was never reset; the 720-call monthly hard stop remains.
