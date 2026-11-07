import json
import statistics
from pathlib import Path
import sys
import argparse
import hashlib

parser = argparse.ArgumentParser(description='Summarize isolated saved-photo benchmark results without API calls.')
parser.add_argument('--scratch', type=Path, required=True)
parser.add_argument('--destination', type=Path, required=True)
args = parser.parse_args()
from benchmark_decisions import TEST_INDICES, REFERENCE_INDICES, ORIGINAL_LIBRARY_SHA256, family_key
from analysis import slug

root = args.scratch
library = json.loads((root/'originals/library.json').read_text())
out = {'date': '2026-10-16', 'scope': 'One Donruss Optic main-set binder family, plus two outside-binder controls.',
       'librarySHA256': ORIGINAL_LIBRARY_SHA256,
       'sample': {'queryCards': len(TEST_INDICES), 'referenceCards': len(REFERENCE_INDICES), 'phoneCards': len(library['cards']), 'phoneCollections': len(library['collections'])},
       'conditions': ['Same original front/back bytes across routes; no photo resizing or OCR regeneration.',
          'Current flow: existing run_identification then run_codex, Luna Fast/medium and conditional Sol/max via ChatGPT CLI; pricing excluded.',
          'Decisions: two requests when routable; family/rookie first, then checklist row/finish; no OCR hints. Current flow retains existing capture OCR.',
          'Full phone checklist candidates supplied to Decisions; current quick flow receives product metadata and full flow receives its normal targeted checklist rows.',
          'Reference arm: three different held-out original cards with stored Blue Hyper, Fire and Base labels; no query card used as its own reference.',
          'Single trial per card and arm, rotated arm order; at most two current-flow jobs overlapped; local network timings, not VPS queue or iPhone-to-server transport.',
          'No production library, worker config, routing or pricing quota was changed. Separate Bench key powers API calls.'],
       'limitations': ['Stored exact variant labels are provisional agreement targets, not independently authenticated physical truth.',
          'Checklist-row matches use visible player names checked on original photos and matching local checklist rows. Product/year expectations come from the existing binder snapshot.',
          'Some original cards have only fronts, glare, sleeves or ambiguous finish. No definitive exact-variant accuracy claim is possible from this sample alone.',
          'The Topps control exceeds this one-binder prototype candidate budget and stops after correct family routing.',
          'CLI image-tool warnings are reported per case; they limit conclusions about the Sol replay.',
          'Two local preflight errors and one discarded API stage during candidate-limit handling are excluded from paired timings; these were not production failures.'],
       'referenceCards': [{'index':i,'id':library['cards'][i]['id'],'player':library['cards'][i]['analysis']['player'],'storedVariant':library['cards'][i]['analysis'].get('parallel') or 'Base','labelVerifiedIndependently':False} for i in REFERENCE_INDICES],
       'cases': [], 'summary': {}}

arms = ['decisions_plain','decisions_reference','current_quick','current_full']
audit_path = Path(__file__).resolve().parent.parent/'docs/decisions-reference-audit-2026-10-16.json'
if audit_path.exists():
    out['referenceAudit'] = json.loads(audit_path.read_text())
    out['originalReferenceArmStatus'] = 'Incorrectly labeled reference: Derrick Harmon Orange Scope /79 was supplied as Fire. Preserve historical observations; do not infer exact-variant accuracy from that arm.'
    out['limitations'].append('The corrected arm changes reference photos and adds Orange Scope to the choices. It is a corrected-reference follow-up, not a controlled label-only ablation. Trey Amos Blue Hyper attribution remains medium confidence.')
if list((root/'run').glob('[0-9][0-9]-decisions_corrected.json')):
    arms.append('decisions_corrected')
for i in TEST_INDICES:
    card = library['cards'][i]
    a = card['analysis']
    family = family_key(a)
    cs = [c for c in library['collections'] if family_key(c)==family]
    rows = {r['number']:r for c in cs for r in c['cards'] if slug(r['player'])==slug(a['player'])}
    expected = a.get('cardNumber') or (next(iter(rows)) if len(rows)==1 else None)
    target = a.get('setName')=='Donruss Optic' and a.get('subset') in ('Base','Rated Rookie')
    stable = target and a.get('identityConfirmed') is True and a.get('confidence')=='high'
    case = {'index':i,'id':card['id'],'player':a['player'],'expectedFamily':family,'expectedChecklistNumber':expected,
            'targetBinderFamily':target,'hasBack':bool(card.get('backFile')),
            'photoSHA256': {side:hashlib.sha256((root/'originals/photos'/card[side]).read_bytes()).hexdigest() for side in ('frontFile','backFile') if card.get(side)},
            'storedVariant':a.get('parallel') or 'Base','variantAgreementScorable':stable,
            'independentVariantTruth':None,'routes':{}}
    for arm in ['decisions_plain','decisions_reference','decisions_corrected','current']:
        f=root/'run'/f'{i:02d}-{arm}.json'
        if not f.exists():continue
        data=json.loads(f.read_text())
        if data['status']!='ok':
            case['routes'][arm]={'status':data['status'],'error':data.get('error')};continue
        if arm.startswith('decisions'):
            p=data.get('prediction') or {}
            pred={'family':p.get('family'), 'cardNumber':p.get('cardNumber'),'variant':p.get('parallel')}
            confidence={a.get('name'):a.get('confidence') for s in data['stages'] for a in s['answers']}
            case['routes'][arm]={'seconds':data['seconds'],'prediction':pred,'confidence':confidence,'apiCalls':len(data['stages']),
               'usage':[s.get('usage') for s in data['stages']]}
        else:
            for key,result,seconds in [('current_quick',data['identification'],data['quickSeconds']),('current_full',data['result'],data['seconds'])]:
                p=result['analysis']
                pred={'family':family_key(p),'cardNumber':p.get('cardNumber'),'variant':p.get('parallel') or 'Base','player':p.get('player')}
                case['routes'][key]={'seconds':seconds,'prediction':pred,'confidence':p.get('confidence'),'identityConfirmed':p.get('identityConfirmed')}
            log=root/'run/jobs'/f'{i:02d}'/'worker.log'
            lines=log.read_text(errors='replace').splitlines() if log.exists() else []
            case['routes']['current_full']['solEscalated']=any(s.startswith('[card-scout] model=gpt-5.6-sol') for s in lines)
            case['routes']['current_full']['imageToolWarnings']=sum('unable to process image' in s for s in lines)
            case['routes']['current_full']['apiAccounting']=[json.loads(s.partition('[card-scout] ')[2]) for s in lines if s.startswith('[card-scout] {')]
    for arm,result in case['routes'].items():
        p=result.get('prediction',{})
        result['familyMatchesExpected']=p.get('family')==family
        result['checklistNumberMatchesExpected']=bool(expected) and p.get('cardNumber')==expected
        result['familyAndCardMatch']=result['familyMatchesExpected'] and result['checklistNumberMatchesExpected']
        if stable:
            result['variantMatchesStoredLabel']=p.get('variant')==case['storedVariant']
            result['familyCardVariantMatchStored']=result['familyAndCardMatch'] and result['variantMatchesStoredLabel']
    out['cases'].append(case)

for arm in arms:
    scored=[(c,c['routes'][arm]) for c in out['cases'] if arm in c['routes'] and 'seconds' in c['routes'][arm]]
    if not scored:continue
    stable=[(c,r) for c,r in scored if c['variantAgreementScorable']]
    target=[(c,r) for c,r in scored if c['targetBinderFamily']]
    durations=[r['seconds'] for c,r in scored]
    out['summary'][arm]={'completedCases':len(scored),'medianSeconds':round(statistics.median(durations),3),
          'minSeconds':round(min(durations),3),'maxSeconds':round(max(durations),3),
          'expectedFamilyMatches':sum(r['familyMatchesExpected'] for c,r in scored),
          'expectedFamilyAndChecklistMatches':sum(r['familyAndCardMatch'] for c,r in scored),
          'targetBinderCases':len(target),'targetBinderFamilyAndChecklistMatches':sum(r['familyAndCardMatch'] for c,r in target),
          'targetBinderMedianSeconds':round(statistics.median(r['seconds'] for c,r in target),3) if target else None,
          'stableStoredVariantCases':len(stable),'variantAgreements':sum(r['variantMatchesStoredLabel'] for c,r in stable),
          'familyCardVariantAgreements':sum(r['familyCardVariantMatchStored'] for c,r in stable),
          'independentExactVariantAccuracy':None}
    if arm=='current_full':
        out['summary'][arm]['solEscalations']=sum(r.get('solEscalated',False) for c,r in scored)
        out['summary'][arm]['casesWithImageToolWarnings']=sum(bool(r.get('imageToolWarnings')) for c,r in scored)

out['complete'] = all(out['summary'].get(arm, {}).get('completedCases') == len(TEST_INDICES) for arm in arms)
dest=args.destination
dest.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n')
print(json.dumps(out['summary'],indent=2))
print('wrote',dest)
