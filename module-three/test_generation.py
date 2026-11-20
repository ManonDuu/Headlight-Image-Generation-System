import base64,json,tempfile,time,unittest
from unittest.mock import patch
from core import Store
from generation import Generation
from test_core import sample,PNG
from providers.gemini import GeminiProvider
class Fake:
 model='test'
 def __init__(self,fail=False):self.calls=0;self.fail=fail
 def capabilities(self):return {'connected':True}
 def generate(self,*args):
  self.calls+=1
  if self.fail:raise RuntimeError('测试失败')
  return {'bytes':b'fake-test-only','mime':'image/png','usage':{}}
class GenerationChecks(unittest.TestCase):
 def prepare(self,d):
  s=Store(d);r=s.save(sample(),[{'name':'p.png','base64':PNG}]);return s,r
 def finish(self,s,r):
  for _ in range(100):
   result=s.get(r['id'])
   if result['generation']['images'][0]['state']!='running':return result
   time.sleep(.01)
  self.fail('worker did not finish')
 def test_success_duplicate_and_durable_result(self):
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);p=Fake();g=Generation(s,p);g.start(r['id'],1)
   result=self.finish(s,r)
   self.assertEqual(result['generation']['images'][0]['state'],'completed')
   with self.assertRaises(ValueError):g.start(r['id'],1)
   self.assertEqual(p.calls,1)
   self.assertEqual(Store(d).get(r['id']),result)
 def test_failure_never_retries(self):
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);p=Fake(True);g=Generation(s,p);g.start(r['id'],1)
   self.assertEqual(self.finish(s,r)['generation']['images'][0]['state'],'stopped');self.assertEqual(p.calls,1)
 def test_daily_limit_and_restart(self):
  with tempfile.TemporaryDirectory() as d:
   from datetime import datetime,timezone
   s,r=self.prepare(d);p=Fake();g=Generation(s,p)
   s._write(s.root/'generation-budget.json',{datetime.now(timezone.utc).date().isoformat():10})
   with self.assertRaises(ValueError):g.start(r['id'],1)
   self.assertEqual(p.calls,0)
   r['generation']={'images':[{'slot':1,'state':'running'}]};s._write(s._path(r['id'])/'record.json',r)
   Generation(s,p);self.assertEqual(s.get(r['id'])['generation']['images'][0]['state'],'stopped')
 def test_provider_sends_exact_prompt_ratio_and_identity(self):
  image=base64.b64encode(b'\x89PNG\r\n\x1a\n'+b'x'*120).decode()
  response=json.dumps({'candidates':[{'finishReason':'STOP','content':{'parts':[{'inlineData':{'mimeType':'image/png','data':image}}]}}]}).encode()
  with patch('providers.gemini.post_once',return_value=response) as call:
   p=GeminiProvider('test-key');p.generate({'prompt':'frozen','ratio':'4:5'},[{'mime':'image/jpeg','bytes':b'identity'}],{'reserveUSD':.5})
   body=json.loads(call.call_args.args[1]);self.assertEqual(body['contents'][0]['parts'][0]['text'],'frozen');self.assertEqual(body['generationConfig']['imageConfig']['aspectRatio'],'4:5');self.assertEqual(call.call_count,1)
 def test_provider_refuses_missing_or_multiple_images(self):
  with patch('providers.gemini.post_once',return_value=b'{"candidates":[]}') as call:
   with self.assertRaises(RuntimeError):GeminiProvider('test-key').generate({'prompt':'p','ratio':'1:1'},[],{'reserveUSD':.5})
   self.assertEqual(call.call_count,1)

 def wait_set(self,s,r):
  for _ in range(200):
   result=s.get(r['id'])
   if result.get('generation',{}).get('state') in ('completed','paused'):return result
   time.sleep(.01)
  self.fail('set did not finish')
 def test_set_survives_no_polling_and_duplicate_submission(self):
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);p=Fake();g=Generation(s,p)
   g.start_set(r['id']);g.start_set(r['id'])
   result=self.wait_set(s,r)
   self.assertEqual(result['generation']['state'],'completed')
   self.assertEqual(len(result['generation']['images']),2)
   g.start_set(r['id']);self.assertEqual(p.calls,2)
 def test_set_failure_pauses_without_submitting_remaining(self):
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);p=Fake(True);g=Generation(s,p);g.start_set(r['id'])
   result=self.wait_set(s,r)
   self.assertEqual(result['generation']['state'],'paused')
   self.assertEqual(len(result['generation']['images']),1)
   g.start_set(r['id']);self.assertEqual(p.calls,1)
 def test_restart_pauses_queue_even_between_images(self):
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);r['generation']={'state':'running','images':[]};s._write(s._path(r['id'])/'record.json',r)
   p=Fake();g=Generation(s,p);g.start_set(r['id'])
   self.assertEqual(s.get(r['id'])['generation']['state'],'paused');self.assertEqual(p.calls,0)

class RetryChecks(GenerationChecks):
 def test_manual_retry_preserves_success_history_and_deduplicates(self):
  class FailSecond(Fake):
   def generate(self,*args):
    if self.calls==1:
     self.calls+=1;raise RuntimeError('模拟超时')
    return super().generate(*args)
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);p=FailSecond();g=Generation(s,p);g.start_set(r['id']);first=self.wait_set(s,r)
   original=first['generation']['images'][0].copy();token='manual-retry-request-001'
   g.retry_set(r['id'],token);g.retry_set(r['id'],token)
   result=self.wait_set(s,r);g.retry_set(r['id'],token)
   self.assertEqual(p.calls,3);self.assertEqual(result['generation']['state'],'completed')
   self.assertEqual(result['generation']['images'][0],original)
   retried=result['generation']['images'][1]
   self.assertEqual(retried['attempts'],2);self.assertEqual(retried['history'][0]['error'],'模拟超时')
   self.assertEqual(result['plan'],first['plan'])
   self.assertEqual(sum(json.loads((s.root/'generation-budget.json').read_text()).values()),1.5)
   with self.assertRaises(ValueError):g.retry_set(r['id'],'manual-retry-request-002')
 def test_retry_failure_stops_without_automatic_retry(self):
  with tempfile.TemporaryDirectory() as d:
   s,r=self.prepare(d);p=Fake(True);g=Generation(s,p);g.start_set(r['id']);self.wait_set(s,r)
   g.retry_set(r['id'],'manual-retry-request-003');result=self.wait_set(s,r)
   self.assertEqual(p.calls,2);self.assertEqual(len(result['generation']['images']),1)
   self.assertEqual(result['generation']['images'][0]['attempts'],2)
 def test_retry_budget_preserves_failure(self):
  with tempfile.TemporaryDirectory() as d:
   from datetime import datetime,timezone
   s,r=self.prepare(d);p=Fake(True);g=Generation(s,p);g.start_set(r['id']);first=self.wait_set(s,r)
   s._write(s.root/'generation-budget.json',{datetime.now(timezone.utc).date().isoformat():10})
   g.retry_set(r['id'],'manual-retry-request-004');result=self.wait_set(s,r)
   self.assertEqual(p.calls,1);self.assertEqual(result['generation']['images'],first['generation']['images'])
   self.assertIn('预算',result['generation']['error']);self.assertEqual(result['generation']['pauseReason'],'budget-limit')

class DailyBudgetOverride(unittest.TestCase):
 def test_only_authorized_day_is_increased_without_erasing_reservations(self):
  from datetime import datetime,timezone
  with tempfile.TemporaryDirectory() as d:
   s=Store(d);r=s.save(sample(),[{'name':'p.png','base64':PNG}]);p=Fake();g=Generation(s,p)
   day=datetime.now(timezone.utc).date().isoformat()
   s._write(s.root/'generation-budget.json',{day:10})
   with self.assertRaises(ValueError):g.start(r['id'],1,synchronous=True)
   s._write(s.root/'generation-budget-limits.json',{day:15})
   g.start(r['id'],1,synchronous=True)
   self.assertEqual(g.budget_status()['reservedUSD'],10.5)
   self.assertEqual(g.budget_status()['remainingUSD'],4.5)
   self.assertEqual(g.budget_status('2099-01-01')['limitUSD'],10)
   s._write(s.root/'generation-budget.json',{day:15})
   with self.assertRaises(ValueError):g.start(r['id'],2,synchronous=True)
   self.assertEqual(p.calls,1)
