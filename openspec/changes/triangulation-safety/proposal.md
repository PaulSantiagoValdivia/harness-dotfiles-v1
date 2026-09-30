# Proposal: Fail-closed triangulation safety

## Intent
Repair A1–A6 without touching product work or equating launched sessions with verified coordination. Missing evidence must fail closed.

## Scope
### In Scope
- Explicit worktree-key → canonical OpenSpec mapping, validated consistently across roles; actionable BLOCKED output when absent, ambiguous, or invalid.
- Complete backend/panel/app verification commands and executed-PASS promotion admission; skipped, failed, timed-out, or unavailable checks cannot authorize publication.
- Authorized cmux and ownership preflight before launch/resume mutations; no directory-age liveness inference or same-slug exemption.
- Non-destructive diagnostic stop preserving sessions, worktrees, branches, and data; Git inspection errors remain BLOCKED.
- Isolated regression fixtures, scoped installation parity, audit dispositions, and a bounded live-smoke contract with honest UNTESTED/BLOCKED outcomes.
### Out of Scope
New daemons/process managers, product changes/promotions, cleanup, forced handoffs, guessed aliases, weakening tests, bypassing cmux access, or claiming simulated messages as real evidence.

## Capabilities
### New Capabilities
- `triangulation-authority`: Explicit canonical mapping and bounded recovery guidance.
- `triangulation-verification`: Complete role commands, execution-state admission, and trustworthy smoke evidence.
- `triangulation-lifecycle-safety`: Preflight/ownership gates and non-destructive diagnostics.
### Modified Capabilities
None; main specifications are empty.

## Approach
Use Strict TDD and feature-branch-chain slices. Replace mtime fallback with operator configuration. Enforce executable/protocol command parity. Inject fixture runners, never production success bypasses. Require three executed results before publication; preserve ref-race/partial-promotion protections.

Resolve native owner identity when available; uncertain ownership or denied transport blocks launch without Git mutation. Make stop inspect/report only. Keep topology fixtures, but reserve coordination PASS for authorized isolated nonce/ACK, contract-update acknowledgement, safe reassignment, and current three-role receipts with bounded timing.

## Affected Areas
| Area | Impact |
| --- | --- |
| `files/claude/hooks/triangulate-handoff.sh` | Explicit authority |
| `files/shared/bin/triangulate` | Preflight and diagnostic stop |
| `files/shared/devtools/cocoa-devtools.py` | Verification admission |
| Shared triangulation protocol, `tests/`, `bootstrap.sh`, `verify.sh` | Parity, fixtures, scoped deployment |
| `docs/` | Mapping/runbook and A1–A6 dispositions |

## Risks
Missing mappings or unavailable cmux can block workflows. Stronger gates may expose product failures; report them rather than changing product code. Live certification remains unavailable from this external session.

## Rollback Plan
Restore backed-up managed files or revert individual slices. Preserve operator mappings, evidence, sessions, and product work. Do not re-enable unsafe bypasses merely to recover convenience; retain BLOCKED status where necessary.

## Dependencies
Dated audit, explicit mapping/ownership evidence, and authorized cmux for live smoke—not isolated tests.

## Success Criteria
- [ ] All A1–A6 have tested corrections or explicit environmental dispositions.
- [ ] No heuristic authority, skipped-check promotion, unsafe stop, or preflight-failure mutation.
- [ ] Required command/installed-source parity passes; other runtime behavior remains intact.
- [ ] Live outcomes identify actual evidence, missing prerequisites, and limits without invented success or latency.
