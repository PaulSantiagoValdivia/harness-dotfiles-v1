# Tasks: Harness evidence hardening

## Review Workload Forecast

| Field | Value |
| --- | --- |
| Estimated implementation lines | 550–760; diagnostics 300–390, evidence 250–370 |
| Delivery strategy | auto-chain |
| Planning | Separate child; split again if authored diff exceeds 400 |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

Tracker `feat/harness-evidence-hardening` → planning child → diagnostics child → evidence child. Each child targets its immediate predecessor; keep tracker draft/no-merge until integration. Existing research/Astra changes are not implementation-slice scope. Measure every child, including docs/progress, against its immediate base; split rather than exceed 400 authored lines.

### Work Units

| Unit | Start → finish | Focused command | Runtime evidence | Rollback |
| --- | --- | --- | --- | --- |
| Diagnostics | Accepted planning → truthful audit | `bash tests/worktree_health_test.sh` | Read-only configured-root audit | Revert health helper/wiring/tests/docs; remove only added exclusions |
| Evidence | Diagnostics → shared installed contract | `bash tests/harness_evidence_test.sh` | `bash tests/standalone_runtime_parity_test.sh` | Restore managed skill backups; revert installer/tests/docs |

## Phase 1: Diagnostics slice

- [x] 1.1 RED: create `tests/worktree_health_test.sh`; test valid main/linked roots, relative/absolute selectors, spaces, symlink aliases, absent/residual/malformed metadata and ancestor false positives; genuine missing instructions still fail.
- [x] 1.2 RED: extend fixtures for staged/unstaged/untracked/renamed work, generated-only versus user `.atl` files, failed status/list/ref queries, qualified local-ref wording, unchanged index/files/registrations, and no fetch.
- [x] 1.3 RED: test the documented local-exclude operation twice and rollback in temporary linked roots; preserve prior/concurrent content, reject unexpected file types/content drift.
- [x] 1.4 GREEN: add `files/shared/lib/worktree-health.sh`; wire `verify.sh` classification/audit/tests. Run `bash tests/worktree_health_test.sh`; retain failing/passing receipts.
- [x] 1.5 REFACTOR: keep source-only shared mechanics, checked exits, NUL-safe status, optional-lock suppression; rerun fixtures and `bash -n verify.sh files/shared/lib/worktree-health.sh`.
- [x] 1.6 Document explicit backed-up ignore remediation in `docs/harness-evidence.md`; primary inspects ownership before live application, never bootstrap/cleanup sibling data.
- [x] 1.7 Primary writes `docs/research/harness-health-dispositions.md`: individually map seven failures/seventeen warnings to evidence, disposition, owner/action, and unresolved status.

## Phase 2: Evidence slice

- [x] 2.1 RED: create `tests/harness_evidence_test.sh`; assert required manifest fields/statuses, explicit unavailable comparisons/checksums, local privacy, fresh/customized homes, rerun/backups/restore, supporting-file drift, and unchanged preferences.
- [x] 2.2 GREEN: author `files/shared/skills/harness-evidence/SKILL.md` and `references/report-template.json`; no recorder, uploader, manifest CLI, or competing receipt authority.
- [x] 2.3 GREEN: extend `bootstrap.sh`, `verify.sh`, and `tests/standalone_runtime_parity_test.sh` for full-tree parity; run `bash tests/harness_evidence_test.sh`.
- [x] 2.4 REFACTOR: document dirty-snapshot limitations, real artifact hashes, optional visual proof, and rollback in `docs/harness-evidence.md`; link from `README.md`; rerun focused tests and syntax checks.

## Phase 3: Consolidation

- [x] 3.1 Deploy only managed skill directories with backups; run standalone parity and Astra/cmux regression checks; retain exact commands/results.
- [x] 3.2 Prepare the installed-state handoff for the dedicated verifier, which MUST execute fresh `./verify.sh` and update result/disposition evidence before acceptance.
- [x] 3.3 Coordinator records per-slice commits/pushes/base/diff/rollback and apply-progress; hand off all eleven scenarios to dedicated `sdd-verify`, without another review lane.

Planning clarification: 3.2/3.3 describe preparation, not a preclaimed verification result. Final execution and scenario judgment belong to the verifier; requiring that judgment as an implementation checkbox would create a circular gate.
