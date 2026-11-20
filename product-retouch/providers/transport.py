"""One HTTPS POST via system curl, no redirects/retries; credentials via stdin."""
import json
import subprocess
import tempfile
from pathlib import Path

LIMIT = 30 * 1024 * 1024

def _post_once_unmetered(endpoint, body, key, diagnostic):
    with tempfile.TemporaryDirectory(prefix='retouch-request-') as folder:
        request = Path(folder) / 'request.json'
        response = Path(folder) / 'response.json'
        request.write_bytes(body)
        request.chmod(0o600)
        response.touch(mode=0o600)
        fields = '{"httpStatus":%{http_code},"connectSeconds":%{time_connect},"tlsSeconds":%{time_appconnect},"firstResponseSeconds":%{time_starttransfer},"totalSeconds":%{time_total}}'
        command = ['/usr/bin/curl', '-q', '--silent', '--retry', '0',
                   '--connect-timeout', '15', '--max-time', '180',
                   '--max-filesize', str(LIMIT), '--proto', '=https',
                   '--request', 'POST', '--header', '@-',
                   '--header', 'Content-Type: application/json',
                   '--data-binary', '@' + str(request),
                   '--output', str(response), '--write-out', fields, endpoint]
        diagnostic.update(transport='system-curl', phase='request-in-flight', retries=0)
        result = subprocess.run(command, input=('x-goog-api-key: ' + key + '\n').encode(),
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=190)
        diagnostic['curlExitCode'] = result.returncode
        try:
            metrics = json.loads(result.stdout)
            for name in ('httpStatus','connectSeconds','tlsSeconds','firstResponseSeconds','totalSeconds'):
                value = metrics.get(name)
                if type(value) in (int, float): diagnostic[name] = value
        except (ValueError, TypeError):
            pass
        if result.returncode:
            diagnostic['phase'] = 'transport-failed'
            if result.returncode == 28:
                raise RuntimeError('模型请求超时；远端结果未知，可能已计费，未自动重试。')
            if result.returncode == 6:
                raise RuntimeError('模型服务域名解析失败；未自动重试。')
            if result.returncode in (35, 60):
                raise RuntimeError('模型服务 TLS 连接或证书校验失败；未自动重试。')
            raise RuntimeError('模型网络传输失败（诊断码 %s），结果未知；未自动重试。' % result.returncode)
        status = diagnostic.get('httpStatus', 0)
        if status != 200:
            diagnostic['phase'] = 'http-error'
            raise RuntimeError('模型服务返回 HTTP %s；请检查权限、配额或服务状态，未自动重试。' % status)
        with response.open('rb') as handle:
            raw = handle.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise RuntimeError('模型响应超过大小上限，未自动重试。')
        diagnostic.update(phase='response-received', responseBytes=len(raw))
        return raw


def post_once(endpoint, body, key, diagnostic):
    from meter import reserve, finish
    ident=reserve('retouch',endpoint.split('/models/')[-1].split(':')[0],body)
    diagnostic['usageRecordId']=ident
    raw=b''
    try:
        raw=_post_once_unmetered(endpoint,body,key,diagnostic)
        return raw
    finally:
        try:finish(ident,diagnostic.get('httpStatus',0),raw)
        except Exception:diagnostic['usageWriteback']='failed-reservation-retained'
