#!/usr/bin/env python3
"""Contrato T3/T4: sólo fixtures Git temporales y Claude stub; nunca memoria real."""

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / "files/shared/bin"
TOOL = BIN / "memory-consolidate"
PLIST = ROOT / "files/shared/launchd/com.cocoa.memory-consolidate.plist"
DATE = datetime.now(timezone.utc).date().isoformat()
BRANCH = "proposal/" + DATE


def proposal(operations=None, suggestions=None):
    return {"operations": operations or [], "merge_suggestions": suggestions or [],
            "summary": "Archivar estado resuelto, mejorar búsqueda y gancho."}


def happy():
    return proposal([
        {"op": "archive_index_entry", "file": "a.md", "reason": "RESUELTO"},
        {"op": "add_aliases", "file": "b.md", "aliases": ["reglas", "rules"]},
        {"op": "reword_index_line", "file": "c.md", "line": "- [Referencia](c.md) — activa"},
    ], [{"files": ["d.md", "e.md"], "rationale": "posible solapamiento; sólo informar"}])


class ConsolidateTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="consolidate-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.memory = self.root / "memory"
        self.state = self.root / "state"
        self.memory.mkdir()
        self.home = self.root / "home"
        self.home.mkdir()
        self.stub = self.root / "claude-stub"
        self.output = self.root / "output.json"
        self.args_log = self.root / "args.json"
        self.prompt_log = self.root / "prompt.txt"
        self.pid_log = self.root / "pid.txt"
        self.child_pid_log = self.root / "child-pid.txt"
        self.stub.write_text("#!" + sys.executable + '\n' + '''import json, os, pathlib, signal, subprocess, sys, time
pathlib.Path(os.environ["STUB_ARGS"]).write_text(json.dumps(sys.argv[1:]))
pathlib.Path(os.environ["STUB_PROMPT"]).write_text(sys.stdin.read())
pathlib.Path(os.environ["STUB_PID"]).write_text(str(os.getpid()))
if os.environ.get("STUB_GRANDCHILD"):
    child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"],
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
    pathlib.Path(os.environ["STUB_CHILD_PID"]).write_text(str(child.pid))
if os.environ.get("STUB_INTERRUPT_PARENT"):
    os.kill(os.getppid(), signal.SIGINT)
time.sleep(float(os.environ.get("STUB_SLEEP", "0")))
print(pathlib.Path(os.environ["STUB_OUTPUT"]).read_text())
''')
        self.stub.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith(("GIT_", "MEMORY_", "CLAUDE_"))}
        self.env.update({"HOME": str(self.home), "GIT_CONFIG_NOSYSTEM": "1",
                         "GIT_CONFIG_GLOBAL": str(self.root / "absent.gitconfig"),
                         "MEMORY_DIR": str(self.memory), "MEMORY_CONSOLIDATOR_STATE": str(self.state),
                         "MEMORY_SNAPSHOT_BIN": str(BIN / "memory-snapshot"),
                         "MEMORY_LINT_BIN": str(BIN / "memory-lint"), "CLAUDE_BIN": str(self.stub),
                         "STUB_OUTPUT": str(self.output), "STUB_ARGS": str(self.args_log),
                         "STUB_PROMPT": str(self.prompt_log), "STUB_PID": str(self.pid_log),
                         "STUB_CHILD_PID": str(self.child_pid_log)})
        kinds = ["project", "feedback", "reference", "user", "project", "reference"]
        for name, kind in zip("abcdef", kinds):
            (self.memory / f"{name}.md").write_text(
                f"---\nname: Memoria {name}\ndescription: Contexto {name}\nmetadata:\n"
                f"  type: {kind}\n  modified: 2026-09-28\n---\n"
                f"Cuerpo exacto de {name}. [[Memoria b]]\n" + "ñ" * 1600 + "\n")
        (self.memory / "MEMORY.md").write_text("# Índice\n\n" + "".join(
            f"- [Memoria {name}]({name}.md) — {'RESUELTO' if name == 'a' else 'vigente'}\n"
            for name in "abcdef"))
        self.snapshot()
        self.base = self.git("rev-parse", "main")
        self.set_output(happy())

    def command(self, args, **kwargs):
        return subprocess.run([str(x) for x in args], env=self.env, cwd=self.root,
                              capture_output=True, text=True, timeout=25, **kwargs)

    def git(self, *args):
        result = self.command(["git", "-C", self.memory, *args])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout.strip()

    def snapshot(self):
        result = self.command([BIN / "memory-snapshot"])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def run_tool(self, *args, code=0):
        result = self.command([sys.executable, TOOL, *args])
        self.assertEqual(result.returncode, code, result.stdout + result.stderr)
        return result

    def set_output(self, value):
        self.output.write_text(json.dumps({"type": "result", "result": json.dumps(value),
                                           "structured_output": value}))

    def files(self):
        return {str(p.relative_to(self.memory)): p.read_bytes()
                for p in self.memory.rglob("*") if p.is_file() and ".git" not in p.relative_to(self.memory).parts}

    def branches(self):
        return self.git("for-each-ref", "--format=%(refname:short)", "refs/heads/proposal/").splitlines()

    def report(self):
        return (self.state / "proposals" / (DATE + ".md")).read_text()

    def assert_clean_rejection(self, code=4):
        before = self.files()
        self.run_tool("propose", code=code)
        self.assertEqual(self.branches(), [])
        self.assertEqual(self.files(), before)
        self.assertEqual(self.git("branch", "--show-current"), "main")
        self.assertEqual(self.git("rev-parse", "HEAD"), self.base)

    def assert_pid_gone(self, path):
        pid = int(path.read_text())
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            time.sleep(0.05)
        self.fail(f"el proceso {pid} sigue vivo")

    def test_happy_propose_isolated_bytes_args_prompt_and_report(self):
        before = self.files()
        self.run_tool("propose")
        self.assertEqual(self.files(), before)
        self.assertEqual(self.git("branch", "--show-current"), "main")
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.assertEqual(self.branches(), [BRANCH])
        self.assertFalse((self.state / "worktrees" / DATE).exists())
        self.assertIn("Base: " + self.base, self.git("show", "-s", "--format=%B", BRANCH))
        self.assertEqual(self.git("show", "-s", "--format=%s", BRANCH), "consolidate: " + DATE)
        args = json.loads(self.args_log.read_text())
        for flag in ("--setting-sources", "--tools"):
            self.assertEqual(args[args.index(flag) + 1], "")
        self.assertIn("--no-session-persistence", args)
        self.assertIn("--strict-mcp-config", args)
        self.assertNotIn("--mcp-config", args)
        self.assertNotIn("--bare", args)
        self.assertEqual(args[args.index("--model") + 1], "sonnet")
        self.assertEqual(float(args[args.index("--max-budget-usd") + 1]), 2)
        self.assertFalse(json.loads(args[args.index("--json-schema") + 1])["additionalProperties"])
        payload = json.loads(self.prompt_log.read_text().split("INPUT (JSON):\n", 1)[1])
        self.assertEqual(len(payload["memories"]), 6)
        for item in payload["memories"]:
            self.assertEqual(len(item["body"]), 1500)
            self.assertIn(item["metadata.type"], ("user", "feedback", "project", "reference"))
            self.assertEqual(item["modified"], "2026-09-28")
        self.assertEqual(payload["lint"]["errors"], [])
        report = self.report()
        for text in ("RESUELTO", "líneas", "bytes", "fusión", "memory-consolidate apply", "Lint"):
            self.assertIn(text, report)
        alias_file = self.git("show", BRANCH + ":b.md")
        self.assertIn("description: Contexto b\naliases: [reglas, rules]\nmetadata:", alias_file)
        self.assertIn("# Memory archive", self.git("show", BRANCH + ":ARCHIVE.md"))
        self.assertNotIn("(a.md)", self.git("show", BRANCH + ":MEMORY.md"))
        self.assertIn("- [Referencia](c.md) — activa", self.git("show", BRANCH + ":MEMORY.md"))

    def test_if_idle_skips_any_pending_proposal_without_snapshot_or_model(self):
        self.git("branch", "proposal/X")
        before = self.files()
        self.env["MEMORY_SNAPSHOT_BIN"] = str(self.root / "snapshot-must-not-run")
        result = self.run_tool("propose", "--if-idle")
        self.assertIn("propuesta pendiente sin revisar: proposal/X; salteo", result.stdout)
        self.assertFalse(self.args_log.exists())
        self.assertEqual(self.files(), before)

    def test_if_idle_without_pending_proposal_proposes_normally(self):
        before = self.files()
        self.run_tool("propose", "--if-idle")
        self.assertEqual(self.files(), before)
        self.assertEqual(self.branches(), [BRANCH])
        self.assertTrue(self.args_log.is_file())

    def test_prompt_requires_spanish_report_fields_and_active_aliases(self):
        self.run_tool("propose")
        prompt = self.prompt_log.read_text()
        self.assertIn("summary, every operation reason, and every merge_suggestion rationale\nin SPANISH", prompt)
        self.assertIn("Actively use add_aliases for memories that REMAIN in MEMORY.md", prompt)
        self.assertIn("Prioritize feedback\nand rules", prompt)

    def test_nightly_plist_contract(self):
        if shutil.which("plutil"):
            lint = subprocess.run(["plutil", "-lint", "--", str(PLIST)],
                                  capture_output=True, text=True)
            self.assertEqual(lint.returncode, 0, lint.stdout + lint.stderr)
        text = PLIST.read_text()
        self.assertIn("<string>propose</string>", text)
        self.assertIn("<string>--if-idle</string>", text)
        self.assertNotIn("<string>apply</string>", text)
        self.assertIn("__HOME__/.local/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin", text)

    def test_unknown_op(self):
        self.set_output(proposal([{"op": "delete_file", "file": "a.md"}]))
        self.assert_clean_rejection()

    def test_nonexistent_file(self):
        self.set_output(proposal([{"op": "archive_index_entry", "file": "missing.md", "reason": "old"}]))
        self.assert_clean_rejection()

    def test_invalid_alias_colon(self):
        self.set_output(proposal([{"op": "add_aliases", "file": "a.md", "aliases": ["bad:alias"]}]))
        self.assert_clean_rejection()

    def test_reword_different_file(self):
        self.set_output(proposal([{"op": "reword_index_line", "file": "a.md",
                                   "line": "- [Wrong](b.md) — hook"}]))
        self.assert_clean_rejection()

    def failing_lint(self, mode):
        stub = self.root / "lint-stub"
        stub.write_text("#!" + sys.executable + "\n" +
                        "import os, sys\n" +
                        f"fail = {mode}\n" +
                        "if fail:\n print('fixture lint failure'); sys.exit(1)\n" +
                        f"os.execv({str(BIN / 'memory-lint')!r}, [{str(BIN / 'memory-lint')!r}] + sys.argv[1:])\n")
        stub.chmod(0o755)
        self.env["MEMORY_LINT_BIN"] = str(stub)

    def test_baseline_failure_cleanup_report(self):
        self.failing_lint("'--baseline' in sys.argv")
        self.assert_clean_rejection(code=5)
        self.assertIn("rechazada", self.report())
        self.assertIn("fixture lint failure", self.report())
        self.assertFalse((self.state / "worktrees" / DATE).exists())
        self.assertNotIn("proposal", self.git("worktree", "list"))

    def test_second_proposal_same_date(self):
        self.run_tool("propose")
        sha = self.git("rev-parse", BRANCH)
        report = self.report()
        self.run_tool("propose", code=3)
        self.assertEqual(self.git("rev-parse", BRANCH), sha)
        self.assertEqual(self.report(), report)

    def test_dirty_memory_snapshotted_and_used_as_base(self):
        with (self.memory / "d.md").open("a") as stream:
            stream.write("\nInformación nueva\n")
        before = self.files()
        self.run_tool("propose")
        self.assertEqual(self.files(), before)
        self.assertNotEqual(self.git("rev-parse", "main"), self.base)
        self.assertIn("Base: " + self.git("rev-parse", "main"), self.git("show", "-s", "--format=%B", BRANCH))

    def test_non_main_refused(self):
        self.git("checkout", "-b", "work")
        self.run_tool("propose", code=3)
        self.assertEqual(self.branches(), [])
        self.assertFalse(self.args_log.exists())

    def test_timeout_kills_and_reaps_stub(self):
        self.env.update({"STUB_SLEEP": "60", "STUB_GRANDCHILD": "1",
                         "MEMORY_CONSOLIDATOR_TIMEOUT": "2"})
        start = time.monotonic()
        self.assert_clean_rejection()
        self.assertLess(time.monotonic() - start, 10)
        self.assert_pid_gone(self.pid_log)
        self.assert_pid_gone(self.child_pid_log)

    def test_model_success_kills_descendants(self):
        self.env["STUB_GRANDCHILD"] = "1"
        self.run_tool("propose")
        self.assert_pid_gone(self.child_pid_log)

    def test_model_keyboard_interrupt_kills_process_group(self):
        self.env.update({"STUB_GRANDCHILD": "1", "STUB_INTERRUPT_PARENT": "1",
                         "STUB_SLEEP": "60"})
        result = self.command([sys.executable, TOOL, "propose"])
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assert_pid_gone(self.pid_log)
        self.assert_pid_gone(self.child_pid_log)
        self.assertEqual(self.branches(), [])

    def test_invalid_json(self):
        self.output.write_text("not JSON")
        self.assert_clean_rejection()

    def test_no_operations(self):
        self.set_output(proposal())
        self.assert_clean_rejection(code=0)
        self.assertIn("sin cambios", self.report())

    def test_apply_happy_and_revert_receipt(self):
        before = self.files()
        self.run_tool("propose")
        sha = self.git("rev-parse", BRANCH)
        result = self.run_tool("apply")
        self.assertEqual(self.git("rev-parse", "main"), sha)
        self.assertEqual(self.branches(), [])
        self.assertIn(f"revert {sha}", result.stdout)
        self.assertNotIn(b"(a.md)", (self.memory / "MEMORY.md").read_bytes())
        self.assertIn(b"(a.md)", (self.memory / "ARCHIVE.md").read_bytes())
        self.assertEqual((self.memory / "a.md").read_bytes(), before["a.md"])
        lint = self.command([BIN / "memory-lint", self.memory])
        self.assertEqual(lint.returncode, 0, lint.stdout)
        self.assertEqual(self.git("status", "--porcelain"), "")
        self.git("-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false", "revert", "--no-edit", sha)
        self.assertEqual(self.files(), before)

    def test_apply_changed_main_compare_and_swap(self):
        self.run_tool("propose")
        with (self.memory / "f.md").open("a") as stream:
            stream.write("Otra sesión escribió aquí.\n")
        self.snapshot()
        before = self.files()
        head = self.git("rev-parse", "main")
        result = self.run_tool("apply", code=6)
        self.assertIn("discard + propose", result.stdout)
        self.assertEqual(self.files(), before)
        self.assertEqual(self.git("rev-parse", "main"), head)
        self.assertEqual(self.branches(), [BRANCH])

    def test_discard_removes_registered_worktree_and_branch(self):
        self.run_tool("propose")
        worktree = self.state / "worktrees" / DATE
        self.git("worktree", "add", str(worktree), BRANCH)
        (worktree / "untracked.txt").write_text("generated proposal debris")
        before = self.files()
        self.run_tool("discard", DATE)
        self.assertEqual(self.branches(), [])
        self.assertFalse(worktree.exists())
        self.assertEqual(self.files(), before)
        self.assertIn("Descartada", self.report())
        self.run_tool("discard", DATE)  # idempotente

    def test_merge_suggestions_never_modify_files(self):
        self.set_output(proposal(suggestions=[{"files": ["a.md", "b.md"], "rationale": "informativo"}]))
        self.assert_clean_rejection(code=0)
        self.assertIn("informativo", self.report())
        self.set_output(happy())
        before = self.files()
        self.run_tool("propose")
        self.run_tool("apply")
        for name in ("d.md", "e.md"):
            self.assertEqual((self.memory / name).read_bytes(), before[name])

    def test_review_and_status(self):
        self.run_tool("propose")
        result = self.run_tool("review", DATE)
        self.assertIn("diff --git", result.stdout)
        self.assertIn("files changed", result.stdout)
        self.assertIn(self.report(), result.stdout)
        status = self.run_tool("status")
        self.assertIn(BRANCH, status.stdout)
        self.assertIn("Última corrida:", status.stdout)
        self.assertIn("review " + DATE, status.stdout)

    def test_result_json_fallback(self):
        self.output.write_text(json.dumps({"type": "result", "result": json.dumps(happy())}))
        self.run_tool("propose")
        self.assertEqual(self.branches(), [BRANCH])

    def test_from_json_skips_model(self):
        source = self.root / "direct.json"
        source.write_text(json.dumps(happy()))
        self.env["CLAUDE_BIN"] = str(self.root / "MUST-NOT-EXECUTE")
        self.run_tool("propose", "--from-json", str(source))
        self.assertFalse(self.args_log.exists())
        self.assertEqual(self.branches(), [BRANCH])

    def test_apply_lint_failure_rolls_back_exactly(self):
        self.run_tool("propose")
        before = self.files()
        self.failing_lint("True")
        self.run_tool("apply", code=5)
        self.assertEqual(self.git("rev-parse", "main"), self.base)
        self.assertEqual(self.files(), before)
        self.assertEqual(self.branches(), [BRANCH])
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_apply_lint_failure_preserves_concurrent_live_write(self):
        self.run_tool("propose")
        original = (self.memory / "f.md").read_text()
        stub = self.root / "lint-concurrent-write"
        stub.write_text("#!" + sys.executable + "\n" +
                        "import os, pathlib, sys\n" +
                        f"memory = pathlib.Path({str(self.memory)!r})\n" +
                        "if pathlib.Path(sys.argv[-1]).resolve() == memory:\n" +
                        " (memory / 'f.md').write_text((memory / 'f.md').read_text() + 'escritura concurrente\\n')\n" +
                        " print('lint injected failure'); sys.exit(1)\n" +
                        f"os.execv({str(BIN / 'memory-lint')!r}, "
                        f"[{str(BIN / 'memory-lint')!r}] + sys.argv[1:])\n")
        stub.chmod(0o755)
        self.env["MEMORY_LINT_BIN"] = str(stub)
        self.run_tool("apply", code=5)
        self.assertEqual(self.git("rev-parse", "main"), self.base)
        self.assertEqual((self.memory / "f.md").read_text(), original + "escritura concurrente\n")
        self.assertIn("f.md", self.git("status", "--porcelain"))

    def test_apply_uses_baseline_for_preexisting_lint_error(self):
        with (self.memory / "MEMORY.md").open("a") as stream:
            stream.write("- [Missing](missing.md) — error preexistente\n")
        self.snapshot()
        self.base = self.git("rev-parse", "main")
        self.run_tool("propose")
        self.run_tool("apply")
        self.assertEqual(self.branches(), [])

    def test_apply_interrupt_after_merge_rolls_back_with_keep(self):
        self.run_tool("propose")
        stub = self.root / "lint-interrupt"
        stub.write_text("#!" + sys.executable + "\n" +
                        "import os, pathlib, signal, sys, time\n" +
                        f"memory = pathlib.Path({str(self.memory)!r})\n" +
                        "if pathlib.Path(sys.argv[-1]).resolve() == memory:\n" +
                        " os.kill(os.getppid(), signal.SIGINT); time.sleep(1); sys.exit(1)\n" +
                        f"os.execv({str(BIN / 'memory-lint')!r}, "
                        f"[{str(BIN / 'memory-lint')!r}] + sys.argv[1:])\n")
        stub.chmod(0o755)
        self.env["MEMORY_LINT_BIN"] = str(stub)
        result = self.command([sys.executable, TOOL, "apply"])
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.git("rev-parse", "main"), self.base)
        self.assertEqual(self.branches(), [BRANCH])

    def test_apply_branch_delete_failure_is_success(self):
        self.run_tool("propose")
        real_git = subprocess.run(["sh", "-c", "command -v git"], capture_output=True,
                                  text=True, check=True).stdout.strip()
        wrapper_dir = self.root / "git-wrapper"
        wrapper_dir.mkdir()
        wrapper = wrapper_dir / "git"
        wrapper.write_text("#!" + sys.executable + "\n" +
                           "import os, sys\n" +
                           "if 'branch' in sys.argv and '-d' in sys.argv:\n"
                           " print('delete injected failure', file=sys.stderr); sys.exit(1)\n" +
                           f"os.execv({real_git!r}, [{real_git!r}] + sys.argv[1:])\n")
        wrapper.chmod(0o755)
        self.env["PATH"] = str(wrapper_dir) + os.pathsep + self.env.get("PATH", "")
        result = self.run_tool("apply")
        self.assertIn("rama no borrada", result.stdout)
        self.assertIn("rama no borrada", self.report())
        self.assertEqual(self.branches(), [BRANCH])

    def test_snapshot_failure_touches_no_state(self):
        stub = self.root / "snapshot-fail"
        stub.write_text("#!/bin/sh\nexit 7\n")
        stub.chmod(0o755)
        self.env["MEMORY_SNAPSHOT_BIN"] = str(stub)
        self.assert_clean_rejection(code=3)
        self.assertFalse(self.state.exists())
        self.assertFalse(self.args_log.exists())

    def test_state_inside_memory_rejected_before_snapshot(self):
        self.env["MEMORY_CONSOLIDATOR_STATE"] = str(self.memory / "state")
        self.assert_clean_rejection(code=3)
        self.assertFalse((self.memory / "state").exists())

    def test_schema_closed_duplicate_ops_and_limits(self):
        variants = [
            {**happy(), "extra": True},
            {**happy(), "summary": None},
            {**happy(), "merge_suggestions": [{}]},
            proposal([happy()["operations"][0]] * 2),
            proposal([{**happy()["operations"][0], "extra": True}]),
            proposal([{"op": "add_aliases", "file": "a.md", "aliases": []}]),
            proposal([{"op": "add_aliases", "file": "a.md", "aliases": ["x"] * 9}]),
            proposal([{"op": "add_aliases", "file": "a.md", "aliases": ["x" * 41]}]),
            proposal([{"op": "reword_index_line", "file": "a.md", "line": "- [A](a.md) — " + "x" * 201}]),
        ]
        for value in variants:
            with self.subTest(value=value):
                self.set_output(value)
                self.assert_clean_rejection()
        self.env["MEMORY_CONSOLIDATOR_MAX_OPS"] = "2"
        self.set_output(happy())
        self.assert_clean_rejection()

    def test_aliases_reject_yaml_indicators_reserved_scalars_and_digits(self):
        invalid = ['"x', "*a", "&a", "!t", "{", "@x", "`", "%x",
                   "null", "123", "a\u2028b", "a\u2029b", "a\x85b", "a\x01b"]
        for alias in invalid:
            with self.subTest(alias=alias):
                self.set_output(proposal([{"op": "add_aliases", "file": "a.md",
                                           "aliases": [alias]}]))
                self.assert_clean_rejection(code=4)

    def test_unicode_aliases_are_accepted(self):
        self.set_output(proposal([{"op": "add_aliases", "file": "a.md",
                                   "aliases": ["búsqueda útil", "記憶-参照"]}]))
        self.run_tool("propose")
        self.assertIn("aliases: [búsqueda útil, 記憶-参照]", self.git("show", BRANCH + ":a.md"))

    def test_indexes_split_only_on_lf(self):
        index = self.memory / "MEMORY.md"
        text = index.read_text()
        text = text.replace(" — RESUELTO\n- [Memoria b]", " — RESUELTO\u2028- [Memoria b]")
        index.write_text(text)
        self.snapshot()
        self.base = self.git("rev-parse", "main")
        self.assert_clean_rejection(code=4)

    def test_reword_rejects_unicode_line_separator(self):
        self.set_output(proposal([{"op": "reword_index_line", "file": "a.md",
                                   "line": "- [A](a.md) — uno\u2028dos"}]))
        self.assert_clean_rejection(code=4)

    def test_nonindexed_path_traversal_and_symlink_refused(self):
        for filename in ("../outside.md", "/tmp/outside.md", "MEMORY.md", "orphan.md"):
            if filename == "orphan.md":
                (self.memory / filename).write_bytes((self.memory / "a.md").read_bytes())
                self.snapshot()
                self.base = self.git("rev-parse", "main")
            with self.subTest(filename=filename):
                self.set_output(proposal([{"op": "archive_index_entry", "file": filename, "reason": "no"}]))
                self.assert_clean_rejection()
        target = self.root / "outside.md"
        target.write_text("must stay intact")
        (self.memory / "a.md").unlink()
        (self.memory / "a.md").symlink_to(target)
        self.snapshot()
        self.base = self.git("rev-parse", "main")
        self.set_output(happy())
        self.assert_clean_rejection()
        self.assertEqual(target.read_text(), "must stay intact")

    def test_alias_replacement_preserves_body_frontmatter_and_crlf(self):
        path = self.memory / "b.md"
        original = path.read_bytes().replace(b"metadata:\n", b"aliases: [old]\nmetadata:\n").replace(b"\n", b"\r\n")
        path.write_bytes(original)
        self.snapshot()
        self.run_tool("propose")
        self.run_tool("apply")
        self.assertEqual(path.read_bytes(), original.replace(b"aliases: [old]", b"aliases: [reglas, rules]"))

    def test_archive_existing_without_final_newline_and_reword_same_target(self):
        (self.memory / "ARCHIVE.md").write_text("# Existing archive")
        self.snapshot()
        self.set_output(proposal([
            {"op": "archive_index_entry", "file": "a.md", "reason": "old"},
            {"op": "reword_index_line", "file": "a.md", "line": "- [A](a.md) — resuelto"}]))
        self.run_tool("propose")
        self.assertEqual(self.git("show", BRANCH + ":ARCHIVE.md"), "# Existing archive\n- [A](a.md) — resuelto")

    def test_invalid_date_cannot_escape_state(self):
        self.run_tool("discard", "../../escape", code=3)
        self.assertFalse(self.state.exists())

    def test_model_error_and_invalid_envelopes(self):
        for envelope in ([], {"result": "no JSON"}, {"structured_output": None},
                         {"is_error": True, "structured_output": happy()}, happy()):
            with self.subTest(envelope=envelope):
                self.output.write_text(json.dumps(envelope))
                self.assert_clean_rejection()

    def test_real_lint_byte_limit_rejects_from_json(self):
        index = self.memory / "MEMORY.md"
        original = index.read_bytes()
        index.write_bytes(original + b"x" * (24999 - len(original) - 1) + b"\n")
        self.snapshot()
        self.base = self.git("rev-parse", "main")
        source = self.root / "too-large.json"
        source.write_text(json.dumps(proposal([{
            "op": "reword_index_line", "file": "c.md",
            "line": "- [Referencia](c.md) — " + "ñ" * 150,
        }])))
        before = self.files()
        self.run_tool("propose", "--from-json", str(source), code=5)
        self.assertEqual(self.files(), before)
        self.assertEqual(self.branches(), [])
        self.assertIn("MEMORY_BYTE_LIMIT", self.report())

    def test_apply_dirty_snapshot_detects_cas_conflict(self):
        self.run_tool("propose")
        with (self.memory / "f.md").open("a") as stream:
            stream.write("Sin snapshot manual\n")
        before = self.files()
        self.run_tool("apply", code=6)
        self.assertEqual(self.files(), before)
        self.assertNotEqual(self.git("rev-parse", "main"), self.base)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_git_hooks_never_execute(self):
        hooks = self.root / "hooks"
        hooks.mkdir()
        canary = self.root / "hook-executed"
        for name in ("pre-commit", "post-checkout", "post-merge"):
            hook = hooks / name
            hook.write_text(f"#!/bin/sh\ntouch '{canary}'\nexit 1\n")
            hook.chmod(0o755)
        self.git("config", "core.hooksPath", str(hooks))
        self.run_tool("propose")
        self.run_tool("apply")
        self.assertFalse(canary.exists())

    def test_aliases_on_archived_memory_and_exact_input_delimiters(self):
        index = self.memory / "MEMORY.md"
        line = next(line for line in index.read_text().splitlines(keepends=True) if "(b.md)" in line)
        index.write_text(index.read_text().replace(line, ""))
        (self.memory / "ARCHIVE.md").write_text("# Archive\n" + line)
        path = self.memory / "b.md"
        path.write_text(path.read_text().replace("description: Contexto b", "description: Contexto --- b"))
        self.snapshot()
        self.set_output(proposal([happy()["operations"][1]]))
        self.run_tool("propose")
        payload = json.loads(self.prompt_log.read_text().split("INPUT (JSON):\n", 1)[1])
        item = next(item for item in payload["memories"] if item["file"] == "b.md")
        self.assertEqual(item["description"], "Contexto --- b")
        self.assertTrue(item["body"].startswith("Cuerpo exacto de b."))
        self.run_tool("apply")
        self.assertIn("aliases: [reglas, rules]", path.read_text())

    def test_duplicate_json_keys_fail_closed(self):
        self.output.write_text('{"structured_output": {}, "structured_output": ' + json.dumps(happy()) + '}')
        self.assert_clean_rejection()

    def test_state_symlink_into_memory_rejected(self):
        self.state.mkdir()
        (self.state / "proposals").symlink_to(self.memory, target_is_directory=True)
        self.assert_clean_rejection(code=3)

    def test_index_lock_does_not_allow_dirty_snapshot(self):
        with (self.memory / "f.md").open("a") as stream:
            stream.write("pending\n")
        lock = self.memory / ".git/index.lock"
        lock.touch()
        self.assert_clean_rejection(code=3)
        self.assertTrue(lock.exists())

    def test_consolidator_lock_is_held_before_snapshot(self):
        stub = self.root / "snapshot-check-lock"
        stub.write_text("#!" + sys.executable + "\n" +
                        "import fcntl, os, pathlib, sys\n" +
                        "lock = open(pathlib.Path(os.environ['MEMORY_CONSOLIDATOR_STATE']) / 'lock', 'a')\n" +
                        "try:\n fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)\n"
                        "except BlockingIOError:\n pass\n"
                        "else:\n sys.exit(19)\n" +
                        f"os.execv({str(BIN / 'memory-snapshot')!r}, "
                        f"[{str(BIN / 'memory-snapshot')!r}])\n")
        stub.chmod(0o755)
        self.env["MEMORY_SNAPSHOT_BIN"] = str(stub)
        self.run_tool("propose")

    def test_inherited_git_dir_cannot_redirect_git(self):
        other = self.root / "other"
        other.mkdir()
        init = subprocess.run(["git", "init", str(other)], capture_output=True, text=True)
        self.assertEqual(init.returncode, 0, init.stdout + init.stderr)
        self.env["GIT_DIR"] = str(other / ".git")
        try:
            self.run_tool("propose")
        finally:
            self.env.pop("GIT_DIR", None)
        self.assertEqual(self.branches(), [BRANCH])

    def test_apply_rejects_non_main_branch(self):
        self.run_tool("propose")
        self.git("checkout", "-b", "work")
        self.run_tool("apply", code=3)
        self.assertEqual(self.git("branch", "--show-current"), "work")
        self.assertEqual(self.branches(), [BRANCH])

    def test_propose_base_exception_cleans_up_and_reports_cleanup_error(self):
        helper = self.root / "inject-applicator-exception.py"
        helper.write_text(
            "import importlib.machinery, sys\n"
            f"m = importlib.machinery.SourceFileLoader('memory_consolidate', {str(TOOL)!r}).load_module()\n"
            "original_cleanup = m.Consolidator.cleanup\n"
            "def explode(self, root, operations):\n raise RuntimeError('aplicador injected')\n"
            "def cleanup_then_fail(self, branch=True):\n"
            " original_cleanup(self, branch)\n raise RuntimeError('cleanup injected')\n"
            "m.Consolidator.edit = explode\n"
            "m.Consolidator.cleanup = cleanup_then_fail\n"
            f"sys.argv = [{str(TOOL)!r}, 'propose']\n"
            "raise SystemExit(m.main())\n")
        result = self.command([sys.executable, helper])
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.branches(), [])
        self.assertFalse((self.state / "worktrees" / DATE).exists())
        self.assertIn("aplicador injected", self.report())
        self.assertIn("cleanup injected", self.report())

    def test_invalid_final_operation_rejects_whole_proposal(self):
        value = happy()
        value["operations"].append({"op": "delete_file", "file": "f.md"})
        self.set_output(value)
        self.assert_clean_rejection()

    def test_safe_nested_reference_and_custom_model_budget(self):
        nested = self.memory / "projects"
        nested.mkdir()
        (self.memory / "a.md").rename(nested / "a.md")
        index = self.memory / "MEMORY.md"
        index.write_text(index.read_text().replace("(a.md)", "(projects/a.md)"))
        self.snapshot()
        self.set_output(proposal([{"op": "archive_index_entry", "file": "projects/a.md", "reason": "resuelto"}]))
        self.env.update({"MEMORY_CONSOLIDATOR_MODEL": "fixture-model", "MEMORY_CONSOLIDATOR_MAX_BUDGET_USD": "0.25"})
        before = self.files()
        self.run_tool("propose")
        self.assertEqual(self.files(), before)
        args = json.loads(self.args_log.read_text())
        self.assertEqual(args[args.index("--model") + 1], "fixture-model")
        self.assertEqual(args[args.index("--max-budget-usd") + 1], "0.25")
        payload = json.loads(self.prompt_log.read_text().split("INPUT (JSON):\n", 1)[1])
        self.assertIn("projects/a.md", [item["file"] for item in payload["memories"]])
        self.run_tool("apply")
        self.assertEqual((nested / "a.md").read_bytes(), before["projects/a.md"])


if __name__ == "__main__":
    unittest.main()
