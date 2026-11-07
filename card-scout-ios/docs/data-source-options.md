# Card ranking without a USD 49/month CSV subscription

**16 October 2026 VPS update:** The [new real-card source pilot](free-source-pilot-2026-10-16.md)
verified CardSight's free-quota pricing API on three exact Chrome base cards.
CardPricer's anonymous API now returns HTTP 200, superseding the historical
September outage below, but had no exact base-card matches in this sample.

Initial research: 8 September 2026. The public-source assessment below predates the authenticated pilot.

**Current update:** The user approved implementation after the pilot. Build 7 adds a Mac-backed, filtered CardSight ranking for Optic 2025 and Topps Flagship Football 2026. It checks titles/variants, keeps sold prices separate from guides, and caches bounded result views for 24 hours. No paid CSV, new subscription or recurring automation. See [integration](cardsight-integration.md), [original pilot findings](cardsight-pilot-2026-09-08.md), and [device verification](verification.md). The original research below is historical.

## Original recommendation

Evaluate **CardSight AI's free tier** using a small, read-only pilot before committing to an integration. Keep independently sourced checklists separate from provider price observations. This is a promising candidate, not a verified full-price replacement yet.

The current app can sort larger catalogs, but its installed reference feed still contains the old ten candidates per product. Changing filters cannot supply the missing data.

## Findings

| Route | Verified finding | Decision |
| --- | --- | --- |
| CardSight AI | Published free plan includes 750 calls/month, catalog and pricing access, and needs no credit card. Public API health returned HTTP 200/healthy. Its live specification supports multi-card queries. | Best candidate for a zero-cost pilot. Actual set and sales coverage require an authenticated test. |
| CardPricer | Documents an anonymous public API. Live requests for Optic 2025, Topps 2026 and service status all returned HTTP 402 with `DEPLOYMENT_DISABLED`. | Not usable in this test. This is a service availability result, not evidence the user must buy access. |
| eBay directly | Sold-market Marketplace Insights access is restricted. Public Browse access is not a replacement for sold prices. | Do not build around an assumed freely available sold-data API. |
| HobbyCardIndex | Its free/personal plans advertise collection exports; the roadmap separately advertises enterprise API/bulk data. A low-cost full-data entitlement was not established. | Do not send the user to another signup expecting a full CSV. |
| Card Hedge | Developer plans start at USD 49/month; the cheaper collector plan is not the developer API. | Rejected for this budget. |

Sources: [CardSight pricing](https://cardsight.ai/pricing), [CardSight live specification](https://api.cardsight.ai/documentation/json), [CardPricer API documentation](https://cardpricer.co/docs/api), [eBay Marketplace Insights availability](https://edp.ebay.com/api-docs/buy/marketplace-insights/resources/methods), [HobbyCardIndex plans](https://hobbycardindex.com/welcome), [HobbyCardIndex roadmap](https://hobbycardindex.com/roadmap/), [Card Hedge developer plans](https://ai.cardhedger.com/signup?target=developer).

## Important CardSight details

- Its specification allows **up to 100 card IDs in one price request**. Catalog pages allow up to 100 entries. Do not equate 750 calls with a verified number of complete card valuations: pagination, variant coverage and additional history queries consume work too.
- Responses separate raw from graded records and identify parallels. The pricing endpoint mixes two concepts unless explicitly filtered: `auction` means completed auction sales; `fixed` means asking prices, not proven sales.
- Individual records can lack dates or original URLs. A successful API response is not enough to qualify a sale. Returned history is capped and may carry truncation warnings.
- The provider says it added 2026 Topps Flagship Football shortly after release. This is a vendor statement, not our independent verification of checklist completeness or useful price coverage. Optic coverage has not been authenticated and tested either.

Sources: [Live API schema](https://api.cardsight.ai/documentation/json), [provider SDK](https://github.com/CardSightAI/cardsightai-sdk-node), [company announcement, 27 August 2026](https://www.einpresswire.com/article/937551984/cardsight-ai-joins-northeastern-university-s-roux-institute-to-build-the-trading-card-industry-s-infrastructure).

## Storage is a real constraint

CardSight's published terms prohibit building an independent standalone catalog from its data. They allow limited, short-term caching under conditions, including refresh/purge and deletion at the end of access. Therefore **do not download their database and retain it indefinitely**. The scope of any whole-product cache must be resolved before implementing it; a free tier does not waive these restrictions.

Permanent checklist identities should come from independent product documents. Topps offers its Flagship checklist and odds directly; the existing Optic base checklist has 300 entries, but does not by itself cover every insert and parallel. Preserve independent source lineage. If the intended cache is not clearly permitted, require provider confirmation or use another price source.

Sources: [CardSight terms, sections 3.b–3.c](https://cardsight.ai/terms), [official Topps Flagship downloads](https://www.topps.com/pages/topps-flagship-football), [Optic checklist](https://www.beckett.com/news/2025-donruss-optic-football-cards/).

## Proposed free pilot and acceptance checks

1. Obtain a user-authorized **free** CardSight API key and configure it locally on the Mac. Do not put it in chat, source control or the iPhone bundle. Do not upload owned-card photos or migrate the user's collection to the provider.
2. Resolve the exact NFL releases for **Optic 2025** and **Topps Flagship Football 2026**. Compare base, insert and parallel coverage against the independent checklists. Report known/missing counts explicitly.
3. Test a mixed sample of base cards, inserts and numbered variants. Include CeeDee Lamb Downtown and Travis Hunter Downtown as identity controls; their older stored prices are not fixed expected results.
4. Validate exact raw auction matches with dates and source links. Keep asks, graded cards, lots, wrong variants and uncertain accepted offers out. Record coverage gaps and truncation rather than filling missing values with zero.
5. Measure actual quota use, latency, source coverage and any cache requirements. Enforce a local free-plan request budget, stop on quota/rate errors and never auto-upgrade.
6. Only after this passes, decide the production price basis and implement the importer/lookup path. Existing ranking validation accepts `guide` prices only: a sold-median result needs an explicit model/UI change and must not be mislabeled as a guide.

**Success means a genuinely larger, source-matched result set reaching the app—not another successful build with ten reference entries.** No source can guarantee a recent sale for every rare or untraded variant. Full checklist coverage and priced-card coverage must remain separate.

## No-new-account fallback

An independently sourced checklist plus individually researched public comps can grow without a paid feed. [130 Point](https://130point.com/about) provides free sales research. This route is useful for checking specific cards, but has not been established as a permitted automated full-catalog feed. It would remain slower and incompletely priced. Do not promise automatic comprehensive rankings, bypass access controls, or turn a manual research site into an undocumented bulk service.
