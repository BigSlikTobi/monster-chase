# CardSight price research — 16 October 2026

## Current route: restored Sol escalation and broader free guides

The user explicitly authorized restoring escalation and a new saved-photo pass.
The deployed primary is **GPT-6 Luna through the existing API**. A materially
uncertain or invalid full assessment escalates once to **GPT-5.6 Sol, max reasoning,
through the existing ChatGPT-authenticated Codex CLI**. An invalid photo-only step
also reaches that lane. Confirmed identity with no market data never triggers a
model escalation. A valid provisional Luna assessment is retained if Sol fails.

Both routes keep web search disabled. Codex runs with shell, browser, computer,
apps, plugins, hooks and multi-agent features disabled, no user configuration, and
a read-only sandbox. Sol does not use the OpenAI API transport or a new API key.
The same server-side rule rejects model-generated numeric prices in both routes;
market commentary is discarded so an incidental “no price found” sentence does
not invalidate an otherwise valid assessment. Prices remain a separate transient
source overlay. The shared CardSight hard stop remains **720/month**.

Both models receive only release-level licensing metadata from the existing
validated local product manifest. If photos and the verified checklist establish
the exact product/year/manufacturer, its known licensing need not be reread from
each physical back. This metadata cannot establish an ambiguous product, year,
finish or authenticity. Its original source links remain attached; the Panini
page was not newly retrieved successfully from the VPS in this follow-up.

Free guide lookup now extends beyond a hardcoded Pacheco entry. It checks normal
public Midpoint search/detail pages and published Slabline player/detail links.
It requires exact player, year, product, subset, number and finish, explicit raw
guide amounts, positive USD values and usable source dates. Midpoint's linked
text export must agree with the search identity; capture dates older than 90 days
are rejected. A verified public Topps Chrome release page handles matches missed
by Midpoint's ten-result search. Only its links are retained briefly in memory;
unrelated prices and provider catalogs are not saved.

No graded-price conversion, asking-price substitution, near match or numbered
guide without print-tier proof is accepted. Numbered cards still use the existing
exact-tier auction route. Guides remain estimates, sold evidence takes priority,
and both Slabline/Midpoint prices expire within 24 hours and are stripped from
library saves/backups. Access/rate failures cool that public host down for an hour;
there is no paid fallback or bypass.

Live VPS controls recovered Pacheco's exact raw Slabline guide and the exact
Jaxson Dart **Topps Refractor** #306 Midpoint raw guide, dated 4 September. The
latter is a source/parser control, not permission to price an owned base Dart as
a Refractor. Testing the nine previously unpriced identities retained Pacheco's
guide but recovered no additional guides for the other eight. That test reused
their sold-check caches and consumed **zero CardSight calls**.

A real saved-photo canary reached Luna and then Sol through Codex. Sol returned
Chimere Dike **#269 Purple Shock**, confirmed/high confidence with licensing and
an exact local checklist match. Pricing then recovered one exact raw auction.
The observed CardSight name is `Rated Rookie Purple Shock`; its same-set UUID was
checked live. Alongside the earlier Blue Hyper case, only those two observed
descriptors are normalized, with both owned and catalog rookie proof required.
Other finishes, wrong sets and print tiers remain rejected. Variant resolution
marker 4 selectively invalidates affected negative caches.

**184 backend tests pass** after the guide-release regression was added. **121
native tests ran, with zero failures and one optional live-cache test skipped.**
Build 26 includes one durable all-saved-photo operation, preserving card IDs,
photos and manual assignments, including failed and already confirmed cards.
The marker commits with the new jobs so repeating the launch does not repeat the
pass. A missing photo aborts without changing the collection or making it read-only.

The installed operation is `93ee5a82-d18b-45d8-ab27-6673844afd15`, also retained in
`/private/tmp/cardscout-sol-full-operation-id` for an idempotent retry. After the
user unlocked the phone, build 26 launched at **16:25 UTC**. The fresh phone receipt
confirmed **45 targeted cards**, and the VPS independently confirmed all **45 jobs
uploaded**. The source ledger began at **419/720**. The pass completed at
**17:00 UTC**, with all **45 analyzed, zero failures and zero pending jobs**.
The VPS and fresh build-26 phone receipts agree: **37 confirmed identities and
28 cards with fresh exact price evidence**. Of those, **26 have auction evidence**
and **two have explicitly labelled raw-guide estimates** (Pacheco/Slabline and
Aiyuk/Midpoint). The phone received **72 references**, acknowledged all 45 jobs,
and reported connected/writable with no connection error. No rescan or individual
card opening was needed for this pass.

Shared usage finished at **520/720**, a **101-call** increase for the full pass.
The final deployed configuration still has Luna primary, GPT-5.6 Sol/max fallback,
web search disabled and the hard cap 720. Real batch logs showed the restored
Sol/max Codex route on uncertain assessments; observed Luna accounting showed
zero hosted web-search calls. No price gap triggered paid search.

**Eight identities remain unresolved**, and **nine confirmed cards still lack
acceptable exact raw price evidence**. Restoring escalation improves coverage;
it does not make incomplete source coverage or ambiguous photos disappear.
The remaining identity reasons and exact-price gaps are listed below. These are
owned-card audit metadata, not a stored provider catalog or price archive.

### Remaining identity reviews after the completed pass

| Card | Evidence still missing |
| --- | --- |
| Trey Amos | Die fehlende Rückseite verhindert die Bestätigung von Kartennummer und exakter Parallelbezeichnung. |
| Jarquez Hunter | Die fehlende Rückseite verhindert die sichere Trennung von Base und Holo sowie die Bestätigung der Kartennummer. |
| Alfred Collins | Ohne Rückseite ist das Base/Holo-Finish nicht sicher unterscheidbar. |
| Calvin Johnson / Matthew Stafford | Offizielles Produktjahr und Checklist-Zuordnung des Inserts sind am Foto nicht eindeutig bestätigt. NFL-/NFLPA-Lizenz fehlt oder ist noch nicht bestätigt. |
| Bo Nix | Ohne Rückseitenfoto fehlt der PRIZM-Stempel zur sicheren Trennung von Base und Holo. |
| Will Johnson | Base und Holo sind anhand dieser Vorderseite nicht zuverlässig unterscheidbar; die Rückseite mit möglicher PRIZM-Kennzeichnung fehlt. |
| Tyjae Spears | Das Rückseitenfoto fehlt; Base und Holo sind ohne PRIZM-Kennzeichnung nicht sicher unterscheidbar. |
| Jayden Daniels | Die vollständige Power-Players-Refractor-Checkliste liegt lokal nicht vor; PP-3 konnte daher nicht checklistengestützt bestätigt werden. |

Jayden Daniels is a checklist-evidence gap, so adding another photo alone may not resolve it. The other unresolved cards have missing number/year/finish evidence from the saved fronts. Do not ask the collector to guess the collection or force an exact price.

### Confirmed cards still without exact raw prices

| Card | Variant | Source outcome |
| --- | --- | --- |
| T.J. Sanders · Donruss Optic · Base #226 | Blue Hyper | Returned sales rejected as non-exact; no acceptable raw guide |
| KeAndre Lambert-Smith · Donruss Optic · Base #271 | Blue Hyper | No raw auctions found; no acceptable raw guide |
| Trevor Etienne · Donruss Optic · Hidden Potential #11 | Base/standard | Returned sales rejected as non-exact; no acceptable raw guide |
| Luke Kuechly · Donruss Optic · Base #84 | Blue Hyper | Exact variant not uniquely resolved in the source catalog |
| Tre Harris · Donruss Optic · Base #229 | Base/standard | Returned sales rejected as non-exact; no acceptable raw guide |
| KeAndre Lambert-Smith · Donruss Optic · Base #271 | Base/standard | Returned sales rejected as non-exact; no acceptable raw guide |
| DJ Moore · Donruss Optic · Base #114 | Base/standard | Returned sales rejected as non-exact; no acceptable raw guide |
| Joe Mixon · Donruss Optic · Base #130 | Base/standard | Returned sales rejected as non-exact; no acceptable raw guide |
| Kyle Pitts · Topps Chrome · Base #14 | Base/standard | Returned sales rejected as non-exact; no acceptable raw guide |

## Earlier guide and recovery checkpoints

## Exact raw guide fallback

When no accepted exact raw sale exists, the server may attach a clearly labelled
raw guide estimate. The first enabled identity is **2025 Donruss Optic Isiah Pacheco
#147 base** from [Slabline's exact page](https://slabline.ai/cards/2025-donruss-optic-football-isiah-pacheco-147-psa-10).
Although its URL names PSA 10, the importer reads only the separate `Raw / Ungraded`
table row marked `price guide`, after checking the exact heading and SportsCardsPro
attribution. The graded headline is never used or converted. Live VPS parsing and
the authenticated app API returned **$1.27 USD**, `provider=Slabline`, `kind=guide`,
`grade=raw`, `matchQuality=exact`, no sale date, and a bounded expiry.

`raw_guides.py` contains an individually verified identity-to-page mapping. Other
players, years, inserts, parallels and serial tiers cannot match this entry. There
is no guessed URL discovery, search API, key or model call. Fetches reject redirects,
oversized pages, changed headings, ambiguous raw rows, missing attribution and
invalid values. Source failures leave the price empty. Another guide needs its own
exact source/page and matching checks.

Accepted sold evidence always takes priority, including a single or older accepted
sale. An existing negative CardSight cache can gain the guide without repeating
CardSight requests. Failed guide checks cool down with the same cache. Guide
evidence expires within 24 hours and is stripped from the permanent phone library
and backups. Collection totals treat guides as estimates. The detail page says
`Schätzung aus Preisguide · kein bestätigter Verkauf`.

At the first live guide check, shared usage remained **397/720**, unchanged. Luna,
disabled paid search, no automatic model/search fallback and the 720-call stop remain.

### Latest front-only batch and checklist repair

The next batch contained 24 jobs, including two failed assessments. All 24 had no
card number and an unconfirmed identity, so price research did not run. The prompt
also had a defect: local checklist excerpts were selected only by card number. A
front without a printed number got no matching rows even when a complete independent
local checklist already existed.

The prompt now supplies bounded player-matched candidate rows from matching local
products/subsets/years, preserving conflicting candidates. A unique verified row may
supply a number only when the photographed product/year/player/subset/finish are
otherwise supported with high confidence. A candidate never proves licensing, year
or finish. Material uncertainty still needs the missing back or a clearer front.
Full-photo retries receive the same photo-identification step and checklist evidence;
the identification step is saved for interruption recovery.

Bounded saved-photo recovery supports named failed cards and completed unclear cards.
It preserves collection card IDs/photos/manual assignments and targets old job IDs
so the same launch cannot repeat the batch. One unreadable-name card was excluded
from the planned 23-card recovery. Build 25 installed successfully. Its first launch
was blocked by iOS because the phone was locked; no recovery job had been submitted
at that checkpoint. Unlock is needed for the saved-photo pass and phone delivery check.

Validation: **174 backend tests passed; 118 native tests ran with zero failures and
one optional live-cache test skipped.** The iPhone build succeeded. The real guide
and authenticated price response were verified from the VPS. No new-card coverage
improvement is claimed before recovery completes.

### Completed saved-photo check

After the phone was unlocked, all 23 selected cards were submitted once from their
existing photo files. The real iPhone build 25 price receipt confirmed **12 cards
with fresh prices, 33 references, and one guide estimate** at 15:36:35 UTC. This
verifies Pacheco's new guide reached the phone, beyond the server-only API check.

The VPS completed the batch with **19 analyzed and four failed validation**.
Of the 19 analyzed results, only two had `identityConfirmed=true`; one of those
(Emeka Egbuka Diamond Hands #4) still had unknown licensing and remained ineligible
for pricing. There were **18 analyzed cards requiring further review**, plus the
four failures. Failed assessments were Chimere Dike, Terrance Ferguson, KeAndre
Lambert-Smith and Brandon Aiyuk. One isolated diagnostic Luna recheck of the first
failure returned a valid but unconfirmed result; it did not mutate the collection
or resolve the four saved failed jobs. Their exact validation causes were not
retained by the original worker, so no unverified cause is asserted here.

The other confirmed card, **Trey Amos #267 Blue Hyper**, exposed a real matcher
defect. CardSight's exact same-set UUID is named `Rated Rookie Blue Hyper`, while
the owned finish is `Blue Hyper`. The four-row native name query proved the
same-set UUID; it was not inferred from a similar card or another finish.

The deployed repair recognizes that one observed label only for 2025 Donruss
Optic Base when both the owned analysis says rookie and the catalog carries `RC`.
The exact release, set UUID, finish and print tier still have to resolve uniquely.
Sale titles must independently state Blue Hyper; base, other colors and other
finishes remain rejected. Only affected negative variant caches are invalidated.
Regression checks cover the observed match, missing owned/catalog rookie proof,
and wrong-finish sales. **177 backend tests passed** after this repair.

Trey's refreshed app API view is `ready` with exact raw auction evidence. Both
provider records report **$0.01 USD on 1 June 2026**, with shipping unknown. The
12-month window warning is retained. This is weak older evidence, not proof the
current market value is one cent. No arbitrary minimum price or fabricated guide
was substituted. No other newly analyzed identity received a price.

Final server checks: no active analysis jobs; Luna remains `gpt-6-luna`, paid search
is disabled, automatic model fallback is null, and shared usage is **409/720**.
The authenticated app API serves Pacheco as an exact raw Slabline guide and Trey
as exact raw CardSight sold evidence. The phone locked again during processing;
later file-copy attempts were denied by iOS file protection and did not update
the receipts. Their older local copies were not treated as proof of final batch
delivery. Opening the app while unlocked is needed for that final sync check.

After the second unlock, a fresh phone receipt at **15:49:04 UTC** confirmed all
23 results had synced: **19 completed, four failed, zero pending, two confirmed**.
The app was then restarted without reanalysis arguments to rehydrate the repaired
price cache. Its fresh receipt at **15:49:27 UTC** contained one priced card and two
references, confirming Trey's newly accepted evidence reached the phone. A later
fresh receipt at **15:50:07 UTC** contained nine priced cards and one guide estimate,
confirming Pacheco's guide had also rehydrated in that session. Older price views
were still loading; these snapshots are not claimed as the final whole-library
price count. No additional source/model research was triggered by this sync.
The four validation failures remain unresolved; they were not relabelled as
successful analyses or silently retried in a loop.

## Earlier auction integration

**Latest update:** The [coverage audit and lookup repair](pricing-coverage-audit.md) adds a clearly labelled 12-month auction window and bounded search of unlinked listings when the recent exact match is empty. Exact parallels and numbered cards remain supported. The shared monthly stop is 720 calls; the old pilot's 270/day stop is removed. Historical test counts/timings below describe the initial integration.

Enabled on the existing Hostinger VPS and shipped in iPhone build **1.1 (20)**.
Luna Fast remains responsible for the saved identity/condition assessment.
CardSight's existing free-quota API supplies a separate 24-hour auction-price
view. Paid OpenAI search is hard-disabled in the API transport. This route sets
`fallbackModel:null` and does not invoke Codex/Sol, another price service, a paid
proxy, or HTTP/Playwright research when CardSight is missing or unavailable.

## What the collector sees

- New confirmed cards receive CardSight research after Luna's analysis. The
  independent photo-identification lane can continue while pricing runs.
- Opening a previously analyzed card requests its price view through the private
  server. Fresh cached prices are reused. After an app restart, bounded GETs
  restore already-cached views for the collection without starting research.
- The price panel names **CardSight**, reports the observed USD median/range,
  labels single sales explicitly and says shipping is unknown. Records are
  provider-reported auctions; original eBay pages/payment/condition were not
  independently verified. A capped sample is labeled as a limited sample.
- Unknown identity, missing numbers, ambiguous matches, unsupported variants,
  quota/auth failures and outages leave prices open. Missing data is not zero
  and does not cause a Bulk recommendation or an automatic paid fallback.

Initial coverage was exact standard base/insert versions of Donruss Optic, Topps
Chrome and Topps Flagship Football. The adapter requires high confidence,
confirmed identity and acceptable licensing. The same-day [parallel and numbered-card extension](cardsight-variants.md) adds resolved exact parallel UUIDs and print tiers. Ambiguous image variations and unknown card numbers remain unpriced.

## Price matching

`card_prices.py` resolves the exact player, year, product, subset and card number.
Sapphire and variation records cannot become a normal Chrome base match. The
response must return the same provider card/set IDs and the requested filters:
raw, exact variant, completed auctions, last 90 days, at most 25 records. If no exact sale qualifies, one bounded 12-month catalog query is checked, then one 25-row auction-title search that can include listings not linked to the provider catalog. Recent matches take priority. Older-only evidence is explicitly labelled as up to 12 months old.

Each sale must have a safe individual evidence link, actual positive amount and
an in-window date. Title checks reject wrong years/products/numbers, grading,
lots, serials, parallels and competing inserts. Duplicate URLs and identical
date/title/amount fingerprints are counted once. Native `parallel_id:null` is
not trusted as proof of base. Emoji/Fire/Electricity parallels and seller-questioned `Insert ?` titles are rejected. The title-search response must echo the requested filters; conflicting canonical IDs and grade metadata are rejected, and unlinked records still need full exact title proof. Known manufacturer words repeated in a listing
cannot by themselves become a named refractor.

Insert/parallel name vocabulary is temporarily cached by release, with no
provider card catalog retained. Parallel vocabulary is name-sorted and bounded
to four 100-row pages; larger/incomplete/changed metadata fails closed. The
live Chrome release has 327 parallel entries, which caught the original
single-page assumption during integration testing. The regression is covered.

## Free quota

The existing CardSight key and usage ledger are shared with product rankings.
All clients/processes reserve each request under an OS file lock **before**
transport. Failures count too; competing clients cannot spend the same final
free request. Account usage is checked before each uncached card lookup.

- Shared local hard cap: **720/month**. The old 270/day pilot stop no longer prevents using the remaining monthly allowance. The published free plan is
  **750/month**, leaving a 30-call buffer. No subscription change or call-pack purchase.
- A recent base match with warm metadata still takes three calls. A full no-match path takes at most five for base or eleven for a parallel; cold metadata can add five (up to ten/sixteen total). Parallel UUID resolution checks at most four 100-row pages because CardSight has no set-ID filter on that endpoint. Sale queries stay capped at 25 rows with only one additional title search. Repeated identities reuse the same 24-hour view.
- Fresh-cache reads and reopenings consume **zero** CardSight calls.
- Failed/no-match checks also cool down for 24 hours. Auth/quota errors use the
  existing global halt. Reopening screens cannot silently retry those failures.
- Matcher version 4 invalidates earlier price views so repaired lookups and stricter variant exclusions can run. Cached reasons distinguish an unresolved catalog/variant, no sales, rejected nonexact records, provider failure, and an invalid response. A response-validation error is no longer reported as a missing sale.
- Manual screen requests run on one bounded background executor with at most
  32 pending identities. Polling reads status only; it does not start research.

Luna's normal model-token charges still apply. No claim of unlimited free
research is made. Other account/key activity can consume the provider quota;
the usage check and conservative shared cap protect this application route.

## Retention and protocol

CardSight evidence is stored only in owner-private `data/card-price-cache/`
views, with an expiry, identity hash and matcher version. Source catalog pages
and rejected sale records are discarded. The maintenance loop purges expired
views/vocabulary even without a connected phone; reads enforce expiry at once.
Removing the key also purges these caches.

Luna receives no CardSight prices in its durable assessment prompt. Its numeric
market fields/references/bullets must remain empty on this route; a violation
fails validation. `Repository.public()` overlays the expiring view on the
network response. Queue SQLite results remain unchanged and contain no
CardSight sale evidence. User photos and local checklists keep their existing
storage and provenance.

The iPhone decodes the references into memory. `DiskStore.save` strips CardSight
references/checks/bullets from a copy before writing `library.json`; the in-memory
view remains usable. Loading the library also sanitizes any accidentally old
transient data. Headline values, detail evidence and statistics reject missing,
expired or overly distant CardSight expiries. Expired views are cleared during
foreground sync and when presented.

Authenticated `POST /v1/jobs/{existing-job-id}/prices` starts/reuses pricing only
for the server's own analyzed record; callers cannot submit arbitrary source
URLs or override its identity. `GET /v1/jobs/{id}` returns current cached prices
and `priceStatus`. Both remain behind the existing pinned HTTPS/authentication.
The API model schema stays a durable no-CardSight-price contract; transient
provider strings/expiry are added only to the public price response.

This follows the [free-plan limits](https://cardsight.ai/pricing),
[auction-versus-asking schema](https://api.cardsight.ai/documentation/json) and
[limited caching terms](https://cardsight.ai/terms). No durable independent
CardSight catalog or owned-card price database is created.

## Verification

- **150 Python tests passed**, including shared-budget concurrency, hard cap and
  quota error stops, cache reuse/expiry, exact matching, 327-variant paging,
  source attribution and absence of provider evidence in queue SQLite.
- **99 Swift tests ran: 98 passed, one optional live-cache check skipped**.
  New cases cover expiry and ensuring library persistence preserves the card,
  photo references and assessment while excluding all transient price evidence.
- The signed iPhone build succeeded. Build 20 installed over the existing app
  without deleting data. The app launched on the unlocked physical iPhone.
  Its delivery-only receipt reported build 20, one card with fresh prices and
  three auction references at 2026-10-16T13:40:58Z. Only that named diagnostic
  file was retrieved; the phone's library/photos were not copied for inspection.
- On the VPS, real Luna market-refresh runs completed for Terrance Ferguson,
  Kamren Kinchens and Jaxson Dart: actual model `gpt-6-luna`, tier `fast`,
  `webSearchCalls:0`; durable references remained empty.
- Final authenticated app-facing price endpoints returned:

| 2025 Topps Chrome Base | Accepted auction records | USD median |
| --- | ---: | ---: |
| Terrance Ferguson #335 | 3 | $0.71 |
| Kamren Kinchens #174 | 1 | $0.25 |
| Jaxson Dart #306 | 16 | $2.43 |

Every returned reference had CardSight attribution and an expiry. The existing
SQLite result text was unchanged for all three cards. Repeating a cached POST
spent zero additional provider calls. The observed local ledger was 186/month,
161/day after the test sequence, below both hard caps. The one-sale Kinchens
sample is weak evidence; Dart's 25-record source response is truncated. Original
listing links remained blocked from the VPS, so these are provider-reported
auction amounts with unknown shipping, not verified delivered EUR values.

Private `/v1/ping` passed after restart. Live configuration retained Luna,
`webSearch:"disabled"`, `fallbackModel:null` and
`cardSightResearchEnabled:true`.

The phone's `card-price-status.json` is a delivery-only receipt: build number,
fresh-price card count, reference count and timestamp. It contains no names,
card IDs, price amounts, evidence URLs, photos or credentials. It is not a
saved provider-price cache or telemetry.

## Deployment and recovery

The Linux installer and Mac source-copy list include `card_prices.py`. Existing
model credentials, pairing, photos and queues are preserved. The private VPS
config snapshot before enabling this route is
`/var/lib/cardscout/config-before-card-prices-20261016.json`; do not print it or
commit it. Keep the API transport's unconditional `tools:[]` policy for every
recovery. Never restore paid search or a model fallback as automatic error
handling. A missing/expired price view is an acceptable failure state.
