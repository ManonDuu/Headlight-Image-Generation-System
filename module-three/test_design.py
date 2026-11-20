import json
import unittest
from core import compile_plan
from design_rules import test_packet
from test_core import sample
class DesignChecks(unittest.TestCase):
 def test_chat_packet_uses_exact_prompts(self):
  plan=compile_plan(sample(),['asset-1']);packet=test_packet(plan)
  self.assertEqual([i['prompt'] for i in packet['images']],[i['prompt'] for i in plan['images']])
  self.assertEqual(packet['sharedDesign'],plan['setDesign']);self.assertEqual(packet['paidRequests'],0)
 def test_order_does_not_force_layout(self):
  raw=sample();one=compile_plan(raw,['asset-1']);raw['images'].reverse();two=compile_plan(raw,['asset-1'])
  self.assertEqual(one['images'][0]['visualDirection'],two['images'][1]['visualDirection'])
  self.assertEqual(two['images'][0]['pointId'],'thermal')
 def test_outline_and_contract_in_every_prompt(self):
  plan=compile_plan(sample(),['asset-1'])
  for task in plan['images']:
   payload=json.loads(task['prompt'].splitlines()[-1]);self.assertEqual(payload['setDesign']['revision'],plan['setDesign']['revision']);self.assertEqual(len(payload['setOutline']),2);self.assertIn('layoutPlan',payload['image'])
 def test_multiple_assets_distributed_without_model_inference(self):
  raw=sample();raw['images']=[{'pointId':'thermal'},{'pointId':'size'}]
  plan=compile_plan(raw,['photo-A','photo-B'])
  self.assertEqual([t['assetIds'] for t in plan['images']],[['photo-A'],['photo-B']])
  self.assertIn('Do not infer which bulb model',plan['images'][0]['prompt'])
 def test_coverage_omits_product_photos(self):
  raw=sample();raw['images'][0]={'pointId':'coverage'}
  plan=compile_plan(raw,['photo-A','photo-B'])
  self.assertEqual(plan['images'][0]['assetIds'],[])
  self.assertEqual(plan['images'][0]['productPhotoPolicy'],'omit')
  self.assertEqual(plan['images'][1]['assetIds'],['photo-A'])
 def test_effect_images_allow_optional_identity_without_forcing_bulbs(self):
  for pid in ['illumination','tone','beam','protection','electronics','lifespan']:
   raw=sample();raw['count']=1;raw['images']=[{'pointId':pid}]
   task=compile_plan(raw,['photo-A'])['images'][0]
   self.assertEqual(task['assetIds'],['photo-A'])
   self.assertEqual(task['productPhotoPolicy'],'optional-selected-reference')
   self.assertIn('NEVER requires displaying the bulb',task['prompt'])
 def test_copy_case_resolved_before_generation(self):
  raw=sample();raw['images'][0]={'pointId':'tone'}
  p=compile_plan(raw,['photo-A']);self.assertEqual(p['images'][0]['lockedCopy']['headline'],'6500K COOL WHITE')
  raw['style']['titleCase']='title-sentence'
  p=compile_plan(raw,['photo-A']);self.assertEqual(p['images'][0]['lockedCopy']['headline'],'6500K Cool White')
 def test_no_provider_transport_in_test_packet(self):
  packet=test_packet(compile_plan(sample(),['asset-1']))
  self.assertNotIn('generationConfig',json.dumps(packet));self.assertNotIn('api_key',json.dumps(packet));self.assertGreaterEqual(len(packet['reviewChecklist']),7)
  self.assertTrue(any('evidenceMap' in item for item in packet['reviewChecklist']))
 def test_all_categories_expand_without_customer_microcopy(self):
  from core import POINTS
  from display_library import CATALOG, SOURCES
  self.assertEqual(set(CATALOG),set(POINTS))
  for pid,entry in CATALOG.items():
   raw=sample();raw['count']=1;raw['images']=[{'pointId':pid}];raw['product']['facts']=''
   task=compile_plan(raw,['photo-A'])['images'][0]
   self.assertEqual(task['displayLibrary']['subpoints'],entry['subpoints'])
   self.assertGreaterEqual(len(task['displayLibrary']['methods']),3)
   self.assertNotIn('请补充与此卖点相关的产品参数或特性',task['missingInformation'])
   self.assertEqual(task['copyMode'],'bounded-layout-copy')
   for method in entry['methods']:
    self.assertTrue(method['sourceIds'])
    self.assertTrue(set(method['sourceIds']).issubset(SOURCES))
 def test_prompts_only_include_current_category_vocabulary(self):
  raw=sample();raw['count']=1;raw['images']=[{'pointId':'beam'}]
  task=compile_plan(raw,['photo-A'])['images'][0]
  self.assertNotIn('多环境组合',task['prompt'])
  self.assertIn(task['layoutPlan']['structure'],task['prompt'])
  self.assertNotIn('Render ONLY the exact strings',task['prompt'])
 def test_custom_point_is_not_replaced_by_generic_category(self):
  raw=sample();raw['count']=1;raw['images']=[{'pointId':'custom-quiet','sellingPoint':'Quiet fan operation'}]
  task=compile_plan(raw,['photo-A'])['images'][0]
  self.assertEqual(task['displayLibrary']['subpoints'],['Quiet fan operation'])
 def test_fallback_subtitles_have_no_trailing_period(self):
  from design_rules import locked_copy
  raw=sample();raw['product']['fitment']='Fits Example Truck.'
  for pid in ['illumination','tone','fitment','thermal','protection']:
   self.assertFalse(locked_copy(pid,raw['product'],'title-sentence')['subheadline'].endswith('.'))
 def test_protection_does_not_expand_ip_into_temperature(self):
  raw=sample();raw['count']=1;raw['images']=[{'pointId':'protection'}];raw['product']['facts']='IP68'
  task=compile_plan(raw,['photo-A'])['images'][0]
  groups=task['contentControls']['contentGroups']
  self.assertNotIn('耐高温',[t for g in groups for t in g['topics']])
  self.assertIn('High temperature',task['contentControls']['prohibitedDefaultClaims'])
  payload=json.loads(task['prompt'].splitlines()[-1])
  self.assertEqual(payload['image']['claimBoundary'],task['contentControls']['claimBoundary'])
 def test_case_roles_change_independently_of_headline(self):
  from content_controls import content_controls
  a=content_controls('beam','title-sentence')['textRoles']
  b=content_controls('beam','upper-title')['textRoles']
  self.assertEqual(a['exampleSubtitle'],'Light for the road ahead')
  self.assertEqual(b['exampleSubtitle'],'Light For The Road Ahead')
  self.assertNotEqual(a['headline'],a['subtitleAndExplanations'])
  self.assertTrue(a['noTrailingPeriod'])
 def test_beam_topics_share_visual_homes_instead_of_duplicate_panels(self):
  from content_controls import content_controls
  groups=content_controls('beam','title-sentence')['contentGroups']
  self.assertEqual(len(groups[0]['topics']),3)
  self.assertIn('不要再加第二幅相似道路全景',groups[0]['visualHome'])
 def test_protection_retains_distinct_weather_contexts(self):
  from content_controls import content_controls
  c=content_controls('protection','title-sentence')
  self.assertEqual(c['sceneCoverage']['required'],['Rain','Snow','Fog','Dust'])
  self.assertEqual(c['sceneCoverage']['minimumDistinctTopics'],4)
  self.assertEqual(c['sceneCoverage']['representation'],'icons-or-scenes')
  self.assertEqual(c['sceneCoverage']['minimumDistinctScenes'],0)
  self.assertNotIn('雪山或积雪行驶场景',c['prohibitedDefaultVisuals'])
  self.assertIn('耐温结论',c['conditionalTopics']['温度条件'])
 def test_spacing_and_supporting_product_limits_are_explicit(self):
  from content_controls import content_controls
  c=content_controls('beam','title-sentence')['layoutMetrics']
  self.assertGreaterEqual(c['headlineToSubtitleGapMinHeight'],0.025)
  self.assertLessEqual(c['productMaxAreaWhenSupporting'],0.18)
if __name__=='__main__':unittest.main()
