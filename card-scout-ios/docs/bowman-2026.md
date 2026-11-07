# 2026 Bowman Football

## College recognition repair — deployed 6 November 2026

The live-worker audit on 6 November found college prospects marked `unlicensed`
because the schema and prompts required NFL/NFLPA licensing. Missing prospect
rows also caused inconsistent subset names and unnecessary checklist review.

The repair adds a separate `college` license scope and imports both
prospect sections from the same pinned official PDF. The source edition is now
`2026-bowman-football-base`; the loader still accepts the older NFL-only edition.

| Family | Numbers | Rows |
| --- | --- | ---: |
| Base | 1–200, excluding unresolved 66/68 | 198 |
| Chrome Base | BCV-1–BCV-200 | 200 |
| Paper Prospects | BPP-1–BPP-200 and BPP-ALT1 | 201 |
| Chrome Prospects | BCP-1–BCP-200 and ALT-1 | 201 |

Exact paper prospect aliases normalize only within 2026 Topps Bowman with a
BPP-prefixed number. Family/number and NFL/college license conflicts block
confirmation. University products, other years, parallels and inserts remain
separate. A 1st Bowman mark is not treated as an NFL rookie mark.

Sourced rows from incomplete checklists can now reach the model as candidates;
their incomplete status is retained. This restores NFL paper evidence without
exposing the quarantined conflicting rows or declaring the binder complete.

The app displays `college` as College. Its existing bounded support recheck can
also target a completed card whose identity was confirmed but whose license
still needs review. It reinspects saved photos, preserves manual assignments,
and cannot repeat the same old-job batch. No automatic collection-wide recheck
or confidence upgrade was introduced.

Verification: 253 Python worker tests passed. College regressions cover both
families, alternate Arch Manning numbers, full and fast validation, aliases,
wrong products/prefixes/licenses, repeat merges and restart persistence.
The Swift suite executed 159 tests, one skipped, with zero failures. The signed
iPhone build succeeded and was installed on MyApple after explicit approval.

The user approved deployment to `srv1216403.hstgr.cloud`, then separately
approved installing the tested app and rechecking the remaining saved cards.
The worker update was installed at 20:52:54 UTC. The prior modules, runtime
supplement and SQLite snapshot are backed up under
`/var/lib/cardscout/data/upgrade-backups/bowman-college-20261106T205254Z`.
The graceful restart retained all 60 saved job records; the saved assessment
digest was unchanged at deployment. Active work was requeued durably.
Configuration, credentials, TLS identity and pairing hashes were unchanged.

Authenticated, certificate-validated HTTPS health passed. The live checklist
endpoint returned all four families above. All three deployed module hashes
matched the tested local files. Live candidate retrieval returned paper
Jaron Tibbs #BPP-72 and Chrome Alex Perry #BCP-43 in their correct families.

The installed app initially queued 12 affected college cards for reinspection
from their original saved photos. The updated app then queued the remaining
three cards whose identities were high confidence but whose licensing had been
wrongly blocked. Existing manual choices were excluded from the support batch.

The final iPhone library snapshot at 20:56:31 UTC confirmed **15/15 targeted
cards analyzed, high-confidence identity confirmed, `licenseScope=college`,
and `needsReview=false`**. This is original-saved-photo model evidence, not a
claim about every future camera capture. All **46 owned card IDs**, front/back
photo references and manual-assignment flags matched the pre-install snapshot.
The phone received all four Bowman families, including 402 prospect rows.
Its 20:56:24 UTC connection receipt confirmed connected, writable, paired state
and accepted certificate trust. The observed batch used GPT-6 Luna and recorded
zero web-search calls. No grading or price-availability claim follows from
successful identification.

## Earlier NFL-only deployment

The worker now loads the official NFL paper and Chrome base checklists through
`catalog_supplement.load_all`. Both Mac setup and Linux installation ship the
supplement. The existing app receives these collections through its worker;
no Swift model or owned-card migration is required.

## Identity

| Manufacturer | Product | Subset | Numbers | Imported rows | Complete |
| --- | --- | --- | --- | ---: | --- |
| Topps | Bowman | Base | 1–200 | 198 | No |
| Topps | Bowman | Chrome Base | BCV-1–BCV-200 | 200 | Yes |

The photographed KC Concepcion is paper #131 (Cleveland Browns, rookie).
Justin Jefferson is Chrome #BCV-69 (Minnesota Vikings, veteran). This identifies
their checklist families, not Jefferson's exact finish. A Chrome logo does not
prove a Refractor parallel. User photos were inspected as evidence and were not
added to the reference library or saved as owned cards by this change.

## Source and conflict

Source: [Topps release page](https://www.topps.com/pages/bowman-football), linking
the [official checklist](https://cdn.shopify.com/s/files/1/0662/9749/5709/files/2026_Bowman_Football_Checklist.pdf?v=1790867994).
Fetched 6 November 2026. SHA256:
`acc2dadf884b603f889445367671b6817eebb1f51a0101d7c014a946cd1a1b6b`.

The paper NFL section prints #68 for both Tua Tagovailoa and Jaylen Waddle,
and omits #66. Both conflicting #68 rows are quarantined in the supplement.
No corrected number is inferred from Chrome. Paper stays incomplete at 198/200.
Teams are printed checklist facts, not current-roster assertions.

Reproduce from the exact pinned PDF:

```bash
python3 mac/import_bowman_checklist.py /path/to/checklist.pdf \
  mac/data/bowman-checklist-supplement.json --checked-at 2026-11-06
```

The importer rejects changed PDF bytes, section counts and numbering. The loader
validates release, subset, expected membership and completeness. Existing rows,
reference artwork and collector assignments are preserved; conflicts are reported.

## Coverage and verification

This addition covers the two NFL base families. College prospects, inserts,
autographs and parallel membership remain outside this supplement. Identification
instructions explicitly distinguish paper, Chrome and college licensing. Existing
general research can investigate other families; this addition does not claim a
complete all-variant catalog. No new CardSight ranking release ID, pricing adapter,
price, licensed prospect claim or reference artwork was invented.

All 240 Python worker tests passed, including five Bowman tests covering both
photographed identities, cross-family rejection, source conflicts, repeat merges,
parser changes and repository restart loading. These tests validate catalog and
pipeline behavior with structured identities; they do not measure photo-model
accuracy on these attachments.

Deployed 6 November 2026 at 18:54 UTC to the existing Hostinger worker through
its verified SSH management hostname `srv1216403.hstgr.cloud`. The earlier timeout
was limited to this Mac's route to the private Tailscale address, not a failed
worker. The service was active before deployment and its queue was empty.

Only `analysis.py`, `catalog_supplement.py` and the Bowman supplement were
installed. The previous files are backed up privately under
`/var/lib/cardscout/data/upgrade-backups/bowman-20261106T185414Z`.
Existing configuration, credentials, owned cards and pairing were preserved.
The restarted service passed authenticated, certificate-validated `/v1/ping`
and `/v1/checklists` checks. The live endpoint contains both Bowman families
with 398 rows; live candidate retrieval returns each photographed card in its
correct family. Paid web search remains disabled. The installed iPhone app was
launched to refresh its catalog. Its persisted library was checked for the two
Bowman family IDs and counts: paper 198, Chrome 200. The temporary verification
copy was deleted afterward; no photos were copied. A new camera scan remains a separate acceptance
check; no synthetic scan was added to the user's collection.
