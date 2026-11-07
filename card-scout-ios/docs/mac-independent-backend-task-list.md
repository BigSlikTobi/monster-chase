# Card Scout: remove the Mac backend

Created: 7 November 2026. Status: planning only; all tasks below remain open.

Each numbered task has its own prepared Codex chat. Open it from the
[task chat index](mac-independent-backend-chats.md) and say `Start this task`.
The chats are waiting; creating them did not start implementation.

Goal: people install Card Scout, scan cards, and receive catalog and market results
without a Mac, private VPN, pairing code, or personal AI account.

## Agreed direction

- Keep original photos, collections, notes, and purchases on the iPhone for the first release.
- Try on-device text reading plus verified checklist matching first. Clear matches need no model call.
- Send ambiguous cards to user review. Jev or Luna is an optional later improvement, subject to testing and a separate provider/budget decision.
- Reuse bounded market caches across users. Keep each person's photos and collection private.
- Keep paid web search disabled. Preserve the existing CardSight usage limit until a change is explicitly approved.
- Preserve current collection data and manual assignments during every migration.

Mac-free operation and public distribution are separate milestones. A private
server can prove Mac-free operation before public onboarding is built. Moving the
backend does not depend on finishing the new recognition flow.

## Milestone 1: prove the existing server can replace the Mac

- [ ] **01 — Audit the actual phone and server route.** Check the phone's saved
  endpoint, VPS service/version, configuration, credentials, queue, catalog,
  storage, and restart behavior. Find every Mac-only path and personal Codex-login
  dependency. Reconcile conflicting historical setup/routing documents.
  **Done when:** one current dependency map says where each operation runs and
  distinguishes source-code evidence from live checks.

- [ ] **02 — Prepare a reversible server migration.** Back up and validate the
  phone's collection and private worker state. Package all required code, reviewed
  catalog assets, configuration, and server-side credentials. Preserve the quota
  ledger. Keep the existing Mac state available for rollback and avoid affecting
  other VPS applications. Record the exact deployed revision.
  **Done when:** the server has every required dependency and a documented,
  tested restore procedure; any remaining personal-login dependency is explicit.

- [ ] **03 — Run the Mac-off acceptance test.** After separately approved
  deployment/device updates, shut down the Mac and scan from the real iPhone over
  cellular. Verify front/back capture, identity/review, pricing or an honest
  unavailable result, corrections, offline save/reconnect, and server restart.
  **Done when:** the phone completes the workflow without reaching the Mac and
  existing card IDs, photos, notes, purchases, and assignments remain intact.
  This private-server milestone may still require Tailscale.

## Milestone 2: make ordinary scans work without AI calls

- [ ] **04 — Read and retain text from both sides.** Audit all capture/import
  paths. Keep front and back text evidence separate, including readable player,
  card number, year, product, serial, and variant marks. OCR is evidence, not an
  exact identity or authenticity verdict.
  **Done when:** saved front/back captures provide usable text to matching and
  unreadable fields stay unknown.

- [ ] **05 — Define the exact identity and maintain its catalog.** Define stable
  identities covering year, manufacturer, product, subset, number, parallel,
  licensing family, and print run where relevant. Use independently sourced,
  reviewed checklist facts with coverage and revision metadata. Support bounded
  catalog delivery and updates for offline matching. Keep provider cache data
  separate from the permanent catalog.
  **Done when:** look-alike releases and variants cannot silently collapse into
  one identity, and incomplete catalog coverage remains visible.

- [ ] **06 — Add deterministic matching and user review.** Match OCR evidence
  against the catalog before any AI call. Accept an identity only when the
  evidence establishes the required fields. A single search result alone is not
  sufficient. Show candidates, missing evidence, a back/retake request, or manual
  confirmation for ambiguous cards. Decouple identity/price handling from the
  existing mandatory model-result contract. Condition stays unassessed unless
  supported by user input or a separate assessment.
  **Done when:** clear cards reach pricing with zero Luna, Decisions, Jev, or
  Codex calls; ambiguous cards stay open and corrections survive refreshes.

- [ ] **07 — Validate the OCR-first flow on verified cards.** Use the same labeled
  front/back photos for comparison. Include wrong years, Holo/Base, numbered
  variants, college/NFL, glare, missing backs, and unsupported products. Measure
  correct, incorrect, unresolved, coverage, total time, and provider calls. Agree
  acceptance targets before the final evaluation. Test unseen cards as well as
  development examples.
  **Done when:** a reviewable report establishes which cases can be accepted
  automatically. Any Jev/Luna experiment is a separate optional task; no silent
  paid fallback is introduced.

## Milestone 3: let public users connect safely

- [ ] **08 — Choose user access and enforce ownership.** Decide whether the first
  beta uses accounts or anonymous installation sessions, with a clear recovery
  policy. Replace the shared pairing token with individual revocable access.
  Scope jobs, results, corrections, cancellations, acknowledgements, bootstrap,
  and deletion to their owner. Review legacy bootstrap and cross-job comparison
  code for private-data exposure. Do not expose the existing private worker
  directly to the internet.
  **Done when:** two users cannot read, change, or infer each other's private
  records, including by submitting another user's job ID.

- [ ] **09 — Add the public service endpoint.** Use a stable domain, trusted TLS,
  automatic certificate renewal, bounded requests, and a production HTTP service
  behind the existing hosting setup where suitable. Keep administration private.
  Public startup must work without a personal ChatGPT/Codex login. Retire or
  replace account-dependent analysis paths for this mode.
  **Done when:** an authenticated supported request works over ordinary cellular
  access with Tailscale disabled, and protected operations reject unauthenticated
  requests.

- [ ] **10 — Update iPhone onboarding and migrate existing installs.** Replace Mac
  pairing with the selected service-access flow. Update connection/error text,
  permissions, TLS handling, and private-IP exceptions appropriately. Preserve
  offline capture and collection access. Migrate queued jobs without duplicate
  work or lost corrections; map owner data explicitly.
  **Done when:** both a fresh installation and an upgraded existing collection
  work without a QR code, private certificate, VPN, or backend setup by the user.

## Milestone 4: control cost and run unattended

- [ ] **11 — Share a bounded cache by exact market identity.** Reuse fresh results
  across users without sharing private photos, condition, notes, or ownership.
  Normalize serials by print run for ordinary comparable evidence: 12/99 and
  43/99 can share /99 variant evidence, while exceptional-copy premiums require
  separate evidence. Preserve exact product, subset, finish, grade/raw, and
  currency boundaries. Keep the current 24-hour policy initially; verify provider
  terms for public use, purge/refresh, and retained metadata.
  **Done when:** a second user requesting the same fresh exact variant causes no
  additional CardSight calls; different variants remain separate and expired
  results do not appear current. The expiry is our policy, not a claimed
  provider guarantee.

- [ ] **12 — Add request deduplication and enforce budgets.** Cache no-match
  outcomes, combine concurrent lookups for the same identity, and prevent polling,
  reopening, or reconnecting from creating duplicate provider work. Add per-user
  allowances, global limits, bounded fair queues, and predictable quota/outage
  behavior. Decide how allowances are funded before widening access.
  **Done when:** concurrent duplicate scans cause one lookup sequence within its
  cache scope, one user cannot monopolize the service, and exhaustion stops new
  spending. Record actual calls and cost per completed card; one lookup may use
  multiple provider requests.

- [ ] **13 — Add operations, retention, and recovery.** Keep secrets on the server.
  Minimize uploads; send metadata instead of photos when sufficient. Define and
  enforce temporary-photo, job, log, cache, and backup retention. Add private-data
  safe health checks, alerts, automatic service restart, durable jobs, and verified
  backups. Exercise interruption and restore paths before inviting testers.
  **Done when:** jobs recover after restart, deleted/expired data is handled under
  the documented policy, a backup restores successfully, and outages produce
  useful app messages without fabricating identity or price results.

## Milestone 5: TestFlight and App Store release

- [ ] **14 — Prepare privacy, data rights, and store requirements.** Verify current
  requirements for privacy disclosures, retention/deletion, any account deletion,
  third-party processing, and any planned payments. Confirm rights for catalog
  sources, reference images, market data, and branding. Ensure app claims preserve
  the distinction between identification, condition observations, guides, and
  sold-price evidence.
  **Done when:** documentation matches the actual shipped data flow and any
  provider restrictions are implemented, with no unresolved release blockers.

- [ ] **15 — Run an external TestFlight beta.** Test fresh installation by people
  outside the private network, ordinary Wi-Fi/cellular, concurrent users, token
  renewal/revocation, offline recovery, quotas, server restart, and deletion.
  Measure recognition coverage, wrong matches, cache hits, throughput, and actual
  cost. Run the Mac-off test again with Tailscale disabled.
  **Done when:** external testers finish the supported workflow independently,
  user isolation passes, and measured capacity/cost support the chosen beta size.

- [ ] **16 — Release and retire the Mac service.** Prepare the signed release,
  screenshots, support details, review access, deployment/rollback notes, and
  operating runbook. Obtain the separate approvals needed for deployment, device
  installation, and submission. After acceptance of the hosted route, disable the
  Mac launch agent and confirm no production traffic depends on it. Preserve
  rollback data under the agreed retention policy.
  **Done when:** the release is approved for distribution, its backend runs
  unattended, and supported users operate with the Mac shut down. Keep App Store
  submission, Apple approval, and public availability as separate status checks.

The Mac can still build and sign app updates. This plan removes its runtime
backend role. Cloud collection sync, automatic grading, subscriptions, a hosting
purchase, and a model-provider switch are separate scope decisions.

## Starting points in the code

- `App/FastScanView.swift`: current OCR capture.
- `App/AppStore.swift`, `App/MacClient.swift`, `App/Info.plist`: collection state,
  transport, pairing, and platform connection settings.
- `mac/server.py`: shared-token routes, queue, ownership changes, and worker orchestration.
- `mac/analysis.py`, `mac/api_client.py`, `mac/scan_matches.py`: current model dependencies.
- `mac/card_prices.py`, `mac/cardsight.py`: matching, transient caches, and provider quota handling.
- `mac/context_catalog.py`, `mac/catalog_supplement.py`: catalog tooling and loaded checklist data.
- `mac/linux.py`, `server/cardscout.service`: private-server startup and service setup.

Historical context: [private server setup](server-setup.md),
[catalog strategy](context-catalog-strategy.md), and
[market research](cardsight-price-research.md). These documents record previous
work; task 01 must establish the current deployed state.
