# Review, paired capture and rough estimates — build 31

Build 31 adds a concrete repair path for the existing collection before the next 300 cards are scanned.

## Using it

Open **Sammlung → Nächste Schritte · Zuordnung & Preise**. The list separates identity work from missing prices. Missing backs, unresolved matches, failed processing and known checklist contradictions have specific actions. Existing front/back pairs can be reused. A checklist choice is explicit and starts a new analysis; the app does not silently change an owned card's identity.

The default scanner now saves the front locally, then asks for the back of that same card. Back capture is manual, so flipping a card cannot immediately trigger the next front. One unfinished pair survives app restart. It is not uploaded until completed or explicitly released as front-only. A thumbnail identifies the pending front. The user can defer comparison and return through the saved drafts. Photo-library bulk import remains explicitly front-only; arbitrary selected photos are not guessed into pairs.

The review checks include the 2025 Optic Orange /299 versus Orange Scope /79 contradiction, and Blue Hyper/Purple Shock membership in Rated Rookies #201–300. These are narrow checks, not a claim to validate every variant automatically.

## Price coverage and meaning

A read-only audit of the deployed API on 20 October covered all 45 collection identity keys:

| Outcome | Cards |
| --- | ---: |
| Exact-card price evidence, including dated guides | 27 |
| Low-confidence comparison ranges | 5 |
| Identity needs review | 10 |
| Identity eligible, price still unknown | 3 |

Total displayed evidence or comparison coverage: **32/45 (71%)**, up from 27/45 (60%). The final build 31 phone receipt independently confirms the same counts. No fresh provider lookup was made by the audit.

The five added ranges cover Tre Harris base, KeAndre Lambert-Smith base, DJ Moore base, Joe Mixon base and Kyle Pitts Chrome base. They use existing cached prices for at least three different players in the same release, base subset and rookie/veteran class. These are observed comparison ranges, not exact prices or statistical confidence intervals for the owned card. Player demand can differ substantially. The UI labels them “Vergleichsspanne · geringe Sicherheit,” links the underlying evidence, and keeps comparison value separate from exact-card value.

The fallback requires a confirmed identity, no obvious damage, no parallel and no serial number. It excludes the target player, deduplicates players and source URLs, never mixes currencies/shipping conventions, and considers at most 12 source cards. Exact-card evidence wins. No model invents a number. The range is min–max of the selected evidence and expires with its earliest source, within 24 hours. It is delivery-only and is stripped from persistent owned-card storage.

Normal authorized price refresh still runs when connected. Interrupted or failed requests retry after 30 seconds instead of being treated as finished for the session. A checked miss can be revisited as the cached comparison pool grows; negative source results remain cached for 24 hours. The new comparison calculation itself makes no provider or model calls.

## Verification and rollout

- Python backend: **229 tests passed**, including API delivery, non-persistence, duplicate sources, sparse/mixed pools and expired evidence.
- Swift core: **139 tests executed, one skipped, zero failures**. Added paired-capture restart/rollback, wrong-card and repeated-callback guards, explicit front-only completion, review conflicts and transient comparison expiry checks.
- Signed Release iPhone build 31 succeeded. The isolated Debug simulator build 30 (same review/capture UI, before the refresh-retry fix) also succeeded.
- Simulator review navigation and missing-price layout inspected using separate demo data.
- Backend deployed with backup `/var/lib/cardscout/backups/review-20261020-1792487739`.
- All **160 saved server job records unchanged**, with **55 binders / 6,476 checklist rows** preserved.
- The deployed API returned the counts above across 45 read-only requests.
- Build 31 installed and launched on the iPhone. Its final delivery receipt at 09:25:21 UTC confirms all **45 owned cards**, **27 exact-card results**, **five comparison estimates**, and **10 identity review items**. All 45 jobs were attempted: 27 ready, five estimates, 10 unsupported identities, two checked misses and one unavailable source. See [rollout receipts](review-rollout-2026-10-20.json).

Still required: a physical 20-card intake trial, including front/back pairing, an interrupted pair, duplicate handling and uncertain variants. The code and persistence tests do not establish camera performance across the remaining 300 cards. Resolve the review queue, try 20 cards, then expand the batch. An unsupported or unsourced price stays unknown rather than becoming zero or a fabricated number.
