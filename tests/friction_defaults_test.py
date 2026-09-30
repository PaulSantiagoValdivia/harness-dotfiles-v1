#!/usr/bin/env python3
"""Disposable HOME only: policy, Stop registration and guarded rollback."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'files/shared/lib/install-friction-defaults.py'
spec = importlib.util.spec_from_file_location('friction', SCRIPT)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp) / 'home'
    backup = Path(tmp) / 'backup'
    before = {}
    for rel, source in [('.claude/CLAUDE.md', 'files/claude/CLAUDE.md'),
                        ('.codex/AGENTS.md', 'files/codex/AGENTS.md'),
                        ('.claude/settings.json', 'files/claude/settings.json')]:
        p = home / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        data = (ROOT / source).read_bytes()
        if rel.endswith('.json'):
            value = json.loads(data)
            value['operator'] = 'preserve'
            value['hooks']['Stop'].append({'hooks': [
                {'type': 'command', 'command': 'bash ~/.claude/hooks/engram-git-sync.sh push'},
                {'type': 'command', 'command': 'operator-hook'}]})
            data = json.dumps(value).encode()
        else:
            data = b'operator prefix\n' + data + b'operator suffix\n'
        p.write_bytes(data)
        before[rel] = data
    m.install(home, backup)
    first = {rel: (home / rel).read_bytes() for rel in before}
    m.install(home, backup)
    assert first == {rel: (home / rel).read_bytes() for rel in before}
    value = json.loads(first['.claude/settings.json'])
    assert value['operator'] == 'preserve'
    assert value['hooks']['Stop'][-1]['hooks'][0]['command'] == 'operator-hook'
    assert not any('engram-git-sync' in h['command'] for g in value['hooks']['Stop'] for h in g['hooks'])
    for rel in ('.claude/CLAUDE.md', '.codex/AGENTS.md'):
        data = first[rel]
        assert b'New changes default to `auto`' in data
        assert b'Never silently overwrite an existing `interactive` plan' in data
        assert b'`origin/dev`' in data and b'Only the tracker merges to main' not in data
        assert data.startswith(b'operator prefix') and data.endswith(b'operator suffix\n')
    target = home / '.claude/settings.json'
    target.write_bytes(b'{}')
    try:
        m.recovery.rollback(home, backup)
    except ValueError:
        pass
    else:
        raise AssertionError('concurrent edit overwritten')
    target.write_bytes(first['.claude/settings.json'])
    m.recovery.rollback(home, backup)
    assert before == {rel: (home / rel).read_bytes() for rel in before}
    for change in ('custom', 'missing-end', 'symlink'):
        target.write_bytes(before['.claude/settings.json'])
        if change == 'custom':
            value = json.loads(target.read_bytes())
            value['hooks']['Stop'][-1]['hooks'][0]['command'] += ' --custom'
            target.write_text(json.dumps(value))
        elif change == 'missing-end':
            value = json.loads(target.read_bytes())
            value['hooks'].pop('SessionEnd')
            target.write_text(json.dumps(value))
        else:
            target.unlink()
            target.symlink_to(backup / 'old/.claude/settings.json')
        try:
            m.install(home, Path(tmp) / ('reject-' + change))
        except ValueError:
            pass
        else:
            raise AssertionError('unsafe install accepted: ' + change)
        assert not (Path(tmp) / ('reject-' + change)).exists()
        if target.is_symlink():
            target.unlink()
    try:
        m.instructions(first['.codex/AGENTS.md'].replace(b'New changes default', b'Custom changes default'))
    except ValueError:
        pass
    else:
        raise AssertionError('custom policy overwritten')
print('PASS: defaults, canonical-mode preservation, Stop removal, unrelated hooks, rerun, rollback and refusal')
