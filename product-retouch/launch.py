"""Standalone retouch launcher; existing authorized Gemini key via memory pipe only."""
import json
import os
import pwd
import re
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from runtime_version import runtime_version
ROOT=Path(__file__).resolve().parent
URL='http://127.0.0.1:8776/'
from rules import VERSION
def session():
    try:
        # Local control must not go through a system HTTP proxy.
        opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with opener.open(URL+'api/session',timeout=2) as response:
            return json.load(response)
    except Exception:
        return None

def credential():
    key=os.environ.pop('RETOUCH_API_KEY',None) or os.environ.pop('GEMINI_API_KEY',None)
    if not key:
        user=pwd.getpwuid(os.getuid())
        queries = [
            ['-s','PictureGenerate.LocalWorkbench.Gemini','-a',user.pw_name,'-w',str(Path(user.pw_dir)/'Library/Keychains/login.keychain-db')],
            ['-s','PictureGenerate.LocalWorkbench.Gemini','-a',user.pw_name,'-w'],
            ['-s','PictureGenerate.LocalWorkbench.Gemini','-w'],
        ]
        codes=[]
        for query in queries:
            result=subprocess.run(['/usr/bin/security','find-generic-password']+query,capture_output=True)
            codes.append(result.returncode)
            if result.returncode == 0 and result.stdout:
                key=result.stdout.decode().rstrip('\n')
                break
        if not key:
            raise RuntimeError('无法读取工作台已有Gemini钥匙串项；诊断码：'+','.join(map(str,codes))+'。未修改密钥或调用模型。')
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,4095}',key):
        raise RuntimeError('已有Gemini凭据格式异常。')
    return key

def main():
    os.umask(0o077)
    current=session();child=None
    if current and current.get('applicationId')!='PictureOps.ProductRetouch':
        raise RuntimeError('8776端口不是精修模块，未停止任何服务。')
    if current and current.get('rulesVersion')==VERSION and current.get('runtimeVersion')==runtime_version() and current.get('generationEnabled'):
        subprocess.run(['/usr/bin/open',URL],check=False);return
    if current and any(t.get('state')=='running' for t in current.get('history',[])):
        raise RuntimeError('精修任务正在生成，待完成后再启动更新。')
    key=credential()  # Verify credential before touching the old preview.
    if current:
        listeners=subprocess.run(['/usr/sbin/lsof','-t','-iTCP:8776','-sTCP:LISTEN'],capture_output=True,text=True).stdout.split()
        if len(listeners)!=1 or not listeners[0].isdigit():
            raise RuntimeError('无法确认旧精修进程，未停止任何服务。')
        pid=int(listeners[0])
        command=subprocess.run(['/bin/ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
        cwd=subprocess.run(['/usr/sbin/lsof','-a','-p',str(pid),'-d','cwd','-Fn'],capture_output=True,text=True).stdout
        if 'server.py' not in command or ('n'+str(ROOT)) not in cwd.splitlines():
            raise RuntimeError('旧服务不属于独立精修目录，未停止。')
        os.kill(pid,signal.SIGTERM)
        for _ in range(40):
            try:os.kill(pid,0)
            except ProcessLookupError:break
            time.sleep(.1)
        else:raise RuntimeError('旧预览未退出，请关闭精修启动窗口后再试。')
    # Let HTTPServer bind with address reuse. A raw preflight bind can fail
    # on sockets in TIME_WAIT immediately after an otherwise clean restart.
    env=os.environ.copy()
    for name in ('GEMINI_API_KEY','RETOUCH_API_KEY'):env.pop(name,None)
    child=subprocess.Popen([sys.executable,str(ROOT/'server.py'),'--credential-stdin'],cwd=ROOT,env=env,stdin=subprocess.PIPE)
    child.stdin.write(json.dumps({'key':key}).encode());child.stdin.close();key=None
    for _ in range(40):
        if child.poll() is not None:raise RuntimeError('精修服务启动失败。')
        s=session()
        if s and s.get('generationEnabled') and s.get('rulesVersion')==VERSION and s.get('runtimeVersion')==runtime_version():break
        time.sleep(.2)
    else:
        child.terminate();raise RuntimeError('精修连接检查未通过。')
    print('Gemini已连接。精修模块独立运行；手动点击生成才收费，零重试。',flush=True)
    subprocess.run(['/usr/bin/open',URL],check=False)
    try:child.wait()
    except KeyboardInterrupt:child.terminate();child.wait()
if __name__=='__main__':
    try:
        main()
    except Exception as exc:
        message = str(exc) if isinstance(exc,RuntimeError) else '启动停止；未自动重试，未自动生图。'
        diagnostic={'errorType':type(exc).__name__, 'message':message,
                    'timestamp':time.strftime('%Y-%m-%dT%H:%M:%S'), 'paidCalls':0}
        (ROOT/'startup-diagnostic.json').write_text(json.dumps(diagnostic,ensure_ascii=False,indent=2))
        print(message,file=sys.stderr)
        print('具体错误已自动记录，可由我直接检查，无需提供密钥。',file=sys.stderr)
        sys.exit(1)
