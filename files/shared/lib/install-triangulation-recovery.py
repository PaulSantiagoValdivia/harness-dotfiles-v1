#!/usr/bin/env python3
"""Explicit scoped recovery overlay; immutable originals and guarded rollback."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SKILL = '.{client}/skills/triangulation-orchestrator'
FILES = {f'.claude/hooks/{name}.sh': f'files/claude/hooks/{name}.sh' for name in
         ('context-budget', 'context-budget-measure', 'triangulate-handoff')}
FILES['.codex/engram-compact-prompt.md'] = 'files/codex/engram-compact-prompt.md'
ALLOWED = {*FILES, '.claude/settings.json', '.claude/CLAUDE.md', '.codex/AGENTS.md', *(SKILL.format(client=c) for c in ('claude', 'codex'))}
MARKER = '<!-- gentle-ai:runtime-budget -->'
END = '<!-- /gentle-ai:runtime-budget -->'


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def safe(path, home):
    require(path.is_relative_to(home), 'outside explicit root')
    for part in [path, *path.parents]:
        require(not part.is_symlink(), f'symlink refused: {part}')
        if part == home:
            break


def identity(path):
    if not path.exists() and not path.is_symlink():
        return None
    rows = []
    for item in [path, *sorted(path.rglob('*'))] if path.is_dir() else [path]:
        require(not item.is_symlink() and (item.is_file() or item.is_dir()), f'nonregular target: {item}')
        rows.append((str(item.relative_to(path)), stat.S_IMODE(item.stat().st_mode),
                     hashlib.sha256(item.read_bytes()).hexdigest() if item.is_file() else 'directory'))
    return hashlib.sha256(json.dumps(rows).encode()).hexdigest()


def settings(old):
    data = json.loads(old) if old else {}
    groups = data.setdefault('hooks', {}).setdefault('SessionStart', [])
    require(type(groups) is list, 'invalid SessionStart')
    for name, matcher in [('triangulate-handoff', 'startup|resume|clear|compact'), ('context-budget-measure', 'compact')]:
        command = f'bash ~/.claude/hooks/{name}.sh'
        found = [(g, h) for g in groups for h in g['hooks'] if name in h.get('command', '')]
        require(len(found) <= 1, f'ambiguous {name}')
        if found:
            group, hook = found[0]
            require(hook.get('command') == command and hook.get('type') == 'command' and len(group['hooks']) == 1,
                    f'unrecognized {name} command/group')
            require(group.get('matcher') in ('startup|clear', matcher), f'unrecognized {name} matcher')
            group['matcher'] = matcher
        else:
            groups.append({'matcher': matcher, 'hooks': [{'type': 'command', 'command': command}]})
    # Preserve byte formatting on identical reruns, not just semantic values.
    return old if old and json.loads(old) == data else (json.dumps(data, indent=2)+'\n').encode()


def instructions(old, client):
    text = old.decode() if old else ''
    block = (ROOT/'files/shared/runtime-budget.md').read_text().strip()
    require(text.count(MARKER) == text.count(END) and text.count(MARKER) <= 1, 'ambiguous managed block')
    if MARKER in text:
        require(text.index(MARKER) < text.index(END), 'reversed managed block')
        text = re.sub(re.escape(MARKER)+'.*?'+re.escape(END), lambda _: block, text, flags=re.S)
    else:
        text += ('\n' if text and not text.endswith('\n') else '') + block + '\n'
    if client == 'claude' and '<!-- user-override:context-budget' in text:
        replacements = {
            '- `~/.claude/hooks/context-budget.sh` (UserPromptSubmit) avisa a 120k, exige\n  cerrar y compactar a 180k, y declara zona de quemado a 400k.':
                '- `context-budget-measure.sh` (Stop) mide: AVISO a 200k, ALTO a 300k,\n  CRITICO a 400k. `context-budget.sh` (UserPromptSubmit) solo lee el cache;\n  SessionStart compact lo invalida para esa sesion. Son avisos, no un bloqueo.',
            'Regla operativa: una unidad de trabajo por sesión, `/clear` al cerrarla. Una\nsesión de 10 horas arrastra el contexto del primer bug hasta el último commit.':
                'Regla operativa: para la misma tarea, checkpoint y compactacion nativa;\nconservar decisiones aprobadas, procesos activos y entregas pendientes.\nNo confundir contexto con cuota ni pedir un reset automatico; cambiar de\nsesion solo para otra tarea o un handoff seguro explicito.'}
        for before, after in replacements.items():
            require(before in text or after in text, 'unrecognized context override; preserve operator edit')
            text = text.replace(before, after)
    return text.encode()


def plan(home, stage):
    for relative in ALLOWED:
        safe(home/relative, home); identity(home/relative)
    staged_home = stage/'home'
    subprocess.run(['bash', '-c', 'source "$1"; install_shared_skill "$2" "$3" "$4"', 'recovery',
        str(ROOT/'files/shared/lib/install-shared-skill.sh'), str(ROOT/'files/shared/skills/triangulation-orchestrator'),
        str(staged_home), str(stage/'unused-backups')], check=True, capture_output=True)
    changes = []
    for relative in sorted(ALLOWED):
        path = home/relative; old = identity(path)
        payload = staged_home/relative
        if '/skills/' not in relative:
            previous = path.read_bytes() if old is not None else None
            if relative == '.claude/settings.json': data = settings(previous)
            elif relative.endswith(('CLAUDE.md', 'AGENTS.md')): data = instructions(previous, 'claude' if '.claude/' in relative else 'codex')
            else: data = (ROOT/FILES[relative]).read_bytes()
            payload.parent.mkdir(parents=True, exist_ok=True); payload.write_bytes(data)
            os.chmod(payload, stat.S_IMODE(path.stat().st_mode) if old else (0o755 if relative.endswith('.sh') else 0o600))
        elif old is not None:
            os.chmod(payload, stat.S_IMODE(path.stat().st_mode))
        new = identity(payload)
        if old != new:
            changes.append({'path':relative, 'old':old, 'new':new, 'payload':payload})
    return changes


def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir(): shutil.copytree(source, destination, copy_function=shutil.copy2)
    else: shutil.copy2(source, destination)


def replace(payload, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=target.parent, prefix='.recovery-') as temporary:
        ready = Path(temporary)/'ready'; copy(payload, ready)
        if target.is_dir():
            os.replace(target, Path(temporary)/'previous')
            try: os.replace(ready, target)
            except OSError:
                os.replace(Path(temporary)/'previous', target); raise
        else:
            os.replace(ready, target)


def commit(home, backup, changes):
    if not changes:
        return
    require(not backup.exists() and not backup.is_symlink(), 'backup collision; choose a fresh directory')
    for item in changes:
        target = home/item['path']; safe(target, home)
        require(identity(target) == item['old'] and identity(item['payload']) == item['new'], 'concurrent target/source change')
    backup.mkdir(parents=True, mode=0o700)
    manifest = {'version':1, 'home':str(home), 'entries':[{k:v for k,v in item.items() if k != 'payload'} for item in changes]}
    for item in changes:
        if item['old'] is not None: copy(home/item['path'], backup/'old'/item['path'])
    with (backup/'manifest.json').open('x') as out: json.dump(manifest, out, indent=2)
    for item in changes:
        target=home/item['path']; safe(target, home)
        require(identity(target) == item['old'], 'concurrent change; preserve backup and inspect partial install')
        replace(item['payload'], target)


def rollback(home, backup):
    manifest=json.loads((backup/'manifest.json').read_text())
    require(manifest.get('version') == 1 and manifest.get('home') == str(home), 'wrong rollback authority')
    entries=manifest['entries']; require(len({e['path'] for e in entries}) == len(entries), 'duplicate rollback path')
    for item in entries:
        require(item['path'] in ALLOWED, 'unmanaged rollback path')
        target=home/item['path']; safe(target, home); safe(backup/'old'/item['path'], backup)
        require(identity(target) in (item['new'], item['old']), 'rollback refused: concurrent edit')
        require(identity(backup/'old'/item['path']) == item['old'], 'backup changed')
    for item in reversed(entries):
        target=home/item['path']; safe(target, home)
        if identity(target) == item['old']: continue
        require(identity(target) == item['new'], 'concurrent rollback edit')
        if item['old'] is not None: replace(backup/'old'/item['path'], target)
        elif target.is_dir(): shutil.rmtree(target)
        else: target.unlink()


if __name__ == '__main__':
    try:
        mode, raw_home, raw_backup = sys.argv[1:]
        require(not Path(raw_home).is_symlink() and not Path(raw_backup).is_symlink(), 'symlinked root')
        home, backup = Path(raw_home).resolve(), Path(raw_backup).resolve()
        require(home.is_dir() and mode in ('install','rollback'), 'explicit existing HOME and install|rollback required')
        require(not any(backup.is_relative_to(home/p) or (home/p).is_relative_to(backup) for p in ALLOWED), 'backup overlaps managed paths')
        if mode == 'rollback': rollback(home, backup)
        else:
            with tempfile.TemporaryDirectory(prefix='recovery-stage-') as stage:
                commit(home, backup, plan(home, Path(stage)))
        print(f'PASS: recovery {mode}; managed paths only')
    except (OSError, ValueError, TypeError, KeyError, AttributeError, subprocess.SubprocessError) as error:
        print(f'BLOCKED recovery overlay: {error}', file=sys.stderr); sys.exit(1)
