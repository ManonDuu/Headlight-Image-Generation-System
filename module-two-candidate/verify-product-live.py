"""Explicit bounded production-path smoke test: two images, no retries."""
import base64
import hashlib
import json
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parent
URL = 'http://127.0.0.1:8774'
REPORT = ROOT / 'product-live-validation.json'

def request(path, data=None, token=None):
    headers = {'Origin': URL, 'Content-Type': 'application/json'}
    if token:
        headers['X-Session-Token'] = token
    req = urllib.request.Request(URL + path, data=None if data is None else json.dumps(data).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.load(r)

def save(report):
    temporary = REPORT.with_suffix('.tmp')
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2))
    temporary.replace(REPORT)

def main():
    if REPORT.exists():
        raise RuntimeError('已有验证记录；为防重复计费，本入口不会再次提交。请检查 product-live-validation.json。')
    s = request('/api/session')
    from importlib.util import spec_from_file_location, module_from_spec
    spec = spec_from_file_location('launcher', ROOT / 'workbench-launch.py')
    launcher = module_from_spec(spec)
    spec.loader.exec_module(launcher)
    if not launcher.compatible(s) or s.get('paidRequestsPaused'):
        raise RuntimeError('服务版本不符或生成已暂停，未提交请求。')
    token = s['token']
    materials = ROOT.parent / '测试素材'
    ref = (materials / '2.png').read_bytes()
    product = (materials / '产品图.png').read_bytes()
    report = {'status': 'started', 'maxImages': 2, 'maxBudgetMicroUSD': 540000,
              'automaticRetries': 0, 'visualAcceptance': 'not-evaluated', 'tasks': []}
    save(report)
    for layout in ('keep-reference', 'auto-layout'):
        options = {'businessSpec': launcher.PRODUCT_SPEC, 'module': 'product-replacement',
                   'mode': 'ai-rewrite', 'layoutMode': layout, 'layoutTone': 'adjust-color', 'color': '#C62828',
                   'productName': 'LED car bulbs', 'sceneMode': 'change',
                   'output': {'aspectRatio': '1:1', 'imageSize': '2K'}, 'budgetMicroUSD': 270000,
                   'imageBase64': base64.b64encode(ref).decode(), 'sourceHash': hashlib.sha256(ref).hexdigest(),
                   'productImageBase64': base64.b64encode(product).decode(), 'productHash': hashlib.sha256(product).hexdigest()}
        task = request('/api/freeze', options, token)
        entry = {'layout': layout, 'id': task['id'], 'requestHash': task['requestHash'], 'state': 'submission-reserved'}
        report['tasks'].append(entry)
        save(report)  # Reserve before sending; ambiguity must never cause a retry.
        request('/api/generic/generate', {'id': task['id'], 'requestHash': task['requestHash']}, token)
        deadline = time.monotonic() + 220
        while time.monotonic() < deadline:
            task = request('/api/task/' + task['id'], token=token)
            if task['state'] != 'running':
                break
            time.sleep(1)
        entry['state'] = task['state']
        entry['outputHash'] = task.get('outputHash')
        entry['imagePath'] = str(ROOT / 'bridge-jobs' / task['id'] / task.get('outputFilename', 'output.jpg'))
        save(report)
        if task['state'] != 'generated-pending-review':
            raise RuntimeError('生成未完成；停止后续测试，不自动重试。')
    report['status'] = 'generated-pending-visual-review'
    save(report)
    print('两种排版均已返回图片；等待人工核对后才能冻结。')

if __name__ == '__main__':
    try:
        main()
    except Exception:
        print('验证停止：请检查本机服务及验证记录；未自动重试，未冻结版本。')
        raise SystemExit(1)
