from copy import deepcopy
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from context_catalog import (bootstrap, catalog_diff, check_sources, context, digest,
                             publish, read, seal, source_url, stage_import, validate)


def binder(identity="2025-panini-optic-base", parallel=None, player="Player A", year=2025):
    return {"id": identity, "name": "Optic", "brand": "Panini", "year": year, "subset": "Base",
            "parallel": parallel, "cards": [{"number": "1", "player": player, "team": "Team", "rookie": False}],
            "expectedCount": 1, "checklistComplete": True, "sourceURL": "https://www.beckett.com/checklist"}


class Reply:
    status = 200
    headers = {"ETag": "v1"}
    url = "https://www.beckett.com/checklist"
    def __init__(self, data): self.data = data
    def __enter__(self): return self
    def __exit__(self, *args): pass
    def read(self, limit): return self.data[:limit]


class ContextCatalogTests(unittest.TestCase):
    def seed(self): return bootstrap([("fixture", [binder(), binder("parallel", "Holo")])])

    def test_deduplicates_family_rows_without_promoting_parallel_membership(self):
        c = self.seed()
        self.assertEqual(len(c["families"]), 1)
        self.assertEqual(len(c["families"][0]["rows"]), 1)
        self.assertEqual(len(c["binders"]), 2)
        self.assertTrue(all(not b["membershipVerified"] for b in c["binders"]))
        self.assertEqual(len(c["families"][0]["rows"][0]["evidence"]), 2)
        self.assertFalse(context(c, "parallel")["automaticAssignmentAllowed"])

    def test_never_merges_years(self):
        c = bootstrap([("fixture", [binder(), binder("next-year", year=2026)])])
        self.assertEqual(len(c["products"]), 2)
        self.assertEqual(len(c["families"]), 2)

    def test_same_binder_conflict_keeps_both_names_and_marks_dispute(self):
        c = bootstrap([("a", [binder()]), ("b", [binder(player="Player B")])])
        self.assertEqual(c["binders"][0]["verification"], "disputed")
        self.assertEqual(len(c["families"][0]["rows"]), 2)
        self.assertTrue(c["issues"])

    def test_unsourced_new_binder_is_registered_as_unverified(self):
        b = binder(); b["sourceURL"] = None; b["checklistComplete"] = False
        c = bootstrap([("new", [b])])
        self.assertEqual(len(c["binders"]), 1)
        self.assertEqual(c["families"][0]["verification"], "imported_unverified")

    def test_tampering_or_cross_product_links_fail(self):
        c = self.seed(); c["families"][0]["rows"][0]["player"] = "Changed"
        with self.assertRaises(ValueError): validate(c)
        c = self.seed(); c["binders"][0]["familyID"] = "wrong"
        with self.assertRaises(ValueError): validate(seal(c))

    def test_review_flag_requires_content_bound_receipt(self):
        c = self.seed(); c["families"][0]["verification"] = "reviewed"
        with self.assertRaises(ValueError): validate(seal(c))
        entity = c["families"][0]
        c["reviewEvidence"] = [{"entityID": entity["id"], "reviewer": "operator", "scope": "checklist_rows",
            "reviewedAt": "2026-10-16", "sourceIDs": [c["sources"][0]["id"]],
            "entitySHA256": digest({k:v for k,v in entity.items() if k != "verification"})}]
        validate(seal(c))
        c["families"][0]["rows"][0]["player"] = "Changed after review"
        with self.assertRaises(ValueError): validate(seal(c))

    def test_context_limits_and_explicit_paging(self):
        b = binder(); b["cards"] = [dict(b["cards"][0], number=str(i)) for i in range(300)]
        b["expectedCount"] = 300
        c = bootstrap([("large", [b])]); r = context(c, b["id"], limit=254)
        self.assertEqual(len(r["candidates"]), 254)
        self.assertEqual(r["nextOffset"], 254)
        self.assertTrue(r["includeUnknownChoice"])
        self.assertNotIn("evidence", r["candidates"][0])
        with self.assertRaises(ValueError): context(c, b["id"], limit=255)

    def test_chase_prices_and_images_never_enter_identity_catalog(self):
        p = {"name": "Select", "year": 2025, "sourceURL": "https://www.beckett.com/select", "cards": [{"priceCents": 99999, "imageURL": "https://example.com/price-image"}]}
        c = bootstrap([("fixture", [binder()])], {"products": [p]})
        self.assertNotIn("priceCents", json.dumps(c))
        self.assertNotIn("price-image", json.dumps(c))
        self.assertTrue(any(x["discoveryOnly"] for x in c["products"]))

    def test_sources_reject_credentials_http_and_unregistered_hosts(self):
        for url in ["http://www.beckett.com/x", "https://secret@www.beckett.com/x", "https://127.0.0.1/x", "https://topps.com.evil.test/x", "https://www.beckett.com:444/x"]:
            with self.subTest(url=url), self.assertRaises(ValueError): source_url(url)

    def test_changed_source_remains_pending_on_later_unchanged_check(self):
        c = self.seed(); original = deepcopy(c)
        with tempfile.TemporaryDirectory() as d, patch("context_catalog.urllib.request.build_opener") as opener:
            opener.return_value.open.return_value = Reply(b"first")
            state, report = check_sources(c, Path(d), {})
            self.assertEqual(report[0]["status"], "first_capture_needs_review")
            opener.return_value.open.return_value = Reply(b"second")
            state, report = check_sources(c, Path(d), state)
            self.assertEqual(report[0]["status"], "changed_needs_review")
            state, report = check_sources(c, Path(d), state)
            self.assertEqual(report[0]["status"], "unchanged")
            self.assertTrue(report[0]["reviewRequired"])
            self.assertEqual(c, original)

    def test_http_failure_does_not_advance_source_success(self):
        c = self.seed(); sid = c["sources"][0]["id"]
        state = {"sources": {sid: {"lastSuccess": "old", "sha256": "old-hash"}}}
        with tempfile.TemporaryDirectory() as d, patch("context_catalog.urllib.request.build_opener") as opener:
            opener.return_value.open.side_effect = urllib.error.HTTPError("https://www.beckett.com/checklist", 403, "blocked", {}, io.BytesIO())
            result, report = check_sources(c, Path(d), state)
            self.assertEqual(report[0]["status"], "unavailable")
            self.assertEqual(result["sources"][sid]["lastSuccess"], "old")

    def test_publication_requires_review_and_expected_revision_and_keeps_rollback(self):
        c = self.seed(); receipt = {"decision": "approved", "reviewer": "operator", "candidateRevision": c["revision"]}
        with tempfile.TemporaryDirectory() as d:
            active = Path(d)/"active.json"
            with self.assertRaises(ValueError): publish(c, active, {}, "none")
            publish(c, active, receipt, "none")
            with self.assertRaises(ValueError): publish(c, active, receipt, "stale")
            changed = deepcopy(c); changed["issues"].append({"kind": "new"}); changed = seal(changed)
            receipt["candidateRevision"] = changed["revision"]
            publish(changed, active, receipt, c["revision"])
            self.assertEqual(read(active)["revision"], changed["revision"])
            self.assertTrue((Path(d)/"history"/(c["revision"]+".json")).exists())
            self.assertEqual(catalog_diff(c, changed)["binders"]["removed"], [])

    def test_incremental_import_preserves_curated_variant_rules(self):
        c = self.seed()
        c["variants"][0]["rules"] = [{"kind": "operator_note", "value": "Keep this curated rule"}]
        c = seal(c)
        newer = bootstrap([("next", [binder("new-binder", "Blue")])])
        merged = stage_import(c, newer)
        self.assertEqual(len(merged["binders"]), 3)
        self.assertTrue(any(v["rules"] == c["variants"][0]["rules"] for v in merged["variants"]))
        self.assertEqual(len(merged["families"][0]["rows"]), 1)

    def test_incremental_import_never_deletes_old_row_or_overwrites_conflict(self):
        c = self.seed()
        newer = bootstrap([("next", [binder(player="Player B")])])
        merged = stage_import(c, newer)
        self.assertEqual(len(merged["families"][0]["rows"]), 2)
        self.assertEqual(merged["families"][0]["verification"], "disputed")

    def test_new_reference_cannot_be_enabled_with_an_unverified_label(self):
        c = self.seed()
        c["variants"][0]["references"] = [{"id": "bad-reference", "verification": "imported_unverified", "assetStatus": "installed", "useForDecisions": True}]
        with self.assertRaises(ValueError): validate(seal(c))


if __name__ == "__main__": unittest.main()
