#!/usr/bin/env python3
"""Focused tests for the managed Cocoa DevTools coordination server."""

from __future__ import annotations

import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "files/shared/devtools/cocoa-devtools.py"


def run(*args: str, cwd: Path) -> str:
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def load_server():
    spec = importlib.util.spec_from_file_location("cocoa_devtools", SERVER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {SERVER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CocoaDevToolsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="cocoa-devtools-test-")
        self.root = Path(self.tmp.name)
        self.repos: dict[str, Path] = {}
        self.worktrees: dict[str, Path] = {}

        for role, base in (("back", "dev"), ("front", "dev"), ("app", "dev")):
            origin = self.root / f"{role}-origin.git"
            repo = self.root / role
            subprocess.run(["git", "init", "--bare", str(origin)], check=True, capture_output=True)
            subprocess.run(["git", "init", "-b", base, str(repo)], check=True, capture_output=True)
            run("git", "config", "user.email", "qa@example.com", cwd=repo)
            run("git", "config", "user.name", "QA", cwd=repo)
            (repo / "README.md").write_text(f"{role}\n", encoding="utf-8")
            if role in ("back", "front"):
                package = repo / "functions" if role == "back" else repo
                package.mkdir(exist_ok=True)
                scripts = ("typecheck", "format:check", "lint", "test:unit") if role == "back" else ("check:all",)
                (package / "package.json").write_text(json.dumps({"scripts": dict.fromkeys(scripts, "fixture")}))
            else:
                (repo / "pubspec.yaml").write_text("name: fixture\n")
            run("git", "add", "-A", cwd=repo)
            run("git", "commit", "-m", "chore: initialize", cwd=repo)
            run("git", "remote", "add", "origin", str(origin), cwd=repo)
            run("git", "push", "-u", "origin", base, cwd=repo)

            wt = repo / ".claude/worktrees/triangulate-qa-audit"
            wt.parent.mkdir(parents=True, exist_ok=True)
            run("git", "worktree", "add", "-b", "triangulate/qa-audit", str(wt), cwd=repo)
            self.repos[role] = repo
            self.worktrees[role] = wt

        # Panel has one real commit not yet pushed; backend has dirty work.
        (self.worktrees["front"] / "panel.txt").write_text("ready\n", encoding="utf-8")
        run("git", "add", "panel.txt", cwd=self.worktrees["front"])
        run("git", "commit", "-m", "fix(panel): close qa finding", cwd=self.worktrees["front"])
        (self.worktrees["back"] / "dirty.txt").write_text("unfinished\n", encoding="utf-8")

        self.config = self.root / "triangulate.conf"
        self.config.write_text(
            "\n".join(f"{role}={path}" for role, path in self.repos.items()) + "\n",
            encoding="utf-8",
        )
        # Inject disposable executable runners; production command/result logic executes.
        self.bin = self.root / "bin"
        self.bin.mkdir()
        for tool in ("npm", "flutter"):
            executable = self.bin / tool
            executable.write_text('#!/bin/sh\nprintf "%s:%s\\n" "$PWD" "$*" >> "$VERIFY_LOG"\n')
            executable.chmod(0o755)
        env = mock.patch.dict(os.environ, {"VERIFY_SKIP": "0", "PATH": str(self.bin) + ":" + os.environ["PATH"], "VERIFY_LOG": str(self.root / "commands.log")})
        env.start()
        self.addCleanup(env.stop)
        self.server = load_server()
        self.server.set_state_path(str(self.root / "triangulations.json"))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_discovers_three_repo_triangulation_with_correct_bases(self) -> None:
        self.assertEqual(self.server.ROLE_BASES, {"back": "dev", "front": "dev", "app": "dev"})
        inventory = self.server.discover_inventory(str(self.config))
        self.assertTrue(inventory["worktrees"])
        self.assertTrue(all(item["slug"] for item in inventory["worktrees"]))
        self.assertFalse({str(path.resolve()) for path in self.repos.values()} & {
            item["path"] for item in inventory["worktrees"]
        })
        group = next(item for item in inventory["triangulations"] if item["slug"] == "qa-audit")
        roles = {item["role"]: item for item in group["worktrees"]}

        self.assertEqual(set(roles), {"back", "front", "app"})
        self.assertEqual(roles["back"]["base_ref"], "origin/dev")
        self.assertEqual(roles["front"]["base_ref"], "origin/dev")
        self.assertEqual(roles["app"]["base_ref"], "origin/dev")
        self.assertEqual(roles["back"]["dirty"], 1)
        self.assertEqual(roles["front"]["unpushed"], 1)
        self.assertEqual(roles["back"]["upstream"], "origin/dev")

    def test_restricts_commands_and_blocks_dirty_pushes(self) -> None:
        self.server.set_config_path(str(self.config))
        self.assertTrue(self.server.is_allowed_cwd(str(self.worktrees["front"])))
        self.assertFalse(self.server.is_allowed_cwd(str(self.root / "outside")))

        diff_cmd = self.server.command_for("git-diff", str(self.worktrees["front"]))
        self.assertIn("origin/dev", " ".join(diff_cmd))
        with self.assertRaisesRegex(ValueError, "cambios sin commit"):
            self.server.validate_push(str(self.worktrees["back"]))
        self.server.validate_push(str(self.worktrees["front"]))

    def test_integrated_group_without_recovery_is_not_archived(self) -> None:
        (self.worktrees["back"] / "dirty.txt").unlink()
        for role in ("back", "app"):
            target = self.worktrees[role] / f"{role}-ready.txt"
            target.write_text("verified\n", encoding="utf-8")
            run("git", "add", target.name, cwd=self.worktrees[role])
            run("git", "commit", "-m", f"fix({role}): close qa finding", cwd=self.worktrees[role])

        run("git", "push", "-u", "origin", "HEAD:refs/heads/triangulate/qa-audit", cwd=self.worktrees["front"])
        self.server.set_config_path(str(self.config))
        result = self.server.promote_group_and_archive(
            "qa-audit", [str(self.worktrees[role]) for role in ("back", "front", "app")]
        )

        self.assertFalse(result["ok"])
        self.assertTrue(result["integration_complete"])
        self.assertNotIn("archive", result)
        self.assertEqual({item["role"] for item in result["promoted"]}, {"back", "front", "app"})
        for role in ("back", "front", "app"):
            self.assertEqual(
                run("git", "rev-parse", "HEAD", cwd=self.worktrees[role]),
                run("git", "rev-parse", "refs/heads/dev", cwd=self.root / f"{role}-origin.git"),
            )
        inventory = self.server.discover_inventory(str(self.config))
        self.assertIn("qa-audit", {item["slug"] for item in inventory["triangulations"]})

    def test_promotion_prevalidates_every_repo_before_updating_any_dev(self) -> None:
        before = {
            role: run("git", "rev-parse", "refs/heads/dev", cwd=self.root / f"{role}-origin.git")
            for role in ("back", "front", "app")
        }
        self.server.set_config_path(str(self.config))

        with self.assertRaisesRegex(ValueError, "cambios sin commit"):
            self.server.promote_group_to_dev(
                "qa-audit", [str(self.worktrees[role]) for role in ("back", "front", "app")]
            )

        after = {
            role: run("git", "rev-parse", "refs/heads/dev", cwd=self.root / f"{role}-origin.git")
            for role in ("back", "front", "app")
        }
        self.assertEqual(before, after)

    def test_promotion_never_pushes_a_head_changed_after_prevalidation(self) -> None:
        (self.worktrees["back"] / "dirty.txt").unlink()
        validated_front = run("git", "rev-parse", "HEAD", cwd=self.worktrees["front"])
        original = self.server._run_git_command
        raced_head = ""

        def inject_race(cwd: str, *args: str):
            nonlocal raced_head
            if not raced_head and cwd == str(self.worktrees["front"]) and args[0] == "push":
                race = self.worktrees["front"] / "race.txt"
                race.write_text("not validated\n", encoding="utf-8")
                run("git", "add", race.name, cwd=self.worktrees["front"])
                run("git", "commit", "-m", "fix(front): concurrent unvalidated change", cwd=self.worktrees["front"])
                raced_head = run("git", "rev-parse", "HEAD", cwd=self.worktrees["front"])
            return original(cwd, *args)

        self.server.set_config_path(str(self.config))
        with mock.patch.object(self.server, "_run_git_command", side_effect=inject_race):
            result = self.server.promote_group_to_dev(
                "qa-audit", [str(self.worktrees[role]) for role in ("back", "front", "app")]
            )

        remote_dev = run("git", "rev-parse", "refs/heads/dev", cwd=self.root / "front-origin.git")
        self.assertFalse(result["ok"])
        self.assertTrue(raced_head)
        self.assertEqual(remote_dev, validated_front)
        self.assertNotEqual(remote_dev, raced_head)

    def test_promotion_blocks_when_functional_verification_fails(self) -> None:
        (self.worktrees["back"] / "dirty.txt").unlink()
        before = self.remote_refs()
        self.server.set_config_path(str(self.config))
        (self.bin / "npm").write_text('#!/bin/sh\n[ "$2" != "test:unit" ]\n')
        with self.assertRaisesRegex(ValueError, "verificación funcional falló en back"):
            self.server.promote_group_to_dev("qa-audit", [str(p) for p in self.worktrees.values()])

        after = self.remote_refs()
        self.assertEqual(before, after)

    def test_verification_requires_the_role_directory(self) -> None:
        result = self.server.verify_worktree(str(self.worktrees["front"]), "back")
        self.assertEqual(result["state"], "BLOCKED")
        self.assertFalse(result["executed"])

    def remote_refs(self):
        return {role: run("git", "show-ref", cwd=self.root / f"{role}-origin.git") for role in self.worktrees}

    def test_complete_commands_execute_and_bind_revision(self):
        for role, path in self.worktrees.items():
            if role == "back":
                (path / "dirty.txt").unlink()
            result = self.server.verify_worktree(str(path), role)
            self.assertEqual(result["state"], "PASS")
            self.assertTrue(result["executed"])
            self.assertEqual(result["tested_revision"], run("git", "rev-parse", "HEAD", cwd=path))
        protocol = (ROOT / "files/shared/skills/triangulation-orchestrator/references/protocol.md").read_text()
        for command in ("npm run typecheck && npm run format:check && npm run lint && npm run test:unit", "npm run check:all", "flutter analyze && flutter test"):
            self.assertIn(f"`{command}`", protocol)
        log = (self.root / "commands.log").read_text().splitlines()
        expected = [("back", "functions", c) for c in ("run typecheck", "run format:check", "run lint", "run test:unit")]
        expected += [("front", "", "run check:all"), ("app", "", "analyze"), ("app", "", "test")]
        self.assertEqual(log, [f"{(self.worktrees[r] / d).resolve()}:{c}" for r, d, c in expected])

    def test_skip_and_unknown_states_block_all_remote_refs(self):
        (self.worktrees["back"] / "dirty.txt").unlink()
        self.server.set_config_path(str(self.config))
        before = self.remote_refs()
        with mock.patch.dict(os.environ, {"VERIFY_SKIP": "1"}):
            receipt = self.server.verify_worktree(str(self.worktrees["back"]), "back")
            self.assertEqual(receipt["state"], "SKIPPED")
            self.assertFalse(receipt["executed"])
            with self.assertRaises(ValueError):
                self.server.promote_group_to_dev("qa-audit", [str(p) for p in self.worktrees.values()])
        for state, executed in (("UNKNOWN", True), ("PASS", False), ("TIMEOUT", True)):
            receipt.update(state=state, executed=executed, returncode=0)
            with mock.patch.object(self.server, "verify_worktree", return_value=receipt):
                with self.assertRaises(ValueError):
                    self.server.promote_group_to_dev("qa-audit", [str(p) for p in self.worktrees.values()])
        self.assertEqual(before, self.remote_refs())

    def test_missing_scripts_block_before_execution_or_first_push(self):
        (self.worktrees["back"] / "dirty.txt").unlink()
        package = self.worktrees["back"] / "functions/package.json"
        package.write_text('{}')
        run("git", "add", "functions/package.json", cwd=self.worktrees["back"])
        run("git", "commit", "-m", "test: missing scripts", cwd=self.worktrees["back"])
        self.server.set_config_path(str(self.config))
        before = self.remote_refs()
        result = self.server.verify_worktree(str(self.worktrees["back"]), "back")
        self.assertEqual(result["state"], "BLOCKED")
        self.assertFalse(result["executed"])
        with self.assertRaises(ValueError):
            self.server.promote_group_to_dev("qa-audit", [str(p) for p in self.worktrees.values()])
        self.assertEqual(before, self.remote_refs())
        self.assertFalse((self.root / "commands.log").exists())

    def test_runner_commit_cannot_be_claimed_as_tested_revision(self):
        (self.worktrees["back"] / "dirty.txt").unlink()
        self.server.set_config_path(str(self.config))
        before = self.remote_refs()
        (self.bin / "npm").write_text('#!/bin/sh\ngit -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm "test: runner mutation"\n')
        with self.assertRaises(ValueError):
            self.server.promote_group_to_dev("qa-audit", [str(p) for p in self.worktrees.values()])
        self.assertEqual(before, self.remote_refs())

    def test_timeout_and_missing_tool_are_nonpass(self):
        path = str(self.worktrees["front"])
        original = subprocess.run
        def timeout(command, **kwargs):
            if command[0] != "git":
                raise subprocess.TimeoutExpired(command, 900)
            return original(command, **kwargs)
        with mock.patch.object(self.server.subprocess, "run", side_effect=timeout):
            result = self.server.verify_worktree(path, "front")
        self.assertEqual((result["state"], result["returncode"]), ("TIMEOUT", 124))
        with mock.patch.object(self.server.shutil, "which", return_value=None):
            result = self.server.verify_worktree(path, "front")
        self.assertEqual((result["state"], result["executed"]), ("BLOCKED", False))

    def test_spawn_failure_does_not_claim_execution(self):
        original = subprocess.run
        def missing(command, **kwargs):
            if command[0] != "git":
                raise FileNotFoundError("executable removed after preflight")
            return original(command, **kwargs)
        with mock.patch.object(self.server.subprocess, "run", side_effect=missing):
            result = self.server.verify_worktree(str(self.worktrees["front"]), "front")
        self.assertEqual((result["state"], result["executed"]), ("BLOCKED", False))

    def test_last_runner_cannot_invalidate_earlier_role_before_first_push(self):
        (self.worktrees["back"] / "dirty.txt").unlink()
        self.server.set_config_path(str(self.config))
        before = self.remote_refs()
        (self.bin / "flutter").write_text(f'#!/bin/sh\ngit -C "{self.worktrees["front"]}" commit --allow-empty -qm "test: concurrent commit"\n')
        with self.assertRaises(ValueError):
            self.server.promote_group_to_dev("qa-audit", [str(p) for p in self.worktrees.values()])
        self.assertEqual(before, self.remote_refs())

    def test_remote_rejection_does_not_archive_partial_publication(self):
        (self.worktrees["back"] / "dirty.txt").unlink()
        self.server.set_config_path(str(self.config))
        hook = self.root / "front-origin.git/hooks/pre-receive"
        hook.write_text('#!/bin/sh\nwhile read old new ref; do [ "$ref" != refs/heads/dev ] || exit 1; done\n')
        hook.chmod(0o755)
        result = self.server.promote_group_and_archive("qa-audit", [str(p) for p in self.worktrees.values()])
        self.assertFalse(result["ok"])
        self.assertEqual(result["failed"]["role"], "front")
        self.assertEqual(result["promoted"][0]["role"], "back")
        inventory = self.server.discover_inventory(str(self.config))
        self.assertIn("qa-audit", {g["slug"] for g in inventory["triangulations"]})

    def test_ignores_prunable_worktrees_whose_directory_no_longer_exists(self) -> None:
        stale = self.repos["back"] / ".claude/worktrees/triangulate-stale"
        run(
            "git", "worktree", "add", "-b", "triangulate/stale", str(stale),
            cwd=self.repos["back"],
        )
        shutil.rmtree(stale)

        worktrees = self.server.parse_worktrees(str(self.repos["back"]), "back")

        self.assertNotIn(str(stale.resolve()), {item["path"] for item in worktrees})

    def test_free_text_cannot_close_unverified_work(self):
        self.server.set_config_path(str(self.config))
        with self.assertRaises(ValueError):
            self.server.set_triangulation_archived("qa-audit", "all complete; user owns pending verification")
        self.assertEqual(self.server.load_archive_state()["archived"], {})

    def test_archives_closed_triangulation_without_deleting_recovery_worktrees(self) -> None:
        self.server.set_config_path(str(self.config))
        # Registry lifecycle only; verifier is covered separately, not certified here.
        with mock.patch.object(self.server, "verify_closure", return_value={"state":"PASS"}):
            receipt = self.server.set_triangulation_archived(
                "qa-audit", "backend PR #1, panel PR #2, app sin cambios"
            )
        inventory = self.server.discover_inventory(str(self.config))

        self.assertEqual(receipt["status"], "archived")
        self.assertNotIn("qa-audit", {item["slug"] for item in inventory["triangulations"]})
        archived = next(
            item for item in inventory["archived_triangulations"] if item["slug"] == "qa-audit"
        )
        self.assertIn("panel PR #2", archived["archive"]["evidence"])
        self.assertTrue(all(path.is_dir() for path in self.worktrees.values()))

        self.server.set_triangulation_archived("qa-audit", "", False)
        restored = self.server.discover_inventory(str(self.config))
        self.assertIn("qa-audit", {item["slug"] for item in restored["triangulations"]})

    def test_corrupt_archive_registry_fails_closed_without_overwriting_evidence(self) -> None:
        state_path = self.root / "triangulations.json"
        corrupt = '{"version": 1, "archived": '
        state_path.write_text(corrupt, encoding="utf-8")
        front_dev = run(
            "git", "rev-parse", "refs/heads/dev", cwd=self.root / "front-origin.git"
        )

        with self.assertRaisesRegex(ValueError, "JSON inválido"):
            self.server.promote_group_and_archive(
                "qa-audit", [str(self.worktrees[role]) for role in ("back", "front", "app")]
            )

        with self.assertRaisesRegex(ValueError, "JSON inválido"):
            self.server.set_triangulation_archived("qa-audit", "PR #123")

        self.assertEqual(state_path.read_text(encoding="utf-8"), corrupt)
        self.assertEqual(
            run("git", "rev-parse", "refs/heads/dev", cwd=self.root / "front-origin.git"),
            front_dev,
        )


if __name__ == "__main__":
    unittest.main()
