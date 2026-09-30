#!/usr/bin/env python3
"""Install only the approved integration policy, preserving operator configuration."""
import importlib.util
from pathlib import Path
import stat
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('recovery', Path(__file__).with_name('install-triangulation-recovery.py'))
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
recovery.ALLOWED = {'.claude/CLAUDE.md', '.codex/AGENTS.md'}
START = '<!-- gentle-ai:integration-autonomy -->'
END = '<!-- /gentle-ai:integration-autonomy -->'
OLD = '3. **Active same-file conflict**: if another LIVE session is editing the same files, do not merge silently. Surface it and let the user decide who lands first and who rebases.'
NEW = '3. **Active same-file conflict**: coordinate landing order and explicit owner handoff under the integration-autonomy policy; preserve live writers and reconcile before merging.'


def instructions(data):
    text = data.decode()
    block = (ROOT / 'files/shared/integration-autonomy.md').read_text().strip()
    recovery.require(text.count(START) == text.count(END) and text.count(START) <= 1,
                     'ambiguous autonomy block')
    if START in text:
        a, b = text.index(START), text.index(END) + len(END)
        recovery.require(a < b and text[a:b] == block, 'custom autonomy block; reconcile explicitly')
    else:
        text += ('\n' if not text.endswith('\n') else '') + '\n' + block + '\n'
    if 'let the user decide who lands first' in text:
        recovery.require(text.count(OLD) == 1, 'custom collision policy; reconcile explicitly')
        text = text.replace(OLD, NEW)
    return text.encode()


def install(home, backup):
    changes = []
    with tempfile.TemporaryDirectory(prefix='autonomy-stage-') as tmp:
        for relative in sorted(recovery.ALLOWED):
            target = home / relative
            recovery.safe(target, home)
            recovery.require(target.is_file(), 'existing instructions required')
            old = recovery.identity(target)
            staged = Path(tmp) / relative
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(instructions(target.read_bytes()))
            staged.chmod(stat.S_IMODE(target.stat().st_mode))
            new = recovery.identity(staged)
            if old != new:
                changes.append(dict(path=relative, old=old, new=new, payload=staged))
        recovery.commit(home, backup, changes)


if __name__ == '__main__':
    try:
        mode, raw_home, raw_backup = sys.argv[1:]
        recovery.require(mode in ('install', 'rollback'), 'install|rollback required')
        home, backup = Path(raw_home).absolute(), Path(raw_backup).absolute()
        recovery.safe(home, home); recovery.safe(backup, Path(backup.anchor))
        recovery.require(home.is_dir(), 'existing HOME required')
        recovery.require(not any(backup.is_relative_to(home/p) or (home/p).is_relative_to(backup)
                                 for p in recovery.ALLOWED), 'backup overlaps targets')
        install(home, backup) if mode == 'install' else recovery.rollback(home, backup)
        print('PASS: integration autonomy ' + mode)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('BLOCKED: ' + str(error), file=sys.stderr)
        sys.exit(1)
