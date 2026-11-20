"""Live-service reads and preparation only. Never calls a generation route."""
import base64
import hashlib
import itertools
import json
import pathlib
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent
BASE = 'http://127.0.0.1:8773'
session = json.load(urllib.request.urlopen(BASE + '/api/session', timeout=5))
assert session['mock'] is False and session['referenceDaily']['enabled']
assert session['referenceDaily']['version'] == 'car-light-direct-20261021.15'
headers = {'Content-Type': 'application/json', 'X-Session-Token': session['token'], 'Origin': BASE}
checks = []
def check(name, value):
    assert value, name
    checks.append(name)
def request(path, data=None, authorized=True):
    h = headers if authorized else {'Content-Type': 'application/json', 'Origin': BASE}
    r = urllib.request.Request(BASE + path, headers=h, data=json.dumps(data).encode() if data is not None else None)
    try:
        with urllib.request.urlopen(r, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()

check('daily profile and budget exposed without secret', session['referenceDaily']['budgetMicroUSD'] == 260000 and 'key' not in session)
source = (ROOT.parent / 'reference-input-041629/source.png').read_bytes()
last = None
for mode, layout, tone in itertools.product(['custom', 'ai-rewrite', 'remove-all-copy'], ['keep-reference', 'auto-layout'], ['keep-reference', 'adjust-color']):
    d = {'businessSpec': session['referenceDaily']['version'], 'module': 'reference-reconstruction', 'mode': mode, 'layoutMode': layout, 'layoutTone': tone, 'output': {'aspectRatio': 'follow-reference', 'imageSize': '2K'}, 'imageBase64': base64.b64encode(source).decode(), 'sourceHash': hashlib.sha256(source).hexdigest(), 'budgetMicroUSD': 260000}
    if mode == 'custom':
        d['customCopy'] = 'mIxEd Road Copy\nLED'
    if tone == 'adjust-color':
        d['color'] = '#C62828'
    status, raw = request('/api/freeze', d)
    task = json.loads(raw)
    check('/'.join([mode, layout, tone]) + ' prepared', status == 200 and task.get('state') == 'frozen')
    check('source and options retained ' + task['id'], task['sourceHash'] == d['sourceHash'] and task['rawUserOptions']['mode'] == mode and task['rawUserOptions']['layoutMode'] == layout)
    if mode == 'custom':
        check('custom case preserved ' + task['id'], task['rawUserOptions']['customCopy'] == d['customCopy'])
    last = task

status, raw = request('/api/task/' + last['id'] + '/reference')
check('uploaded PNG bytes unchanged', status == 200 and hashlib.sha256(raw).hexdigest() == last['sourceHash'])
status, raw = request('/api/freeze', {}, authorized=False)
check('unauthenticated preparation blocked', status == 400)

clean = (ROOT.parent / 'generated_images/exec-c73edbb8-79d4-478c-85a2-941e4a0273e5.png').read_bytes()
d.update(mode='preserve-reference', layoutMode='keep-reference', layoutTone='keep-reference', imageBase64=base64.b64encode(clean).decode(), sourceHash=hashlib.sha256(clean).hexdigest())
d.pop('color', None)
status, raw = request('/api/freeze', d)
preserve = json.loads(raw)
native_ocr = status == 200 and preserve.get('state') == 'frozen'
if not native_ocr:
    check('OCR unavailable stops before generation', status == 400 and '文字提取不可用' in preserve.get('error', ''))
    d['referenceCopy'] = 'Brighter Road Visibility\nLED\nHalogen'
    status, raw = request('/api/freeze', d)
    preserve = json.loads(raw)
check('preserve mode prepared with OCR or user-checked transcript', status == 200 and preserve.get('state') == 'frozen')
check('preserve-mode prompt contains exact original copy', 'referenceCopy' in preserve['prompt'] and 'Brighter Road Visibility' in preserve['prompt'])

marker = json.loads((ROOT / 'bridge-jobs/accepted-gemini-reference-041629.json').read_text())
status, raw = request('/api/task/' + marker['id'])
accepted = json.loads(raw)
check('accepted Gemini history restored', status == 200 and accepted['userFeedback']['overallVisual'] == 'accepted-by-user')
status, raw = request('/api/task/' + marker['id'] + '/image')
check('real Gemini original download verified', status == 200 and hashlib.sha256(raw).hexdigest() == marker['outputHash'])
for path in ['/', '/bridge.js', '/business-ui.js', '/reference-inspired-ui.js', '/original-ui.js']:
    with urllib.request.urlopen(BASE + path, timeout=5) as response:
        body = response.read()
        check('served ' + path, response.status == 200 and bool(body))
        if path == '/':
            check('module renamed in served page', '参考图卖点重构' in body.decode())

report = {'passed': len(checks), 'checks': checks, 'paidCalls': 0, 'generationRouteCalls': 0, 'nativeOCR': 'passed' if native_ocr else 'unavailable; manual transcript fallback passed', 'browserNativeFileChooser': 'not exercised: browser control unavailable', 'liveService': BASE}
(ROOT / 'release-http-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
print(json.dumps(report, ensure_ascii=False))
