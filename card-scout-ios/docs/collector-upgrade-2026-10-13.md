# Collector upgrade — 13 October 2026

Build 14, version 1.1. Scope: the native iPhone app and its Mac companion.

## Problem and change

The previous queue made one Codex worker identify a card, resolve its checklist and research the market before starting another card. The photo form also closed between cards. This made a stack of 100 cards feel like 100 separate research tasks.

The new flow is **capture → local save → short identification → background research**. A dedicated camera tab remains open after saving. Optional automatic capture requires a stable rectangle for 0.7 seconds and waits for the card to leave for 0.55 seconds before rearming. Those are trigger settings, not measured physical-device throughput.

The photo picker supports 200 fronts. It reads, normalizes, performs fast on-device OCR and saves one image at a time. Camera and image work run off the main thread. New capture uploads use a consistent 1,800-pixel JPEG derivative; local originals stay intact. Uploads and status requests run three at a time. Saved upload IDs avoid repeated photo transfers.

The Mac has two independent workers. Identification uses the existing primary model, medium effort by default, no web search and a 180-second limit. Market research can take longer without blocking the next identification. Only an exact local-checklist match with high confidence and acceptable licensing is assigned automatically. Unknown year, number, variant or licensing stays open. Fast identification provides visible condition facts, not professional grades.

Provisional results contain no prices. The UI hides their placeholder recommendation. Confirmed cards reuse the saved identity and condition for market-only research. Unresolved cards retain full research and the existing material-uncertainty fallback. The queue is bounded at 250 active jobs. Retry, cancellation and restart preserve photo revisions and provisional results.

The collection now starts with photos, rather than a dashboard of decorative panels. It has search, favorites, open cards, binders, storage locations and notes. Paper backgrounds, ink text, a small red accent and simple rows replace the previous dark/lime treatment. Prices remain evidence-backed and show their original currency; sorting groups currencies. The Mac shows local waiting, analysis, price and failed-job counts.

## Research and design choices

These are product lessons inferred from the source material, not claims that this app now matches a competitor's accuracy or throughput.

| Source | Lesson applied |
| --- | --- |
| [Card Dealer Pro](https://www.carddealerpro.com/) | Design around a stack of cards: capture and documentation should form a repeatable workflow. |
| [CollX FAQ](https://www.collx.app/faq) | A visual match and an exact variant are different decisions. Keep uncertainty visible. |
| [CollX Pro](https://www.collx.app/collx-pro) | Location matters for a real collection. Add searchable storage and notes. |
| [Codex non-interactive mode](https://learn.chatgpt.com/docs/non-interactive-mode), [configuration reference](https://developers.openai.com/codex/config-reference/) | Use a narrow output contract and separate reasoning/web settings for identification and research. |

The implementation keeps native Apple camera, PhotosPicker and Vision APIs. It introduces no new image generation, provider, API key, subscription or public service.

## Verification

- Mac Python suite: 97 tests pass. Coverage includes 100 durable/idempotent jobs, an independent identity worker while pricing is blocked, restart recovery, cancellation, fallback, locked manual assignments and partial-checklist merging.
- Swift core suite: 73 tests, 72 pass and one optional live-provider-cache check is skipped. Coverage includes 100 offline captures surviving reload, batch rollback, stale-result rejection, partial-checklist races, automatic capture gating, metadata preservation and existing ranking/retake rules.
- iPhone simulator Debug build and signed iPhone Release build compile. Mac companion compiles for Apple Silicon/macOS 14. Final build paths are in `/private/tmp/nfl-monster-chase-build14-xcode` and `/private/tmp/nfl-monster-chase-build14-device`.
- The isolated `.preview` app has a labeled 100-record layout fixture. Its card-shaped drawings are explicitly marked as design demos, contain no real card photos or invented prices, and cannot seed the production bundle. Gallery navigation and favorite filtering were checked in the simulator. Storage/notes text entry was checked; full persistence is covered by the core save/reload test.
- One existing **front photo only** was tested with the user's explicit approval through their existing ChatGPT-authenticated Codex CLI. No local checklist/catalog metadata was included in that benchmark. It completed in **10.8 seconds** using `gpt-5.6-luna` at medium effort, read **Daunte Culpepper / Donruss Optic**, and returned medium confidence with unknown year and number. It produced zero price references. The temporary photo and output directory were deleted. The collection was not changed by the test.

This single timing is not a 100-card throughput benchmark, a before/after comparison or proof of a 10× speedup. Full pricing latency remains dependent on external research. Automatic camera quality, blur, lighting and real-stack capture speed still need an unlocked physical iPhone and a collector test.

## Local rollout

Follow-up: the primary is now GPT-6 Luna at the existing effort levels after the user-authorized [same-photo benchmark](luna6-benchmark-2026-10-13.md). The final paired median was 6.72 s versus 12.03 s for GPT-5.6 Luna. This model update needs no new iPhone build.

The existing Mac service was updated and its stale Codex executable path repaired. A private backup was saved under `~/Library/Application Support/CardScoutMac/upgrade-backups/2026-10-13-build14/`. Before the update there were 212 completed jobs, eight failed jobs and one cancelled job, with no active photo jobs. A post-update database comparison confirms every existing job ID, digest, status, result, error and acknowledgement is unchanged. The local TLS endpoint advertises fast-pipeline version 1 and capacity 250, and installed worker files match the workspace. Failed jobs are not retried automatically. Pairing token/link and certificate/key remain unchanged.

The Mac UI is version 1.1/build 14. The signed phone update is prepared. At the device check, `MyApple` was paired but locked, so the developer image could not mount. The existing app was not uninstalled or reset. Unlocking is required for installation and physical camera checks.

The user deferred phone installation. The verified signed app is saved at `build-device/build14/CardScout.app`, with [installation notes](../build-device/build14/INSTALL.md). This directory is already excluded by `.gitignore`. Its development profile expires on 22 May 2027 at 13:41 CEST.

To build again:

```sh
python3 -m unittest discover -s mac
swift test --package-path Core --scratch-path /tmp/card-scout-core-tests
python3 mac/setup.py --install
python3 mac/build_companion.py
xcodebuild -project CardScout.xcodeproj -scheme CardScout \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath /tmp/card-scout-build14 -allowProvisioningUpdates build
```

For a layout-only preview, build Debug with `PRODUCT_BUNDLE_IDENTIFIER=com.tobiaslatta.cardscout.preview` and launch it with `--collector-preview`. Preview data stays in that separate simulator app container.
