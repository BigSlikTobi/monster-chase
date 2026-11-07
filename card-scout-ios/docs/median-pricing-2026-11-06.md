# Median pricing — build 40

Comparison estimates previously showed the lowest and highest comparison prices
as the headline and used the midpoint of that range for sorting. Three €1 cards
and one €8 card therefore displayed €1–€8 and sorted at €4.50.

The headline now shows **ca. €1** with **Vergleichsmedian · 4 Karten · geringe
Sicherheit**. The full comparison range remains a smaller supporting detail and
the evidence links remain available. These are other players' cards, so this is
still a rough comparison, not a verified sale price for the owned card.

Each comparison card contributes one value. A sold price contributes its amount;
a ranged guide contributes its midpoint. The median is the middle sorted value,
or the mean of the two middle values for an even sample. Display rounds to cents.
Sorting uses the unrounded median. Collection indicators use the rounded median
instead of summing range endpoints. The older uncertain-variant sales indicator
also uses a median rather than an arithmetic mean.

Exact-card sales already used a median and retain their sale count and observed
range. A source guide's own range remains a range. Currencies and shipping bases
stay separate. Comparison freshness, distinct-card checks and non-persistence
remain unchanged. No backend migration or fresh provider lookup is required.

## Verification

The regression tests reproduced the previous range headline, €4.50 sorting and
mean-based fallback before the fix. Coverage includes the €1/€1/€1/€8 example,
odd/even and unordered samples, ranged guides, cent rounding, expired comparison
evidence, exact-sale behavior, and exclusion of comparisons from confirmed totals.

- Swift core: 158 tests executed, one skipped, zero failures.
- Signed Release iPhone build 40 succeeded.
- Installed on the paired iPhone 17 Pro. The collection file was byte-for-byte
  unchanged across installation: 46 cards, their analyses and photo references,
  and 57 collections retained. This check did not rehash the photo files.
- The app launched successfully through CoreDevice. Physical screen layout and
  real-card pricing accuracy were not independently verified; test prices are fixtures.
