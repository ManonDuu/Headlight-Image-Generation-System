"""Standalone, loopback-only preview. Does not import or start other modules."""
import json
import os
import sys
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit
from providers import get_provider
from jobs import Jobs
from rules import VERSION
from runtime_version import runtime_version
RUNTIME_VERSION = runtime_version()

ROOT = Path(__file__).resolve().parent
PORT = 8776
ORIGIN = f'http://127.0.0.1:{PORT}'
TOKEN = secrets.token_urlsafe(32)
BOOT = json.loads(sys.stdin.read(16384)) if '--credential-stdin' in sys.argv else {}
if '--preview' in sys.argv:
    PROVIDER = get_provider('preview')
elif '--credential-stdin' in sys.argv:
    proxy = BOOT.get('imageProxy') if isinstance(BOOT, dict) else None
    if not isinstance(proxy, dict) or not proxy.get('configPath'):
        print('反代版本缺少 imageProxy 配置。请先运行 python3 scripts/setup-proxy.py。未输出密钥，未调用模型。', file=sys.stderr)
        sys.exit(1)
    from providers.image_proxy import ImageProxyProvider
    sys.path.insert(0, str(ROOT.parent / 'deploy'))
    from image_proxy import load_config
    PROVIDER = ImageProxyProvider(load_config(proxy['configPath']))
else:
    if __name__ == '__main__':
        print('请通过 python3 scripts/run-proxy.py 启动反代版本。未调用模型。', file=sys.stderr)
        sys.exit(1)
    PROVIDER = get_provider(os.environ.get('RETOUCH_PROVIDER', 'gemini'), key=None)
JOBS = Jobs(ROOT / 'data' / 'jobs', PROVIDER)

class RetouchServer(ThreadingHTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, status, body, mime='application/json; charset=utf-8'):
        raw = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'unsafe-inline'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'; form-action 'none'")
        self.end_headers()
        self.wfile.write(raw)

    def allowed(self):
        return (self.headers.get('Host') == f'127.0.0.1:{PORT}'
                and self.client_address[0] == '127.0.0.1'
                and self.headers.get('Origin', ORIGIN) == ORIGIN)

    def do_GET(self):
        if not self.allowed():
            return self.respond(403, {'error': 'local origin required'})
        path = urlsplit(self.path).path
        if path == '/api/session':
            if self.headers.get('Sec-Fetch-Site') == 'cross-site':
                return self.respond(403, {'error': 'cross-site API blocked'})
            return self.respond(200, {'applicationId': 'PictureOps.ProductRetouch', 'version': '20261023.2', 'rulesVersion': VERSION, 'runtimeVersion': RUNTIME_VERSION, 'pid': os.getpid(), 'model': getattr(PROVIDER,'model',None),
                                      'phase': 'manual-testing', 'provider': PROVIDER.name,
                                      'generationEnabled': getattr(PROVIDER, 'connected', False), 'token': TOKEN, 'history': JOBS.history()})
        if path.startswith('/api/task/'):
            if self.headers.get('Sec-Fetch-Site') == 'cross-site' or self.headers.get('X-Session-Token') != TOKEN:
                return self.respond(403, {'error':'session required'})
            try:
                segments=path.split('/')
                state=JOBS.read(segments[3])
                if len(segments)==5 and segments[4]=='image':
                    if state['state']!='completed':
                        raise ValueError('图片未完成')
                    return self.respond(200,(JOBS.folder(state['id'])/'output').read_bytes(),state['outputMime'])
                return self.respond(200,state)
            except Exception:
                return self.respond(400,{'error':'无法读取任务或图片'})
        files = {'/': ('index.html', 'text/html; charset=utf-8'),
                 '/app.js': ('app.js', 'application/javascript; charset=utf-8')}
        if path not in files:
            return self.respond(404, {'error': 'not found'})
        filename, mime = files[path]
        return self.respond(200, (ROOT / 'static' / filename).read_bytes(), mime)

    def do_POST(self):
        if not self.allowed() or self.headers.get('Origin') != ORIGIN or self.headers.get('X-Session-Token') != TOKEN:
            return self.respond(403, {'error':'session/origin required'})
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=6000000 or self.headers.get('Content-Type','').split(';')[0]!='application/json':
                raise ValueError('请求格式或大小无效')
            data=json.loads(self.rfile.read(length))
            if self.path=='/api/prepare':
                return self.respond(200,JOBS.prepare(data))
            if self.path=='/api/generate' and set(data)=={'id'}:
                return self.respond(200,JOBS.generate(data['id']))
            raise ValueError('操作无效')
        except (ValueError,KeyError,TypeError) as exc:
            self.respond(400,{'error':str(exc)})
        except Exception:
            self.respond(400,{'error':'任务处理失败，未自动重试'})

if __name__ == '__main__':
    if '--preview' in sys.argv:
        print(f'独立精修模块预览：{ORIGIN}；未连接模型，不会生图。', flush=True)
    else:
        print(f'独立精修模块：{ORIGIN}；点击生成才调用已配置的反代生图服务', flush=True)
    try:
        server = RetouchServer(('127.0.0.1', PORT), Handler)
    except OSError as exc:
        print(f'精修服务无法绑定端口 {PORT}（系统错误码 {exc.errno}）；未调用模型。', file=sys.stderr, flush=True)
        sys.exit(1)
    server.serve_forever()
