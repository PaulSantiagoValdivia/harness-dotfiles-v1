# Design: Fail-closed triangulation with a usable fresh-launch path

## Technical Approach

Repair A1–A6. Producer-root amendment: [registry design](design-registry-root.md).

## Architecture Decisions

| Option | Tradeoff | Decision |
|---|---|---|
| Exact slug/explicit alias vs newest directory | Operators must resolve missing mappings | Never use mtime; fail closed on ambiguity. |
| Complete verification vs skip-as-success | More runtime; exposes real product failures | All three executed PASS results precede publication. |
| Fresh launch with bounded reservations vs process discovery framework | Existing groups need owner handoff | Support safe new targets; unknown reuse/resume stays BLOCKED. |
| Diagnostic stop vs automatic cleanup | Owners handle eventual disposal | Stop never removes data, branches, worktrees or sessions. |

## Data Flow

Configuration → validated role/root/key → exact canonical authority → bounded handoff.

Launch intent → read-only preflight → atomic reservations → repeated checks → worktree creation → native launch → launch receipt, not coordination PASS.

Role commands → revision-bound results → promotion guards → receipt.

## Interfaces / Contracts

### Canonical mapping

Before mutations, start binds key to `backend/.claude/worktrees/triangulate-<key>/openspec/changes/<key>` or an explicit validated alias. Operator-owned `$HOME/.claude/triangulate-changes.conf` supplies literal `key=change-slug` aliases; parse data, never source/eval; support an override path.

Validate identifiers, unique keys/roles, existing repository roots and prospective path containment; reject conflicting aliases, traversal, escaping symlinks and unreadable config. Mapping identity is not artifact availability: fresh provisioning may create absent worktrees, but handoff MUST report BLOCKED for implementation until that exact canonical change exists. No missing-plan fallback or task suggestions. All roles use the same binding; output stays under 4000 bytes. Fixtures distinguish valid fresh provisioning from absent-artifact handoff.

### Functional verification

Keep `VERIFY_COMMANDS` in DevTools and enforce exact protocol parity:

- back/functions: `npm run typecheck && npm run format:check && npm run lint && npm run test:unit`.
- front: `npm run check:all`.
- app: `flutter analyze && flutter test`.

Backend scripts verified in `functions/package.json`. Verify required directories/scripts/tools. Results carry role, command, executed flag, state (`PASS`, `FAIL`, `SKIPPED`, `BLOCKED`, `TIMEOUT`), exit/result and tested revision. `VERIFY_SKIP=1` remains explicitly nonpromotable. Missing prerequisites/timeouts never PASS. Tests patch the subprocess runner, not production bypasses. Promotion requires executed PASS for all roles and unchanged verified revisions before its first push; retain immutable-SHA publication, ref races and partial receipts.

### Launch and stop

Validate slug, unique canonical repositories and selected targets; require successful authorized cmux readiness before fetch, worktree creation, DevTools startup or sends. Fresh admission requires every target path and branch absent. Directories are not owners.

Acquire nonblocking atomic `triangulate-launch.lock` directories in each Git common directory in order, recording a nonce; release only this invocation's reservations. Recheck target absence and preconditions while held. A competing invocation or unexplained existing reservation is BLOCKED, not auto-reclaimed. Keep reservations through creation/dispatch; partial failure preserves created state and reports recovery paths without cleanup.

Existing target/branch and resume require explicit owner handoff; this slice blocks new-writer resume rather than pretending directory/PID absence proves release. Document direct continuation through the existing native owner as the recovery route, and new-slug launch as the supported fresh path. `--force`/environment flags cannot bypass ownership or denied transport. Stop runs checked read-only inspection, reports uncertainty/pending work, and preserves everything.

## File Changes

| Paths | Change |
|---|---|
| `files/claude/hooks/triangulate-handoff.sh` | Deterministic mapping and blocked output. |
| `files/shared/bin/triangulate` | Fresh preflight/reservations; blocked reuse; diagnostic stop. |
| `files/shared/devtools/cocoa-devtools.py` | Complete commands/result admission. |
| `files/shared/skills/triangulation-orchestrator/references/protocol.md` | Shared mapping/lifecycle/verification/smoke contracts. |
| `tests/triangulate_launcher_test.sh`, `tests/cocoa_devtools_test.py`, new `tests/triangulate_handoff_test.sh` | RED/GREEN fixtures. |
| `tests/standalone_runtime_parity_test.sh`, `bootstrap.sh`, `verify.sh` | Scoped parity/test wiring as needed. |
| `docs/triangulation-safety.md`, audit document | Runbook and dispositions. |

## Testing Strategy

Strict TDD with focused Bash/Python fixtures then authorized `./verify.sh`. Exercise all role mappings, denied transport before mutation, same-target races, preserved historical groups, Git errors and stop nonmutation. Disposable Git remotes prove SKIPPED/FAIL/unit-test failures block first push and preserve existing race protections.

Live smoke requires authorized isolated cmux: bounded nonce/ACK, contract-revision ACK, safe read/test reassignment and three current receipts; stale receipts/timeouts fail. Record monotonic measurements only when executed. Current external socket restriction means BLOCKED, not simulated PASS.

## Threat Matrix

| Boundary | Applicability; safe/failure behavior; RED tests |
|---|---|
| Documentation-like paths | N/A: no executable classification. |
| Git repository selection | Applicable: quoted `git -C`, relative/absolute selectors; reject invalid roots/traversal; test each selector and spaces. |
| Commit state | N/A: no commit automation; dirty/staged preservation covered. |
| Push state | Applicable: tracking/first push/explicit refspec; require executed PASS and immutable SHA; test each plus changed refs/partial failure. |
| PR commands | N/A: no PR automation changes. |

## Rollout / Open Questions

Auto-chain autonomous ≤400-authored-line slices; keep tests/docs with behavior. Back up only managed deployment files, preserve user mapping/config and dual-client protocol parity. Rollback own slices without deleting recovery state. Live certification awaits authorized runtime.
