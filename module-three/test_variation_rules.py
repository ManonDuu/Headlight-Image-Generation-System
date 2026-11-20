import tempfile
import unittest
from core import Store, compile_plan, POINTS
from test_core import sample, PNG
from variation_rules import CATALOG, choose, STABLE_CATEGORIES

class VariationChecks(unittest.TestCase):
 def test_all_eleven_rotate_without_recent_two(self):
  self.assertEqual(set(CATALOG),set(POINTS))
  for category in POINTS:
   history=[]
   for i in range(12):
    v=choose(category,[],i,history)
    if category in STABLE_CATEGORIES and history:
     self.assertEqual(v['variantId'],history[-1]['variantId'])
    else:self.assertNotIn(v['variantId'],[t['variantId'] for t in history[-2:]])
    history.append({'pointId':category,'variantId':v['variantId']})
 def test_restart_preserves_planning_history_and_saved_prompt(self):
  with tempfile.TemporaryDirectory() as d:
   raw=sample();raw['count']=1;raw['images']=[{'pointId':'protection'}]
   records=[Store(d).save(raw,[{'name':'p.png','base64':PNG}]) for _ in range(3)]
   self.assertEqual(len({r['plan']['images'][0]['layoutPlan']['id'] for r in records}),3)
   for r in records:self.assertEqual(Store(d).get(r['id'])['plan'],r['plan'])
 def test_seed_replay_and_fits(self):
  raw=sample();raw['product']['fitment']='Ram 1500 2009–2024'
  a=compile_plan(raw,['p'],seed=42);b=compile_plan(raw,['p'],seed=42)
  self.assertEqual(a,b)
  self.assertTrue(a['images'][0]['lockedCopy']['subheadline'].startswith('Fits '))
  raw['product']['fitment']='Fits Ram 1500'
  self.assertEqual(compile_plan(raw,['p'])['images'][0]['lockedCopy']['subheadline'],'Fits Ram 1500')
 def test_all_prompts_use_current_rules_not_legacy_prohibitions(self):
  for category in POINTS:
   raw=sample();raw['count']=1;raw['images']=[{'pointId':category}]
   t=compile_plan(raw,['p'])['images'][0]
   if category in ('illumination','beam','tone'):self.assertIn('No concentrated circular hot spots',t['prompt'])
   else:self.assertNotIn('Lighting must be broad',t['prompt'])
   self.assertIn('EVERY vehicle fitment text must start with Fits',t['prompt'])
   self.assertNotIn('gradients on labels',t['prompt'])
   self.assertNotIn('规则草案，尚无用户认可',t['prompt'])
   self.assertTrue(t['layoutPlan']['selectedSubpoints'])

if __name__=='__main__':unittest.main()
