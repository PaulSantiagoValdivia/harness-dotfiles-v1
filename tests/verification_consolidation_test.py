#!/usr/bin/env python3
"""Timing and policy contracts; subprocess fixtures are not production tests."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('devtools', ROOT/'files/shared/devtools/cocoa-devtools.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp)
    (p/'package.json').write_text(json.dumps({'scripts':{'check:all':'fixture'}}))
    def git(cwd, *args, **kwargs):
        return '' if args[0] == 'status' else ('feature' if args[0] == 'branch' else 'a'*40)
    for state in ('PASS', 'FAIL', 'TIMEOUT', 'BLOCKED', 'SKIPPED'):
        effect = {'TIMEOUT':subprocess.TimeoutExpired(['npm'],900),
                  'BLOCKED':FileNotFoundError('fixture spawn failure')}.get(state)
        with mock.patch.object(m, '_git', side_effect=git), \
             mock.patch.object(m.shutil, 'which', return_value='/fixture/tool'), \
             mock.patch.object(m.time, 'monotonic', side_effect=[10.0,12.5]), \
             mock.patch.object(m.subprocess, 'run', side_effect=effect,
                 return_value=subprocess.CompletedProcess(['npm'], 7 if state == 'FAIL' else 0, 'fixture','')) as runner, \
             mock.patch.dict(os.environ, {'VERIFY_SKIP':'1' if state == 'SKIPPED' else '0'}):
            receipt = m.verify_worktree(str(p),'front')
        assert receipt['state'] == state, receipt
        assert receipt['elapsed_seconds'] == 2.5, receipt
        assert runner.call_count == (0 if state == 'SKIPPED' else 1)
        assert receipt['executed'] == (state in ('PASS','FAIL','TIMEOUT'))
        if state == 'PASS': assert receipt['tested_revision'] == 'a'*40
protocol = (ROOT/'files/shared/skills/triangulation-orchestrator/references/protocol.md').read_text()
section = protocol.split('## Consolidation gate\n',1)[1].split('## Local QA control plane',1)[0]
assert 'Do not rerun the full per-repository suites merely to consolidate' in section
assert 'not a reusable verification cache' in section
assert 'mandatory final verification' in section
assert 'runs the verification commands table above per repository' not in section
assert 'verification = verify_worktree(cwd, role)' in (ROOT/'files/shared/devtools/cocoa-devtools.py').read_text()
print('PASS: five timed outcomes, no skipped execution, preserved final gate and nonduplicating consolidation policy')
