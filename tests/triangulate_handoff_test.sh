#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import os, pathlib, subprocess, sys, tempfile, time
root = pathlib.Path(sys.argv[1])
hook = root / 'files/claude/hooks/triangulate-handoff.sh'
with tempfile.TemporaryDirectory(prefix='handoff space ') as tmp:
    home = pathlib.Path(tmp)
    config, aliases = home / 'repos.conf', home / 'changes.conf'
    repos, worktrees = {}, {}
    for role in ('back', 'front', 'app'):
        repo = home / role
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        subprocess.run(['git', '-C', str(repo), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'initial', '--allow-empty'], check=True)
        wt = repo / '.claude/worktrees/triangulate-example'
        subprocess.run(['git', '-C', str(repo), 'worktree', 'add', '-q', '--detach', str(wt)], check=True)
        repos[role], worktrees[role] = repo, wt
    config.write_text(''.join(f'{role}={path}\n' for role, path in repos.items()))
    changes = worktrees['back'] / 'openspec/changes'
    other = changes / 'unrelated-newest'
    other.mkdir(parents=True)
    (other / 'tasks.md').write_text('- [ ] NEVER SUGGEST THIS\n')
    elapsed = []
    def run(role='front', blocked=False, directory=None, verify=False):
        env = {**os.environ, 'HOME': str(home), 'TRIANGULATE_CONFIG': str(config), 'TRIANGULATE_CHANGES_CONFIG': str(aliases), 'CLAUDE_PROJECT_DIR': str(directory or worktrees[role])}
        start = time.monotonic()
        result = subprocess.run(['bash', str(hook), *(['--verify'] if verify else [])], env=env, cwd=home, capture_output=True, timeout=10)
        elapsed.append(time.monotonic() - start)
        out = result.stdout.decode()
        assert len(result.stdout) <= 4000
        if blocked:
            assert 'BLOCKED' in out and 'PRÓXIMAS' not in out and 'NEVER SUGGEST' not in out, (out, result.stderr)
            assert result.returncode != 0
        else:
            assert result.returncode == 0, (out, result.stderr)
        return out
    run(blocked=True)
    exact = changes / 'example'
    exact.mkdir()
    (exact / 'tasks.md').write_text('- [x] done\n- [ ] expected task\n')
    for role in worktrees:
        out = run(role)
        assert str(exact) in out and f'rol={role}' in out and 'expected task' in out, out
    # An authority directory alone must never pass the explicit recovery probe.
    run(verify=True, blocked=True)
    out = run(directory=worktrees['front'].relative_to(home))
    assert 'expected task' in out
    aliases.write_text('example=unrelated-newest\n')
    run(blocked=True)
    (exact / 'tasks.md').unlink(); exact.rmdir()
    out = run()
    assert str(other) in out and 'NEVER SUGGEST THIS' in out
    aliases.write_text('example=unrelated-newest\nexample=unrelated-newest\n')
    run(blocked=True)
    aliases.write_text('example=../outside\n')
    run(blocked=True)
    aliases.write_text('example=missing\n')
    run(blocked=True)
    aliases.write_text('example=escape\n')
    (changes / 'escape').symlink_to(home, target_is_directory=True)
    run(blocked=True)
    aliases.unlink()
    aliases.mkdir()
    run(blocked=True)
    aliases.rmdir()
    config.write_text(config.read_text() + f'back={repos["back"]}\n')
    run(blocked=True)
    config.write_text(''.join(f'{role}={path}\n' for role, path in repos.items()))
    aliases.write_text('example=unrelated-newest\n')
    (other / 'tasks.md').write_text('- [ ] ' + 'é' * 10000 + '\n')
    assert len(run().encode()) <= 4000
    gitfile = worktrees['front'] / '.git'
    original = gitfile.read_bytes(); gitfile.write_text('gitdir: /missing\n')
    run(blocked=True)
    gitfile.write_bytes(original)
    gitfile.rename(gitfile.with_name('saved-git'))
    run(blocked=True)  # ancestor discovery cannot validate an ordinary directory
    subprocess.run(['git', 'init', '-q', str(worktrees['front'])], check=True)
    run(blocked=True)  # unrelated nested repository must not impersonate the role
    import shutil
    shutil.rmtree(gitfile)
    gitfile.with_name('saved-git').rename(gitfile)
    # Recovery facts are bounded data, never permission or an executable packet.
    import copy, hashlib, json
    aliases.unlink(); exact.mkdir()
    (exact / 'specs/context').mkdir(parents=True)
    for name in ('proposal.md', 'design.md', 'tasks.md', 'specs/context/spec.md'):
        (exact / name).write_text('contract\n')
    state = exact / 'state.yaml'
    state.write_text('mode: auto\ndelivery_strategy: auto-chain\nchain_strategy: feature-branch-chain\n')
    assert 'mode: auto' in run()
    state.write_text('mode: auto\nexecution_mode: interactive\n'); run(blocked=True)
    state.write_text('execution_mode: auto\n'); assert 'mode: auto' in run()
    state.write_text('mode: invalid\n'); run(blocked=True)
    state.write_text('mode: auto\nmode: auto\n'); run(blocked=True)
    state.write_text('mode: auto\n')
    recovery = exact / 'recovery'; recovery.mkdir()
    checkpoint = recovery / 'front.json'
    head = subprocess.check_output(['git', '-C', str(worktrees['front']), 'rev-parse', 'HEAD'], text=True).strip()
    valid = dict(version=1, slug='example', role='front', authority=str(exact.resolve()),
        worktree=str(worktrees['front'].resolve()), branch='HEAD', revision=head, dirty=True,
        observed_at='2026-09-09T22:00:00Z', execution_mode='auto', delivery_strategy='auto-chain',
        chain_strategy='feature-branch-chain', task='split pending PR', next_action='inspect existing tool',
        owner=dict(identity='native-panel-1', status='active'),
        process=dict(handle='tool-123', status='running', observed_at='2026-09-09T22:00:00Z'),
        receipts=[dict(path=str(exact/'tasks.md'), revision=head)], pending_delivery=['PR split pending'],
        blocker=dict(kind='tool', evidence='existing tool still running', observed_at='2026-09-09T22:00:00Z'),
        artifact_hashes={name:hashlib.sha256((exact/name).read_bytes()).hexdigest()
            for name in ('proposal.md', 'design.md', 'tasks.md', 'specs/context/spec.md')})
    def check(data=None, raw=None, invalid=False):
        checkpoint.write_text(raw if raw is not None else json.dumps(valid if data is None else data))
        out = run()
        assert len(out.encode()) < 3999 and 'NO AUTORIZA' in out, out
        assert ('RECOVERY UNAVAILABLE' in out) == invalid, out
        if invalid:
            assert 'split pending PR' not in out, out
        return out
    out = check()
    print(f'OBSERVED: valid checkpoint hook {elapsed[-1]:.3f}s; disposable fixture, excludes repository setup')
    for term in ('split pending PR', 'tool-123', 'PR split pending', 'native-panel-1', 'dirty'):
        assert term in out, (term, out)
    mutations = [('version',2), ('version',True), ('role','back'), ('slug','wrong'),
        ('worktree',str(home)), ('authority',str(home)), ('branch','stale'), ('revision','0'*40),
        ('dirty','yes'), ('task','control\x00'), ('execution_mode','interactive'),
        ('delivery_strategy','invalid'), ('chain_strategy','invalid'), ('observed_at','yesterday'),
        ('owner',dict(identity='x',status='invalid')), ('process',dict(handle='x',status='running')),
        ('blocker',dict(kind='invalid',evidence='x',observed_at=valid['observed_at'])),
        ('receipts',[dict(path=str(home),revision=head)]), ('pending_delivery',['x']*17),
        ('artifact_hashes',{}), ('extra','unexpected'), ('task','é'*513)]
    for key, value in mutations:
        bad_data=copy.deepcopy(valid); bad_data[key]=value; check(bad_data, invalid=True)
    for raw in ('{', '[]', '{"version":1,"version":1}', ' '*8193, json.dumps(valid).replace('"version": 1','"version": NaN')):
        check(raw=raw, invalid=True)
    bad_data=copy.deepcopy(valid); bad_data['artifact_hashes']['tasks.md']='0'*64
    check(bad_data, invalid=True)
    (exact/'tasks.md').write_text('contract changed\n'); check(invalid=True)
    (exact/'tasks.md').write_text('contract\n')
    bad_data=copy.deepcopy(valid); bad_data['next_action']='$(touch '+str(home/'must-not-exist')+')'
    check(bad_data); assert not (home/'must-not-exist').exists()
    checkpoint.unlink(); checkpoint.symlink_to(exact/'tasks.md'); assert 'RECOVERY UNAVAILABLE' in run()
    checkpoint.unlink(); recovery.rmdir(); recovery.symlink_to(home, target_is_directory=True)
    assert 'RECOVERY UNAVAILABLE' in run(); recovery.unlink(); recovery.mkdir()
    assert 'RECOVERY UNAVAILABLE' in run() and str(exact) in run()
    checkpoint.write_text(json.dumps(valid)); (exact/'tasks.md').unlink(); (exact/'tasks.md').symlink_to(home/'missing')
    assert 'RECOVERY UNAVAILABLE' in run()
    (exact/'tasks.md').unlink(); (exact/'tasks.md').write_text('contract\n')
    bad_data=copy.deepcopy(valid); bad_data['receipts']=[dict(path=str(exact/'escape-receipt'),revision=head)]
    (exact/'escape-receipt').symlink_to(home); check(bad_data, invalid=True)
    # Boundary triangulation and complete decision recovery.
    raw=json.dumps(valid); check(raw=raw+' '*(8192-len(raw)))
    check(raw=raw+' '*(8193-len(raw)), invalid=True)
    check(raw=json.dumps(valid).replace('"identity": "native-panel-1"', '"identity": "native-panel-1", "identity": "other"'), invalid=True)
    check(raw='['*2000+']'*2000, invalid=True)
    (exact/'design.md').write_bytes(b'x'*262145); check(invalid=True)
    (exact/'design.md').write_text('contract\n')
    checkpoint.unlink(); os.mkfifo(checkpoint); assert 'RECOVERY UNAVAILABLE' in run(); checkpoint.unlink()
    bad_data=copy.deepcopy(valid); bad_data['process']['handle']=''; check(bad_data, invalid=True)
    out=check(); assert 'auto-chain' in out and 'feature-branch-chain' in out, out
    state.write_text('mode: auto"\n'); run(blocked=True); state.write_text('mode: auto\n')
    large=copy.deepcopy(valid); large['pending_delivery']=['é'*150]*16
    out=check(raw=json.dumps(large, ensure_ascii=False))
    assert 'TRUNCATED' in out and str(checkpoint.resolve()) in out and 'NO AUTORIZA' in out, out
    # v2: preserve scoped waits, never upgrade ACK to completion.
    v2=copy.deepcopy(valid); v2['version']=2
    v2['coordination']=dict(phase='receipt_pending', wait=dict(kind='peer',
        owner='native-app-1', request_id='receipt-app-1', event='receipt response',
        mechanism='native_reply', handle='observed-message-1', scope='app receipt only',
        started_at='2026-09-09T22:00:00Z', deadline='2026-09-09T22:02:00Z',
        next_action='validate receipt then resume integration'))
    out=check(v2)
    for term in ('native-app-1', 'receipt-app-1', 'receipt_pending', 'wait_expired'):
        assert term in out, out
    for key, val in [('owner',''), ('request_id',''), ('event',''), ('handle',''),
                     ('scope',''), ('next_action',''), ('mechanism','poll'),
                     ('deadline','2026-09-09T21:00:00Z'), ('started_at','yesterday')]:
        bad=copy.deepcopy(v2); bad['coordination']['wait'][key]=val; check(bad,invalid=True)
    for phase in ('complete','done','ACK'):
        bad=copy.deepcopy(v2); bad['coordination']['phase']=phase; check(bad,invalid=True)
    bad=copy.deepcopy(v2); bad['coordination']['wait']={}; check(bad,invalid=True)
    ack=copy.deepcopy(v2); ack['coordination']=dict(phase='acknowledged',wait={})
    assert 'acknowledged' in check(ack)
    human=copy.deepcopy(v2); human['coordination']['wait'].update(kind='human',
        mechanism='user_response',handle='device-acceptance-request',scope='device smoke only')
    assert 'device smoke only' in check(human)
    bad=copy.deepcopy(human); bad['coordination']['wait']['mechanism']='native_reply'; check(bad,invalid=True)
    ready=copy.deepcopy(v2); ready['coordination']=dict(phase='validated',wait={})
    ready['dirty']=False; ready['blocker']['kind']='none'
    assert 'validated' in check(ready)
    bad=copy.deepcopy(ready); bad['receipts'][0]['revision']='0'*40; check(bad,invalid=True)
    dirty_file=worktrees['front']/'uncommitted-v2.txt'; dirty_file.write_text('changed')
    check(ready,invalid=True); dirty_file.unlink()
    for key,val in [('dirty',True),('receipts',[])]:
        bad=copy.deepcopy(ready); bad[key]=val; check(bad,invalid=True)
    assert 'LEGACY_WAIT_UNVERIFIED' in check(valid)
    run(verify=True, blocked=True)
    check(ack)
    assert 'RECOVERY VERIFIED' in run(verify=True)
    check(raw='{', invalid=True)
    run(verify=True, blocked=True)
    run(directory=home, verify=True, blocked=True)
    assert run(directory=home) == ''
    print('PASS: checkpoint schema, bounds, paths, identities, hashes, modes and pending delivery')
    print('PASS: exact/alias authority, all roles, blocked invalid mappings/Git, paths and output budget')
PY

# Exercise scoped deployment against disposable homes, never the installed HOME.
source "$ROOT/files/shared/lib/install-shared-skill.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/handoff-install.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
SKILL="$ROOT/files/shared/skills/triangulation-orchestrator"
for mode in fresh customized; do
  home="$TMP/$mode home"; saved="$TMP/$mode backup"
  mkdir -p "$home/.claude/hooks" "$home/.codex" "$saved"
  printf 'operator mapping\n' > "$home/.claude/triangulate-changes.conf"
  printf 'operator preference\n' > "$home/.codex/config.toml"
  if [ "$mode" = customized ]; then
    printf 'old hook\n' > "$home/.claude/hooks/triangulate-handoff.sh"
    for client in claude codex; do
      mkdir -p "$home/.$client/skills/triangulation-orchestrator"
      printf 'custom skill\n' > "$home/.$client/skills/triangulation-orchestrator/SKILL.md"
    done
  fi
  for _attempt in 1 2; do
    dest="$home/.claude/hooks/triangulate-handoff.sh"
    if ! cmp -s "$ROOT/files/claude/hooks/triangulate-handoff.sh" "$dest"; then
      [ ! -e "$dest" ] || cp -a "$dest" "$saved/handoff.sh"
      cp -a "$ROOT/files/claude/hooks/triangulate-handoff.sh" "$dest"
    fi
    install_shared_skill "$SKILL" "$home" "$saved"
    cmp "$ROOT/files/claude/hooks/triangulate-handoff.sh" "$dest"
    for client in claude codex; do
      diff -qr "$SKILL" "$home/.$client/skills/triangulation-orchestrator"
    done
  done
  grep -qx 'operator mapping' "$home/.claude/triangulate-changes.conf"
  grep -qx 'operator preference' "$home/.codex/config.toml"
  if [ "$mode" = customized ]; then
    cp -a "$saved/handoff.sh" "$dest"
    grep -qx 'old hook' "$dest"
    for client in claude codex; do
      target="$home/.$client/skills/triangulation-orchestrator"
      rm -rf "$target"; cp -a "$saved/$client/triangulation-orchestrator" "$target"
      grep -qx 'custom skill' "$target/SKILL.md"
    done
  fi
done
printf 'PASS: scoped hook/shared protocol parity, rerun, backups/restore, mappings/preferences preserved\n'
