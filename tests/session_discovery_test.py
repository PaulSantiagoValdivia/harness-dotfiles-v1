#!/usr/bin/env python3
"""Execute the real monitor with controlled process listings, no live sessions."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp); bin_dir = home/'bin'; bin_dir.mkdir()
    def executable(name, text):
        p = bin_dir/name; p.write_text('#!/bin/sh\n'+text); p.chmod(0o755)
    executable('ps', '''[ "$*" = "-eo pid=,comm=" ] || exit 91
[ "${FAIL_PS:-0}" = 0 ] || { echo 'process enumeration denied' >&2; exit 7; }
[ "${EMPTY_PS:-0}" = 0 ] || exit 0
cat <<'ROWS'
101 /Users/example/.local/bin/claude
102 /Applications/Legacy App/bin/claude
103 claude
104 /usr/bin/grep
105 /bin/echo
106 /some/claude-helper
107 /tmp/claude/project/node
ROWS
''')
    executable('lsof', 'printf "n/nonexistent-fixture-repository\\n"\n')
    env = dict(os.environ, HOME=str(home), PATH=str(bin_dir)+':'+os.environ['PATH'])
    def run(*args, **extra):
        return subprocess.run(['bash',str(ROOT/'files/shared/bin/claude-sessions'),*args],
                              env=dict(env,**extra), capture_output=True,text=True,timeout=10)
    r = run('--porcelain')
    assert r.returncode == 0, r.stderr
    rows = r.stdout.splitlines()
    assert {row.split('\t')[0] for row in rows} == {'101','102','103'}, r.stdout
    assert all(row.split('\t')[1:3] == ['-','-'] for row in rows)
    for args in ([], ['--porcelain']):
        r = run(*args,FAIL_PS='1')
        assert r.returncode != 0 and 'process enumeration denied' in r.stderr
        assert not r.stdout, 'failure disguised as empty success'
    r = run('--porcelain',EMPTY_PS='1')
    assert r.returncode == 0 and r.stdout == ''
print('PASS: native/legacy/bare processes, false positives, unknown metrics, process failure and true empty inventory')
