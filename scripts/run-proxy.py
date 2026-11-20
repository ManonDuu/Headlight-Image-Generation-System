"""Start the proxy edition on loopback. This script is Linux-oriented.

It runs `ruby` and `nginx` from PATH, then the image client uses `curl` from
PATH. Those commands are present in the Docker image. They were not verified
on macOS or Windows. A stock Mac often has no nginx and no Ruby; Windows is
not a supported launch path. tesseract is not required to open the pages; the
existing preserve-original-text mode still needs it, on Linux as before.
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
(ROOT / 'data').mkdir(mode=0o700, exist_ok=True)
os.environ['IMAGE_PROXY_CONFIG'] = str(ROOT / 'secrets' / 'image-proxy.json')
os.environ['PUBLIC_ORIGIN'] = 'http://127.0.0.1:18080'
os.environ['LOCAL_LOOPBACK_HTTP'] = '1'
os.environ['PROXY_HTTP_LISTEN'] = '127.0.0.1:18080'
os.environ['USAGE_DB'] = str(ROOT / 'data' / 'usage.sqlite3')
os.environ['BUDGET_CONFIG'] = str(ROOT / 'deploy' / 'budget.json')
os.environ['SYSTEM_BUDGET'] = '1'
os.environ['PYTHONPATH'] = str(ROOT / 'deploy')
sys.path.insert(0, str(ROOT / 'deploy'))
from supervise import main

print('反代版只监听 http://127.0.0.1:18080 。不会占用原版 80/443，也不会把 62037 公开。', flush=True)
sys.exit(main())
