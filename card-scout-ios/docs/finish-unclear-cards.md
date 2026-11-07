# Finish unclear cards — build 24

The collection screen now offers `Offene Karten fertigstellen`. An unfinished pass shows `Offene Karten fortsetzen` instead. Starting or resuming saves the queue locally; it does not send photos, call Luna, or request prices.

Each step shows the saved front photo (tap to enlarge), available identity details, missing fields, and the existing guided front/back actions. Save a new side using `Speichern & neu analysieren`: the same collection card receives a new photo/analysis revision, the analysis runs through the normal queue, and the next card opens after the photo sheet closes. Canceling or failing to save leaves the current step unchanged. No collection selection is required.

`Überspringen` leaves the card unresolved and advances within this pass. `Schließen` keeps progress for later, including after app restart. The end screen reports saved-photo, skipped, and no-longer-needed counts without claiming that the cards have been identified or priced. Skipped cards and still-unclear results can be included when the collector explicitly starts another pass.

`UnclearCardQueue` snapshots stable owned-card IDs, not changing analysis job IDs. Only non-running analyzed/failed cards whose identity is unconfirmed qualify. Confirmed cards with missing prices or other review notes are excluded. A pass does not grow when new cards arrive or results remain unclear. Resume filters out deleted, confirmed, or already-running entries. The photo revision and current queue advance are persisted in the same atomic library save. Stale callbacks cannot skip or complete a different card.

The queue is an optional `Library` field, preserving compatibility with existing libraries. It contains only collection card IDs and progress; no additional photo or provider cache is created. Retaking an unrelated card does not advance the current step. The existing offline upload, result revision checks, transient pricing, and private TLS path remain in use.

No backend or model configuration changed. Live checks confirmed GPT-6 Luna, CardSight enabled with its existing exact-match gate, monthly cap 720, paid search disabled, and no automatic model/search fallback.

Validation: 116 core tests, 115 passed and one optional live-cache check skipped. New queue tests cover target selection, durable photo/advance commits, cancellation, resume/reconciliation, stale callbacks, no repeated unresolved results, and old-library decoding. Signed iPhone build succeeded. The real camera-to-next-card interaction remains a physical user check.
