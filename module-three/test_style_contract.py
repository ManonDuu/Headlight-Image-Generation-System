import json,unittest
from core import compile_plan,normalize
from test_core import sample
from style_contract import theme
class StyleContractTests(unittest.TestCase):
 def test_default_ip68_flows_into_actual_prompt_and_copy(self):
  r=sample();r['product']['facts']='6500K';r['count']=1;r['images']=[{'pointId':'protection'}]
  p=compile_plan(r,['a']);payload=json.loads(p['images'][0]['prompt'].splitlines()[-1])
  self.assertEqual(payload['product']['protectionRating'],{'value':'IP68','source':'user-confirmed-catalog-default'})
  self.assertIn('IP68',payload['image']['renderCopy']['headline']);self.assertNotIn('IPXX',str(payload['image']['renderCopy']))
  self.assertNotIn('copyDraft',payload['image'])
 def test_explicit_rating_overrides_default_without_mutating_original_facts(self):
  for value in ['IP67','IP65','IP6X']:
   r=sample();r['product']['facts']='6500K '+value;p=normalize(r)
   self.assertEqual(p['product']['protectionRating']['value'],value)
   self.assertEqual(p['product']['facts'],r['product']['facts'])
 def test_user_color_stays_exact_and_does_not_choose_fixed_background(self):
  for color in ['#f59e0b','#F4B400','#00e8a0']:
   t=theme(color);self.assertEqual(t['accent'],color.lower());self.assertNotIn('background',t);self.assertNotIn('anchor',t)
 def test_typography_full_bleed_and_copy_boundary_reach_provider_prompt(self):
  p=compile_plan(sample(),['a'])
  for task in p['images']:
   data=json.loads(task['prompt'].splitlines()[-1]);font=data['style']['typography']
   self.assertEqual(font['headline']['weight'],900);self.assertEqual(font['subtitle']['weight'],700)
   self.assertIn('FULL-BLEED',task['prompt']);self.assertIn('Render ONLY the text strings',task['prompt'])
   self.assertNotIn('or a visually consistent sans-serif',task['prompt'])
   self.assertIn('renderCopy',data['image'])

 def test_color_roles_reach_all_categories_without_changing_user_color(self):
  from variation_rules import CATALOG
  for category in CATALOG:
   r=sample();r['count']=1;r['images']=[{'pointId':category}]
   p=compile_plan(r,['a']);payload=json.loads(p['images'][0]['prompt'].splitlines()[-1])
   direction=payload['image']['colorDirection']
   self.assertEqual(direction['accent'],r['style']['primaryColor'])
   self.assertEqual(payload['setDesign']['revision'],p['rulesRevision'])
   self.assertIn('gradient',direction['headline'])
   if payload['image']['renderCopy']['labels']:self.assertIn('gradient',direction['labels'])
   else:self.assertNotIn('mandatory gradient tabs',direction['labels'])
   if category=='electronics':self.assertIn('headlights ON',direction['scene']);self.assertNotIn('brightly sunlit',direction['scene'])
   if category=='protection':self.assertIn('only environments in the selected composition',direction['scene'])

 def test_canbus_default_and_explicit_exclusion_reach_copy(self):
  for facts,expected in [('6500K',True),('without CANBUS',False),('不支持 CANBUS',False)]:
   r=sample();r['count']=1;r['images']=[{'pointId':'electronics'}];r['product']['facts']=facts
   p=compile_plan(r,['a']);data=json.loads(p['images'][0]['prompt'].splitlines()[-1])
   self.assertEqual(data['product']['canbus']['value'],expected)
   self.assertEqual('CANBUS' in data['image']['renderCopy']['headline'],expected)
   self.assertNotIn('Vehicle Compatibility',data['image']['renderCopy']['labels'])

 def test_gemini_request_reinforces_frozen_set_color_and_label_size(self):
  from unittest.mock import patch
  from providers.gemini import GeminiProvider
  r=sample();r['count']=1;r['images']=[{'pointId':'beam'}];r['style']['primaryColor']='#8426d9'
  plan=compile_plan(r,['a']);calls=[]
  def capture(endpoint,body,key,diagnostic):
   calls.append(json.loads(body));return b'{}'
  with patch('providers.gemini.post_once',capture):
   with self.assertRaises(RuntimeError):GeminiProvider('fake-test-key').generate(plan['images'][0],[],{'reserveUSD':.5})
  self.assertEqual(len(calls),1)
  guard=calls[0]['contents'][0]['parts'][-1]['text']
  self.assertIn('#8426d9',guard);self.assertIn('labels bold',guard);self.assertIn('3.2%',guard)
  self.assertIn('no dark foreground gap',guard)
