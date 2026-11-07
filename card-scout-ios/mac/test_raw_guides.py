from copy import deepcopy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from raw_guides import PACHECO, PACHECO_URL, parse_guide, supported
from card_prices import PriceResearch, identity_key, MATCHER_VERSION, TTL
from cardsight import Client, atomic
from test_pipeline import result
from analysis import local_identity_excerpts, run_codex
import raw_guides

HTML = '''<h1>2025 Donruss Optic Isiah Pacheco #147</h1><table>
<tr><td>Raw / Ungraded</td><td><strong>$1.27</strong></td><td>price guide</td></tr>
<tr><td>Gem Mint 10</td><td>$35</td><td>estimate</td></tr></table>
<p>Price guide data: <a>SportsCardsPro</a></p>'''


class RawGuideTests(unittest.TestCase):
    def test_uncached_estimate_does_not_spend_auction_quota(self):
        with tempfile.TemporaryDirectory() as folder:
            a = result()["analysis"]; a.update(PACHECO, identityConfirmed=True, confidence="high")
            client = Client(folder, lambda *args: self.fail("Guide needs no CardSight calls"))
            prices = PriceResearch(folder, client)
            guide = raw_guides.reference("Midpoint", "https://www.cardcenteringtool.com/prices/pricecharting-1",
                                        125, a, "2026-10-01", __import__("time").time() + TTL, "Raw guide")
            try:
                with patch("raw_guides.fetch_guide", return_value=guide) as fetch:
                    value = prices.lookup(a)
                    self.assertEqual(value["status"], "ready")
                    self.assertEqual(value["soldStatus"], "not_checked")
                    self.assertEqual(prices.lookup(a)["references"], [guide])
                    self.assertEqual(fetch.call_count, 1)
            finally:
                prices.executor.shutdown()

    def test_exact_midpoint_raw_guide_never_uses_graded_or_wrong_variant_value(self):
        a = dict(PACHECO)
        captured = __import__('datetime').date.today().isoformat()
        text = f'''# Isiah Pacheco #147 — Football Cards 2025 Panini Donruss Optic
- Last price capture: {captured}
## Raw (ungraded) prices
- Ungraded: $1.27
## Graded prices
- PSA 10: $350
Prices are USD market values.
'''
        self.assertEqual(raw_guides.parse_midpoint(text,a), (127,captured))
        for old,new in [('Pacheco #147','Pacheco [Holo] #147'),('2025 Panini','2024 Panini'),
                        ('Donruss Optic','Donruss Optic Downtown'),('Prices are USD','Prices are CAD'),
                        ('Ungraded: $1.27','Ungraded: $0'),(captured,'2000-01-01')]:
            self.assertIsNone(raw_guides.parse_midpoint(text.replace(old,new),a))
        self.assertIsNone(raw_guides.parse_midpoint(text.replace('## Raw (ungraded) prices','## Graded prices'),a))
        self.assertTrue(raw_guides.can_lookup(dict(a,serialNumber='1/99',parallel='Gold')))
        self.assertFalse(raw_guides.can_lookup(dict(a,serialNumber='1/99',parallel=None)))
        self.assertFalse(raw_guides.can_lookup(dict(a,serialNumber='100/99',parallel='Gold')))

    def test_older_guide_is_usable_and_numbered_cards_need_source_tier(self):
        import datetime as dt
        captured = (dt.date.today() - dt.timedelta(days=180)).isoformat()
        a = dict(PACHECO, parallel="Orange Scope", serialNumber="20/79")
        text = f'''# Isiah Pacheco [Orange Scope] #147 — Football Cards 2025 Panini Donruss Optic
- Last price capture: {captured}
## Raw (ungraded) prices
- Ungraded: $4.50
## Details
Print run: /79
Prices are USD.
'''
        self.assertEqual(raw_guides.parse_midpoint(text, a), (450, captured))
        self.assertIsNone(raw_guides.parse_midpoint(text.replace("/79", "/99"), a))
        self.assertIsNone(raw_guides.parse_midpoint(text.replace("Print run: /79", ""), a))
        self.assertIsNone(raw_guides.parse_midpoint(text.replace("Orange Scope", "Orange"), a))

    def test_midpoint_search_results_need_exact_release_before_any_detail_fetch(self):
        wrong = dict(game='football',name='Isiah Pacheco [Holo] #147',set='Football Cards 2025 Panini Donruss Optic',url='/prices/pricecharting-1',raw=100)
        with patch('raw_guides.public_get',return_value=__import__('json').dumps({'cards':[wrong]})) as fetch:
            self.assertIsNone(raw_guides.midpoint(PACHECO,'2026-10-16',1234))
        self.assertEqual(fetch.call_count,1)

    def test_public_release_page_recovers_exact_guide_outside_ten_search_results(self):
        a=dict(PACHECO,player='Jaxson Dart',brand='Topps',setName='Topps Chrome',cardNumber='306',parallel='Topps Refractor')
        date=__import__('datetime').date.today().isoformat()
        text=f'''# Jaxson Dart [Topps Refractor] #306 — Football Cards 2025 Topps Chrome
- Last price capture: {date}
## Raw (ungraded) prices
- Ungraded: $22.99
## Graded prices
- PSA 10: $580
Prices are USD market values.
'''
        raw_guides._release_links.clear()
        with patch('raw_guides.public_get',side_effect=['{"cards":[]}','{"cards":[]}',
                   '<a href="/prices/pricecharting-12532499">Jaxson Dart [Topps Refractor] #306</a>',text]):
            guide=raw_guides.midpoint(a,date,1234)
        self.assertEqual((guide['provider'],guide['kind'],guide['lowCents']),('Midpoint','guide',2299))
        raw_guides._release_links.clear()

    def test_sol_and_luna_cannot_save_model_prices_but_source_commentary_is_discarded(self):
        from analysis import enforce_separate_pricing
        from schema import RESULT
        a = result(); a['analysis']['marketSources']=[]; a['analysis']['insights']['marketReferences']=[]
        enforce_separate_pricing(a,{'cardSightResearchEnabled':True},RESULT)
        self.assertEqual(a['analysis']['insights']['marketBullets'],[])
        a['analysis']['marketLowCents']=100
        with self.assertRaises(ValueError): enforce_separate_pricing(a,{'cardSightResearchEnabled':True},RESULT)

    def test_only_explicit_exact_raw_guide_can_supply_price(self):
        self.assertEqual(parse_guide(HTML), 127)
        for old, new in [('Pacheco #147', 'Pacheco [Holo] #147'), ('2025 Donruss', '2024 Donruss'),
                         ('Raw / Ungraded', 'PSA 10'), ('price guide</td>', 'estimate</td>'),
                         ('$1.27', '$1.27–$2.00'), ('$1.27', '$0.00'),
                         ('SportsCardsPro', 'Unknown')]:
            self.assertIsNone(parse_guide(HTML.replace(old, new)))
        row = '<tr><td>Raw / Ungraded</td><td>$2</td><td>price guide</td></tr>'
        self.assertIsNone(parse_guide(HTML + row))
        self.assertIsNone(parse_guide('<script>' + HTML + '</script>'))

    def test_source_identity_cannot_expand_to_another_product_or_variant(self):
        self.assertTrue(supported(PACHECO))
        for key, value in [('parallel', 'Holo'), ('serialNumber', '2/99'), ('year', 2024),
                           ('brand', 'Topps'), ('subset', 'Downtown'), ('cardNumber', '148')]:
            self.assertFalse(supported(dict(PACHECO, **{key: value})))

    def test_cached_negative_gains_guide_without_repeating_cardsight_and_without_persisting_identity(self):
        import time
        with tempfile.TemporaryDirectory() as folder:
            a = result()['analysis']; a.update(PACHECO, identityConfirmed=True, confidence='high', licenseScope='nfl_and_nflpa')
            before = deepcopy(a)
            client = Client(folder, lambda *args: self.fail('Existing sold check must not repeat'))
            prices = PriceResearch(folder, client)
            value = dict(key=identity_key(a), matcherVersion=MATCHER_VERSION, checkedAt='2026-10-16',
                         expiresAt=time.time()+TTL, status='no_match', reason='no_exact_sales', references=[], sampleLimited=False)
            atomic(prices.cache / (identity_key(a)+'.json'), value)
            guide = dict(provider='Slabline', url=PACHECO_URL, kind='guide', grade='raw', lowCents=127,
                         highCents=127, checkedAt=value['checkedAt'], expiresAt=value['expiresAt'])
            try:
                with patch('raw_guides.fetch_guide', return_value=guide) as fetch:
                    self.assertEqual(prices.lookup(a)['references'], [guide])
                    prices.lookup(a); self.assertEqual(fetch.call_count, 1)
                out = prices.attach({'analysis': a})['analysis']['insights']
                self.assertEqual(out['sourceChecks'][0]['status'], 'no_match')
                self.assertEqual(out['sourceChecks'][1]['provider'], 'Slabline')
                self.assertIn('Kein bestätigter Verkauf', out['marketBullets'][0])
                self.assertEqual(a, before)
                # An accepted sale always wins, without a guide request.
                value['status']='ready'; value['references']=[dict(guide, provider='CardSight', kind='sold')]
                atomic(prices.cache / (identity_key(a)+'.json'), value)
                with patch('raw_guides.fetch_guide', side_effect=AssertionError('Guide must not replace sale')):
                    self.assertEqual(prices.lookup(a)['references'][0]['kind'], 'sold')
                # Failed free fetches also cool down, without a quota-consuming retry.
                value['status']='no_match'; value['references']=[]
                atomic(prices.cache / (identity_key(a)+'.json'), value)
                with patch('raw_guides.fetch_guide', side_effect=OSError('offline')) as fetch:
                    self.assertEqual(prices.lookup(a)['status'], 'no_match')
                    prices.lookup(a); self.assertEqual(fetch.call_count, 1)
            finally: prices.executor.shutdown(wait=True)


class LocalIdentityEvidenceTests(unittest.TestCase):
    def test_full_photo_retry_gets_candidates_and_reuses_its_photo_only_step(self):
        a = result(); a['analysis']['cardNumber'] = None
        c = result()['collection']; c['checklistComplete'] = True
        with tempfile.TemporaryDirectory() as folder:
            with patch('analysis.run_identification', return_value=a) as identify, patch('analysis._run_model', return_value=result()) as model:
                config = dict(model='gpt-6-luna', cardSightResearchEnabled=True)
                run_codex(Path(folder), [c], config)
                self.assertIn('"number": "60"', model.call_args.args[3])
                self.assertIn('not proof of year, licensing or finish', model.call_args.args[3])
                run_codex(Path(folder), [c], config)
                self.assertEqual(identify.call_count, 1)

    def test_missing_front_number_gets_exact_player_candidates_without_auto_assigning(self):
        known = result()['collection']; known.update(checklistComplete=True)
        a = result()['analysis']; a['cardNumber'] = None
        before = deepcopy(a)
        matches = local_identity_excerpts(a, [known])
        self.assertEqual(matches[0]['cards'][0]['number'], '60')
        self.assertEqual(a, before)
        wrong = deepcopy(known); wrong['cards'][0]['player']='Other Player'
        self.assertEqual(local_identity_excerpts(a, [wrong]), [])
        a['cardNumber']='61'
        self.assertEqual(local_identity_excerpts(a, [known])[0]['cards'][0]['number'], '60')

    def test_wrong_first_pass_metadata_does_not_exclude_sourced_alternatives(self):
        a = result()['analysis']; a['cardNumber']=None
        c = result()['collection']; c['checklistComplete']=True
        for k,v in [('year',2024), ('name','Topps Chrome'), ('subset','Downtown'), ('parallel','Holo')]:
            self.assertEqual(local_identity_excerpts(a, [dict(c, **{k:v})])[0][k], v)
        partial = local_identity_excerpts(a, [dict(c, checklistComplete=False)])
        self.assertFalse(partial[0]['checklistComplete'])
        self.assertEqual(partial[0]['cards'], c['cards'])
        self.assertEqual(local_identity_excerpts(a, [dict(c, sourceURL=None)]), [])
        self.assertEqual(local_identity_excerpts(dict(a, player=None), [c]), [])

    def test_independent_ocr_recovers_evidence_without_a_model_name(self):
        c = result()['collection']; c['checklistComplete'] = True
        self.assertEqual(local_identity_excerpts({}, [c], 'DAUNTE CULPEPPER')[0]['cards'][0]['number'], '60')


if __name__ == '__main__': unittest.main()
