#!/usr/bin/env python3
"""Real Git, disposable HOME and controlled exporters; never a real remote."""
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / 'files/claude/hooks/engram-git-sync.sh'


class ConcurrentSync(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.src = self.root / 'src'
        self.remote = self.root / 'repo.git'
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), CLAUDE_PROJECT_DIR=str(self.src),
                        PATH=str(self.bin)+':'+os.environ['PATH'], FIXTURE=str(self.root),
                        GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null',
                        GIT_TERMINAL_PROMPT='0', GIT_AUTHOR_NAME='test', GIT_AUTHOR_EMAIL='test@local',
                        GIT_COMMITTER_NAME='test', GIT_COMMITTER_EMAIL='test@local')
        stub = self.bin / 'engram'
        stub.write_text('''#!/usr/bin/env python3
import os,pathlib,sys,time
if '--import' in sys.argv:
 with (pathlib.Path(os.environ['FIXTURE'])/'imports').open('a') as log: log.write('import\\n')
 sys.exit(0)
r=pathlib.Path(os.environ['FIXTURE']); guard=r/'exporting'; owned=False
try: guard.mkdir(); owned=True
except FileExistsError: (r/'overlap').touch()
try:
 if os.environ.get('HOLD')=='1':
  (r/'entered').touch(); deadline=time.monotonic()+10
  while not (r/'release').exists() and time.monotonic()<deadline: time.sleep(.02)
 pathlib.Path('.engram').mkdir(exist_ok=True)
 pathlib.Path('.engram/data').write_text(os.environ.get('VALUE','initial'))
finally:
 if owned: guard.rmdir()
''')
        stub.chmod(0o755)
        self.git('init','--bare','-q',str(self.remote))
        self.git('-C',str(self.remote),'symbolic-ref','HEAD','refs/heads/main')
        self.git('init','-q','-b','main',str(self.src))
        (self.src/'base').write_text('base')
        self.git('-C',str(self.src),'add','base')
        self.git('-C',str(self.src),'commit','-qm','base')
        self.git('-C',str(self.src),'remote','add','origin',str(self.remote))
        self.git('-C',str(self.src),'push','-q','origin','main')

    def git(self,*args):
        return subprocess.check_output(['git',*args],env=self.env,stderr=subprocess.DEVNULL)

    def run_hook(self,**extra):
        return subprocess.run(['bash',str(HOOK),'push'],env=dict(self.env,**extra),
                              stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=8)

    def test_same_checkout_excludes_overlapping_export_then_retries(self):
        self.assertEqual(self.run_hook().returncode,0)
        first=subprocess.Popen(['bash',str(HOOK),'push'],env=dict(self.env,HOLD='1',VALUE='first'),
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'entered').exists() and time.monotonic()<deadline: time.sleep(.02)
            self.assertTrue((self.root/'entered').exists())
            started=time.monotonic(); second=self.run_hook(VALUE='second')
            self.assertEqual(second.returncode,0)
            self.assertLess(time.monotonic()-started,3)
            self.assertFalse((self.root/'overlap').exists(),'two exporters entered the same checkout')
            self.assertIn('diferida',(self.home/'.engram/git-sync.log').read_text())
        finally:
            (self.root/'release').touch()
            self.assertEqual(first.wait(timeout=8),0)
        self.assertEqual(self.run_hook(VALUE='second').returncode,0)
        self.assertEqual(self.git('-C',str(self.remote),'show','engram-sync:.engram/data'),b'second')

    def make_other_origin(self, name):
        remote=self.root/'orgB'/name
        remote.parent.mkdir(exist_ok=True)
        self.git('init','--bare','-q',str(remote))
        self.git('-C',str(remote),'symbolic-ref','HEAD','refs/heads/main')
        self.git('-C',str(self.src),'push','-q',str(remote),'main')
        src=self.root/'srcB'
        self.git('clone','-q',str(remote),str(src))
        return remote,src

    def test_cold_same_basename_origins_defer_then_route_correctly(self):
        remote,src=self.make_other_origin('repo.git')
        first=subprocess.Popen(['bash',str(HOOK),'push'],env=dict(self.env,HOLD='1',VALUE='originA'),
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'entered').exists() and time.monotonic()<deadline: time.sleep(.02)
            self.assertTrue((self.root/'entered').exists())
            self.assertEqual(self.run_hook(CLAUDE_PROJECT_DIR=str(src),VALUE='originB').returncode,0)
            self.assertFalse((self.root/'overlap').exists())
        finally:
            (self.root/'release').touch(); self.assertEqual(first.wait(timeout=8),0)
        self.assertEqual(self.run_hook(CLAUDE_PROJECT_DIR=str(src),VALUE='originB').returncode,0)
        self.assertEqual(self.git('-C',str(self.remote),'show','engram-sync:.engram/data'),b'originA')
        self.assertEqual(self.git('-C',str(remote),'show','engram-sync:.engram/data'),b'originB')

    def test_unrelated_basename_can_progress(self):
        remote,src=self.make_other_origin('different.git')
        first=subprocess.Popen(['bash',str(HOOK),'push'],env=dict(self.env,HOLD='1'),
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'entered').exists() and time.monotonic()<deadline: time.sleep(.02)
            self.assertTrue((self.root/'entered').exists())
            self.assertEqual(self.run_hook(CLAUDE_PROJECT_DIR=str(src),VALUE='independent').returncode,0)
            self.assertEqual(self.git('-C',str(remote),'show','engram-sync:.engram/data'),b'independent')
            self.assertIsNone(first.poll())
        finally:
            (self.root/'release').touch(); self.assertEqual(first.wait(timeout=8),0)

    def test_symlink_lock_refused_without_checkout_mutation(self):
        locks=self.home/'.engram/git-sync-locks'; locks.mkdir(parents=True)
        key=subprocess.check_output(['cksum'],input=b'repo').decode().split()[0]
        sentinel=self.root/'sentinel'; sentinel.write_text('untouched')
        (locks/(key+'.lock')).symlink_to(sentinel)
        self.assertEqual(self.run_hook().returncode,0)
        self.assertFalse((self.home/'.engram-git/repo').exists())
        self.assertEqual(sentinel.read_text(),'untouched')
        self.assertIn('inseguro',(self.home/'.engram/git-sync.log').read_text())

    def test_lock_remains_owned_by_child_after_parent_termination(self):
        first=subprocess.Popen(['bash',str(HOOK),'push'],env=dict(self.env,HOLD='1'),
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'entered').exists() and time.monotonic()<deadline: time.sleep(.02)
            self.assertTrue((self.root/'entered').exists())
            first.terminate()  # Only this fixture's owned process, never a live hook.
            first.wait(timeout=3)
            self.assertEqual(self.run_hook(VALUE='contender').returncode,0)
            self.assertFalse((self.root/'overlap').exists())
            self.assertIn('diferida',(self.home/'.engram/git-sync.log').read_text())
        finally:
            (self.root/'release').touch(); first.wait(timeout=8)
        deadline=time.monotonic()+5
        while (self.root/'exporting').exists() and time.monotonic()<deadline: time.sleep(.02)
        self.assertFalse((self.root/'exporting').exists())
        self.assertEqual(self.run_hook(VALUE='after-exit').returncode,0)
        self.assertEqual(self.git('-C',str(self.remote),'show','engram-sync:.engram/data'),b'after-exit')

    def test_pull_does_not_import_during_export(self):
        self.assertEqual(self.run_hook().returncode,0)
        first=subprocess.Popen(['bash',str(HOOK),'push'],env=dict(self.env,HOLD='1'),
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'entered').exists() and time.monotonic()<deadline: time.sleep(.02)
            self.assertTrue((self.root/'entered').exists())
            before=(self.root/'imports').read_bytes()
            other=subprocess.run(['bash',str(HOOK),'pull'],env=self.env,capture_output=True,timeout=3)
            self.assertEqual(other.returncode,0)
            self.assertEqual((self.root/'imports').read_bytes(),before)
        finally:
            (self.root/'release').touch(); self.assertEqual(first.wait(timeout=8),0)
        lock=next((self.home/'.engram/git-sync-locks').glob('*.lock'))
        self.assertEqual(lock.stat().st_mode&0o777,0o600)
        self.assertEqual(lock.parent.stat().st_mode&0o777,0o700)

    def test_failed_lock_runtime_never_enters_checkout(self):
        stub=self.bin/'python3'; stub.write_text('#!/bin/sh\nexit 1\n'); stub.chmod(0o755)
        self.assertEqual(self.run_hook().returncode,0)
        self.assertFalse((self.home/'.engram-git/repo').exists())
        self.assertIn('lock no disponible',(self.home/'.engram/git-sync.log').read_text())

    def test_lock_precedes_first_clone(self):
        actual_git=shutil.which('git')
        wrapper=self.bin/'git'
        wrapper.write_text("#!/usr/bin/env python3\nimport os,pathlib,sys,time\n"
            "r=pathlib.Path(os.environ['FIXTURE'])\n"
            "if 'clone' in sys.argv and os.environ.get('HOLD_CLONE')=='1':\n"
            " (r/'clone-entered').touch(); end=time.monotonic()+10\n"
            " while not (r/'clone-release').exists() and time.monotonic()<end: time.sleep(.02)\n"
            "elif 'clone' in sys.argv and os.environ.get('SECOND')=='1': (r/'second-clone').touch()\n"
            +f"os.execv({actual_git!r}, [{actual_git!r}, *sys.argv[1:]])\n")
        wrapper.chmod(0o755)
        first=subprocess.Popen(['bash',str(HOOK),'push'],env=dict(self.env,HOLD_CLONE='1'),
                               stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        try:
            deadline=time.monotonic()+5
            while not (self.root/'clone-entered').exists() and time.monotonic()<deadline: time.sleep(.02)
            self.assertTrue((self.root/'clone-entered').exists())
            self.assertEqual(self.run_hook(SECOND='1').returncode,0)
            self.assertFalse((self.root/'second-clone').exists())
        finally:
            (self.root/'clone-release').touch(); self.assertEqual(first.wait(timeout=8),0)


if __name__=='__main__': unittest.main()
