import base64,json,sys,tempfile,time,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'product-retouch'))
from jobs import Jobs
from providers import RenderResult
from rules import VERSION,PRESETS
class Fake:
 name='fixture';model='fixture';connected=True
 def __init__(self,fail=False):self.calls=0;self.fail=fail
 def generate(self,req):
  self.calls+=1
  if self.fail:raise RuntimeError('fixture failure')
  return RenderResult(req.image,'image/png',{'totalTokenCount':0})
class RetouchTests(unittest.TestCase):
 def payload(self,preset='refined'):
  return {'imageBase64':base64.b64encode(b'\x89PNG\r\n\x1a\nfixture').decode(),'preset':preset,'ratio':'1:1','colorMode':'preserve','lightness':0}
 def wait(self,j,ident):
  for _ in range(200):
   r=j.read(ident)
   if r['state']!='running':return r
   time.sleep(.005)
  self.fail('worker timeout')
 def test_modes_duplicate_and_persistence(self):
  with tempfile.TemporaryDirectory() as d:
   p=Fake();j=Jobs(d,p)
   for mode in PRESETS:
    s=j.prepare(self.payload(mode));self.assertEqual(s['rulesVersion'],VERSION)
    j.generate(s['id']);self.assertEqual(self.wait(j,s['id'])['state'],'completed')
    with self.assertRaises(ValueError):j.generate(s['id'])
   self.assertEqual(p.calls,3);self.assertEqual(len(Jobs(d,p).history()),3)
 def test_failure_no_retry_and_restart_recovery(self):
  with tempfile.TemporaryDirectory() as d:
   p=Fake(True);j=Jobs(d,p);s=j.prepare(self.payload());j.generate(s['id'])
   self.assertEqual(self.wait(j,s['id'])['state'],'stopped');self.assertEqual(p.calls,1)
   s=j.prepare(self.payload());s['state']='running';j.save(s)
   self.assertEqual(Jobs(d,p).read(s['id'])['state'],'stopped');self.assertEqual(p.calls,1)
