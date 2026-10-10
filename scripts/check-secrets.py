#!/usr/bin/env python3
"""Check tracked and non-ignored candidate files without printing matched values."""
import pathlib, re, subprocess, sys
files = subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z']).split(b'\0')
patterns = [rb'gh[pousr]_[A-Za-z0-9]{30,}', rb'github_pat_[A-Za-z0-9_]{50,}',
            rb'sk-(?:proj-)?[A-Za-z0-9_-]{32,}', rb'AKIA[A-Z0-9]{16}',
            rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----']
found = False
for file in files:
    if not file: continue
    path = pathlib.Path(file.decode())
    if path.is_file():
        data = path.read_bytes()
        found |= any(re.search(pattern, data) for pattern in patterns)
print('有' if found else '沒有')
sys.exit(1 if found else 0)
