#!/usr/bin/env python3
"""Closure parsing/dispatch fixtures; mocked provider responses are not live proof."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('closure', ROOT/'files/shared/devtools/cocoa-devtools.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as tmp:
    home = Path(tmp)
    repos = {r:str(home/r) for r in ('back','front','app')}
    wts = {r:Path(p)/'.claude/worktrees/triangulate-fixture' for r,p in repos.items()}
    authority = wts['back']/'openspec/changes/fixture'
    (authority/'recovery').mkdir(parents=True)
    head = 'a'*40
    reports, checkpoints = {}, {}
    for role, wt in wts.items():
        wt.mkdir(parents=True, exist_ok=True)
        log = wt/'test.log'; log.write_text('fixture output, not real QA')
        reports[role] = dict(role=role, revision=head, status='complete', remaining=[], checks=[
            dict(name=name,state='PASS',revision=head,path=str(log),sha256=hashlib.sha256(log.read_bytes()).hexdigest())
            for name in (['functional','contract','device'] if role=='app' else ['functional','contract'])])
        checkpoints[role] = dict(revision=head,coordination=dict(phase='validated',wait={}),
            blocker=dict(kind='none'),pending_delivery=[],artifact_hashes={'tasks.md':'fixture'},
            receipts=[dict(path=str(wt/'receipt.json'))])
    def write():
        for r in repos:
            (wts[r]/'receipt.json').write_text(json.dumps(reports[r]))
            (authority/'recovery'/f'{r}.json').write_text(json.dumps(checkpoints[r]))
    def process(argv, **kw):
        if argv[0] == 'git':
            return subprocess.CompletedProcess(argv,0,head+'\trefs/heads/dev\n','')
        role = next(r for r in repos if str(wts[r]) == kw['cwd'])
        return subprocess.CompletedProcess(argv,0,f'RECOVERY VERIFIED\nRECOVERY DATA {authority}/recovery/{role}.json (recorded; inspect dirty bytes): {{}}','')
    def git(cwd,*args,**kw):
        return 'feature' if args[0]=='branch' else head
    with mock.patch.object(m,'load_repo_config',return_value=repos), \
         mock.patch.object(m,'validate_push'), mock.patch.object(m,'_git',side_effect=git), \
         mock.patch.object(m,'verify_worktree',return_value=dict(state='PASS',executed=True,returncode=0,tested_revision=head)), \
         mock.patch.object(m.subprocess,'run',side_effect=process):
        write(); assert m.verify_closure('fixture')['state']=='PASS'
        for field,value in [('remaining',['user must verify']),('revision','b'*40),
                            ('status','blocked'),('merged_pr',371),('checks',[])]:
            original=copy.deepcopy(reports['app']); reports['app'][field]=value; write()
            assert m.verify_closure('fixture')['state']=='BLOCKED', (field,value)
            reports['app']=original
        for field,value in [('state','SKIPPED'),('revision','b'*40),('sha256','0'*64)]:
            old=reports['app']['checks'][0][field]; reports['app']['checks'][0][field]=value; write()
            assert m.verify_closure('fixture')['state']=='BLOCKED'
            reports['app']['checks'][0][field]=old
        for field,value in [('pending_delivery',['release build']),('blocker',{'kind':'dependency'}),
                            ('coordination',{'phase':'blocked','wait':{'owner':'user'}})]:
            old=checkpoints['app'][field]; checkpoints['app'][field]=value; write()
            assert m.verify_closure('fixture')['state']=='BLOCKED'
            checkpoints['app'][field]=old
        write()
        with mock.patch.object(m,'verify_worktree',return_value={'state':'SKIPPED'}):
            assert m.verify_closure('fixture')['state']=='BLOCKED'
        with mock.patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],2,'','')):
            assert m.verify_closure('fixture')['state']!='PASS'
        with mock.patch.object(m.subprocess,'run',side_effect=PermissionError('native boundary')):
            assert m.verify_closure('fixture')['state']=='UNVERIFIED'
        with mock.patch.object(m,'_git',side_effect=ValueError('untracked/stale git artifact')):
            assert m.verify_closure('fixture')['state']=='BLOCKED'
        def unpushed(argv, **kw):
            result=process(argv, **kw)
            if argv[0]=='git' and argv[-1]=='refs/heads/feature':
                result.stdout='b'*40+'\trefs/heads/feature\n'
            return result
        with mock.patch.object(m.subprocess,'run',side_effect=unpushed):
            assert m.verify_closure('fixture')['state']=='BLOCKED'
        path=wts['app']/'receipt.json'
        path.write_text(path.read_text().replace('"status": "complete"','"status": "blocked", "status": "complete"'))
        assert m.verify_closure('fixture')['state']=='BLOCKED'
        write()
        # No request-provided status can replace the internal verifier result.
        m.set_state_path(str(home/'registry.json'))
        with mock.patch.object(m,'verify_closure',return_value={'state':'UNVERIFIED'}):
            try: m.set_triangulation_archived('fixture','PASS all done')
            except ValueError: pass
            else: raise AssertionError('free text bypassed verifier')
        assert m.load_archive_state()['archived']=={}
print('PASS: closure evidence fixtures; provider and hook mocked, live adoption unverified')
