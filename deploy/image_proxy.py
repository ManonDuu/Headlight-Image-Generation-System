"""OpenAI-compatible image proxy client for the car-light proxy edition.

One POST, no redirects, no retries, no remote URL fetch. The API key is read
from the config file inside this process and is never printed.
"""
import argparse
import base64
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

# Long edge used only to build a distinct request size for each selected ratio.
# 1008 and the 16-pixel grid come from a previously measured acceptance of
# 800x1008 for a near-4:5 request. This process has not called the live proxy.
RATIO_LONG_EDGE = 1008
RATIO_TOLERANCE = 0.025
LOOPBACK = {'127.0.0.1', 'localhost', '::1'}
KEY_RE = re.compile(r'[A-Za-z0-9._~+/=-]{1,4096}\Z')
MODEL_RE = re.compile(r'[A-Za-z0-9._:/-]{1,200}\Z')
MODULES = {'reference', 'replacement', 'listing', 'retouch'}


class ProxyError(RuntimeError):
    def __init__(self, message, diagnostic=None):
        super().__init__(message)
        self.diagnostic = diagnostic if isinstance(diagnostic, dict) else {}


def public_diagnostic(status=None, kind=None, base=None):
    """Only integers and known endpoint names. Never copy messages, prompts, or keys."""
    out = {'retries': 0, 'outputVerified2K': False, 'attempts': 1}
    if isinstance(base, dict):
        if type(base.get('httpStatus')) is int:
            status = base['httpStatus']
        if base.get('endpointKind') in ('edits', 'generations'):
            kind = base['endpointKind']
    if type(status) is int and status > 0:
        out['httpStatus'] = status
    if kind in ('edits', 'generations'):
        out['endpointKind'] = kind
    return out


def usable_key(key):
    return isinstance(key, str) and bool(key) and key.strip() == key and not any(ch.isspace() for ch in key)


class Config:
    def __init__(self, base_url, api_key, model, path, sizes):
        self.base_url = base_url
        self.api_key = api_key
        self.model = model
        self.path = path
        self.sizes = sizes


def _fail(message):
    raise ProxyError(message)


def validate_base_url(value):
    if not isinstance(value, str) or not value or any(c in value for c in ' \t\r\n'):
        _fail('baseUrl 无效。本机只允许 http://127.0.0.1、localhost 或 ::1；其他地址必须是 https，且不能含空白。')
    parts = urlsplit(value)
    if parts.username or parts.password or parts.query or parts.fragment:
        _fail('baseUrl 不能包含账号、查询参数或片段。')
    host = parts.hostname
    if host is None or parts.scheme not in ('http', 'https'):
        _fail('baseUrl 只接受 http 或 https。')
    if parts.scheme == 'http' and host not in LOOPBACK:
        _fail('非本机地址必须使用 https。本机 http 只允许 127.0.0.1、localhost 或 ::1，不能改用局域网地址。')
    if parts.scheme == 'https' and not re.fullmatch(r'[A-Za-z0-9.-]+', host) and host not in LOOPBACK:
        _fail('https 主机名无效。')
    try:
        port = parts.port
    except ValueError:
        _fail('baseUrl 端口无效。')
    if port is not None and not 1 <= port <= 65535:
        _fail('baseUrl 端口无效。')
    path = parts.path or ''
    if '\\' in value or '//' in path or '..' in path.split('/'):
        _fail('baseUrl 路径无效。')
    return value.rstrip('/')


def load_config(path):
    file = Path(path)
    if not file.is_file():
        _fail('找不到反代配置文件。请按 deploy/image-proxy.example.json 复制一份并填写，不要把密钥提交到 git。')
    try:
        data = json.loads(file.read_text())
    except (OSError, ValueError):
        _fail('反代配置不是可读的 JSON 对象。')
    if not isinstance(data, dict):
        _fail('反代配置必须是 JSON 对象。')
    key = data.get('apiKey')
    model = data.get('model')
    if not isinstance(key, str) or not KEY_RE.fullmatch(key):
        _fail('apiKey 为空或格式无效。密钥不能含空白、换行或控制字符。未输出密钥。')
    if not isinstance(model, str) or not MODEL_RE.fullmatch(model):
        _fail('model 为空或格式无效。模板里的 gpt-image-2.6 只是示例，不保证可用；请填写检测结果中的 id。')
    return Config(validate_base_url(data.get('baseUrl')), key, model, str(file), parse_sizes(data.get('sizes')))


def round16(value):
    return max(16, int(round(value / 16.0)) * 16)


def size_for_ratio(ratio, long_edge=RATIO_LONG_EDGE):
    match = re.fullmatch(r'(\d+):(\d+)', ratio or '')
    if not match:
        return None
    width_part, height_part = int(match.group(1)), int(match.group(2))
    if width_part < 1 or height_part < 1:
        return None
    long_edge = round16(long_edge)
    if width_part >= height_part:
        width, height = long_edge, round16(long_edge * height_part / width_part)
    else:
        height, width = long_edge, round16(long_edge * width_part / height_part)
    return f'{width}x{height}'


def default_sizes():
    ratios = ('1:1', '4:5', '5:4', '3:4', '4:3', '9:16', '16:9', '2:3', '3:2', '12:15')
    return {ratio: size_for_ratio(ratio) for ratio in ratios}


def _ratio_error(ratio, width, height):
    width_part, height_part = (int(part) for part in ratio.split(':'))
    return abs((width / height) - (width_part / height_part)) / (width_part / height_part)


def parse_sizes(raw):
    if raw is None:
        return {}
    if not isinstance(raw, dict):
        _fail('sizes 必须是「比例: 宽x高」对象。未调用模型。')
    parsed = {}
    for ratio, value in raw.items():
        if not isinstance(ratio, str) or size_for_ratio(ratio) is None:
            _fail('sizes 含有无法识别的比例。未调用模型。')
        if not isinstance(value, str) or not re.fullmatch(r'\d+x\d+', value):
            _fail('sizes 的每一项都必须是宽x高。未调用模型。')
        width, height = (int(part) for part in value.split('x'))
        if width < 16 or height < 16 or width % 16 or height % 16:
            _fail('请求尺寸的宽和高都必须是 16 的正倍数。这只沿用先前测过的约束，不是对本机反代的新实测。')
        if _ratio_error(ratio, width, height) > RATIO_TOLERANCE:
            _fail(f'{ratio} 不能改成 {value}：偏离原比例过多。不会用另一个比例的尺寸代替。')
        parsed[ratio] = value
    return parsed


def request_size(ratio, sizes=None):
    """One distinct request size per selected ratio. Not a claim about returned pixels."""
    table = default_sizes()
    if sizes:
        table.update(sizes)
    if not isinstance(ratio, str) or not ratio:
        return None
    if ratio in table:
        return table[ratio]
    return size_for_ratio(ratio)


def _decode_image(mime, blob):
    if mime == 'image/png' and blob.startswith(b'\x89PNG\r\n\x1a\n'):
        return mime, blob
    if mime == 'image/jpeg' and blob.startswith(b'\xff\xd8\xff'):
        return mime, blob
    if mime == 'image/webp' or (len(blob) >= 12 and blob[:4] == b'RIFF' and blob[8:12] == b'WEBP'):
        from io import BytesIO
        from PIL import Image
        try:
            image = Image.open(BytesIO(blob))
            image.load()
            out = BytesIO()
            image.save(out, format='PNG')
            data = out.getvalue()
        except Exception:
            _fail('WebP 无法真正解码为 PNG，已停止。不能只修改 MIME。')
        if not data.startswith(b'\x89PNG\r\n\x1a\n'):
            _fail('WebP 转换结果不是 PNG，已停止。')
        return 'image/png', data
    _fail('参考图必须是 PNG、JPEG，或可真正转换为 PNG 的 WebP。')


def translate(body, sizes=None):
    if isinstance(body, (bytes, bytearray)):
        try:
            body = json.loads(body)
        except ValueError:
            _fail('冻结的生图请求无法读取，未调用模型。')
    parts = (((body or {}).get('contents') or [{}])[0].get('parts')) or []
    texts, images = [], []
    for part in parts:
        if not isinstance(part, dict):
            continue
        if isinstance(part.get('text'), str):
            texts.append(part['text'])
        inline = part.get('inlineData')
        if isinstance(inline, dict) and isinstance(inline.get('data'), str):
            try:
                raw = base64.b64decode(inline['data'], validate=True)
            except (ValueError, TypeError):
                _fail('参考图编码无效，未调用模型。')
            images.append(_decode_image(inline.get('mimeType') or '', raw))
    if not texts:
        _fail('生图请求缺少提示词，未调用模型。')
    ratio = ((body.get('generationConfig') or {}).get('imageConfig') or {}).get('aspectRatio')
    prompt = '\n'.join(texts)
    if isinstance(ratio, str) and ratio and not re.search(rf'(?<!\d){re.escape(ratio)}(?!\d)', prompt):
        prompt += f'\nRequested aspect ratio: {ratio}.'
    return {'prompt': prompt, 'images': images, 'size': request_size(ratio, sizes), 'ratio': ratio,
            'kind': 'edits' if images else 'generations'}


def _endpoint(config, kind):
    return config.base_url + ('/images/edits' if kind == 'edits' else '/images/generations')


def _multipart(config, spec):
    boundary = '----carlight' + secrets.token_hex(18)
    chunks = []

    def field(name, value):
        chunks.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())

    field('model', config.model)
    field('prompt', spec['prompt'])
    if spec['size']:
        field('size', spec['size'])
    for index, (mime, blob) in enumerate(spec['images'], 1):
        ext = 'png' if mime == 'image/png' else 'jpg'
        chunks.append(
            f'--{boundary}\r\nContent-Disposition: form-data; name="image[]"; filename="input-{index}.{ext}"\r\n'
            f'Content-Type: {mime}\r\n\r\n'.encode() + blob + b'\r\n')
    chunks.append(f'--{boundary}--\r\n'.encode())
    return boundary, b''.join(chunks)


def _json_body(config, spec):
    payload = {'model': config.model, 'prompt': spec['prompt']}
    if spec['size']:
        payload['size'] = spec['size']
    return json.dumps(payload).encode()


def _curl(config, url, header, body_path, timeout, connect_timeout):
    parts = urlsplit(config.base_url)
    command = [curl_binary(), '-q', '--silent', '--show-error', '--retry', '0',
               '--connect-timeout', str(connect_timeout), '--max-time', str(timeout),
               '--proto-redir', '-all', '--proto', '=http' if parts.scheme == 'http' else '=https',
               '--max-filesize', str(30 * 1024 * 1024), '--request', 'POST', '--header', '@-',
               '--data-binary', '@' + body_path, '--output', '-', '--write-out', '\n%{http_code}', url]
    if parts.hostname == 'localhost':
        port = parts.port or (80 if parts.scheme == 'http' else 443)
        command[1:1] = ['--resolve', f'localhost:{port}:127.0.0.1']
    try:
        result = subprocess.run(command, input=header, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout + 5)
    except subprocess.TimeoutExpired:
        _fail('等待模型响应超时；远端结果未知，未自动重试。')
    if result.returncode:
        if result.returncode == 28:
            _fail('等待模型响应超时；远端结果未知，未自动重试。')
        if result.returncode == 47:
            _fail('服务返回了跳转，已拒绝继续访问，未自动重试。')
        _fail('模型网络传输失败，结果未知，未自动重试。')
    raw = result.stdout
    marker = raw.rfind(b'\n')
    status = int(raw[marker + 1:] or b'0')
    return status, raw[:marker]


def _safety_message(raw):
    try:
        data = json.loads(raw)
    except ValueError:
        return None
    err = data.get('error') if isinstance(data, dict) else None
    text = ''
    if isinstance(err, dict):
        text = ' '.join(str(err.get(name) or '') for name in ('message', 'code', 'type'))
    elif isinstance(err, str):
        text = err
    low = text.lower()
    if any(word in low for word in ('moderation', 'safety', 'content_policy', 'blocked', 'image_safety')):
        return '内容未通过安全检查，已停止，未自动重试。'
    return None


def _http_error(status, raw):
    safety = _safety_message(raw)
    if safety:
        _fail(safety)
    if status in (301, 302, 303, 307, 308):
        _fail('服务返回了跳转，已拒绝继续访问，未自动重试。')
    if status == 401:
        _fail('模型密钥验证失败，未自动重试。')
    if status == 402:
        _fail('计费未通过（HTTP 402）。请检查反代服务的余额或计费状态；未自动重试。')
    if status == 403:
        _fail('模型访问被拒绝，未自动重试。')
    if status == 400:
        _fail('模型拒绝了请求参数，未自动重试。')
    if status == 429:
        _fail('模型限流或配额不足，未自动重试。')
    _fail(f'模型服务返回 HTTP {status}，未自动重试。')


def _parse_image(raw):
    try:
        data = json.loads(raw)
    except ValueError:
        _fail('模型响应不是完整图片结果，未自动重试。')
    if not isinstance(data, dict):
        _fail('模型响应不是完整图片结果，未自动重试。')
    items = data.get('data')
    if not isinstance(items, list):
        _fail('模型响应没有图片数据，未自动重试。')
    inline = [item.get('b64_json') for item in items if isinstance(item, dict) and item.get('b64_json')]
    linked = [item.get('url') for item in items if isinstance(item, dict) and item.get('url')]
    if linked and len(inline) != 1:
        _fail('结果只有图片地址，已拒绝下载，未自动重试。')
    if len(inline) != 1:
        _fail('模型未返回恰好一张图片，未自动重试。')
    try:
        blob = base64.b64decode(inline[0], validate=True)
    except (ValueError, TypeError):
        _fail('图片数据无法解码，未自动重试。')
    if blob.startswith(b'\x89PNG\r\n\x1a\n'):
        mime = 'image/png'
    elif blob.startswith(b'\xff\xd8\xff'):
        mime = 'image/jpeg'
    else:
        _fail('返回的不是 PNG 或 JPEG 原图，未自动重试。')
    if not 0 < len(blob) <= 20 * 1024 * 1024:
        _fail('返回图片大小无效，未自动重试。')
    from io import BytesIO
    from PIL import Image
    try:
        image = Image.open(BytesIO(blob))
        image.load()
        width, height = image.size
    except Exception:
        _fail('返回图片无法解码，未自动重试。')
    if width < 1 or height < 1:
        _fail('返回图片尺寸无效，未自动重试。')
    return blob, mime, width, height


def curl_binary():
    found = shutil.which('curl')
    if found:
        return found
    if os.path.isfile('/usr/bin/curl'):
        return '/usr/bin/curl'
    _fail('找不到 curl，未调用模型。')


def execute(config, gemini_body, module, timeout=180, connect_timeout=15):
    if module not in MODULES:
        _fail('用量模块无效，未调用模型。')
    # Read the key once. Never clear the shared Config: modules 03 and 04 reuse it.
    key = config.api_key
    if not usable_key(key):
        _fail('反代密钥不可用，未调用模型。')
    spec = None
    status, raw = 0, b''
    ident = None
    try:
        spec = translate(gemini_body, config.sizes)
        if spec['kind'] == 'edits':
            boundary, payload = _multipart(config, spec)
            header = f'Expect:\nAuthorization: Bearer {key}\nContent-Type: multipart/form-data; boundary={boundary}\n'.encode()
        else:
            payload = _json_body(config, spec)
            header = f'Expect:\nAuthorization: Bearer {key}\nContent-Type: application/json\n'.encode()
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import meter
        ident = meter.reserve(module, config.model, payload)
        with tempfile.TemporaryDirectory(prefix='image-proxy-') as folder:
            body_path = Path(folder) / 'body'
            body_path.write_bytes(payload)
            body_path.chmod(0o600)
            status, raw = _curl(config, _endpoint(config, spec['kind']), header, str(body_path), timeout, connect_timeout)
        if status != 200:
            _http_error(status, raw)
        blob, mime, width, height = _parse_image(raw)
        diagnostic = public_diagnostic(status, spec['kind'])
        diagnostic.update({'actualDimensions': [width, height], 'requestedSize': spec['size'], 'usageRecordId': ident})
        return {'bytes': blob, 'mime': mime, 'usage': {}, 'diagnostic': diagnostic}
    except ProxyError as exc:
        kind = spec['kind'] if isinstance(spec, dict) else None
        exc.diagnostic = public_diagnostic(status, kind, getattr(exc, 'diagnostic', None))
        raise
    finally:
        key = None
        if ident is not None:
            try:
                import meter
                # Success responses may be parsed for numeric usage only. Error bodies are not stored.
                stored = raw if status == 200 and raw[:1] in (b'{', b'[') else b''
                meter.finish(ident, status, stored)
            except Exception:
                pass


def public_summary(config):
    return {'ok': True, 'model': config.model, 'baseUrl': config.base_url}


def detect_models(config, timeout=20):
    """GET {base}/models once. Never calls an image generation endpoint."""
    if not usable_key(config.api_key):
        _fail('反代密钥不可用，未调用模型。')
    url = config.base_url + '/models'
    parts = urlsplit(config.base_url)
    command = [curl_binary(), '-q', '--silent', '--show-error', '--retry', '0', '--request', 'GET',
               '--connect-timeout', '10', '--max-time', str(timeout), '--proto-redir', '-all',
               '--proto', '=http' if parts.scheme == 'http' else '=https', '--header', '@-',
               '--output', '-', '--write-out', '\n%{http_code}', url]
    if parts.hostname == 'localhost':
        port = parts.port or (80 if parts.scheme == 'http' else 443)
        command[1:1] = ['--resolve', f'localhost:{port}:127.0.0.1']
    header = f'Authorization: Bearer {config.api_key}\r\n'.encode()
    result = subprocess.run(command, input=header, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout + 5)
    if result.returncode:
        _fail('模型列表读取失败，未调用生图。配置中的 model 不会被自动改写。')
    raw, _, status_raw = result.stdout.rpartition(b'\n')
    if int(status_raw or b'0') == 404:
        _fail('这个反代没有模型列表接口。请自行确认 model。示例 gpt-image-2.6 不保证可用，未调用生图。')
    if int(status_raw or b'0') != 200:
        _fail('模型列表读取失败，未调用生图。配置中的 model 不会被自动改写。')
    try:
        data = json.loads(raw)
    except ValueError:
        _fail('模型列表不是 JSON，未调用生图。')
    rows = data.get('data') if isinstance(data, dict) else None
    if rows is None and isinstance(data, dict):
        rows = data.get('models')
    names = []
    for row in rows or []:
        if isinstance(row, dict) and isinstance(row.get('id'), str):
            names.append(row['id'])
        elif isinstance(row, str):
            names.append(row)
    return names


def main(argv):
    parser = argparse.ArgumentParser(description='image proxy helper')
    parser.add_argument('command', choices=('check', 'detect', 'send'))
    parser.add_argument('--config', required=True)
    parser.add_argument('--body')
    parser.add_argument('--out')
    parser.add_argument('--meta')
    parser.add_argument('--module')
    parser.add_argument('--timeout', type=int, default=180)
    parser.add_argument('--connect-timeout', type=int, default=15)
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        if args.command == 'check':
            print(json.dumps(public_summary(config), ensure_ascii=False))
            return 0
        if args.command == 'detect':
            print(json.dumps({'models': detect_models(config)}, ensure_ascii=False))
            return 0
        if not args.body or not args.out or not args.meta or not args.module:
            _fail('发送参数不完整，未调用模型。')
        result = execute(config, Path(args.body).read_bytes(), args.module, args.timeout, args.connect_timeout)
        Path(args.out).write_bytes(result['bytes'])
        meta = {k: v for k, v in result.items() if k != 'bytes'}
        meta.update({'outputMime': result['mime'], 'outputHash': __import__('hashlib').sha256(result['bytes']).hexdigest(),
                     'outputFilename': 'output.png' if result['mime'] == 'image/png' else 'output.jpg',
                     'state': 'generated-pending-review', 'visualAcceptance': 'not-evaluated',
                     'actualDimensions': result['diagnostic']['actualDimensions'], 'outputVerified2K': False})
        Path(args.meta).write_text(json.dumps(meta, ensure_ascii=False))
        return 0
    except ProxyError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]))
    except BrokenPipeError:
        sys.exit(1)
