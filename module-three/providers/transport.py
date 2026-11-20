"""One HTTPS POST via system curl, no redirects/retries; credentials via stdin."""
import json
import subprocess
import tempfile
import time
from pathlib import Path

LIMIT = 30 * 1024 * 1024
TRANSPORT_REVISION = "connect45-total240-v3"

def _post_once_unmetered(endpoint, body, key, diagnostic):
    with tempfile.TemporaryDirectory(prefix='retouch-request-') as folder:
        request = Path(folder) / 'request.json'
        response = Path(folder) / 'response.json'
        request.write_bytes(body)
        request.chmod(0o600)
        response.touch(mode=0o600)
        fields = 'httpStatus=%{http_code}\nconnectSeconds=%{time_connect}\ntlsSeconds=%{time_appconnect}\nfirstResponseSeconds=%{time_starttransfer}\ntotalSeconds=%{time_total}\nuploadedBytes=%{size_upload}\n' 
        command = ['/usr/bin/curl', '-q', '--silent', '--http1.1', '--retry', '0',
                   '--connect-timeout', '45', '--max-time', '240',
                   '--max-filesize', str(LIMIT), '--proto', '=https',
                   '--request', 'POST', '--header', '@-',
                   '--header', 'Content-Type: application/json',
                   '--data-binary', '@' + str(request),
                   '--output', str(response), '--write-out', fields, endpoint]
        diagnostic.update(transport='system-curl', phase='request-in-flight', retries=0)
        started=time.monotonic()
        diagnostic.update(transportRevision=TRANSPORT_REVISION,connectTimeoutSeconds=45,totalTimeoutSeconds=240)
        try:
            result = subprocess.run(command, input=('x-goog-api-key: ' + key + '\n').encode(),
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=250)
        except subprocess.TimeoutExpired:
            diagnostic.update(phase='transport-process-timeout',elapsedSeconds=round(time.monotonic()-started,3),responseBytes=response.stat().st_size)
            raise RuntimeError('模型传输进程超时，远端结果未知；未自动重试。') from None
        diagnostic.update(elapsedSeconds=round(time.monotonic()-started,3),responseBytes=response.stat().st_size,curlExitCode=result.returncode)
        raw_metrics=result.stdout.decode('utf-8',errors='replace')
        try:
            metrics=json.loads(raw_metrics) if raw_metrics.lstrip().startswith('{') else dict(line.split('=',1) for line in raw_metrics.splitlines() if '=' in line)
            for name in ('httpStatus','connectSeconds','tlsSeconds','firstResponseSeconds','totalSeconds','uploadedBytes'):
                value=metrics.get(name)
                if value is not None:
                    try:diagnostic[name]=int(value) if name=='httpStatus' else float(value)
                    except (TypeError,ValueError):pass
        except (ValueError,TypeError):pass
        if result.returncode:
            diagnostic['phase'] = 'transport-failed'
            if result.returncode == 18:
                raise RuntimeError('图片响应传输中断，未收到完整结果。请求已发出，远端结果与计费未知；未自动重试。')
            if result.returncode == 28:
                if diagnostic.get('tlsSeconds')==0 and diagnostic.get('uploadedBytes')==0:
                    diagnostic['phase']='connection-timeout'
                    raise RuntimeError('连接模型服务超时（45 秒内未完成安全连接），未上传生图请求体；请检查电脑网络或代理，未自动重试。')
                diagnostic['phase']='response-timeout'
                raise RuntimeError('等待模型响应或图片下载超时（最多 240 秒）；远端结果与计费未知，未自动重试。')
            if result.returncode == 6:
                raise RuntimeError('模型服务域名解析失败；未自动重试。')
            if result.returncode in (35, 60):
                raise RuntimeError('模型服务 TLS 连接或证书校验失败；未自动重试。')
            raise RuntimeError('模型网络传输失败（诊断码 %s），结果未知；未自动重试。' % result.returncode)
        status = diagnostic.get('httpStatus', 0)
        if status != 200:
            diagnostic['phase'] = 'http-error'
            if status == 402:
                diagnostic.update(phase='billing-rejected',failureCategory='billing',retryable=False)
                raise RuntimeError('Gemini 拒绝生图请求（HTTP 402：付款或计费状态异常）。请在 Google AI Studio 核对当前 API 密钥所属项目的预付余额和计费状态；未自动重试。')
            raise RuntimeError('模型服务返回 HTTP %s；请检查权限、配额或服务状态，未自动重试。' % status)
        with response.open('rb') as handle:
            raw = handle.read(LIMIT + 1)
        if len(raw) > LIMIT:
            raise RuntimeError('模型响应超过大小上限，未自动重试。')
        diagnostic.update(phase='response-received', responseBytes=len(raw))
        return raw


def post_once(endpoint, body, key, diagnostic):
    from meter import reserve, finish
    ident=reserve('listing',endpoint.split('/models/')[-1].split(':')[0],body)
    diagnostic['usageRecordId']=ident
    raw=b''
    try:
        raw=_post_once_unmetered(endpoint,body,key,diagnostic)
        return raw
    finally:
        try:finish(ident,diagnostic.get('httpStatus',0),raw)
        except Exception:diagnostic['usageWriteback']='failed-reservation-retained'
