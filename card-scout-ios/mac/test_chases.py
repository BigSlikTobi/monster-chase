from copy import deepcopy
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from chases import load_catalog, validate_catalog
from server import Repository, handler

SEED = Path(__file__).parent / "data/chases.json"


class ChaseTests(unittest.TestCase):
    def test_seed_combines_price_guides_with_the_official_topps_chase_snapshot(self):
        c = load_catalog(SEED)
        self.assertEqual(c["version"], 2)
        self.assertEqual(c["managedBy"], "cardscout-bundled")
        self.assertEqual(len(c["products"]), 5)
        self.assertEqual(c["products"][0]["id"], "2025-panini-donruss-optic")
        self.assertEqual(c["products"][1]["id"], "2026-topps-flagship-football")
        topps = c["products"][1]
        guides = [card for product in c["products"] if product is not topps for card in product["cards"]]
        self.assertEqual(len(guides), 40)
        self.assertTrue(all(x["priceKind"] == "guide" and x["imageURL"] and x["priceCents"] for x in guides))
        self.assertEqual(len(topps["cards"]), 693)
        self.assertEqual(topps["coverage"]["scope"], "official_chases")
        self.assertTrue(all(x.get("priceCents") is None and x["imageURL"] is None for x in topps["cards"]))
        variants = {card["variant"] for card in topps["cards"]}
        self.assertTrue({"All Kings", "1957 Rookie Variation", "Flagship First Dual Signatures", "Island Ink", "Ring of Honor Signatures", "Rookie Real One Relics"} <= variants)
        self.assertTrue(any(x["number"] == "FFS-FM" and x["player"] == "Fernando Mendoza" for x in topps["cards"]))
        self.assertTrue(any(x["number"] == "SBCS-TBRA" and x["player"] == "Tom Brady" for x in topps["cards"]))

    def test_official_topps_snapshot_matches_the_served_catalog(self):
        catalog = load_catalog(SEED)
        topps = next(product for product in catalog["products"] if product["id"] == "2026-topps-flagship-football")
        snapshot = json.loads((SEED.parent / "topps_flagship_chases.json").read_text())
        self.assertEqual(snapshot["sourceSHA256"], "ab25d4ceb1d5693dd0e74f82c9a5d716b0d6929f2c2f009ffdc09d223c30b035")
        self.assertEqual(snapshot["cards"], topps["cards"])
        self.assertEqual(len(snapshot["highlightedFamilies"]), 15)

    def test_invalid_catalogs_rejected(self):
        valid = load_catalog(SEED)
        for field, value in [("imageURL", "http://example.com/x"), ("priceKind", "sold"), ("priceCents", -100), ("priceCents", True), ("priceSourceURL", None), ("priceCheckedAt", "bad-date")]:
            with self.subTest(field=field, value=value):
                c = deepcopy(valid); c["products"][0]["cards"][0][field] = value
                with self.assertRaises(ValueError): validate_catalog(c)
        c = deepcopy(valid); c["products"][0]["cards"][0]["rank"] = 2
        with self.assertRaises(ValueError): validate_catalog(c)
        c = deepcopy(valid); c["products"][0]["licenseScope"] = "unlicensed"
        with self.assertRaises(ValueError): validate_catalog(c)
        c = deepcopy(valid); c["products"][0]["coverage"]["scope"] = "everything"
        with self.assertRaises(ValueError): validate_catalog(c)

    def test_missing_or_bad_optional_catalog_does_not_stop_analysis_service(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Repository(directory); self.assertIsNone(repo.chases)
            (Path(directory) / "chases.json").write_text('{"broken":true}')
            repo = Repository(directory); self.assertIsNone(repo.chases)
            self.assertEqual(repo.bootstrap()["cards"], [])

    def test_v2_accepts_full_catalog_without_ten_card_limit(self):
        catalog = load_catalog(SEED); catalog["version"] = 2
        for product in catalog["products"]:
            product["coverage"] = {"status": "imported", "sourceName": "SportsCardsPro", "sourceURLs": [product["sourceURL"]], "cardCount": len(product["cards"])}
        template = catalog["products"][0]["cards"][0]
        for index in range(11, 501):
            card = deepcopy(template); card["id"] += f":{index}"; card["rank"] = index
            card["priceCents"] = None if index % 2 else 10000
            catalog["products"][0]["cards"].append(card)
        catalog["products"][0]["coverage"]["cardCount"] = 500
        validate_catalog(catalog)
        catalog["products"][0]["coverage"]["cardCount"] = 499
        with self.assertRaises(ValueError): validate_catalog(catalog)
        del catalog["products"][0]["coverage"]
        with self.assertRaises(ValueError): validate_catalog(catalog)

    def test_authenticated_endpoint_revision_and_queue_isolation(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "chases.json").write_bytes(SEED.read_bytes())
            repo = Repository(directory)
            server = ThreadingHTTPServer(("127.0.0.1", 0), handler(repo, "fixture-token"))
            thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
            def request(path, authenticated=True):
                url = f"http://127.0.0.1:{server.server_port}{path}"
                headers = {"Authorization": "Bearer fixture-token"} if authenticated else {}
                with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=5) as response: return json.load(response)
            try:
                with self.assertRaises(urllib.error.HTTPError) as error: request("/v1/chases", False)
                self.assertEqual(error.exception.code, 401)
                catalog = request("/v1/chases")
                self.assertEqual(catalog, load_catalog(SEED))
                self.assertEqual(request("/v1/ping")["chaseRevision"], catalog["revision"])
                self.assertEqual(request("/v1/ping")["analysisVersion"], "3")
                with repo.db() as db: self.assertEqual(db.execute("SELECT count(*) FROM jobs").fetchone()[0], 0)
                self.assertEqual(repo.catalog, [])
            finally: server.shutdown(); server.server_close(); thread.join(2)
