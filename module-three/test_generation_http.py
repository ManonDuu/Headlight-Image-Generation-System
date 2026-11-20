import base64,json,tempfile,threading,time,unittest,urllib.request,urllib.error
from http.server import ThreadingHTTPServer
from server import Handler
from core import Store
from generation import Generation
from test_generation import Fake
from test_core import sample,PNG
class HTTPChecks(unittest.TestCase):
 def test_prepare_generate_read_and_reject_duplicate(self):
  with tempfile.TemporaryDirectory() as d:
   server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.store=Store(d);server.provider=Fake();server.generation=Generation(server.store,server.provider)
   threading.Thread(target=server.serve_forever,daemon=True).start()
   url='http://127.0.0.1:'+str(server.server_port)
   def request(path,body=None,origin=None):
    headers={'Content-Type':'application/json'}
    if origin:headers['Origin']=origin
    req=urllib.request.Request(url+path,data=json.dumps(body).encode() if body is not None else None,headers=headers)
    return urllib.request.urlopen(req,timeout=3)
   try:
    with request('/api/prepare',{'plan':sample(),'uploads':[{'name':'p.png','base64':PNG}]}) as f:r=json.load(f)
    with request('/api/tasks/'+r['id']+'/generate',{'slot':1}) as f:self.assertEqual(f.status,202)
    for _ in range(100):
     with request('/api/tasks/'+r['id']) as f:result=json.load(f)
     if result['generation']['images'][0]['state']!='running':break
     time.sleep(.01)
    with request('/api/tasks/'+r['id']+'/results/1') as f:self.assertEqual(f.read(),b'fake-test-only');self.assertEqual(f.headers['Content-Type'],'image/png')
    with self.assertRaises(urllib.error.HTTPError):request('/api/tasks/'+r['id']+'/generate',{'slot':1})
    with self.assertRaises(urllib.error.HTTPError):request('/api/prepare',{},'https://example.com')
    self.assertEqual(server.provider.calls,1)
    import io,zipfile
    with request('/api/tasks/'+r['id']+'/download') as f:
     self.assertEqual(f.headers['Content-Type'],'application/zip')
     with zipfile.ZipFile(io.BytesIO(f.read())) as z:
      self.assertEqual(z.read('result-1.png'),b'fake-test-only')
      self.assertIn('status.json',z.namelist())

   finally:server.shutdown();server.server_close()
