# Tasks: Integrate Codex as an Optional SDD Apply Backend

## Review Workload Forecast

| Field | Value |
|---|---|
| Estimated changed lines | 1,000–1,500 lines |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 packet/receipt → PR 2 apply integration → PR 3 overlays/runtime parity → PR 4 docs |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

| Unit | Goal / dependency | Focused test command | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| 1 | Transactional workflow; none | `bash tests/codex_sdd_backend_test.sh workflow` | fake-Codex repo | SDD branch in `codex-build.js` + fixture |
| 2 | Apply authority/progress; Unit 1 | `bash tests/codex_sdd_backend_test.sh apply` | resume/conflict disposable repos | apply skill/agent sections + fixtures |
| 3 | Installed runtime parity; Units 1–2 | `bash tests/codex_sdd_backend_test.sh runtime` | separate Claude/Direct-Codex Conductor smokes | bootstrap, verify, overlays, runtime fixtures |
| 4 | Docs; Units 1–3 | `./verify.sh` | native/standalone smoke | README/PRD prose |

## Phase 1: Workflow Transaction (Unit 1)

- [x] 1.1 **RED:** create `tests/codex_sdd_backend_test.sh` fixtures rejecting repo escape/wrong repo/mismatched `git -C`, pre-staged/`commit -a` leakage/empty commit, changed identities, dirty overlap, tampered receipt, and `spec-gap` with no commit.
- [x] 1.2 **GREEN:** extend `files/claude/workflows/codex-build.js` with versioned canonical packet/receipt hashing, isolated worktree, allowed-path/one-conventional-commit enforcement, RED-GREEN-REFACTOR records, audit, and fail-closed structured results; preserve standalone fan-out.
- [x] 1.3 **REFACTOR:** run `node --check files/claude/workflows/codex-build.js` and the workflow fixture; remove duplication without broadening ownership.

## Phase 2: Apply Authority and Resume (Unit 2)

- [x] 2.1 **RED:** add apply fixtures for default-native/explicit routing, one-next-unit selection, duplicate/partial lineage, receipt/tree mismatch, conflict, failed authoritative gate, and integration-without-progress reconciliation.
- [x] 2.2 **GREEN:** update `files/claude/skills/sdd-apply/SKILL.md` and `files/claude/agents/sdd-apply.md` so apply alone checks eligibility, invokes Codex, validates/cherry-picks onto unchanged HEAD, reruns `./verify.sh`, and atomically records lineage/tasks/progress.
- [x] 2.3 **REFACTOR:** prove no silent fallback, no OpenSpec workflow writes, no destructive Git recovery, and independent `sdd-verify` remains required.

## Phase 3: Bootstrap and Live Runtime Parity (Unit 3)

- [x] 3.1 **RED:** extend `tests/bootstrap_codex_config_test.sh` and runtime fixtures for fresh/idempotent installs, preference/backups, overlay equality, `codexBin`, missing prerequisites, unsupported `[agents]` scalars, and exactly one Engram provider.
- [x] 3.2 **GREEN:** update `bootstrap.sh`, `verify.sh`, `files/claude/CLAUDE.md`, `files/codex/AGENTS.md`, and `files/conductor/settings.toml` to install client-specific overlays while preserving native default and user settings.
- [ ] 3.3 Validate Claude-in-Conductor live discovery/invocation and structured receipt at medium effort; separately validate direct bundled Codex strict startup, native SDD/Engram behavior, medium default/high review, and zero `codex-build` invocation; also check global Codex.

## Phase 4: Documentation and Full Gate (Unit 4)

- [x] 4.1 Update `README.md` and `docs/PRD.md` with routing, authority, both Conductor paths, rollback, and compatibility.
- [x] 4.2 Run `bash -n bootstrap.sh verify.sh tests/*.sh`, both `node --check` commands, then `./verify.sh`; record exact results and rollback boundaries per unit.

## Overlap Risk

The dirty tree overlaps every planned production area plus `tests/`; apply MUST preserve those edits, never reset them, and stop if path ownership is ambiguous.
