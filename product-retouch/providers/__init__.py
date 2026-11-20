"""Module-owned model adapters. No imports or credentials from other modules."""
from dataclasses import dataclass

@dataclass(frozen=True)
class RenderRequest:
    image: bytes
    mime: str
    prompt: str
    ratio: str
    size: str = '2K'

@dataclass(frozen=True)
class RenderResult:
    image: bytes
    mime: str
    usage: dict

class PreviewProvider:
    name = 'preview'
    def generate(self, request: RenderRequest):
        raise RuntimeError('页面预览阶段，尚未启用生图模型。')

def get_provider(name, key=None):
    if name == 'preview':
        return PreviewProvider()
    if name == 'gemini':
        from .gemini import GeminiProvider
        return GeminiProvider(key=key)
    raise ValueError('尚未配置该模块的独立模型适配器')
