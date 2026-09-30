# Design addendum: Registry producer root

User-reported nested `.atl` is a producer-target defect, not permission to suppress Prettier or delete product files. Source inspection confirms Claude accepts any Git-contained directory unchanged; installed Codex refreshes at `$PWD`. Isolated real reproduction confirms refresh exit 0 creates `functions/src/.atl/{skill-registry.md,.skill-registry.cache.json}`; actual Prettier then exits 1 on `src/.atl/skill-registry.md`. Receipt: `/tmp/triangulation-safety-evidence/registry-nested-reproduction.json` (0.178s refresh, 1.292s Prettier); no product files touched.

| Option | Tradeoff | Decision |
|---|---|---|
| Shared root-resolving hook vs duplicate shell strings | One deployed dependency | Add `files/shared/bin/skill-registry-refresh`, installed into `~/.local/bin`; both clients invoke it. |
| Producer fix vs formatter ignore/cleanup | Existing residue remains owner-controlled | No product changes, deletion or weaker format gate. |

Resolve the supplied client cwd with quoted `git -C … rev-parse --show-toplevel`, confirming a working tree. Use the returned physical worktree root, never `--git-common-dir`. Exact physical HOME retains global refresh; nonrepository/unresolvable paths safely skip with bounded diagnostic and no original-cwd fallback. Preserve `--quiet --no-gitignore`; refresh errors remain distinguishable from success without breaking session startup.

`files/claude/settings.json` declares the shared helper. A narrow versioned installer/patcher called by `bootstrap.sh` updates only recognized registry-refresh command entries in installed Claude settings and Codex `hooks.json`, retaining matchers, metadata, other entries and preferences. Back up changed files, refuse malformed/ambiguous structures, and avoid whole-config replacement during scoped deployment. Apply after upstream install so bootstrap cannot restore the unsafe producer.

Add `tests/skill_registry_root_test.sh`: execute both client hook commands with a recording `gentle-ai` fixture from nested main/linked roots, spaces/symlinks, HOME/nonrepo, and injected Git failures. Assert exact target and absence of nested writes. Installer fixtures prove fresh/customized setup, repeat, backup/restore and bootstrap wiring. Extend `verify.sh` root-behavior/parity checks instead of relying on the old `is-inside-work-tree` substring assertion.

Threat matrix: Git selectors remain Applicable; add nested main/linked, aliases, nonrepo/HOME/error RED cases. Other existing rows unchanged. Deploy helper before hook references; rollback only managed helper/command deltas after preserving later edits. Lifecycle/stop tasks remain unchanged.
