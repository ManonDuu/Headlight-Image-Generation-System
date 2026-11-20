"""Read the proxy model list. Does not call image generation."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'deploy'))
from image_proxy import ProxyError, detect_models, load_config

path = ROOT / 'secrets' / 'image-proxy.json'
try:
    names = detect_models(load_config(path))
except ProxyError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(1)
print('反代报告的模型 id：')
for name in names:
    print(name)
print('请把要用的 id 写入 secrets/image-proxy.json 的 model。示例 gpt-image-2.6 不代表一定在列表中。未调用生图。')
