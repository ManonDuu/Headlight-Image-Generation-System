import unittest,json
from style_contract import resolved_lifespan
from core import compile_plan
from test_core import sample

class LifespanDefaults(unittest.TestCase):
 def test_default_and_overrides(self):
  self.assertEqual(resolved_lifespan('6500K')['value'],'5000+ Hours')
  for facts,value in [('寿命：10000小时','10000 Hours'),('寿命 8000+小时','8000+ Hours'),('lifespan: up to 50,000 hours','Up To 50,000 Hours'),('15000 hrs','15000 Hours'),('寿命至少6000小时','At Least 6000 Hours'),('寿命1万小时以上','10000+ Hours')]:
   with self.subTest(facts=facts):
    life=resolved_lifespan(facts);self.assertEqual(life['value'],value);self.assertEqual(life['source'],'user-input')
 def test_test_duration_is_not_lifespan(self):
  self.assertEqual(resolved_lifespan('100 hours aging test')['source'],'user-confirmed-catalog-default')
 def test_saved_prompt_receives_resolved_value(self):
  for facts in ('6500K','lifespan 12000 hours'):
   r=sample();r.update(count=1,images=[{'pointId':'lifespan'}]);r['product']['facts']=facts
   p=json.loads(compile_plan(r,['a'])['images'][0]['prompt'].splitlines()[-1])
   value=p['product']['lifespan']['value']
   self.assertIn(value.lower(),str(p['image']['renderCopy']).lower())
   self.assertIn(value.lower(),p['providerExecution']['finalCheck'].lower())
