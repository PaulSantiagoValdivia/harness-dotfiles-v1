#!/usr/bin/env python3
"""Scoped registry producer overlay; explicit HOME and immutable backup directory."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

OLD_CLAUDE = 'd="${CLAUDE_PROJECT_DIR:-$PWD}"; { [ "$d" = "$HOME" ] || git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; } && gentle-ai skill-registry refresh --quiet --no-gitignore --cwd "$d"; true'
OLD_CODEX = 'gentle-ai skill-registry refresh --quiet --no-gitignore --cwd "$PWD" || true'
COMMANDS = {
    'claude': '"$HOME/.local/bin/skill-registry-refresh" "${CLAUDE_PROJECT_DIR:-$PWD}"',
    'codex': '"$HOME/.local/bin/skill-registry-refresh" "$PWD"',
}


def install(home, backup):
    changes = []
    for client, filename in (('claude', 'settings.json'), ('codex', 'hooks.json')):
        path = home / f'.{client}' / filename
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise ValueError(f'symlink refused: {path}')
        old = path.read_bytes() if path.exists() else None
        data = json.loads(old) if old is not None else {}
        hooks = data.setdefault('hooks', {}).setdefault('SessionStart', [])
        found = []
        for group in hooks:
            for entry in group['hooks']:
                command = entry.get('command', '')
                if 'skill-registry' in command:
                    if entry.get('type') != 'command' or command not in (OLD_CLAUDE, OLD_CODEX, COMMANDS[client]):
                        raise ValueError(f'unrecognized registry command: {path}')
                    found.append(entry)
        if len(found) > 1:
            raise ValueError(f'ambiguous registry hooks: {path}')
        if found:
            if found[0]['command'] == COMMANDS[client]:
                continue
            found[0]['command'] = COMMANDS[client]
        else:
            hooks.append({'matcher': 'startup|resume|clear|compact', 'hooks': [{'type': 'command', 'command': COMMANDS[client], 'timeout': 30}]})
        changes.append((path, backup / f'{client}-{filename}', old, (json.dumps(data, indent=2)+'\n').encode(), path.stat().st_mode if old is not None else 0o600))
    source = Path(__file__).resolve().parents[1] / 'bin/skill-registry-refresh'
    helper = home / '.local/bin/skill-registry-refresh'
    if helper.is_symlink() or (helper.exists() and not helper.is_file()):
        raise ValueError('helper symlink refused')
    old = helper.read_bytes() if helper.exists() else None
    if old != source.read_bytes() or not os.access(helper, os.X_OK):
        changes.insert(0, (helper, backup / 'skill-registry-refresh', old, source.read_bytes(), 0o755))
    for path, saved, old, _, _ in changes:
        if saved.exists() or saved.is_symlink():
            raise ValueError(f'backup collision: {saved}')
        if path.exists() and path.read_bytes() != old:
            raise ValueError(f'concurrent change: {path}')
    for path, saved, old, new, mode in changes:
        if old is not None:
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, saved)
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(dir=path.parent)
        with os.fdopen(fd, 'wb') as output:
            output.write(new)
        os.chmod(temporary, mode)
        os.replace(temporary, path)


if __name__ == '__main__':
    try:
        install(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
    except (OSError, ValueError, TypeError, KeyError, AttributeError, IndexError) as error:
        print(f'BLOCKED registry install: {error}', file=sys.stderr)
        sys.exit(1)
