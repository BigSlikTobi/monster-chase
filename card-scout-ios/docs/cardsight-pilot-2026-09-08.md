# CardSight free-plan pilot — 8 September 2026

Historical pilot below. **Build 7 now adds a filtered, expiring CardSight ranking view** for Optic and Topps. It does not import a permanent provider checklist or claim all-parallel coverage. See [integration](cardsight-integration.md) and [current deployment verification](verification.md).

## Decision

**The free connection works, and both NFL releases have substantial catalog coverage. Directly importing its prices is not safe yet: some parallel sales are incorrectly returned as base-card sales.**

The dedicated key was created with the user's approval and saved outside the project, in the Mac companion's private application-support directory (directory `0700`, key file `0600`). No key was printed, added to source files, bundled into the phone app, or sent anywhere except the official CardSight API and the one-time loopback setup form. That form has shut down. No subscription upgrade, photo upload, collection migration, app deployment, or production-feed replacement happened.

The manual pilot made **20 authenticated HTTP requests**. The usage endpoint returned 16 metered calls; the subsequently refreshed dashboard showed **17 used out of the free plan's 750**, leaving **733** at the final check. The dashboard still displayed Free / $0.00 per month. Do not assume one HTTP request always equals one billed call, or that the usage counter is immediately final. The local pilot client capped requests at 40 and ran no automatic retries or background refresh.

## Catalog result

| Exact football release | Provider-reported sets | Base set | Sum of set card counts |
| --- | ---: | ---: | ---: |
| 2025 Donruss Optic | 29 | 300 | 902 |
| 2026 Topps Flagship Football | 67 | 400 | 2,715 |

These are **provider metadata counts**, not a complete card-by-card checklist audit and not counts of priced cards or all parallel combinations. Only a small card sample was retrieved. Optic's 300-card base count agrees with the [independent checklist](https://www.beckett.com/news/2025-donruss-optic-football-cards/). Manufacturer checklist references remain separate from CardSight's catalog; [Topps provides its official product downloads here](https://www.topps.com/pages/topps-flagship-football).

Known metadata limits:

- The Culpepper card detail lists 79 set-level parallel types, including partial rookie-autograph types. This does not mean Culpepper has every listed variant. Never multiply every subject by every set parallel without checking applicability.
- Josh Allen #22 has separate variation card IDs. Search returned six matches; the small five-result page was explicitly incomplete. Only the non-variation base ID was selected for base pricing.
- Fernando Mendoza Flagship First Signatures reports zero parallel types. Gold/Red Ink versions are listed by the [independent related-set checklist](https://www.tcdb.com/Inserts.cfm/sid/665897/2026-ToppsFlagship), so this part of the provider catalog needs further reconciliation. A Mendoza Gold Ink price was not tested.

## Price sample

Every request explicitly selected ungraded cards, completed auctions, a 90-day period, and either base (`parallel_id: null`) or a specific Gold parallel. Limits were 25 recent observations per card. No response reached that cap or supplied a truncation warning. This does not establish complete marketplace coverage.

| Card/version | Returned observations | Pilot finding |
| --- | ---: | --- |
| Optic CeeDee Lamb Downtown #9 | 5 | Title-matched raw auction records; item-price median **$350**, observed $336.11–$385. |
| Optic Travis Hunter Downtown #13 | 8 | Title-matched raw auction records; item-price median **$326**, observed $305–$345. |
| Optic Daunte Culpepper base #60 | 1 | $0.09 with `READ` in the title. Needs listing review; no stable value assigned. |
| Optic Michael Penix Jr. base #134 | 7 | One clear Stars parallel must be excluded. Three `READ` listings need review. Three other titles are base candidates; no automatic value assigned. |
| Optic Culpepper Gold /10 | 0 | No returned sale; unknown, not zero dollars. |
| Optic Penix Gold /10 | 0 | No returned sale; unknown, not zero dollars. |
| Topps Fernando Mendoza Flagship First Signatures #FFS-FM | 1 | One $791 sale. Useful evidence, not a reliable market range. |
| Topps Josh Allen base #22 | 7 | All seven titles indicate Gold, Diamante, Holo Foil, a numbered card, or an unspecified parallel. **None qualifies as an exact base comp.** |
| Topps Josh Allen Gold /2026 #22 | 1 | Exact-parallel request returned one $2 observation. Other Gold titles were instead returned under base. Classification is incomplete. |

Across nine card/version queries, the provider returned 30 observations. Eight have clear wrong-variant titles for the requested base identity. Four further low-price `READ` listings were held for review, not declared invalid. The remaining 18 are title-matched candidates, not 18 independently verified transactions. Three original listings were spot-checked below.

The two Downtown medians are calculated from all five/eight title-matched provider records, respectively. Only their newest sale was independently checked on eBay. No outliers were removed from those two samples. These are **raw auction item-price medians, not price-guide values and not delivered totals**. Actual buyer-paid shipping and fees are not provided by the API. eBay's current international shipping quote is not proof of what the original buyer paid.

## Original-sale checks

The following original eBay pages matched the provider's price and raw-card classification:

- [CeeDee Lamb, item 168632894525](https://www.ebay.com/itm/168632894525?nordt=true): sold for $344, nine bids, ungraded, 2 September 2026.
- [Travis Hunter, item 327328149735](https://www.ebay.com/itm/327328149735?nordt=true): sold for $305, 22 bids, ungraded. The page shows 3 September in its local display; the API timestamp is 4 September UTC for the same sale.
- [Fernando Mendoza, item 278303827099](https://www.ebay.com/itm/278303827099?nordt=true): sold for $791, 54 bids, ungraded. The page shows 27 August locally; the API timestamp is 28 August UTC.

API source links used `showme.cards` redirects to the original eBay items. The supplied links preserve `nordt=true`; opening a bare item URL can redirect to a generic product page and show a different active listing. Do not use that replacement listing as evidence of the original sale.

## What must happen before an app integration

1. Resolve exact card, variation, autograph and parallel identities against independent checklists. Do not rely on the provider's nullable parallel field alone.
2. Reject contradictory listing titles and flag ambiguous records for review. A wrongly categorized Gold sale must never inflate a base-card value.
3. Use a common explicit price basis for rankings and collection comparisons: raw sold median, item-only when shipping is unknown, with observation count, window and source links. The existing guide-only model needs a deliberate change; sold medians must not be labeled guides.
4. Keep unpriced cards visible but unranked. Separate complete-checklist coverage from price coverage and show sparse single-sale evidence separately.
5. Resolve permitted short-lived cache scope before any whole-product download. [CardSight's terms](https://cardsight.ai/terms) restrict standalone database copies. This pilot did not populate a permanent provider catalog or import its response bodies into the app.
6. Verify more than ten real entries reach the phone, filters work against the larger feed, and the user's collection/photos remain intact. This pilot is not that release.

## Reproducibility and safety

- Public contract: [live OpenAPI specification](https://api.cardsight.ai/documentation/json) and [API documentation](https://api.cardsight.ai/documentation).
- Local manual client: `mac/cardsight_pilot.py`. It is not imported by the server, analysis worker or app.
- `setup` accepts hidden terminal input; `setup-web` provides a one-use loopback-only form with an unguessable route, strict host/origin checks, no external assets, no cache, no key echo, and exclusive private-file creation. Existing keys are never overwritten.
- `serve` reads the private key without printing it and permits only catalog/usage GETs and small raw-auction pricing POSTs. It pins requests to `api.cardsight.ai`, uses normal TLS validation, refuses redirects, redacts echoed credentials, and stops on authentication, billing, or rate-limit errors.
- No API response cache is written by the client. This report retains aggregate findings and a small set of audit references, not a provider database export.
- Verification: **58 Python tests passed**, including 12 new offline safety tests. The setup form, file permissions, authenticated requests, and three source listings were also checked live.
