# Card Scout — iPhone + Mac

Build **40** shows a **comparison median** instead of a broad comparison range as
the headline. For €1, €1, €1 and €8, it shows **ca. €1**, with the €1–€8 range as
supporting detail. Collection sorting and indicative totals use the same median.
Comparison evidence remains low confidence and separate from exact-card prices.
See [median pricing and verification](docs/median-pricing-2026-11-06.md).

CardSight now prices confirmed 2026 Bowman NFL paper and Chrome base cards.
The adapter preserves exact family matching and handles the release's larger
variant catalog. See [repair and live verification](docs/cardsight-bowman-fix-2026-11-06.md).

Build **39** keeps acceptable hand-movement tracking across autofocus pulses and removes the extra cooldown after continuous autofocus. The shutter still waits for focus. Build 38 added recovery of repaired analyses; see [failure and recovery](docs/analysis-refresh-recovery-2026-11-06.md). Automatic front/back capture and screen wake behavior remain. See [scan workflow and verification limits](docs/fresh-scan-flow-2026-11-06.md).

Native SwiftUI collection app. The iPhone stores the photos and collection. A paired Mac or private Linux server runs identification and market research. Build 32 fixes reference-comparison navigation that could blank the screen and leave card links unresponsive. See [reproduction and UI verification](docs/reference-navigation-fix-2026-10-20.md). Build 31 adds a review queue, durable front/back capture pairs, and clearly labeled comparison ranges from cached evidence. See [build 31 workflow, coverage and validation](docs/review-and-paired-capture-2026-10-20.md). Build 29 expanded the source-backed catalog, added reviewed reference images to candidate matching, and enabled missing-estimate refresh when the app opens. Free raw guides run before CardSight auction research. Prices expire from the cache after 24 hours; dated older guides are labeled. Paid OpenAI web search stays disabled. See [matching and estimate changes, tests and limits](docs/matching-and-estimates-2026-10-20.md), [CardSight price research](docs/cardsight-price-research.md), and [hybrid routing](docs/hybrid-routing.md).

A private Linux server can replace the Mac worker. See [server setup and ChatGPT login](docs/server-setup.md). The worker is running on the existing Hostinger VPS with verified ChatGPT login, private Tailscale access and a complete real-card research test. The app is installed on the iPhone 17 Pro and its authenticated, pinned HTTPS connection is verified. Tailscale must stay enabled. Phone-originated scans and the camera focus fix were verified on the physical iPhone.

## Use

### Appearance — build 17 / version 1.1

- Tackle4Loss colors in light and dark mode. Open the connection/settings button in Sammlung → **Darstellung** → **Wie iPhone**, **Hell**, or **Dunkel**. The choice stays saved on this device.
- Camera and full-screen photo inspection keep a dark backdrop in either mode.

### Collector UX — build 14 / version 1.1

- A photo-first collection with a compact three-column gallery, searchable binders, favorites and a separate inbox. Search includes player, team, year, product, card number, location and notes. Price sorting groups currencies instead of comparing dollars with euros.
- Tackle4Loss deep green, cool gray backgrounds, white cards and readable gold status accents across collection, scanning, Chase, Lookout and the Mac companion. No invented portfolio total, trend or rarity score.
- **Scannen** keeps the camera open after each local save. Optional **Auto** captures a stable card once and waits for it to leave the frame before another shot. **Vorderseiten wählen** imports up to 200 front photos, one image at a time. Add a back later or use the separate front/back form.
- Capture, identification and pricing are separate. The Mac runs a short photo-only identification worker alongside the research worker. Known, high-confidence checklist matches can enter their binder before pricing finishes. Uncertain variants remain open. A provisional card has **Preis folgt**, with no price or recommendation presented as verified.
- Upload preparation stays off the main thread. Three local requests run at a time; completed uploads are polled rather than uploaded again. The queue holds 250 active jobs and survives restarts.
- Favorites, storage location and personal notes stay on the phone. A correction starts a new revision and clears the old assessment. Older results cannot overwrite it, and older partial checklists cannot remove already collected slots.
- Tap your card photo for full-screen inspection. Pinch or double-tap to zoom; front/back selection carries into the viewer. VoiceOver also exposes zoom actions.
- Large front/back photo targets, clear required/optional sides and an explicit save button. Retakes keep the existing card. Cancel never submits or replaces photos.
- Readable price, rarity and condition panels. Guide values, sales evidence, exact variants and photo limits retain their distinct meanings.
- Visual collection chooser, custom thresholds, full available rankings, and a searchable Lookout grouped into hunting/found.
- Local display thumbnails use a bounded memory cache. Original photo files are unchanged. Larger text gets adaptive layouts; gallery images remain aligned when metadata differs.

### Topps official chase layer — builds 9–13

- Topps Flagship Football now combines the [official Topps checklist](https://cdn.shopify.com/s/files/1/0662/9749/5709/files/CheckList_26TFOB_VERSION5_1.pdf?v=1786730315) with the sold-card market view.
- The app includes all 693 entries from the chase families highlighted on the [Topps product page](https://www.topps.com/pages/topps-flagship-football): Golden Mirror variations, All Kings, 1957 Rookie Variations, Flagship First autos, Island Ink, Super Bowl Champion and Ring of Honor signatures, and Real One relics.
- Topps opens on **Chase-Karten**, not prices. Filter by **Golden Mirror**, **Autos**, **Relics**, **All Kings**, or **1957 Rookies**, then by **Alle**, **Mit Preis**, or **Preis offen**. **Marktpreise** is a separate view with the dollar thresholds.
- Cards with accepted raw sales are ranked by value. Official cards without a matching sale stay visible under **Preis offen**. They never become $0 and never receive a made-up rank.
- Search works across both groups. An official card can be added to Lookout before it has a sale. Existing sold-card Lookout entries are recognized by exact product and card identity, so the new official ID does not create a duplicate.
- Exact scans remain exact. Every official card without one now uses the matching Topps family artwork, visibly stamped **BEISPIEL**; the detail view says it is not the concrete card. The nine official examples prefetch once and stay in the local reference-image cache.

### Getting started

1. Open **Card Scout Mac** in your Mac's Applications folder.
2. On the iPhone, open Card Scout → the Mac button → **Verbindungscode scannen**. Scan the private QR code and confirm the Mac. Allow local-network access when iOS asks.
3. Open **Scannen**. **Einzeln** captures front and back, then opens comparison. **Stapel** captures front and back, saves the pair, and continues to the next card while recognition runs. Fronts may capture automatically; backs use the shutter. Remove the finished card briefly before presenting the next front. Bulk photo import is front-only and available in Single mode.
4. Each capture is saved locally first. The player and visible details arrive before the market research. Open **Offen** to resolve uncertain cards. Prices, condition facts and their sources remain separate.

Older analyses refresh once after the app connects to the updated Mac. All existing card IDs and photo files stay unchanged. The previous assessment remains accessible while the refresh runs. **Neu bewerten** starts a later refresh without taking new photos. For confirmed cards with identical photos, the Mac reuses its own saved identity/condition and researches only the market. A changed photo or unresolved identity always gets a full analysis.

To replace a photo, open the card → **Foto neu aufnehmen**. Choose **Kamera** or **Fotos** for either side, preview it, then tap **Speichern & neu analysieren**. The card keeps its collection entry and any unchanged photo. **Abbrechen** leaves everything as it was. Saving starts a fresh analysis; the previous condition and value are hidden while it runs. Retakes also save offline and upload when the Mac is reachable again.

The Mac must be awake, logged in and reachable on the same local network. It needs internet access and available Codex usage. Your collection and photos work without it. Queued uploads resume while the app is open or when you reopen it. iOS does not keep this app running indefinitely in the background.

The Mac service starts at login. Closing the small QR-code window does not stop it. Do not share its QR code or pairing link: they grant access to this private companion.

## Collection

- Exact year, product, subset and parallel determine the binder.
- Owned slots use your full-colour photo. Missing slots are grey.
- Duplicate copies count once toward completion. Parallels do not fill base-set slots.
- Search by player, team or number. Filter All / Owned / Missing. Missing cards can be added to Lookout.
- The complete **2025 Donruss Optic Base checklist: 300 entries** is seeded from the [Beckett checklist](https://www.beckett.com/news/2025-donruss-optic-football-cards/).
- Other sets are researched during analysis. Incomplete checklists are explicitly labelled, never presented as complete.
- **2026 Bowman Football** includes separate NFL paper/Chrome and college paper/Chrome prospect checklists: 800 source-backed rows across four families. College licensing stays separate from NFL/NFLPA licensing. Two conflicting NFL paper #68 entries remain quarantined. See [coverage, source and deployment status](docs/bowman-2026.md).
- **Reference-image limitation:** the seeded checklist has names and numbers, not 300 card scans. Missing cards currently use grey numbered placeholders. Where an exact reference scan is verified, the app supports a locally cached greyscale image. No fabricated artwork or guessed image URLs.

The first website card, its front/back, 10 legacy Hot cards and 1 Lookout target have been migrated to the private Mac import. Each paired iPhone downloads its own local copy. The old site is unchanged.

## Product ranking and minimum value — builds 7–10

- **Optic 2025 and Topps Flagship Football 2026 use CardSight's completed eBay auctions** for prices from the last 90 days. The priced feed remains standard unnumbered base and insert versions only. Numbered parallels, variations, graded cards, lots, asking prices and ambiguous listings are excluded from pricing. Build 9 separately keeps Topps' official chase checklist visible with unknown prices. A single sale is labelled **1 Verkauf**; multiple matching sales use the median and show the range and up to five recent evidence links. Item prices exclude shipping.
- The release scan pages through all provider catalog entries without splitting equal-player-name groups (the API otherwise produces duplicates across pages). It requests at most 25 recent auctions per entry. This is a provider-sourced, title-checked sales sample, not independent inspection of every original auction or a complete all-parallel market ranking.
- Verified snapshots on 8 September: **359 priced Optic cards / 902 catalog entries checked**, and **99 priced Topps cards / 3,715 entries checked**. Topps' global catalog includes additional variation records beyond the 2,715 base records counted by its set endpoint. Unpriced or rejected entries do not turn into zero-dollar values.
- Results are sorted by USD sale value, with strict >$50 / >$100 / >$200 / custom filters, stable tied ranks, rank-preserving search and 60-row display batches. Product thresholds persist independently of the owned-card library. Select, Prizm and Topps Chrome retain the existing, clearly labelled **partial raw-guide** selections; guides are not blended into the two sold-price rankings.
- Open **Rangliste** and select a product. Loading or pulling to refresh starts an on-demand Mac job when no fresh result view exists. The app shows progress and errors. No new recurring Codex automation is installed. The analysis queue, owned-card assessments, photos and collection checklists are separate and unchanged by a ranking refresh.
- Provider catalog pages are discarded, not imported into a standalone database. A bounded view of at most 500 priced cards per product (and five recent evidence links each) is cached for 24 hours on the Mac, then purged. If capped, the UI explicitly states the highest 500 results. The iPhone holds these views and listing images in memory, not `library.json`. Original owned photos remain local. Limited free access means a full scan is not an unlimited daily service: the client stops at 600 monthly calls, leaving headroom under the free plan's 750; it also has per-day and per-scan safety limits. No paid plan, retries through quota errors or alternate accounts.
- The fixed-host API client never redirects or exposes the key to the phone, URLs, logs, image hosts or Codex. Remove the Mac key when disconnecting CardSight; cached views are then removed by maintenance. See [integration details](docs/cardsight-integration.md).

### Bundled guide feed and official checklist

- Choose **Donruss Optic 2025**, **Topps Flagship Football 2026**, **Select 2025**, **Prizm 2025**, or **Topps Chrome 2025**. The new **Rangliste** screen sorts every available raw-guide entry, without a ten-card cap. Equal prices share a rank; searching keeps the original rank. Results load in batches of 60 using an explicit next-batch button.
- Minimum filters are **All**, **over USD 50**, **over USD 100**, **over USD 200**, and a custom decimal amount. The comparison is strictly greater than the selected amount, not greater than or equal. Each product retains its own threshold across app restarts. Unknown prices remain in a separate, unranked **Ohne Preis** section and never count as passing a monetary threshold.
- The separate `/v1/chases` feed contains 40 dated guide cards across Optic, Select, Prizm and Topps Chrome, plus 693 unpriced official Topps chase cards. It is not the CardSight ranking endpoint. Build 9 merges it in memory with `/v1/market/{product}`. No CSV subscription is required.
- The four ten-card guide selections are **curated and partial**, ordered by ungraded SportsCardsPro guide values. The Topps list is complete only for the 15 highlighted checklist sections imported in build 9, not every card or parallel in the full product. Every Topps entry links to the official checklist; no generic image is presented as an exact card scan.
- **Hobby** is the box-comparison baseline. Box averages are separate from individual chase odds and are not expected resale returns. Do not apply Hobby contents to retail or Mega boxes. Flagship First Signatures odds explicitly refer to the insert series, not the named player.
- Prices are USD raw **Richtwerte**, excluding shipping; no graded extrapolations, invented sold transactions, or conversion to portfolio value. A source link opens the underlying card page. Values and rankings do not update from the internet on every app refresh.
- The Mac serves `mac/data/chases.json` through authenticated `/v1/chases`. `/v1/ping` advertises its revision. Existing paired phones receive new snapshots without reimporting the legacy library. Pull-to-refresh reloads the latest installed Mac snapshot. No new automation or analysis-policy migration is installed.
- `python3 mac/build_topps_flagship_chases.py --pdf <official-checklist.pdf>` reproduces the Topps snapshot only when the exact verified PDF digest and all expected section counts match.
- Last-good catalog and selection stay on the phone offline. Reference scans cache as they are viewed. Malformed catalogs cannot replace valid snapshots or block card uploads; catalog updates never modify owned cards, analyses, photo paths, or Lookout statuses.

See [chase research](docs/chase-research.md) for selection evidence and update rules.

## Analysis rules

- Identify from front/back plus checklist evidence. Unknown identity or unconfirmed NFL/NFLPA licensing stays in the inbox.
- Raw valuation uses **SportsCardsPro and sold eBay listings**: exact year, set, player, number and variant. At most six targeted valuation searches. PSA is optional graded context only; Beckett remains a checklist source, not a valuation gate.
- [SportsCardsPro](https://www.sportscardspro.com/page/methodology) guide values are algorithmic estimates excluding shipping. A verified ungraded guide can display even when eBay is inaccessible. Its graded extrapolations are not used. Sold rows must include their underlying eBay item link; duplicate items, even across sources or regional eBay domains, are rejected. A page heading does not turn misclassified parallel/lot/damaged listings into exact base-card comps.
- Two or more comparable exact raw sales from the last 90 days produce a median and observed range. Currencies and shipping bases are not mixed. Otherwise prefer a labelled guide; a lone sale or a wider window (up to 365 days) remains explicit. Sources and sale dates are expandable. The collection tiles show the same labelled price, never a made-up portfolio total.
- [PSA Auction Prices](https://www.psacard.com/auctionprices) are graded-card comparisons. They never become the headline price of an ungraded card. Inaccessible prices are not invented or access controls bypassed.
- Guide values, actual sales, original currency, source condition bands, dates and exact/near/proxy matches are separate. Unknown shipping no longer hides an otherwise verified item-only reference; its shipping basis remains visible. Asking prices and unknown accepted offers are not sold prices.
- The existing delivered-EUR value fields still require exact raw sales with known total costs. Labelled guide/item-only references are stored separately and are not a portfolio valuation. Missing data is not zero.
- Condition bullets report clearly visible damage with its location. No obvious damage means only **Keine klaren Schäden sichtbar**, never Mint or PSA 10. Material photo limitations stay in **Foto-Details**. An unusable view explicitly requests a better photo.
- Numbered rarity requires serial evidence. Low search counts or graded populations do not prove a small print run. No invented rarity score, damage discount or numeric grade probability.
- The photo check is not professional grading. No **Grade** recommendation without verified grading economics. Missing price data alone does not mark the card damaged, trigger a general review warning, or justify **Bulk**.
- Corrections can be made inside the app. Changing identity clears the old valuation; it does not silently reuse it for another card.

## Build and install

Requirements: Apple Silicon Mac, macOS 14+, Python 3.11+, Xcode with an iOS 17+ SDK, Codex CLI logged in with ChatGPT, and an Apple signing team for a physical iPhone.

From this directory:

```sh
python3 mac/setup.py --install
python3 mac/build_companion.py
open CardScout.xcodeproj
```

Select your iPhone and run the CardScout scheme. The project is configured for the existing personal signing team. The phone must be unlocked and Developer Mode enabled. This is a local development install, not an App Store or TestFlight release.

Build outside an iCloud-backed Documents folder to avoid Finder metadata breaking code signing:

```sh
xcodebuild -project CardScout.xcodeproj -scheme CardScout \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/card-scout-native-device \
  -allowProvisioningUpdates build
```

The setup selects the newest installed Codex CLI and preserves explicit operator changes. Model route 2 upgrades the app-managed primary to **GPT-6 Luna** after the [same-photo benchmark](docs/luna6-benchmark-2026-10-13.md): **medium** effort and web search disabled for identification, **medium** for confirmed-card market refreshes, and **max** for unresolved full analysis. Existing effort settings are preserved. A material identity, checklist, variant or licensing uncertainty, or an invalid full-analysis response, escalates once to **GPT-5.6 Sol / max**. Missing prices, normal photo caveats, market-only refreshes, worker outages, timeouts and configuration errors do not trigger Sol. The optional `scanReasoningEffort` and `marketReasoningEffort` settings override the two medium defaults. This is the default CLI-only route for fresh installs. The deployed retrieval route uses Luna API Fast with medium effort for scans/research/market refreshes, CardSight free-quota price views, and no automatic Sol or paid-search fallback; see [current routing](docs/hybrid-routing.md).

## Storage and security

- iPhone: `Library/Application Support/CardScout/library.json` and `photos/` in the app sandbox; atomic writes and iOS file protection. Pairing secret in Keychain. Reference images are cached locally.
- Deleting the iPhone app removes its local library. Keep a normal iPhone backup. This build does not yet provide a separate photo-library export or multi-device sync; the Mac's analysis database is not a replacement for a photo backup.
- Mac: `~/Library/Application Support/CardScoutMac/`, owner-only permissions. Durable SQLite queue. TLS on port 8743, private bearer authentication and explicitly pinned certificate. No public tunnel, CORS access or router changes.
- Photos are transferred to the Mac and Codex/OpenAI for analysis. They are not on-device-only AI. Temporary Mac job photos are deleted only after the iPhone has durably saved and acknowledged the result; interrupted acknowledgments retry.
- The original site and private one-way migration backup retain the original uploaded photos. They are not deleted by this migration.
- The worker has read-only filesystem access, shell/tool integrations disabled and no personal API keys in its environment. Web content is evidence, not instructions.
- Worker interruption requeues unfinished work. Duplicate delivery of the same analysis job is safe; mismatched photos for that job ID are rejected. Retakes keep the card ID but receive a new job ID. Superseded jobs are cancelled and their results cannot overwrite newer photos. Original local photo files are preserved.
- The paired certificate currently lasts one year. Renewal or Mac hostname changes require issuing a fresh certificate and re-pairing. There is no automatic remote certificate rotation.
- Do not commit `config.json`, `pairing.txt`, private keys, photos or runtime databases. Runtime data lives outside this source tree.

## Checks

```sh
python3 -m unittest discover -s mac -v
swift test --package-path Core --scratch-path /tmp/card-scout-core-tests
```

See [the build 14 research and verification](docs/collector-upgrade-2026-10-13.md) for current checks, the one-photo timing and device limits. [verification.md](docs/verification.md) records earlier builds. The worker uses the documented [Codex non-interactive command](https://learn.chatgpt.com/docs/non-interactive-mode) and native Apple AVFoundation, Vision, PhotosPicker, Keychain and URLSession APIs.

### Card presentation

Build 15 detects the physical card's four edges on-device, straightens the display
copy and places it on a charcoal/rust-red Card Scout backdrop. Existing captures
also use this presentation in the collection, binder, detail and zoom viewer.
Processing runs on a serial background actor with bounded in-memory thumbnails.
Vision receives a downsampled sRGB raster for consistent camera-color handling;
perspective correction uses the higher-resolution photo. No reliable complete
card boundary means the full photo is shown instead of a guessed crop.

Open the enlarged card and enable **Originalfoto** to inspect the original frame.
Stored originals and the photos sent for identification/condition analysis are
unchanged. This is local presentation processing, with no image-generation service
or additional credentials. Cropping is best with one complete, centred card;
multiple overlapping cards, transparent holders and low-contrast edges can still
require the original view or a better-framed capture.

Validation: 76 Swift core tests (one skipped), signed physical-device build and
installation, and a simulator check using the user's sharp Wirfs scan. The image
showed the corrected full card border on the branded background; the original
photo toggle restored the table/background. Physical-device visual acceptance
of this presentation remains a separate check.

### Easier scanning — build 18

The fixed alignment box is removed. One complete card can be off-centre or
moderately tilted; an outline follows its detected physical edges. Portrait and
landscape cards use the same geometry filter. Small, clipped and square objects
are excluded from automatic capture. The display crop uses this selector too,
so an accepted off-centre card no longer needs to overlap the image centre.

Auto mode defaults on and remembers the user's choice. Capture needs settled
focus/exposure plus 0.45 seconds of stable framing, with tolerance for small hand
movement. Stability is measured against an anchor, so slow continuous movement
cannot accumulate into a false stable detection. One card still produces one
automatic capture until it leaves the frame; autofocus/lens transitions do not
rearm it. The status explicitly asks for that brief removal after saving.

A manual tap queues one photo while focus settles, for at most three seconds;
no alignment/detection match is needed for a manual shot. Leaving the scanner
cancels that pending shot. Focus follows the detected card with throttling; tap
the preview to choose a focus point yourself. Macro-capable lens switching and
quality-prioritized still photos remain enabled.

The camera preview fits the viewport without clipping its edges. Its outline
uses the same aspect-fit transform. Controls sit outside the camera image, and
preview height adapts to available screen height so the shutter stays visible.
This improves framing/capture; it does not establish card identity or change the
server's API/Codex research route.

Validation: 85 Swift tests (one skipped), signed physical-iPhone build/install,
and simulator layout inspection. Tests cover off-centre/tilted/landscape cards,
outer borders, rejection of partial/tiny/square candidates, aspect-fit/fill overlay
coordinates, hand movement, slow drift and duplicate prevention across focus
transitions. A real-camera scan on the updated phone is still the acceptance
check for focus tracking and physical alignment of the outline.

## Collection statistics (iOS build 19)

The Stats tab and the collection's “Dein Clubhaus” shortcut show card/player
counts, rookies, numbered cards, favorites, confirmed duplicate extras, the next
collection milestone, and cumulative scan/import growth over the last 14 days.
This is collection growth, not historical market-value performance.

Purchases are entered manually in EUR by default, with separate categories for
single cards, packs, boxes, supplies, and other expenses. Enter the **full total
paid**, including shipping and fees, for all units together. Quantity never
multiplies that total. Pack/box spending must not be booked again for each card
pulled. Purchases can be edited/removed; single-card purchases can be linked from
the card metadata screen. The ledger lives in the phone's protected library file,
works offline, and is not sent to the research worker or models. Older libraries
without a purchases field remain readable. Failed writes roll back in memory.

Known collection value sums compatible raw-card sold medians or guide ranges
for confirmed identities and displays price coverage and the oldest check date.
Missing prices remain unknown. Similar-card sales provide a separate average
price indicator; those indicators are excluded from known value. Sales are
deduplicated across provider links by eBay item ID where available. Comparison
averages never mix currency, shipping treatment, graded cards, or proxy matches.
Currencies remain separate; there is no invented exchange rate or profit figure.

The price leaderboard links to card details. Special-card selection is explicit:
smallest visible serial-number limit first, then confirmed parallels, inserts,
and rookies. It does not manufacture a rarity score.

Validation: 96 core tests (one skipped), signed iPhone and simulator builds.
Tests cover exact decimal/cents parsing, full-total accounting, currency and
shipping separation, duplicate sale evidence, incomplete/uncertain prices,
numbered-card ranking, scan growth, backward decoding, and ledger persistence.
Simulator checks exercised add/edit and relaunch persistence, empty-price
states, and populated demo valuation/highlight states. Demo fixtures remain in
the separate preview bundle and are never installed as the user's collection.

## Shared identity context catalog

The [context catalog strategy](docs/context-catalog-strategy.md) covers all 34
existing binders across Optic, Flagship and Chrome, plus explicit Select/Prizm
discovery gaps. `mac/context_catalog.py` provides inventory import, incremental
staging, context slices, source-change checks, revision diffs and reviewed local
publication with rollback. The bundled `mac/data/context-catalog.candidate.json`
preserves imported evidence as unverified. It is not wired into production scans;
reference installation, source-format adapters and fact verification remain open.
No catalog update timer or production routing change is installed.

### Scan, compare and collect — build 27

New scans are durable drafts. Compare up to five likely checklist matches, select the exact variant, and add the card to a custom folder. Search, back-photo capture and an unidentified save remain available when none fits. Folder edits under card notes support multiple folders without duplicate ownership or value. Decisions ranks a bounded shortlist after photo extraction; user selection starts the existing condition and exact-card pricing lane. Missing reference artwork is labeled. See [implementation and verification](docs/scan-flow-2026-10-16.md).

Reference photos: build 28 adds 547 reviewed exact-card images across all 35 current binders, source links, full-size comparisons, and labeled same-variant examples. Exact coverage remains partial. See [the reference image report](docs/reference-images-2026-10-16.md).

### Centralized image loading

All dynamic display images use `ImagePipeline` and `StableImage`. The pipeline owns shared requests, background decoding, downsampling, a 48 MiB memory cache and a versioned 256 MiB disk cache. Each visible view retains its image independently of cache eviction; offscreen views release their raster. Source changes and cancelled tasks cannot display an old side or photo. Failures show a retry action instead of reloading on every redraw.

| Surface | Shared presentation |
| --- | --- |
| Collection, inbox, binders, folders, review queues, statistics, card details | `OwnedPhoto` / `LocalCardPhoto` |
| Full-screen viewer, scan comparisons, enlarged scan photos, own-photo comparisons | `LocalCardPhoto` |
| Exact references, missing-card previews, binder covers, reference comparisons | `ReferenceImageView` |
| Chase artwork, representative examples, Lookout | `CachedPhoto` |
| Retake/import previews, captured-photo preview | `StableImage` with a capture revision |

Official references and local display renditions persist, including migration of older cached reference files for offline use. eBay listing images and unsaved capture previews remain memory-only. Original captures and analysis evidence are unchanged. The live camera continues to use its capture-session preview.

Run `python3 scripts/verify_photo_loading.py --device <booted-simulator-UUID>` from this directory. The script audits all view sources for bypasses, then builds an isolated simulator app. Generated photo fixtures and a mocked URL session exercise eviction, request sharing, offline/disk reloads, cache limits, market-image policy, failed downloads, explicit retry, late responses, cancellation, source/preview revisions, real image wrappers, and full-screen zoom retention. The test bundle never connects to the analysis server or downloads real remote images.

### Collection overview, family binders and Collectibles

The collection opens on an overview with card/player counts, a 14-day collection
growth chart, card counts by binder, and a shelf of up to six personally selected
Collectibles. The full showcase is available through its arrow or the Collectibles
filter. All cards, favorites, folders, search and review tools remain available.
Inbox and review actions are grouped under a collapsible section.

Bowman, Donruss and Topps editions share family binders across years. Inside each
binder, year sections contain the original product/type checklists (Base, Chrome,
Optic, parallels and inserts). Other products keep their product name. This is a
presentation group: exact collection IDs, reference images, owned checklist
slots, duplicates and analysis assignments retain their original meaning. Binder
card counts include physical copies, exclude scan drafts, and show only cards
linked to a known collection. Cards without a binder assignment are counted
separately on the overview. Partial checklists remain labeled as partial.

The trophy action in card details or the all-cards context menu adds/removes a
Collectible. This optional flag is saved locally with the card, independently of
favorites; old libraries decode without it. Analysis updates preserve the flag.
No remote services or additional credentials are needed.

Validation (2026-11-07): 162 Swift core tests passed with one existing skip;
Debug simulator build and shared-image source audit passed. In an isolated demo
bundle, checked overview charts, Bowman/Donruss grouping, Base/Chrome drill-down,
checklist-to-detail navigation, the Collectibles filter, trophy add/remove, and
removal persistence after relaunch. Signed Release build 1.1 (41) was then
installed in place and launched on MyApple (iPhone 17 Pro); device inventory
confirmed build 41. Physical-screen acceptance remains open. The optional
pre-install data backup was blocked by automatic approval review, so the phone's
private collection and photos were not copied or compared before/after.

### Sports-card presentation

The overview uses a stadium-inspired green/gold header with real owned-card
photos, a gold-framed Personal Collection showcase, and color-coded family
binders with card fans. Binder interiors keep year/type sections and show larger
photo covers. Stats sit below the showcase and binders in a compact Collection
Pulse section. Press feedback respects Reduce Motion. Decoration is drawn with
SwiftUI; card photos keep the shared image pipeline and original evidence.
The hero can show recent owned cards when no Collectibles are chosen, while the
Personal Collection shelf continues to show only explicitly selected cards.

Motion: overview sections reveal with a short stagger, horizontal showcase cards
use a small scroll-linked 3D tilt, and buttons spring on press. A restrained foil
light sweep runs across the hero and showcase cards. Reduce Motion disables
these transforms and the foil sweep; the sweep also pauses while the app is not
active. No photos are modified by these display effects.

Sports presentation validation (2026-11-07): Debug simulator and signed Release
builds passed, as did the shared-image source audit. Simulator inspection covered
the overview in light/dark appearance, the family covers, Base/Chrome interiors,
and the wider two-column Collectibles layout with readable player names. Build
1.1 (42) installed in place and launched successfully on MyApple; fresh device
inventory confirmed build 42. Physical-device animation smoothness and user
acceptance remain separate checks.

### Value-first collection dashboard (build 43)

The collection and Stats tab now lead with the estimated raw value of priced
owned cards, price coverage and a currency selector. Exact-card sold medians and
exact-card guide ranges contribute to this explicitly partial estimate. Weaker
comparison-card indicators are shown separately and excluded from the headline,
ranking and history. Missing prices never count as zero, currencies stay separate,
and the estimate is not profit or expected net sale proceeds.

The five highest-valued priced cards link to their details. Grade, Keep and Sell
sections expose existing completed recommendations and their reasons. Promotion
requires a confirmed identity, high confidence, no review flag and a nonempty
analysis reason. Grade additionally requires the photo status to show no obvious
damage. This does not predict a grade, calculate grading profit or include fees.

New optional `portfolioHistory` records local derived amounts for owned cards.
Provider payloads/listings/URLs and photo evidence are not copied into history.
Raw transient references still expire and stay out of the saved analyses. A saved
historical amount never becomes a current quote: offline/expired states identify
the last observed value and its date. Collection reset clears history with the
library; old libraries remain readable without this field.

History begins with the first completed observation; no pre-install market trend
is reconstructed from scan dates. Initial price hydration waits for completed
lookups of confirmed cards before recording. Keep an initial and latest snapshot
per UTC day, up to 730 records. Total-history charts include additions, removals
and changes in price coverage. The separate value-change figure compares only
the same physical card IDs, unchanged identities, currency and pricing/shipping
basis against the earliest retained baseline. Range midpoints are labeled;
legacy spans without a comparable basis cannot create a gain. New cards do not
create market appreciation. No external service, model or paid search was added.

Value dashboard validation (2026-11-07): 169 core tests, one existing skip, zero
failures; Debug simulator and signed Release builds passed. Regression checks
cover additions vs gains, currency/identity/shipping separation, range midpoints,
missing/expired prices, snapshot retention/persistence, backward decoding and
explicit grading eligibility. Shared-image source audit passed. Simulator QA
covered the populated value hero and change chart, recommendation-to-detail
navigation, and an unpriced first-day library without fabricated history.
Build 1.1 (43) installed in place and launched on MyApple; device inventory
confirmed build 43. Real-device historical tracking across future sessions and
physical user acceptance remain separate checks.

### Collector clubhouse and Burn Count (build 44)

The current navigation has four connected destinations:

| Destination | Purpose |
| --- | --- |
| Clubhaus | Burn Count, mascot and a small Personal Collection showcase |
| Sammlung | Binders, all cards, Collectibles, favorites, folders and review inbox |
| Scannen | Existing capture/compare/collect flow; returns to Sammlung |
| Insights | Wert (value/history/leaders), Moves (grade/keep/sell), Entdecken (Chase + Lookout) |

Home no longer contains value charts, rankings, full binder lists, filter chips
or recommendation lists. Deep links to market rankings now open from Insights;
Lookout links back to Chase through navigation instead of a removed tab.

Burn Count compares entered card/pack/box costs with the estimated value of the
current collection, per currency. Quantity never multiplies the full paid total;
shipping and fees are included once. Supplies and other expenses stay in the
purchase ledger but do not contribute to Burn Count. Missing purchase records
remain unknown. Incomplete price coverage cannot create a loss figure or an
embarrassed reaction. Overlapping price ranges remain uncertain; above-cost
ranges show zero burn rather than a negative burn/profit claim.

You can enter a personal total estimate from Burn Count details. It is explicitly
labeled, saved locally in optional `burnManualValues`, and used only by Burn
Count. It never changes card analyses, researched rankings or portfolio history.
A changed owned-card ID set invalidates the estimate until it is entered again.
The ledger and estimates persist across app restarts. This remains a playful
hobby comparison, not realized profit/loss or net sale proceeds; older purchases
can include cards no longer owned.

Scout has three original transparent PNG moods: curious, proud and sheepish.
They were generated using built-in `image_gen.imagegen`, checked for real alpha,
and copied into `App/Assets.xcassets/BurnMascot-*.imageset/mascot.png`.
The exact base/edit prompts are in [burn-mascot-prompts.json](docs/burn-mascot-prompts.json).
Gentle floating, tap bounce and mood transitions respect Reduce Motion; floating
pauses when the app is inactive.

Validation: 177 Swift core tests, one existing skip, zero failures; simulator and
signed Release builds passed, and the shared-image audit passed. Isolated demo
UI checks exercised purchase entry, partial-price safety, manual value editing,
proud/sheepish reactions, spending/value persistence after restart, light/dark
Home, Home-to-binder drill-down, Insights Wert/Moves/Entdecken, and Lookout-to-Chase
navigation. No real purchase, external sale or grading submission was performed.

Build 1.1 (44) was installed in place and launched on MyApple on 2026-11-07;
fresh device inventory confirmed build 44. Physical-screen acceptance and real
camera capture on this build remain user/device checks. The spending and manual
estimate demo entries were made only in the isolated simulator bundle.

### German / English and concise copy (build 45)

Language defaults to the iPhone's preferred supported language (German or English;
English fallback). Settings → Sprache / Language offers iPhone, Deutsch and English.
The override is stored locally and updates open screens and sheets immediately,
without replacing the app store, navigation, filters or purchase form state.
UI dates, amounts, accessibility labels and permission descriptions have localized
presentation. Card names, folder names, entered notes and research prose remain
as supplied; language changes never rewrite collection records or evidence.

Home now leads with Burn Count, numbers and Scout. Slogans, mood narration,
duplicate shortcuts, decorative headings and arbitrary PC row numbers are gone.
Repeated helper paragraphs were shortened across collection, capture, matching,
identity review, Insights, purchases and Settings. Recommendation reasons are
expandable in card details. Price uncertainty, partial coverage, identity warnings
and accounting notes remain where they affect a decision.

`App/de.lproj` and `App/en.lproj` contain matching Localizable/InfoPlist resources.
`ScoutText` separates interpolation values from stable translation keys; known
core-generated display labels use the bounded `LocalizableTemplates.json` list.
AppLanguage refreshes UI dependencies while preserving screen state. Persisted
state/filter tokens and backend contracts remain language-independent.
Run `python3 scripts/verify_localization.py` to check both resource key sets,
placeholder safety and presentation-literal coverage before adding UI copy.

Validation: 181 Swift tests, one existing skip, zero failures; 819 bilingual
entries and 98 dynamic label templates passed the localization audit. Debug
simulator and signed Release builds passed, as did the shared-image source audit.
Simulator checks covered the English iPhone default, live English→German switching
without closing Settings, German Home, persisted German preference after relaunch,
and switching explicitly back to English. Spending and manual card value were
retained through the switches and relaunch.

Build 1.1 (45) installed in place and launched on MyApple on 2026-11-07;
fresh device inventory confirmed build 45. Physical-device acceptance remains a
user check; live language-switch and relaunch-persistence QA used the isolated
simulator app. No phone collection, purchase, history or pairing data was copied
for this update.

### Clubhouse identity (build 46)

Home now opens with a compact Burn Count wordmark, a mascot-derived flame-and-card logo,
and one localized line: “Your cards. Your clubhouse.” Burn Count uses a prominent
rounded headline and more readable metric labels. The showcase heading has a
matching trophy badge. Existing Home content, accounting, mascot motion and
collection navigation stay intact. No additional dashboard panels were added.

The direction takes inspiration from Sleeper's sports-club presentation and clear
section hierarchy while retaining Card Scout's own palette and assets.

The flame-and-card mark is generated from the proud Burn Scout mascot reference:
orange flame head, simple eyes, cream/gold card and the green jersey lightning
bolt. It replaces the old AppIcon and appears in the Home identity header.
The original full-body mood mascots remain on Burn Count. The 1024px iOS icon
is opaque, with square canvas corners for the system mask. The built-in image_gen
prompt is preserved in `docs/flame-logo-prompt.txt`; the full-resolution in-app
asset is `App/Assets.xcassets/ScoutFlameLogo.imageset/logo.png`.

The user-facing app name is now **Burn Count**, in both localizations, the Home
wordmark and the iPhone display name. Existing bundle ID, keychain service,
local storage directory and pairing URL scheme are retained so the update opens
the same installed collection and connection. Internal Swift target/package
names remain stable. No storage migration or collection rewrite is required.

Validation for build 46: Debug simulator and signed Release builds passed;
820 bilingual keys and 98 dynamic templates passed the localization audit.
The shared-image source audit passed. Final English and German Home layouts
were visually checked in the isolated simulator with the new logo and name.
The app icon is 1024×1024 with no alpha. After one device-tunnel timeout, the
in-place installation succeeded. Burn Count 1.1 (46) launched on MyApple;
fresh device inventory confirmed the display name and build. Physical-screen
acceptance and collection-content checks on the phone remain user checks.

### Signed Burn Count and result styling (build 47)

Burn Count is now paid minus estimated card value, including negative numbers
when the collection is worth more than its recorded card/pack/box spending.
Ranges retain both signed endpoints, including when their upper endpoint is zero.
The formula appears on Home. Complete price coverage or a current manual estimate
is still required: unknown card prices never become zero. Missing spending/value
is explained compactly; when value is incomplete, the main action opens the manual
value editor. The displayed value also has a pencil action for direct editing.

The headline is green for gains, gold for break-even/overlapping ranges, orange
for losses, and coral red for a heavy burn. A conservative gain of at least 25%
of spending gets heavier italic type, a soft green glow and a sparkle; a minimum
loss of 25% gets heavier red type. Incomplete comparisons remain neutral. Mood
and result descriptions have accessible localized labels; colors do not carry
meaning alone. Percentage thresholds require the full value range to qualify.

Build 47 validation: 183 Swift tests, one existing skip, zero failures;
833 bilingual entries and 98 dynamic templates passed the localization audit.
Final simulator and signed Release builds passed. The isolated preview showed
€3,000 paid versus €4,000 estimated value as a green −€1,000 result, with the
amount and sign kept together. Threshold/range cases were covered by core tests.
Installed in place on MyApple; fresh device inventory confirmed Burn Count
1.1 (47). Automatic phone launch was denied because the device was locked;
physical-device visual and collection-content acceptance remain user checks.
