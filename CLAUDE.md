# Claude instructions

Read and follow [AGENTS.md](AGENTS.md). It is the shared source for working style, UI copy, product rules, data preservation, security, and verification. These rules apply to every change in this repo.

## Start here

1. Read [README.md](README.md) for the project map and setup.
2. For native work, read [card-scout-ios/README.md](card-scout-ios/README.md) and the relevant design or verification note in `card-scout-ios/docs/`.
3. Inspect the current code and Git diff. Treat historical deployment reports as history until verified.

## Code map

- `card-scout-ios/App/`: SwiftUI screens, camera, persistence, shared image pipeline, and paired worker client.
- `card-scout-ios/Core/`: Swift package and unit tests.
- `card-scout-ios/mac/`: Python worker, provider adapters, source-backed catalogs, companion tools, and tests.
- `card-scout-ios/server/`: private Linux deployment tools.
- `card-scout-ios/scripts/`: localization, image regression, and collection-preservation checks.
- `card-scout-app/`: earlier React/vinext web prototype with Cloudflare D1 and R2.

## Finish work

Keep the user's cards and photos safe. Keep credentials and runtime data outside Git. Run the checks listed in AGENTS.md that cover the change. State what changed, what passed, and what still needs verification. Be direct and brief.
