# Design: Native triangulation readiness

## Technical Approach
Retain three Claude sessions / Codex primary plus two children. Extend launcher/shared skill; no service or model/security/settings changes. Readiness instructions do not enforce transport or write authorization.

## Architecture Decisions
| Option | Tradeoff | Decision |
|---|---|---|
| Shared role-aware packet builder | Small Bash change; model compliance remains external | Choose: plan and dispatch consume identical builder output. |
| Replace Claude topology | Disrupts supported cross-session messaging | Reject; retain installed native `ListAgents`/`SendMessage`; no removed TeamCreate/Delete. |
| Runtime readiness service | Could enforce state but adds lifecycle/security surface | Reject; require observed native exchanges, never fabricated launcher readiness. |
| Shared skill source | Both clients receive one behavioral contract | Choose; preserve unrelated client configuration and existing CLI flags. |

## Data Flow
Validated identity → packet/CLI → discovery/canonical planning → revision-bound HELLO/ACK → implementation → follow-up → receipts.

## Interfaces / Contracts
- One packet function accepts `back|front|app`; derive worktree/sibling paths, canonical artifact paths, recipient/lead and write boundary from validated arrays.
- Generate one fresh 128-bit hexadecimal nonce per invocation, separate from reservation ownership; plan writes no files. All roles share it; restart/replacement requires fresh handshake.
- Packet activates `triangulation-orchestrator`, includes runtime adaptation and finite readiness instructions. Claude workers discover the exact lead; Codex primary forwards scoped packets to exactly two children, which MUST NOT delegate.
- Missing artifacts allow read-only discovery and canonical SDD planning, never implementation. Connectivity alone is not implementation readiness; never fabricate hashes.
- Task HELLO/ACK bind nonce, request ID, observed native identities (not claimed names), role, worktree, authority path/current contract-artifact revision hash and task/write boundary. Both workers must ACK; changed revisions invalidate readiness and require fresh acknowledgment. Retain no secrets.
- Missing, duplicate, stale, wrong-role/path/authority or rejected ACKs cannot establish readiness. Discovery gets at most two attempts, HELLO one follow-up per peer, and a 120-second coordinator-clock deadline starting at actual HELLO issuance, not startup/planning. Second discovery requires an event or one scheduled bounded retry, never polling. Inbox refusal/capability loss stays BLOCKED without bypass.
- Adoption requires exact discovery/fresh ACK; replacement requires stopped owner/clean handoff. Independent read/test may continue; never duplicate writers.
- Routine scope-preserving questions, failures, drift and receipt corrections route worker→lead→worker autonomously. Unresolved requirements, permissions, scope expansion and conflicting ownership escalate to the human.
- Launcher reports dispatch/LAUNCHED with live coordination UNTESTED. Fixtures cannot prove delivery; retain observed exchanges/follow-up before readiness claims.

## File Changes
| File | Action |
|---|---|
| `files/shared/bin/triangulate` | Shared packet builder, Claude plan commands and role-aware dispatch, Codex handoff instructions. |
| `files/shared/skills/triangulation-orchestrator/SKILL.md` | Readiness gate and autonomous escalation routing. |
| `files/shared/skills/triangulation-orchestrator/references/protocol.md` | Exact fields, finite bounds, failure/adoption rules and scoped deployment. |
| `tests/triangulate_launcher_test.sh` | Real launcher plan and disposable mocked dispatch/argv assertions. |
| `tests/triangulation_evidence_test.sh` | Execute extracted documentation recipe with fake npm (explicit C2 amendment). |
| `docs/triangulation-safety.md` | Separate procedural/fixture checks from observed native smoke. |

## Testing Strategy
Strict TDD: focused launcher/handoff/evidence RED→GREEN, syntax and deployed parity. Acceptance runner `./verify.sh` remains; no full 21-minute prerequisite per apply batch.
Invoke the real launcher; capture cmux argv losslessly and execute fixture-generated commands with recording fake clients. Assert argv boundaries, roles/siblings, authority aliases, nonce shape/shared identity/freshness, bounds and topology. Reject invalid roles; assert invalid/stale-hash ACK rejection, planning exception and HELLO deadline, NOT runtime enforcement.
C2 extracts the exact Bash block under “Preserve gate failures and logs”; fake npm records all three commands and deterministic output/exits. Exercise each failed gate and all-success, asserting aggregate status and retained logs. Preserve the historical `triangulation-safety/verify-report.md` unchanged.
Native smoke needs actual bidirectional exchanges, one safe follow-up and three receipts. Current external cmux denial remains BLOCKED; fixtures never satisfy it. Retain evidence privately at `/tmp/triangulation-live-coordination-evidence/` with snapshot identity and exits.

## Threat Matrix
| Boundary | Applicability | Safe/failure behavior and planned RED tests |
|---|---|---|
| Documentation-like paths | N/A: no executable-file classifier | Docs recipe executes only its explicitly extracted fixture block. |
| Git repository selection | Applicable: absolute/relative paths and `git -C` authority | Preserve existing absolute-root validation; reject relative mappings; assert absolute sibling/canonical paths, aliases and space-containing paths survive real plan/dispatch argv. |
| Commit state | N/A: no commit automation changes | Existing semantics unchanged. |
| Push state | N/A: no push automation changes | Existing semantics unchanged. |
| PR commands | N/A: no PR command changes | Existing semantics unchanged. |

## Migration / Rollout
Deliver reviewable feature-branch-chain slices under 400 authored changed lines. Back up managed launcher and both installed shared-skill trees before scoped copy/install; verify `cmp`/`diff -qr`, fresh-home and idempotent behavior. Revert commits and restore those backups (remove only newly installed managed paths); preserve mappings, settings, product worktrees and old evidence. No global bootstrap.

## Open Questions
None; native smoke remains a verification prerequisite.
