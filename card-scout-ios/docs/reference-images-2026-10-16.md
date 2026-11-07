# Reviewed binder reference images — 16 October 2026

Build 28 adds real reference photos to scan matches, binder covers, missing checklist entries, and collected-card comparisons. Exact photos are bound to the full year, brand, product, subset, parallel, card number, and player. A different player's photo is shown only as an explicit variant example, never as that checklist entry's exact photo.

## Coverage

The live catalog has 35 binders and 4,814 slots. The reviewed overlay contains 547 exact-card fronts, with an example in every binder. 4,267 slots still lack a verified exact photo. This is partial image coverage across all binders, not a complete photo library.

Examples: 2026 Topps Profiles 23/25, 2025 All Topps Team 19/20, 1991 Topps Football 47/50, and 1991 Topps Rookies Football 45/50. See `reference-image-coverage.json` for every binder. Slot counts reflect the user's existing checklists. Some parallel checklists inherit base membership; Blue Hyper's 300 slots must not be treated as proof that every base card has that parallel. This update does not change those checklists or owned-card assignments.

## Evidence and exclusions

The manifest at `mac/data/reference-images.json` keeps the public source page, exact image URL, review timestamp, image SHA-256, pixel dimensions, and full card identity. Sources include FreshDCards, Wayne Collection, eBay galleries, Sports Card Investor, and SportsCardsPro. Public Shopify product metadata was read using Shopify's documented Ajax product endpoint; no seller prices are imported.

Photographed fronts were visually reviewed. Where Wayne listings omit numbers, photographed backs also passed local macOS Vision OCR checks for player and printed card number. Number-matching OCR only creates review candidates; it does not publish images automatically. We excluded placeholders, autograph versions in unsigned binders, wrong-product Downtowns, foil photos in base listings, unreadable identities, and ambiguous finishes. These are seller/reference exemplars, not a guarantee of another physical card's condition or authenticity.

TCDB is a checklist link only. Its terms prohibit automated scraping and image framing; its photos were not ingested. Blocked sites were not bypassed. No generated card artwork is used.

## Updating safely

1. Start from missing identities in the current worker checklist response. Search by full scope, including subset and finish. Do not assume copied parallel membership is verified.
2. Retrieve public source metadata and the actual photographed front/back. Keep candidates outside the reviewed manifest until inspected. A seller title alone is insufficient when the picture contradicts it.
3. Review player, printed number, release, product, insert, and finish. Compare foil texture and serial-number evidence when relevant. Record the original byte SHA and dimensions. Reject stock/placeholder photos and duplicate pixels used for different identities.
4. Add only reviewed records, recalculate `revision` with `reference_images.digest(records)`, then validate using `reference_images.load`. Run the worker tests and coverage CLI against the live checklist snapshot.
5. Back up the running manifest and SQLite database. Publish the new manifest atomically to the worker data directory, owned by the service account. Do not overwrite `collections.json`. The app notices the manifest revision and refreshes its persisted checklist overlay.

The checked-in manifest seeds new installations only. An existing live manifest is preserved during setup. There is no automatic publisher or scheduled crawler. A routine refresh should report newly filled exact slots, broken links, and remaining gaps separately. If an image changes at its URL, its prior review receipt no longer establishes the new bytes; re-review it before updating its receipt.

## Verification

211 Python tests passed. 133 Swift tests passed with one existing skip. Signed iPhone and simulator builds passed. Simulator checks confirmed actual photos in the Profiles grid, its 23/25 coverage count, enlarged exact-card photos, and source attribution. The authenticated live API returned 547 exact photos and examples for all 35 binders. Original checklist bytes were preserved during deployment.

Build 28 was installed and launched on MyApple. A device readback confirmed 547 exact references and all 35 binder examples. All 45 complete owned-card records and all 77 original photo SHA-256 values matched the pre-install backup. See `reference-image-verification.json`.
