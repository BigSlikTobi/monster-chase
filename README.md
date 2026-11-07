# Monster Chase · Card Scout

A photo-first football trading-card collector app. Scan a card, check its exact identity, keep track of your collection, and research comparable sales.

The main product is **Card Scout for iPhone**, backed by a private Mac or Linux research worker. This repo also contains the earlier web prototype.

> **Release status:** development source. Local device installs and historical deployment checks do not mean the app is publicly available on the App Store. Publishing this repo does not deploy the app or its worker.

## What it does

- **Capture front and back.** Single-card and batch workflows, photo imports, retakes, and local saves.
- **Identify the actual card.** Player, year, product, subset, card number, parallel, serial evidence, and licensing matter. Uncertain matches stay open for review.
- **Organize the collection.** Photo galleries, binders, checklists, favorites, notes, storage locations, search, and duplicate-aware completion.
- **Research value.** Exact-card sales, guide prices, and broader comparison estimates have separate meanings. Comparison headlines use a median with an observed range where available.
- **Find chase cards.** Product rankings, official chase checklists, and a Lookout list for missing targets.
- **Inspect photos and references.** Zoomable images and source-backed reference matching. Unknown reference images are not invented.
- **Use German or English.** Native strings and dynamic labels have a localization audit.

Card identity takes priority over an attractive price. Missing evidence is not a zero-dollar card, a verified sale, or a professional grade.

## Repository map

| Path | Purpose |
| --- | --- |
| [`card-scout-ios/App`](card-scout-ios/App) | SwiftUI app, capture, collection, image loading, pairing, and local persistence |
| [`card-scout-ios/Core`](card-scout-ios/Core) | Swift package with shared models, collection rules, pricing logic, and tests |
| [`card-scout-ios/mac`](card-scout-ios/mac) | Python research worker, Mac companion, provider adapters, catalogs, and tests |
| [`card-scout-ios/server`](card-scout-ios/server) | Private Linux worker installers and systemd service |
| [`card-scout-ios/scripts`](card-scout-ios/scripts) | Localization, photo-loading, and collection-preservation checks |
| [`card-scout-ios/docs`](card-scout-ios/docs) | Design notes, source research, operational history, and verification reports |
| [`card-scout-app`](card-scout-app) | Earlier React web prototype with Cloudflare D1/R2 storage |
| [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) | Contributor and coding-agent instructions |

## How the native app works

```text
                         Private paired HTTPS
 iPhone app  ------------------------------------------>  Mac / Linux worker
     |                                                         |
     |                                                         +-- Identification and research
     +-- Local collection and original photos                  +-- Checklist / reference matching
     +-- Offline capture and queued uploads                    +-- Market-source adapters
     +-- Review and display                                    +-- Durable analysis queue
```

The iPhone owns its local library and original photos. The worker processes queued analysis and market jobs. It is **not** a replacement for a collection backup or multi-device sync.

Photos leave the phone for remote analysis. Worker access uses private pairing, bearer authentication, HTTPS, and certificate pinning. Keep the worker on a trusted private network; review the server guide before installing it.

## Native development

### Requirements

- An Apple Silicon Mac with macOS 14 or newer.
- Xcode with an iOS 17+ SDK and a Swift 6-compatible toolchain.
- Python 3.11 or newer.
- A configured research route. The Mac setup supports a locally authenticated Codex CLI; other routes have their own provider and credential requirements.
- An Apple signing team for physical-device installation.

### Open and build

```sh
git clone https://github.com/BigSlikTobi/monster-chase.git
cd monster-chase/card-scout-ios
open CardScout.xcodeproj
```

Choose the **CardScout** scheme. Set your own signing team and bundle identifier before installing on a device. The checked-in project includes the original development configuration.

For a simulator build without signing:

```sh
xcodebuild -project CardScout.xcodeproj -scheme CardScout \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/card-scout-simulator \
  CODE_SIGNING_ALLOWED=NO build
```

### Set up a private worker

For the Mac companion, from `card-scout-ios`:

```sh
python3 mac/setup.py --install
python3 mac/build_companion.py
```

The setup installs local worker components. Read the [native guide](card-scout-ios/README.md) before running it. Pair the app with the companion's private QR code. Do not publish that code or pairing URL.

For Linux, use the [private server guide](card-scout-ios/docs/server-setup.md). Inspect installers before running them on a shared server. Pairing, network access, authentication, and provider availability need separate verification on your own setup.

### Run checks

From `card-scout-ios`:

```sh
python3 -m unittest discover -s mac -v
swift test --package-path Core --scratch-path /tmp/card-scout-core-tests
python3 scripts/verify_localization.py
```

The photo regression check needs a booted simulator:

```sh
python3 scripts/verify_photo_loading.py --device <SIMULATOR_UUID>
```

For changes that could affect stored collections, compare private before/after backups:

```sh
node scripts/verify_collection_preservation.mjs <BEFORE_BACKUP> <AFTER_BACKUP>
```

Keep those backups outside the repo. A passing unit test does not establish physical-camera behavior, market accuracy, or App Store readiness.

## Web prototype

The web app uses React 19, TypeScript, vinext/Vite, Tailwind, Drizzle, and Cloudflare Workers storage bindings.

```sh
cd card-scout-app
npm ci
npm run dev
```

Use Node **22.13+**. The app expects a D1 database binding named `DB` and an R2 bucket binding named `FILES`. Configure them for your own environment and apply the SQL migrations in `drizzle/`. The checked-in `.openai/hosting.json` describes the original hosting project; it does not grant access to its resources.

```sh
npm run lint
npm run build
```

The prototype includes card, Hot 10, and Lookout endpoints. Its analysis integration depends on the original tool/hosting environment. A local web server alone does not provide a complete recognition service. Review access controls before exposing it to other users.

## Pricing and data rules

- Match year, product family, card number, variant, and condition before treating a sale as an exact comp.
- Keep raw and graded cards, asking and sold prices, individual cards and lots, and different currencies separate.
- Show provenance and uncertainty. Guide values and broader estimates are not confirmed exact-card sales.
- Unknown prices remain unknown. Do not invent portfolio totals, rarity scores, or grade probabilities.
- Provider data can be incomplete, stale, quota-limited, or unavailable. Historical verification reports are not current uptime guarantees.
- Bundled catalog data and reference metadata support matching. They are not a complete durable market database with periodic price refresh.

See [matching and estimates](card-scout-ios/docs/matching-and-estimates-2026-10-20.md), [median pricing](card-scout-ios/docs/median-pricing-2026-11-06.md), [CardSight integration](card-scout-ios/docs/cardsight-integration.md), and [reference images](card-scout-ios/docs/reference-images-2026-10-16.md).

## Import verification

The initial repository import passed 253 Python worker tests, the Swift suite (188 tests, one skipped, no failures), the web production build, and the localization audit (842 bilingual keys and 98 dynamic templates). The web lint check reports 19 existing errors in shared UI components and hooks, including accessibility, React effect, and template-expression rules. They remain open; the import does not change application behavior.

## Secrets, storage, and backups

Never commit API keys, authentication files, pairing links, private certificates, original collection photos, app-data exports, or runtime databases. Root and component ignore files exclude common local artifacts; inspect every staged change before pushing.

The native app stores its collection in its sandbox. The Mac worker normally stores runtime state under `~/Library/Application Support/CardScoutMac/`; Linux uses its configured private data directory. Deleting the app can remove its local collection. Keep device backups and verify recovery separately.

Operational docs describe past installs and may include machine-specific paths or configuration. Adapt them to your environment. Do not paste private runtime files into issues or pull requests.

## Contributing

Read [`AGENTS.md`](AGENTS.md) first. Keep changes focused, preserve saved cards and photos, and run checks for the code you change. Use Conventional Commits. Report what you verified and which device or deployment checks remain open.

No project license is granted by this README. Third-party names, card artwork, checklists, and provider data retain their respective rights and terms.
