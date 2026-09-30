# Tasks: Triangulation safety

## Review Workload Forecast
| Field | Value |
| --- | --- |
| Estimated authored lines | 1000–1500 implementation/docs/tests |
| Delivery strategy | auto-chain |
| Per-child boundary | ≤400 additions+deletions, including progress |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High
Registry amendment: ≤350 lines; focused `bash tests/skill_registry_root_test.sh`, disposable roots/installations, rollback helper/hook backups.

Children target predecessors; split above 400. One writer; Strict TDD `./verify.sh`, focused RED/GREEN.

### Autonomous Work Units
| Unit / estimate | Start → finish | Focused command | Runtime/rollback |
| --- | --- | --- | --- |
| Authority / 200–300 | Planning → deterministic handoff | `bash tests/triangulate_handoff_test.sh` | Three-role fixture handoff; revert hook/tests/protocol |
| Verification / 280–390 | Authority → executed-PASS gates | `python3 tests/cocoa_devtools_test.py` | Temporary remotes; revert server/tests/protocol |
| Diagnostic-stop / 120–220 | Gates → non-destructive stop | `bash tests/triangulate_launcher_test.sh` | Temporary worktrees; revert stop/tests/docs without cleanup |
| Fresh-launch / 280–390 | Safe stop → reserved launch | `bash tests/triangulate_launcher_test.sh` | Mock cmux, real temporary Git; revert launcher/tests, preserve reservations |
| Smoke/dispositions / 120–200 | Fixes → evidence | Focused suites above + scoped parity | Authorized probe or BLOCKED; revert managed docs/wiring only |

## 1. Authority
- [x] 1.1 RED `tests/triangulate_handoff_test.sh`: role/authority/error/path/budget cases.
- [x] 1.2 GREEN `triangulate-handoff.sh`: bind declared identity/aliases; no mtime fallback or blocked task suggestions; rerun 1.1, then REFACTOR.
- [x] 1.3 Update shared protocol and scoped installation/parity fixtures: fresh/customized homes, mapping preservation, backups/rerun/restore.

## 2. Functional verification
- [x] 2.1 RED `tests/cocoa_devtools_test.py`: complete commands/prerequisites; SKIPPED/FAIL/TIMEOUT/unknown cannot push; inject runners instead of VERIFY_SKIP success.
- [x] 2.2 RED temporary-remote admission/race/partial-publication cases.
- [x] 2.3 GREEN DevTools executed/result/revision admission and exact protocol commands; retain format:check; rerun after REFACTOR.

## 3. Diagnostic stop
- [x] 3.1 RED launcher fixtures: status/ref failures, unknown generated-looking files, dirty/unpublished work, and live/unknown ownership never authorize removal.
- [x] 3.2 GREEN report-only stop; assert unchanged files/index/refs/worktrees/sessions, rerun fixtures, document preserved-state recovery.

- [x] 3.3 RED registry fixtures: nested main/linked roots, aliases, HOME/nonrepo/Git errors, scoped config preservation/backups/rerun.
- [x] 3.4 GREEN shared helper/recognized-command patcher, Claude declaration, post-upstream bootstrap and verify wiring; rerun/refactor.

## 4. Fresh launch
- [x] 4.1 RED launcher fixtures: denied transport before any mutation, invalid selectors, historical groups, target races, unknown locks, force/reuse/resume refusal, and partial dispatch preservation.
- [x] 4.2 GREEN preflight/binding, atomic reservations/recheck, fresh-only admission; release only own nonce; rerun after REFACTOR.
- [x] 4.3 Prove fresh provisioning versus missing-artifact BLOCKED handoff; launch is topology, not coordination PASS.

## 5. Evidence and deployment
- [x] 5.1 Document authorized smoke in `docs/triangulation-safety.md`: nonce/revision ACK, safe reassignment, current three-role receipts, stale/timeout rejection, measured latencies; no smoke framework.
- [x] 5.2 Wire focused suites into `verify.sh`; back up/deploy managed files; prove parity and configuration preservation.
- [x] 5.3 Prepare fourteen-scenario/A1–A6 evidence map and full-run handoff; dedicated final verifier owns one `./verify.sh`. Live smoke remains BLOCKED.

Clarification: slug declares prospective authority; absent artifacts block implementation, not fresh provisioning. Explicit aliases; retained format:check.
