from copy import deepcopy
import unittest

from reference_images import digest, identity, validate, overlay, coverage, safe_url


class ReferenceImagesTests(unittest.TestCase):
    def setUp(self):
        self.collection = {"id": "optic-blue", "year": 2025, "brand": "Panini", "name": "Donruss Optic", "subset": "Base", "parallel": "Blue Hyper",
                           "cards": [{"number": "267", "player": "Trey Amos"}]}
        self.record = {"identity": identity(self.collection, self.collection["cards"][0]), "frontURL": "https://i.ebayimg.com/images/g/fixture/s-l1600.jpg",
                       "sourceURL": "https://www.ebay.com/itm/123", "sourceTitle": "2025 Optic Trey Amos #267 Blue Hyper",
                       "status": "reviewed", "kind": "scan", "reviewer": "codex-visual", "reviewedAt": "2026-10-16", "sha256": "a" * 64, "width": 800, "height": 1100}

    def manifest(self, records=None):
        rows = records if records is not None else [self.record]
        return {"version": 1, "records": deepcopy(rows), "revision": digest(rows)}

    def test_exact_scope_only_no_identity_or_image_url_mutation(self):
        original = deepcopy(self.collection)
        result = overlay([self.collection], validate(self.manifest()))[0]
        self.assertEqual(self.collection, original)
        self.assertIn("referenceImage", result["cards"][0])
        self.assertNotIn("imageURL", result["cards"][0])
        self.assertEqual(result["referenceExample"]["player"], "Trey Amos")
        for key, value in [("parallel", None), ("year", 2024), ("name", "Donruss"), ("subset", "Rookie Recruits")]:
            changed = deepcopy(self.collection); changed[key] = value
            self.assertNotIn("referenceImage", overlay([changed], self.manifest())[0]["cards"][0])

    def test_wrong_number_player_and_stale_embedded_images_are_removed(self):
        changed = deepcopy(self.collection)
        changed["cards"][0].update(player="Wrong player", referenceImage={"old": True})
        changed["referenceExample"] = {"old": True}
        result = overlay([changed], self.manifest())[0]
        self.assertNotIn("referenceImage", result["cards"][0])
        self.assertNotIn("referenceExample", result)
        changed["cards"][0]["number"] = "369"
        self.assertNotIn("referenceImage", overlay([changed], self.manifest())[0]["cards"][0])

    def test_revision_review_and_scan_evidence_required(self):
        for key, value in [("status", "candidate"), ("kind", "mockup"), ("reviewer", "seller"), ("sha256", "bad"), ("width", 50), ("reviewedAt", "")]:
            record = deepcopy(self.record); record[key] = value
            with self.assertRaises(ValueError): validate(self.manifest([record]))
        manifest = self.manifest(); manifest["revision"] = "bad"
        with self.assertRaises(ValueError): validate(manifest)

    def test_duplicate_identity_and_reused_pixels_across_variants_rejected(self):
        with self.assertRaises(ValueError): validate(self.manifest([self.record, self.record]))
        second = deepcopy(self.record); second["identity"]["collectionID"] = "optic-fire"; second["identity"]["parallel"] = "Fire"
        with self.assertRaises(ValueError): validate(self.manifest([self.record, second]))

    def test_url_hosts_credentials_redirect_targets_and_namespaces(self):
        for url in ["http://i.ebayimg.com/a.jpg", "https://i.ebayimg.com@evil.test/a.jpg", "https://127.0.0.1/a.jpg", "https://i.ebayimg.com:8080/a.jpg", "https://cdn.shopify.com/other-account/a.jpg", "https://storage.googleapis.com/private/a.jpg"]:
            self.assertFalse(safe_url(url, image=True))
        self.assertTrue(safe_url("https://cdn.shopify.com/s/files/1/0791/7515/6005/files/card.jpg", image=True))
        self.assertFalse(safe_url("https://www.tcdb.com/a.jpg", image=True))

    def test_coverage_counts_real_exact_slots_and_no_cartesian_fill(self):
        second = deepcopy(self.collection); second["id"] = "optic-fire"; second["parallel"] = "Fire"
        report = coverage([self.collection, second], self.manifest())
        self.assertEqual(report["exactImages"], 1)
        self.assertEqual(report["slots"], 2)
        self.assertEqual(report["bindersWithImages"], 1)

    def test_shipped_manifest_is_reviewed_and_every_record_matches_catalog(self):
        import json
        from pathlib import Path
        from reference_images import load
        root = Path(__file__).parent / 'data'
        manifest = load(root / 'reference-images.json')
        catalog = json.loads((root / 'collections.json').read_text())
        report = coverage(catalog, manifest)
        self.assertGreater(report['exactImages'], 0)
        # Bundled seed is smaller than the user's live checklist catalog.
        scopes = {r['identity']['collectionID'] for r in manifest['records']}
        self.assertEqual(len(scopes), 35)
        for record in manifest['records']:
            scope = record['identity']
            for collection in catalog:
                if collection['id'] != scope['collectionID']: continue
                for entry in collection['cards']:
                    if entry['number'] == scope['number']:
                        self.assertEqual(identity(collection, entry), scope)
        self.assertFalse(any('PHOTO COMING SOON' in r['sourceTitle'].upper() for r in manifest['records']))
