# Product chase catalog — 8 September 2026

## Scope and selection

The user's two priorities are 2025 Donruss Optic and 2026 Topps Flagship Football. The three added products are 2025 Select, 2025 Prizm and 2025 Topps Chrome: a practical shortlist of licensed NFL releases with recognizable high-value chases and documented Hobby box contents. This is editorial selection, not proof these products lead the entire market on hit rate or expected return. Box prices, total print runs and individual-player insertion odds are insufficient for a reliable ROI ranking.

| Product | Hobby contents used for comparison | Chase selection |
| --- | --- | --- |
| 2025 Donruss Optic | 1 autograph, 9 numbered + 3 Holo parallels, on average | Six standard-sized Downtowns, three Gold RPS rookie autographs, one Gold base parallel |
| 2026 Topps Flagship | 1 autograph **or** relic; Jumbo separately has 1 of each | Eight First Signatures rookies and two Gold Ink /50 parallels |
| 2025 Select | 2 autographs, 1 relic, 15 Prizms, on average | Six Color Wheels and four Starcades |
| 2025 Prizm | 2 autographs, 10 numbered Prizms, on average | Ten high-value Color Blasts |
| 2025 Topps Chrome | 1 autograph/auto-relic, 2 numbered base/rookie parallels | Seven Helix inserts and three Black Refractors /10 |

Sources: [Panini Optic announcement](https://blog.paniniamerica.net/2025-donruss-optic-nfl-adds-to-thrilling-championship-chase/), [Topps Flagship release](https://www.topps.com/pages/topps-flagship-football), [Panini Select manufacturer sell sheet](https://www.blowoutcards.net/images/ss/25pnselectFB.pdf), [Panini Prizm announcement](https://blog.paniniamerica.net/panini-prizm-nfl-keeps-football-alive-past-the-super-bowl/), [Topps Chrome manufacturer sell sheet](https://www.blowoutcards.net/images/ss/25tpchrFB.pdf). The sell sheets are manufacturer-authored documents hosted by a retailer. Select's Hobby sheet explicitly includes Color Wheel and Starcade. [Topps confirms Chrome's NFL licensing](https://www.topps.com/pages/topps-chrome-football).

## Prices and ranking

The 50 exact player/set/variant/card-number entries were read from public SportsCardsPro price tables, with individual card pages and original image links checked in the browser on 8 September 2026. Each entry stores that exact card page as its price and image source. The app labels the values as raw guide estimates, not sold prices. No algorithmically extrapolated PSA grades are used.

Within each selected candidate list, rank is descending raw guide value. These are not the ten most valuable cards across every parallel, not sales-volume rankings, and not a measured rolling 90-day market index. One-of-ones were intentionally excluded from this starter selection: an observed sale would mean that unique card is no longer available to pull. Even numbered /10 and /50 cards may already be partly or entirely pulled; remaining sealed-pack availability is unknown.

2026 Flagship released on 21 August 2026, leaving less than three weeks of trading history at this snapshot. Its guide prices are especially provisional. [Topps collector guide](https://ripped.topps.com/2026-topps-flagship-football-cards-collector-guide/).

## Odds and formats

The baseline is Hobby, as announced while asking the user about box preference. Retail, Mega, H2, Delight, FOTL and Jumbo are not interchangeable. No per-card odds are inferred from autographs-per-box or print numbering. Panini's cited product materials do not provide exact insertion odds for these named players; the app says so.

[Topps 2026 Football odds](https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2026_Topps_Football_Odds.pdf?v=1787326624), page 41: Hobby Pack Rate is 1:449 for the First Signatures Base **series** and 1:5,857 for the Gold Ink **series**. Neither is the probability of pulling the displayed player. [Official checklist](https://cdn.shopify.com/s/files/1/0662/9749/5709/files/CheckList_26TFOB_VERSION5_1.pdf?v=1786730315), page 31, confirms the selected First Signatures identities.

[Topps 2025 Chrome odds](https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2025_Topps_Chrome_Football_Odds.pdf?v=1776193199), page 10: Helix is 1:2,559 packs in SKU 6390 Hobby Distributor. The next columns are HTA Jumbo First Day Issue, HTA Jumbo Hobby Distributor and Breaker Delight, **not** alternate standard Hobby odds.

## Maintaining the snapshot

Edit only the public reference seed `mac/data/chases.json`, retain stable card IDs when ranks change, update dates/revision only after fresh source review, run both test suites and install the companion. New paired clients fetch the changed revision independently of legacy import. Pull-to-refresh fetches the installed snapshot; it does not run new internet research. No scheduled research task was requested or created.

`python3 mac/verify_chase_images.py --output <QA directory>` downloads the cited scans and creates contact sheets for visual verification (Pillow required for this optional QA tool). Do not substitute a base-card image for a named parallel. Mark missing scans unavailable instead of inventing a URL or image.
