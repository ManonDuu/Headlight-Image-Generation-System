from variation_rules import CATALOG as VARIANTS, choose, REVISION
"""Independent local module 3 service. Generation requires an explicit request."""
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlsplit
import io
import zipfile
import argparse
import json
import re
import sys
from generation import Generation
from providers.gemini import GeminiProvider
from providers.transport import TRANSPORT_REVISION
from core import Store, PALETTES
from display_library import CATALOG, REVISION as DISPLAY_REVISION
ROOT=Path(__file__).resolve().parent
class Handler(SimpleHTTPRequestHandler):
    def __init__(self,*args,**kwargs): super().__init__(*args,directory=str(ROOT/'static'),**kwargs)
    def end_headers(self):
        self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Security-Policy',"default-src 'self'; img-src 'self' blob:; style-src 'self' 'unsafe-inline'; script-src 'self'; connect-src 'self'; object-src 'none'; frame-ancestors 'none'")
        super().end_headers()
    def check_origin(self):
        origin=self.headers.get('Origin');port=self.server.server_port
        if self.headers.get('Host') not in (f'127.0.0.1:{port}',f'localhost:{port}'): raise ValueError('Host 不匹配')
        if origin and origin not in (f'http://127.0.0.1:{port}',f'http://localhost:{port}'): raise ValueError('请求来源不匹配')
        if self.headers.get('Sec-Fetch-Site')=='cross-site': raise ValueError('不接受跨站请求')
    def send_json(self,data,status=200):
        payload=json.dumps(data,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
    def do_GET(self):
        try:
            self.check_origin();path=urlsplit(self.path).path
            if path=='/api/capabilities': return self.send_json({'budget':self.server.generation.budget_status(),'module':'three','transportRevision':TRANSPORT_REVISION,'generationRevision':'durable-set-v5-dated-authorization','provider':'gemini',**self.server.provider.capabilities(),'persistence':True,'planner':'history-aware-variation-compiler','rulesRevision':REVISION,'palettes':PALETTES,'displayLibraryRevision':DISPLAY_REVISION,'displayCatalog':{k:{'subpoints':v['subpoints'],'methods':[v['name'] for v in VARIANTS[k]],'layout':choose(k,v['subpoints'])} for k,v in CATALOG.items()}})
            if path=='/api/tasks': return self.send_json({'tasks':self.server.store.list()})
            archive_match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})/download',path)
            if archive_match:
                r=self.server.store.get(archive_match[1]);done=[t for t in r.get('generation',{}).get('images',[]) if t['state']=='completed']
                if not done:return self.send_json({'error':'暂无成功图片可下载'},404)
                buffer=io.BytesIO()
                with zipfile.ZipFile(buffer,'w',compression=zipfile.ZIP_STORED) as archive:
                    for t in done:archive.write(self.server.store._path(r['id'])/t['file'],t['file'])
                    archive.writestr('status.json',json.dumps({'count':r['plan']['count'],'generation':r.get('generation')},ensure_ascii=False,indent=2))
                payload=buffer.getvalue();self.send_response(200);self.send_header('Content-Type','application/zip');self.send_header('Content-Disposition',f'attachment; filename="images-{r["id"]}.zip"');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload);return
            result_match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})/results/(\d+)',path)
            if result_match:
                r=self.server.store.get(result_match[1])
                result=next((t for t in r.get('generation',{}).get('images',[]) if t['slot']==int(result_match[2]) and t['state']=='completed'),None)
                if not result: return self.send_json({'error':'结果尚未生成'},404)
                payload=(self.server.store._path(result_match[1])/result['file']).read_bytes()
                self.send_response(200);self.send_header('Content-Type',result['mime']);self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload);return
            match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})(?:/(asset-\d+))?',path)
            if match:
                record=self.server.store.get(match[1])
                if not match[2]: return self.send_json(record)
                asset=next((a for a in record['assets'] if a['id']==match[2]),None)
                if not asset: raise ValueError('图片不存在')
                payload=(self.server.store._path(match[1])/asset['file']).read_bytes()
                self.send_response(200);self.send_header('Content-Type',asset['mime']);self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload);return
            if path.startswith('/api/'): return self.send_json({'error':'接口不存在'},404)
            super().do_GET()
        except (ValueError,OSError,KeyError): self.send_json({'error':'请求无效或记录不可用'},400)
    def do_POST(self):
        try:
            self.check_origin()
            if self.headers.get('Content-Type','').split(';')[0]!='application/json': raise ValueError('需要 JSON 请求')
            length=int(self.headers.get('Content-Length','0'))
            if not 0<length<=175*1024*1024: raise ValueError('请求大小超限')
            body=json.loads(self.rfile.read(length));path=urlsplit(self.path).path
            if not isinstance(body,dict): raise ValueError('请求格式错误')
            if path=='/api/prepare': return self.send_json(self.server.store.save(body.get('plan'),body.get('uploads')),201)
            match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})/generate-set',path)
            if match: return self.send_json(self.server.generation.start_set(match[1]),202)
            match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})/retry-set',path)
            if match: return self.send_json(self.server.generation.retry_set(match[1],body.get('requestId')),202)
            match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})/generate',path)
            if match: return self.send_json(self.server.generation.start(match[1],body.get('slot')),202)
            match=re.fullmatch(r'/api/tasks/([0-9a-f]{32})/simulate',path)
            if match: return self.send_json(self.server.store.simulate(match[1]))
            return self.send_json({'error':'接口不存在；未发出模型请求'},405)
        except (ValueError,OSError,KeyError) as error: self.send_json({'error':str(error) if isinstance(error,ValueError) else '无法保存或读取任务，请重试'},400)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=8775);p.add_argument('--open',action='store_true');p.add_argument('--credential-stdin',action='store_true');p.add_argument('--data',default=str(ROOT/'data'))
    p.add_argument('--preview', action='store_true')
    args=p.parse_args();boot=json.loads(sys.stdin.read(16384)) if args.credential_stdin else {}
    if args.preview:
        provider=GeminiProvider(None)
    elif args.credential_stdin:
        proxy=boot.get('imageProxy') if isinstance(boot,dict) else None
        if not isinstance(proxy,dict) or not proxy.get('configPath'):
            print('反代版本缺少 imageProxy 配置。请先运行 python3 scripts/setup-proxy.py。未输出密钥，未调用模型。',file=sys.stderr);sys.exit(1)
        sys.path.insert(0,str(ROOT.parent/'deploy'))
        from image_proxy import load_config
        from providers.image_proxy import ImageProxyProvider
        provider=ImageProxyProvider(load_config(proxy['configPath']))
    else:
        print('请通过 python3 scripts/run-proxy.py 启动反代版本。未调用模型。',file=sys.stderr);sys.exit(1)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),Handler);server.store=Store(args.data);server.provider=provider;server.generation=Generation(server.store,server.provider)
    if args.open:
        import webbrowser
        webbrowser.open(f'http://127.0.0.1:{args.port}')
    print(f'Module 3: http://127.0.0.1:{args.port} — independent module ready',flush=True)
    server.serve_forever()
