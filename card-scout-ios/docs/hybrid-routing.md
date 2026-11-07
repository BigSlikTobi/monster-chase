# Luna API Fast + server retrieval

**Current route, 2026-10-16:** Luna Fast performs analysis; CardSight supplies a separate expiring price view through its existing free-quota API. Paid OpenAI search and automatic fallback remain disabled. See [current price integration and verification](cardsight-price-research.md). The HTTP/Playwright route below is retained as implementation history and is not used when `cardSightResearchEnabled:true`.

The earlier hybrid route was enabled on the Hostinger VPS on 2026-10-16 at the user's request. “Sol” means the
heavier model, not sold-price research. All Luna stages use the API. The ChatGPT-authenticated Codex CLI is retained for the historical CLI-only route, but is not selected by the current retrieval route.

| Stage | Model | Access | Effort | Web tools |
| --- | --- | --- | --- | --- |
| Photo identification / visible condition | gpt-6-luna | Responses API, Fast | medium | disabled |
| Normal card/checklist/market research | gpt-6-luna | Responses API, Fast | medium | CardSight free-quota view; no hosted tools |
| Confirmed-card price refresh | gpt-6-luna | Responses API, Fast | medium | CardSight free-quota view; no hosted tools |
| Material identity/checklist/variant/licensing uncertainty | gpt-6-luna | Responses API, Fast | medium | retain uncertainty; no automatic model/search fallback |

Missing prices, API outages/timeouts/auth/quota failures and market-only refreshes
do not escalate to Sol. A failed quick identification can enter the normal full
analysis lane; it does not silently retry paid API calls or switch API models.
Schema/name-evidence/checklist/price-evidence validators remain active. The historical CLI-only fallback policy does not run on the retrieval route. No iPhone credentials or app
update are needed. Existing collection-reset backups remain untouched.

## Server configuration

Private `/var/lib/cardscout/data/config.json` contains these non-secret switches:

```json
{
  "apiEnabled": true,
  "apiModel": "gpt-6-luna",
  "apiServiceTier": "fast",
  "apiKeyFile": "/var/lib/cardscout/openai.env",
  "webSearch": "disabled",
  "retrievalEnabled": true,
  "cardSightResearchEnabled": true,
  "retrievalBrowserEnabled": true,
  "retrievalCacheDir": "/var/lib/cardscout/data/retrieval-cache",
  "fallbackModel": null,
  "reasoningEffort": "medium",
  "scanReasoningEffort": "medium",
  "marketReasoningEffort": "medium"
}
```

The key file is owned by `cardscout`, mode 0600, outside the service source and
job directories. A group/world-readable file or symlink is rejected. It is read
only by the API transport; it is not injected into Codex's environment or prompts.
The separately approved local key destination is `card-scout-ios/.env.local`,
ignored by Git. Never print or commit either file. Key name/project/lifetime came
from the secure Platform picker; lifetime was non-expiring, with no override.

The transport uses standard-library HTTPS only to `api.openai.com/v1/responses`,
blocks redirects, sends `store:false`, uses strict structured outputs and retains
no provider response body. Identification receives the original uploaded photo
(not the branded display crop). Web research receives no shell, filesystem or
computer-use tools. Market refreshes omit image inputs as before. Responses are
bounded to 2 MB; the default output budget is 6,000 tokens for scans and 24,000
for research, with 90/300-second request timeouts and zero hosted tool calls. Public-source retrieval is separately bounded. These are request bounds, not an account spend cap.

Logs contain model, requested/actual service tier, duration, token usage and web
search call count. HTTP errors expose only their numeric status, never provider
error bodies, credentials or images. Incomplete/refused results do not become a
saved analysis. Cancellation is checked before/after a synchronous HTTP request;
an in-flight network call may finish before shutdown/cancellation is observed.

## Fast mode and cost

Requests explicitly set `service_tier:"fast"`. The API may downgrade processing
under its documented ramp limits; `actualTier` records what ran. There is no
application fallback that silently requests Standard. Fast costs 2× the
corresponding Standard token rates. The advertised “up to 2.5×” is not a guaranteed
latency multiplier for Luna or a complete card-research job. API usage is billed
separately from the ChatGPT-authenticated Codex route; hosted web search would have separate charges, but is disabled in the current transport. No billing settings or spending limits were changed.

Official references:
- https://developers.openai.com/api/docs/models/gpt-6-luna
- https://developers.openai.com/api/docs/guides/fast-mode
- https://developers.openai.com/api/docs/pricing
- https://developers.openai.com/api/docs/guides/structured-outputs

## Earlier hybrid verification and rollback

The results below describe the previous paid-search route. Current tests and rollback requirements are in [retrieval verification](retrieval-worker.md). Never restore old paid-search settings as an automatic fallback.

126 Python tests passed, including API/CLI routing, name-evidence rejection,
credential handling, redirect refusal, missing/PNG image handling, incomplete
responses and HTTP errors without automatic paid retries. On the VPS, under the
service user and systemd filesystem policy, a synthetic image identification and
one real web-search request both completed with actual tier `fast` (2.85 s and
4.85 s respectively). This is integration evidence, not a latency or real-card
accuracy benchmark. Tests ran outside the owned-card queue and did not add cards.
A fresh scan through the iPhone remains the end-to-end acceptance step.

To roll back, stop the service, restore the private
`/var/lib/cardscout/config-before-hybrid-20261016.json` to `data/config.json`
with owner `cardscout:cardscout` and mode 0600, then start the service. This restores
the previous CLI-only settings and effort levels. Keep the API key private;
revoking it is a separate explicit action. Do not restore collection-reset
backups as part of a model-route rollback.
