import importlib.util,tempfile,pathlib,json,hashlib,multiprocessing
specmod=importlib.util.spec_from_file_location('budget','cumulative-budget.py');mod=importlib.util.module_from_spec(specmod);specmod.loader.exec_module(mod);B=mod.Budget
multiprocessing.set_start_method("fork",force=True)
checks=[]
def blocked(fn):
 try:fn()
 except (ValueError,KeyError):return
 raise AssertionError('Unexpected acceptance')
with tempfile.TemporaryDirectory() as p:
 b=B(p);b.initialize([{'reserveMicroUSD':7900000,'requestHash':'b'*64}],{'capMicroUSD':10000000});body=b'one';h=hashlib.sha256(body).hexdigest();s={'requestHash':h,'reserveMicroUSD':2040000,'boundMicroUSD':2031616,'endpoint':'test://offline','retries':0,'maxRequests':1}
 blocked(lambda:b.reserve(s));checks.append('disabled ledger blocks before transport')
 b._transaction(lambda j:(j.update(enabled=True),j['approval'].update(approvedRequests={h:s,**{hashlib.sha256(str(i).encode()).hexdigest():{**s,'requestHash':hashlib.sha256(str(i).encode()).hexdigest()} for i in range(8)}})))
 blocked(lambda:b.initialize([],{'capMicroUSD':10000000}));b.reserve(s);blocked(lambda:b.reserve(s));blocked(lambda:b.dispatch(h,b'changed','test://offline'));checks.append('reset, duplicate and changed bytes blocked')
 b.dispatch(h,body,'test://offline');blocked(lambda:B(p).dispatch(h,body,'test://offline'));checks.append('durable pre-dispatch marker prevents restart resend')
 b.settle(h,error='timeout');blocked(lambda:b.reserve({**s,'requestHash':'c'*64}));checks.append('uncertain response retains reserve and cap blocks next request')
 assert len(json.loads(b.path.read_text())['events'])==3
with tempfile.TemporaryDirectory() as p:
 b=B(p);b.initialize([{'reserveMicroUSD':7900000}],{'capMicroUSD':10000000});b._transaction(lambda j:(j.update(enabled=True),j['approval'].update(approvedRequests={h:s,**{hashlib.sha256(str(i).encode()).hexdigest():{**s,'requestHash':hashlib.sha256(str(i).encode()).hexdigest()} for i in range(8)}})));q=multiprocessing.Queue()
 def contender(i):
  try:B(p).reserve({**s,'requestHash':hashlib.sha256(str(i).encode()).hexdigest()});q.put('pass')
  except ValueError:q.put('blocked')
 ps=[multiprocessing.Process(target=contender,args=(i,)) for i in range(8)]
 for x in ps:x.start()
 for x in ps:x.join()
 assert [q.get() for x in ps].count('pass')==1;checks.append('eight concurrent cross-module reservations permit exactly one')
print(json.dumps({'checks':checks,'networkCalls':0},indent=2))
pathlib.Path('diagnostics/cumulative-budget/guard-tests.json').write_text(json.dumps({'checks':checks,'networkCalls':0},indent=2))
