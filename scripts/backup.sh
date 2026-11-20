#!/bin/sh
# Run during maintenance only, after checking no generation is running.
set -eu
cd "$(dirname "$0")/.."
mkdir -p backups
chmod 700 backups
stamp=$(date -u +%Y%m%dT%H%M%SZ)
docker compose stop
trap 'docker compose up -d >/dev/null' EXIT HUP INT TERM
docker compose run --rm --no-deps -T --entrypoint python3 app - <<'PY' > "backups/data-$stamp.tar.gz"
import sys,tarfile
with tarfile.open(fileobj=sys.stdout.buffer,mode='w|gz') as t:
 for name in ['module-two-candidate/bridge-jobs','module-two-candidate/live-attempts','module-three/data','product-retouch/data']:
  t.add('/app/'+name,arcname=name)
 t.add('/data',arcname='usage')
PY
chmod 600 "backups/data-$stamp.tar.gz"
printf 'Backup saved: backups/data-%s.tar.gz\n' "$stamp"
