"""Restore trusted backup into EMPTY volumes only; never follow archive links."""
import sys,tarfile
from pathlib import Path,PurePosixPath
roots={'module-two-candidate/bridge-jobs':Path('/app/module-two-candidate/bridge-jobs'),'module-two-candidate/live-attempts':Path('/app/module-two-candidate/live-attempts'),'module-three/data':Path('/app/module-three/data'),'product-retouch/data':Path('/app/product-retouch/data'),'usage':Path('/data')}
for dest in roots.values():
 dest.mkdir(parents=True,exist_ok=True)
 if any(dest.iterdir()):raise SystemExit('目标卷不为空；请使用独立空数据卷，禁止覆盖现有记录。')
with tarfile.open(fileobj=sys.stdin.buffer,mode='r|gz') as tar:
 for member in tar:
  p=PurePosixPath(member.name)
  if p.is_absolute() or '..' in p.parts or member.issym() or member.islnk() or not (member.isfile() or member.isdir()):raise SystemExit('不安全的备份条目')
  prefix=next((k for k in roots if member.name==k or member.name.startswith(k+'/')),None)
  if prefix is None:raise SystemExit('备份包含未知路径')
  dest=roots[prefix]/member.name[len(prefix):].lstrip('/')
  if member.isdir():dest.mkdir(parents=True,exist_ok=True,mode=0o700)
  else:
   dest.parent.mkdir(parents=True,exist_ok=True,mode=0o700)
   with tar.extractfile(member) as src,dest.open('xb') as out:
    while chunk:=src.read(1024*1024):out.write(chunk)
   dest.chmod(0o600)
print('恢复完成。启动服务后核对图片、记录与用量。')
