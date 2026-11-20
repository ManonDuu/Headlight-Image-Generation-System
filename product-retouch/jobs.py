"""Module-owned durable tasks. Only explicit generate starts one request."""
import base64
import hashlib
import json
import secrets
import threading
from datetime import datetime, timezone
from pathlib import Path
from rules import compile_prompt, VERSION
from providers import RenderRequest

def now():
    return datetime.now(timezone.utc).isoformat()

class Jobs:
    def __init__(self, root, provider):
        self.root = Path(root)
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.provider = provider
        self.lock = threading.Lock()
        for path in self.root.glob('*/state.json'):
            s = json.loads(path.read_text())
            if s['state'] == 'running':
                s.update(state='stopped', error='服务重启，前次结果未知；不会自动重试。')
                self.save(s)
    def folder(self, identifier):
        if len(identifier) != 24 or any(c not in '0123456789abcdef' for c in identifier):
            raise ValueError('任务ID无效')
        return self.root / identifier
    def save(self, s):
        path = self.folder(s['id']) / 'state.json'
        temp = path.with_suffix('.tmp')
        temp.write_text(json.dumps(s, ensure_ascii=False, indent=2))
        temp.replace(path)
    def read(self, identifier):
        return json.loads((self.folder(identifier) / 'state.json').read_text())
    def history(self):
        return sorted([json.loads(p.read_text()) for p in self.root.glob('*/state.json')], key=lambda s:s['createdAt'], reverse=True)
    def prepare(self, d):
        if set(d) - {'imageBase64','preset','ratio','colorMode','lightness'}:
            raise ValueError('不接受额外提示词或模型参数')
        encoded = d['imageBase64']
        if not isinstance(encoded, str) or len(encoded) > 5600000:
            raise ValueError('图片过大')
        image = base64.b64decode(encoded, validate=True)
        if len(image) > 4194304:
            raise ValueError('图片超过4MB')
        if image.startswith(b'\x89PNG\r\n\x1a\n'):
            mime='image/png'
        elif image.startswith(b'\xff\xd8\xff'):
            mime='image/jpeg'
        else:
            raise ValueError('仅支持JPEG/PNG')
        prompt=compile_prompt(d['preset'],d['ratio'],color_mode=d['colorMode'],lightness=d['lightness'])
        identifier=secrets.token_hex(12)
        folder=self.folder(identifier);folder.mkdir(mode=0o700)
        (folder/'source').write_bytes(image)
        (folder/'prompt.txt').write_text(prompt)
        s={'id':identifier,'state':'prepared','createdAt':now(),'rulesVersion':VERSION,
           'preset':d['preset'],'ratio':d['ratio'],'colorMode':d['colorMode'],
           'lightness':d['lightness'] if d['colorMode']=='lightness' else 0,'sourceMime':mime,'sourceHash':hashlib.sha256(image).hexdigest(),
           'promptHash':hashlib.sha256(prompt.encode()).hexdigest(),
           'pipeline':'source-only-surface-retouch','maxModelCalls':1,'modelCallsStarted':0,
           'provider':self.provider.name,'model':getattr(self.provider,'model',None),
           'visualAcceptance':'pending-user-review','retries':0}
        self.save(s);return s
    def generate(self, identifier):
        with self.lock:
            s=self.read(identifier)
            if s['state']!='prepared':
                raise ValueError('本任务已提交，不可重复生成')
            if s.get('rulesVersion') != VERSION:
                raise ValueError('精修规则已更新，请重新点击准备本次生成')
            if not getattr(self.provider,'connected',False):
                raise ValueError('尚未配置本模块的独立模型连接')
            if any(x['state']=='running' for x in self.history()):
                raise ValueError('已有任务生成中')
            folder=self.folder(identifier)
            image=(folder/'source').read_bytes();prompt=(folder/'prompt.txt').read_text()
            if hashlib.sha256(image).hexdigest()!=s['sourceHash'] or hashlib.sha256(prompt.encode()).hexdigest()!=s['promptHash']:
                raise ValueError('任务素材或规则已改变，请重新准备')
            s.update(state='running',startedAt=now());self.save(s)
            threading.Thread(target=self.run,args=(s,image,prompt),daemon=True).start()
            return s
    def run(self,s,image,prompt):
        try:
            s.update(stage='retouch',modelCallsStarted=1);self.save(s)
            result=self.provider.generate(RenderRequest(image,s['sourceMime'],prompt,s['ratio']))
            (self.folder(s['id'])/'output').write_bytes(result.image)
            s.update(state='completed',outputMime=result.mime,usage=result.usage,
                     outputHash=hashlib.sha256(result.image).hexdigest())
        except Exception as exc:
            s.update(state='stopped',error=str(exc))
        finally:
            diagnostic=getattr(self.provider,'last_diagnostic',None)
            if diagnostic is not None:
                s['transportDiagnostic']=dict(diagnostic)
            s['finishedAt']=now();self.save(s)
