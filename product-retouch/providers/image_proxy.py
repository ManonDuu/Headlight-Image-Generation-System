"""Retouch adapter. Reuses the untouched Gemini prompt assembly, then sends it once."""
import sys
from pathlib import Path
from . import RenderResult

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'deploy'))
from image_proxy import ProxyError, execute, public_diagnostic

class ImageProxyProvider:
    name = 'image-proxy'
    connected = True

    def __init__(self, config):
        self.config = config
        self.model = config.model
        self.last_diagnostic = {}

    def generate(self, request):
        from . import gemini as gemini_mod
        from .gemini import GeminiProvider
        captured = {}
        original = gemini_mod.post_once

        def capture(_endpoint, body, _key, _diagnostic):
            captured['body'] = body
            raise RuntimeError('IMAGE_PROXY_CAPTURE')

        gemini_mod.post_once = capture
        try:
            GeminiProvider('proxy-placeholder').generate(request)
        except RuntimeError as exc:
            if 'IMAGE_PROXY_CAPTURE' not in str(exc) or 'body' not in captured:
                raise
        finally:
            gemini_mod.post_once = original
        try:
            result = execute(self.config, captured['body'], 'retouch', timeout=180, connect_timeout=15)
        except ProxyError as exc:
            self.last_diagnostic = public_diagnostic(base=getattr(exc, 'diagnostic', None))
            raise RuntimeError(str(exc)) from None
        self.last_diagnostic = result['diagnostic']
        return RenderResult(result['bytes'], result['mime'], result['usage'])
