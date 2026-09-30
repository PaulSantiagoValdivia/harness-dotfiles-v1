#!/usr/bin/env bash
# Observable evidence labels and full-verifier suite wiring, without live clients.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import os, pathlib, re, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
protocol = (root / 'files/shared/skills/triangulation-orchestrator/references/protocol.md').read_text()
launcher = protocol.split('## Launcher\n', 1)[1].split('\n## ', 1)[0]
assert 'creates three fresh worktrees' in launcher and 'rejects existing targets' in launcher
assert 'creates or reuses' not in launcher, 'launcher must not promise unsafe reuse'
verify = (root / 'verify.sh').read_text()
for suite in ('triangulate_handoff_test.sh', 'triangulate_launcher_test.sh', 'cocoa_devtools_test.py', 'skill_registry_root_test.sh'):
    assert f'tests/{suite}' in verify, f'missing full-verifier fixture: {suite}'
parity = (root / 'tests/standalone_runtime_parity_test.sh').read_text()
label = next(line for line in reversed(parity.splitlines()) if line.startswith('pass '))
output = subprocess.check_output(['bash', '-c', 'pass() { printf "%s\\n" "$1"; }; ' + label], text=True)
assert 'static configuration/contracts' in output and 'live messaging UNTESTED' in output, output
# C2: exercise the actual published recipe, not a handwritten equivalent.
doc = (root / 'docs/triangulation-safety.md').read_text()
section = doc.split('## Preserve gate failures and logs\n', 1)[1].split('\n## ', 1)[0]
blocks = re.findall(r'```bash\n(.*?)\n```', section, re.S)
assert len(blocks) == 1, 'expected one gate-retention recipe'
recipe = blocks[0]
gates = ('format:check', 'typecheck', 'lint')
with tempfile.TemporaryDirectory(prefix='gate recipe ') as temporary:
    home = pathlib.Path(temporary); binary = home / 'bin'; binary.mkdir()
    npm = binary / 'npm'
    npm.write_text("#!/usr/bin/env python3\nimport os, sys\ngates = ('format:check', 'typecheck', 'lint')\nassert sys.argv[1] == 'run' and len(sys.argv) == 3\ngate = sys.argv[2]\nwith open(os.environ['CALLS'], 'a') as stream: stream.write(gate + '\\n')\nprint('stdout:' + gate)\nprint('stderr:' + gate, file=sys.stderr)\nsys.exit(int(os.environ['CODES'].split(',')[gates.index(gate)]))\n")
    npm.chmod(0o755)
    cases = ((0, 0, 0), (11, 0, 0), (0, 22, 0), (0, 0, 33), (11, 22, 0), (11, 22, 33))
    for index, codes in enumerate(cases):
        evidence = home / str(index); evidence.mkdir(); calls = evidence / 'calls'
        result = subprocess.run(['bash', '-c', recipe], capture_output=True, text=True, timeout=10,
                                env={**os.environ, 'PATH': str(binary) + ':' + os.environ['PATH'],
                                     'EVIDENCE': str(evidence), 'CALLS': str(calls), 'CODES': ','.join(map(str, codes))})
        expected = next((code for code in reversed(codes) if code), 0)
        assert result.returncode == expected, ('aggregate exit', codes, expected, result.returncode)
        assert calls.read_text().splitlines() == list(gates), 'all gates must run in order'
        for gate, filename in zip(gates, ('format.log', 'typecheck.log', 'lint.log')):
            log = (evidence / filename).read_text()
            assert 'stdout:' + gate in log and 'stderr:' + gate in log, (gate, log)
assert 'last nonzero exit' in section, 'document aggregate failure policy'
# These assert instruction contracts, NOT observed model behavior or native delivery.
skill = (root / 'files/shared/skills/triangulation-orchestrator/SKILL.md').read_text()
for instruction in ('HELLO/ACK', 'without human relay', 'unresolved requirements', 'permissions', 'ownership conflicts'):
    assert instruction in skill, instruction
routing = protocol.split('## Autonomous routing and existing-session adoption\n', 1)[1].split('\n## ', 1)[0]
for instruction in ('worker → lead → worker', 'receipt corrections', 'safe unblocked read/test', 'scope expansion',
                    'Reload the installed skill', 'existing coordinator', 'fresh nonce', 'fresh ACK', 'exact sibling paths',
                    'Never launch another top-level', 'triangulate resume', 'held/refused inbox', 'never change permissions', 'BLOCKED'):
    assert instruction in routing, instruction
assert 'cannot force compliance' in doc and 'live coordination UNTESTED' in doc
print('PASS: actual docs recipe (six exit cases/logs), routing/adoption contracts and static labels; native coordination UNTESTED')
PY
