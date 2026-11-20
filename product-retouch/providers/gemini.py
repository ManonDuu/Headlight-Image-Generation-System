"""Independent Gemini adapter. One request, no retries or fallback."""
import base64
import json
import os
import urllib.request
import urllib.error
import ssl
import socket
import sys
import time
from . import RenderResult
from .transport import post_once

def tls_context():
    context = ssl.create_default_context()
    if sys.platform == 'darwin':
        # Use the OS-managed CA bundle; keep hostname and chain verification on.
        context.load_verify_locations(cafile='/etc/ssl/cert.pem')
    return context

class GeminiProvider:
    name = 'gemini'
    model = 'gemini-3.1-flash-image'
    def __init__(self, key=None):
        self.key = key or os.environ.get('RETOUCH_API_KEY', '')
    @property
    def connected(self):
        return bool(self.key)
    def generate(self, request):
        started = time.monotonic()
        self.last_diagnostic = {'phase': 'preparing', 'elapsedSeconds': 0}
        if not self.key:
            raise RuntimeError('尚未配置精修模块专用 RETOUCH_API_KEY')
        parts = [
            {'text': request.prompt},
            {'text': 'IMAGE 1 — USER PRODUCT SOURCE: sole geometry, design and hue-family authority; material base depth follows the explicit resolved_color_target.'},
            {'inlineData': {'mimeType': request.mime, 'data': base64.b64encode(request.image).decode()}},
        ]
        body = {'contents': [{'role': 'user', 'parts': parts}],
            'generationConfig': {'candidateCount': 1, 'responseModalities': ['IMAGE'],
                                 'maxOutputTokens': 4096,
                                 'thinkingConfig': {'thinkingLevel': 'MINIMAL'},
                                 'imageConfig': {'aspectRatio': request.ratio, 'imageSize': '2K'}}}
        endpoint = 'https://generativelanguage.googleapis.com/v1beta/models/' + self.model + ':generateContent'
        try:
            raw = post_once(endpoint, json.dumps(body).encode(), self.key, self.last_diagnostic)
            if len(raw) > 30 * 1024 * 1024:
                raise ValueError('response too large')
            self.last_diagnostic.update(phase='validating-response', responseBytes=len(raw))
            data = json.loads(raw)
            candidates = data.get('candidates', [])
            if len(candidates) != 1 or candidates[0].get('finishReason') != 'STOP':
                raise ValueError('incomplete response')
            parts = candidates[0].get('content', {}).get('parts', [])
            images = [p['inlineData'] for p in parts if 'inlineData' in p and not p.get('thought')]
            if len(images) != 1 or images[0].get('mimeType') not in ('image/png', 'image/jpeg'):
                raise ValueError('invalid image result')
            blob = base64.b64decode(images[0]['data'], validate=True)
            mime = images[0]['mimeType']
            if len(blob) > 20*1024*1024 or not blob.startswith(b'\x89PNG' if mime == 'image/png' else b'\xff\xd8\xff'):
                raise ValueError('invalid image bytes')
            self.last_diagnostic['phase'] = 'completed'
            return RenderResult(blob, mime, data.get('usageMetadata', {}))
        except RuntimeError:
            raise
        except urllib.error.HTTPError as exc:
            self.last_diagnostic['httpStatus'] = exc.code
            messages = {400: '模型拒绝请求参数', 401: '模型密钥验证失败',
                        403: '模型访问被拒绝，请检查密钥权限或网络地区',
                        404: '当前模型地址不可用', 429: '模型配额不足或请求限流'}
            detail = messages.get(exc.code, '模型服务返回错误')
            raise RuntimeError(f'{detail}（HTTP {exc.code}）。已停止，未自动重试。') from None
        except urllib.error.URLError as exc:
            reason = exc.reason
            if isinstance(reason, ssl.SSLCertVerificationError):
                detail = 'Python 无法验证模型服务的 HTTPS 证书'
            elif isinstance(reason, socket.gaierror):
                detail = '无法解析模型服务地址，请检查网络或代理'
            elif isinstance(reason, (socket.timeout, TimeoutError)):
                detail = '连接模型服务超时，远端结果未知，该次请求可能已计费'
            else:
                detail = '无法连接模型服务，请检查网络或代理设置'
            raise RuntimeError(detail + '。已停止，未自动重试。') from None
        except (socket.timeout, TimeoutError):
            raise RuntimeError('等待模型响应超时，远端结果未知，该次请求可能已计费；未自动重试。') from None
        except Exception:
            raise RuntimeError('模型响应未包含完整有效图片，已停止且未自动重试；该次请求可能已计费。') from None

        finally:
            self.last_diagnostic['elapsedSeconds'] = round(time.monotonic()-started, 3)
