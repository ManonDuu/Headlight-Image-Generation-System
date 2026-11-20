"""Read only the existing workbench credential; never create or alter it."""
import os
import pathlib
import pwd
import re
import subprocess

def credential():
    key = os.environ.pop('GEMINI_API_KEY', None)
    if not key:
        user = pwd.getpwuid(os.getuid())
        path = str(pathlib.Path(user.pw_dir) / 'Library/Keychains/login.keychain-db')
        result = subprocess.run(
            ['/usr/bin/security', 'find-generic-password', '-s',
             'PictureGenerate.LocalWorkbench.Gemini', '-a', user.pw_name,
             '-w', path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError('当前进程无法读取工作台已保存的钥匙串项；未创建或修改密钥，未调用模型。请在本机终端运行测试入口，如系统提示则允许读取。')
        key = result.stdout.decode('ascii').rstrip('\n')
    if not re.fullmatch(r'[A-Za-z0-9._-]{1,4095}', key):
        raise RuntimeError('已保存凭据格式异常；未调用模型。')
    return key
