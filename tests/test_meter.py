import concurrent.futures,json,os,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'deploy'))
import meter
class MeterTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.old=os.environ.copy();p=Path(self.tmp.name)
  os.environ['USAGE_DB']=str(p/'usage.sqlite3');os.environ['BUDGET_CONFIG']=str(p/'budget.json')
  self.config={'timezone':'America/Los_Angeles','daily_limit_usd':1,'monthly_limit_usd':10,'per_call_limit_usd':1,'reserves_usd':{'reference':.26,'replacement':.27,'listing':.5,'retouch':.5}}
  self.write()
 def write(self):Path(os.environ['BUDGET_CONFIG']).write_text(json.dumps(self.config))
 def tearDown(self):os.environ.clear();os.environ.update(self.old);self.tmp.cleanup()
 def test_global_budget_across_modules(self):
  meter.reserve('reference','model',b'a');meter.reserve('replacement','model',b'b')
  with self.assertRaises(RuntimeError):meter.reserve('listing','model',b'c')
 def test_monthly_limit(self):
  self.config.update(daily_limit_usd=10,monthly_limit_usd=.5);self.write()
  meter.reserve('listing','m',b'x')
  with self.assertRaises(RuntimeError):meter.reserve('retouch','m',b'y')
 def test_usage_whitelist_unknown_cost_and_persistence(self):
  ident=meter.reserve('listing','m',b'private prompt')
  meter.finish(ident,200,json.dumps({'usageMetadata':{'promptTokenCount':12,'secret':'never persist'},'sensitive':'never persist'}))
  with meter.connect() as db:
   r=db.execute('SELECT usage_json,estimated_micro,billed_micro,actor FROM calls').fetchone()
  self.assertEqual(json.loads(r[0]),{'promptTokenCount':12});self.assertEqual(r[1:],[None,None,'system-shared'] if isinstance(r,list) else (None,None,'system-shared'))
  self.assertNotIn('private prompt',Path(os.environ['USAGE_DB']).read_bytes().decode(errors='ignore'))
 def test_concurrent_reservation_atomic(self):
  meter.connect().close()
  def work(_):
   try:meter.reserve('listing','m',b'x');return 1
   except RuntimeError:return 0
  with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:self.assertEqual(sum(pool.map(work,range(8))),2)
 def test_failed_request_not_refunded(self):
  ident=meter.reserve('listing','m',b'x');meter.finish(ident,0,b'')
  self.assertEqual(meter.summary()['rows'][0]['unknown_calls'],1)
  meter.reserve('retouch','m',b'y')
  with self.assertRaises(RuntimeError):meter.reserve('reference','m',b'z')
