"""Release checks inspect real frozen requests, using fake transport only."""
import json,tempfile,unittest
from datetime import datetime,timezone,timedelta
from zoneinfo import ZoneInfo
from unittest.mock import patch
from core import Store,compile_plan
from generation import Generation
from providers.gemini import GeminiProvider
from variation_rules import CATALOG,choose
from test_core import sample,PNG
from test_generation import Fake

class ReleaseAudit(unittest.TestCase):
 def test_actual_request_for_every_method_and_supported_product_type(self):
  count=0
  for pid,variants in CATALOG.items():
   for v in variants:
    for kind in ('led','mixed','halogen'):
     if kind=='halogen' and pid in ('thermal','electronics'):continue
     r=sample();r.update(count=1,images=[{'pointId':pid}]);r['product'].update(type=kind,configuration='9005*2 远光',facts='3000K' if kind=='halogen' else '6500K')
     layout=choose(pid,[],17);layout.update(id=v['id'],variantId=v['id'],structure=v['structure'],selectedSubpoints=v['points'])
     with patch('core.choose',return_value=layout):task=compile_plan(r,['a'])['images'][0]
     p=json.loads(task['prompt'].splitlines()[-1]);e=p['providerExecution']
     self.assertFalse(task['missingInformation']);self.assertEqual(e['schema'],'gemini-art-check-v2')
     with patch('providers.gemini.post_once',return_value=b'{}') as send:
      with self.assertRaises(RuntimeError):GeminiProvider('test-key').generate(task,[],{'reserveUSD':.5})
     body=json.loads(send.call_args.args[1]);parts=body['contents'][0]['parts']
     self.assertEqual(parts[0]['text'],e['renderBrief']);self.assertEqual(parts[-1]['text'],e['finalCheck'])
     relation=p['image']['displayContract']
     self.assertEqual(relation['category'],pid);self.assertEqual(relation['method'],v['id'])
     self.assertTrue(relation['sourceCases'])
     self.assertIn(relation['principle'],parts[0]['text'])
     self.assertIn(relation['boundary'],parts[0]['text'])
     self.assertEqual(send.call_count,1)
     self.assertNotIn('"providerExecution"',parts[0]['text'])
     c=json.loads(parts[-1]['text'].split('<PRINT_ONLY_ENGLISH_COPY>')[1].split('</PRINT_ONLY_ENGLISH_COPY>')[0])
     self.assertEqual(c,p['image']['renderCopy'])
     self.assertTrue(c['headline']);self.assertTrue(c['subtitle'])
     self.assertEqual(task['lockedCopy']['headline'],c['headline'])
     self.assertEqual(task['lockedCopy']['subheadline'],c['subtitle'])
     self.assertNotIn('compositionResolution',task['contentControls'])
     self.assertNotIn('renderCopyOnly',task['contentControls'])
     self.assertNotIn('远光',str(c));self.assertNotIn('Inter 700',str(c))
     if pid=='coverage':self.assertIn('9005 × 2',c['subtitle'])
     if pid=='lifespan':self.assertTrue(c['subtitle']);self.assertTrue(c['labels'])
     if c.get('shortStatements'):
      self.assertEqual(c['shortStatements'],[b['text'] for b in p['image']['evidenceMap']['labelBindings']])
     count+=1
  self.assertGreaterEqual(count,90)
 def test_absent_canbus_does_not_require_canbus_symbol(self):
  r=sample();r.update(count=1,images=[{'pointId':'electronics'}]);r['product']['facts']='without CANBUS'
  p=json.loads(compile_plan(r,['a'])['images'][0]['prompt'].splitlines()[-1])
  self.assertNotIn('CANBUS',p['image']['layoutPlan']['structure'])
  self.assertNotIn('CANBUS',p['image']['renderCopy']['headline'])
 def test_unlimited_authorization_expires_and_preserves_ledger(self):
  with tempfile.TemporaryDirectory() as root:
   s=Store(root);r=s.save(sample(),[{'name':'p.png','base64':PNG}]);fake=Fake();g=Generation(s,fake)
   now=datetime.now(timezone.utc);day=now.date().isoformat();local=now.astimezone(ZoneInfo('America/Los_Angeles')).date()
   s._write(s.root/'generation-budget.json',{day:20})
   s._write(s.root/'generation-budget-authorization.json',{'date':local.isoformat(),'timezone':'America/Los_Angeles','unlimited':True})
   self.assertTrue(g.budget_status()['unlimited']);self.assertIsNone(g.budget_status()['limitUSD'])
   g.start(r['id'],1,synchronous=True)
   self.assertEqual(g.budget_status()['reservedUSD'],20.5)
   self.assertEqual(fake.calls,1)
   self.assertEqual(g.budget_status('2099-01-01')['limitUSD'],10)
   s._write(s.root/'generation-budget-authorization.json',{'date':(local-timedelta(days=1)).isoformat(),'timezone':'America/Los_Angeles','unlimited':True})
   self.assertFalse(g.budget_status()['unlimited']);self.assertEqual(g.budget_status()['limitUSD'],10)
   with self.assertRaises(ValueError):g.start(r['id'],2,synchronous=True)
   self.assertEqual(fake.calls,1)
