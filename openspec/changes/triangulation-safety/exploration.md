## Exploration: Triangulation safety

### Current State

Correct A1–A6 with explicit authority, complete functional gates, and non-destructive failure behavior. Preserve the distinction between a launcher contract and demonstrated coordination.

The authoritative audit is `docs/research/cmux-triangulation-audit-2026-09-09.md`. This exploration checked its findings against current source without operating product sessions. `openspec/config.yaml` retains Strict TDD; main specs currently contain no domain specifications.

| Finding | Confirmed source behavior | Minimum correction |
| --- | --- | --- |
| A1 | `triangulate-handoff.sh` falls back from exact slug to newest change directory via `ls -dt`. | Explicit worktree-key → canonical change mapping; missing, ambiguous, or invalid mapping reports BLOCKED without task suggestions. |
| A2 | DevTools backend omits lint/unit tests; app omits `flutter test`. | Full role contract: backend typecheck + lint + test:unit; panel check:all; app analyze + test. Missing commands/prerequisites block verification. |
| A3 | `VERIFY_SKIP=1` yields returncode 0; promotion checks returncode only. | Explicit non-promotable SKIPPED/BLOCKED state; promotion requires executed PASS. Fixtures inject the runner instead of activating production bypass. |
| A4 | Directory counting blocks other slugs but exempts the same slug without ownership proof. | Directory existence means preserved workspace, not live writer. Validate available native session/owner identity; uncertain or duplicate ownership blocks launch/resume. |
| A5 | Stop maps status/ref errors to clean/zero, filters whole directories, and falls back to forced removal. | Make stop report-only/non-destructive; Git errors and unknown owners produce BLOCKED, never implied cleanup success. |
| A6 | Launcher tests mock cmux; parity tests inspect contracts. | Label these precisely and define a bounded, isolated live smoke requiring real messaging evidence; unavailable transport stays BLOCKED. |

`start` currently calls `ensure_worktrees` before reaching cmux workspace creation. A denied socket can therefore leave Git changes without a viable launch. Move authorized cmux readiness checks before any worktree mutation; do not bypass access restrictions.

### Affected Areas

- `files/claude/hooks/triangulate-handoff.sh` — authority resolution and bounded blocked output.
- `files/shared/bin/triangulate` — preflight ordering, launch/resume ownership, non-destructive stop, truthful readiness wording.
- `files/shared/devtools/cocoa-devtools.py` — complete role commands, explicit execution states, promotion admission.
- `files/shared/skills/triangulation-orchestrator/references/protocol.md` — explicit mapping, ownership, required commands, and smoke evidence contract shared by both clients.
- `tests/triangulate_launcher_test.sh`, `tests/cocoa_devtools_test.py`, focused handoff/smoke fixtures — test missing mappings, skipped/failed tests, blocked transport, and preservation.
- `bootstrap.sh`, `verify.sh`, parity tests — scoped deployment and source/installed parity for changed contracts.

### Approaches

1. **Surgical fail-closed corrections** — explicit mapping, authoritative command contract, runner injection, preflight before mutation, report-only stop, bounded smoke admission.
   - Pros: Repairs demonstrated failures without touching product work or adding a daemon.
   - Cons: Unverified ownership or unavailable cmux remains BLOCKED; operators must supply missing mapping/handoff evidence.
   - Effort: Medium; split into autonomous ≤400-line slices.
2. **New lifecycle/process manager** — persistent leases, automatic process discovery/recovery, cleanup automation.
   - Pros: Could automate future recovery.
   - Cons: Larger unproven ownership/security surface; unnecessary for current safe behavior.
   - Effort: High; defer.

### Recommendation

Choose approach 1. Keep one explicit canonical mapping resolved consistently for all roles; never infer aliases for current groups or use mtime. Store required commands in one shared contract or enforce exact source/protocol parity; retain current stricter checks where compatible. Bind verification to actual execution and current revision, with all three role gates passing before any publication attempt. Keep existing ref-race/partial-promotion protections.

Use narrowly recorded owner/session identifiers and explicit handoff evidence where available, not directory age, archive state, or PID existence alone. If native liveness cannot be established, block start/resume without mutating anything. Report-only stop preserves all branches, worktrees, ignored files, and running sessions; cleanup need not be invented to fix a dangerous stop path.

The live smoke must use disposable repositories and an authorized separate cmux context: nonce/ACK for both workers, contract-revision ACK, safe read/test reassignment, three revision-bound receipts, stale-receipt rejection, timeouts, and measured monotonic latencies. Fixture success is not live success. Here the socket restriction makes that smoke BLOCKED; record the exact prerequisite rather than fabricating measurements or starting product agents.

### Risks

- Existing groups need owner-supplied mapping; guessing would recreate A1.
- Stronger functional gates may reveal real product failures; do not weaken commands or change product code to pass this harness change.
- An archived directory or clean Git status does not prove its writer stopped.
- Changing stop to preservation/reporting is an intentional safety-compatible behavior change that needs operator guidance.
- Live coordination cannot be certified from this external session. No security bypass, session takeover, or synthetic ACK may substitute.

### Ready for Proposal

Yes. Cover all A1–A6 with testable source corrections and explicit environmental dispositions. Completion of source fixes is distinct from live-smoke certification; keep the latter BLOCKED until an authorized runtime supplies real evidence.
