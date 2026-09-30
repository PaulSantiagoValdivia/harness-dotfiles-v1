# Design: Truthful harness health and local evidence

## Technical Approach

Harden the existing Bash verifier and shared-skill installer, not the product repositories. Implement the proposal's `harness-health-diagnostics` and `harness-evidence` capabilities with isolated fixtures before production changes. Preserve existing SDD verification authority and pinned research decisions.

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Shared source-only health functions vs duplicated predicates | One testable seam; small additional source dependency | Source `files/shared/lib/worktree-health.sh` from `verify.sh` using `REPO_DIR`; no installed helper required. |
| Actual root vs directory existence / Git discovery alone | More checks prevent ancestor-repository false positives | Require local `.git` metadata, successful Git inspection and physical-path equality with `--show-toplevel`; accept linked-worktree gitfiles and symlink aliases. |
| Local exclude vs product `.gitignore` commit | Local protection is immediate but not team-wide | Backed-up explicit runbook operation only; product owner later proposes dev-based `.gitignore` change. |
| Original skill/template vs recorder framework | Manual observations need discipline but introduce no process/upload dependency | One local report contract shared by both clients; no executable evidence helper initially. |

## Data Flow

Configured repository → registered roots → shared classification → existing core/app checks and ownership diagnostics → retained verification log → local evidence manifest and disposition ledger.

Shared skill source → existing backup/copy installation seam → identical Claude/Codex skill trees → parity checks.

## Interfaces / Contracts

- Classification distinguishes valid checkout, missing/residual checkout, and inspection error. Missing metadata skips instruction checks without deleting files; malformed metadata/failed Git operations surface uncertainty, never PASS. Physical comparison handles macOS `/tmp` aliases. Legacy Conductor and memory-only exclusions remain explicit.
- Audit uses `GIT_OPTIONAL_LOCKS=0`, checked command exits and NUL-delimited status with all untracked files. Handle rename records correctly. Exclude only known generated `.atl/skill-registry*` files, not arbitrary `.atl/` content. Report tracked/untracked pending-work counts. Failed status/list/ref queries remain warnings or failures, never clean/unpublished assertions. Remote containment describes **locally available remote-tracking refs**; no fetch occurs.
- Resolve panel common directory through Git from a validated root. Back up `info/exclude`, append only missing `/.claude/worktrees/` and `/.atl/` rules, preserve contents, recheck status/ignore behavior. Refuse unexpected file type or concurrent content drift. Do not run global bootstrap to apply this local remediation.
- Report schema is a documented field contract plus JSON template: version, UTC timestamp, repository/branch/commit, dirty status and snapshot limitations; scope/target/environment; checks with expected/observed result, exact command/interaction, exit code or explicit null reason, PASS/FAIL/BLOCKED/UNTESTED; before/after references or unavailability reasons; local artifact paths/SHA-256; limitations and sensitive-data handling. Dirty HEAD is not complete snapshot identity. Hash only retained, inspected artifacts; commands are data, never evaluated from reports. Use a verified ignored local directory or private directory outside the repository. No automatic capture/upload.

## File Changes

| File | Action |
|---|---|
| `verify.sh` | Wire shared health seam and focused tests. |
| `files/shared/lib/worktree-health.sh` | Add classification/audit mechanics only. |
| `tests/worktree_health_test.sh` | Add isolated Git/error/nonmutation fixtures. |
| `files/shared/skills/harness-evidence/SKILL.md` | Add original workflow/valid metadata. |
| `files/shared/skills/harness-evidence/references/report-template.json` | Add shared field template. |
| `bootstrap.sh`, `tests/standalone_runtime_parity_test.sh` | Extend scoped backup/copy and full-tree parity. |
| `tests/harness_evidence_test.sh` | Test template, isolated installation, rerun and preservation. |
| `docs/harness-evidence.md`, `README.md` | Runbook, baseline disposition ledger/link. |

## Testing Strategy

Strict TDD: retain failing focused receipts, implement, rerun; finish with `bash -n` and `./verify.sh`. Fixtures cover residual directories inside another repository, linked roots, missing instructions, spaces, staged/unstaged/untracked/renamed files, generated-only versus user `.atl` files, failing Git operations and unchanged files/index/registration. Installer fixtures cover fresh/rerun/drift/backups/supporting files and untouched user preferences. Test exclude runbook twice in temporary linked worktrees before live application.

## Threat Matrix

| Boundary | Applicability; safe/failure behavior; planned RED tests |
|---|---|
| Documentation-like paths | N/A: no executable classification. |
| Git repository selection | Applicable: quoted `git -C`, relative/absolute paths resolve actual root or report uncertainty; RED each selector, spaces, ancestor false positive. |
| Commit state | N/A: no commit automation; status fixtures above cover index visibility. |
| Push state | N/A: no push automation. |
| PR commands | N/A: no PR-command changes. |

## Migration / Rollout

No data migration. Deliver autonomous ≤400-authored-line feature-branch-chain slices with tests/docs beside behavior. Deploy only managed skill directories with backups; never overwrite global config. Record every baseline failure/warning and residual owner/action. Rollback own commits/managed files; remove only added exclude lines, preserving concurrent edits and all sibling work.

## Open Questions

None blocking.
