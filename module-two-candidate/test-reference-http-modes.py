import os,json,urllib.request,urllib.error,base64,hashlib,pathlib,itertools
base=os.environ.get('WORKBENCH_TEST_URL','http://127.0.0.1:8797');s=json.load(urllib.request.urlopen(base+'/api/session'));assert s['mock'] is True
headers={'Content-Type':'application/json','X-Session-Token':s['token'],'Origin':base}
def post(d):
 req=urllib.request.Request(base+'/api/freeze',data=json.dumps(d).encode(),headers=headers)
 try:
  with urllib.request.urlopen(req,timeout=20) as r:return r.status,json.load(r)
 except urllib.error.HTTPError as e:return e.code,json.load(e)
source=pathlib.Path('/Users/manrongdu/Downloads/71efzt2fH8L._AC_SL1500_.jpg').read_bytes()
checks=[]
for mode,layout,tone in itertools.product(['custom','ai-rewrite','remove-all-copy'],['keep-reference','auto-layout'],['keep-reference','adjust-color']):
 d={'businessSpec':'car-light-direct-20261021.15','module':'reference-reconstruction','mode':mode,'layoutMode':layout,'layoutTone':tone,'output':{'aspectRatio':'1:1','imageSize':'2K'},'imageBase64':base64.b64encode(source).decode(),'sourceHash':hashlib.sha256(source).hexdigest(),'budgetMicroUSD':260000}
 if mode=='custom':d['customCopy']='Road Visibility\nLED\nHalogen'
 if tone=='adjust-color':d['color']='#2864C8'
 status,t=post(d);checks.append({'mode':mode,'layout':layout,'tone':tone,'passed':status==200 and t.get('state')=='frozen'})
clean=pathlib.Path('generated_images/exec-c73edbb8-79d4-478c-85a2-941e4a0273e5.png').read_bytes()
d.update(mode='preserve-reference',layoutMode='keep-reference',layoutTone='keep-reference',imageBase64=base64.b64encode(clean).decode(),sourceHash=hashlib.sha256(clean).hexdigest());d.pop('color',None);d.pop('customCopy',None)
status,t=post(d);preserve={'status':status,'state':t.get('state'),'error':t.get('error'),'passed':status==200 and t.get('state')=='frozen','taskId':t.get('id')}
report={'combinations':checks,'passed':sum(x['passed'] for x in checks),'preserveReference':preserve,'paidCalls':0,'note':'Reference source for preserve is the prior generated clean-text fixture, not an unseen sample.'}
pathlib.Path(__file__).with_name('http-modes-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
