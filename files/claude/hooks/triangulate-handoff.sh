#!/usr/bin/env bash
# Read-only, deterministic SessionStart authority. Never infer another plan.
set -uo pipefail
python3 - "$@" <<'PY'
import datetime
import hashlib
import json
import os
import stat
import unicodedata
import pathlib
import re
import subprocess
import sys

VERIFY = sys.argv[1:] == ['--verify']
if sys.argv[1:] and not VERIFY:
    print('BLOCKED: usage: triangulate-handoff.sh [--verify]')
    raise SystemExit(2)


def emit(message):
    data = message.encode()
    suffix = b'\nTRUNCATED: read canonical checkpoint pointer.' if len(data) > 3997 else b''
    print(data[:3997-len(suffix)].decode('utf-8', errors='ignore') + suffix.decode())


def git(path, *args):
    result = subprocess.run(['git', '-C', str(path), *args], capture_output=True,
                            text=True, timeout=10, env={**os.environ, 'GIT_OPTIONAL_LOCKS': '0'})
    if result.returncode:
        raise ValueError(f'Git no verificable: {path}')
    return result.stdout.strip()


def root(path):
    path = path.resolve(strict=True)
    if not (path / '.git').exists() or pathlib.Path(git(path, 'rev-parse', '--show-toplevel')).resolve() != path:
        raise ValueError(f'No es raíz Git: {path}')
    return path


def entries(path, optional=False):
    if optional and not os.path.lexists(path):
        return {}
    values = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, separator, value = line.partition('=')
        if not separator or not key or not value or key in values:
            raise ValueError(f'Mapping inválido/duplicado: {path}')
        values[key] = value
    return values


def identifier(value):
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', value):
        raise ValueError(f'Identificador inválido: {value}')
    return value


def inside(path, parent):
    resolved = path.resolve(strict=True)
    if not resolved.is_relative_to(parent):
        raise ValueError(f'Ruta fuera de autoridad: {path}')
    return resolved


MODES = {'mode': {'auto', 'interactive'}, 'delivery_strategy': {'ask-on-risk', 'auto-chain', 'single-pr', 'exception-ok'},
         'chain_strategy': {'stacked-to-main', 'feature-branch-chain'}}


def bounded(path, parent, limit):
    resolved = inside(path, parent)
    if resolved != path or not stat.S_ISREG(resolved.stat().st_mode):
        raise ValueError('Ruta regular sin symlinks requerida')
    with resolved.open('rb') as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Archivo excede limite')
    return data


def state_flags(path, authority):
    flags = {}
    for line in bounded(path, authority, 65536).decode().splitlines():
        key, separator, value = line.partition(':')
        if not separator or key not in {*MODES, 'execution_mode', 'artifact_store', 'strict_tdd'}:
            continue
        if key in flags:
            raise ValueError('Estado duplicado')
        value = value.split(' #', 1)[0].strip()
        if value[:1] in ('\'', '"'):
            require(len(value) >= 2 and value[-1] == value[0])
            value = value[1:-1]
        flags[key] = value
    legacy = flags.pop('execution_mode', None)
    if legacy is not None:
        if 'mode' in flags and flags['mode'] != legacy:
            raise ValueError('Conflicto mode/execution_mode')
        flags['mode'] = legacy
    if any(key in flags and flags[key] not in values for key, values in MODES.items()):
        raise ValueError('Modo/estrategia invalida')
    return flags


def require(condition):
    if not condition:
        raise ValueError('Checkpoint invalido o stale')


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result)
        result[key] = value
    return result


def shape(value, keys):
    require(type(value) is dict and set(value) == set(keys.split()))


def timestamp(value):
    require(type(value) is str)
    parsed = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None)
    return parsed


def text_data(value, depth=0):
    require(depth < 8)
    if isinstance(value, str):
        require(len(value.encode()) <= 512 and not any(unicodedata.category(c).startswith('C') for c in value))
    elif isinstance(value, dict):
        require(len(value) <= 32)
        for key, item in value.items():
            text_data(key, depth + 1); text_data(item, depth + 1)
    elif isinstance(value, list):
        require(len(value) <= 16)
        for item in value:
            text_data(item, depth + 1)
    else:
        require(type(value) in (int, bool))


def coordination_state(value):
    if value['version'] == 1:
        return {'coordination': 'LEGACY_WAIT_UNVERIFIED'}
    state = value['coordination']
    shape(state, 'phase wait')
    require(state['phase'] in ('acknowledged', 'working', 'receipt_pending', 'validated', 'blocked'))
    wait = state['wait']
    require(type(wait) is dict)
    waiting = state['phase'] in ('receipt_pending', 'blocked')
    require(bool(wait) == waiting)
    if state['phase'] == 'validated':
        require(not value['dirty'] and bool(value['receipts']) and value['blocker']['kind'] == 'none')
    expired = False
    if waiting:
        shape(wait, 'kind owner request_id event mechanism handle scope started_at deadline next_action')
        for key, item in wait.items():
            require(type(item) is str and (bool(item) or key == 'handle'))
        require(wait['kind'] in ('peer', 'human'))
        allowed = ('native_reply', 'idle_notice', 'unavailable') if wait['kind'] == 'peer' else ('user_response', 'unavailable')
        require(wait['mechanism'] in allowed)
        require(bool(wait['handle']) == (wait['mechanism'] != 'unavailable'))
        start, deadline = timestamp(wait['started_at']), timestamp(wait['deadline'])
        require(start < deadline)
        expired = deadline <= datetime.datetime.now(datetime.timezone.utc)
    return {'coordination': state, 'wait_expired': expired}


def checkpoint(authority, current, slug, role, flags):
    try:
        value = json.loads(bounded(authority / 'recovery' / f'{role}.json', authority, 8192), object_pairs_hook=unique)
        require(type(value) is dict and type(value.get('version')) is int and value['version'] in (1, 2))
        fields = 'version slug role authority worktree branch revision dirty observed_at artifact_hashes execution_mode delivery_strategy chain_strategy task next_action owner process receipts pending_delivery blocker'
        shape(value, fields + (' coordination' if value['version'] == 2 else ''))
        text_data(value)
        require(type(value['dirty']) is bool)
        for key in ('slug', 'role', 'authority', 'worktree', 'branch', 'revision', 'execution_mode', 'delivery_strategy', 'chain_strategy', 'task', 'next_action'):
            require(type(value[key]) is str and bool(value[key]))
        require((value['slug'], value['role'], value['authority'], value['worktree']) == (slug, role, str(authority), str(current)))
        require(value['revision'] == git(current, 'rev-parse', 'HEAD') and value['branch'] == git(current, 'rev-parse', '--abbrev-ref', 'HEAD'))
        timestamp(value['observed_at'])
        for key, choices in MODES.items():
            field = 'execution_mode' if key == 'mode' else key
            require(value[field] in choices and (key not in flags or value[field] == flags[key]))
        shape(value['owner'], 'identity status')
        require(type(value['owner']['identity']) is str and bool(value['owner']['identity']) and value['owner']['status'] in ('active', 'stopped', 'unknown'))
        shape(value['process'], 'handle status observed_at')
        require(type(value['process']['handle']) is str and value['process']['status'] in ('running', 'finished', 'unknown'))
        require(value['process']['status'] != 'running' or bool(value['process']['handle']))
        timestamp(value['process']['observed_at'])
        shape(value['blocker'], 'kind evidence observed_at')
        require(value['blocker']['kind'] in ('none', 'context', 'quota', 'tool', 'dependency', 'permission', 'delivery') and type(value['blocker']['evidence']) is str)
        timestamp(value['blocker']['observed_at'])
        require(type(value['pending_delivery']) is list and all(type(v) is str and v for v in value['pending_delivery']))
        require(type(value['receipts']) is list)
        for receipt in value['receipts']:
            shape(receipt, 'path revision')
            require(type(receipt['revision']) is str and re.fullmatch(r'[a-f0-9]{40}(?:[a-f0-9]{24})?', receipt['revision']))
            require(type(receipt['path']) is str)
            pointer = pathlib.Path(receipt['path']).resolve(strict=True)
            require(pointer.is_relative_to(current) or pointer.is_relative_to(authority))
        hashes = value['artifact_hashes']
        required = {'proposal.md', 'design.md', 'tasks.md'} | {str(p.relative_to(authority)) for p in authority.glob('specs/*/spec.md')}
        require(type(hashes) is dict and len(required) > 3 and set(hashes) == required)
        for name, digest in hashes.items():
            require(type(digest) is str and re.fullmatch('[a-f0-9]{64}', digest))
            require(hashlib.sha256(bounded(authority / name, authority, 262144)).hexdigest() == digest)
        if VERIFY and value['version'] != 2:
            raise ValueError('v2 required for explicit verification')
        summary = coordination_state(value)
        if value['version'] == 2 and value['coordination']['phase'] == 'validated':
            require(not git(current, 'status', '--porcelain'))
            require(all(r['revision'] == value['revision'] for r in value['receipts']))
        summary.update({k: value[k] for k in ('execution_mode', 'delivery_strategy', 'chain_strategy', 'task', 'next_action', 'owner', 'process', 'pending_delivery', 'blocker', 'dirty', 'revision', 'observed_at', 'receipts')})
        return f'RECOVERY DATA {authority}/recovery/{role}.json (recorded; inspect dirty bytes): ' + json.dumps(summary, ensure_ascii=False)
    except (OSError, ValueError, RecursionError, TypeError) as error:
        if VERIFY:
            raise ValueError('RECOVERY UNAVAILABLE: ' + str(error)[:160]) from error
        return 'RECOVERY UNAVAILABLE: ' + str(error)[:160]


try:
    directory = pathlib.Path(os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd())).absolute()
    marker = '/.claude/worktrees/triangulate-'
    if marker not in str(directory):
        if VERIFY:
            raise ValueError('Explicit recovery verification requires a triangulation worktree')
        raise SystemExit(0)
    base, suffix = str(directory).split(marker, 1)
    slug = identifier(suffix.split('/')[0])
    config = pathlib.Path(os.environ.get('TRIANGULATE_CONFIG', os.path.expanduser('~/.claude/triangulate.conf')))
    configured = entries(config)
    if set(configured) != {'back', 'front', 'app'}:
        raise ValueError('Se requieren roles únicos back/front/app')
    repos = {role: root(pathlib.Path(path)) for role, path in configured.items()}
    if len(set(repos.values())) != 3:
        raise ValueError('Repositorios duplicados')
    role = next((role for role, path in repos.items() if path == pathlib.Path(base).resolve()), None)
    if role is None:
        raise ValueError('Repositorio sin rol explícito')
    relative = pathlib.Path('.claude/worktrees') / f'triangulate-{slug}'
    current = root(repos[role] / relative)
    backend = root(repos['back'] / relative)
    for worktree, owner in ((current, repos[role]), (backend, repos['back'])):
        common = (worktree / git(worktree, 'rev-parse', '--git-common-dir')).resolve(strict=True)
        expected = (owner / git(owner, 'rev-parse', '--git-common-dir')).resolve(strict=True)
        if common != expected:
            raise ValueError(f'Worktree no pertenece al repositorio: {worktree}')
    inside(current, repos[role]); inside(backend, repos['back'])
    inside(directory, current)
    alias_file = pathlib.Path(os.environ.get('TRIANGULATE_CHANGES_CONFIG', os.path.expanduser('~/.claude/triangulate-changes.conf')))
    aliases = entries(alias_file, optional=True)
    for key, value in aliases.items():
        identifier(key); identifier(value)
    selected = aliases.get(slug, slug)
    changes = backend / 'openspec/changes'
    if selected != slug and (changes / slug).exists():
        raise ValueError('Alias contradice autoridad exacta existente')
    authority = inside(changes / selected, backend)
    if not authority.is_dir():
        raise ValueError('Autoridad no es directorio')
    lines = ['HANDOFF DE TRIANGULACIÓN (lectura local; no certifica coordinación viva)',
             'NO AUTORIZA: validar Git, procesos y propietario; reutilizar HELLO/ACK. Sin canal nativo: BLOCKED.',
             'Conservar decisiones aprobadas y PR/integracion/deploy pendientes; push no significa complete.',
             f'slug={slug}  rol={role}', f'openspec canónico: {authority}',
             f'git: {git(current, "status", "--short", "--branch")[:800]}']
    state = authority / 'state.yaml'
    flags = state_flags(state, authority) if state.exists() else {}
    recovery_data = checkpoint(authority, current, slug, role, flags)
    if VERIFY:
        emit('RECOVERY VERIFIED: local v2 snapshot only; NOT live coordination, persistence, integration or completion.\n' + recovery_data)
        raise SystemExit(0)
    lines += ['config: ' + ' '.join(f'{key}: {value}' for key, value in flags.items())[:800],
              recovery_data]
    tasks = authority / 'tasks.md'
    if tasks.exists():
        pending = [line[:160] for line in inside(tasks, authority).read_text().splitlines() if line.startswith('- [ ]')]
        lines += ['PRÓXIMAS PENDIENTES:', *pending[:3]]
    lines += ['Leer propuesta/spec/design/tasks antes de implementar; un escritor por repositorio.',
              'Usar el runtime nativo del cliente; no inferir permisos ni transferir propiedad.',
              'Antes de cerrar: preservar trabajo, commit + push y memoria durable.']
    emit('\n'.join(lines))
except (OSError, ValueError, subprocess.SubprocessError) as error:
    emit(f'BLOCKED: {error}. Sin tareas autorizadas. Verifique repos en TRIANGULATE_CONFIG y autoridad exacta openspec/changes/<slug>; alias literal slug=change en TRIANGULATE_CHANGES_CONFIG (por defecto ~/.claude/triangulate-changes.conf). Nunca elegir otro plan por fecha.')
    raise SystemExit(2)
PY
