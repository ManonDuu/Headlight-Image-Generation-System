"""Foreground daily workbench. Startup never generates an image."""
import importlib.util
import json
import os
import pathlib
import resource
import socket
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
PORT = 8773
URL = 'http://127.0.0.1:' + str(PORT)

def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    os.umask(0o077)
    with socket.socket() as probe:
        probe.settimeout(1)
        occupied = probe.connect_ex(('127.0.0.1', PORT)) == 0
    if occupied:
        try:
            with urllib.request.urlopen(URL + '/api/session', timeout=3) as response:
                session = json.load(response)
            valid = (session.get('applicationId') == 'PictureGenerate.LocalWorkbench'
                     and session.get('referenceDaily', {}).get('enabled') is True
                     and session.get('referenceDaily', {}).get('version') == 'car-light-direct-20261021.20'
                     and session.get('mock') is False)
        except Exception:
            valid = False
        if not valid:
            raise RuntimeError('8773 被其他版本占用；未读取密钥、未停止旧服务。请关闭旧工作台自己的终端窗口后再启动。')
        print('参考图卖点重构已运行：' + URL, flush=True)
        subprocess.run(['/usr/bin/open', URL], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    spec = importlib.util.spec_from_file_location('saved_gemini_key', ROOT / 'saved-gemini-key.py')
    saved = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(saved)
    key = saved.credential()
    boot = {'key': key, 'rulesVersion': 'car-light-direct-20261021.20'}
    env = os.environ.copy()
    env.pop('GEMINI_API_KEY', None)
    print('启动参考图卖点重构；启动和准备不收费，点击生成才提交一张图。请保持本窗口打开。', flush=True)
    child = subprocess.Popen(['/usr/bin/ruby', str(ROOT / 'bridge-server.rb'),
                              '--reference-daily-stdin', '--port', str(PORT)],
                             stdin=subprocess.PIPE, env=env)
    (ROOT / 'daily-service.json').write_text(json.dumps({'pid': child.pid, 'url': URL, 'version': 'car-light-direct-20261021.20'}))
    try:
        child.stdin.write(json.dumps(boot).encode())
        child.stdin.close()
        boot['key'] = None
        key = None
        return child.wait()
    except KeyboardInterrupt:
        child.terminate()
        child.wait()
        return 0
    finally:
        boot['key'] = None
        key = None

if __name__ == '__main__':
    try:
        sys.exit(main() or 0)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError):
        print('工作台启动失败；未显示凭据、未提交图片请求。', file=sys.stderr)
        sys.exit(1)
