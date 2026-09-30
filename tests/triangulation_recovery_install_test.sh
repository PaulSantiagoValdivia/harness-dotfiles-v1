#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import copy, importlib.util, json, os, pathlib, subprocess, sys, tempfile
sys.dont_write_bytecode=True
root=pathlib.Path(sys.argv[1]); script=root/'files/shared/lib/install-triangulation-recovery.py'
assert script.exists(), 'missing scoped recovery installer'
spec=importlib.util.spec_from_file_location('recovery_install',script); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
with tempfile.TemporaryDirectory(prefix='recovery install ') as tmp:
    base=pathlib.Path(tmp).resolve()
    def files(home):
        return {str(p.relative_to(home)):(p.read_bytes(),p.stat().st_mode & 0o777) for p in home.rglob('*') if p.is_file()}
    def invoke(home, backup, mode='install', ok=True):
        result=subprocess.run([sys.executable,str(script),mode,str(home),str(backup)],capture_output=True,timeout=20)
        assert (result.returncode == 0) == ok, result.stderr
    for customized in (False,True):
        home=base/str(customized); home.mkdir(); backup=base/(str(customized)+'-backup')
        if customized:
            (home/'.claude/hooks').mkdir(parents=True); (home/'.codex').mkdir()
            data={'model':'operator-model','permissions':{'defaultMode':'default'},'operator':{'keep':True},'hooks':{'SessionStart':[
                {'matcher':'startup|clear','hooks':[{'type':'command','command':'bash ~/.claude/hooks/triangulate-handoff.sh','timeout':17}]},
                {'matcher':'resume','hooks':[{'type':'command','command':'operator-notification'}]}]}}
            (home/'.claude/settings.json').write_text(json.dumps(data)); (home/'.claude/settings.json').chmod(0o640)
            (home/'.claude/CLAUDE.md').write_text('operator prefix\n<!-- gentle-ai:runtime-budget -->\nold managed\n<!-- /gentle-ai:runtime-budget -->\noperator suffix\n')
            (home/'.codex/AGENTS.md').write_text('operator Codex instructions\n')
            (home/'.claude/triangulate-changes.conf').write_text('operator=alias\n')
            (home/'.codex/config.toml').write_text('operator = "preserve"\n')
            for client in ('claude','codex'):
                skill=home/f'.{client}/skills/triangulation-orchestrator'; skill.mkdir(parents=True)
                (skill/'SKILL.md').write_text('previous skill\n'); (skill/'old-reference').write_text('preserve in backup\n')
        before=files(home); invoke(home,backup); installed=files(home); saved=files(backup)
        invoke(home,backup); assert files(home)==installed and files(backup)==saved
        settings=json.loads((home/'.claude/settings.json').read_text()); groups=settings['hooks']['SessionStart']
        handoff=[g for g in groups if any('triangulate-handoff.sh' in h.get('command','') for h in g['hooks'])]
        assert len(handoff)==1 and handoff[0]['matcher']=='startup|resume|clear|compact'
        assert sum(g.get('matcher')=='compact' for g in groups)==1
        if customized:
            for key in ('model','permissions','operator'): assert settings[key]==data[key]
            assert groups[1]==data['hooks']['SessionStart'][1]
            assert handoff[0]['hooks'][0]['timeout']==17
            assert (home/'.claude/CLAUDE.md').read_text().endswith('operator suffix\n')
        for client in ('claude','codex'):
            for source in (root/'files/shared/skills/triangulation-orchestrator').rglob('*'):
                if source.is_file(): assert (home/f'.{client}/skills/triangulation-orchestrator'/source.relative_to(root/'files/shared/skills/triangulation-orchestrator')).read_bytes()==source.read_bytes()
        prompt=(home/'.codex/engram-compact-prompt.md').read_text()
        assert 'triangulate-handoff.sh' in prompt and 'mem_context' not in prompt and 'pending' in prompt
        target=home/'.claude/CLAUDE.md'; current=target.read_bytes(); target.write_text('concurrent operator edit\n')
        drift=files(home); invoke(home,backup,'rollback',False); assert files(home)==drift and files(backup)==saved
        target.write_bytes(current); invoke(home,backup,'rollback'); assert files(home)==before
        invoke(home,backup,'rollback'); assert files(home)==before and files(backup)==saved
    # Preflight failures must leave all target bytes untouched.
    for case in ('duplicate','unknown','malformed','symlink','parent-link','fifo','collision','block'):
        home=base/case; home.mkdir(); backup=base/(case+'-backup'); (home/'.claude').mkdir()
        config=home/'.claude/settings.json'; config.write_text('{}')
        if case in ('duplicate','unknown'):
            hook={'type':'command','command':'bash ~/.claude/hooks/triangulate-handoff.sh'+(' --custom' if case=='unknown' else '')}
            config.write_text(json.dumps({'hooks':{'SessionStart':[{'matcher':'startup|clear','hooks':[hook]*(2 if case=='duplicate' else 1)}]}}))
        if case=='malformed': config.write_text('[]')
        if case=='symlink': config.unlink(); config.symlink_to(base/'False/.claude/settings.json')
        if case=='parent-link': (home/'.codex').symlink_to(base/'False/.claude',target_is_directory=True)
        if case=='fifo': config.unlink(); os.mkfifo(config)
        if case=='collision': backup.mkdir(); (backup/'immutable').write_text('keep')
        if case=='block': (home/'.claude/CLAUDE.md').write_text('<!-- gentle-ai:runtime-budget -->\nunclosed')
        before=files(home); invoke(home,backup,ok=False); assert files(home)==before
    # Deterministic interleaving: plan, external edit, commit must refuse everything.
    home=base/'concurrent'; home.mkdir(); backup=base/'concurrent-backup'
    with tempfile.TemporaryDirectory(dir=base) as stage:
        plan=module.plan(home,pathlib.Path(stage)); (home/'.claude').mkdir(); (home/'.claude/CLAUDE.md').write_text('new external owner\n')
        before=files(home)
        try: module.commit(home,backup,plan)
        except (ValueError,OSError): pass
        else: raise AssertionError('concurrent plan applied')
        assert files(home)==before and not backup.exists()
    legacy = ('<!-- user-override:context-budget -->\n'
        '- `~/.claude/hooks/context-budget.sh` (UserPromptSubmit) avisa a 120k, exige\n  cerrar y compactar a 180k, y declara zona de quemado a 400k.\n'
        'Regla operativa: una unidad de trabajo por sesión, `/clear` al cerrarla. Una\nsesión de 10 horas arrastra el contexto del primer bug hasta el último commit.\noperator suffix\n')
    migrated=module.instructions(legacy.encode(),'claude').decode()
    assert 'ALTO a 300k' in migrated and '`/clear` al cerrarla' not in migrated and 'operator suffix' in migrated
    print('PASS: scoped install fresh/custom/rerun/rollback, immutable backups, concurrent and hostile overlay refusal')
PY
