import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'deploy'))
from supervise import nginx_config
class DeploymentTests(unittest.TestCase):
 def test_origin_is_validated_before_rewrite(self):
  text=nginx_config('https://images.example.com')
  self.assertIn('"https://images.example.com" 1;',text)
  self.assertIn('if ($origin_ok = 0) { return 403; }',text)
  for p in (8774,8775,8776):self.assertIn(f'proxy_pass http://127.0.0.1:{p}/;',text)
 def test_configuration_injection_rejected(self):
  for v in ['http://x.com','https://x.com/a','https://x.com; bad','https://x.com\nmalicious']:
   with self.assertRaises(ValueError):nginx_config(v)
 def test_no_local_navigation_in_entry(self):
  root=Path(__file__).resolve().parents[1]
  html=(root/'module-two-candidate/bridge.html').read_text()
  self.assertIn('href="/listing/"',html);self.assertIn('href="/retouch/"',html)
  self.assertNotIn('http://127.0.0.1',html)
