import json
import unittest
from core import compile_plan, POINTS
from test_core import sample
from layout_templates import ALLOWED, TEMPLATES, resolve_layout

class BoundedLayouts(unittest.TestCase):
 def test_comparison_and_steps_require_explicit_ready_inputs(self):
  self.assertEqual(resolve_layout('illumination',[])['id'],'scene-details')
  self.assertEqual(resolve_layout('illumination',[],{'comparisonReady':True})['id'],'comparison')
  self.assertEqual(resolve_layout('installation',[])['id'],'detail-callouts')
  self.assertEqual(resolve_layout('installation',[],{'installationStepsReady':True})['id'],'steps')
  self.assertEqual(resolve_layout('coverage',[],{'comparisonReady':True})['id'],'information')
 def test_saved_archive_does_not_reintroduce_choices_into_generation(self):
  for pid in POINTS:
   raw=sample();raw['count']=1;raw['images']=[{'pointId':pid}]
   task=compile_plan(raw,['photo'])['images'][0]
   payload=json.loads(task['prompt'].splitlines()[-1])['image']
   self.assertNotIn('displayLibrary',payload)
   self.assertNotIn('contentControls',payload)
   self.assertNotIn('renderCopyOnly',task['prompt'])
   self.assertEqual(payload['layoutPlan']['id'],task['layoutPlan']['id'])
   self.assertNotIn('allowedFamilies',payload['layoutPlan'])
   from variation_rules import CATALOG
   self.assertIn(task['layoutPlan']['id'],[v['id'] for v in CATALOG[pid]])
 def test_all_categories_are_bounded_and_protection_keeps_four_topics(self):
  self.assertEqual(len(TEMPLATES),6)
  self.assertEqual(set(ALLOWED),set(POINTS))
  self.assertTrue(all(1<=len(v)<=2 for v in ALLOWED.values()))
  layout=resolve_layout('protection',[])
  self.assertEqual(layout['visualHomes']['功能图标组'],['Rain','Snow','Fog','Dust'])
  self.assertEqual(layout['limits']['auxiliaryPanels'],0)
 def test_custom_point_stays_in_information_layout(self):
  layout=resolve_layout('custom-anything',['User selected point'])
  self.assertEqual(layout['id'],'information')
  self.assertEqual(layout['visualHomes']['主题视觉'],['User selected point'])

if __name__=='__main__':unittest.main()
