import json
import tempfile
import unittest
from unittest.mock import patch
from core import Store, compile_plan, POINTS
from test_core import sample, PNG
from variation_rules import CATALOG, choose


class VariationExecutionChecks(unittest.TestCase):
    def test_all_methods_keep_subtitle_and_installation_sequence_in_request(self):
        for pid, variants in CATALOG.items():
            for variant in variants:
                raw=sample();raw.update(count=1,images=[{'pointId':pid}])
                layout=choose(pid,[],0)
                layout.update(id=variant['id'],variantId=variant['id'],structure=variant['structure'],detailIndex=0)
                with patch('core.choose',return_value=layout):
                    task=compile_plan(raw,['asset-1'])['images'][0]
                payload=json.loads(task['prompt'].splitlines()[-1]);copy=payload['image']['renderCopy'];ex=payload['providerExecution']
                self.assertTrue(copy['headline']);self.assertTrue(copy['subtitle'])
                self.assertIn(copy['subtitle'],ex['finalCheck'])
                self.assertNotIn('Inter 900',ex['renderBrief']+ex['finalCheck'])
                self.assertNotIn('Inter 700',ex['renderBrief']+ex['finalCheck'])
                if pid=='installation':
                    self.assertEqual(copy['labels'],['1 Remove Old Bulb','2 Fit New Bulb','3 Check The Lights'])
                    self.assertIn('lasfit-10 and novsight-5',ex['renderBrief'])
                    self.assertIn('not a vehicle-specific disassembly manual',ex['renderBrief'])
                    self.assertEqual(len(payload['image']['evidenceMap']['regions']),3)

    def test_comparison_brand_separated_from_inset_and_products_cannot_fuse(self):
        raw=sample();raw.update(count=1,images=[{'pointId':'illumination'}]);raw['product']['brand']='TXBILMOO'
        layout=choose('illumination',[],0);variant=next(v for v in CATALOG['illumination'] if v['id']=='hero-baseline')
        layout.update(id=variant['id'],variantId=variant['id'],structure=variant['structure'])
        with patch('core.choose',return_value=layout):task=compile_plan(raw,['a'])['images'][0]
        p=json.loads(task['prompt'].splitlines()[-1]);b=p['image']['evidenceMap']['labelBindings'][0]
        self.assertEqual(b['owner'],'ours');self.assertIn('RIGHT side',b['placement'])
        self.assertIn('one label-width',b['placement'])
        self.assertIn('Never merge two shafts into one base',p['providerExecution']['finalCheck'])

    def test_nine_plans_have_nine_executed_combinations(self):
        for pid in ('illumination', 'beam', 'protection'):
            history=[]; combinations=set(); copies=set()
            for round_number in range(9):
                raw=sample();raw.update(count=1,images=[{'pointId':pid}])
                plan=compile_plan(raw,['asset-1'],seed=round_number,history=history)
                task=plan['images'][0]; layout=task['layoutPlan']
                payload=json.loads(task['prompt'].splitlines()[-1])
                execution=payload['providerExecution']; copy=payload['image']['renderCopy']
                self.assertNotIn(layout['id'],[h['variantId'] for h in history[-2:]])
                if layout['detailIndex']:
                    self.assertIn('SELECTED EVIDENCE EMPHASIS',execution['renderBrief'])
                self.assertIn(copy['headline'],execution['finalCheck'])
                if pid=='illumination':
                    self.assertEqual(sum(b['role']=='identity' for b in payload['image']['evidenceMap']['labelBindings']),2)
                if pid=='beam' and layout['id']=='overhead-field':
                    bindings=payload['image']['evidenceMap']['labelBindings']
                    self.assertIn('lateral',bindings[0]['evidence'])
                    self.assertIn('across',bindings[0]['text'].lower())
                combinations.add((layout['id'],layout['detailIndex']))
                copies.add(json.dumps(copy))
                history.append({'pointId':pid,'variantId':layout['id'],'detailIndex':layout['detailIndex'],'scene':layout['scene']})
            self.assertEqual(len(combinations),9)
            self.assertGreaterEqual(len(copies),5)

    def test_drafts_do_not_displace_submitted_history(self):
        with tempfile.TemporaryDirectory() as root:
            store=Store(root);raw=sample();raw.update(count=1,images=[{'pointId':'illumination'}])
            record=store.save(raw,[{'name':'p.png','base64':PNG}])
            used=record['plan']['images'][0]['layoutPlan']['id']
            record['generation']={'images':[{'slot':1,'attempts':1,'state':'completed'}]}
            store._write(store._path(record['id'])/'record.json',record)
            for _ in range(12):
                new=Store(root).save(raw,[{'name':'p.png','base64':PNG}])
                self.assertNotEqual(new['plan']['images'][0]['layoutPlan']['id'],used)
            self.assertEqual(store.get(record['id'])['plan'],record['plan'])

    def test_product_proportions_reach_every_final_request(self):
        for pid in POINTS:
            raw=sample();raw.update(count=1,images=[{'pointId':pid}])
            payload=json.loads(compile_plan(raw,['asset-1'])['images'][0]['prompt'].splitlines()[-1])
            check=payload['providerExecution']['finalCheck']
            self.assertIn('UNIFORM whole-object scaling',check)
            self.assertIn('shorten the shaft',check)
            self.assertIn('With an omit-product composition, do not add a bulb',check)


if __name__=='__main__': unittest.main()
