# Apply progress: harness-evidence-hardening

Diagnostics subset on `fix/harness-worktree-health`, base `a15470e`; Strict TDD, auto-chain / feature-branch-chain. Completed 1.1, 1.2, 1.4, 1.5. Local-exclude tests/runbook (1.3, 1.6) are now complete in the next slice; 1.7 ledger is coordinator-owned. Evidence implementation is complete; installed verification remains pending.

## TDD Cycle Evidence

Logs: `/tmp/harness-hardening-evidence/diagnostics-*.log`.

| Task | Safety net / layer | RED | GREEN | TRIANGULATE | REFACTOR |
| --- | --- | --- | --- | --- | --- |
| 1.1 | New helper; Git fixtures | red-identity: exit 1 | green-identity: exit 0 | Seven root cases | final-focused: exit 0 |
| 1.2 | Git fixtures | red-status: exit 1 | green-status: exit 0 | Clean/dirty/generated, rename/newline, status/list/ref errors | final-focused: exit 0 |
| 1.4 | baseline standalone parity + syntax: exit 0 | red-selector: exit 1 | green-selector: exit 0 | Real missing instructions vs stale, valid vs ancestor selector | final-focused: exit 0 |
| 1.5 | Previous GREEN | Tests above precede refactor | final-focused: exit 0 | Existing scenarios rerun | Checked parsing/exits retained; no unrelated cleanup |
| 1.3 | New Python/Git integration fixtures; diagnostics baseline exit 0 | protection-red / red-nonregular / red-rollback-ownership: exit 1 | protection-final: 9 tests, exit 0 | Main/linked, drift, symlink/FIFO, permissions, closed rollback | Lock cleanup/read helpers; all GREEN |
| 1.6 | Existing diagnostic guide; fixture-tested commands | protection-red-guidance: exit 1 | protection-final: exit 0 | Apply/rerun/rollback commands exercised; cache wording structural | Guide matches tool; no extra runtime |

| 2.1–2.2 | New contract/installer fixtures | evidence-red: exit 1 | evidence-green: exit 0 | Unknown defaults; fresh/customized HOME; backup/rerun/drift/restore | evidence-final: exit 0 |
| 2.3 | evidence-baseline standalone parity/syntax: exit 0 | evidence-red-wiring: exit 1 | evidence-green-wiring: exit 0 | Real bootstrap/parity stanzas; extra/supporting-file drift | evidence-final: exit 0 |
| 2.4 | Contract/tests precede docs | RED receipts above | evidence-final: exit 0 | Actual documented scoped installer; settings preserved | Syntax/new-script ShellCheck pass |

## Work Unit Evidence

| Evidence | Result |
| --- | --- |
| Focused | `bash tests/worktree_health_test.sh`: exit 0, two PASS groups (seven identity cases plus ownership/integration assertions). |
| Syntax/lint | `bash -n verify.sh files/shared/lib/worktree-health.sh tests/worktree_health_test.sh` and new-script `shellcheck -x`: exit 0. Existing verify lint remains SC2015/SC2088/SC2295; no new category. |
| Runtime | Source helper; invoke `health_each_root "$repo" health_audit_root` for back/front/app from triangulate.conf: exit 0, four stale records, real pending work/local-ref warnings retained (`diagnostics-runtime.log`). |
| Rollback | Revert health helper, verify wiring, fixture tests, and diagnostics guide together; no sibling mutations or installed configuration changes. |

No full `./verify.sh`, live ignore repair, commit, or push performed. Source-only helper deployment is part of the repository checkout, not global installation.

## Local-protection slice

`fix/harness-local-protection`, base `03cfb64`: source-only `files/shared/bin/harness-local-protect`, nine tests in `tests/local_protection_test.py`, runbook, and guarded cache wording. No framework or installer changes.

- Focused/runtime: `python3 tests/local_protection_test.py` → nine PASS, exit 0; real temporary main/linked Git prepare/apply/rerun/rollback, preserved index/HEAD/source, and failure paths. Existing health fixtures also pass (`protection-final.log`).
- Syntax: Python compilation and `bash -n verify.sh` pass. New tool/tests are Python (ShellCheck not applicable); verifier retains existing lint categories only.
- Rollback: use `python3 files/shared/bin/harness-local-protect rollback RECEIPT`; preserve receipt/sidecars. Revert only this slice's tool/tests/runbook/verify changes after any applied local operation is accounted for.
- Live sibling application, final installed `./verify.sh`, commits, pushes, and ledger completion remain coordinator-owned. No live ignore file was changed by this executor.

## Shared-evidence slice

`feat/harness-local-evidence`, base `4adfd0f`; 2.1–2.4 complete. Original shared skill/template plus a scoped installer, bootstrap/parity wiring, focused fixtures, and operator guidance. Task 1.7 complete per coordinator's 24-finding ledger.

- Focused/runtime: `bash tests/harness_evidence_test.sh` → exit 0, three PASS groups including actual installation/parity stanzas in isolated fresh/customized homes (`evidence-final.log`). No installed HOME writes; live parity follows scoped deployment.
- Syntax/new-script ShellCheck: exit 0. Template JSON parses; deliberately UNTESTED/null defaults prevent fabricated receipts. Test coverage proves structure, not future human observations.
- Rollback: inspect managed trees for subsequent work, restore per-client backup (or remove only newly installed tree), and revert this slice's helper/skill/wiring/docs together. Preserve global settings and other skills.
- Registry refresh deferred explicitly to coordinator after deployment; no project AGENTS registration needed for this globally installed shared skill. Existing source/project registry remains untouched.
- No full verify, live install, commit, or push by executor; Phase 3 and final verification remain pending.

## Coordinator deployment and final-verification handoff

All implementation tasks complete; final acceptance is NOT claimed. Source commit `75e2703`. Scoped installer invoked twice against the real HOME, backup root `/Users/cocoa/.harness-evidence-backup.6EtuDx`; full-tree Claude/Codex parity passes. SHA-256 checks of global Codex config and Claude settings match before/after. Installed standalone parity and 36/36 routing tests pass. Registry refreshed with 12 skills, including harness-evidence. No whole-home bootstrap, upstream installer, recorder or upload executed.

| Slice | Commit | Branch / immediate base | Authored lines | Push |
|---|---|---|---|---|
| Research/Astra tracker | 7d32c56 (Astra 0fb202b) | feat/harness-evidence-hardening / main | 223 | confirmed |
| Planning | 4965d46, a15470e | docs/harness-hardening-plan / tracker | 324 | confirmed |
| Diagnostics | 03cfb64 | fix/harness-worktree-health / planning | 271 | confirmed |
| Local protection | 4adfd0f | fix/harness-local-protection / diagnostics | 369 | confirmed |
| Shared evidence | 75e2703 | feat/harness-local-evidence / protection | 265 | confirmed |

Final verifier must run `./verify.sh`, retain `/tmp/harness-hardening-evidence/final-verify.log`, and map all 8 requirements/11 scenarios. The implementation checkbox handoff was clarified to avoid a circular prerequisite; no test result has been invented. Rollback boundaries remain per-slice; local protection uses its immutable receipt, skill deployment uses saved per-client trees after checking later edits. Product work and all recovery sources remain untouched.
