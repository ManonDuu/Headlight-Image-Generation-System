"""User-run launcher. No API calls, secret files, or credential discovery."""
import os
import pwd
import re
import resource
import socket
import subprocess
import sys
import json
import urllib.request
from pathlib import Path

SERVICE = 'PictureGenerate.LocalWorkbench.Gemini'
SECURITY = '/usr/bin/security'

def credential(run=subprocess.run):
    account = pwd.getpwuid(os.getuid()).pw_name
    expected = Path(pwd.getpwuid(os.getuid()).pw_dir) / 'Library/Keychains/login.keychain-db'
    def capture(args):
        return run([SECURITY, *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    default = capture(['default-keychain', '-d', 'user'])
    if default.returncode or default.stdout.decode().strip().strip('"') != str(expected):
        raise RuntimeError('当前默认钥匙串不是本用户登录钥匙串；已停止，未修改设置。')
    selector = ['-s', SERVICE, '-a', account]
    found = capture(['find-generic-password', *selector, str(expected)])
    if found.returncode == 44:
        print('首次配置：在系统 security 的 password 提示处输入已有 Gemini 密钥。输入隐藏。', flush=True)
        print('如出现 verify password，请再输入相同密钥；不要把密钥发到聊天。', flush=True)
        # -w LAST means interactive hidden input, never a password argv value.
        # Empty trusted-app list preserves OS prompts; never -A or partition edits.
        added = run([SECURITY, 'add-generic-password', *selector,
                     '-l', 'PictureOps Gemini API', '-T', '', '-w'])
        if added.returncode:
            raise RuntimeError('钥匙串保存未完成或已取消；未启动服务。')
    elif found.returncode:
        raise RuntimeError('钥匙串查询被拒绝或失败；未尝试其他凭据来源。')
    print('读取专用钥匙串项；如有系统授权弹窗，请在本机确认。', flush=True)
    result = capture(['find-generic-password', *selector, '-w', str(expected)])
    if result.returncode:
        raise RuntimeError('钥匙串读取未获授权；已停止，不绕过系统提示。')
    raw = result.stdout.removesuffix(b'\n')
    if not re.fullmatch(rb'[A-Za-z0-9._-]{1,4095}', raw) or not re.search(rb'[A-Za-z0-9]', raw):
        raise RuntimeError('专用条目格式不符合预期；未发送请求。请在钥匙串访问中检查该条目。')
    return raw.decode('ascii')

def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if not sys.stdin.isatty():
        raise RuntimeError('请双击启动文件，在自己的 Terminal 中运行。')
    with socket.socket() as sock:
        sock.settimeout(1)
        if sock.connect_ex(('127.0.0.1', 8773)) == 0:
            try:
                with urllib.request.urlopen('http://127.0.0.1:8773/api/session', timeout=3) as response:
                    session = json.load(response)
                valid = session.get('applicationId') == 'PictureGenerate.LocalWorkbench' and session.get('maintenanceAvailable') is True and session.get('mock') is False
            except Exception:
                valid = False
            if not valid:
                raise RuntimeError('8773被其他或未确认的服务占用；未读取密钥、未改端口。')
            print('图片工作台已运行：http://127.0.0.1:8773；未读取密钥或重复启动。')
            if session.get('paidRequestsPaused'):
                print('当前仅修复系统，所有付费请求已暂停。')
            return
    key = credential()
    env = os.environ.copy()
    env['GEMINI_API_KEY'] = key
    env.pop('GEMINI_TEXT_TEST_APPROVED', None)
    env.update(HISTFILE='/dev/null', HISTSIZE='0', SAVEHIST='0')
    launcher = str(Path(__file__).resolve().with_name('start-maintained-module-one.zsh'))
    print('启动本机维护服务；启动不调用模型。看到 READY 后保持窗口运行。', flush=True)
    os.execve('/bin/zsh', ['/bin/zsh', '-f', launcher, '--gc-comparison-once'], env)

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError) as exc:
        print(str(exc) if isinstance(exc, RuntimeError) else '系统操作失败，已停止；未显示凭据。', file=sys.stderr)
        sys.exit(1)
    except (KeyboardInterrupt, EOFError):
        print('\n已取消。', file=sys.stderr)
        sys.exit(130)
