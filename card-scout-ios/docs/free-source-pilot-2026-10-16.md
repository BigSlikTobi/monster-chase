# Free price sources tested from the VPS

**Later update:** The user approved integration. [CardSight price research](cardsight-price-research.md) is now active with expiring views. The pilot boundaries below describe the state before that change.

**Current guards:** The later pricing audit raised the shared stop to **720 calls/month** and removed the separate 270/day pilot stop. See the [nine-card follow-up](#nine-card-follow-up-after-the-pricing-coverage-audit) below. The older limits in the initial pilot narrative are historical.

Tested 16 October 2026 against the existing Hostinger VPS. The result is a
working **free-quota API candidate: CardSight**. Reachable websites were also
checked for actual usable evidence, rather than treating HTTP 200 as success.

This was a read-only pilot. The production retrieval route, owned-card results,
and subscription settings were not changed. Luna remains the analysis model.
Paid OpenAI search remains hard-disabled. This pilot made no OpenAI requests.

## Real-card results: CardSight

All cards below are **2025 Topps Chrome, raw, Base Set**, not Sapphire,
refractors, image variations, autographs or multi-card lots.

| Card | Provider records | Accepted title matches | Median USD | Observed range USD | Newest accepted sale |
| --- | ---: | ---: | ---: | ---: | --- |
| Terrance Ferguson #335 | 3 | 3 | $0.71 | $0.36–$1.00 | 2026-09-20 |
| Kamren Kinchens #174 | 1 | 1 | $0.25 | $0.25 | 2026-10-11 |
| Jaxson Dart #306 | 25 | 16 | $2.43 | $0.99–$14.50 | 2026-10-13 |

These are **provider-reported completed-auction amounts**, with shipping unknown.
They are not delivered EUR valuations or independently verified paid transactions.
The accepted sale titles match identity and do not name a conflicting variant;
original listing photos and physical condition were not independently checked.
Three sampled `showme.cards` evidence links themselves returned HTTP 403 from
the VPS. Therefore the sale information is attributed to CardSight, not a claim
that the VPS opened and verified the original eBay listing.

Kamren has one observation, which is weak evidence, not a stable market median.
Jaxson's 25-record response is truncated; the provider warns that older records
exist. We rejected eight parallel records and one explicit 12-card lot. The high
accepted prices were not removed merely because they differed from the median.
Unstated photo differences can still remain. This small base-card pilot does
not establish insert, numbered, auto or parallel coverage.

The bounded reproducible pilot took **5.21 seconds for six API calls** under the
service user and the same systemd filesystem restrictions as production.
Exploration plus that pilot used 11 CardSight calls in this session. The existing
conservative local monthly ledger moved from 138 to 149. This is an application
ledger, not a billing statement. No raw catalog or provider-response archive was
saved. Temporary public-webpage captures were removed after review.

## Options tested

| Source | Actual VPS result | Decision |
| --- | --- | --- |
| CardSight | Authenticated API returned exact catalog IDs and auction records for all three cards; filtered results above | Best candidate within its free allowance |
| CardPricer | Anonymous documented API returned HTTP 200; full bounded player pages had zero exact base-card matches for all three | Working free API, insufficient coverage for this sample |
| CardGrader | Native checklist and all three individual card pages returned HTTP 200 using the identified CardScout client | Reachable, but unsuitable as trusted base sold pricing in this pilot |
| HobbyScan | Terrance page returned HTTP 200 and RAW $1.91, but detail fields said Gold Football Border, autograph and serial-numbered despite the generic heading | Reject as a base match |
| Midpoint / Card Centering Tool | Public Jaxson Topps Refractor page returned HTTP 200 with a PriceCharting-derived guide, dated 4 September | A secondary guide for a different variant; not independent live base-sale evidence |
| HiBid | Real Jaxson #306 auction lot returned HTTP 200, but public extracted page had no usable realized amount | No numerical comp accepted |
| 130 Point | Public sales page returned HTTP 403 | Unavailable through tested HTTP access |
| COMC | Exact-card search returned HTTP 403 | Unavailable through tested HTTP access; asking prices would remain separate |
| TCDB | Exact-card search returned HTTP 403 | Unavailable through tested HTTP access |
| Clector | Real Terrance parallel page returned HTTP 403 | Unavailable through tested HTTP access |
| FootballCardShop | Terrance player page returned HTTP 403 | Unavailable through tested HTTP access; retailer asks would remain separate |

CardGrader's problem is evidence quality rather than basic reachability. The
Terrance page showed “Recent Median (Raw)” $3.25 and “Raw Value” $1.16; its recent
sale rows mostly named parallels. Jaxson showed $50.00 as the recent raw median
while the shown rows mixed refractors, numbered parallels and graded cards.
No per-sale title and original sale link were available in the extracted table
to independently qualify these as exact base comps. Blindly importing the
headline would be wrong. Initial requests with Python's default user agent
returned 403; the same disclosed CardScout client used for the checklist worked
on the individual pages. No CAPTCHA, login or access-control bypass was used.

CardPricer is now reachable, unlike the older September HTTP 402 pilot. Its
current status endpoint reported no eBay, COMC, PWCC, Goldin or Heritage records
in the displayed 24-hour/seven-day source windows. Terrance and Kamren player
queries returned no cards. Jaxson returned 20 cards across other products and an
insert, with no 2025 Chrome base #306. API availability does not establish the
needed NFL coverage.

## Free quota and production boundary

[CardSight's published Free plan](https://cardsight.ai/pricing) includes 750
calls/month and stops at that limit. Existing app guards are stricter:
600/month and 270/day, with no retry or upgrade on auth/quota failures. Use
batch pricing and short caches; 750 calls is not unlimited card research, and
catalog lookups and usage checks also consume requests.

[Its current API schema](https://api.cardsight.ai/documentation/json) explicitly
defines auction prices as final-sale USD amounts and fixed listings as asking
prices. Native `parallel_id:null` results still require our own title filters,
as the Jaxson response demonstrated.

[CardSight's terms](https://cardsight.ai/terms) permit limited short-term caching
for the app and restrict independent durable provider databases. The existing
integration already uses expiring views for two products. This pilot does not
automatically copy CardSight prices into the permanent owned-card library or
expand that integration. A production extension should use the existing shared
quota ledger, strict exact-variant matching, attribution and expiring price
views, while Luna consumes the retrieved evidence with hosted tools disabled.

No alternative was silently activated. The existing saved-analysis provider
enum and validation contract still allow only SportsCardsPro/eBay/PSA. Correct
CardSight attribution needs an explicit integration change; its records must
not be mislabeled as directly verified eBay results.

## Reproduce

Read-only live pilot, using the existing private server key:

```sh
sudo -u cardscout -H python3 /opt/cardscout/service/free_source_pilot.py \
  --data /var/lib/cardscout/data
```

The pilot caps itself at seven requests and uses the existing durable free-plan
guards. It prints a summary only. It does not submit photos, mutate cards, change
plans, enable a scheduler or invoke OpenAI. Missing/ambiguous catalog identities
and incorrect pricing response IDs/filters fail closed. Regression controls
cover real observed variant/lot contamination, asks, missing links/dates,
invalid prices, future records, wrong card numbers and duplicate sales.

Other primary references:

- [CardPricer public API](https://cardpricer.co/docs/api)
- [CardGrader Jaxson Dart #306](https://cardgrader.ai/sports-card-database/football/2025-topps-chrome/306)
- [HobbyScan Terrance Ferguson page](https://www.hobbyscan.com/card/662869)
- [Midpoint's dated Topps Refractor guide](https://www.cardcenteringtool.com/prices/pricecharting-12532499)
- [HiBid Jaxson Dart auction lot](https://hibid.com/lot/318517396/2025-topps-chrome-jaxson-dart-rc---306)

At completion, authenticated private HTTPS `/v1/ping` returned 200, CardScout
was active, `webSearch` remained `disabled`, and automatic fallback remained
disabled. Luna remained `gpt-6-luna` through the existing API route.

## Nine-card follow-up after the pricing coverage audit

On 16 October 2026, the user requested another free source for the nine saved,
confirmed identities still missing qualifying CardSight prices. These checks ran
from the actual VPS, using ordinary public HTTP requests and its existing
Playwright browser runtime. Saved identities were used; no photos or owned-card
records were uploaded or changed. This was a source test, not an importer rollout.

### Results

| Source | Actual VPS result | Usable result for these nine |
| --- | --- | --- |
| Slabline | Public indexes and six exact detail pages returned 200. Three identities had no exact page found in bounded player/search/detail checks. | One exact raw **guide**, no qualified sold-price replacement. The other five exact pages only exposed a PSA 10 estimate. |
| CardPricer | All nine player/year API queries returned 200 and zero results. Broader 2025 product queries returned other cards. | Zero exact matches in the tested queries; reachability alone does not solve coverage. |
| CardGrader | All nine individual card pages eventually returned 200. The last five initially hit 429; a later paced retry succeeded. | Mixed variants and grades. No individual sale titles and original sale links were established in the retrieved tables, so no sold-price records qualified. |
| SportsCardsPro / PriceCharting | Exact Pacheco URL returned 403 on both domains. The existing VPS Playwright worker also returned 403 for SportsCardsPro. | Unavailable through tested access. No bypass attempted; this is a representative access check, not nine successful page retrievals. |
| CardValue | Pacheco route redirected to a rookie-card page whose live text explicitly described median eBay **asking prices**, across different years/cards/grades. | Wrong identity scope and evidence type. Rejected before expanding to nine queries. |

All nine cards are 2025 releases. “PSA 10 only” below means the exact page had a
single grade estimate, not a raw-card price. No conversion or discount was applied
to turn it into a raw value. A 404 or empty search is a bounded negative finding,
not proof the source can never cover that card.

| Saved card | Slabline exact-page result | CardPricer player/year query | CardGrader page |
| --- | --- | --- | --- |
| Donruss Optic Isiah Pacheco #147 base | 200; explicit Raw / Ungraded guide row | 200, zero results | 200, mixed variants |
| Donruss Optic Terry Bradshaw #188 Holo | 200; PSA 10 only | 200, zero results | 200, mixed variants |
| Donruss Optic Joe Mixon #130 base | No exact page found | 200, zero results | 200, numbered variants in displayed rows |
| Donruss Optic DJ Moore #114 base | 200; PSA 10 only | 200, zero results | 200, mixed variants |
| Donruss Optic Tyjae Spears #172 Holo | No exact Holo page found | 200, zero results | 200 after initial 429, mixed variants |
| Donruss Optic KeAndre Lambert-Smith #271 base | 200; PSA 10 only | 200, zero results | 200 after initial 429, mixed variants |
| Donruss Optic Tre Harris #229 base | 200; PSA 10 only | 200, zero results | 200 after initial 429, mixed variants |
| Topps Chrome Kyle Pitts #14 base | No exact base page found; Sapphire is a different product | 200, zero results | 200 after initial 429, mixed variants |
| Topps Chrome Jayden Daniels #295 Lightboard Logo Variation | 200; exact variation heading, PSA 10 only | 200, zero results | 200 after initial 429, mixed variants/grades |

The [exact Pacheco page](https://slabline.ai/cards/2025-donruss-optic-football-isiah-pacheco-147-psa-10)
had an explicit raw guide row attributed to **SportsCardsPro**. It is a secondary
guide, not an independent sales feed or a verified transaction. Other exact pages
were [DJ Moore](https://slabline.ai/cards/2025-donruss-optic-football-dj-moore-114-psa-10),
[KeAndre Lambert-Smith](https://slabline.ai/cards/2025-donruss-optic-football-keandre-lambert-smith-271-psa-10),
[Tre Harris](https://slabline.ai/cards/2025-panini-donruss-optic-tre-harris-229-psa-10),
[Bradshaw Holo](https://slabline.ai/cards/2025-panini-donruss-optic-terry-bradshaw-holo-188-psa-10),
and [Daniels Lightboard](https://slabline.ai/cards/2025-topps-chrome-jayden-daniels-lightboard-logo-variation-295-psa-10).
A normal browser check of Daniels and Lambert-Smith confirmed the public grade
selector offered only PSA 10. Those values cannot price the user's raw cards.

Slabline's public player/set indexes and its published `/cards?q=...` search were
checked, along with a small number of candidate detail routes. Search queries
returned no matching links for the missing cards. No full catalog was downloaded
or retained. No production allowlist was expanded. Public-page reachability does
not establish permission or a service guarantee for an automated production feed.

CardGrader example routes:
[Bradshaw #188](https://cardgrader.ai/sports-card-database/football/2025-panini-donruss-optic/188),
[Tre Harris #229](https://cardgrader.ai/sports-card-database/football/2025-panini-donruss-optic/229),
[Daniels #295](https://cardgrader.ai/sports-card-database/football/2025-topps-chrome/295).
Base or Holo labels alone were not promoted to verified full-title matches.
The [CardPricer API](https://cardpricer.co/docs/api) was used anonymously, with no
paid plan or key. CardValue's [live Pacheco page](https://cardvalue.io/isiah-pacheco-rookie-card/)
was classified from the VPS response, not older indexed search snippets.

### Outcome and guard verification

No alternative tested supplies qualified exact sold-price records for these nine.
Slabline is a limited guide candidate for one card; it does not resolve the other
eight. No new source was enabled and no app price was populated from these tests.
Existing CardSight remains active under its established exact-match rules.

After testing, the server still reported `model=apiModel=gpt-6-luna`,
`webSearch=disabled`, and `fallbackModel=null`. The shared CardSight ledger remained
**397/720 monthly calls**, unchanged during this follow-up. No CardSight or model
calls were made for the alternative-source checks. The 720 hard-stop constants
remain in place; no ledger reset, plan upgrade, paid search, or automatic fallback
was used. This source-research-only follow-up changed no runtime code or deployment.
