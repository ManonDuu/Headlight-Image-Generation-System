"""Two-module candidate launcher. Startup alone never calls the image model."""
import importlib.util
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
PORT = 8774
URL = f'http://127.0.0.1:{PORT}'
PRODUCT_SPEC = 'car-light-product-20261022.10'
POLICY = 'product-identity-20261022.17'

def session():
    with urllib.request.urlopen(URL + '/api/session', timeout=3) as r:
        return json.load(r)

def compatible(s):
    return (s.get('applicationId') == 'PictureGenerate.LocalWorkbench'
            and s.get('mock') is False
            and s.get('referenceDaily', {}).get('enabled') is True
            and s.get('productDaily', {}).get('enabled') is True
            and s.get('productDaily', {}).get('version') == PRODUCT_SPEC
            and s.get('productDaily', {}).get('policyVersion') == POLICY)

def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.umask(0o077)
    child = None
    prepared_key = None
    try:
        current = session()
    except Exception:
        current = None
    if current is not None and not compatible(current):
        if (current.get('applicationId') != 'PictureGenerate.LocalWorkbench'
                or any(t.get('state') == 'running' for t in current.get('history', []))):
            raise RuntimeError('端口被其他服务占用或有任务生成中；未停止服务。')
        listeners = subprocess.run(['/usr/sbin/lsof', '-t', '-iTCP:' + str(PORT), '-sTCP:LISTEN'], capture_output=True, text=True)
        pids = listeners.stdout.split()
        if len(pids) != 1 or not pids[0].isdigit():
            raise RuntimeError('无法确认旧服务进程；未停止服务。')
        cwd = subprocess.run(['/usr/sbin/lsof', '-a', '-p', pids[0], '-d', 'cwd', '-Fn'], capture_output=True, text=True)
        if 'n' + str(ROOT) not in cwd.stdout.splitlines():
            raise RuntimeError('端口服务不属于当前工作台目录；未停止服务。')
        spec = importlib.util.spec_from_file_location('saved_key', ROOT / 'saved-gemini-key.py')
        saved = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(saved)
        prepared_key = saved.credential()  # Verify restart credentials before stopping anything.
        import signal
        os.kill(int(pids[0]), signal.SIGTERM)
        for _ in range(50):
            try:
                os.kill(int(pids[0]), 0)
            except ProcessLookupError:
                break
            time.sleep(.1)
        else:
            raise RuntimeError('旧服务尚未退出；未强制结束，请稍后重开入口。')
        current = None
        print('旧版本已安全停止，正在载入更新；不会自动生图。', flush=True)
    if current is None:
        # Check the bind before reading a credential; never stop another service.
        import socket
        with socket.socket() as probe:
            try:
                probe.bind(('127.0.0.1', PORT))
            except OSError as exc:
                raise RuntimeError('无法使用本地端口 8774；未读取凭据、未提交生成请求。') from exc
        spec = importlib.util.spec_from_file_location('saved_key', ROOT / 'saved-gemini-key.py')
        saved = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(saved)
        boot = {'key': prepared_key if prepared_key is not None else saved.credential(), 'rulesVersion': 'car-light-direct-20261021.20'}
        env = os.environ.copy()
        env.pop('GEMINI_API_KEY', None)
        child = subprocess.Popen(['/usr/bin/ruby', str(ROOT / 'bridge-server.rb'),
                                  '--reference-daily-stdin', '--product-daily', '--port', str(PORT)],
                                 stdin=subprocess.PIPE, env=env, cwd=ROOT)
        try:
            child.stdin.write(json.dumps(boot).encode())
            child.stdin.close()
        finally:
            boot['key'] = None
        for _ in range(50):
            if child.poll() is not None:
                raise RuntimeError('工作台启动失败；未提交生成请求。')
            try:
                current = session()
                break
            except Exception:
                time.sleep(.2)
        if not current or not compatible(current):
            child.terminate()
            raise RuntimeError('启动版本核对失败；未提交生成请求。')
    try:
        if '--verify' in sys.argv:
            check = subprocess.run([sys.executable, str(ROOT / 'verify-product-live.py')], cwd=ROOT)
            if check.returncode:
                print('验证未通过或尚待检查；保留候选版，不冻结、不自动重试。', flush=True)
        print('两模块候选工作台：' + URL + '；启动免费，手动生成才收费。', flush=True)
        subprocess.run(['/usr/bin/open', URL], check=False)
        if child:
            print('请保留本窗口；关闭窗口将停止本次服务。', flush=True)
            return child.wait()
    except KeyboardInterrupt:
        if child:
            child.terminate()
            child.wait()
        return 0

if __name__ == '__main__':
    try:
        sys.exit(main() or 0)
    except Exception as exc:
        # Never print arbitrary transport or credential exception contents.
        print(str(exc) if isinstance(exc, RuntimeError) else '启动停止；请在本机终端运行入口，未自动重试。', file=sys.stderr)
        sys.exit(1)
