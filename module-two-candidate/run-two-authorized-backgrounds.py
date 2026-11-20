"""Single scoped step of the newly approved two-background validation; global UI pause stays on."""
import base64,hashlib,json,os,pathlib,pwd,re,resource,subprocess,sys,urllib.request
from datetime import datetime,timezone
ROOT=pathlib.Path(__file__).resolve().parent
WORK=ROOT/'diagnostics/two-backgrounds-20261018'
LEDGER=ROOT/'live-attempts/two-backgrounds-20261018-153414'
APPROVAL='two-backgrounds-20261018-153414'
def now():return datetime.now(timezone.utc).isoformat()
def main():
 resource.setrlimit(resource.RLIMIT_CORE,(0,0));step=int(sys.argv[1]);assert step in (1,2)
 authorization=json.loads((LEDGER/'authorization.json').read_text())
 if authorization['id']!=APPROVAL or authorization['maxBackgroundRequests']!=2 or authorization['totalBudgetMicroUSD']!=520000:raise RuntimeError('New round authorization mismatch')
 if (LEDGER/'STOP.json').exists():raise RuntimeError('This round stopped; no further requests.')
 attempt=LEDGER/('step'+str(step))
 if attempt.exists():raise RuntimeError('Step already reserved; never repeat.')
 if not (ROOT/'LIVE-REQUESTS-PAUSED').is_file():raise RuntimeError('Global service pause must remain active.')
 for previous in range(1,step):
  gate=json.loads((WORK/('step'+str(previous)+'-review.json')).read_text())
  if gate.get('passed') is not True:raise RuntimeError('Previous step not accepted; stop.')
 plan=json.loads((WORK/('step'+str(step)+'-plan.json')).read_text());b=plan['binding'];body=(WORK/('step'+str(step)+'-request.json')).read_bytes()
 expected={1:'a902c11fb5495e2e979bedfdc9504734d1b2b7e9864baf7ca0dc1be54411de25',2:'e7a4ccef8bc61aba8684441489f3e3c6d0bc7a4e21904a3b81d2233f4bc4dc16'}
 if hashlib.sha256(body).hexdigest()!=expected[step] or b['requestHash']!=expected[step]:raise RuntimeError('Frozen step changed.')
 data=json.loads(body);cfg=data['generationConfig'];parts=data['contents'][0]['parts'];model='gemini-3.1-flash-image'
 if b['model']!=model or b['endpoint']!='https://generativelanguage.googleapis.com/v1beta/models/'+model+':generateContent':raise RuntimeError('Wrong endpoint/model')
 if cfg['maxOutputTokens']!=4096 or cfg['candidateCount']!=1 or data.get('tools') or len(parts)!=2:raise RuntimeError('Token/candidate/tool/input limit changed')
 if hashlib.sha256(base64.b64decode(parts[1]['inlineData']['data'],validate=True)).hexdigest()!=b['sourceHash']:raise RuntimeError('Reference mismatch')
 if cfg['responseModalities']!=['IMAGE'] or cfg['imageConfig']!={'aspectRatio':'4:5','imageSize':'2K'} or cfg['thinkingConfig']!={'thinkingLevel':'MINIMAL'}:raise RuntimeError('Frozen image settings changed')
 conservative=25600*.50+4096*60;budget=260000
 used=list(LEDGER.glob('step*/receipt.json'))
 if len(used)!=step-1 or sum(json.loads(p.read_text())['budgetMicroUSD'] for p in used)+budget>520000 or conservative>budget:raise RuntimeError('Count or cumulative budget violation')
 with urllib.request.urlopen('http://127.0.0.1:8773/api/session',timeout=3) as response:session=json.load(response)
 if session.get('mock') is not False or session.get('paidRequestsPaused') is not True or any(x['state']=='running' for x in session['history']):raise RuntimeError('Paused idle local service required')
 keychain=str(pathlib.Path.home()/'Library/Keychains/login.keychain-db');account=pwd.getpwuid(os.getuid()).pw_name
 found=subprocess.run(['/usr/bin/security','find-generic-password','-s','PictureGenerate.LocalWorkbench.Gemini','-a',account,'-w',keychain],capture_output=True,timeout=60)
 if found.returncode:raise RuntimeError('Exact existing Keychain item unavailable; nothing dispatched')
 secret=found.stdout.removesuffix(b'\n')
 if not re.fullmatch(rb'[A-Za-z0-9._-]{1,4095}',secret):raise RuntimeError('Credential format invalid; nothing dispatched')
 LEDGER.mkdir(mode=0o700,exist_ok=True);attempt.mkdir(mode=0o700)
 record={'approval':APPROVAL,'step':step,'state':'attempt-started','startedAt':now(),'requestHash':b['requestHash'],'sourceHash':b['sourceHash'],'model':model,'budgetMicroUSD':budget,'conservativeMicroUSD':conservative,'cumulativeReservedMicroUSD':sum(json.loads(p.read_text())['budgetMicroUSD'] for p in used)+budget,'maxOutputTokens':4096,'maxRequests':1,'retries':0,'globalPausePreserved':True}
 (attempt/'receipt.json').write_text(json.dumps(record,indent=2))
 fd,writefd=os.pipe();os.write(writefd,b'x-goog-api-key: '+secret+b'\n');os.close(writefd);env=dict(os.environ);env.pop('GEMINI_API_KEY',None)
 raw=attempt/'response.raw.json'
 try:
  limit=180
  r=subprocess.run(['/usr/bin/curl','-q','--header','@/dev/fd/'+str(fd),'--silent','--retry','0','--connect-timeout','15','--max-time',str(limit),'--proto','=https','--request','POST','--header','Content-Type: application/json','--data-binary','@'+str(WORK/('step'+str(step)+'-request.json')),'--output',str(raw),'--write-out','%{http_code}',b['endpoint']],pass_fds=(fd,),stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env,timeout=limit+10)
  record.update(curlExit=r.returncode,httpStatus=r.stdout.decode(errors='replace').strip(),state='response-received' if r.returncode==0 else 'stopped-unknown')
 except Exception:record.update(state='stopped-unknown',error='Transport interrupted; no retry')
 finally:
  os.close(fd)
  if raw.exists():
   raw.write_bytes(raw.read_bytes().replace(secret,b'[REDACTED]'));record['responseHash']=hashlib.sha256(raw.read_bytes()).hexdigest()
   try:
    payload=json.loads(raw.read_bytes());record['usage']=payload.get('usageMetadata');record['finishReason']=payload.get('candidates',[{}])[0].get('finishReason')
   except Exception:pass
  secret=None;record['finishedAt']=now();record['globalPausePresent']=(ROOT/'LIVE-REQUESTS-PAUSED').is_file();(attempt/'receipt.json').write_text(json.dumps(record,indent=2))
  if record.get('httpStatus')!='200' or record.get('curlExit')!=0 or record.get('finishReason')!='STOP':(LEDGER/'STOP.json').write_text(json.dumps({'reason':'request failed or incomplete; stop entire round','step':step}))
 print(json.dumps(record))
if __name__=='__main__':
 try:main()
 except Exception as e:print(json.dumps({'state':'blocked','type':type(e).__name__,'reason':str(e) if isinstance(e,(RuntimeError,AssertionError)) else 'Local preflight failed; inspect ledger before any further action'}));sys.exit(1)
