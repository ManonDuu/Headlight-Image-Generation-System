"""Identify the loaded service implementation, independently of rendering rules."""
import hashlib
from pathlib import Path

def runtime_version():
    root = Path(__file__).resolve().parent
    files = ('server.py', 'jobs.py', 'providers/__init__.py', 'providers/gemini.py', 'providers/transport.py', 'runtime_version.py')
    digest = hashlib.sha256()
    for name in files:
        digest.update(name.encode())
        digest.update((root / name).read_bytes())
    return digest.hexdigest()[:16]
