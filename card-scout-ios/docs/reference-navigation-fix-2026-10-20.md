# Reference comparison navigation fix — build 32

Opening Derrick Harmon's “Variantenbeispiel vergleichen” produced a blank screen, returned to the collection, and left other card links unable to open. This was reproduced in the isolated iOS 26.2 simulator preview with the same card/checklist metadata and demo artwork. The failure did not require the user's original photos. The available iPhone crash-log listing contained no new CardScout crash or Jetsam event for this incident.

The shared `ReferenceComparisonView` created its own `NavigationStack` even when pushed through a `NavigationLink` inside the collection's stack. Removing that nested stack resolved the reproduced failure. Pushed comparisons now use the existing stack. `ReferenceComparisonSheet` supplies a stack and a Done action only for modal callers. Both scan matches and the missing-checklist-card sheet use that wrapper.

Verified interactively in the fixed simulator:

1. Open Harmon → Variantenbeispiel vergleichen. The comparison title, owned demo photo, Josh Allen Orange example metadata and source link appear.
2. Return to Harmon's detail, then return to the collection. Open Joe Mixon and his comparison successfully. Navigation remains responsive.
3. Open a draft's variant-example sheet. Done returns to the same match list with the candidate controls intact.

Signed Release iPhone build 32 and isolated Debug simulator build 32 succeeded. No core, backend, matching or pricing logic changed; validation focused on the failing UI routes. The comparison result does not confirm Harmon's saved variant: his existing Orange /79 mismatch still belongs in the identity review queue.

Device installation: build 32 installed successfully on the iPhone. iOS blocked automated launch because the device was locked. The complete navigation regression was verified in the simulator; the physical-phone flow still needs a user check after unlock.
