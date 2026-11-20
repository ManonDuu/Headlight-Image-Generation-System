import json,os,sys,urllib.request
op=urllib.request.build_opener(urllib.request.ProxyHandler({}))
listen=os.environ.get('PROXY_HTTP_LISTEN','8080')
base='http://127.0.0.1:'+listen.rsplit(':',1)[-1]
try:
    for path,field,value in [('/api/session','applicationId','PictureGenerate.LocalWorkbench'),('/listing/api/capabilities','rulesRevision','E31-all-category-trace-audit-20261026'),('/retouch/api/session','rulesVersion','retouch-rules-20261023.35')]:
        with op.open(base+path,timeout=3) as r:d=json.load(r)
        assert d[field]==value
        if field=='applicationId':
            assert d['referenceDaily']['version']=='car-light-direct-20261021.20'
            assert d['productDaily']['version']=='car-light-product-20261022.10'
except Exception:sys.exit(1)
