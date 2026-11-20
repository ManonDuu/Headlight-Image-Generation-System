import os,json,urllib.request,urllib.error,base64,hashlib,time,pathlib
base=os.environ.get('WORKBENCH_TEST_URL','http://127.0.0.1:8797')
s=json.load(urllib.request.urlopen(base+'/api/session',timeout=3));assert s['mock'] is True
headers={'Content-Type':'application/json','X-Session-Token':s['token'],'Origin':base}
def call(path,data=None):
 req=urllib.request.Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
 try:
  with urllib.request.urlopen(req,timeout=10) as r:return r.status,r.read()
 except urllib.error.HTTPError as e:return e.code,e.read()
source=pathlib.Path('/Users/manrongdu/Downloads/71efzt2fH8L._AC_SL1500_.jpg').read_bytes()
input={'businessSpec':'car-light-direct-20261021.15','module':'reference-reconstruction','mode':'custom','layoutTone':'adjust-color','color':'#2864C8','layoutMode':'auto-layout','customCopy':'Brighter Road Visibility\nLED\nHalogen','output':{'aspectRatio':'1:1','imageSize':'2K'},'imageBase64':base64.b64encode(source).decode(),'sourceHash':hashlib.sha256(source).hexdigest(),'budgetMicroUSD':260000}
checks=[]
def check(name,ok):
 checks.append({'name':name,'passed':bool(ok)})
 if not ok:raise RuntimeError(name)
status,raw=call('/api/freeze',input);task=json.loads(raw);check('prepare through HTTP',status==200 and task['state']=='frozen');tid=task['id'];d={'id':tid,'requestHash':task['requestHash']}
status,raw=call('/api/task/'+tid+'/reference');check('reference byte-for-byte stored',status==200 and raw==source)
status,raw=call('/api/generic/generate',d);check('mock execution submitted',status==200)
for _ in range(150):
 status,raw=call('/api/task/'+tid);done=json.loads(raw)
 if done['state']!='running':break
 time.sleep(.05)
check('mock execution completed',done['state']=='mock-result')
status,img=call('/api/task/'+tid+'/image');check('download hash verified',status==200 and hashlib.sha256(img).hexdigest()==done['outputHash'])
status,_=call('/api/generic/generate',d);check('duplicate execution rejected',status!=200)
status,raw=call('/api/task/'+tid);restored=json.loads(raw);check('history options retained',restored['rawUserOptions']['customCopy']==input['customCopy'] and restored['rawUserOptions']['color']=='#2864C8')
req=urllib.request.Request(base+'/api/task/'+tid,headers={'X-Session-Token':'invalid'})
try:urllib.request.urlopen(req,timeout=5);protected=False
except urllib.error.HTTPError:protected=True
check('task route requires session token',protected)
report={'checks':checks,'taskId':tid,'passed':len(checks),'paidCalls':0,'realImageGenerated':False,'note':'API import tests bytes; browser file selection is a separate test'}
pathlib.Path(__file__).with_name('http-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
