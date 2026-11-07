# Fresh collection and scan workflow — builds 33–39

The previous flow could turn a wrong first-pass year, subset or finish into a hard
filter, hiding the correct checklist entry. Every completed photo pair also opened
a comparison sheet. That combined recognition failures with repeated user work.

## Capture and collection

- Build 39 addresses another auto-capture stall. Build 38 on the physical phone
  still contained build 36's motion tolerance; those changes were not overwritten.
  However, an autofocus pulse erased the movement window, and the driver applied
  a new 0.12-second delay after every observed pulse. The gate now tracks acceptable
  rectangles while focusing and permits capture only when hardware focus is ready.
  Framing quality is independent of focus readiness. The short delay remains only
  after explicit focus requests, light changes and session startup. Rectangle loss
  during focusing still does not establish card removal.
  A bounded local `capture-status.json` records build, camera/auto/saving state,
  card detection, focus, removal wait and readiness at most once per second during
  guidance, plus saving/stop transitions. It contains no photos, OCR, player names,
  coordinates or credentials and is never sent over the network by the app.
- Build 37 fixes the misunderstood back-capture flow: with **Auto an**, the back
  now captures automatically too. After the front is saved, briefly remove the
  card from the viewfinder, flip it and return the back to view. The same removal
  latch guards both sides, so merely leaving the front visible cannot capture it
  again as the back. If the flip did not clear the latch, the status explicitly
  asks for card removal. Manual shutter capture remains available.
  The camera disables automatic screen locking only while active. Stopping it
  for navigation, sheets or background restores normal auto-lock. A late camera
  startup callback cannot re-enable the keep-awake flag after stopping.
- Build 36 responds to the physical report that automatic capture demanded
  unrealistic stillness. Detection runs at roughly 0.12-second intervals instead
  of 0.3; an acceptable movement window is 0.12 seconds instead of 0.45. Consecutive
  detected rectangles can drift gently, with size-relative displacement and speed
  limits rejecting rapid movement. Gaps over one second restart the window.
  Continuous exposure adjustment no longer resets the focus delay; actual focus
  adjustment still blocks capture. The focus delay is 0.12 seconds. These are
  usability heuristics, not a measured image-sharpness guarantee. The existing
  removal latch still permits only one front until the card has left the frame.
- Build 35 adds **Licht an/aus** beside the capture controls for both sides and
  Single/Stack modes. The camera owns the torch on its serial capture queue, uses
  a moderate 0.35 level and reports hardware state. The button is disabled during
  capture or when the torch is unavailable. Changing light restarts the focus
  delay before the next automatic capture. Stopping the camera switches the
  torch off; the setting is not persisted across camera sessions.
- **Einzeln** keeps immediate comparison after each front/back pair.
- **Stapel** requires both sides, saves the pair into the collection and immediately
  returns to the next front. Identification and assessment use the existing fast
  worker route. No candidate-selection sheet or add-to-collection form is required
  for every card. Uncertain cards remain unconfirmed and do not fill binder slots.
- The selected mode is stored with the pending front. Restarting the app preserves
  that pair and its route. A stack pair cannot be released as front-only.
- Both sides can be automatic in build 37. After either side, automatic capture
  waits for card removal before accepting another photo. Switching modes does not
  reset this latch.
- Build 34 automatic capture waits for a complete detected card, sufficient frame
  coverage, settled focus and stable framing. Preview OCR is no longer a
  shutter requirement: small print or failed live recognition cannot block a usable
  photo. Accurate OCR still runs on the captured JPEG and supplies analysis hints.
  This remains a live heuristic, not a calibrated sharpness or glare detector.
  Manual capture remains available. Guidance identifies framing, distance or focus.
  Enlarging a sharp image can help read small print; it cannot recover missing detail
  from blur. The stored photo and existing analysis resolution are unchanged.
- The session separates saved pairs, recognized cards, processing and actual review.
  Offline capture is still local; server work requires a connection and an active app.
- Saving a single scan without a match preserves its provisional identity fields.
  It clears confirmation, slot ownership and price/assessment claims. Old responses
  cannot overwrite that explicit decision.

## Recognition

- Candidate retrieval accepts independent on-device OCR and conservative name
  spelling similarity. Product/year/subset/finish rank alternatives rather than
  excluding them after an early wrong guess. No-evidence searches stay empty.
- OCR can retrieve sourced checklist excerpts during the first photo-only pass.
  Full assessment receives a bounded set of sourced, complete-checklist alternatives
  across plausible years and finishes. There is no extra model call for retrieval.
- Recovered server suggestions remain visible on the phone even when both original
  name and number guesses were wrong. Suggestions never establish ownership.
- The backend now also rejects the already-reviewed 2025 Optic Orange /299 versus
  Orange Scope /79 conflicts and Blue Hyper/Purple Shock veteran-number conflicts.
  These are narrow release checks, not universal variant validation.
- Review distinguishes missing catalog evidence from incomplete identity and
  unresolved variants. Failed processing and catalog gaps do not request new photos.
  Specific missing/unreadable details get side-specific guidance; replacement remains
  available as an explicit secondary action.

Catalog gaps still require verified catalog additions. This change does not add
every product or parallel, enable automatic catalog publication, or establish a
new measured recognition-accuracy rate. Unreadable photos can still need recapture.

## Reset and rollout

The user explicitly requested the entire collection be cleared. Operation
`19719605-2d37-484d-a025-4728e61720df` removed 46 active phone cards and their active
photos. The built-in reset retained a recovery copy in the phone's Application
Support sibling `CardScout-ResetBackups/<operation-id>/`.

The server's 161 historical scan records and job files were archived in
`/var/lib/cardscout/reset-backups/<operation-id>/`. The fresh queue has zero jobs.
Catalogs, provider quota accounting, keys, TLS and pairing were retained. A normal
phone relaunch confirmed zero cards, no pending acknowledgements, no superseded
jobs and `importedLegacy=true`, preventing old bootstrap data from returning.

Backend deployment retained its previous three modules in
`/var/lib/cardscout/backups/scan-20261106-build33/`. The active source baseline was
checked before replacement. Authenticated pinned-certificate HTTPS health passed;
the queue remained empty and retained configuration/catalog files were verified.
No live model evaluation or price lookup was used for verification.

## Validation

- Build 39: the new autofocus-pulse regression failed before the fix. After the
  fix, 150 Swift tests executed with one skipped and zero failures. This verifies
  the modeled autofocus interruption, not the user's physical capture experience.
  Signed device build succeeded and build 39 was installed on the paired iPhone.
- Build 37: 149 Swift core tests executed, one skipped, zero failures, including
  an automatic front/removal/back sequence that rejects a repeated front.
  Signed device build succeeded and was installed on the paired iPhone.
  Real-camera flip timing and remaining awake through the device's auto-lock
  interval remain physical acceptance checks.
- Build 36: 148 Swift core tests executed, one skipped, zero failures. New/updated
  sequences cover handheld jitter and drift, rapid movement within positional
  tolerance, long detection gaps, focus interruption and one capture per card.
  Signed device build succeeded and was installed on the paired iPhone. Physical
  handheld acceptance remains open; no new real-card scan was claimed by tests.
- Build 35 signed device build succeeded and was installed on the paired iPhone.
  The lamp hardware, actual illumination and reflective-card usability remain
  physical acceptance checks; a successful build/install is not proof of those.
- Build 34: 146 Swift core tests executed, one skipped, zero failures. Regression
  coverage verifies capture readiness without preview OCR, continued focus/size
  gating, stable triggering and the existing duplicate-capture latch. Signed device
  build succeeded; build 34 installed and launched on the paired iPhone. Physical
  camera behavior with the user's Bowman cards still needs user acceptance.
- Backend: 235 tests passed locally; 47 targeted matching/identity tests also passed
  under the server's Python runtime before activation.
- Swift core: 145 tests executed, one optional test skipped, zero failures.
- Signed Release iPhone build 33 and isolated Debug simulator build 33 succeeded.
- Simulator: Single/Stack switching, stack import restrictions and visible shutter
  verified. A layout issue found during inspection was corrected before installation.
- Build 33 installed and launched on the paired iPhone without another collection
  reset. The post-install library still has zero cards and `importedLegacy=true`.
- Initial phone connection check timed out (`NSURLErrorDomain/-1001`, before TLS).
  Server-side authenticated HTTPS health passed. Phone pairing remains saved;
  the registered iPhone was offline in Tailscale. After the user reconnected it,
  the phone diagnostic at 18:58 CET confirmed `connected=true`, `stage=reachable`,
  `trustStage=accepted`, and no connection error. The fresh library contains zero
  cards and 55 synced checklists; the server queue is empty. This verifies phone
  connectivity and checklist sync, not a new physical card scan.

Still needed: a physical 20-card trial with correct reference identities, including
glare, look-alike variants, interrupted pairs and card removal between captures.
Measure correct identities without intervention, wrong identities, unresolved
cards, extra photos and total time including corrections. Unit tests and simulator
layout checks do not establish real-camera accuracy or throughput.
