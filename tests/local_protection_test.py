"""Isolated integration tests for explicit local Git exclusions."""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "files/shared/bin/harness-local-protect"


class LocalProtectionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.repo = self.home / "repo space"
        self.repo.mkdir()
        self.git("init", "-q")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-qm", "initial", "--allow-empty")
        self.exclude = self.repo / ".git/info/exclude"
        self.exclude.write_bytes(b"# preserved without newline")
        self.receipt = self.home / "receipt.json"

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args])

    def run_tool(self, *args, ok=True):
        result = subprocess.run(["python3", str(TOOL), *map(str, args)], capture_output=True, timeout=5)
        self.assertEqual(result.returncode == 0, ok, result.stderr.decode())
        return result

    def test_prepare_apply_rerun_rollback(self):
        self.exclude.chmod(0o640)
        before = self.exclude.read_bytes()
        head = self.git("rev-parse", "HEAD")
        owned = self.repo / "owned.txt"
        owned.write_bytes(b"pending owner work")
        self.git("add", "owned.txt")
        index = (self.repo / ".git/index").read_bytes()
        self.run_tool("prepare", self.repo, self.receipt)
        self.assertEqual(self.exclude.read_bytes(), before)
        self.run_tool("apply", self.receipt)
        after = self.exclude.read_bytes()
        self.assertEqual(self.exclude.stat().st_mode & 0o777, 0o640)
        self.assertIn(b"\n/.claude/worktrees/\n/.atl/\n", after)
        self.git("check-ignore", "-q", ".claude/worktrees/probe")
        self.git("check-ignore", "-q", ".atl/probe")
        self.run_tool("apply", self.receipt)
        self.assertEqual(self.exclude.read_bytes(), after)
        self.run_tool("rollback", self.receipt)
        self.assertEqual(self.exclude.read_bytes(), before)
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual((self.repo / ".git/index").read_bytes(), index)
        self.assertEqual(owned.read_bytes(), b"pending owner work")

    def test_linked_root_and_concurrent_append(self):
        linked = self.home / "linked space"
        self.git("worktree", "add", "-q", "--detach", str(linked))
        self.exclude.write_bytes(b"/.atl/\n# retained\n")
        self.run_tool("prepare", linked, self.receipt)
        self.run_tool("apply", self.receipt)
        self.assertEqual(self.exclude.read_bytes().count(b"/.atl/"), 1)
        with self.exclude.open("ab") as out:
            out.write(b"# another session\n/other/\n")
        self.run_tool("rollback", self.receipt)
        self.assertEqual(self.exclude.read_bytes(), b"/.atl/\n# retained\n# another session\n/other/\n")
        self.run_tool("rollback", self.receipt)
        with self.exclude.open("ab") as out:
            out.write(b"/.claude/worktrees/\n# new owner\n")
        later = self.exclude.read_bytes()
        self.run_tool("rollback", self.receipt)
        self.assertEqual(self.exclude.read_bytes(), later)

    def test_drift_and_unapplied_rollback_refused(self):
        self.run_tool("prepare", self.repo, self.receipt)
        self.run_tool("rollback", self.receipt, ok=False)
        self.exclude.write_bytes(b"# concurrent modification\n")
        self.run_tool("apply", self.receipt, ok=False)
        self.assertEqual(self.exclude.read_bytes(), b"# concurrent modification\n")
        backup = self.receipt.read_bytes()
        self.run_tool("prepare", self.repo, self.receipt, ok=False)
        self.assertEqual(self.receipt.read_bytes(), backup)

    def test_symlink_directory_and_nonroot_refused(self):
        victim = self.home / "victim"
        victim.write_bytes(b"untouched")
        self.exclude.unlink()
        self.exclude.symlink_to(victim)
        self.run_tool("prepare", self.repo, self.receipt, ok=False)
        self.assertEqual(victim.read_bytes(), b"untouched")
        self.exclude.unlink()
        self.exclude.mkdir()
        self.run_tool("prepare", self.repo, self.receipt, ok=False)
        child = self.repo / "child"
        child.mkdir()
        self.run_tool("prepare", child, self.receipt, ok=False)

    def test_locked_or_replaced_target_refused(self):
        self.run_tool("prepare", self.repo, self.receipt)
        lock = self.exclude.with_name("exclude.lock")
        lock.write_bytes(b"other owner")
        self.run_tool("apply", self.receipt, ok=False)
        self.assertEqual(lock.read_bytes(), b"other owner")
        lock.unlink()
        victim = self.home / "victim"
        victim.write_bytes(self.exclude.read_bytes())
        self.exclude.unlink()
        self.exclude.symlink_to(victim)
        self.run_tool("apply", self.receipt, ok=False)
        self.assertEqual(victim.read_bytes(), b"# preserved without newline")

    def test_no_rules_missing_and_ambiguous_rollback(self):
        self.exclude.write_bytes(b"/.claude/worktrees/\n/.atl/\n")
        self.run_tool("prepare", self.repo, self.receipt)
        self.run_tool("apply", self.receipt)
        self.run_tool("rollback", self.receipt)
        self.assertEqual(self.exclude.read_bytes(), b"/.claude/worktrees/\n/.atl/\n")
        self.receipt = self.home / "second.json"
        self.exclude.write_bytes(b"")
        self.run_tool("prepare", self.repo, self.receipt)
        self.run_tool("apply", self.receipt)
        with self.exclude.open("ab") as out:
            out.write(b"/.atl/\n")
        before = self.exclude.read_bytes()
        self.run_tool("rollback", self.receipt, ok=False)
        self.assertEqual(self.exclude.read_bytes(), before)

    def test_missing_exclude_and_symlink_info(self):
        self.exclude.unlink()
        self.run_tool("prepare", self.repo, self.receipt)
        self.run_tool("apply", self.receipt)
        self.run_tool("rollback", self.receipt)
        self.assertEqual(self.exclude.read_bytes(), b"")
        info = self.exclude.parent
        moved = info.with_name("info-original")
        info.rename(moved)
        info.symlink_to(moved, target_is_directory=True)
        self.run_tool("prepare", self.repo, self.home / "other.json", ok=False)

    def test_cache_age_is_not_deletion_permission(self):
        verifier = (ROOT / "verify.sh").read_text()
        self.assertNotIn('; borrables"', verifier)
        self.assertIn('inspeccionar propietario y uso antes de borrar', verifier)
        self.assertIn('tests/local_protection_test.py', verifier)

    def test_nonregular_application_receipt_refused(self):
        self.run_tool("prepare", self.repo, self.receipt)
        self.run_tool("apply", self.receipt)
        marker = self.receipt.with_name(self.receipt.name + ".applied")
        marker.unlink()
        os.mkfifo(marker)
        self.run_tool("rollback", self.receipt, ok=False)


if __name__ == "__main__":
    unittest.main()
