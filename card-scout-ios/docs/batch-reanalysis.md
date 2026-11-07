# Reanalyze unclear saved cards

Saved originals belong to the iPhone. The VPS deletes its temporary transport copies after the phone acknowledges results. A new assessment therefore needs the phone to send its saved photos again; no new capture or individual card opening is needed.

Build 21 adds a bounded support launch argument:

```
--reanalyze-saved-jobs <comma-separated previous job UUIDs>
```

Only named, completed cards with an unconfirmed or below-high-confidence identity qualify. Confirmed high-confidence cards and manual assignments are untouched. The batch reads every required saved photo before atomically saving a new queue. Collection IDs, photos, and existing assessments stay intact. New analysis job IDs make repeating the same command harmless, even after completion.

These jobs explicitly use the full pipeline and original photo bytes. They do not reuse the old uncertain identity or the fast identification result. The normal durable upload/recovery loop handles them. The existing server routes analysis to GPT-6 Luna, then runs exact CardSight matching only for eligible identities. The shared provider ledger enforces the 720 monthly cap and the existing daily cap; paid search and model fallback remain disabled.

During a support launch, `Library/Application Support/CardScout/reanalysis-status.json` provides counts only: targeted, pending, completed, failed, confirmed, and timestamp. It contains no card identities, photo paths, prices, URLs, or credentials. It is a diagnostic receipt, not an upload source or a persistent batch command.

Validation: 102 Swift core tests, 101 passed and one optional live-cache test skipped. Added coverage for whole-batch photo preflight, stable collection/photos, exact targeting, confirmed-card exclusion, and duplicate-launch prevention. Signed iPhone build succeeded. Runtime batch results are checked separately against the phone receipt and VPS queue.

## Runtime check, 16 October 2026

The 18 unclear server job records selected 17 current eligible iPhone entries. One requested server job did not correspond to a current eligible entry; the exact reason was not established. Do not present the server's historical job count as the current number of owned cards.

All 17 selected entries completed full Luna reanalysis and were acknowledged after persistence on the iPhone. None met the existing confirmed/high-confidence identity gate, so CardSight made no new requests. Monthly usage stayed at 218 of 720. Most results lacked readable names, card numbers, or reverse-side evidence. Jalen Ramsey #191 remained uncertain between Base and Refractor. Jayden Daniels PP-3 remained unconfirmed because the Power Players insert lacked independent checklist confirmation. No failed jobs, paid search, or alternate-model fallback occurred.
