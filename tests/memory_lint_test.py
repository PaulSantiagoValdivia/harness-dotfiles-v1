#!/usr/bin/env python3
"""Contract fixtures for the read-only memory linter."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "files/shared/bin/memory-lint"


def memory(name: str = "Alpha", description: str = "Contexto útil", kind: str = "project",
           body: str = "Contenido\n", extra_metadata: str = "") -> str:
    metadata = f"  type: {kind}\n"
    if extra_metadata:
        metadata += extra_metadata
    return (
        "---\n"
        f"name: {name}\n"
        f"description: {description}\n"
        "metadata:\n"
        f"{metadata}"
        "---\n"
        f"{body}"
    )


class MemoryLintTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.workspace = Path(self.tmp.name)
        self.serial = 0

    def fixture(self, index: str = "- [Alpha](a.md) — útil\n", *, archive: str | None = None,
                files: dict[str, str] | None = None) -> Path:
        self.serial += 1
        root = self.workspace / f"fixture-{self.serial}"
        root.mkdir()
        (root / "MEMORY.md").write_text(index)
        if archive is not None:
            (root / "ARCHIVE.md").write_text(archive)
        for filename, content in (files or {"a.md": memory()}).items():
            (root / filename).write_text(content)
        return root

    def clone(self, source: Path) -> Path:
        self.serial += 1
        target = self.workspace / f"fixture-{self.serial}"
        shutil.copytree(source, target)
        return target

    def run_lint(self, directory: Path, *, baseline: Path | None = None,
                 as_json: bool = True) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(TOOL)]
        if baseline is not None:
            command.extend(["--baseline", str(baseline)])
        if as_json:
            command.append("--json")
        command.append(str(directory))
        return subprocess.run(command, capture_output=True, text=True, timeout=10)

    def payload(self, result: subprocess.CompletedProcess[str]) -> dict[str, list[dict[str, str]]]:
        return json.loads(result.stdout)

    def error_codes(self, result: subprocess.CompletedProcess[str]) -> list[str]:
        return [finding["code"] for finding in self.payload(result)["errors"]]

    def warning_codes(self, result: subprocess.CompletedProcess[str]) -> list[str]:
        return [finding["code"] for finding in self.payload(result)["warnings"]]

    def test_index_target_missing(self) -> None:
        root = self.fixture(index="- [Ausente](missing.md) — útil\n", files={})
        result = self.run_lint(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("INDEX_TARGET_MISSING", self.error_codes(result))

    def test_index_duplicate_inside_memory_and_across_archive(self) -> None:
        cases = (
            ("- [Uno](a.md)\n- [Dos](a.md)\n", None),
            ("- [Uno](a.md)\n", "- [Dos](a.md)\n"),
        )
        for index, archive in cases:
            with self.subTest(archive=archive is not None):
                result = self.run_lint(self.fixture(index=index, archive=archive))
                self.assertEqual(result.returncode, 1)
                self.assertIn("INDEX_DUPLICATE_FILE", self.error_codes(result))

    def test_frontmatter_errors(self) -> None:
        fixtures = {
            "FRONTMATTER_MISSING": "sin frontmatter\n",
            "FRONTMATTER_NAME_MISSING": memory(name=""),
            "FRONTMATTER_DESCRIPTION_MISSING": memory(description=""),
            "FRONTMATTER_TYPE_MISSING": (
                "---\nname: Alpha\ndescription: Contexto\nmetadata:\n  node_type: memory\n---\nContenido\n"
            ),
            "FRONTMATTER_TYPE_INVALID": memory(kind="unknown"),
        }
        for code, content in fixtures.items():
            with self.subTest(code=code):
                result = self.run_lint(self.fixture(files={"a.md": content}))
                self.assertEqual(result.returncode, 1)
                self.assertIn(code, self.error_codes(result))

    def test_duplicate_names(self) -> None:
        root = self.fixture(
            index="- [Uno](a.md)\n- [Dos](b.md)\n",
            files={"a.md": memory(), "b.md": memory(body="Otro\n")},
        )
        result = self.run_lint(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("NAME_DUPLICATE", self.error_codes(result))

    def test_memory_hard_limits(self) -> None:
        line_root = self.fixture(index="x\n" * 201, files={})
        line_result = self.run_lint(line_root)
        self.assertEqual(line_result.returncode, 1)
        self.assertIn("MEMORY_LINE_LIMIT", self.error_codes(line_result))

        byte_root = self.fixture(index="x" * 25001, files={})
        byte_result = self.run_lint(byte_root)
        self.assertEqual(byte_result.returncode, 1)
        self.assertIn("MEMORY_BYTE_LIMIT", self.error_codes(byte_result))

    def test_warnings_do_not_change_exit_status(self) -> None:
        cases = {
            "UNREFERENCED_FILE": self.fixture(index="", files={"a.md": memory()}),
            "DANGLING_LINK": self.fixture(files={"a.md": memory(body="Ver [[Fantasma]].\n")}),
            "MEMORY_LINE_NEAR_LIMIT": self.fixture(index="x\n" * 161, files={}),
            "MEMORY_BYTE_NEAR_LIMIT": self.fixture(index="x" * 20001, files={}),
        }
        for code, root in cases.items():
            with self.subTest(code=code):
                result = self.run_lint(root)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(code, self.warning_codes(result))

    def test_bracketed_title_missing_archive_and_extended_metadata(self) -> None:
        content = memory(extra_metadata=(
            "  node_type: durable\n"
            "  originSessionId: fixture-session\n"
            "  modified: 2026-09-29\n"
        ))
        root = self.fixture(
            index="- [Modelo sin `[1m]`](a.md) — gancho\n",
            files={"a.md": content},
        )
        self.assertFalse((root / "ARCHIVE.md").exists())
        result = self.run_lint(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.error_codes(result), [])
        self.assertNotIn("UNREFERENCED_FILE", self.warning_codes(result))

    def test_each_baseline_regression_fails(self) -> None:
        def assert_regression(mutator, expected: str) -> None:
            base = self.fixture(
                index="- [Alpha](a.md)\n- [Beta](b.md)\n",
                files={"a.md": memory(), "b.md": memory(name="Beta", body="Beta\n")},
            )
            proposal = self.clone(base)
            mutator(proposal)
            result = self.run_lint(proposal, baseline=base)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn(expected, self.error_codes(result))

        cases = (
            (lambda root: (root / "a.md").write_text(memory(kind="invalid")), "BASE_ERROR_ADDED"),
            (lambda root: (root / "b.md").unlink(), "BASE_FILE_REMOVED"),
            (lambda root: (root / "a.md").write_text(memory(body="Cuerpo cambiado\n")), "BASE_BODY_CHANGED"),
            (lambda root: (root / "a.md").write_text(memory(description="Otra descripción")),
             "BASE_FRONTMATTER_CHANGED"),
            (lambda root: (root / "MEMORY.md").write_text("- [Beta](b.md)\n"),
             "BASE_REFERENCE_REMOVED"),
        )
        for mutator, expected in cases:
            with self.subTest(expected=expected):
                assert_regression(mutator, expected)

        base = self.fixture(files={"a.md": memory()})
        proposal = self.clone(base)
        (proposal / "MEMORY.md").write_text("")
        result = self.run_lint(proposal, baseline=base)
        self.assertEqual(result.returncode, 1)
        self.assertIn("BASE_REFERENCE_REMOVED", self.error_codes(result))
        self.assertIn("BASE_BECAME_UNREFERENCED", self.error_codes(result))

    def test_baseline_allows_archive_move_and_aliases(self) -> None:
        base = self.fixture(files={"a.md": memory()})
        proposal = self.clone(base)
        (proposal / "MEMORY.md").write_text("")
        (proposal / "ARCHIVE.md").write_text("- [Alpha](a.md) — archivada\n")
        original = (proposal / "a.md").read_text()
        (proposal / "a.md").write_text(original.replace("metadata:\n", "aliases: [x, y]\nmetadata:\n"))
        result = self.run_lint(proposal, baseline=base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.error_codes(result), [])

    def test_baseline_ignores_line_number_changes_for_existing_index_error(self) -> None:
        base = self.fixture(index="encabezado\notra línea\n- [Ausente](missing.md)\n", files={})
        proposal = self.clone(base)
        (proposal / "MEMORY.md").write_text("- [Ausente](missing.md)\n")
        result = self.run_lint(proposal, baseline=base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.error_codes(result), [])

    def test_json_contract_and_missing_directory_exit(self) -> None:
        root = self.fixture(
            index="- [Ausente](missing.md)\n",
            files={"orphan.md": memory(body="[[Fantasma]]\n")},
        )
        result = self.run_lint(root)
        self.assertEqual(result.returncode, 1)
        payload = self.payload(result)
        self.assertTrue(payload["errors"])
        self.assertTrue(payload["warnings"])
        for finding in payload["errors"] + payload["warnings"]:
            self.assertTrue({"code", "file", "message"}.issubset(finding))

        missing = self.run_lint(self.workspace / "does-not-exist", as_json=False)
        self.assertEqual(missing.returncode, 2)
        self.assertIn("DIR no existe", missing.stderr)

    def test_lint_never_writes_fixture_files(self) -> None:
        root = self.fixture(files={"a.md": memory(body="Ver [[Fantasma]].\n")})

        def state() -> dict[str, tuple[str, int]]:
            return {
                str(path.relative_to(root)): (
                    hashlib.sha256(path.read_bytes()).hexdigest(),
                    path.stat().st_mtime_ns,
                )
                for path in root.rglob("*") if path.is_file()
            }

        before = state()
        result = self.run_lint(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(state(), before)


if __name__ == "__main__":
    unittest.main()
