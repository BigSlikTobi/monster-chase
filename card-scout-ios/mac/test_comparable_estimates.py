from copy import deepcopy
import datetime as dt
import tempfile
import time
from pathlib import Path
import unittest
from card_prices import PriceResearch, identity_key, MATCHER_VERSION
from cardsight import Client, atomic
from test_pipeline import result


class ComparableEstimateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        def no_network(*args): raise AssertionError("Comparisons must not make network calls")
        self.prices = PriceResearch(self.root, Client(self.root, no_network))
        self.target = deepcopy(result())
        self.a = self.target["analysis"]
        self.a.update(player="Target", year=2025, brand="Panini", setName="Donruss Optic", subset="Base",
                      cardNumber="10", parallel=None, serialNumber=None, rookie=False, confidence="high", identityConfirmed=True)
        self.a["insights"].update(conditionStatus="no_obvious_damage", marketReferences=[])

    def tearDown(self):
        self.prices.executor.shutdown(wait=True)
        self.temp.cleanup()

    def peer(self, name, amount, **changes):
        a = deepcopy(self.a); a.update(player=name, cardNumber=str(amount), **changes)
        date = dt.datetime.now(dt.timezone.utc).date().isoformat()
        ref = dict(provider="CardSight", url="https://example.com/"+name, kind="sold", grade="raw",
                   matchQuality="exact", lowCents=amount, highCents=amount, currency="USD", shipping="unknown",
                   checkedAt=date, saleDate=date, expiresAt=time.time()+100)
        atomic(self.prices.cache/(identity_key(a)+".json"),
               dict(key=identity_key(a), matcherVersion=MATCHER_VERSION, status="ready", references=[ref], expiresAt=time.time()+100))
        return a

    def test_three_distinct_players_give_labeled_range_without_mutation_or_network(self):
        peers = [self.peer("One",100), self.peer("Two",200), self.peer("Three",300)]
        before = deepcopy(self.target)
        out = self.prices.attach_comparable(self.target, peers)
        estimate = out["analysis"]["comparableEstimate"]
        self.assertEqual((estimate["lowCents"],estimate["highCents"],estimate["cardCount"]), (100,300,3))
        self.assertEqual(estimate["confidence"], "low")
        self.assertTrue(all(r["matchQuality"]=="near" for r in estimate["references"]))
        self.assertEqual(self.target, before)

    def test_duplicates_wrong_scope_and_serials_cannot_fill_a_sparse_pool(self):
        one = self.peer("One",100)
        peers = [one,one,self.peer("Rookie",200,rookie=True),self.peer("Parallel",300,parallel="Holo"),
                 self.peer("Year",400,year=2024),self.peer("Numbered",500,serialNumber="1/99"),
                 self.peer("Target",600)]
        self.assertNotIn("comparableEstimate",self.prices.attach_comparable(self.target,peers)["analysis"])

    def test_exact_evidence_and_uncertain_or_damaged_targets_never_get_cohort_estimate(self):
        peers = [self.peer("One",100),self.peer("Two",200),self.peer("Three",300)]
        for change in ({"identityConfirmed":False},{"parallel":"Holo"},{"serialNumber":"1/99"},{"subset":"Insert"}):
            target=deepcopy(self.target); target["analysis"].update(change)
            self.assertNotIn("comparableEstimate",self.prices.attach_comparable(target,peers)["analysis"])
        self.a["insights"]["conditionStatus"]="visible_damage"
        self.assertNotIn("comparableEstimate",self.prices.attach_comparable(self.target,peers)["analysis"])
        self.a["insights"].update(conditionStatus="no_obvious_damage",marketReferences=[{"kind":"guide"}])
        self.assertNotIn("comparableEstimate",self.prices.attach_comparable(self.target,peers)["analysis"])

    def test_expired_or_mixed_currency_evidence_is_not_combined(self):
        peers=[self.peer("One",100),self.peer("Two",200),self.peer("Three",300)]
        p=self.prices.cache/(identity_key(peers[-1])+".json")
        import json
        value=json.loads(p.read_text()); value["references"][0]["currency"]="EUR"; atomic(p,value)
        self.assertNotIn("comparableEstimate",self.prices.attach_comparable(self.target,peers)["analysis"])
        value["references"][0]["currency"]="USD"; value["references"][0]["expiresAt"]=time.time()-1; atomic(p,value)
        self.assertNotIn("comparableEstimate",self.prices.attach_comparable(self.target,peers)["analysis"])

    def test_api_delivers_comparison_without_persisting_it_in_job_result(self):
        import json
        from server import Repository
        repo=Repository(self.root); repo.card_prices.executor.shutdown(wait=True)
        repo.card_prices=self.prices; repo.card_prices_enabled=True
        peers = [self.peer("One",100),self.peer("Two",200),self.peer("Three",300)]
        with repo.db() as db:
            for i,a in enumerate([self.a]+peers):
                db.execute("INSERT INTO jobs(id,digest,status,created_at,updated_at,result) VALUES(?,?,'analyzed','now','now',?)",
                           (str(i),str(i),json.dumps({"analysis":a})))
        response=repo.get("0")
        self.assertEqual(response["priceStatus"],"estimate")
        self.assertEqual(response["analysis"]["comparableEstimate"]["cardCount"],3)
        with repo.db() as db:
            saved=json.loads(db.execute("SELECT result FROM jobs WHERE id='0'").fetchone()[0])
        self.assertNotIn("comparableEstimate",saved["analysis"])

    def test_repeated_source_urls_count_once(self):
        import json
        peers=[self.peer("One",100),self.peer("Two",200),self.peer("Three",300),self.peer("Four",400)]
        p=self.prices.cache/(identity_key(peers[-1])+".json")
        value=json.loads(p.read_text()); value["references"][0]["url"]="https://example.com/One"; atomic(p,value)
        estimate=self.prices.attach_comparable(self.target,peers)["analysis"]["comparableEstimate"]
        self.assertEqual(estimate["cardCount"],3)
        self.assertEqual(len({r["url"] for r in estimate["references"]}),3)
