"""Shared offline budget gate. No network or credential loading. All amounts micro-USD.
One persistent state file and one stable flock per project, never per module.
No retry/release: reserved ceilings stay charged even after success or ambiguity.
"""
import fcntl,hashlib,json,os,tempfile,time
from pathlib import Path
class Budget:
 def __init__(self,root):self.root=Path(root).resolve();self.root.mkdir(parents=True,exist_ok=True);self.path=self.root/'ledger.json'
 def _transaction(self,change):
  with open(self.root/'ledger.lock','a') as lock:
   fcntl.flock(lock,fcntl.LOCK_EX)
   state=json.loads(self.path.read_text()) if self.path.exists() else None
   result=change(state)
   state=result if state is None else state
   fd,tmp=tempfile.mkstemp(dir=self.root,prefix='.ledger-')
   try:
    with os.fdopen(fd,'w') as f:json.dump(state,f,sort_keys=True,indent=2);f.flush();os.fsync(f.fileno())
    os.replace(tmp,self.path)
    d=os.open(self.root,os.O_RDONLY);os.fsync(d);os.close(d)
   finally:
    if os.path.exists(tmp):os.unlink(tmp)
   return result
 def initialize(self,history,approval):
  def change(s):
   if s is not None:raise ValueError('Ledger already exists; never reset historical budget')
   if approval['capMicroUSD']!=10000000:raise ValueError('Wrong cumulative cap')
   if any(type(x['reserveMicroUSD']) is not int or x['reserveMicroUSD']<0 for x in history):raise ValueError('Invalid historical reserve')
   return {'version':1,'approval':approval,'capMicroUSD':10000000,'history':history,'requests':{},'events':[],'enabled':False}
  return self._transaction(change)
 def reserve(self,spec):
  def change(s):
   if not s or not s['enabled']:raise ValueError('Paid execution remains disabled')
   h=spec['requestHash'];n=spec['reserveMicroUSD']
   if s['approval'].get('approvedRequests',{}).get(h)!=spec:raise ValueError('Request lacks exact new approval binding')
   if len(h)!=64 or any(c not in '0123456789abcdef' for c in h):raise ValueError('Invalid hash')
   if type(n) is not int or n<=0 or n<spec['boundMicroUSD']:raise ValueError('Invalid ceiling')
   if spec['retries']!=0 or spec['maxRequests']!=1:raise ValueError('Only one no-retry request')
   if h in s['requests'] or any(x.get('requestHash')==h for x in s['history']):raise ValueError('Request already consumed or reserved')
   if any(x['state'] in ['reserved','dispatched-uncertain','uncertain-reserve-retained'] for x in s['requests'].values()):raise ValueError('Outstanding request requires reconciliation')
   total=sum(x['reserveMicroUSD'] for x in s['history'])+sum(x['reserveMicroUSD'] for x in s['requests'].values())
   if total+n>s['capMicroUSD']:raise ValueError('Cumulative budget exceeded')
   s['requests'][h]={**spec,'state':'reserved'};s['events'].append({'event':'reserve','hash':h,'microUSD':n,'at':time.time()})
  self._transaction(change)
 def dispatch(self,h,body,endpoint):
  def change(s):
   if not s['enabled']:raise ValueError('Paid execution remains disabled')
   r=s['requests'][h]
   if r['state']!='reserved':raise ValueError('Dispatch already consumed; never resend')
   if hashlib.sha256(body).hexdigest()!=h or endpoint!=r['endpoint']:raise ValueError('Frozen request changed')
   # Durable before any caller invokes transport. Crash after this point is uncertain.
   r['state']='dispatched-uncertain'
   if r.get('scope')=='fresh-analysis-single':
    s['enabled']=False
    s['events'].append({'event':'pause-after-single-analysis-dispatch','hash':h,'at':time.time()})
   s['events'].append({'event':'dispatch','hash':h,'at':time.time()})
  self._transaction(change)
 def settle(self,h,response_hash=None,error=None):
  def change(s):
   r=s['requests'][h]
   if r['state']!='dispatched-uncertain':raise ValueError('Invalid settlement transition')
   r['state']='returned-reserve-retained' if response_hash else 'uncertain-reserve-retained'
   r['responseHash']=response_hash;r['error']=error
   s['events'].append({'event':'settle','hash':h,'state':r['state'],'reserveReleased':0,'at':time.time()})
  self._transaction(change)
 def run_once(self,spec,body,transport):
  self.reserve(spec);self.dispatch(spec['requestHash'],body,spec['endpoint'])
  try:response=transport(spec['endpoint'],body,{'retries':0});self.settle(spec['requestHash'],hashlib.sha256(response).hexdigest());return response
  except BaseException as e:self.settle(spec['requestHash'],error=type(e).__name__);raise

if __name__ == '__main__':
 import sys,base64
 if len(sys.argv)!=3:raise SystemExit('Usage: cumulative-budget.py LEDGER_ROOT begin|settle')
 b=Budget(sys.argv[1]);v=json.load(sys.stdin)
 if sys.argv[2]=='begin':
  body=base64.b64decode(v['bodyBase64'],validate=True);spec=v['spec']
  if hashlib.sha256(body).hexdigest()!=spec['requestHash']:raise ValueError('Frozen body mismatch before reserve')
  b.reserve(spec);b.dispatch(spec['requestHash'],body,spec['endpoint'])
 elif sys.argv[2]=='settle':b.settle(v['requestHash'],v.get('responseHash'),v.get('error'))
 else:raise ValueError('Unknown operation')
 print(json.dumps({'state':'recorded','operation':sys.argv[2]}))
