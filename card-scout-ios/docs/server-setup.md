# Private Linux research worker

The iPhone can use this server instead of the Mac. It keeps the same pinned-TLS
pairing protocol, durable queue, photo-only identification and researched valuation.
The iPhone keeps its library and original photos. This is not collection sync or a
photo backup. The Mac is still used to build/install iOS updates.

## Hosting choice (researched 16 October 2026)

Selected route: use the user's existing **Hostinger VPS**. Inspect its current
services, resources, firewall and SSH access before installing. Do not reimage,
reset, upgrade the hosting plan or interrupt unrelated workloads. The supplied
installer targets a dedicated Ubuntu 24.04 VM; on a shared VPS, review package,
user and service changes first. A Hostinger account alone is insufficient, but
the user has confirmed they have a VPS. No new hosting purchase is needed.

The existing VPS was inspected through Hostinger and SSH on 16 October: Ubuntu
24.04, x86_64, KVM 1 with 4 GB RAM and 50 GB disk. About 3 GB RAM and 40 GB disk
were available. Caddy and other applications were already running. The isolated
worker and Codex CLI 0.160.1 were installed under `/opt/cardscout`, with the
service stopped pending login/private-network setup. Existing Node 24.20.0 was
preserved. Tailscale was installed from its official repository. Account login,
service startup and phone acceptance must be verified separately below.

The VPS initially rejected Codex's bundled Bubblewrap helper under Ubuntu's
AppArmor user-namespace restriction. The installer now adds the distro Bubblewrap
package and, where needed, loads the extra `bwrap-userns-restrict` profile from
Ubuntu's `apparmor-profiles` package. It never sets the global restriction to 0.
A sandbox preflight runs under the systemd service restrictions before research
is enabled. See [OpenAI's Ubuntu sandbox prerequisites](https://learn.chatgpt.com/docs/sandboxing#prerequisites).

Verified: the sandbox preflight passed on the real VPS with the service's
NoNewPrivileges, ProtectSystem, ProtectHome, PrivateTmp and writable-data rules.
The global AppArmor user-namespace restriction remained set to 1. The service
unit passed `systemd-analyze verify`. Existing Caddy stayed active and Node's
version did not change. The initial device-code login was blocked because the
user could not find the required account setting. Normal browser login through
an SSH callback tunnel succeeded. The CLI reported successful login and the
isolated helper independently verified it. Tailscale confirmed the VPS and
iPhone connected. The service is enabled for boot and runs only on its
Tailscale IPv4. Authenticated HTTPS health passed; TCP 8743 on the public IP was
closed. A real photo completed identification, full research and the configured
Sol fallback, ending in `analyzed` with five market references. SportsCardsPro
was found, eBay was unavailable and PSA had no matching graded context. The card
remained medium confidence; the test did not establish its exact variant or a
verified eBay sale. Physical-iPhone pairing/scanning and long-term token renewal
remain separate acceptance checks.

The Mac worker was briefly stopped for a locked SQLite backup, then restarted
for fallback. Its snapshot was validated and activated on the VPS: 212 analyzed,
eight failed and one cancelled job, plus 30 collections. The CardSight key and
existing usage ledger were transferred privately; expired market caches were
not carried over. The VPS login directory, certificate and pairing were kept.
Login, health, record counts and key readability all passed after the service
restart. Temporary archives, staging data and test-photo copies were removed.
The original Mac state remains available for rollback. This operational move
did not uninstall its launch agent or alter the iPhone library.

## New iPhone installation — 16 October

The connected iPhone 17 Pro did not have `com.tobiaslatta.cardscout` installed.
The user chose to start without the old collection. The server's `legacy.json`
was moved to a private file outside the live data directory so first connection
will not automatically import the old photo/card. Historical queue/checklists
and the original Mac data remain intact.

A signed generic-device Release build succeeded, but installation was rejected
because its provisioning profile did not include the new iPhone. A targeted
build with device-registration permission then reached Apple's membership
gate: **PLA Update available**. The user accepted the latest Program License
Agreement in their own account. The targeted Release build then succeeded;
its profile was verified to include the connected iPhone and expires on
16 October 2027. Card Scout 1.1 (14) was installed and launched successfully.
The private server pairing URL was delivered directly to the app without
printing the credential. The user confirmed the server in the app.
No existing app data was deleted to work around the signing error.

## Physical-iPhone connection fix — 16 October

The first connection stayed offline without a visible error. A connection-only
diagnostic file established that pairing was saved but URLSession returned
`NSURLErrorDomain/-1200`. Certificate pinning and trust evaluation both passed;
the diagnostic stage was `accepted`. iOS still applied ATS requirements to the
explicit private IP despite `NSAllowsLocalNetworking`.

The app now has an ATS exception limited to **100.87.203.45**, allowing its
existing manual pinned self-signed trust evaluation for this endpoint. There is
no global arbitrary-load exception. MacClient independently requires HTTPS,
TLS 1.2 or newer, the exact paired leaf fingerprint, hostname/validity checks
and no redirects. A changed private server IP requires updating that narrow
exception as well as pairing/certificate configuration. See
[Apple's manual trust guidance](https://developer.apple.com/documentation/foundation/performing-manual-server-trust-authentication).

Network failures now appear inline in the connection screen. The private
`connection-status.json` contains only pairing/connected flags, host, timestamps,
stage names and numeric error codes. It contains no tokens, certificate hashes,
full URLs, photos or collection records. A broad app-container copy was rejected
by automatic approval review; diagnosis proceeded by retrieving only this
purpose-built file.

The corrected signed Release build was installed without deleting app data.
The physical iPhone then reported `paired=true`, `connected=true`,
`trustStage=accepted` for the VPS. This verifies the phone's authenticated HTTPS
connection, not just reachability from the server. A new phone-originated card
capture and long-term token renewal remain untested; the separate real-server
identification/research test above completed successfully.

Local validation: 111 Python tests passed in an ARM64 Debian Linux container,
including the copied install bundle import smoke test; Codex CLI 0.160.1 installed
and accepted the worker command flags there. Swift Core: 73 tests, one skipped,
zero failures. The iOS simulator build succeeded. None of these checks establish
a phone-to-VPS connection or unattended token renewal. After adding the normal
browser-login option, the complete Mac Python suite passed 112 tests.

Railway also belongs to the user, but its volume support alone does not establish
that the existing Codex read-only Linux sandbox can run there. Railway has not
been validated as a deployment target. Prefer the VPS for this implementation.

The original new-server comparison below is retained only as a price reference.
Use a small Ubuntu 24.04 LTS VM in Germany. No GPU is needed; Codex calls remote
models. Start with 2 vCPU and 4 GB RAM. Actual latency, model availability and
memory use still need a real-server trial.

Hetzner CX23: 2 vCPU, 4 GB, 40 GB disk; listed at €6.53/month including 19% German
VAT, excluding IPv4 and backups. Its public product page currently reports it
unavailable. Check the console before ordering. CAX11 (ARM64) is listed at
€7.13/month including VAT; use it only after confirming the pinned Codex package
installs on that image. CX33 is another x86 option at €10.10/month including VAT.
No server has been ordered, and no region's live capacity has been verified.

Sources:

- [Hetzner plans and availability](https://www.hetzner.com/cloud/cost-optimized/)
- [Hetzner June 2026 price list](https://docs.hetzner.com/de/general/infrastructure-and-availability/price-adjustment/)
- [IPv4 pricing](https://docs.hetzner.com/general/infrastructure-and-availability/ipv4-pricing/)

## Private network

Install [Tailscale on the server](https://tailscale.com/docs/install/linux) and
[on the iPhone](https://tailscale.com/docs/install/ios), then sign both into your
private tailnet. Tailscale must be connected on the phone while uploading or
fetching results. This introduces a VPN app/account requirement.

Use a dedicated VM and SSH keys. In the provider firewall, allow SSH only from
your admin address and optionally UDP 41641 for Tailscale direct connections.
Keep outbound internet allowed. **Do not expose TCP 8743 to the public internet.**
The worker binds only to its Tailscale IPv4; it rejects wildcard, public and LAN
addresses. Limit access to your devices in the tailnet policy. Do not use Funnel.
Review server node key expiry in Tailscale so the connection does not stop
unexpectedly; the TLS certificate separately expires after one year and then
needs renewal and re-pairing.

## Install and sign in

Copy this `card-scout-ios` source directory to the server over SSH. Do not copy
Mac credentials, personal Codex settings or runtime secrets into the source tree.
On the server, from that directory:

```sh
tailscale ip -4
sudo bash server/install-linux.sh 100.100.100.10
```

Replace the example IP with the actual Tailscale IPv4. The installer creates a
dedicated `cardscout` service user, installs Codex CLI **0.160.1**, creates a
private certificate and persistent queue directory, and installs a systemd unit.
It does not start the worker before login. Reinstalling stops an existing worker;
run the start command below after any update.

Enable device-code login in your ChatGPT security settings if necessary. Then:

```sh
sudo -u cardscout -H python3 /opt/cardscout/service/linux.py login
```

If that setting is absent, use the normal browser login through an SSH callback
tunnel. From the Mac (keep this terminal session open):

```sh
ssh -o ExitOnForwardFailure=yes -L 127.0.0.1:1455:127.0.0.1:1455 root@YOUR_VPS \
  'cd /var/lib/cardscout && sudo -u cardscout -H python3 /opt/cardscout/service/linux.py login --browser'
```

Open the official authorization URL printed by Codex in the **Mac's browser**
and finish the sign-in/consent there. The callback forwards through SSH to the
VPS. Do not open this URL on the iPhone: its localhost cannot reach the Mac's
tunnel. No device-code account setting is required for this fallback. It is
[documented by OpenAI](https://learn.chatgpt.com/docs/auth#fallback-forward-the-localhost-callback-over-ssh).
This route was prepared after the user reported the Security setting absent.

Open the official URL printed in that terminal, sign in with your ChatGPT account
and enter the one-time code. The password and approval stay in OpenAI's login
flow. Do not paste account credentials into chat. This uses the
[documented Codex device login](https://learn.chatgpt.com/docs/auth#login-on-headless-devices).
OpenAI recommends API keys as the default for automation; this private worker
deliberately retains ChatGPT login as requested. Subscription limits and account
availability still apply to Codex. The initial setup is CLI-only. The later, explicitly enabled [hybrid route](hybrid-routing.md) uses a separate server-side API key for Luna Fast and retains ChatGPT login for Sol; it is not an automatic paid fallback.

```sh
sudo -u cardscout -H python3 /opt/cardscout/service/linux.py check
sudo systemctl enable --now cardscout.service
sudo systemctl status cardscout.service
```

The login and worker use the same isolated `/var/lib/cardscout/data/codex` store,
with mode 0700 and private auth files. The store stays on disk across service
restarts and reboots. Codex handles token refresh. If the account requires a new
login, stop the worker, repeat login, then `systemctl reset-failed cardscout` and
`systemctl start cardscout`. No login endpoint is exposed to the network.

## Pair the phone

Before switching, connect to the Mac once and let current uploads/results finish.
Do not remove the iPhone app. Check that the collection opens offline.

```sh
sudo -u cardscout -H python3 /opt/cardscout/service/linux.py pair
```

This explicitly prints a **secret pairing link** to your own terminal. Copy it
privately to the iPhone's connection screen, tap **Code öffnen**, check the host,
then confirm. The current app already accepts an HTTPS IP address and pins the
certificate. No iOS update is needed for pairing; the updated source also uses
Mac/server wording. Treat the link as a password and do not put it in logs/chat.

The server starts with bundled checklists. Saved cards, notes, photos and binders
stay on the phone. Already-uploaded unfinished jobs missing on the new worker
are resubmitted from the phone when polled. However, pending acknowledgments,
custom checklists and server-owned previous analyses require care when moving:
finish/acknowledge current jobs on the Mac first. If there are old pending acks
or user-added checklists, migrate the stopped worker's queue/catalog before
switching; don't simply reset the phone or copy a live SQLite database. Full
worker-data migration is not automated by this installer.

The CardSight ranking key is a separate credential. It is **not** copied by
ChatGPT login. It and the existing usage ledger were migrated separately for
this VPS. On a fresh install, configure both privately before enabling provider
refreshes; bundled chase entries and Codex card research are separate. Preserve
the existing provider quota/cache rules. Do not purchase a new plan or reset
local quota accounting as part of moving the worker.

## Acceptance and rollback

Before retiring the Mac worker:

1. Verify `/v1/ping` through the iPhone's connection check.
2. Scan a card over mobile data with Tailscale on and the Mac asleep.
3. Confirm identification, German assessment, researched prices/sources or an
   explicit missing-price result; check collection assignment and original photos.
4. Close the app after upload. Reopen it and verify the finished result saves.
5. Restart the service, then reboot the VM. Verify login persistence and a new scan.
6. Confirm port 8743 is not reachable through the server's public IP.

These real-server and physical-iPhone checks are not established by local tests.
Keep the existing model route. A new machine does not guarantee the same model
access or web-source access. Resolve failures before changing models or shipping.

Rollback: re-pair the iPhone to the original Mac using its private pairing link.
The server can be stopped with `sudo systemctl disable --now cardscout`.
Stopping the VM does not cancel hosting charges; delete it only after preserving
needed data. Server backups contain credentials and temporary photos and must
remain private. Temporary uploaded photos are deleted after the phone saves and
acknowledges results, as with the Mac worker.

## Camera and player-name regression check (2026-10-16)

The first three physical-phone scans reached the VPS but were optically blurred.
The Ferguson and Wirfs cards were incorrectly labelled Tutu Atwell and Travis
Kelce; Kyle Pitts was correct. The capture driver previously selected only the
physical wide-angle camera. It now prefers a virtual triple/dual-wide camera,
allows automatic lens switching, uses continuous centre autofocus/exposure and
quality-prioritized still capture. Automatic capture requires focus/exposure to
settle before the rectangle stability timer can trigger. Manual capture reports
when focus is still adjusting. This requires fresh physical-device photos to
verify; it cannot restore detail in existing blurred photos.

Quick recognition now asks for the printed player-name evidence. Conflicting or
missing name evidence and all low-confidence player guesses are discarded.
Full photo analysis applies the same guard; confirmed manual checklist assignments
remain authoritative. Unconfirmed scan results are explicitly labelled provisional
on the phone. Name evidence is internal and is stripped before persistence.
This is a conservative guard, not a guarantee of correct medium/high-confidence
identification: the model can still misread printed text.

Live regression on the exact three old photos after the guard: Ferguson -> null
(low confidence), Wirfs -> Tristan Wirfs, Pitts -> Kyle Pitts. These diagnostic
runs did not overwrite collection entries. Existing incorrect entries need a
retake/correction; do not silently edit them from test ground truth. Temporary
diagnostic copies were removed after the check. Local validation: 117 Python
tests passed; 74 Swift core tests ran (one skipped), physical signed build and
installation passed. The phone's narrow connection diagnostic remained reachable.

Physical-camera acceptance: user confirmed the updated camera is sharp and the
new Wirfs scan is correctly recognized. This verifies the repaired capture path
on this iPhone, not accuracy across all cards. Fresh Ferguson retake remains an
available follow-up; the old blurred Ferguson result is not a successful ID.

## User-requested fresh collection (2026-10-16, build 16)

Reset operation `5d8d385a-1bcf-4967-bdc6-0002f8e1d931` cleared the five
current iPhone cards and active local photos. App Support sibling directory
`CardScout-ResetBackups/<operation-id>/` on the iPhone retains the old
`library.json` and `photos/` privately for recovery. The active library sets
`importedLegacy=true`, has no owned cards/binders/acknowledgements or superseded
jobs, and cannot bootstrap old cards back into the fresh collection. Pairing in
Keychain is retained. A repeated maintenance launch with the same operation UUID
is idempotent and must never delete captures made after this reset.

The VPS was stopped first. Its 226 historical/current queue rows and jobs folder
were moved to `/var/lib/cardscout/reset-backups/<operation-id>/` (private root
permissions) before a fresh queue was created. Product checklist/catalog data,
provider quotas/cache, TLS, pairing and ChatGPT authentication were retained.
After normal app relaunch: zero active phone cards, zero server jobs/transport
photos, authenticated server reachable, ChatGPT login intact. Restoring requires
stopping the worker/phone sync and restoring both corresponding backups; do not
copy credentials, reset quota accounting, or automatically restore old cards.

Maintenance launch: `devicectl ... process launch ... com.tobiaslatta.cardscout --
--reset-collection <new UUID>`. Only use after an explicit user request to reset.
No reset is triggered by normal app launches. Core regression verifies backup,
cleared acknowledgements/photos and repeat-launch safety (77 tests, one skipped).
