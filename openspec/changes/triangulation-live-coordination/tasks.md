# Tasks: Native triangulation coordination

## Review Workload Forecast
| Field | Value |
|---|---|
| Estimated authored changed lines | 420–650 implementation/tests/docs; planning separately |
| Delivery strategy | auto-chain |
| Tracker | `fix/triangulation-live-coordination` (planning/current branch) |
| Slice 1 base | tracker |
| Slice 2 base | slice 1 branch |
Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

## Work Units
| Unit | Start → finish | Focused command / runtime harness | Rollback |
|---|---|---|---|
| 1: startup readiness, ≤400 lines | Approved planning → role-isolated packets and minimal finite readiness contract | `bash tests/triangulate_launcher_test.sh`; real launcher with captured argv/fake clients | Revert launcher, packet tests, associated protocol changes |
| 2: autonomy/evidence, ≤400 lines | Slice 1 → autonomous routing, C2 regression, scoped deployment receipts | `bash tests/triangulation_evidence_test.sh`; extracted recipe/fake npm; `bash tests/triangulate_handoff_test.sh` disposable-home deployment | Revert slice-2 docs/tests/skill deltas; restore managed backups |

One implementation writer. Each slice includes its tests/docs, conventional commit, measured additions+deletions, push, clean parent-relative diff, and receipt. Repartition before exceeding 400 lines; no implicit exception. Tracker remains draft/no-merge until integration; PR targets follow the cached chain, not protected branches.

## Phase 1: Role-aware startup and readiness
- [x] 1.1 Preserve old verification-report identity; record source snapshot and supplied launcher baseline PASS/exit 0 (62.999s), `/tmp/triangulation-live-coordination-evidence/baseline-launcher.*`.
- [x] 1.2 RED: extend `tests/triangulate_launcher_test.sh` to capture actual plan/dispatch argv for both clients; assert roles, aliases, spaced absolute paths, relative-mapping rejection, and ownership isolation.
- [x] 1.3 RED: assert shared/fresh 128-bit nonce, skill activation, worker forwarding/no-delegation, HELLO/ACK fields, two-worker gate, invalid-ACK rejection instructions, two discovery attempts/one event-triggered or scheduled retry within 10 seconds, one follow-up, 120-second deadline from HELLO, and UNTESTED output; absent artifacts permit discovery/SDD only, dispatch ACK binds current contract-revision hash, changes require fresh ACK.
- [x] 1.4 GREEN: implement shared packet builder in `files/shared/bin/triangulate`; document matching minimal readiness rules in shared `references/protocol.md`; preserve topology/security/fresh-target safeguards.
- [x] 1.5 REFACTOR: run focused launcher suite and `bash -n files/shared/bin/triangulate`; record real exits and mocked-transport limitation; commit/push slice 1 within budget.

## Phase 2: Autonomy and explicit C2 amendment
- [x] 2.1 RED: test autonomy/escalation contract and truthful labels; replace handwritten aggregate surrogate with exact docs-recipe extraction in `tests/triangulation_evidence_test.sh`.
- [x] 2.2 RED: fake npm exercises all-success, each failing gate, and multiple distinct failures; assert invocation order, retained logs, and documented aggregate exit policy.
- [x] 2.3 GREEN: update shared skill/protocol and `docs/triangulation-safety.md`; keep original C2 failure historical, C1 smoke pending, and prompt-compliance limitations explicit.
- [x] 2.4 Verify fresh/idempotent managed deployment in disposable homes; back up and deploy only launcher/shared skills; prove installed parity and preserved settings/mappings. Record rollback paths.
- [x] 2.5 REFACTOR: run focused evidence/handoff checks; record exits, unchanged historical-report identity, diff budget, commit/push slice 2.

## Phase 3: Independent verification handoff
- [x] 3.1 Consolidate per-slice snapshot/RED→GREEN/deployment receipts and completed implementation tasks; dedicated verifier then runs ONE full `./verify.sh`, not an apply prerequisite.
- [x] 3.2 Report instruction-contract verification separately from operational certification. Actual authorized native ACK/follow-up/three-receipt smoke remains a dependency; retain original C1 BLOCKED/UNTESTED without simulation or bypass.
