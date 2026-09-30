#!/usr/bin/env python3
"""Policy/installer contracts, not a claim of live agent behavior."""
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('autonomy', ROOT/'files/shared/lib/install-integration-autonomy.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
block = (ROOT/'files/shared/integration-autonomy.md').read_text().strip()
for client, name in [('claude', 'CLAUDE.md'), ('codex', 'AGENTS.md')]:
    source = (ROOT/f'files/{client}/{name}').read_text()
    assert source.count(block) == 1
    assert m.OLD not in source
for phrase in ('never infer approval', 'explicit holds', 'deploys production',
               'Unknown or failed gates block merge', 'unmanaged review result is not approval',
               'Without a', 'zero redundant merge prompts'):
    assert phrase in block
with tempfile.TemporaryDirectory() as tmp:
    home, backup = Path(tmp)/'home', Path(tmp)/'backup'
    before = {}
    for relative in m.recovery.ALLOWED:
        p = home/relative
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text('operator prefix\n' + m.OLD + '\noperator suffix\n')
        before[relative] = p.read_bytes()
    m.install(home, backup)
    installed = {p: (home/p).read_bytes() for p in before}
    m.install(home, backup)
    assert installed == {p: (home/p).read_bytes() for p in before}
    assert all(b'operator prefix' in d and b'operator suffix' in d for d in installed.values())
    p = home/'.claude/CLAUDE.md'
    p.write_bytes(p.read_bytes() + b'concurrent edit\n')
    try:
        m.recovery.rollback(home, backup)
        raise AssertionError('concurrent edit overwritten')
    except ValueError:
        pass
    p.write_bytes(installed['.claude/CLAUDE.md'])
    m.recovery.rollback(home, backup)
    assert before == {p: (home/p).read_bytes() for p in before}
    for bad in (m.START, m.END + m.START, block + block,
                block.replace('zero redundant', 'allow redundant'),
                m.OLD.replace('do not merge silently', 'custom policy')):
        try:
            m.instructions(bad.encode())
            raise AssertionError('unsafe policy accepted')
        except ValueError:
            pass
    p.unlink(); p.symlink_to(backup/'old/.claude/CLAUDE.md')
    try:
        m.install(home, Path(tmp)/'unsafe')
        raise AssertionError('symlink accepted')
    except ValueError:
        pass
print('PASS: policy parity, idempotence, preservation, rollback, concurrent edit and malformed/symlink refusal')
