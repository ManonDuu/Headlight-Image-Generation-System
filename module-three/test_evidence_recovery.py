import json,unittest
from unittest.mock import patch
from core import compile_plan
from test_core import sample
from variation_rules import CATALOG,choose
from providers.gemini import GeminiProvider

class EvidenceRecoveryTests(unittest.TestCase):
 def packet(self,pid,variant=None,facts='',kind='led'):
  r=sample();r.update(count=1,images=[{'pointId':pid}]);r['product'].update(type=kind,facts=facts)
  if variant:
   v=next(v for v in CATALOG[pid] if v['id']==variant);layout=choose(pid,[],17);layout.update(id=v['id'],variantId=v['id'],structure=v['structure'])
   with patch('core.choose',return_value=layout):t=compile_plan(r,['a'])['images'][0]
  else:t=compile_plan(r,['a'])['images'][0]
  return t,json.loads(t['prompt'].splitlines()[-1])
 def test_white_catalog_defaults_and_explicit_override_in_every_scene(self):
  for kind,value,facts in [('led',6500,''),('mixed',6500,''),('halogen',6000,''),('halogen',6500,'6500K'),('led',3000,'3000K')]:
   for pid in CATALOG:
    if kind=='halogen' and pid in ('electronics','thermal'):continue
    t,p=self.packet(pid,facts=facts,kind=kind)
    self.assertEqual(p['product']['lightColor']['kelvin'],value)
    self.assertIn(str(value)+'K',p['providerExecution']['finalCheck'])
    self.assertIn('EVERY scene',p['providerExecution']['finalCheck'])
    self.assertIn('warm light is permitted only',p['providerExecution']['finalCheck'].lower())
    self.assertIn('explicit user-supplied different temperature overrides',p['providerExecution']['finalCheck'])
 def test_lifespan_recovers_methods_and_varies_copy(self):
  titles=[]
  for v in CATALOG['lifespan']:
   t,p=self.packet('lifespan',v['id']);c=p['image']['renderCopy'];titles.append(c['headline'])
   self.assertTrue(c['subtitle']);self.assertTrue(c['labels']);self.assertNotIn('One short headline only',t['prompt'])
   self.assertNotIn('50,000',str(c));self.assertNotIn('200',str(c))
   self.assertIn('clock',p['image']['layoutPlan']['structure']) if v['id']=='life-structure' else None
  self.assertEqual(len(set(titles)),3)
  t,p=self.packet('lifespan','life-structure',facts='lifespan: up to 50,000 hours')
  self.assertIn('UP TO 50,000 HOURS',p['image']['renderCopy']['headline'])
  t,p=self.packet('lifespan','decay-compare',facts='lifespan: 10x vs halogen')
  self.assertIn('10×',p['image']['renderCopy']['headline'])
 def test_size_explains_spatial_relationship_not_fin_names(self):
  for v in CATALOG['size']:
   t,p=self.packet('size',v['id']);im=p['image']
   self.assertIn('Rear Space Needed',im['renderCopy']['labels'])
   self.assertIn('BEHIND',im['evidenceMap']['regions']['rear'])
   self.assertIn('not just a dot',im['evidenceMap']['regions']['rear'])
   self.assertIn('space',im['layoutPlan']['structure'].lower()) if v['id']!='dimension-views' else None
 def test_white_header_and_logos_prohibited_in_final_instruction(self):
  t,p=self.packet('illumination','road-states')
  self.assertIn('NO separate header',p['image']['layoutPlan']['structure'])
  self.assertIn('full-width blank header',p['providerExecution']['finalCheck'])
  self.assertIn('remove grille badges',p['providerExecution']['finalCheck'])
 def test_provider_validation_error_retains_safe_diagnostics(self):
  def fake(endpoint,body,key,diagnostic):
   diagnostic.update(httpStatus=200,totalSeconds=35)
   return b'{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"not saved"}]}}]}'
  with patch('providers.gemini.post_once',side_effect=fake):
   with self.assertRaises(RuntimeError) as e:GeminiProvider('test-key').generate({'prompt':'frozen','ratio':'1:1'},[],{'reserveUSD':.5})
  self.assertEqual(e.exception.diagnostic['httpStatus'],200)
  self.assertEqual(e.exception.diagnostic['imagePartCount'],0)
  self.assertEqual(e.exception.diagnostic['validationFailure'],'missing-or-multiple-images')
  self.assertNotIn('not saved',str(e.exception.diagnostic))
