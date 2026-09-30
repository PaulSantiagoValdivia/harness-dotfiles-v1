#!/usr/bin/env python3
"""Bounded prompt regression and real CLI parsing (help only; no model call)."""
import pathlib, re, shlex, shutil, subprocess, sys, unittest
ROOT = pathlib.Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1]
class InvocationTests(unittest.TestCase):
    def test_global_approval_placement(self):
        for name in ('codex-build', 'dual-review'):
            source = (ROOT / f'files/claude/workflows/{name}.js').read_text()
            matches = re.findall(r'"\$\{CODEX_BIN\}" ([^`\n]*?)-c model_reasoning_effort=', source)
            self.assertTrue(matches, name)
            for prefix in matches:
                with self.subTest(workflow=name, prefix=prefix):
                    tokens = shlex.split(prefix)
                    self.assertIn('--ask-for-approval', tokens)
                    self.assertLess(tokens.index('--ask-for-approval'), tokens.index('exec'))
                    codex = shutil.which('codex', path='/usr/local/bin:/opt/homebrew/bin')
                    if not codex:
                        self.skipTest('Codex not installed: structural checks only; runtime parsing NOT verified')
                    result = subprocess.run([codex, *tokens, '--help'], capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, 0, result.stderr)
    def test_collision_preserves_worktree(self):
        source = (ROOT / 'files/claude/workflows/codex-build.js').read_text()
        self.assertNotIn('worktree remove --force', source)
        self.assertIn('STOP', source)
        self.assertIn('existing worktree', source)
if __name__ == '__main__':
    unittest.main()
