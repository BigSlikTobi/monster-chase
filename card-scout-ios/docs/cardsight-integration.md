# CardSight integration — build 7

## Boundary

This is an on-demand sale-ranking view for two licensed products. It is **not** a permanent CardSight checklist mirror, a complete all-parallel ranking, or a replacement for the owned-card analysis workflow. The three other products retain their existing partial guide rankings. No owned cards are automatically revalued by this change.

Official contracts: [API documentation](https://api.cardsight.ai/documentation), [OpenAPI](https://api.cardsight.ai/documentation/json), [terms](https://cardsight.ai/terms), [free plan](https://cardsight.ai/pricing). Terms were read on 8 September (updated 26 August). Implementation uses bounded, expiring app-result caching, not a wholesale database download. Any later bulk export, durable provider checklist or broader reuse needs a separate terms check.

## Flow

1. The iPhone requests authenticated `GET /v1/market/{product}` from its certificate-pinned Mac.
2. If empty, `POST` to the same route starts an idempotent, serialized job outside the analysis worker. Concurrent viewers share the job. No API calls are made by simply polling status.
3. The Mac checks subscription usage, reads the release's set/parallel names, then streams catalog pages and raw, base-only, 90-day auction requests (up to 100 card IDs, 25 records each).
4. Equal-name groups stay on one page. The API's name sort lacks a stable tie-breaker; ordinary offset=100 paging demonstrably duplicated and missed Topps records. Incomplete pages/changed counts/mismatched response IDs fail closed.
5. Title checks require the player, year, card number, product and insert. Alternate insert names, parallel names/colors/serials, grading, lots, READ/condition flags, non-auctions, unsafe links, old/future records and duplicates are excluded. Generic `Football` inside the full Topps product title is not confused with its `Football` parallel; a repeated variant word remains detectable. A player's `Golden` surname cannot hide a Golden parallel.
6. Publish the highest 500 priced results at most, with explicit cap metadata. Single sales stay explicit. Source URLs and shipping basis are visible. The phone validates the complete response before using it and does not persist it in the owned library.

## Limits and retention

- Key: existing owner-only `cardsight-api-key` in private Mac Application Support. Never embedded in app/source, never sent to OpenAI or image hosts.
- Fixed HTTPS host, normal certificate verification, no redirects, no automatic retry. 401/402/403/429 stop further requests for 24 hours.
- Conservative durable ledger counts requests **before** sending, including failures, and checks provider usage without exposing the subscription endpoint's echoed key. Hard limits: 720/month (updated at the user’s request on 16 October 2026), 270/day, 140/scan. No subscription changes or automatic paid fallback.
- Temporary output: `market-cache/{known-product-id}.json`, 24-hour TTL, at most 500 cards with five evidence links each. No full catalog or rejected-record archive. Maintenance purges expired data even with no phone connected; removing the key also purges these result views.
- iPhone views/listing images are memory-only. Existing owned photos remain in protected local storage. User-selected Lookout targets remain user-authored saved selections, not a mirrored catalog.
- A local `Library/Caches/cardscout-market-view.json` delivery receipt stores only build, product ID, revision, counts and timestamp. No photos, names, prices, searches or credentials; nothing is transmitted to a telemetry service.
- Code installation preserves an existing live guide feed, pairing, model and analysis policy. No migration or deletion of the user's collection.

## Reproduction

```sh
python3 -m unittest discover -s mac -p 'test_*.py'
swift test --package-path Core
python3 mac/setup.py --install
```

Developer-only explicit refresh (still within all free limits):

```sh
python3 mac/cardsight.py --data '/Users/tobiaslatta/Library/Application Support/CardScoutMac' --refresh all
```

`--force` rebuilds a selected temporary result view for a matcher repair. It does not bypass quota limits. Normal app refreshes reuse the fresh view. The native link `cardscout://ranking/2025-panini-donruss-optic` opens the Optic ranking; the other accepted product is `2026-topps-flagship-football`. Unknown products, extra query parameters or credentials are rejected.

## Known limits

This does not promise every card has a value. Most Topps matches currently have only one recorded sale. A title match cannot establish physical condition or verify that every original auction was paid. At most 25 recent API records are sampled per card, not an exhaustive transaction history. Generic unnamed parallels remain dependent on accurate seller descriptions. Numbered parallels and ambiguous variants are deliberately not ranked. Saved owned-card valuations may have different dates or a different evidence basis; they are not overwritten with catalog medians.
