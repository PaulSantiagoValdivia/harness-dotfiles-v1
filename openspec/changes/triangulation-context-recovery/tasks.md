# Tasks: Triangulation Context Recovery

## Review Workload Forecast
- Estimated authored changes: planning 300–390; source slices 700–1100 total. Count tests/docs/progress too.
- Delivery strategy: auto-chain; cached execution: auto; artifact store: openspec.
Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Work Units
Tracker → planning (`fix/triangulation-context-recovery`) → warnings → checkpoint → wiring/install. Child base = predecessor; tracker targets default (no origin/dev). Split checkpoint into 2a bounded mode/parser and 2b rich identity/process/receipt validation if needed; each carries safety tests. No size exception.

| Unit / start → finish | Budget | Focused command / runtime harness | Rollback |
|---|---|---|---|
| Planning: baseline → approved artifacts | <400 | Inspect artifact references; runtime N/A, documentation only | Change artifacts |
| Warnings: approved plan → safe compact lifecycle | 200–300 | `bash tests/context_budget_test.sh`; disposable transcript/cache events | Warning scripts, event entry, guidance, tests |
| Checkpoint: warnings → bounded recovery facts | 280–390 | `bash tests/triangulate_handoff_test.sh`; disposable Git worktrees | Checkpoint reader/protocol/tests |
| Wiring/install: checkpoint → client deployment parity | 220–390 | `bash tests/triangulation_recovery_install_test.sh`; disposable homes/rollback | Scoped installer, client wiring/prompts/tests |

## 1. Planning boundary
- [x] 1.1 Commit/push planning separately; inspect clean parent diff and sibling status; coordinator alone maintains `state.yaml`.

## 2. Warning lifecycle — RED → GREEN → REFACTOR
- [x] 2.1 RED `tests/context_budget_test.sh`: exact threshold/quiet cases; A/B isolation, unsafe session/cache paths, compact with stale transcript usage, new low/critical measurements; zero-fork fail-open reader.
- [x] 2.2 GREEN warning scripts and compact event entry in `files/claude/settings.json`; prevent precompact measurement resurrection without disabling critical protection.
- [x] 2.3 Update `files/shared/runtime-budget.md`, corresponding managed client blocks and CLAUDE context override: measured thresholds, taxonomy, same-task compact; no clear/reset/relaunch mandate. Refactor; retain RED/GREEN receipts.

## 3. Canonical checkpoint — RED → GREEN → REFACTOR
- [x] 3.1 RED handoff fixtures: relative/absolute/spaced Git roots and wrong repository; schema/duplicate/unknown keys, types/enums, 8192-byte limit, controls, symlinks, identity, stale HEAD/hashes, multibyte output/safety footer, inert command strings.
- [x] 3.2 RED mode aliases/conflicts, absent legacy checkpoint, process/receipt pointers and pushed-but-PR-pending continuity; unavailable native channel never certifies readiness.
- [x] 3.3 GREEN `triangulate-handoff.sh` and protocol checkpoint contract per design; coordinator-owned per-role files, current validation and <3999-byte output. Refactor and record focused receipts.

## 4. Wiring and scoped rollout — RED → GREEN → REFACTOR
- [x] 4.1 RED installer fixtures: fresh/customized/rerun/rollback, backup collisions, symlinks, concurrent changes, ambiguous overlays and unrelated settings/mappings preservation.
- [x] 4.2 GREEN `install-triangulation-recovery.py`, supported recovery matchers and targeted Codex compact prompt; reuse shared-skill installer. Register tests in `verify.sh`; no full bootstrap.
- [x] 4.3 Refactor; run all three focused suites, source syntax checks and disposable install lifecycle; record exact revision/dirty state and rollback boundaries.

## 5. Final verification and delivery
- Verification gate (not an apply task): verify final candidate with `./verify.sh`; map six requirements/nine scenarios. One normal fresh final review.
- [x] 5.2 Coordinator performs authorized scoped install/parity/preservation probes using isolated HOME; reuse private measurement. Native unavailable remains BLOCKED.
- Delivery gate (not an apply task): commit/push slices; report branches/PR bases, tests and pending delivery; archive after required gates.
