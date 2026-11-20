"""Regression audit across the actual category/variant/color/case combinations."""
import json
import unittest
from copy import deepcopy
from unittest.mock import patch
from core import compile_plan
from test_core import sample
from variation_rules import CATALOG, choose
from providers.gemini import GeminiProvider

class PromptAudit(unittest.TestCase):
 def test_every_variant_keeps_set_contract_and_category_scope(self):
  checked=0
  for category,variants in CATALOG.items():
   for variant in variants:
    layout=choose(category,[],17)
    layout.update(id=variant['id'],variantId=variant['id'],structure=variant['structure'],selectedSubpoints=variant['points'])
    for color in ('#2563eb','#F4B400','#be123c'):
     for case in ('upper-title','title-sentence'):
      raw=sample();raw.update(count=1,images=[{'pointId':category}]);raw['style'].update(primaryColor=color,titleCase=case)
      with patch('core.choose',return_value=deepcopy(layout)):
       plan=compile_plan(raw,['a'])
      prompt=plan['images'][0]['prompt'];packet=json.loads(prompt.splitlines()[-1]);image=packet['image']
      self.assertEqual(packet['style']['palette']['accent'],color.lower())
      self.assertNotIn('copyDraft',image)
      self.assertNotIn('gold labels',prompt);self.assertNotIn('Ram-shaped',prompt)
      self.assertNotIn('6500K',str(image['subpoints']))
      self.assertNotIn('typography',packet['setDesign'])
      self.assertEqual(packet['style']['typography']['labels']['weight'],700)
      self.assertIn(color.lower(),packet['providerExecution']['finalCheck'])
      if category!='installation':self.assertNotIn('Installation: keep',prompt)
      if category!='protection':self.assertNotIn('Weather-context methods',prompt)
      if category not in ('illumination','beam','tone'):self.assertNotIn('Lighting must be broad',prompt)
      checked+=1
  self.assertGreaterEqual(checked,198)

 def test_provider_uses_saved_check_verbatim_without_recompiling(self):
  task=compile_plan(sample(),['a'])['images'][0]
  packet=json.loads(task['prompt'].splitlines()[-1]);frozen=packet['providerExecution']['finalCheck']
  with patch('providers.gemini.post_once',return_value=b'{}') as send:
   with self.assertRaises(RuntimeError):GeminiProvider('test-key').generate(task,[],{'reserveUSD':.5})
  body=json.loads(send.call_args.args[1])
  self.assertEqual(body['contents'][0]['parts'][-1]['text'],frozen)
  self.assertEqual(send.call_count,1)

 def test_dominance_label_geometry_and_electronic_evidence(self):
  raw=sample();raw.update(count=2,images=[{'pointId':'illumination'},{'pointId':'electronics'}])
  plan=compile_plan(raw,['a'])
  for item in plan['images']:
   data=json.loads(item['prompt'].splitlines()[-1]);execution=data['image']['layoutExecution']
   self.assertIn('INSIDE one colored',execution['labels'])
   self.assertIn('Inter 900',execution['title'])
   self.assertEqual(data['style']['typography']['subtitle']['weight'],700)
   if item['pointId']=='illumination':self.assertIn('clear LED road area',execution['dominance'])
   else:
    self.assertIn('headlights ON at night',execution['evidence'])
    self.assertIn('ordinary road photo as proof',execution['evidence'])
    self.assertIn('radio/audio symbols with clear music',execution['evidence'])
  stacked=next(v for v in CATALOG['illumination'] if v['id']=='road-states')['structure']
  self.assertIn('54 percent',stacked);self.assertIn('28 percent',stacked)
  self.assertNotIn('Two equal',stacked)
