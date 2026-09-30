#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1])
patcher = root / 'files/shared/lib/install-registry-hooks.py'
with tempfile.TemporaryDirectory(prefix='registry root ') as tmp:
    home = pathlib.Path(tmp) / 'home'; home.mkdir()
    bins = home / 'bin'; bins.mkdir()
    log = home / 'calls.log'
    gentle = bins / 'gentle-ai'
    gentle.write_text('#!/bin/sh\nwhile [ "$1" != --cwd ]; do shift; done\nprintf "%s\\n" "$2" >> "$REGISTRY_LOG"\nmkdir -p "$2/.atl"\n')
    gentle.chmod(0o755)
    env = {**os.environ, 'HOME': str(home), 'PATH': str(bins)+':'+os.environ['PATH'], 'REGISTRY_LOG': str(log)}
    config = home / '.claude/settings.json'; config.parent.mkdir()
    data = json.loads((root / 'files/claude/settings.json').read_text())
    data['hooks']['SessionStart'][0]['hooks'][0]['command'] = 'gentle-ai skill-registry refresh --quiet --no-gitignore --cwd "$PWD" || true'
    data['operator'] = {'preserve': True}; config.write_text(json.dumps(data))
    original = config.read_bytes(); backup = home / 'backup'
    def install(expect=0):
        p = subprocess.run(['python3', str(patcher), str(home), str(backup)], capture_output=True, env=env, timeout=10)
        assert p.returncode == expect, p.stderr
    install(); installed = config.read_bytes(); install(); assert config.read_bytes() == installed
    helper = home / ".local/bin/skill-registry-refresh"
    helper.chmod(0o644); install(); assert os.access(helper, os.X_OK)
    expected = json.loads(original)
    expected['hooks']['SessionStart'][0]['hooks'][0]['command'] = '"$HOME/.local/bin/skill-registry-refresh" "${CLAUDE_PROJECT_DIR:-$PWD}"'
    assert json.loads(installed) == expected
    commands = []
    for client, filename in (('claude','settings.json'), ('codex','hooks.json')):
        p = home / f'.{client}/{filename}'
        document = json.loads(p.read_text())
        commands += [h['command'] for g in document['hooks']['SessionStart'] for h in g['hooks'] if 'skill-registry' in h.get('command','')]
    assert len(commands) == 2 and all('skill-registry-refresh' in c for c in commands)
    repo = home / 'repo space'; subprocess.run(['git','init','-q',str(repo)],check=True)
    subprocess.run(['git','-C',str(repo),'-c','user.name=Fixture','-c','user.email=fixture@example.invalid','commit','--allow-empty','-qm','initial'],check=True)
    linked = home / 'linked space'; subprocess.run(['git','-C',str(repo),'worktree','add','-q','--detach',str(linked)],check=True)
    alias = home / 'alias'; alias.symlink_to(linked, target_is_directory=True)
    outside = home / 'outside'; outside.mkdir()
    for checkout in (repo, linked): (checkout / 'functions/src').mkdir(parents=True)
    for command in commands:
        for cwd, target in ((repo/'functions/src',repo),(linked/'functions/src',linked),(alias/'functions/src',linked),(home,home),(outside,None)):
            log.unlink(missing_ok=True)
            p = subprocess.run(['bash','-c',command],cwd=cwd,env={**env,'CLAUDE_PROJECT_DIR':str(cwd)},capture_output=True)
            assert p.returncode == 0, p.stderr
            assert (log.read_text().strip() == str(target.resolve())) if target else not log.exists()
            if cwd != home: assert not (cwd / '.atl').exists()
    fake_git = bins / 'git'; fake_git.write_text('#!/bin/sh\nexit 71\n'); fake_git.chmod(0o755)
    log.unlink(missing_ok=True)
    p = subprocess.run(['bash','-c',commands[0]],cwd=repo/'functions/src',env={**env,'CLAUDE_PROJECT_DIR':str(repo/'functions/src')},capture_output=True)
    assert not log.exists() and b'SKIPPED' in p.stderr and p.returncode == 0
    fake_git.write_text('#!/bin/sh\ncase "$*" in *--show-toplevel*) exit 71;; esac\nexec /usr/bin/git "$@"\n')
    p = subprocess.run(['bash','-c',commands[0]],cwd=repo/'functions/src',env={**env,'CLAUDE_PROJECT_DIR':str(repo/'functions/src')},capture_output=True)
    assert not log.exists() and b'SKIPPED' in p.stderr
    fake_git.unlink()
    gentle.write_text('#!/bin/sh\nexit 23\n')
    p = subprocess.run(['bash','-c',commands[0]],cwd=repo,env={**env,'CLAUDE_PROJECT_DIR':str(repo)},capture_output=True)
    assert p.returncode == 0 and b'BLOCKED' in p.stderr
    saved = backup / 'claude-settings.json'
    assert saved.read_bytes() == original
    config.write_bytes(saved.read_bytes()); assert config.read_bytes() == original
    # Unknown producers are not silently rewritten; no partial config mutation.
    invalid = json.loads(config.read_text()); invalid['hooks']['SessionStart'][0]['hooks'][0]['command'] = 'gentle-ai skill-registry refresh --custom'
    config.write_text(json.dumps(invalid)); before = config.read_bytes()
    install(expect=1); assert config.read_bytes() == before
    for malformed in ('[]', '{"hooks":{"SessionStart":{}}}', json.dumps({'hooks': {'SessionStart': [{'hooks': [expected['hooks']['SessionStart'][0]['hooks'][0]] * 2}]}})):
        config.write_text(malformed); before = config.read_bytes()
        install(expect=1); assert config.read_bytes() == before
    config.unlink(); os.mkfifo(config)
    install(expect=1); assert not config.is_file()
    config.unlink()
    fresh = home / 'fresh'; fresh.mkdir()
    subprocess.run(['python3',str(patcher),str(fresh),str(home/'fresh-backup')],check=True)
    assert (fresh/'.claude/settings.json').exists() and (fresh/'.codex/hooks.json').exists()
    assert json.loads((fresh/'.codex/hooks.json').read_text())['hooks']['SessionStart'][0]['hooks'][0]['timeout'] == 30
    verify = (root/'verify.sh').read_text()
    block = 'for client in claude codex; do\n  registry_config=' + verify.split('for client in claude codex; do\n  registry_config=',1)[1].split('\ndone',1)[0] + '\ndone'
    subprocess.run(['bash','-ec','check() { shift; "$@"; }; ' + block],env={**env,'HOME':str(fresh)},check=True,capture_output=True)
    bootstrap = (root / 'bootstrap.sh').read_text()
    assert bootstrap.index('install-registry-hooks.py') > bootstrap.index('gentle-ai install')
    print('PASS: both registry hooks target main/linked physical roots, HOME only, error skip; scoped preservation/rerun/backup/unknown refusal')
PY
