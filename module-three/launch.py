"""Start only the independent listing module using the existing workbench key."""
import importlib.util,json,os,subprocess,sys,time,urllib.request
from pathlib import Path
from style_contract import REVISION
from providers.transport import TRANSPORT_REVISION
ROOT=Path(__file__).resolve().parent
URL='http://127.0.0.1:8775'
def session():
 try:
  with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(URL+'/api/capabilities',timeout=2) as r:return json.load(r)
 except Exception:return None
def main():
 os.umask(0o077)
 spec=importlib.util.spec_from_file_location('saved_key',ROOT.parent/'module-two-candidate/saved-gemini-key.py')
 mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);key=mod.credential()
 current=session()
 if current:
  if current.get('module')!='three':raise RuntimeError('端口被其他服务占用，未停止其他模块')
  if current.get('liveEnabled') and current.get('generationRevision')=='durable-set-v5-dated-authorization' and isinstance(current.get('budget'),dict) and current.get('rulesRevision')==REVISION and current.get('transportRevision')==TRANSPORT_REVISION:
   subprocess.run(['/usr/bin/open',URL]);return
  with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(URL+'/api/tasks',timeout=3) as response:tasks=json.load(response)['tasks']
  for task in tasks:
   with urllib.request.build_opener(urllib.request.ProxyHandler({})).open(URL+'/api/tasks/'+task['id'],timeout=3) as response:record=json.load(response)
   if record.get('generation',{}).get('state')=='running' or any(t['state']=='running' for t in record.get('generation',{}).get('images',[])):
    raise RuntimeError('仍有图片生成中，请完成后再启动更新；未中断任务')
  # Only replace this module's old process.
  ids=subprocess.run(['/usr/sbin/lsof','-t','-iTCP:8775','-sTCP:LISTEN'],capture_output=True,text=True).stdout.split()
  if len(ids)!=1:raise RuntimeError('无法确认旧预览进程')
  cwd=subprocess.run(['/usr/sbin/lsof','-a','-p',ids[0],'-d','cwd','-Fn'],capture_output=True,text=True).stdout.splitlines()
  if 'n'+str(ROOT) not in cwd:raise RuntimeError('旧进程不属于独立附图目录，未停止')
  os.kill(int(ids[0]),15)
  for _ in range(30):
   if not session():break
   time.sleep(.1)
 env=os.environ.copy();env.pop('GEMINI_API_KEY',None)
 child=subprocess.Popen([sys.executable,str(ROOT/'server.py'),'--credential-stdin'],stdin=subprocess.PIPE,cwd=ROOT,env=env)
 child.stdin.write(json.dumps({'key':key}).encode());child.stdin.close();key=None
 for _ in range(50):
  s=session()
  if s and s.get('liveEnabled'):break
  if child.poll() is not None:raise RuntimeError('服务启动失败')
  time.sleep(.2)
 else:child.terminate();raise RuntimeError('连接检查失败')
 print('整套附图已连接 Gemini；点击生成才提交请求。',flush=True)
 subprocess.run(['/usr/bin/open',URL],check=False)
 try:child.wait()
 except KeyboardInterrupt:child.terminate();child.wait()
if __name__=='__main__':
 try:main()
 except PermissionError:
  print('当前会话无权停止已有本地服务。请在电脑上重新双击启动整套附图模块.command，以加载新规则；未自动生图。',file=sys.stderr);sys.exit(1)
 except Exception as e:
  print(str(e) if isinstance(e,RuntimeError) else '启动失败，未显示凭据或自动生图',file=sys.stderr);sys.exit(1)
