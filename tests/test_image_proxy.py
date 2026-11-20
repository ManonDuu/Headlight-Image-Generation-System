"""Offline proxy tests. They talk only to a local fake server, never to a paid API."""
import base64
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'deploy'))
from image_proxy import ProxyError, execute, load_config, translate

KEY = 'test-key-not-real'


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass

    def _read(self):
        return self.rfile.read(int(self.headers.get('Content-Length', '0')))

    def _send(self, status, body, mime='application/json'):
        data = body if isinstance(body, bytes) else body.encode()
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self.server.gets.append(self.path)
        if self.path.endswith('/models'):
            self._send(200 if self.server.mode != 'no-models' else 404,
                       json.dumps({'data': [{'id': 'gpt-image-2.6'}, {'id': 'demo-model'}]}))
        else:
            self._send(404, '{}')

    def do_POST(self):
        body = self._read()
        self.server.posts.append(self.path)
        self.server.bodies.append(body)
        self.server.types.append(self.headers.get('Content-Type', ''))
        self.server.auths.append(self.headers.get('Authorization'))
        if self.server.mode == 'fail-first':
            self.server.mode = 'ok'
            self._send(401, '{"error":{"message":"unauthorized"}}')
            return
        if self.server.mode == 'timeout':
            import time
            time.sleep(3)
            return
        if self.server.mode == 'redirect':
            self.send_response(302)
            self.send_header('Location', 'http://127.0.0.1/secret.png')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if self.server.mode == 'fail':
            self._send(500, '{"error":{"message":"down"}}')
            return
        if self.server.mode == 'safety':
            self._send(400, '{"error":{"message":"moderation blocked","code":"content_policy_violation"}}')
            return
        if self.server.mode == 'url':
            self._send(200, json.dumps({'data': [{'url': 'http://127.0.0.1/secret.png'}]}))
            return
        if self.server.mode == 'multi':
            blob = base64.b64encode(self.server.png).decode()
            self._send(200, json.dumps({'data': [{'b64_json': blob}, {'b64_json': blob}]}))
            return
        self._send(200, json.dumps({'data': [{'b64_json': base64.b64encode(self.server.png).decode()}]}))


def picture(fmt, size, color):
    stream = io.BytesIO()
    Image.new('RGB', size, color).save(stream, format=fmt)
    return stream.getvalue()


class ProxyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self._env = {name: os.environ.get(name) for name in ('USAGE_DB', 'BUDGET_CONFIG', 'SYSTEM_BUDGET')}
        os.environ['USAGE_DB'] = str(Path(self.tmp.name) / 'usage.sqlite3')
        os.environ['BUDGET_CONFIG'] = str(ROOT / 'deploy' / 'budget.json')
        os.environ['SYSTEM_BUDGET'] = '1'
        self.servers = []

    def tearDown(self):
        for server in self.servers:
            server.shutdown()
            server.server_close()
        for name, value in self._env.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value
        self.tmp.cleanup()

    def serve(self, mode='ok', png=None):
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        server.mode = mode
        server.posts, server.gets, server.bodies, server.types, server.auths = [], [], [], [], []
        server.png = png or picture('PNG', (32, 16), 'navy')
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.servers.append(server)
        return server

    def config(self, server, model='gpt-image-2.6'):
        path = Path(self.tmp.name) / f'{server.server_port}.json'
        path.write_text(json.dumps({'baseUrl': f'http://127.0.0.1:{server.server_port}/v1',
                                    'apiKey': KEY, 'model': model}))
        return load_config(path)

    def gemini_body(self, parts, ratio='4:5'):
        return {'contents': [{'role': 'user', 'parts': parts}],
                'generationConfig': {'candidateCount': 1, 'responseModalities': ['IMAGE'],
                                     'imageConfig': {'aspectRatio': ratio, 'imageSize': '2K'}}}

    def test_config_rejects_missing_and_illegal_urls_without_connecting(self):
        missing = Path(self.tmp.name) / 'absent.json'
        with self.assertRaises(ProxyError):
            load_config(missing)
        samples = {
            'http://example.com/v1': 'https',
            'http://10.1.2.3:62037/v1': 'https',
            'http://127.0.0.1.evil.com/v1': 'https',
            'http://user:secret@127.0.0.1:62037/v1': '账号',
            'file:///tmp/x': 'http',
            'https://images.example.com/v1?x=1': '查询',
        }
        for base, needle in samples.items():
            path = Path(self.tmp.name) / 'bad.json'
            path.write_text(json.dumps({'baseUrl': base, 'apiKey': KEY, 'model': 'gpt-image-2.6'}))
            with self.assertRaises(ProxyError) as caught:
                load_config(path)
            self.assertIn(needle, str(caught.exception))
            self.assertNotIn(KEY, str(caught.exception))
        path.write_text(json.dumps({'baseUrl': 'https://images.example.com/v1', 'apiKey': '', 'model': 'gpt-image-2.6'}))
        with self.assertRaises(ProxyError):
            load_config(path)
        path.write_text(json.dumps({'baseUrl': 'http://127.0.0.1:62037/v1', 'apiKey': KEY, 'model': ''}))
        with self.assertRaises(ProxyError):
            load_config(path)
        import socket
        original = socket.socket
        def boom(*_a, **_k):
            raise AssertionError('config validation opened a socket')
        socket.socket = boom
        try:
            path.write_text(json.dumps({'baseUrl': 'http://127.0.0.1:62037/v1', 'apiKey': KEY, 'model': 'gpt-image-2.6'}))
            cfg = load_config(path)
            self.assertEqual(cfg.model, 'gpt-image-2.6')
        finally:
            socket.socket = original

    def test_loopback_http_is_allowed_and_remote_http_is_not(self):
        sys.path.insert(0, str(ROOT / 'deploy'))
        from supervise import nginx_config
        text = nginx_config('http://127.0.0.1:18080', True, '127.0.0.1:18080')
        self.assertIn('listen 127.0.0.1:18080;', text)
        self.assertIn('"http://127.0.0.1:18080" 1;', text)
        for bad in ('http://10.0.0.8:18080', 'http://evil.example', 'https://ok.example/path'):
            with self.assertRaises(ValueError):
                nginx_config(bad, True, '127.0.0.1:18080')

    def test_reference_success_keeps_non_2k_bytes_and_one_post(self):
        png = picture('PNG', (32, 16), 'navy')
        server = self.serve(png=png)
        source = picture('PNG', (8, 8), 'white')
        body = self.gemini_body([
            {'text': 'RULE Return exactly one native 2K 4:5 image.'},
            {'text': 'REFERENCE: reconstruction source. The next image is image 1.'},
            {'inlineData': {'mimeType': 'image/png', 'data': base64.b64encode(source).decode()}},
        ])
        result = execute(self.config(server), body, 'reference')
        self.assertEqual(server.posts, ['/v1/images/edits'])
        self.assertEqual(result['bytes'], png)
        self.assertEqual(result['diagnostic']['actualDimensions'], [32, 16])
        self.assertFalse(result['diagnostic']['outputVerified2K'])
        self.assertEqual(result['diagnostic']['retries'], 0)
        self.assertEqual(hashlib.sha256(result['bytes']).hexdigest(), hashlib.sha256(png).hexdigest())
        self.assertNotIn(KEY, json.dumps(result['diagnostic']))
        sent = server.bodies[0]
        self.assertIn(b'name="model"', sent)
        self.assertIn(b'gpt-image-2.6', sent)
        self.assertIn(b'name="size"\r\n\r\n800x1008', sent)
        self.assertIn(b'4:5', sent)
        self.assertNotEqual(result['diagnostic']['actualDimensions'], [800, 1008])
        self.assertEqual(result['bytes'], png)
        self.assertNotIn(b'name="quality"', sent)
        self.assertNotIn(b'name="moderation"', sent)
        self.assertNotIn(b'name="response_format"', sent)
        self.assertIn(source, sent)
        self.assertEqual(server.auths, ['Bearer ' + KEY])

    def test_replacement_image_order_and_role_text(self):
        reference = picture('PNG', (6, 6), 'red')
        product = picture('JPEG', (7, 5), 'green')
        server = self.serve()
        body = self.gemini_body([
            {'text': 'RULES'},
            {'text': 'REFERENCE: image 1 only.'},
            {'inlineData': {'mimeType': 'image/png', 'data': base64.b64encode(reference).decode()}},
            {'text': 'PRODUCT: image 2 only.'},
            {'inlineData': {'mimeType': 'image/jpeg', 'data': base64.b64encode(product).decode()}},
        ], '16:9')
        execute(self.config(server), body, 'replacement')
        sent = server.bodies[0]
        self.assertLess(sent.find(b'REFERENCE: image 1 only.'), sent.find(b'PRODUCT: image 2 only.'))
        self.assertLess(sent.find(reference), sent.find(product))
        self.assertIn(b'name="size"\r\n\r\n1008x560', sent)
        self.assertIn(b'16:9', sent)
        self.assertEqual(server.posts, ['/v1/images/edits'])

    def test_each_original_ratio_requests_its_own_nearby_size(self):
        from image_proxy import _ratio_error, default_sizes
        native = {'1:1': (2048, 2048), '4:5': (1856, 2304), '5:4': (2304, 1856), '3:4': (1792, 2400),
                  '4:3': (2400, 1792), '9:16': (1536, 2752), '16:9': (2752, 1536), '2:3': (1696, 2528), '3:2': (2528, 1696)}
        sizes = default_sizes()
        seen = {}
        for ratio, old in native.items():
            spec = translate(self.gemini_body([{'text': 'frozen rules'}], ratio))
            width, height = (int(part) for part in spec['size'].split('x'))
            self.assertEqual(spec['size'], sizes[ratio])
            self.assertIn(ratio, spec['prompt'])
            self.assertNotEqual((width, height), old)
            self.assertEqual((width % 16, height % 16), (0, 0))
            self.assertLess(_ratio_error(ratio, width, height), 0.025)
            self.assertNotIn(spec['size'], seen)
            seen[spec['size']] = ratio
        self.assertEqual(sizes['4:5'], '800x1008')
        self.assertEqual(sizes['12:15'], sizes['4:5'])
        self.assertNotEqual(sizes['4:5'], sizes['3:4'])
        self.assertNotEqual(sizes['5:4'], sizes['4:3'])
        self.assertNotEqual(sizes['16:9'], sizes['3:2'])
        path = Path(self.tmp.name) / 'sizes.json'
        path.write_text(json.dumps({'baseUrl': 'http://127.0.0.1:9/v1', 'apiKey': KEY, 'model': 'gpt-image-2.6',
                                    'sizes': {'4:5': '640x800', '3:4': '768x1024'}}))
        from image_proxy import load_config
        spec = translate(self.gemini_body([{'text': 'frozen rules'}], '4:5'), load_config(path).sizes)
        self.assertEqual(spec['size'], '640x800')
        self.assertIn('4:5', spec['prompt'])
        path.write_text(json.dumps({'baseUrl': 'http://127.0.0.1:9/v1', 'apiKey': KEY, 'model': 'gpt-image-2.6',
                                    'sizes': {'4:5': '1024x1536'}}))
        with self.assertRaises(ProxyError) as caught:
            load_config(path)
        self.assertIn('不会用另一个比例的尺寸代替', str(caught.exception))

    def test_listing_without_image_uses_generations_once(self):
        server = self.serve()
        body = self.gemini_body([{'text': 'No product photo for this slot. 1:1'}], '1:1')
        result = execute(self.config(server), body, 'listing')
        self.assertEqual(server.posts, ['/v1/images/generations'])
        self.assertTrue(server.types[0].startswith('application/json'))
        payload = json.loads(server.bodies[0])
        self.assertEqual(set(payload), {'model', 'prompt', 'size'})
        self.assertEqual(payload['size'], '1008x1008')
        self.assertIn('1:1', payload['prompt'])
        self.assertEqual(result['diagnostic']['endpointKind'], 'generations')
        self.assertNotEqual(result['diagnostic']['actualDimensions'], [2048, 2048])

    def test_listing_webp_is_really_converted_before_send(self):
        webp = picture('WEBP', (9, 4), 'orange')
        self.assertEqual(webp[8:12], b'WEBP')
        server = self.serve()
        self.config(server)
        spec = translate(self.gemini_body([
            {'text': 'Uploaded product: identity reference only'},
            {'inlineData': {'mimeType': 'image/webp', 'data': base64.b64encode(webp).decode()}},
        ]))
        self.assertEqual(spec['images'][0][0], 'image/png')
        self.assertTrue(spec['images'][0][1].startswith(b'\x89PNG\r\n\x1a\n'))
        self.assertNotEqual(spec['images'][0][1], webp)
        with Image.open(io.BytesIO(webp)) as src, Image.open(io.BytesIO(spec['images'][0][1])) as out:
            self.assertEqual(list(src.convert('RGB').getdata()), list(out.convert('RGB').getdata()))
        code = r'''
import json, os, sys
sys.path[:0] = [sys.argv[1], sys.argv[2]]
os.environ["USAGE_DB"] = sys.argv[3]
os.environ["BUDGET_CONFIG"] = sys.argv[2] + "/budget.json"
from image_proxy import load_config
from providers.image_proxy import ImageProxyProvider
cfg = load_config(sys.argv[4])
web = open(sys.argv[5], "rb").read()
result = ImageProxyProvider(cfg).generate(
    {"prompt": "frozen prompt\n{\"providerExecution\":{\"schema\":\"gemini-art-check-v2\",\"renderBrief\":\"RENDER BRIEF\",\"finalCheck\":\"FINAL CHECK\"}}", "ratio": "4:5"},
    [{"mime": "image/webp", "bytes": web}], {"reserveUSD": 0.5})
open(sys.argv[6], "w").write(json.dumps({"mime": result["mime"], "dimensions": result["diagnostic"]["actualDimensions"], "sha": __import__("hashlib").sha256(result["bytes"]).hexdigest()}))
'''
        out = Path(self.tmp.name) / 'provider.json'
        web_path = Path(self.tmp.name) / 'in.webp'
        web_path.write_bytes(webp)
        cfg_path = Path(self.tmp.name) / f'{server.server_port}.json'
        proc = subprocess.run([sys.executable, '-c', code, str(ROOT / 'module-three'), str(ROOT / 'deploy'),
                               os.environ['USAGE_DB'], str(cfg_path), str(web_path), str(out)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        saved = json.loads(out.read_text())
        self.assertEqual(saved['mime'], 'image/png')
        self.assertEqual(saved['dimensions'], [32, 16])
        sent = server.bodies[0]
        self.assertIn(b'RENDER BRIEF', sent)
        self.assertIn(b'FINAL CHECK', sent)
        self.assertNotIn(b'WEBP', sent)
        self.assertIn(b'\x89PNG\r\n\x1a\n', sent)

    def test_retouch_success_failure_and_saved_hash(self):
        jpeg = picture('JPEG', (5, 5), 'blue')
        server = self.serve()
        self.config(server)
        code = r'''
import json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, sys.argv[2])
os.environ["USAGE_DB"] = sys.argv[3]
os.environ["BUDGET_CONFIG"] = sys.argv[2] + "/budget.json"
from image_proxy import load_config
from providers import RenderRequest
from providers.image_proxy import ImageProxyProvider
cfg = load_config(sys.argv[4])
image = open(sys.argv[5], "rb").read()
provider = ImageProxyProvider(cfg)
try:
    result = provider.generate(RenderRequest(image, "image/jpeg", "retouch the metal", "3:4"))
    json.dump({"ok": True, "sha": __import__("hashlib").sha256(result.image).hexdigest(), "mime": result.mime,
               "verified": provider.last_diagnostic["outputVerified2K"]}, open(sys.argv[6], "w"))
except Exception as exc:
    json.dump({"ok": False, "error": str(exc)}, open(sys.argv[6], "w"))
'''
        cfg_path = Path(self.tmp.name) / f'{server.server_port}.json'
        image_path = Path(self.tmp.name) / 'src.jpg'
        image_path.write_bytes(jpeg)
        out = Path(self.tmp.name) / 'retouch.json'
        proc = subprocess.run([sys.executable, '-c', code, str(ROOT / 'product-retouch'), str(ROOT / 'deploy'),
                               os.environ['USAGE_DB'], str(cfg_path), str(image_path), str(out)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        saved = json.loads(out.read_text())
        self.assertTrue(saved['ok'], saved)
        self.assertFalse(saved['verified'])
        self.assertEqual(saved['sha'], hashlib.sha256(server.png).hexdigest())
        self.assertIn(jpeg, server.bodies[0])
        self.assertEqual(len(server.posts), 1)
        failed = self.serve(mode='fail')
        failed_cfg = Path(self.tmp.name) / f'{failed.server_port}.json'
        failed_cfg.write_text(cfg_path.read_text().replace(f':{server.server_port}/', f':{failed.server_port}/'))
        out2 = Path(self.tmp.name) / 'retouch-fail.json'
        proc = subprocess.run([sys.executable, '-c', code, str(ROOT / 'product-retouch'), str(ROOT / 'deploy'),
                               os.environ['USAGE_DB'], str(failed_cfg), str(image_path), str(out2)],
                              capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn('未自动重试', json.loads(out2.read_text())['error'])
        self.assertEqual(len(failed.posts), 1)

    def test_timeout_safety_redirect_and_url_do_not_retry_or_fetch(self):
        slow = self.serve(mode='timeout')
        with self.assertRaises(ProxyError) as caught:
            execute(self.config(slow), self.gemini_body([{'text': 'slow'}], '1:1'), 'reference', timeout=1, connect_timeout=1)
        self.assertIn('未自动重试', str(caught.exception))
        self.assertEqual(len(slow.posts), 1)
        unsafe = self.serve(mode='safety')
        with self.assertRaises(ProxyError) as caught:
            execute(self.config(unsafe), self.gemini_body([{'text': 'blocked'}]), 'listing')
        self.assertIn('安全检查', str(caught.exception))
        self.assertEqual(len(unsafe.posts), 1)
        linked = self.serve(mode='url')
        with self.assertRaises(ProxyError) as caught:
            execute(self.config(linked), self.gemini_body([{'text': 'link'}]), 'retouch')
        self.assertIn('拒绝下载', str(caught.exception))
        self.assertEqual(linked.gets, [])
        self.assertEqual(len(linked.posts), 1)
        jumped = self.serve(mode='redirect')
        with self.assertRaises(ProxyError):
            execute(self.config(jumped), self.gemini_body([{'text': 'go'}]), 'reference')
        self.assertEqual(jumped.posts, ['/v1/images/generations'])
        many = self.serve(mode='multi')
        with self.assertRaises(ProxyError):
            execute(self.config(many), self.gemini_body([{'text': 'two'}]), 'reference')
        self.assertEqual(len(many.posts), 1)

    def test_detect_is_get_only_and_does_not_rewrite_config(self):
        server = self.serve()
        cfg = self.config(server, model='keep-this')
        from image_proxy import detect_models
        self.assertEqual(detect_models(cfg), ['gpt-image-2.6', 'demo-model'])
        self.assertEqual(server.posts, [])
        self.assertTrue(server.gets[0].endswith('/models'))
        self.assertEqual(cfg.model, 'keep-this')
        missing = self.serve(mode='no-models')
        with self.assertRaises(ProxyError) as caught:
            detect_models(self.config(missing))
        self.assertIn('不保证可用', str(caught.exception))
        self.assertEqual(missing.posts, [])

    def test_freeze_body_rules_stay_and_ruby_client_saves_original_bytes(self):
        probe = ROOT / 'deploy' / 'image_probe.py'
        mode = probe.stat().st_mode
        probe.chmod(mode | 0o111)
        self.addCleanup(probe.chmod, mode)
        one = Path(self.tmp.name) / 'a.png'
        two = Path(self.tmp.name) / 'b.png'
        one.write_bytes(picture('PNG', (12, 10), 'white'))
        two.write_bytes(picture('PNG', (11, 9), 'black'))
        script = r'''
require "json"; require "base64"; require "digest"
require "./module-two-candidate/direct-image-plan"
a=File.binread(ARGV[0]); b=File.binread(ARGV[1])
opts={"businessSpec"=>"car-light-direct-20261021.20","module"=>"reference-reconstruction","mode"=>"ai-rewrite","layoutMode"=>"auto-layout","layoutTone"=>"keep-reference","output"=>{"aspectRatio"=>"4:5","imageSize"=>"2K"}}
plan=DirectImagePlan.prepare(a,nil,opts,mock:true,input_origin:"test")
body=JSON.parse(plan["body"])
abort "2k" unless body.dig("generationConfig","imageConfig","imageSize")=="2K"
abort "ratio" unless body.dig("generationConfig","imageConfig","aspectRatio")=="4:5"
abort "rule" unless body["contents"][0]["parts"][0]["text"].include?("Direct generation")
product=opts.merge("businessSpec"=>"car-light-product-20261022.10","module"=>"product-replacement","productName"=>"bulb")
second=DirectImagePlan.prepare(a,b,product,mock:true,input_origin:"test")
parts=JSON.parse(second["body"])["contents"][0]["parts"]
abort "roles" unless parts[1]["text"].include?("REFERENCE") && parts[3]["text"].include?("PRODUCT")
File.write(ARGV[2], second["body"])
'''
        frozen = Path(self.tmp.name) / 'frozen.json'
        proc = subprocess.run(['ruby', '-e', script, str(one), str(two), str(frozen)], cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        unchanged = ['module-three/providers/gemini.py', 'module-three/providers/transport.py',
                     'product-retouch/providers/gemini.py', 'product-retouch/providers/transport.py',
                     'module-two-candidate/generate-content-adapter.rb', 'module-two-candidate/generate-content-transport.rb',
                     'module-two-candidate/direct-image-plan.rb', 'compose.yaml', 'Dockerfile']
        baseline = json.loads((ROOT / 'baseline/source-sha256.json').read_text())
        adapted = json.loads((ROOT / 'baseline/adaptations.json').read_text())['changed']
        for path in unchanged:
            digest = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
            if path in baseline or path in adapted:
                self.assertEqual(digest, adapted.get(path, baseline[path]))
            else:
                text = (ROOT / path).read_text()
                self.assertNotIn('image_proxy', text)
                self.assertNotIn('image-proxy', text)
        if shutil.which('git'):
            diff = subprocess.run(['git', 'diff', '--exit-code', 'main', '--', *unchanged], cwd=ROOT, capture_output=True, text=True)
            self.assertEqual(diff.returncode, 0, diff.stdout)
        server = self.serve()
        self.config(server)
        cfg = Path(self.tmp.name) / f'{server.server_port}.json'
        ruby = r'''
require "./module-two-candidate/image-proxy-client"
result=ImageProxyClient.generate(File.read(ARGV[1]), {"configPath"=>ARGV[0]}, "replacement")
abort "hash" unless result["outputHash"]==Digest::SHA256.hexdigest(result["bytes"])
abort "label" unless result["outputVerified2K"]==false
File.binwrite(ARGV[2], result["bytes"])
'''
        out = Path(self.tmp.name) / 'saved.bin'
        proc = subprocess.run(['ruby', '-e', ruby, str(cfg), str(frozen), str(out)], cwd=ROOT, capture_output=True, text=True,
                              env={**os.environ, 'USAGE_DB': os.environ['USAGE_DB'], 'BUDGET_CONFIG': os.environ['BUDGET_CONFIG']})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(out.read_bytes(), server.png)
        self.assertEqual(hashlib.sha256(out.read_bytes()).hexdigest(), hashlib.sha256(server.png).hexdigest())
        sent = server.bodies[0]
        self.assertLess(sent.find(one.read_bytes()), sent.find(two.read_bytes()))
        self.assertIn(b'REFERENCE:', sent)
        self.assertIn(b'PRODUCT:', sent)

    def test_daily_boot_without_proxy_config_fails_before_listen(self):
        proc = subprocess.run(['ruby', 'bridge-server.rb', '--reference-daily-stdin', '--product-daily', '--port', '8791'],
                              cwd=ROOT / 'module-two-candidate',
                              input=json.dumps({'rulesVersion': 'car-light-direct-20261021.20', 'key': 'not-used'}),
                              capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn('imageProxy', proc.stderr)
        self.assertNotIn('not-used', proc.stderr)

    def test_preview_opens_four_existing_screens_without_a_key(self):
        if shutil.which('ruby') is None:
            self.skipTest('ruby is required for the existing workbench UI')
        import importlib.util
        spec = importlib.util.spec_from_file_location('preview_ui', ROOT / 'scripts' / 'preview-ui.py')
        preview_ui = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(preview_ui)
        data = Path(self.tmp.name) / 'preview'
        children, gateway = preview_ui.start_preview(data, gateway_port=18180, workbench_port=18774, listing_port=18775, retouch_port=8776)
        self.addCleanup(preview_ui.stop, children)
        self.addCleanup(gateway.shutdown)
        thread = threading.Thread(target=gateway.serve_forever, daemon=True)
        thread.start()
        import urllib.request
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        pages = {
            'http://127.0.0.1:18180/': '参考图卖点重构',
            'http://127.0.0.1:18180/listing/': '先认识你的产品',
            'http://127.0.0.1:18180/retouch/': '产品精修建模渲染',
        }
        for url, marker in pages.items():
            with opener.open(url, timeout=5) as response:
                text = response.read().decode('utf-8', 'replace')
            self.assertEqual(response.status, 200)
            self.assertIn(marker, text)
        with opener.open('http://127.0.0.1:18180/api/session', timeout=5) as response:
            session = json.loads(response.read().decode())
        self.assertTrue(session['mock'])
        home = opener.open('http://127.0.0.1:18180/', timeout=5).read().decode('utf-8', 'replace')
        self.assertIn('id="home"', home)
        self.assertIn('选择你的创作模块', home)
        self.assertIn('id="brandHome" class="brand" href="/"', home)
        self.assertIn('<main id="moduleView" class="workflow" hidden>', home)
        for url in ('http://127.0.0.1:18180/listing/', 'http://127.0.0.1:18180/retouch/'):
            page = opener.open(url, timeout=5).read().decode('utf-8', 'replace')
            self.assertIn('class="brand" href="/"', page)
            self.assertIn('PictureOps', page)

    def test_brand_link_returns_to_module_picker_without_generation_actions(self):
        home = (ROOT / 'module-two-candidate/bridge.html').read_text()
        listing = (ROOT / 'module-three/static/index.html').read_text()
        retouch = (ROOT / 'product-retouch/static/index.html').read_text()
        script = (ROOT / 'module-two-candidate/original-ui.js').read_text()
        self.assertIn('id="home"', home)
        self.assertIn('选择你的创作模块', home)
        self.assertIn('<main id="moduleView" class="workflow" hidden>', home)
        self.assertIn('id="brandHome" class="brand" href="/"', home)
        self.assertIn('class="brand" href="/"', listing)
        self.assertIn('整套附图工作台', listing)
        self.assertIn('class="brand" href="/"', retouch)
        self.assertIn('产品精修建模渲染', retouch)
        self.assertIn('showModuleHome', script)
        self.assertIn("event.preventDefault();showModuleHome();", script)
        for banned in ('/api/generate', '/api/generic/generate', '/api/freeze', 'newTask'):
            self.assertNotIn(banned, script[script.find('const showModuleHome'):script.find('document.querySelectorAll')])

    def test_shared_config_survives_success_and_error_and_blank_key_stays_offline(self):
        png = picture('PNG', (20, 12), 'navy')
        body = self.gemini_body([{'text': 'slot rules 4:5'}, {'inlineData': {'mimeType': 'image/png', 'data': base64.b64encode(picture('PNG', (4, 4), 'white')).decode()}}], '4:5')
        server = self.serve(png=png)
        cfg = self.config(server)
        first = execute(cfg, body, 'listing')
        second = execute(cfg, body, 'listing')
        self.assertEqual(cfg.api_key, KEY)
        self.assertEqual(server.auths, ['Bearer ' + KEY, 'Bearer ' + KEY])
        self.assertEqual(first['bytes'], png)
        self.assertEqual(second['bytes'], png)
        failed = self.serve(mode='fail-first', png=png)
        cfg2 = self.config(failed)
        with self.assertRaises(ProxyError) as caught:
            execute(cfg2, body, 'listing')
        self.assertEqual(caught.exception.diagnostic.get('httpStatus'), 401)
        self.assertEqual(caught.exception.diagnostic.get('endpointKind'), 'edits')
        self.assertNotIn(KEY, str(caught.exception))
        self.assertNotIn('slot rules', json.dumps(caught.exception.diagnostic))
        recovered = execute(cfg2, body, 'listing')
        self.assertEqual(cfg2.api_key, KEY)
        self.assertEqual(recovered['bytes'], png)
        self.assertEqual(failed.auths, ['Bearer ' + KEY, 'Bearer ' + KEY])
        for blank in (None, '', '   ', 'bad key'):
            cfg.api_key = blank
            before = len(server.posts)
            with self.assertRaises(ProxyError) as caught:
                execute(cfg, body, 'listing')
            self.assertEqual(len(server.posts), before)
            self.assertNotIn('httpStatus', caught.exception.diagnostic)
        code = r'''
import json, os, sys
sys.path[:0] = [sys.argv[1], sys.argv[2]]
os.environ["USAGE_DB"] = sys.argv[3]
os.environ["BUDGET_CONFIG"] = sys.argv[2] + "/budget.json"
from image_proxy import load_config
from providers.image_proxy import ImageProxyProvider
cfg = load_config(sys.argv[4])
provider = ImageProxyProvider(cfg)
web = open(sys.argv[5], "rb").read()
brief = {"prompt": "frozen listing prompt", "ratio": "1:1"}
asset = [{"mime": "image/png", "bytes": web}]
states = []
for _ in range(2):
    try:
        result = provider.generate(brief, asset, {"reserveUSD": 0.5})
        states.append({"ok": True, "n": len(result["bytes"]), "http": result["diagnostic"].get("httpStatus"), "kind": result["diagnostic"].get("endpointKind")})
    except RuntimeError as exc:
        states.append({"ok": False, "error": str(exc), "diagnostic": dict(getattr(exc, "diagnostic", {}))})
json.dump({"keyStill": cfg.api_key == sys.argv[7], "states": states}, open(sys.argv[6], "w"))
'''
        listing = Path(self.tmp.name) / 'listing.json'
        image = Path(self.tmp.name) / 'slot.png'
        image.write_bytes(picture('PNG', (4, 4), 'red'))
        once = self.serve(mode='fail-first', png=png)
        self.config(once)
        proc = subprocess.run([sys.executable, '-c', code, str(ROOT / 'module-three'), str(ROOT / 'deploy'),
                               os.environ['USAGE_DB'], str(Path(self.tmp.name) / f'{once.server_port}.json'),
                               str(image), str(listing), KEY], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        saved = json.loads(listing.read_text())
        self.assertTrue(saved['keyStill'])
        self.assertFalse(saved['states'][0]['ok'])
        self.assertEqual(saved['states'][0]['diagnostic'].get('httpStatus'), 401)
        self.assertEqual(saved['states'][0]['diagnostic'].get('endpointKind'), 'edits')
        self.assertNotIn(KEY, saved['states'][0]['error'])
        self.assertTrue(saved['states'][1]['ok'])
        self.assertEqual(saved['states'][1]['http'], 200)
        retouch_code = r'''
import json, os, sys
sys.path.insert(0, sys.argv[1])
sys.path.insert(0, sys.argv[2])
os.environ["USAGE_DB"] = sys.argv[3]
os.environ["BUDGET_CONFIG"] = sys.argv[2] + "/budget.json"
from image_proxy import load_config
from providers import RenderRequest
from providers.image_proxy import ImageProxyProvider
cfg = load_config(sys.argv[4])
image = open(sys.argv[5], "rb").read()
provider = ImageProxyProvider(cfg)
states = []
for _ in range(2):
    try:
        result = provider.generate(RenderRequest(image, "image/jpeg", "retouch prompt", "1:1"))
        states.append({"ok": True, "n": len(result.image), "diag": provider.last_diagnostic})
    except RuntimeError as exc:
        states.append({"ok": False, "error": str(exc), "diag": dict(provider.last_diagnostic)})
json.dump({"keyStill": cfg.api_key == sys.argv[7], "states": states}, open(sys.argv[6], "w"))
'''
        retouch = Path(self.tmp.name) / 'retouch-seq.json'
        jpeg = Path(self.tmp.name) / 'src.jpg'
        jpeg.write_bytes(picture('JPEG', (5, 5), 'blue'))
        seq = self.serve(png=png)
        self.config(seq)
        proc = subprocess.run([sys.executable, '-c', retouch_code, str(ROOT / 'product-retouch'), str(ROOT / 'deploy'),
                               os.environ['USAGE_DB'], str(Path(self.tmp.name) / f'{seq.server_port}.json'),
                               str(jpeg), str(retouch), KEY], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        saved = json.loads(retouch.read_text())
        self.assertTrue(saved['keyStill'])
        self.assertTrue(saved['states'][0]['ok'] and saved['states'][1]['ok'])
        self.assertEqual([item['diag'].get('httpStatus') for item in saved['states']], [200, 200])
        self.assertEqual(seq.auths, ['Bearer ' + KEY, 'Bearer ' + KEY])

    def test_ui_diff_is_only_provider_and_result_wording(self):
        if shutil.which('git'):
            parent = subprocess.run(['git', 'rev-parse', 'main^'], cwd=ROOT, capture_output=True, text=True)
            if parent.returncode == 0:
                names = subprocess.check_output(['git', 'diff', '--name-only', 'main', '--', '*.js', '*.html', '*.css'], cwd=ROOT, text=True).split()
                self.assertEqual(sorted(names), ['module-three/static/backend.js', 'module-three/static/index.html', 'module-two-candidate/bridge.html', 'module-two-candidate/original-ui.js', 'product-retouch/static/app.js', 'product-retouch/static/index.html'])
        backend = (ROOT / 'module-three/static/backend.js').read_text()
        retouch = (ROOT / 'product-retouch/static/app.js').read_text()
        self.assertNotIn('aistudio.google.com', backend)
        self.assertNotIn('Gemini 计费未通过', backend)
        self.assertIn('反代服务的余额', backend)
        self.assertNotIn('输出1张2K图', retouch)
        self.assertIn('不标成2K', retouch)


if __name__ == '__main__':
    unittest.main()
