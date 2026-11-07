# Scan match and collect experience

The collector scans a card, compares a few likely matches, chooses the right one and adds it to a folder. This is the product direction requested on 16 October 2026. AI supports the choice; collection entry does not require a long automatic identity and market investigation first.

PSA documents [a carousel of likely photo matches with a tap to select](https://www.psacard.com/articles/articleview/11053/snap-to-submit-in-the-psa-app). Its newer [collection experience includes ungraded cards and custom folders](https://www.psacard.com/articles/articleview/15761/raw-cards-psa-app-update). These public flows were reviewed; the native PSA app was not tested in this task. The older scanning article describes a grading-submission flow. Our destination is the user's collection.

## Collector flow

1. **Scan.** Open the camera, frame the front and capture. Import remains available. Save the original immediately as a recoverable draft. Ask for a back or a different angle only when it would resolve a visible difference between candidates.
2. **Choose a match.** Show the user's photo alongside three to five distinct catalog candidates. Each shows its available reference image, product/year, player, card number and exact variant. Highlight the differences in plain words. Allow swipe/browse and tap to choose.
3. **Add to a folder.** Show the selected card, remembered last-used folder and an option to choose or create another folder. One clear “Add to collection” action saves the owned card and folder membership together.
4. **Keep collecting.** Show the new card in the folder and offer “Scan next.” Do not make price research or condition analysis a blocking step.

Suggested German controls: “Welche Karte ist deine?”, “Das ist meine Karte”, “Keine passt”, “Rückseite aufnehmen”, “Ohne Zuordnung speichern”, “Zur Sammlung hinzufügen”, and “Nächste Karte scannen”. Final labels should follow the app's existing German voice.

## Make similar cards easy to compare

For Derrick Harmon #257, show Orange Scope and Fire as separate choices with their actual visual references when available. Explain the numbering difference: a visible 20/79 supports the /79 print tier. It does not establish a parallel without the matching design and release evidence. A candidate contradicted by the visible serial should explain that mismatch and must not be promoted as an exact match.

Use observable labels such as “Name und Nummer passen” or “Oberfläche noch unklar.” Do not turn raw model probabilities into accuracy percentages. Avoid an overwhelming grid of every theoretical parallel. Keep rejected and contradicted suggestions out of the leading choices, while allowing the collector to search the catalog.

When a reference image is missing, show an honest placeholder and textual differences. Never reuse a base photo as if it pictured the exact parallel. Distinguish manufacturer mockups from photos of released cards. The current context catalog still needs reviewed images before this can become a consistently visual experience.

“Keine passt” offers a sharper/back photo, catalog search or an unidentified save. It never forces the nearest wrong match. Unknown photos remain recoverable, including offline or after an app restart. Saving without identity does not fill an exact checklist slot.

## Card identity and folders are separate

The catalog owns a stable identity: release, subset, card number, variant and any serial/configuration distinctions. The owned-card record represents a physical copy with its own photos, notes and serial number. Folder membership is organization chosen by the collector.

A card can belong to “Commanders,” “Rookies,” and “Box 1” without creating three physical copies. Checklist binders can keep their existing set-completion behavior. User folders are additional groupings and must not rewrite a card's identity. Two real copies remain two owned-card records; quantities and duplicate indicators must not hide different serials or conditions.

## How the catalog and models support it

The intended path is capture/OCR hints → catalog lookup → a small set of valid candidate identities → ranking → collector selection. Decisions can rank a bounded candidate set. Slower Luna/Sol investigation is available when no useful choices can be produced or the collector requests help.

Do not combine independent field probabilities into an invented exact-card confidence. Only offer coherent product/subset/card/variant combinations supported by catalog evidence. Always retain “unknown” and a search path. Existing benchmark latency is evidence about those measured workflows, not a promise for this new UI.

The catalog distinguishes imported candidate data from reviewed facts. The UI can present candidates while clearly showing unresolved fields. A collector's selection is recorded as a user assignment, not independent proof that the underlying catalog or reference image is correct. It must not silently enter a verified reference library or benchmark ground truth.

## Implementation boundaries

Build 27 implements this path. Captures stay in `library.cards` with `isScanDraft=true` until the collector confirms a match or explicitly saves unidentified. Drafts are excluded from collection statistics and checklist completion. The original photos remain local and recoverable.

The native match picker supports front/back comparison, five ranked candidates, catalog search, unknown saves, optional folders and later folder edits. Confirmation saves identity, ownership, folder membership and selection provenance in one atomic library write. Provenance records the selected candidate, photo job revision, selection time and checklist source/date; it does not claim an independently reviewed catalog revision. Late model results cannot replace that choice. A repeated save cannot add a duplicate physical record.

Do not rewrite or reassign existing owned cards as part of migration. Preserve their IDs, photos, notes and manual assignments. A folder migration must remain readable when an old library contains no folders.

## Acceptance checks

- A clear card can be scanned, selected and saved to the chosen folder without waiting for pricing.
- Look-alike variants expose their distinguishing evidence; no candidate is pre-confirmed.
- Missing images, unsupported cards and conflicting evidence have a usable search/unknown path.
- Cancelling a match screen does not lose the captured draft or add a false checklist completion.
- Drafts, confirmed selections and folder memberships survive relaunch and offline recovery.
- Repeated taps, reconnects and delayed model results preserve one owned record and the collector's chosen identity.
- Multiple folders do not multiply ownership, quantities or collection value.

Implemented and installed on 16 October 2026. See [build 27 verification](scan-flow-2026-10-16.md). Exact variant reference-image coverage remains incomplete; the UI labels missing artwork instead of substituting base artwork.
