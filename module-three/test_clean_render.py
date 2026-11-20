import json,re,unittest
from unittest.mock import patch
from core import compile_plan
from test_core import sample
from providers.gemini import GeminiProvider
from style_contract import theme

class CleanRenderTests(unittest.TestCase):
 def task(self,pid,configuration='9005*2 远光',facts='6500K'):
  raw=sample();raw.update(count=1,images=[{'pointId':pid}]);raw['product'].update(configuration=configuration,facts=facts)
  t=compile_plan(raw,['a'])['images'][0]
  return t,json.loads(t['prompt'].splitlines()[-1])
 def test_coverage_uses_product_facts_not_design_fields(self):
  t,p=self.task('coverage');c=p['image']['renderCopy'];text=json.dumps(c,ensure_ascii=False)
  self.assertIn('9005 × 2',text);self.assertIn('6500K',text);self.assertIn('LED',text)
  self.assertFalse(re.search(r'[\u3400-\u9fff]',text))
  self.assertNotIn('High Beam',text);self.assertNotIn('Low Beam',text)
  self.assertNotIn('Inter',text);self.assertNotIn('#',text)
  self.assertEqual(c['labels'],['Headlamp Location'])
  self.assertIn('whole external headlamp',p['image']['layoutPlan']['structure'])
 def test_unknown_fields_are_not_filled(self):
  t,p=self.task('coverage',configuration='未知型号',facts='')
  self.assertEqual(p['image']['renderCopy']['subtitle'],'6500K · LED')
  self.assertFalse(t['missingInformation'])
  self.assertNotIn('9005',str(p['image']['renderCopy']))
 def test_lifespan_explains_design_and_use_without_inventing_hours(self):
  t,p=self.task('lifespan');c=p['image']['renderCopy']
  self.assertTrue(c['headline']);self.assertTrue(c['subtitle']);self.assertEqual(len(c['labels']),2)
  self.assertNotIn('50,000',str(c))
  self.assertEqual(p['image']['evidenceMap']['copyStructure']['mode'],'headline-subtitle-labels')
 def test_saturated_whole_title_and_no_white_perimeter(self):
  self.assertEqual(theme('#f4b400')['headlineStart'],'#f4b400')
  t,p=self.task('coverage')
  self.assertIn('EVERY word',p['image']['colorDirection']['headline'])
  self.assertIn('white/near-white margins',p['providerExecution']['finalCheck'])
 def test_provider_sends_frozen_execution_brief_not_planning_packet(self):
  t,p=self.task('coverage');e=p['providerExecution']
  with patch('providers.gemini.post_once',return_value=b'{}') as send:
   with self.assertRaises(RuntimeError):GeminiProvider('test-key').generate(t,[],{'reserveUSD':.5})
  parts=json.loads(send.call_args.args[1])['contents'][0]['parts']
  self.assertEqual(parts[0]['text'],e['renderBrief']);self.assertNotEqual(parts[0]['text'],t['prompt'])
  self.assertEqual(parts[-1]['text'],e['finalCheck'])
  self.assertNotIn('"providerExecution"',parts[0]['text'])
  self.assertNotIn('"omittedCopy"',parts[-1]['text'])
  whitelist=parts[-1]['text'].split('<PRINT_ONLY_ENGLISH_COPY>')[1].split('</PRINT_ONLY_ENGLISH_COPY>')[0]
  self.assertEqual(json.loads(whitelist),p['image']['renderCopy'])
 def test_unsupported_chinese_copy_fails_before_submission(self):
  raw=sample();raw.update(count=1,images=[{'pointId':'fitment'}]);raw['product']['fitment']='适配未知车型'
  with self.assertRaisesRegex(ValueError,'只能使用英文'):compile_plan(raw,['a'])

 def test_final_copy_has_no_redundant_installation_or_cooling_subtitle(self):
  for pid in ('installation','thermal'):
   t,p=self.task(pid);c=p['image']['renderCopy']
   self.assertTrue(c['subtitle']);self.assertEqual(len(c['labels']),3 if pid=='installation' else 2)
   self.assertEqual(p['image']['evidenceMap']['copyStructure']['mode'],'headline-subtitle-labels')
   self.assertIn('One uniform neutral ink',p['providerExecution']['finalCheck'])
   self.assertIn('ONE complete surface',p['providerExecution']['finalCheck'])
