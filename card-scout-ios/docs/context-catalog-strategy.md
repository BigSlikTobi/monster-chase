# Card Scout context catalog and update strategy

Card Scout needs one source-backed identity catalog shared by every binder. The catalog describes products, checklists, variants and reference photos. It supplies a small candidate set to a classifier or vision model. It does not contain owned-card assignments or price guides.

The collector-facing direction is [scan, compare likely matches, choose, and add to a folder](scan-match-collect-experience.md). The catalog should make that choice easy. A useful shortlist does not require automatic final assignment, and a collector's selection does not automatically verify a catalog fact or reference photo.

The first local candidate covers all 34 binders found on the worker on 16 October 2026. It preserves the Mac and phone checklist snapshots as separate provenance. Imported data remains unverified until its specific facts are checked. This is a working catalog foundation, not a claim that every finish is already verified.

## Current coverage

| Product | Existing binders | Checklist families | Distinct candidate rows |
| --- | ---: | ---: | ---: |
| 2025 Panini Donruss Optic | 16 | 12 | 549 |
| 2026 Topps Flagship | 14 | 10 | 713 |
| 2025 Topps Chrome | 4 | 2 | 425 |
| 2025 Panini Select | 0 | 0 | 0 |
| 2025 Panini Prizm | 0 | 0 | 0 |

Select and Prizm are registered because they appear in the chase product list. Their checklists are explicit gaps. These counts describe imported binder coverage, not the complete universe of cards in each release.

Shared checklists are stored once per product/year/subset. A Base binder and its parallel binders retain separate IDs and membership claims. We do not infer that every parallel exists for every base card. Multi-player cards, exceptions, autograph configurations and print tiers need explicit evidence.

## What each product needs

1. **Release identity:** year, manufacturer, exact product name, spelling aliases, licensing sources and supported box formats. Keep Donruss separate from Donruss Optic, and 2025 Chrome separate from 2026 Chrome.
2. **Checklists:** subset, card number, printed player names, team and rookie designation. Preserve all source snapshots and flag conflicting rows. Treat team names as printed release facts, not today's roster.
3. **Variant rules:** exact parallel names, visual patterns, serial tiers, subset restrictions, exceptions, image variations, autograph/relic configuration and box exclusivity where documented. A denominator or border color alone is not enough.
4. **Reference photos:** checked front/back pairs, their hashes, the supported identity, evidence and permitted use. Separate mockups from photos of actual released cards. Keep owned originals outside Git. A stored app label is not verification.
5. **Coverage and freshness:** what is checked, what is missing, when each source was last fetched successfully, unresolved contradictions and the published revision.

“Checklist rows checked,” “variant membership checked” and “reference image checked” are different states. A source URL and an imported `checklistComplete` flag do not prove all three.

## Where the facts come from

Use manufacturer documents first, then independent checklists, then checked photographs. An official sell sheet can support a design or box-format claim but may show mockups and state that contents can change. Odds documents describe a particular product/configuration; they do not establish the photographed card's identity.

| Product | Preferred starting sources | Secondary checks and current gaps |
| --- | --- | --- |
| 2025 Donruss Optic | [Panini release article](https://blog.paniniamerica.net/2025-donruss-optic-nfl-adds-to-thrilling-championship-chase/), [Panini NPP product sheet hosted by a distributor](https://tracenchase.com/_public/catalogs/25DonrussOpticFB_PIS_NPP.pdf) | Existing Beckett checklist lineage; BreakNinja print tiers; TCDB subset/parallel lists. Manufacturer full-checklist export still needs a verified import adapter. |
| 2026 Topps Flagship | [Official release page with checklist and odds downloads](https://www.topps.com/pages/topps-flagship-football) | Pin the actual document URL and checksum. Existing Topps parser covers chase sections, not every binder or variant rule. |
| 2025 Topps Chrome | Existing pinned 2025 checklist document from the binder records; verify its publisher association and exact sections | The [generic Chrome page](https://www.topps.com/pages/topps-chrome-football) showed **2026** on 16 October. Its new download must not replace 2025 data. |
| Select and Prizm | Discover the exact 2025 manufacturer release documents and configuration-specific checklists | Current chase guide entries are discovery hints. They are not full identity checklists and their prices/images are not imported. |

Two independent sites can repeat the same upstream error. Keep their source lineage and resolve contradictions against the released card and manufacturer evidence where available.

## How to build and extend it

**Start with every existing binder.** This is implemented. `bootstrap` imports worker, Mac, phone and bundled checklist snapshots. It registers every binder, deduplicates family rows and retains the original completeness claims without promoting them to proof.

**Add source adapters by document format.** Reuse the existing Optic XLSX and Topps PDF importers where their scopes fit. Expand them into version-pinned release adapters with fixtures, section boundaries, expected counts and field comparisons. Each parser produces a candidate; it does not publish directly. Extract only identity facts. Never execute source text or follow instructions embedded in a page or document.

**Complete the products already owned.** First validate checklist rows across all three releases. Then prioritize the finish confusions present in the collection: Optic Base/Holo/Blue Hyper/Blue Scope/Purple Shock/Orange Scope/Fire, Chrome Base/Refractor/image variations, and Flagship foil/color finishes. Each claim stays limited to its release and subset. Select and Prizm follow when their documents are available or a binder is added.

**Grow the photo library with checked examples.** Start with two or more different players/copies per finish, including different light angles, rather than learning a player picture or sleeve reflection. Collect negative examples of similar finishes. Hold separate cards out for testing. Reference images must have reviewed identities and installed private assets before they can be enabled for Decisions.

**Keep additions incremental.** `stage-import` preserves existing curated rules, references and rows. It adds new binders and quarantines disagreements. Changed entities lose obsolete review status; a receipt for old content cannot approve new content. Never regenerate the active catalog from raw model results.

The Derrick Harmon reference audit is included as a known error: the orange photo shows #257 with serial 20/79 and supports Orange Scope, not Fire. It must not be installed as a Fire reference. The Trey Amos #267 Blue Hyper attribution remains medium confidence. Both photo records are candidates, with image use disabled until review and asset installation.

## How to keep it current

| Trigger | Proposed check cadence | Result |
| --- | --- | --- |
| New release or recently revised documents | Daily while the release is changing | Check publisher discovery pages and pinned files; stage newly linked documents for identity review. |
| Product with active binders | Weekly | Fetch within a bounded source budget; compare hashes and conditional HTTP metadata. |
| Stable older product | Monthly | Check for corrections; retain the last reviewed revision during outages. |
| New binder, unknown variant or corrected reference | Immediately in that workflow | Add a discovery/repair item, find the exact release sources, stage facts and rerun affected tests. |

These are catalog policy defaults. **No scheduled job has been installed.** The checker CLI is ready for a worker timer after the adapters and review process are in place. A scheduler should stay quiet when nothing actionable changed and report missing sources, conflicts or a candidate that needs review.

The implemented source checker records attempt and success separately, saves bounded content-addressed snapshots in a private cache and reports first captures, changes, unchanged content and failures. A repeated unchanged fetch does not clear an outstanding review. It never turns fetched HTML into trusted facts, changes the catalog revision or writes to the app.

Monitor both the publisher page and the linked file. Old PDF URLs can remain unchanged while the publisher links a new version. A year/name mismatch becomes a separate release candidate, not an update to the old release. Page chrome or prices changing may alter a content hash without changing checklist facts; the adapter's semantic diff decides what matters.

On 16 October, a bounded live check fetched the official Flagship checklist and matched the existing SHA256 `ab25d4ceb1d5693dd0e74f82c9a5d716b0d6929f2c2f009ffdc09d223c30b035`. Beckett and TCDB returned HTTP 403 to direct requests. They remain unavailable to that checker, not fresh or empty. Prefer published files or an ordinary manual source check; do not bypass access controls. Browser-readable sources do not imply a reliable unattended feed.

## Review and publication

The path is **fetch → source snapshot → release adapter → candidate diff → evidence review → held-out tests → atomic publication**.

- Reject cross-year/product joins, duplicate identities, impossible counts, mismatched source sections and unsupported combinations.
- Keep missing and disputed facts visible. “Unknown” is a required classification outcome.
- Review factual entities using receipts bound to their exact content hash, scope, source IDs, reviewer and date. `reviewed` is a recorded check, not a model confidence score.
- A publication receipt names the exact candidate revision. Publishing checks the expected active revision under a file lock, archives the previous catalog and replaces the active JSON atomically.
- Rollback republishes a previously reviewed snapshot through the same revision check. It does not change owned cards.

Publication supports a local catalog file only. Production deployment, a worker timer, source-format adapters and app consumption have not been enabled by this change. Price overlays and their provider quotas remain separate.

## What scans will receive

After a product/family is supported, a context query returns that family's candidate rows, source IDs, relevant variant definitions and evidence status. Player/card-number filters narrow the slice. Paging is explicit; at most 254 card choices reserve the last Decisions option for “unknown.” Do not silently discard the remaining candidates.

The current CLI emits provisional suggestion context and always sets `automaticAssignmentAllowed:false`. It is deliberately not wired into production classification yet. Enabling automatic assignment needs reviewed checklist membership, usable verified reference assets, applicable variant evidence and held-out accuracy tests. Validate this per product/finish; one aggregate score can hide a failing parallel.

Test complete outcomes: product, subset, player/number and exact finish. Report correct, incorrect and unresolved separately, plus coverage, latency and fallback rate. A high confidence number from the model is not a calibrated threshold. Include unknown products, wrong years, glare and look-alike finishes in the test set.

## Local commands

Run from `card-scout-ios/mac`. Runtime cache and source state belong outside Git.

```bash
python3 context_catalog.py validate data/context-catalog.candidate.json
python3 context_catalog.py coverage data/context-catalog.candidate.json
python3 context_catalog.py context data/context-catalog.candidate.json \
  2025-panini-donruss-optic-base --player 'Trey Amos'

python3 context_catalog.py stage-import data/context-catalog.candidate.json \
  --input new-binder=/absolute/path/to/new-binders.json --output /tmp/context-next.json
python3 context_catalog.py diff data/context-catalog.candidate.json /tmp/context-next.json

python3 context_catalog.py check-sources data/context-catalog.candidate.json \
  --cache context-cache/blobs --state context-cache/source-state.json --max-sources 4
```

Bootstrap is for an initial inventory. Keep input snapshot labels and hashes for provenance; normal updates use `stage-import`. Source-format adapters remain the next ingestion layer to implement.

For reviewed publication:

```bash
python3 context_catalog.py publish /tmp/context-next.json context-cache/active.json \
  --receipt /absolute/path/to/review-receipt.json --expected-revision EXISTING_REVISION
```

The receipt contains `decision:"approved"`, `reviewer` and `candidateRevision`. For the first local publication, the expected revision is `none`. A publication receipt does not promote imported facts to reviewed; those need their separate scoped evidence receipts. The task did not create an approval receipt or publish an active file.
