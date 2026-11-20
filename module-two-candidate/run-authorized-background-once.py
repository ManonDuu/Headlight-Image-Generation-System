"""Exact user authorization only. Does not disable the global paid pause."""
import base64, hashlib, json, os, pathlib, pwd, re, resource, subprocess, urllib.request
from datetime import datetime, timezone
ROOT = pathlib.Path(__file__).resolve().parent
WORK = ROOT / 'diagnostics/authorized-background-20261018'
LEDGER = ROOT / 'live-attempts/background-Sentinel_34ec2b52a6188191a6dae1af7ca8a24e'
REQUEST = '24cab91d7aa8306e2d75c89a3c5cfd859726a9a20aa41f4aa76739cdea641f41'
SOURCE = '28399cad8a8e136d5cad8dbd88bb3d46763448e73755beb45a083a8f0b261814'
ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent'
def now(): return datetime.now(timezone.utc).isoformat()
def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if LEDGER.exists(): raise RuntimeError('Single-use approval consumed; no retry.')
    if not (ROOT / 'LIVE-REQUESTS-PAUSED').is_file(): raise RuntimeError('Global pause must remain present.')
    body = (WORK / 'request.json').read_bytes()
    if hashlib.sha256(body).hexdigest() != REQUEST: raise RuntimeError('Frozen request mismatch.')
    data = json.loads(body); cfg = data['generationConfig']; parts = data['contents'][0]['parts']
    if cfg['responseModalities'] != ['IMAGE'] or cfg['imageConfig'] != {'aspectRatio':'4:5','imageSize':'2K'} or cfg['maxOutputTokens'] != 4096 or cfg['candidateCount'] != 1: raise RuntimeError('Frozen background contract changed.')
    if 'responseFormat' in cfg or len(parts) != 2: raise RuntimeError('Analysis or extra input forbidden.')
    if hashlib.sha256(base64.b64decode(parts[1]['inlineData']['data'], validate=True)).hexdigest() != SOURCE: raise RuntimeError('Original reference mismatch.')
    with urllib.request.urlopen('http://127.0.0.1:8773/api/session', timeout=3) as r: session = json.load(r)
    if session.get('applicationId') != 'PictureGenerate.LocalWorkbench' or session.get('mock') is not False or session.get('paidRequestsPaused') is not True: raise RuntimeError('Existing paused service not verified.')
    account = pwd.getpwuid(os.getuid()).pw_name
    keychain = str(pathlib.Path.home() / 'Library/Keychains/login.keychain-db')
    # Exact existing item, read-only. No creation, ACL changes or alternate sources.
    found = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', 'PictureGenerate.LocalWorkbench.Gemini', '-a', account, '-w', keychain], capture_output=True, timeout=60)
    if found.returncode: raise RuntimeError('Exact Keychain read denied/failed; no request dispatched.')
    secret = found.stdout.removesuffix(b'\n')
    if not re.fullmatch(rb'[A-Za-z0-9._-]{1,4095}', secret): raise RuntimeError('Unexpected credential format; no request.')
    LEDGER.mkdir(mode=0o700)  # Atomic single-use claim, before any network request.
    record = {'approval': 'Sentinel_34ec2b52a6188191a6dae1af7ca8a24e', 'requestHash': REQUEST, 'sourceHash': SOURCE, 'model': 'gemini-3.1-flash-image', 'maxRequests': 1, 'retries': 0, 'budgetMicroUSD': 260000, 'maxOutputTokens': 4096, 'imageCalls': 1, 'analysisCalls': 0, 'state': 'attempt-started', 'startedAt': now()}
    (LEDGER / 'receipt.json').write_text(json.dumps(record, indent=2))
    readfd, writefd = os.pipe(); os.write(writefd, b'x-goog-api-key: ' + secret + b'\n'); os.close(writefd)
    response_path = LEDGER / 'response.raw.json'
    env = dict(os.environ); env.pop('GEMINI_API_KEY', None)
    try:
        result = subprocess.run(['/usr/bin/curl', '-q', '--header', '@/dev/fd/' + str(readfd), '--silent', '--retry', '0', '--connect-timeout', '15', '--max-time', '180', '--proto', '=https', '--request', 'POST', '--header', 'Content-Type: application/json', '--data-binary', '@' + str(WORK / 'request.json'), '--output', str(response_path), '--write-out', '%{http_code}', ENDPOINT], pass_fds=(readfd,), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=190)
        record.update(curlExit=result.returncode, httpStatus=result.stdout.decode(errors='replace').strip(), state='response-received' if result.returncode == 0 else 'stopped-unknown')
    except Exception:
        record.update(state='stopped-unknown', error='Transport interrupted; remote outcome unknown; no retry.')
    finally:
        os.close(readfd)
        if response_path.exists():
            response_path.write_bytes(response_path.read_bytes().replace(secret, b'[REDACTED]'))
            record['responseHash'] = hashlib.sha256(response_path.read_bytes()).hexdigest()
        secret = None
        record.update(finishedAt=now(), globalPausePresent=(ROOT / 'LIVE-REQUESTS-PAUSED').is_file())
        (LEDGER / 'receipt.json').write_text(json.dumps(record, indent=2))
    print(json.dumps(record))
if __name__ == '__main__':
    try: main()
    except subprocess.TimeoutExpired:
        detail = {'state': 'preflight-blocked', 'action': 'read exact existing Keychain item', 'item': 'PictureGenerate.LocalWorkbench.Gemini', 'reason': 'Keychain read did not complete within 60 seconds', 'attemptClaimed': LEDGER.exists(), 'automaticRetry': False}
        (WORK / 'preflight-blocker.json').write_text(json.dumps(detail, indent=2))
        print(json.dumps(detail)); raise SystemExit(1)
    except RuntimeError as e: print(str(e)); raise SystemExit(1)
    except Exception: print('Preflight or local operation failed; inspect receipt; do not retry automatically.'); raise SystemExit(1)
