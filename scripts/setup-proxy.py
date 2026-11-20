"""Write the proxy config outside git. Never prints the key or touches Gemini secrets."""
import argparse
import getpass
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'deploy'))
from image_proxy import ProxyError, load_config

TARGET = ROOT / 'secrets' / 'image-proxy.json'
GEMINI = ROOT / 'secrets' / 'gemini_key'


def save_config(path, base_url, api_key, model):
    path = Path(path)
    if path.resolve() == GEMINI.resolve():
        raise ProxyError('不能把反代配置写到 Gemini 密钥文件。')
    path.parent.mkdir(mode=0o700, exist_ok=True)
    blob = json.dumps({'baseUrl': base_url, 'apiKey': api_key, 'model': model}, ensure_ascii=False, indent=2) + '\n'
    temp = path.with_suffix('.tmp')
    temp.write_text(blob)
    temp.chmod(0o600)
    temp.replace(path)
    os.chmod(path, 0o600)
    return load_config(path)


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description='配置车灯反代生图')
    parser.add_argument('--base-url')
    parser.add_argument('--model')
    parser.add_argument('--replace', action='store_true')
    args = parser.parse_args()
    if TARGET.exists() and not args.replace:
        raise SystemExit('反代配置已存在。确认要更换时再加 --replace。不会覆盖 Gemini 密钥。')
    base = args.base_url or input('反代 Base URL（本机示例 http://127.0.0.1:62037/v1）: ').strip()
    model = args.model or input('模型 id（可先填示例 gpt-image-2.6，检测后再改成列表里的 id）: ').strip()
    key = getpass.getpass('反代 API 密钥（隐藏输入，不会打印）: ').strip()
    try:
        cfg = save_config(TARGET, base, key, model)
    except ProxyError as exc:
        raise SystemExit(str(exc)) from None
    print(f'已写入 {TARGET}（权限 600）。模型 {cfg.model}，地址主机已接受。密钥未显示。')
    print('下一步：python3 scripts/detect-image-model.py，确认模型 id 后再 python3 scripts/run-proxy.py。')


if __name__ == '__main__':
    main()
