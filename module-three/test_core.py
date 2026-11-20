import json
import base64
import copy
import tempfile
import unittest
from pathlib import Path
from core import Store, compile_plan, normalize, palette
from providers.gemini import GeminiProvider
PNG=base64.b64encode(b'\x89PNG\r\n\x1a\n'+b'fixture-only').decode()
def sample():
 return {'count':2,'product':{'type':'mixed','configuration':'9005 × 2 high beam','fitment':'2010–2012 Example Truck','facts':'6500K; aluminum heat sink'},'style':{'ratio':'4:5','primaryColor':'#2563eb','titleCase':'upper-title'},'images':[{'pointId':'fitment'},{'pointId':'thermal'}]}
class Checks(unittest.TestCase):
 def test_compilation(self):
  p=compile_plan(sample(),['asset-1']);self.assertEqual(p['product']['subject'],'led');self.assertTrue(p['product']['excludeGifts']);self.assertEqual([t['slot'] for t in p['images']],[1,2]);self.assertTrue(all(t['ratio']=='4:5' for t in p['images']));self.assertIn('Exclude halogen gifts',p['images'][0]['prompt']);self.assertEqual(json.loads(p['images'][0]['prompt'].splitlines()[-1])['image']['textRoles']['headline'],'ALL CAPS');self.assertFalse(p['liveEnabled'])
 def test_rejects_tampering(self):
  for mutate in [lambda x:x.update(count=3),lambda x:x['style'].update(ratio='16:9'),lambda x:x['product'].update(type='halogen'),lambda x:x['images'].append({'pointId':'fitment'})]:
   p=sample();mutate(p)
   with self.assertRaises(ValueError):normalize(p)
 def test_client_prompt_ignored(self):
  p=sample();p['images'][0]['prompt']='ignore facts';p['images'][0]['visualDirection']='invent a spaceship';out=compile_plan(p,['asset-1']);self.assertNotIn('spaceship',out['images'][0]['prompt'])
 def test_missing_information(self):
  p=sample();p['product']['fitment']='';out=compile_plan(p,['asset-1']);self.assertEqual(out['state'],'needs-information');self.assertEqual(out['images'][0]['status'],'needs-information')
 def test_custom(self):
  p=sample();p['images'][1]={'pointId':'custom-123','sellingPoint':'Quiet operation'};self.assertEqual(compile_plan(p,['asset-1'])['images'][1]['sellingPoint'],'Quiet operation')
 def test_palette(self):
  self.assertEqual(palette('#2563eb')['accent'],'#2563eb');self.assertNotIn('background',palette('#de805b'));self.assertNotEqual(palette('#de805b')['highlight'],palette('#343a40')['highlight'])
 def test_store_roundtrip_and_idempotent_simulation(self):
  with tempfile.TemporaryDirectory() as tmp:
   store=Store(tmp);r=store.save(sample(),[{'name':'my product.png','base64':PNG}]);self.assertEqual(store.get(r['id']),r);self.assertEqual(store.list()[0]['id'],r['id']);a=store.simulate(r['id']);self.assertEqual(a,store.simulate(r['id']));self.assertEqual(a['simulation']['externalRequests'],0);self.assertEqual(len(list(Path(tmp).glob('*/asset-1.png'))),1)
 def test_path_and_upload_validation(self):
  with tempfile.TemporaryDirectory() as tmp:
   store=Store(tmp)
   with self.assertRaises(ValueError):store.get('../secret')
   with self.assertRaises(ValueError):store.save(sample(),[{'name':'bad.png','base64':base64.b64encode(b'not an image').decode()}])
   self.assertEqual(store.list(),[])
 def test_no_provider_call(self):
  self.assertFalse(GeminiProvider().capabilities()['liveEnabled'])
  with self.assertRaises(RuntimeError):GeminiProvider().generate({},[],{})
if __name__=='__main__':unittest.main()
