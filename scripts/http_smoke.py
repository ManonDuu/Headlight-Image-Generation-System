"""CI-only HTTP prepare/persistence checks. Never invokes a generation endpoint."""
import base64,hashlib,io,json,sys,urllib.request,urllib.error
from pathlib import Path
from PIL import Image
op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
def api(path,body=None,token=None):
 headers={'Content-Type':'application/json','Origin':'https://images.example.com'}
 if token:headers['X-Session-Token']=token
 request=urllib.request.Request('http://127.0.0.1:8080'+path,headers=headers,data=json.dumps(body).encode() if body is not None else None)
 with op.open(request,timeout=10) as response:return json.load(response)
for path in ['/', '/listing/', '/listing/app.js', '/listing/backend.js', '/retouch/', '/retouch/app.js']:
 with op.open('http://127.0.0.1:8080'+path,timeout=5) as r:assert r.status==200
for origin in ['https://evil.example','null']:
 try:op.open(urllib.request.Request('http://127.0.0.1:8080/api/session',headers={'Origin':origin}),timeout=5);raise AssertionError('bad origin accepted')
 except urllib.error.HTTPError as e:assert e.code==403
record=Path('/tmp/http-smoke-records.json')
if '--prepare' in sys.argv:
 def png(color):
  stream=io.BytesIO();Image.new('RGB',(800,400),color).save(stream,format='PNG');return stream.getvalue()
 source,product=png('white'),png('red');encoded=base64.b64encode(source).decode();token=api('/api/session')['token'];ids={}
 common={'mode':'ai-rewrite','layoutMode':'auto-layout','layoutTone':'adjust-color','color':'#ff6600','output':{'aspectRatio':'1:1','imageSize':'2K'},'imageBase64':encoded,'sourceHash':hashlib.sha256(source).hexdigest()}
 for mod,spec,budget in [('reference-reconstruction','car-light-direct-20261021.20',260000),('product-replacement','car-light-product-20261022.10',270000)]:
  body={**common,'module':mod,'businessSpec':spec,'budgetMicroUSD':budget}
  if mod=='product-replacement':body.update(productImageBase64=base64.b64encode(product).decode(),productHash=hashlib.sha256(product).hexdigest(),productName='LED car bulbs')
  result=api('/api/freeze',body,token);assert result['state']=='frozen';ids[mod]=result['id']
 plan={'count':2,'product':{'type':'mixed','configuration':'9005 × 2 high beam','fitment':'2010–2012 Example Truck','facts':'6500K; aluminum heat sink'},'style':{'ratio':'4:5','primaryColor':'#2563eb','titleCase':'upper-title'},'images':[{'pointId':'fitment'},{'pointId':'thermal'}]}
 ids['listing']=api('/listing/api/prepare',{'plan':plan,'uploads':[{'name':'fixture.png','base64':encoded}]})['id']
 token=api('/retouch/api/session')['token'];result=api('/retouch/api/prepare',{'imageBase64':encoded,'preset':'refined','ratio':'1:1','colorMode':'preserve','lightness':0},token);assert result['state']=='prepared';ids['retouch']=result['id'];record.write_text(json.dumps(ids))
 print('All four module HTTP upload/prepare routes passed; no paid calls.')
if '--verify' in sys.argv:
 ids=json.loads(record.read_text());token=api('/api/session')['token']
 for name in ['reference-reconstruction','product-replacement']:assert api('/api/task/'+ids[name],token=token)['state']=='frozen'
 assert api('/listing/api/tasks/'+ids['listing'])['id']==ids['listing']
 token=api('/retouch/api/session')['token'];assert api('/retouch/api/task/'+ids['retouch'],token=token)['state']=='prepared'
 print('All four module task records survived service restart; no paid calls.')
print('Pages, static routes and origin rejection passed; no paid calls.')
