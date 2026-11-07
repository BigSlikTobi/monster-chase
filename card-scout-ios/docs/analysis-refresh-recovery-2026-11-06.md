# Saved analysis refresh recovery — 6 November 2026

Justin Jefferson, 2026 Bowman Chrome Base #BCV-69, was identified correctly but
the subsequent market refresh failed after the model had returned successfully.
The server was connected and active. This was not a camera or connectivity error.

Saved results included `matches` and `matchNotice`. `merge_market_refresh` copied
those fields into the strict assessment contract, which permits only `analysis`
and `collection`. Validation rejected the result with `missing or additional
fields`. Retrying without changing this handoff repeated the same failure.

The merge now removes only the two known routing fields from its private copy.
All other strict schema, identity and market-evidence validation remains intact.
Regression tests cover saved routing, unchanged original input, unexpected saved
fields, identity preservation and the persisted same-photo refresh queue path.

The fixed worker was deployed with the previous `analysis.py` backed up under
`/var/lib/cardscout/data/upgrade-backups/refresh-routing-20261106T192728Z`.
Its config and existing original photos were preserved. The actual saved result
passed offline validation with the fix. Retrying the original job then completed
with `status=analyzed`, `error=null`, confirmed player/number and assessment
insights. No replacement capture or invented price was used.

Build 38 also polls failed phone jobs for repaired server results. This is a read,
not an automatic retry or re-upload: a missing failed job cannot trigger upload.
The paused-price message now explains interrupted analysis rather than suggesting
that connectivity is necessarily broken.

Verification: all 242 Python worker tests passed. The persisted refresh queue
regression was then expanded to include match-routing metadata; all 12 market
tests passed again. The signed iPhone build 38 succeeded, was installed over the
existing app and launched. The server subsequently recorded the phone's ACK for
the repaired Jefferson job and removed its temporary transport photos. This ACK
is sent only after the phone persists the successful result. No new capture or
collection reset was performed. The completed assessment does not establish that
an exact market price is available for Bowman.
