# Guided identity review — build 23

`Zuordnung prüfen` on a card now opens a guided review instead of the manual collection picker. It shows missing structured identity fields, whether the saved back is absent, and the actual uncertainty notes from the latest analysis. It does not invent a variant, confirm an identity, or require the collector to know a set.

The next steps are `Rückseite ergänzen` / `Rückseite neu aufnehmen` and `Vorderseite neu aufnehmen`. A missing back is suggested first; with both sides present, an unreadable player name suggests the front, while a missing year or card number suggests the back. Variant-only uncertainty remains visible and suggests a clearer front. These suggestions are photo guidance, not promises that another photo will resolve a missing checklist match.

Each action opens capture focused on that side and starts the portrait camera when available. Photo-library import remains available when the camera is unavailable or access is denied. The collector reviews the photo, then saves it. Existing retake storage replaces only that side, keeps the stable owned-card ID, invalidates the old analysis, and queues new identification automatically. Closing or canceling does not replace photos or confirm anything. The guide shows pending state while the result is being checked, then either the latest unresolved details or confirmation. The guide can be closed at any time.

`Ich kenne die genaue Karte` remains an optional manual route. Its picker now says `Kartenset` rather than `Sammlung`, and explains that saving confirms the identity and requires the year, set, variant, and number to agree.

No backend, model, pricing, or quota code changed. The live route was checked as GPT-6 Luna, CardSight enabled, paid search disabled, no model fallback, monthly hard cap 720. Price research retains its strict exact-identity gate and shared budget ledger.

Validation: 110 core tests (109 passed, one optional live-cache check skipped), including six guide tests and the existing retake/persistence protections. Signed iPhone build succeeded. Guided camera interactions still need a physical user check; build and core tests do not establish an end-to-end camera capture.
