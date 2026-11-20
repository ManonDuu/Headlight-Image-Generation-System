"""User-operated single Gemini image call. Credential stays in process memory."""
import base64,datetime,getpass,hashlib,json,os,pathlib,re,resource,subprocess,sys,urllib.request,urllib.error
root=pathlib.Path(__file__).resolve().parent
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
folder=root/'gemini-reference-041629-v14-one-call'
marker=folder/'attempt-started'
if marker.exists():sys.exit('这次单次测试已提交或结果未知，禁止重复执行。')
try:
 prepared=subprocess.run(['/usr/bin/ruby',str(root/'prepare-gemini-reference-041629.rb')],capture_output=True,check=True,text=True)
 plan=json.loads(prepared.stdout);body=json.loads(plan['body']);binding=plan['binding']
 assert binding['maxRequests']==1 and binding['retries']==0 and binding['analysisCalls']==0
 assert binding['model']=='gemini-3.1-flash-image' and binding['conservativeMicroUSD']<=500000
 assert hashlib.sha256(plan['body'].encode()).hexdigest()==binding['requestHash']
 assert body['generationConfig']['maxOutputTokens']==4096 and body['generationConfig']['candidateCount']==1
except Exception:sys.exit('请求准备或限额检查失败，未调用模型。')
print('Gemini 单次测试：红色、跟随原图、AI改写、参考排版；一张，零重试，费用上限 $0.50。')
print('使用已确认的新规则；本次不是模拟。自动读取工作台已保存凭据。')
# Verify system TLS without a credential or a generation request first.
probe=subprocess.run(['/usr/bin/curl','-q','--silent','--connect-timeout','8','--max-time','12','--proto','=https','--output','/dev/null','--write-out','%{http_code}','https://generativelanguage.googleapis.com/v1beta/models'],capture_output=True,text=True)
if probe.returncode!=0 or probe.stdout.strip()=='000':sys.exit('系统HTTPS连通检查失败；未读取密钥、未生成图片。')
import importlib.util
credential_spec=importlib.util.spec_from_file_location('saved_gemini_key',root/'saved-gemini-key.py')
credential_module=importlib.util.module_from_spec(credential_spec)
credential_spec.loader.exec_module(credential_module)
try:key=credential_module.credential()
except RuntimeError as exc:sys.exit(str(exc))
if not re.fullmatch(r'[A-Za-z0-9._-]{1,4095}',key):sys.exit('密钥格式不正确；未调用模型。')
folder.mkdir(exist_ok=True)
(folder/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2))
fd=os.open(str(marker),os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600);os.close(fd)
result={'state':'submitting','submissions':1,'retries':0,'analysisCalls':0,'budgetCapUSD':0.5,'requestHash':binding['requestHash'],'startedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'actualBillingVerified':False}
(folder/'result.json').write_text(json.dumps(result,indent=2))
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None
try:
 # Keep the API key in a pipe, never argv, environment, or credential files.
 (folder/'request.json').write_text(plan['body'])
 read_fd,write_fd=os.pipe()
 try:
  os.write(write_fd,('x-goog-api-key: '+key+'\n').encode());os.close(write_fd);write_fd=None;key=None
  print('正在请求一张图；请保持终端打开，结束后不会自动重试。',flush=True)
  transport=subprocess.run(['/usr/bin/curl','-q','--silent','--retry','0','--connect-timeout','15','--max-time','180','--proto','=https','--header','@/dev/fd/'+str(read_fd),'--header','Content-Type: application/json','--request','POST','--data-binary','@'+str(folder/'request.json'),'--output',str(folder/'response.json'),'--write-out','%{http_code}',binding['endpoint']],pass_fds=(read_fd,),capture_output=True,text=True)
 finally:
  os.close(read_fd)
  if write_fd is not None:os.close(write_fd)
 result['curlExitCode']=transport.returncode
 result['httpStatus']=int(transport.stdout.strip()) if transport.stdout.strip().isdigit() else 0
 if transport.returncode!=0:raise RuntimeError('transport failed')
 if result['httpStatus']!=200:raise RuntimeError('provider returned non-200')
 raw=(folder/'response.json').read_bytes()
 r=json.loads(raw);candidates=r.get('candidates',[])
 assert len(candidates)==1 and candidates[0].get('finishReason')=='STOP'
 assert r.get('modelVersion','').startswith(binding['model'])
 images=[p['inlineData'] for p in candidates[0].get('content',{}).get('parts',[]) if 'inlineData' in p and not p.get('thought')]
 assert len(images)==1
 image=images[0];ext={'image/png':'.png','image/jpeg':'.jpg'}[image['mimeType']];pixels=base64.b64decode(image['data'],validate=True)
 output=folder/('gemini-result'+ext);output.write_bytes(pixels)
 validation_code="r=GenerateContentAdapter.parse(200,File.binread(ARGV[0]),expected_dimensions:[1856,2304],input_token_reserve:25600);r.delete('bytes');puts JSON.generate(r)"
 validated=subprocess.run(['/usr/bin/ruby','-r',str(root/'generate-content-adapter.rb'),'-e',validation_code,str(folder/'response.json')],capture_output=True,text=True,check=True)
 native=json.loads(validated.stdout)
 assert native['outputHash']==hashlib.sha256(pixels).hexdigest()
 result.update(state='generated-pending-visual-review',output=str(output),outputHash=hashlib.sha256(pixels).hexdigest(),usage=r.get('usageMetadata'),modelVersion=r.get('modelVersion'))
 print('单次请求完成，图片已保存；尚未判断设计是否合格。')
except urllib.error.HTTPError as e:
 result.update(state='stopped',httpStatus=e.code);print('请求返回错误，已停止，不重试。HTTP '+str(e.code))
except Exception as e:
 result.update(state='stopped',errorType=type(e).__name__);print('测试停止，未重试。网络中断时远端结果可能未知。')
finally:
 key=None
 result['finishedAt']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 (folder/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2))
 print('请回到聊天告诉我终端最后显示的状态，我会读取结果继续核对。')
