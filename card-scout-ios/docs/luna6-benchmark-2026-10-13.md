# GPT-6 Luna benchmark and rollout — 13 October 2026

The user authorized testing GPT-6 Luna on the same previously approved front photo and switching the app if it was faster without losing accuracy on that test. The destination remains the existing ChatGPT-authenticated Codex worker. No API key or provider was added.

## Test and decision

The final comparison used three sequential runs per model, alternating GPT-5.6 Luna and GPT-6 Luna. Both used **medium** effort, the same front JPEG, the same clarified prompt, the same JSON contract, no OCR hints, an empty known-product list and disabled web search. No back photo or local catalog/collection metadata was sent. There were 13 calls on this one photo across exploratory and final comparisons; the final six are reported below.

| Model | Final runs, seconds | Median |
| --- | --- | --- |
| GPT-5.6 Luna / medium | 16.58, 9.05, 12.03 | 12.03 s |
| GPT-6 Luna / medium | 6.72, 10.06, 6.13 | 6.72 s |

The observed median latency fell **44.1%**. The earlier 10.8-second GPT-5.6 timing remains a historical single-run baseline; it is not substituted for the fresh comparison.

Manual photo inspection confirms the visible player name, Donruss Optic product logo and Dolphins team. Both final pipelines returned **Daunte Culpepper / Donruss Optic / Miami Dolphins** in all three runs. The app uses **Panini** as Donruss Optic's manufacturer key. Both models sometimes returned the printed brand, Donruss, instead. A narrow, deterministic manufacturer-alias normalization now handles that exact product in both identification and full analysis. It leaves historical non-Optic Donruss products alone and cannot promote confidence or fill missing identity fields.

GPT-6 Luna left the unreadable year, card number and serial number null in every final run. It retained low/medium confidence and a provisional result; it never filled a binder, invented prices, asserted mint condition or assigned a numeric grade. Its visible-damage lists stayed empty and its final photo limits correctly described blur, glare and the missing back. The old model inconsistently inferred 2016 or 2021; neither year is verified by this front-photo test.

Exploratory output exposed two issues: a low-effort probe returned the Donruss manufacturer alias, and medium output repeatedly described the complete physical card as cropped. The prompt now distinguishes the printed player's framing from the physical card's outside edges and explicitly requests German free text. The final paired comparison uses those same instructions for both models. Medium is the only effort level accepted for rollout; this test does not justify lowering it to low.

This is a repeatability and readable-identity check on **one photo**, with manual inspection and deterministic validation. It is not a population accuracy score or a 100-card throughput test. Pricing accuracy/latency and difficult variants were not benchmarked. Repeating an image may benefit from caching, and individual request latency varies. The observed gate passed for this specific sample and configuration.

## Route and safeguards

- Primary: `gpt-6-luna`.
- Identification: medium effort, no web search, 180-second deadline.
- Confirmed-card pricing refresh: medium effort.
- Unresolved full analysis: the existing max effort is preserved.
- Difficult identities, checklists, variants, licensing or invalid full-analysis responses: one fallback to the existing `gpt-5.6-sol` at max effort.
- Missing prices, price-only refreshes, worker outages/timeouts and configuration errors do not escalate to Sol. Retry keeps the durable queue and provisional result.
- App-managed route 1 advances to route 2. Explicit custom routes and stage-effort settings remain intact. No endpoint, output schema or iPhone binary change is required.

These choices preserve supported reasoning settings and the two models' roles. [Official OpenAI migration guidance](https://developers.openai.com/api/docs/guides/latest-model#gpt-6-astra-update-api-and-model-parameters)

## Verification and local update

The Mac regression suite passes **103 tests**, including managed-route migration/idempotency, custom-route preservation, manufacturer aliases, no confidence promotion, difficult-card escalation and no Sol calls for worker/configuration failures. The earlier Swift core and signed build checks remain applicable; Swift source and the saved build 14 were not changed for this migration.

The installed Mac worker and configuration are updated after a private backup under `~/Library/Application Support/CardScoutMac/upgrade-backups/2026-10-13-luna6/`. The service is restarted with the new primary. Pairing, certificates, catalogs and all existing job results are checked against the backup. Failed jobs are not retried automatically.

The temporary front photo, raw comparisons, schema, results and worker logs are deleted after verification. The collection stays unchanged. The user-deferred iPhone installation remains deferred; its saved build already works with this Mac route.
