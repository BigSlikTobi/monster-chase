# Server retrieval — 16 October 2026

Later same-day [free-source pilot](free-source-pilot-2026-10-16.md): CardSight's
existing free-quota API returned usable title-matched auction records for three
real cards. This is now active through the [expiring CardSight price integration](cardsight-price-research.md). The original public HTTP/Playwright route described below is superseded for the VPS.

The Hostinger VPS now fetches public source pages itself. Luna Fast still does
photo identification and structured analysis. The Responses API always receives
`tools:[]`; even a legacy `webSearch:live` configuration cannot enable paid search.
The retrieval route disables automatic Sol/model fallback. Failures never invoke
OpenAI search, a paid scraping provider or an automatic proxy service.

**Material limitation:** SportsCardsPro and eBay returned HTTP 403 from this VPS
through both HTTP and a sandboxed Chromium browser. The pilot verified safe
analysis with unavailable sources, not successful fresh price retrieval. No
fresh market price was obtained. This deployment reduces source coverage versus
the previous hosted-search route. Existing saved card results were not rewritten
by the pilot. New analyses and explicit refreshes use only fetched evidence and
may have no price. No access-control or CAPTCHA bypass was implemented.

## Retrieval behavior

- Exact card identity comes from the saved identification, confirmed refresh,
  collector assignment, or a photo-only Luna identification when needed.
- The worker queries the native SportsCardsPro search page and eBay sold results.
  It can reuse actual source URLs from a prior analysis and follow at most two
  matching football-card links discovered in the native source page. It never
  manufactures card-page slugs. Missing player/year/product skips broad research.
- HTTPS source hosts and paths are allowlisted. Redirects are checked. HTTP
  requests have 12-second limits and 1.5 MB response bounds. Browser processes
  have 28-second limits, including descendant cleanup on timeout.
- Playwright 1.64.1 / Chromium headless shell revision 1248 runs as `cardscout`,
  with Chromium sandboxing enabled, a fresh browser context, no login/profile,
  no provider keys in its environment, no downloads and no service workers.
  Requests outside the source hosts and image/media/font requests are blocked.
- An executable-specific AppArmor profile allows user namespaces for the
  root-owned browser binary. The global Ubuntu restriction stays enabled at 1.
  The existing systemd filesystem isolation remains enabled.
- Successful page reads are cached for 24 hours; failures for five minutes.
  The private cache stores URL, status, fetch timestamp and bounded extracted
  text/links. Script/style contents are removed. Cache files are mode 0600.
- The model receives page text as untrusted evidence and no hosted tools.
  References require a readable fetched URL and observed price amounts. Sales
  also require their date and listing URL in fetched text. Existing exact-match,
  currency, shipping, duplicate-sale and schema checks still apply.
- Source text is not a structured sold-data feed. Exact variant matching and
  guide-versus-sale interpretation still need successful-source accuracy tests.
  Missing evidence produces unavailable/no-match source states and empty prices.

## Verification

The final local worker suite passed all 136 tests. New tests cover no-tool API
requests despite legacy live-search config, allowlists, HTML/table extraction,
cache reuse, blocked browser pages, real-link discovery, incomplete identity,
unsupported price rejection in full and market-only contracts, and no fallback.

The real-card pilot ran under the service user and systemd filesystem policy.
It copied records/photos into private temporary folders, called production
`run_codex`, and deleted the copies. It never submitted or overwrote owned cards.

| Real card | Test | Time | Result |
| --- | --- | --- | --- |
| Terrance Ferguson, 2025 Topps Chrome #335 | Price refresh | 8.94 s | Valid result; identity retained; no fresh price |
| Kamren Kinchens, 2025 Topps Chrome #174 | Price refresh | 7.56 s | Valid result; identity retained; no fresh price |
| Tre Harris, 2025 Donruss Optic, unresolved variant/number | Original-photo analysis | 13.28 s | Valid provisional result; uncertainty retained; no fresh price |

All three requests used `gpt-6-luna`, actual tier `fast`, and logged
`webSearchCalls:0`. All completed with Keep rather than treating missing data as
Bulk. All attempted source pages returned HTTP 403. These timings describe this
small pilot, not general throughput. A later prompt-size reduction passes only
the matching local-checklist row instead of a whole product checklist.

After deployment, the service resumed its existing queue. Authenticated private HTTPS `/v1/ping` returned 200, and subsequent production-card logs also showed Luna with `webSearchCalls:0`. Caddy remained active.

The safe pilot report is `/var/lib/cardscout/retrieval-pilot-20261016.json`.
Re-run with `sudo -u cardscout -H python3 /opt/cardscout/retrieval-pilot.py`.
Model-token costs still apply. Hosting/browser resource use and maintenance
remain; no claim of entirely free research is made.

## Install / recover

`server/install-linux.sh` copies the retrieval Python module and browser helper
with the service. Run `sudo bash server/install-retrieval.sh` to install the
isolated pinned browser runtime and its narrow AppArmor profile. No public
listener or separate paid service is added.

Private `data/config.json` sets `retrievalEnabled:true`,
`retrievalBrowserEnabled:true`, `webSearch:"disabled"`, `fallbackModel:null` and
`retrievalCacheDir:"/var/lib/cardscout/data/retrieval-cache"`.
Keep `apiEnabled:true` and `apiModel`/`model` set to `gpt-6-luna`.

The pre-change private config snapshot is
`/var/lib/cardscout/config-before-retrieval-20261016.json`. It contains secrets
and old search settings. Do not print it, copy it into source control, or restore
it as routine error recovery. Recovery must preserve disabled search and the
current paid-search-free API transport. Source-access failure means unavailable
pricing until a usable permitted source is validated.

Chromium's executable allowance follows its documented
[AppArmor guidance](https://chromium.googlesource.com/chromium/src/+/main/docs/security/apparmor-userns-restrictions.md).
