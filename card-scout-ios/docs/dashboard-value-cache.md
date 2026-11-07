# Saved dashboard estimates and counting animation

The Clubhouse and value dashboard use a local `dashboard-values.json` cache in
Application Support. It contains derived owned-card amounts and their saved
classification, scan job and identity. Provider responses and listing evidence
remain transient and stay out of `library.json`.

On the first launch after this change, successful price loads populate the cache.
Later launches display those amounts immediately. Cached entries suppress automatic
price requests until the earlier of the source expiry and 24 hours after saving.
Expired amounts remain visible as saved estimates while background refresh runs.
Transport failures and provider unavailability keep the last known amount. A
completed empty result can remove it. Explicit card-detail price loads still work.

Current values replace cached amounts per card. The displayed estimated collection
value and indicative Burn Count include comparison medians alongside exact-card
prices and guides, within each currency. Unknown amounts are not extrapolated.
The incomplete-value message is removed. Totals use concise estimated-value
labels; operational cache descriptions are not shown. Source-backed historical observations continue
to keep comparisons separate. Fresh derived portfolio entries also support
value history without fetching the same prices again. Corrections, scan revisions,
retakes and collection removals invalidate cached entries. Currencies never mix.

Value, comparison totals and Burn Count count between old and new amounts over
1.1 seconds. Value increases flash green; decreases flash orange. Burn Count
transitions through its existing performance colors. The first displayed amount
starts at the saved value. Reduce Motion disables counting and color animation.
Burn Count can show an indicative balance from available amounts; its approximate
label distinguishes that balance from a complete valuation or manual estimate.
