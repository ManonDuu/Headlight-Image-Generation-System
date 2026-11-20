"""Open the four existing screens without an API key or a live image call.

This is a local preview only. It uses the workbench's existing mock mode and
the disconnected preview providers. It does not call Cockpit or Google.

Verified here on Linux only. It needs Python, Ruby, and Pillow on PATH.
It does not use nginx or tesseract. It is not a Windows app and has not been
run on macOS.
"""
import argparse
import http.client
import os
import shutil
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


class PreviewProxy(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, status, headers, body):
        self.send_response(status)
        for key, value in headers:
            if key.lower() in ('transfer-encoding', 'connection', 'content-length', 'keep-alive'):
                continue
            self.send_header(key, value)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle(self):
        parts = urlsplit(self.path)
        path = parts.path or '/'
        if path in ('/listing', '/retouch'):
            body = b''
            self._send(308, [('Location', path + '/'), ('Content-Length', '0')], body)
            return
        if path == '/listing' or path.startswith('/listing/'):
            port, upstream = self.server.ports['listing'], path[len('/listing'):] or '/'
        elif path == '/retouch' or path.startswith('/retouch/'):
            port, upstream = self.server.ports['retouch'], path[len('/retouch'):] or '/'
        else:
            port, upstream = self.server.ports['workbench'], path
        if not upstream.startswith('/'):
            upstream = '/' + upstream
        target = upstream + (('?' + parts.query) if parts.query else '')
        length = int(self.headers.get('Content-Length', '0') or 0)
        payload = self.rfile.read(length) if length else None
        headers = {}
        for key, value in self.headers.items():
            if key.lower() in ('host', 'origin', 'content-length', 'connection'):
                continue
            headers[key] = value
        headers['Host'] = f'127.0.0.1:{port}'
        headers['Origin'] = f'http://127.0.0.1:{port}'
        connection = http.client.HTTPConnection('127.0.0.1', port, timeout=30)
        try:
            connection.request(self.command, target, body=payload, headers=headers)
            response = connection.getresponse()
            body = response.read()
            self._send(response.status, list(response.headers.items()), body)
        finally:
            connection.close()

    def do_GET(self):
        self._handle()

    def do_POST(self):
        self._handle()

    def do_HEAD(self):
        self._handle()


def start_preview(data_root, gateway_port=18080, workbench_port=8774, listing_port=8775, retouch_port=8776):
    if shutil.which('ruby') is None:
        raise SystemExit('本机没有 ruby，四模块页面起不来。这不是已经验证过的 macOS 或 Windows 安装包。')
    data_root = Path(data_root)
    data_root.mkdir(parents=True, exist_ok=True)
    children = []
    env = os.environ.copy()
    env['SYSTEM_BUDGET'] = '0'
    env['PYTHONPATH'] = str(ROOT / 'deploy') + os.pathsep + env.get('PYTHONPATH', '')
    workbench_data = data_root / 'workbench'
    listing_data = data_root / 'listing'
    workbench_data.mkdir(exist_ok=True)
    listing_data.mkdir(exist_ok=True)
    children.append(subprocess.Popen(
        ['ruby', 'bridge-server.rb', '--mock', '--port', str(workbench_port), '--data', str(workbench_data)],
        cwd=ROOT / 'module-two-candidate', env=env))
    children.append(subprocess.Popen(
        [sys.executable, 'server.py', '--preview', '--port', str(listing_port), '--data', str(listing_data)],
        cwd=ROOT / 'module-three', env=env))
    children.append(subprocess.Popen(
        [sys.executable, 'server.py', '--preview'],
        cwd=ROOT / 'product-retouch', env=env))
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if any(child.poll() is not None for child in children):
            stop(children)
            raise SystemExit('预览进程提前退出。未调用模型。请确认 8774、8775、8776 没有被占用。')
        try:
            for port, path in ((workbench_port, '/api/session'), (listing_port, '/api/capabilities'), (retouch_port, '/api/session')):
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=1)
                connection.request('GET', path, headers={'Host': f'127.0.0.1:{port}'})
                response = connection.getresponse()
                response.read()
                if response.status != 200:
                    raise OSError(response.status)
            break
        except OSError:
            time.sleep(0.2)
    else:
        stop(children)
        raise SystemExit('预览服务没有在 40 秒内打开。未调用模型。')
    gateway = ThreadingHTTPServer(('127.0.0.1', gateway_port), PreviewProxy)
    gateway.ports = {'workbench': workbench_port, 'listing': listing_port, 'retouch': retouch_port}
    return children, gateway


def stop(children):
    for child in children:
        if child.poll() is None:
            child.terminate()
    for child in children:
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()


def main():
    parser = argparse.ArgumentParser(description='离线查看四个原界面，不需要密钥')
    parser.add_argument('--port', type=int, default=18080)
    args = parser.parse_args()
    os.chdir(ROOT)
    children, gateway = start_preview(ROOT / 'preview-data', args.port)
    print(f'离线界面：http://127.0.0.1:{args.port}', flush=True)
    print('这是现有模拟/未连接模式。可以看到四个模块的原页面。点击生成不会调用 Cockpit 或 Google。', flush=True)
    print('只在这台 Linux 环境里启动验证过。macOS 和 Windows 没有实测，缺 Ruby 或端口被占都会失败。', flush=True)
    try:
        gateway.serve_forever()
    finally:
        gateway.shutdown()
        stop(children)


if __name__ == '__main__':
    main()
