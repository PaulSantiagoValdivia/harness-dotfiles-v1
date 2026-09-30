# Apply Progress: Integrate Codex as an Optional SDD Apply Backend

## Current Batch

- Work unit: Unit 1 — Workflow Transaction
- Delivery: chained PRs
- Chain strategy: `feature-branch-chain`
- Status: blocked before RED
- Base revision: `8b8c78d88304de56add16e4512c6ad36b5714282`

## Blocker

Unit 1 requires changing `files/claude/workflows/codex-build.js`, but that file
already contains unattributed working-tree edits on `main`. The existing diff
changes the standalone fan-out control flow (`MAX_PARALLEL`, batching, and
`pipeline` invocation), which is behavior Unit 1 must preserve while adding an
SDD-mode entry path. Because the new transaction implementation would touch the
same control-flow boundary, ownership cannot be separated safely without the
maintainer first preserving or identifying those edits.

No production code or tests were written, no task checkbox was changed, and no
commit or PR was created. No reset, clean, stash, checkout, or destructive Git
operation was used.

## TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 1.1–1.3 | Not started — workspace ownership gate blocked before test creation | Not started | Not started |

## Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | Not run — blocked before RED; `tests/codex_sdd_backend_test.sh` does not exist |
| Runtime harness | Not run — the fake-Codex fixture belongs to the blocked unit |
| Rollback boundary | No implementation exists; remove only this progress record to undo this blocked-attempt metadata |

## Safe Recovery

Preserve the current `codex-build.js` edits in a maintainer-owned commit or
separate branch, then start Unit 1 from a clean, attributable base that includes
those edits. Alternatively, explicitly declare those edits part of Unit 1 so
the executor can test and commit them together. Do not discard them.

## Resumption — Unit 1 Completed

The user explicitly authorized the existing uncommitted
`files/claude/workflows/codex-build.js` state as Unit 1's preserved baseline.
Implementation resumed without reverting or claiming those earlier fan-out
changes.

### Completed Tasks

- [x] 1.1 Added executable VM-backed workflow fixtures for packet eligibility,
  repository and path boundaries, dirty overlap, identity changes, rejected
  execution states, tampered audit evidence, `spec-gap`, and standalone mode.
- [x] 1.2 Added opt-in `mode: "sdd"` packet validation, single-unit execution,
  isolated worktree instructions, candidate validation, independent audit, and
  a versioned content-bound receipt. Native standalone fan-out remains the
  default path.
- [x] 1.3 Triangulated rejection and compatibility paths, ran syntax checking,
  the focused fixture, and the authoritative repository gate.

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 1.1–1.2 | `bash tests/codex_sdd_backend_test.sh workflow` exited 1: first invalid packet returned no structured `rejected` status | Same command exited 0: `codex SDD workflow fixtures: 15 passed` | Expanded audit-tampering and standalone triangulation; command exited 0: `20 passed` |
| 1.3 | Syntax/fixture requirements were already represented by the failing workflow fixture | `node --check files/claude/workflows/codex-build.js` exited 0 | Combined focused fixture plus syntax check exited 0 with unchanged HEAD/status |

All recorded commands ran at revision
`8b8c78d88304de56add16e4512c6ad36b5714282`; HEAD and working-tree status were
unchanged during each evidence command.

### Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | `bash tests/codex_sdd_backend_test.sh workflow` → exit 0, `20 passed` |
| Runtime harness | VM-executed workflow with fake Execute/Audit Codex agents and fake worktree identities → accepted receipt, fail-closed rejection/spec-gap, and standalone compatibility all passed |
| Syntax | `node --check files/claude/workflows/codex-build.js` → exit 0 |
| Authoritative gate | `./verify.sh` → exit 0, `153 PASS / 1 WARN / 0 FAIL`; warning is the documented sandboxed Claude MCP health check |
| Rollback boundary | Remove only `mode: "sdd"` validation/execution/audit additions in `files/claude/workflows/codex-build.js` and `tests/codex_sdd_backend_test.sh`; retain the pre-authorized standalone concurrency baseline |

### Attribution and Delivery

- Attributable Unit 1 implementation is approximately 321 authored lines: the
  new SDD workflow block plus the 169-line fixture. The pre-existing standalone
  fan-out diff is excluded from this attribution.
- No commit or PR was created. The repository remains on dirty `main`, and the
  workflow file contains both the authorized earlier baseline and Unit 1 in one
  working-tree diff; creating a commit here would risk claiming unrelated work
  and would bypass the required issue/branch preflight.
- Chain strategy remains `feature-branch-chain`; Unit 2 is the next autonomous
  slice.

## Unit 2 — Apply Authority and Resume

### Ownership Gate

`files/claude/skills/sdd-apply/SKILL.md` contained pre-existing unrelated edits
before Unit 2. Unit 2 preserved every existing hunk and added one self-contained
Codex backend section without modifying those earlier changes.
`files/claude/agents/sdd-apply.md` was clean before this unit. No ownership was
assumed for the pre-existing skill diff.

### Completed Tasks

- [x] 2.1 Added apply contract fixtures for explicit/default routing,
  next-unit ordering, duplicate/partial lineage, receipt/tree validation,
  conflict/gate stops, and integration-without-progress reconciliation.
- [x] 2.2 Added the `sdd-apply` eligibility, immutable packet, workflow
  invocation, receipt validation, unchanged-HEAD integration, authoritative
  rerun, and sole-writer persistence contract; forwarded it through the apply
  agent.
- [x] 2.3 Proved no silent fallback, no workflow-owned OpenSpec progress, no
  destructive recovery, and independent `sdd-verify` retention.

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 2.1–2.2 | `bash tests/codex_sdd_backend_test.sh apply` exited 1 with `missing apply contract: explicit native/codex routing` | After the minimum authority/routing contract, the focused fixture reached the remaining contract assertions and then exited 0 | Added negative workflow-ownership assertion and reran both apply and Unit 1 workflow fixtures |
| 2.3 | Prohibitions were explicit failing assertions in the RED fixture | Apply contract fixture exited 0 | `apply`: `19 passed`; `workflow`: `20 passed`; Bash syntax exited 0 |

All commands ran at revision
`8b8c78d88304de56add16e4512c6ad36b5714282`; HEAD and working-tree status were
unchanged during each recorded gate.

### Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused test | `bash tests/codex_sdd_backend_test.sh apply` → exit 0, `19 passed` |
| Regression fixture | `bash tests/codex_sdd_backend_test.sh workflow` → exit 0, `20 passed` |
| Runtime harness | Apply is an instruction/agent routing boundary rather than an executable library; VM-backed workflow runtime from Unit 1 remained green, while Unit 2's executable contract fixture validates the caller boundary |
| Syntax | `bash -n tests/codex_sdd_backend_test.sh` → exit 0 |
| Authoritative gate | `./verify.sh` → exit 0, `153 PASS / 1 WARN / 0 FAIL`; warning remains the documented sandboxed Claude MCP health check |
| Rollback boundary | Remove only `Optional Codex SDD Execution Backend` from the apply skill, `Optional Codex Backend` from the apply agent, and the `apply` fixture branch; retain Unit 1 and all earlier skill edits |

### Delivery

- No commit or PR was created. The apply skill's working-tree diff contains
  pre-existing unauthorized edits plus Unit 2, so a normal whole-file commit
  would falsely attribute unrelated work; issue/branch preflight is also absent.
- Chain strategy remains `feature-branch-chain`. Unit 3 is the next autonomous
  slice.

## Unit 3 — Bootstrap and Runtime Parity (Partial)

### Ownership Gate

The bootstrap, verify, Claude instructions, Codex instructions, Conductor
settings, and bootstrap fixture already contained extensive user changes. This
unit preserved those hunks and added only isolated runtime-contract sections, a
new runtime fixture, and one new verify invocation. Existing bootstrap behavior
was treated as baseline and verified, not claimed as newly authored.

### Completed Tasks

- [x] 3.1 Added `tests/conductor_runtime_parity_test.sh` while retaining the
  existing isolated fresh/idempotent bootstrap fixture. The new fixture checks
  installed/source workflow equality, transactional receipt execution,
  executable `codexBin`, Claude discovery, Conductor DB efforts, direct Codex
  native policy, one Engram provider, SDD presence, and strict startup with both
  global and bundled Codex.
- [x] 3.2 Added client-specific routing contracts to Claude/Codex overlays and
  wired the runtime fixture into `verify.sh`. Ran real `bootstrap.sh --yes`,
  which created backup `/Users/cocoa/.harness-backup-20260731-134831`, preserved
  preferences, refreshed overlays, and kept the direct Engram MCP unique.
- [ ] 3.3 Direct Codex validation is complete, but a real non-interactive Claude
  invocation could not authenticate: `Not logged in · Please run /login`.
  Workflow discovery, binary startup, installed overlay equality, and the real
  transactional receipt harness pass, but end-to-end Claude model-driven
  workflow invocation cannot be honestly claimed until login is restored.

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 3.1–3.2 | `bash tests/conductor_runtime_parity_test.sh` exited 1: installed Claude workflow differed from source | After bootstrap installed the source overlays, the runtime fixture exited 0 for separate Claude/direct-Codex paths | `bash -n bootstrap.sh verify.sh tests/*.sh`, isolated bootstrap twice-per-fixture, runtime parity, and full verify passed |
| 3.3 | Live Claude `-p` invocation returned an authentication error before API/tool execution | Direct bundled/global Codex strict startup and native-policy checks passed | Claude half remains blocked by login, so task stays unchecked |

Recorded repository gates ran at revision
`8b8c78d88304de56add16e4512c6ad36b5714282` with unchanged Git HEAD/status.

### Work Unit Evidence

| Evidence | Result |
|---|---|
| Bootstrap fixture | `bash tests/bootstrap_codex_config_test.sh` → exit 0; clean HOME, existing role, two runs each, strict global/bundled Codex |
| Runtime fixture | `bash tests/conductor_runtime_parity_test.sh` → exit 0; Claude installed-route/receipt harness and direct Codex native path pass separately |
| Claude live attempt | `claude -p --effort medium ...` → exit 1 before tool/API execution, `Not logged in · Please run /login`; no files changed |
| Direct Codex live startup | Both `/usr/local/bin/codex` and Conductor bundled 0.144.1 accepted `app-server --strict-config`; bundled binary emitted only its sandbox PATH-alias warning |
| Authoritative gate | `./verify.sh` → exit 0, `154 PASS / 1 WARN / 0 FAIL` |
| Rollback boundary | Remove the new routing sections in Claude/Codex instruction sources, the one runtime check in `verify.sh`, and `tests/conductor_runtime_parity_test.sh`; restore home overlays from the recorded bootstrap backup if operational rollback is needed |

### Delivery and Blocker

- No commit or PR was created because all major source targets contain
  pre-existing user changes and issue/branch gates are absent.
- Unit 3 remains partial until Claude login allows one real workflow invocation
  that returns a structured rejection/receipt. Direct Codex parity is proven.

## Unit 4 — Documentation and Full Gate

### Completed Tasks

- [x] 4.1 Added a scan-first two-path operator guide to `README.md` and an
  evidence table/checklist to `docs/PRD.md`. Both state native routing authority,
  Claude `codex-build` receipt behavior, direct Codex bypass, rollback, verified
  compatibility, and the exact pending Claude login blocker.
- [x] 4.2 Added nine documentation contract fixtures and ran every required
  syntax, focused, and authoritative command.

Task 3.3 remains unchecked. Unit 4 documentation does not convert discovery or
the VM receipt harness into a fabricated authenticated Claude invocation.

### TDD Cycle Evidence

| Task | RED | GREEN | REFACTOR |
|---|---|---|---|
| 4.1 | `bash tests/codex_sdd_backend_test.sh docs` exited 1: `missing docs contract: explicit routing` | After the operator/PRD sections were added, the same fixture exited 0 with `9 passed` | Reduced recall with one routing table, one command block, rollback steps, and a dated evidence table; all earlier apply/workflow fixtures remained green |
| 4.2 | Required command checklist was encoded before the final documentation edits | Bash and both workflow syntax checks exited 0 | `./verify.sh` exited 0 with `154 PASS / 1 WARN / 0 FAIL` |

All commands ran at Git revision
`8b8c78d88304de56add16e4512c6ad36b5714282`; HEAD and working-tree status were
unchanged during each recorded gate.

### Work Unit Evidence

| Evidence | Result |
|---|---|
| Focused documentation test | `bash tests/codex_sdd_backend_test.sh docs` → exit 0, `9 passed` |
| Regression fixtures | Apply contract `19 passed`; workflow runtime `20 passed` |
| Required syntax | `bash -n bootstrap.sh verify.sh tests/*.sh` → exit 0; `node --check` for `codex-build.js` and `dual-review.js` → exit 0 |
| Runtime harness | `./verify.sh` includes `tests/conductor_runtime_parity_test.sh` and exited 0 with `154 PASS / 1 WARN / 0 FAIL` |
| Rollback boundary | Remove only the `Codex durante SDD` README section, PRD §8.0, and the `docs` fixture branch; retain Units 1–3 and all pre-existing documentation edits |

### Delivery and Remaining Blocker

- No commit or PR was created because both documentation files already
  contained extensive user changes and branch/issue gates are absent.
- Remaining implementation blocker: task 3.3 requires Claude `/login`, followed
  by a real medium-effort `codex-build` invocation returning structured evidence
  without mutation. All Unit 4 tasks are complete, but the overall apply phase
  is not ready for `sdd-verify` until 3.3 is proven.
