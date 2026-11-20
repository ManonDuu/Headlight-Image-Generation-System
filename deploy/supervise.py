"""Start three loopback backends plus private nginx ingress. Any child failure stops all."""
import json,os,re,signal,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
children=[];stopping=False

def stop(*_):
    global stopping
    stopping=True

def start(cmd,cwd,boot=None):
    p=subprocess.Popen(cmd,cwd=cwd,stdin=subprocess.PIPE if boot is not None else subprocess.DEVNULL)
    children.append(p)
    if boot is not None:p.stdin.write(json.dumps(boot).encode());p.stdin.close()
    return p

def nginx_config(origin, allow_loopback_http=False, listen='8080'):
    if not re.fullmatch(r'(?:127\.0\.0\.1:)?[0-9]{2,5}', listen):raise ValueError('invalid listen address')
    local=re.fullmatch(r'http://127\.0\.0\.1:([0-9]{1,5})', origin)
    valid_local=allow_loopback_http and local and 1<=int(local.group(1))<=65535
    if not valid_local and not re.fullmatch(r'https://[a-zA-Z0-9.-]+(?::[0-9]{1,5})?',origin):raise ValueError('PUBLIC_ORIGIN must be HTTPS, or explicitly enabled loopback HTTP')
    locations=[]
    for prefix,port in [('/listing/',8775),('/retouch/',8776),('/',8774)]:
        locations.append(f'''location {prefix} {{
            proxy_pass http://127.0.0.1:{port}/;
            proxy_set_header Host 127.0.0.1:{port};
            proxy_set_header Origin http://127.0.0.1:{port};
            proxy_set_header Authorization "";
            proxy_set_header Connection "";
            proxy_http_version 1.1;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
            proxy_buffering off;
        }}''')
    return '''pid /tmp/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 256; }
http {
 access_log off;
 client_body_temp_path /tmp/nginx-client;
 proxy_temp_path /tmp/nginx-proxy;
 map $http_origin $origin_ok { default 0; "" 1; "ORIGIN" 1; }
 server {
  listen LISTEN;
  client_max_body_size 180m;
  client_body_timeout 60s;
  if ($origin_ok = 0) { return 403; }
  if ($http_sec_fetch_site = cross-site) { return 403; }
  location = /listing { return 308 /listing/; }
  location = /retouch { return 308 /retouch/; }
  LOCATIONS
 }
}
'''.replace('ORIGIN',origin).replace('LOCATIONS','\n'.join(locations)).replace('LISTEN',listen)

def main():
    os.umask(0o077)
    config_path=os.environ.get('IMAGE_PROXY_CONFIG','/run/secrets/image_proxy.json')
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from image_proxy import load_config
    cfg=load_config(config_path)
    from meter import config,connect
    config();connect().close()
    origin=os.environ['PUBLIC_ORIGIN']
    Path('/tmp/nginx.conf').write_text(nginx_config(origin, os.environ.get('LOCAL_LOOPBACK_HTTP')=='1', os.environ.get('PROXY_HTTP_LISTEN','8080')))
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    boot={'rulesVersion':'car-light-direct-20261021.20','imageProxy':{'configPath':config_path,'baseUrl':cfg.base_url,'model':cfg.model}}
    cfg=None
    start(['ruby','bridge-server.rb','--reference-daily-stdin','--product-daily','--port','8774'],ROOT/'module-two-candidate',boot)
    start([sys.executable,'server.py','--credential-stdin'],ROOT/'module-three',boot)
    start([sys.executable,'server.py','--credential-stdin'],ROOT/'product-retouch',boot)
    start(['nginx','-c','/tmp/nginx.conf','-g','daemon off;'],ROOT)
    while not stopping and all(p.poll() is None for p in children):time.sleep(.5)
    failed=any(p.poll() not in (None,0) for p in children)
    for p in children:
        if p.poll() is None:p.terminate()
    deadline=time.monotonic()+20
    for p in children:
        try:p.wait(timeout=max(.1,deadline-time.monotonic()))
        except subprocess.TimeoutExpired:p.kill();p.wait()
    return 1 if failed or not stopping else 0

if __name__=='__main__':
    try:sys.exit(main())
    except Exception as exc:
        for p in children:
            if p.poll() is None:p.terminate()
        print(str(exc) if exc.__class__.__name__=='ProxyError' else '启动失败；请检查配置、密钥文件和持久化目录。未输出密钥。',file=sys.stderr);sys.exit(1)
