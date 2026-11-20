"""Interactive server setup. Secrets are hidden input and never command arguments."""
import getpass,os,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT);os.umask(0o077)
if (ROOT/'secrets/gemini_key').exists() or (ROOT/'.env').exists():raise SystemExit('配置已存在，请管理员手动维护；不会覆盖。')
subprocess.run(['docker','compose','version'],check=True)
domain=input('正式域名（不含 https:// 或路径）: ').strip()
if not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?',domain) or '.' not in domain:raise SystemExit('域名格式无效')
key=getpass.getpass('Gemini API 密钥（隐藏输入）: ').strip()
if not re.fullmatch(r'[A-Za-z0-9._-]{1,4095}',key):raise SystemExit('密钥格式无效')
user=input('共用登录账号: ').strip()
if not re.fullmatch(r'[A-Za-z0-9_-]{1,40}',user):raise SystemExit('账号只能含字母数字下划线横线')
password=getpass.getpass('登录密码（至少 12 位）: ')
if len(password)<12 or password!=getpass.getpass('再次输入密码: '):raise SystemExit('密码长度不足或不一致')
p=subprocess.run(['docker','run','--rm','-i','caddy:2.10.2-alpine','caddy','hash-password'],input=password+'\n',text=True,capture_output=True,check=True)
hash_=p.stdout.strip()
if not hash_.startswith('$2'):raise SystemExit('密码加密失败；未写入配置')
(ROOT/'secrets').mkdir(mode=0o700,exist_ok=True)
(ROOT/'secrets/gemini_key').write_text(key+'\n');(ROOT/'secrets/access').write_text(user+' '+hash_+'\n');(ROOT/'.env').write_text('DOMAIN='+domain+'\n')
print('配置已保存。运行 docker compose up -d --build，然后 docker compose ps。')
