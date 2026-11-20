import json, unittest
from copy import deepcopy
from unittest.mock import patch
from core import compile_plan
from test_core import sample
from variation_rules import CATALOG, choose

class SemanticLabelTests(unittest.TestCase):
 def packet(self,pid,variant,subject='led',facts='6500K',brand='TXBILMOO'):
  raw=sample();raw.update(count=1,images=[{'pointId':pid}]);raw['product'].update(type=subject,facts=facts,brand=brand)
  layout=choose(pid,[],0);layout.update(id=variant['id'],variantId=variant['id'],structure=variant['structure'],selectedSubpoints=variant['points'])
  with patch('core.choose',return_value=deepcopy(layout)):
   task=compile_plan(raw,['asset'])['images'][0]
  return json.loads(task['prompt'].splitlines()[-1])
 def test_all_methods_bind_each_printed_label_to_evidence_and_provider(self):
  for pid,variants in CATALOG.items():
   for variant in variants:
    with self.subTest(pid=pid,variant=variant['id']):
     p=self.packet(pid,variant);im=p['image'];mapping=im['evidenceMap'];labels=im['renderCopy']['labels']+im['renderCopy'].get('shortStatements',[])
     self.assertEqual(labels,[b['text'] for b in mapping['labelBindings']])
     self.assertEqual(len(labels),len(set(labels)))
     for b in mapping['labelBindings']:
      self.assertIn(b['owner'],mapping['regions']);self.assertTrue(b['evidence'])
      self.assertIn(repr(b['text']),p['providerExecution']['finalCheck'])
     self.assertLess(len(json.dumps(p).encode()),64000)
 def test_comparison_identity_is_never_a_shared_footer(self):
  for variant in CATALOG['illumination']:
   p=self.packet('illumination',variant);m=p['image']['evidenceMap'];bindings=m['labelBindings']
   self.assertEqual(bindings[0]['text'],'TXBILMOO');self.assertEqual(bindings[0]['owner'],'ours')
   self.assertEqual(bindings[1]['text'],'Halogen');self.assertEqual(bindings[1]['owner'],'baseline')
   self.assertTrue(all(b['owner']!='baseline' for b in bindings if b['role']=='benefit'))
  p=self.packet('illumination',CATALOG['illumination'][0]);self.assertIn('UPPER',p['image']['evidenceMap']['regions']['ours'])
 def test_no_direction_only_labels_or_fake_surface_copy(self):
  for pid in ('illumination','beam','tone'):
   for variant in CATALOG[pid]:
    p=self.packet(pid,variant);labels=p['image']['renderCopy']['labels']
    self.assertFalse(set(labels)&{'Road Ahead','Road Edges','Near Field','Midrange','Distance','Light Appearance','Illuminated Surface'})
  p=self.packet('beam',CATALOG['beam'][1]);self.assertIn('BOTTOM',p['image']['evidenceMap']['labelBindings'][0]['evidence'])
 def test_tone_methods_have_different_meaningful_labels_and_fact_bounds(self):
  for variant in CATALOG['tone']:
   p=self.packet('tone',variant,facts='3000K');self.assertIn('3000K',p['image']['renderCopy']['headline'])
   self.assertNotIn('Cool White',str(p['image']['renderCopy']))
   p=self.packet('tone',variant,facts='');self.assertIn('6500K',str(p['image']['renderCopy']))
   self.assertIn('COOL WHITE',p['image']['renderCopy']['headline'])
  p=self.packet('tone',CATALOG['tone'][0]);b=p['image']['evidenceMap']['labelBindings']
  self.assertEqual(b[0]['owner'],'baseline');self.assertEqual(b[1]['owner'],'ours');self.assertIn('TXBILMOO',b[1]['text'])
 def test_halogen_identity_and_negative_electronic_result(self):
  p=self.packet('illumination',CATALOG['illumination'][0],subject='halogen',brand='')
  self.assertEqual(p['image']['renderCopy']['labels'][:2],['Our Bulb','Comparison Bulb'])
  p=self.packet('electronics',CATALOG['electronics'][1]);self.assertIn('NEVER the dominant successful state',p['image']['evidenceMap']['labelBindings'][0]['evidence'])
 def test_deep_title_start_preserves_selected_theme(self):
  p=self.packet('beam',CATALOG['beam'][0]);palette=p['style']['palette']
  for j in (1,3,5):self.assertLessEqual(int(palette['headlineStart'][j:j+2],16),int(palette['accent'][j:j+2],16))
  self.assertIn(palette['headlineStart'],p['providerExecution']['finalCheck'])
  self.assertIn('first 60 percent',p['image']['colorDirection']['gradient'])
 def test_concise_benefits_across_all_category_methods(self):
  for pid,variants in CATALOG.items():
   for variant in variants:
    p=self.packet(pid,variant)
    for b in p['image']['evidenceMap']['labelBindings']:
     if b['role']=='benefit':self.assertLessEqual(len(b['text'].split()),4,(pid,b['text']))
    self.assertIn('buying concern',p['providerExecution']['finalCheck'])
    self.assertIn('never shrink the font',p['providerExecution']['finalCheck'])
    for filler in ('Make Every Step Count','Explore the details','Light Appearance'):
     self.assertNotIn(filler,str(p['image']['renderCopy']))
 def test_shortening_preserves_evidence_ownership(self):
  p=self.packet('illumination',CATALOG['illumination'][0]);m=p['image']['evidenceMap']
  b=next(b for b in m['labelBindings'] if b['text']=='Clearer Road Edges')
  self.assertEqual(b['owner'],'ours');self.assertIn('verge',b['evidence'])
  p=self.packet('beam',CATALOG['beam'][1]);m=p['image']['evidenceMap']
  self.assertEqual(m['labelBindings'][0]['text'],'Even Nearby Illumination')
  self.assertIn('BOTTOM',m['labelBindings'][0]['evidence'])

 def test_short_statements_replace_labels_without_empty_subtitle_space(self):
  p=self.packet('beam',CATALOG['beam'][0]);im=p['image']
  self.assertTrue(im['renderCopy']['subtitle'])
  self.assertEqual(im['renderCopy']['labels'],[])
  self.assertEqual(len(im['renderCopy']['shortStatements']),3)
  self.assertEqual(im['evidenceMap']['copyStructure']['mode'],'headline-subtitle-statements')
  self.assertIn('subtitle',im['layoutExecution']['title'])
  v=next(v for v in CATALOG['electronics'] if v['id']=='function-results')
  im=self.packet('electronics',v)['image']
  self.assertTrue(im['renderCopy']['subtitle']);self.assertEqual(len(im['renderCopy']['shortStatements']),3)
  self.assertFalse(im['renderCopy']['labels'])

 def test_obvious_scenes_do_not_get_redundant_labels(self):
  v=next(v for v in CATALOG['protection'] if v['id']=='protection-detail')
  p=self.packet('protection',v);im=p['image']
  self.assertEqual(im['evidenceMap']['copyStructure']['mode'],'headline-subtitle')
  self.assertTrue(im['renderCopy']['headline']);self.assertTrue(im['renderCopy']['subtitle'])
  self.assertFalse(im['renderCopy']['labels'])
  self.assertEqual(len(im['evidenceMap']['regions']),2)
  self.assertEqual(len(im['evidenceMap']['copyStructure']['omittedCopy']),2)
  self.assertIn('needs no labels',im['layoutExecution']['labels'])
  self.assertIn('annotation zone is optional',im['colorDirection']['balance'])
