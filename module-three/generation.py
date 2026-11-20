"""Durable one-shot per-slot generation and conservative daily reservations."""
import re
import os
from copy import deepcopy
import hashlib
import json
import threading
from datetime import datetime,timezone
from zoneinfo import ZoneInfo
from core import LOCK,require
from variation_rules import REVISION

class Generation:
 def __init__(self,store,provider):
  self.store=store;self.provider=provider
  for item in store.list():
   r=store.get(item['id']);changed=False
   for t in r.get('generation',{}).get('images',[]):
    if t['state']=='running':t.update(state='stopped',error='服务重启，前次结果未知；不会自动重试');changed=True
   if r.get('generation',{}).get('state')=='running':
    r['generation'].update(state='paused',error='服务重启，队列已暂停；未自动重发任何请求');changed=True
   if changed:store._write(store._path(r['id'])/'record.json',r)
 def budget_status(self,day=None):
  if os.environ.get("SYSTEM_BUDGET")=="1":
   from meter import budget_status
   return budget_status()
  day=day or datetime.now(timezone.utc).date().isoformat()
  with LOCK:
   overrides=self.store.root/'generation-budget-limits.json'
   limits=json.loads(overrides.read_text()) if overrides.exists() else {}
   limit=limits.get(day,10)
   require(type(limit) in (int,float) and 0<limit<10000,'预算设置无效')
   ledger=self.store.root/'generation-budget.json'
   used=json.loads(ledger.read_text()).get(day,0) if ledger.exists() else 0
   authorization=self.store.root/'generation-budget-authorization.json'
   a=json.loads(authorization.read_text()) if authorization.exists() else {}
   now=datetime.now(timezone.utc)
   unlimited=(a.get('unlimited') is True and a.get('timezone')=='America/Los_Angeles'
              and a.get('date')==now.astimezone(ZoneInfo('America/Los_Angeles')).date().isoformat()
              and day==now.date().isoformat())
   return {'day':day,'timezone':'UTC','limitUSD':None if unlimited else limit,'reservedUSD':used,
           'remainingUSD':None if unlimited else max(0,limit-used),'unlimited':unlimited,
           'authorizationDate':a.get('date') if unlimited else None,'authorizationTimezone':a.get('timezone') if unlimited else None}
 def start_set(self,ident):
  with LOCK:
   r=self.store.get(ident)
   # A saved task is a one-shot idempotency key, including lost HTTP responses.
   if r.get('generation',{}).get('state'):return r
   require(self.provider.capabilities()['connected'],'生图服务尚未连接；尚未提交')
   require(r['plan'].get('rulesRevision')==REVISION,'旧方案需重新组合后生成；尚未提交')
   require(not r.get('generation',{}).get('images'),'此任务已有提交记录，请查看结果；不会重新提交')
   for b in r['plan']['images']:
    require(not b['missingInformation'],f"第 {b['slot']} 张资料待补充："+'；'.join(b['missingInformation']))
   for item in self.store.list():
    g=self.store.get(item['id']).get('generation',{})
    require(g.get('state')!='running' and not any(t['state']=='running' for t in g.get('images',[])),'已有任务生成中，请在生成记录查看')
   r['generation']={'state':'running','acceptedAt':datetime.now(timezone.utc).isoformat(),'images':[]}
   self.store._write(self.store._path(ident)/'record.json',r)
   try:threading.Thread(target=self.run_set,args=(ident,),daemon=True).start()
   except Exception:
    r['generation'].update(state='paused',error='队列未能启动，未提交模型请求')
    self.store._write(self.store._path(ident)/'record.json',r)
   return r
 def retry_set(self,ident,request_id):
  with LOCK:
   require(isinstance(request_id,str) and bool(re.fullmatch(r'[a-zA-Z0-9-]{16,80}',request_id)),'重试请求编号无效')
   r=self.store.get(ident);g=r.get('generation',{})
   if request_id in g.get('retryRequests',[]):return r
   require(g and g.get('state')!='running','任务未失败或仍在生成中')
   require(any(t['state']=='stopped' for t in g.get('images',[])) or g.get('state')=='paused','没有需要重试的图片')
   require(self.provider.capabilities()['connected'],'生图服务尚未连接')
   for item in self.store.list():
    other=self.store.get(item['id']).get('generation',{})
    require(other.get('state')!='running' and not any(t['state']=='running' for t in other.get('images',[])),'已有任务生成中，请等待完成')
   g.setdefault('retryRequests',[]).append(request_id)
   g.update(state='running',error=None)
   g.pop('finishedAt',None)
   self.store._write(self.store._path(ident)/'record.json',r)
   try:threading.Thread(target=self.run_set,args=(ident,True),daemon=True).start()
   except Exception:
    g.update(state='paused',error='重试队列未启动，未提交模型请求')
    self.store._write(self.store._path(ident)/'record.json',r)
   return r
 def run_set(self,ident,retry=False):
  try:
   r=self.store.get(ident)
   for b in r['plan']['images']:
    existing=next((t for t in self.store.get(ident)['generation']['images'] if t['slot']==b['slot']),None)
    if existing and existing['state']=='completed':continue
    self.start(ident,b['slot'],synchronous=True,retry=retry)
    r=self.store.get(ident)
    if next(t for t in r['generation']['images'] if t['slot']==b['slot'])['state']!='completed':
     raise RuntimeError('本张失败，整套已暂停；后续图片未提交，失败图片不会自动重试')
   state,error='completed',None
  except Exception as e:
   state,error='paused',str(e) if isinstance(e,(ValueError,RuntimeError)) else '队列已暂停，请查看各图状态'
  with LOCK:
   r=self.store.get(ident);r['generation'].update(state=state,error=error,pauseReason=('budget-limit' if error and '预算' in error else 'generation-stopped' if error else None),finishedAt=datetime.now(timezone.utc).isoformat())
   self.store._write(self.store._path(ident)/'record.json',r)
 def start(self,ident,slot,synchronous=False,retry=False):
  with LOCK:
   r=self.store.get(ident)
   require(type(slot)is int and 1<=slot<=r['plan']['count'],'图片序号无效')
   require(self.provider.capabilities()['connected'],'生图服务尚未连接')
   require(retry or r['plan'].get('rulesRevision')==REVISION,'旧方案需重新组合后生成')
   brief=r['plan']['images'][slot-1]
   require(not brief['missingInformation'],'请先补充或核对该图所需信息：'+'；'.join(brief['missingInformation']))
   for item in self.store.list():
    other=self.store.get(item['id']).get('generation',{})
    require(other.get('state')!='running' or (synchronous and item['id']==ident),'已有整套任务生成中')
    require(not any(t['state']=='running' for t in self.store.get(item['id']).get('generation',{}).get('images',[])),'已有图片生成中，请等待完成')
   require(synchronous or r.get('generation',{}).get('state')!='running','整套任务已接收，请勿重复提交')
   g=r.setdefault('generation',{'images':[]})
   previous=next((t for t in g['images'] if t['slot']==slot),None)
   require(previous is None or (retry and synchronous and previous['state']=='stopped'),'该图片已提交过，请使用重试按钮')
   assets=[]
   for aid in brief['assetIds']:
    meta=next(a for a in r['assets'] if a['id']==aid);blob=(self.store._path(ident)/meta['file']).read_bytes()
    require(hashlib.sha256(blob).hexdigest()==meta['sha256'],'原图校验失败')
    assets.append({'mime':meta['mime'],'bytes':blob})
   require(len(brief['prompt'].encode())<=64000 and len(assets)<=1,'输入超过单图预算范围')
   day=datetime.now(timezone.utc).date().isoformat()
   ledger=self.store.root/'generation-budget.json'
   budget=json.loads(ledger.read_text()) if ledger.exists() else {}
   used=budget.get(day,0)
   limit=self.budget_status(day)['limitUSD']
   if os.environ.get('SYSTEM_BUDGET')=='1':require(self.budget_status()['remainingUSD']>=0.5,'系统日/月预算不足，停止新请求')
   elif limit is not None:require(used+0.5<=limit,f'本模块今日预留预算已达 ${limit:g}，停止新请求')
   budget[day]=used+0.5;self.store._write(ledger,budget)
   history=deepcopy(previous.get('history',[])) if previous else []
   if previous:
    history.append({k:v for k,v in previous.items() if k!='history'})
    g['images'].remove(previous)
   g['images'].append({'history':history,'slot':slot,'state':'running','startedAt':datetime.now(timezone.utc).isoformat(),'reserveUSD':0.5,'model':self.provider.model,'attempts':(previous.get('attempts',1)+1 if previous else 1),'promptHash':hashlib.sha256(brief['prompt'].encode()).hexdigest()})
   self.store._write(self.store._path(ident)/'record.json',r)
   if not synchronous:
    threading.Thread(target=self.run,args=(ident,slot,brief,assets),daemon=True).start()
    return r
  self.run(ident,slot,brief,assets)
  return self.store.get(ident)
 def run(self,ident,slot,brief,assets):
  try:
   result=self.provider.generate(brief,assets,{'reserveUSD':0.5})
   filename=f'result-{slot}.'+('png' if result['mime']=='image/png' else 'jpg')
   (self.store._path(ident)/filename).write_bytes(result['bytes'])
   update={'state':'completed','file':filename,'mime':result['mime'],'usage':result['usage'],'diagnostic':result.get('diagnostic',{}),'visualAcceptance':'pending-user-review'}
  except Exception as e:
   update={'state':'stopped','error':str(e) if isinstance(e,RuntimeError) else '生成或保存失败，结果未知；未自动重试','diagnostic':getattr(e,'diagnostic',{}),'submission':'attempted-result-unknown'}
  with LOCK:
   r=self.store.get(ident);t=next(t for t in r['generation']['images'] if t['slot']==slot)
   t.update(update,finishedAt=datetime.now(timezone.utc).isoformat());self.store._write(self.store._path(ident)/'record.json',r)
