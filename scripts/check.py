"""Offline gate. Never loads credentials or calls an image model."""
import ast,hashlib,json,os,re,subprocess,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT);sys.path.insert(0,str(ROOT/'deploy'))
# All copied rule files not explicitly adapted must still match original bytes.
baseline=json.loads((ROOT/'baseline/source-sha256.json').read_text())
patches=json.loads((ROOT/'baseline/adaptations.json').read_text())
for name,h in baseline.items():
 p=ROOT/name
 if name in patches['excluded']:continue
 assert p.is_file(),f'Missing: {name}'
 expected=patches['changed'].get(name,h)
 assert hashlib.sha256(p.read_bytes()).hexdigest()==expected,f'Unexpected drift: {name}'
for p in ROOT.rglob('*.py'):
 if '__pycache__' not in p.parts:ast.parse(p.read_text(),filename=str(p))
for p in ROOT.rglob('*'):
 if not p.is_file() or any(x in p.parts for x in ['.git','secrets','__pycache__','backups']):continue
 if p.suffix in ['.py','.rb','.js','.json','.md','.html','.txt','.yaml','.yml']:
  assert not re.search(rb'AIza[0-9A-Za-z_-]{30,}',p.read_bytes()),f'Credential pattern: {p}'
# Verify actual recursive Ruby requires, not just a declared dependency list.
subprocess.run(['ruby','-I','module-two-candidate','-e','require "bridge-server"; abort unless DirectImagePlan::SPEC=="car-light-direct-20261021.20" && DirectImagePlan::PRODUCT_SPEC=="car-light-product-20261022.10"'],check=True)
with tempfile.TemporaryDirectory() as tmp:
 os.environ['USAGE_DB']=str(Path(tmp)/'usage.sqlite3');os.environ['PYTHONPATH']=str(ROOT/'deploy')
 tests=unittest.defaultTestLoader.discover(str(ROOT/'tests'),pattern='test_*.py')
 if not unittest.TextTestRunner(verbosity=2).run(tests).wasSuccessful():raise SystemExit(1)
 # Run frozen listing tests. HTTP requires network permission; optional explicit skip for restricted local environments only.
 code="""import sys,unittest
sys.path.insert(0,'module-three')
s=unittest.defaultTestLoader.discover('module-three',pattern='test_*.py')
def flat(s):
 for t in s:
  if isinstance(t,unittest.TestSuite):yield from flat(t)
  else:yield t
items=list(flat(s))
if '--no-http' in sys.argv:
 print('HTTP test explicitly excluded in restricted local environment')
 items=[t for t in items if not t.id().startswith('test_generation_http.')]
r=unittest.TextTestRunner(verbosity=1).run(unittest.TestSuite(items));sys.exit(not r.wasSuccessful())
"""
 subprocess.run([sys.executable,'-c',code]+(['--no-http'] if '--no-http' in sys.argv else []),check=True,env=os.environ.copy())
print('Offline checks passed. This is NOT paid-generation or production acceptance.')
