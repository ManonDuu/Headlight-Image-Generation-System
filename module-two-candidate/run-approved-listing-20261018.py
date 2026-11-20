"""Single-use scoped authorization Sentinel_9ce2af725860819189d6a06874e32720.
Global pause remains; no general model route is enabled. Never retry a claimed step.
"""
import base64,hashlib,json,os,pathlib,pwd,re,resource,subprocess,sys,urllib.request
from datetime import datetime,timezone
R=pathlib.Path(__file__).resolve().parent
B=R/'live-attempts/listing-Sentinel_9ce2af725860819189d6a06874e32720'
W=R/'diagnostics/approved-listing-20261018'
def now():return datetime.now(timezone.utc).isoformat()
def call_local(path,data=None,token=None):
 req=urllib.request.Request('http://127.0.0.1:8773'+path,data=json.dumps(data).encode() if data is not None else None,headers={'Origin':'http://127.0.0.1:8773','Content-Type':'application/json',**({'X-Session-Token':token} if token else {})})
 with urllib.request.urlopen(req,timeout=10) as f:return json.load(f)
def main(stage):
 resource.setrlimit(resource.RLIMIT_CORE,(0,0));W.mkdir(exist_ok=True)
 assert stage in ['analysis','background']
 if (B/'STOP.json').exists():raise RuntimeError('Batch stopped after failure; no further requests')
 if (B/stage).exists():raise RuntimeError('Step already claimed; never retry')
 for prev in {'reference':[],'analysis':[],'background':['analysis']}[stage]:
  if not (B/prev/'completed.json').exists():raise RuntimeError('Previous step not completed; stop batch')
 assert (R/'LIVE-REQUESTS-PAUSED').is_file()
 paths={'reference':R/'diagnostics/today-real-input-readiness/reference-reconstruction-live-plan.json','analysis':R/'diagnostics/listing-canbus-preflight/analysis-plan-UNAUTHORIZED.json','background':W/'background-plan.json'}
 plan=json.loads(paths[stage].read_text());binding=plan['binding'];body=plan['body'].encode();cfg=json.loads(body)['generationConfig']
 expected={'reference':('9845660e5d22f4ee285d62bf1bd1a083d1eefcabb8f39380f006dbed48549dd7',260000),'analysis':('708797f9c157d9eb51c815676ae3bb5e5408c548c36f03bc7dc64aa6af3545bc',20000),'background':(binding['requestHash'],260000)}
 assert hashlib.sha256(body).hexdigest()==binding['requestHash']==expected[stage][0]
 assert binding['budgetMicroUSD']==expected[stage][1] and binding['conservativeMicroUSD']<=binding['budgetMicroUSD'] and cfg['maxOutputTokens']==4096 and cfg['candidateCount']==1 and binding['retries']==0
 expected_model='gemini-3.5-flash-lite' if stage=='analysis' else 'gemini-3.1-flash-image';assert binding['model']==expected_model
 endpoint='https://generativelanguage.googleapis.com/v1beta/models/'+expected_model+':generateContent';assert binding['endpoint']==endpoint
 images=[p['inlineData'] for p in json.loads(body)['contents'][0]['parts'] if 'inlineData'in p]
 source='28399cad8a8e136d5cad8dbd88bb3d46763448e73755beb45a083a8f0b261814' if stage=='reference' else '31df2ed4e210f51c1b0a3ea92b01b381f0bb1b5dd00b1a30db6bb75de55253ff'
 assert len(images)==1 and hashlib.sha256(base64.b64decode(images[0]['data'],validate=True)).hexdigest()==source
 if stage=='background':assert 'Do not draw any replacement product' in json.loads(body)['contents'][0]['parts'][0]['text']
 session=call_local('/api/session');assert session['mock'] is False and session['paidRequestsPaused'] is True
 if any(j['state']=='running' for j in session['history']):raise RuntimeError('Another request running')
 if stage=='reference' and any(j['requestHash']==binding['requestHash'] for j in session['history']):raise RuntimeError('Matching normal task already exists; inspect, do not recreate')
 if (R/'live-attempts'/('generic-gc-'+binding['requestHash'])).exists():raise RuntimeError('Hash already consumed')
 
 for old in (R/'live-attempts').rglob('receipt.json'):
  previous=json.loads(old.read_text())
  if previous.get('requestHash')==binding['requestHash']:raise RuntimeError('Matching receipt exists; do not dispatch')
 account=pwd.getpwuid(os.getuid()).pw_name;keychain=str(pathlib.Path.home()/'Library/Keychains/login.keychain-db')
 k=subprocess.run(['/usr/bin/security','find-generic-password','-s','PictureGenerate.LocalWorkbench.Gemini','-a',account,'-w',keychain],capture_output=True,timeout=60)
 if k.returncode:raise RuntimeError('Exact Keychain read denied/failed; no dispatch')
 secret=k.stdout.removesuffix(b'\n');assert re.fullmatch(rb'[A-Za-z0-9._-]{1,4095}',secret)
 B.mkdir(exist_ok=True,mode=0o700);folder=B/stage;folder.mkdir(mode=0o700)
 (folder/'plan.json').write_text(json.dumps(plan));(folder/'request.json').write_bytes(body)
 receipt={'approval':'Sentinel_9ce2af725860819189d6a06874e32720','stage':stage,'requestHash':binding['requestHash'],'model':expected_model,'budgetMicroUSD':expected[stage][1],'maxRequests':1,'retries':0,'startedAt':now(),'state':'claimed'}
 if stage=='reference':
  f=call_local('/api/freeze',{**plan['options'],'budgetMicroUSD':260000,'sourceHash':source,'imageBase64':images[0]['data']},session['token'])
  assert f['requestHash']==binding['requestHash'];receipt['task']=f['id'];(W/'reference-task.json').write_text(json.dumps(f))
 (folder/'receipt.json').write_text(json.dumps(receipt,indent=2))
 rd,wr=os.pipe();os.write(wr,b'x-goog-api-key: '+secret+b'\n');os.close(wr);response=folder/'response.raw.json';env=dict(os.environ);env.pop('GEMINI_API_KEY',None)
 try:
  t=120 if stage=='analysis' else 180
  z=subprocess.run(['/usr/bin/curl','-q','--header','@/dev/fd/'+str(rd),'--silent','--retry','0','--connect-timeout','15','--max-time',str(t),'--proto','=https','--request','POST','--header','Content-Type: application/json','--data-binary','@'+str(folder/'request.json'),'--output',str(response),'--write-out','%{http_code}',endpoint],pass_fds=(rd,),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=t+10)
  receipt.update(curlExit=z.returncode,httpStatus=z.stdout.decode(errors='replace').strip(),state='response-received' if z.returncode==0 else 'stopped-unknown')
 except Exception:receipt.update(state='stopped-unknown',error='Transport interrupted; no retry')
 finally:
  os.close(rd)
  if response.exists():response.write_bytes(response.read_bytes().replace(secret,b'[REDACTED]'));receipt['responseHash']=hashlib.sha256(response.read_bytes()).hexdigest()
  secret=None;receipt['finishedAt']=now();(folder/'receipt.json').write_text(json.dumps(receipt,indent=2))
 print(json.dumps(receipt),flush=True)
if __name__=='__main__':
 try:main(sys.argv[1])
 except Exception as e:print('Preflight/operation stopped: '+str(e));raise SystemExit(1)
