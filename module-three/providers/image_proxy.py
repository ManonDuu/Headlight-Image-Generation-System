"""Listing-module adapter. Reuses the untouched Gemini prompt assembly, then sends it once."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'deploy'))
from image_proxy import ProxyError, execute, public_diagnostic

class ImageProxyProvider:
    name = 'image-proxy'

    def __init__(self, config):
        self.config = config
        self.model = config.model
        self.last_diagnostic = {}

    def capabilities(self):
        return {'provider': self.name, 'model': self.model, 'connected': True, 'liveEnabled': True}

    def generate(self, image_brief, assets, budget):
        import providers.gemini as gemini_mod
        from providers.gemini import GeminiProvider
        captured = {}
        original = gemini_mod.post_once

        def capture(_endpoint, body, _key, _diagnostic):
            captured['body'] = body
            raise RuntimeError('IMAGE_PROXY_CAPTURE')

        gemini_mod.post_once = capture
        try:
            GeminiProvider('proxy-placeholder').generate(image_brief, assets, budget)
        except RuntimeError as exc:
            if 'IMAGE_PROXY_CAPTURE' not in str(exc) or 'body' not in captured:
                raise
        finally:
            gemini_mod.post_once = original
        try:
            result = execute(self.config, captured['body'], 'listing', timeout=240, connect_timeout=45)
        except ProxyError as exc:
            error = RuntimeError(str(exc))
            error.diagnostic = public_diagnostic(base=getattr(exc, 'diagnostic', None))
            raise error from None
        self.last_diagnostic = result['diagnostic']
        return {'bytes': result['bytes'], 'mime': result['mime'], 'usage': result['usage'],
                'diagnostic': result['diagnostic']}
