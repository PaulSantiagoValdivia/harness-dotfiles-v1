#!/usr/bin/env python3
"""Scoped, guarded policy overlay; reuse recovery backup/rollback primitives."""
import hashlib
import importlib.util
import json
from pathlib import Path
import stat
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('recovery', Path(__file__).with_name('install-triangulation-recovery.py'))
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)
recovery.ALLOWED = {'.claude/CLAUDE.md', '.codex/AGENTS.md', '.claude/settings.json'}
LEGACY = {'### Execution Mode': ['f4e3f1c13fab249f7a5e390a61a738d8c3fa21e02ce7d226913116c231cc0bb5', 'fd78f4b6997368dfbac4e8f3c9039672ece03e4d20aa03e9fd8d49ef9b72379b'], '### Delivery Strategy': ['d2c8b3d914cf32c188f880f1d2bd6dd5c7df1576103d13ed6008308b64e33644']}
MODE = """### Execution Mode

New changes default to `auto` (standing user preference). Resolve explicit user choice,
then the exact canonical change's saved mode, then this default. Read `mode` and
legacy `execution_mode`; conflicting values block only the affected change.
Never silently overwrite an existing `interactive` plan, infer authority from a
worktree name, or re-ask a decision already persisted for that change.

- **Automatic** (`auto`): execute dependency-ready phases without routine approval
  pauses; continue approved independent work and deliver verified commits/PRs.
- **Interactive** (`interactive`): honor an explicit or persisted request to review
  each phase; ask once at that boundary and wait for the answer.

Persist resolved choices in the canonical state; workers consume them. Automatic
mode does not authorize production promotion, permission bypass, scope expansion,
write-ownership transfer or size exceptions. Escalate those real decisions only.

"""
DELIVERY = """### Delivery Strategy

For new changes, default to `auto-chain`; preserve an explicit or persisted
`ask-on-risk`, `single-pr`, or `exception-ok`. Cache by canonical change, not by
session alone, and pass the resolved strategy to tasks/apply executors.

### Chain Strategy

For a new chain with no explicit or persisted choice, use `feature-branch-chain`.
Resolve the integration target to `dev` when `origin/dev` exists; otherwise use
the verified repository default branch. The name `stacked-to-main` is a legacy
strategy identifier, NEVER an instruction to bypass the branch-flow policy.

- **`stacked-to-main`**: merge ordered slices to the resolved integration target.
- **`feature-branch-chain`**: the first child targets the tracker; later children
  target their predecessor; only the tracker targets the integration branch.

Preserve existing chain boundaries and pass the resolved choice to tasks/apply.
Do not ask routine strategy questions again; unresolved conflicting choices or
ownership still require an explicit decision. No automatic production promotion.

"""


def instructions(data):
    text = data.decode()
    for start, end, new in [('### Execution Mode', '### Artifact Store Mode', MODE),
                            ('### Delivery Strategy', '### Dependency Graph', DELIVERY)]:
        recovery.require(text.count(start) == text.count(end) == 1, 'ambiguous policy section')
        a, b = text.index(start), text.index(end)
        recovery.require(a < b, 'reversed policy section')
        old = text[a:b]
        recovery.require(old == new or hashlib.sha256(old.encode()).hexdigest() in LEGACY[start],
                         'custom policy section: preserve and reconcile explicitly')
        text = text[:a] + new + text[b:]
    text = text.replace('and skip straight to asking about Execution Mode (auto/interactive) and Chain Strategy',
                        'and resolve execution/delivery choices from canonical state before defaults')
    text = text.replace('also ask which chain strategy to use (`stacked-to-main` or `feature-branch-chain`)',
                        'resolve chain strategy from canonical state or the new-chain default')
    text = text.replace('If `chain_strategy` is not yet cached, ask which chain strategy to use.',
                        'If `chain_strategy` is not yet cached, resolve canonical state or the new-chain default.')
    return text.encode()


def settings(data):
    value = json.loads(data)
    command = 'bash ~/.claude/hooks/engram-git-sync.sh push'
    hooks = value.get('hooks', {})
    recovery.require(any(h.get('command') == command for g in hooks.get('SessionEnd', [])
                         for h in g.get('hooks', [])), 'missing SessionEnd sync; preserve Stop')
    groups = []
    for group in hooks.get('Stop', []):
        kept = []
        for hook in group.get('hooks', []):
            if 'engram-git-sync' in hook.get('command', ''):
                recovery.require(hook.get('command') == command and hook.get('type') == 'command',
                                 'custom Stop sync: preserve and reconcile explicitly')
            else:
                kept.append(hook)
        if kept:
            groups.append({**group, 'hooks': kept})
    hooks['Stop'] = groups
    return data if value == json.loads(data) else (json.dumps(value, indent=2) + '\n').encode()


def install(home, backup):
    changes = []
    with tempfile.TemporaryDirectory(prefix='friction-stage-') as temporary:
        for relative in sorted(recovery.ALLOWED):
            target = home / relative
            recovery.safe(target, home)
            old = recovery.identity(target)
            recovery.require(target.is_file(), 'existing configuration required')
            data = settings(target.read_bytes()) if relative.endswith('.json') else instructions(target.read_bytes())
            staged = Path(temporary) / relative
            staged.parent.mkdir(parents=True, exist_ok=True)
            staged.write_bytes(data)
            staged.chmod(stat.S_IMODE(target.stat().st_mode))
            new = recovery.identity(staged)
            if old != new:
                changes.append({'path': relative, 'old': old, 'new': new, 'payload': staged})
        recovery.commit(home, backup, changes)


if __name__ == '__main__':
    try:
        mode, raw_home, raw_backup = sys.argv[1:]
        recovery.require(mode in ('install', 'rollback'), 'install|rollback required')
        recovery.require(not Path(raw_home).is_symlink() and not Path(raw_backup).is_symlink(), 'symlink root')
        home, backup = Path(raw_home).resolve(), Path(raw_backup).resolve()
        recovery.require(home.is_dir(), 'existing HOME required')
        recovery.require(not any(backup.is_relative_to(home/p) or (home/p).is_relative_to(backup)
                                 for p in recovery.ALLOWED), 'backup overlaps targets')
        if mode == 'install':
            install(home, backup)
        else:
            recovery.rollback(home, backup)
        print('PASS: friction overlay ' + mode)
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        print('BLOCKED: ' + str(error), file=sys.stderr)
        sys.exit(1)
