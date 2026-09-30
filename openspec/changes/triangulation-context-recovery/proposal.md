# Proposal: Triangulation Context Recovery

## Intent
Preserve unfinished, approved triangulation work across compaction without unnecessary user decisions, lost delivery state, duplicate writers or false completion. Installed hooks match source: missing recovery events and clear-oriented instructions affect deployment.

## Scope
### In Scope
- Classify context, quota, tools, dependencies, permissions and delivery from evidence.
- Prefer same-task native compaction; preserve execution/delivery choices.
- Reload validated checkpoint pointers; reuse existing readiness/closure gates.
- Preserve pending PR/integration/deployment despite pushed commits.
- Focused regression tests and scoped installation/rollback evidence for both clients.

### Out of Scope
- Automatic clear, quota reset, purchases, provider changes, updates or writer relaunches.
- Product-repository writes, restarts, permission changes, new coordination infrastructure or measurement tooling.
- Changing numerical warning thresholds, disabling critical warnings or treating fixtures as live certification.

## Capabilities
### New Capabilities
- `context-recovery`: bounded same-task checkpoint/reload, evidence-based recovery decisions and truthful delivery continuity.
### Modified Capabilities
- None; `openspec/specs/` contains no existing capability specifications.

## Approach
Three tested slices, each below 400 authored changed lines:
1. Correct recovery instructions/threshold documentation and invalidate stale precompact warnings while preserving the zero-fork prompt reader and actual 200k/300k/400k protections.
2. Define one canonical bounded checkpoint; validate mode aliases, identity and paths; reload task, process, owner and receipt pointers as data, never authorization.
3. Wire resume/compact events and targeted Codex recovery; prove scoped deployment and unfinished-PR continuation with fixtures.

Use OpenSpec, auto, `auto-chain`, `feature-branch-chain`; count planning in review size. Preserve canonical ownership; stale evidence requires revalidation, not repeated settled decisions.

## Affected Areas
| Area | Impact |
|---|---|
| `files/claude/hooks/{context-budget,context-budget-measure,triangulate-handoff}.sh` | Warning lifecycle and bounded reload |
| `files/claude/{settings.json,CLAUDE.md}` | Events and corrected guidance |
| `files/shared/runtime-budget.md`, `files/codex/engram-compact-prompt.md` | Cross-client continuity |
| `files/shared/skills/triangulation-orchestrator/references/protocol.md` | Checkpoint/closure contract |
| `tests/`, `verify.sh` | Strict-TDD regression coverage |

## Risks
| Risk | Mitigation |
|---|---|
| Stale/malicious checkpoints | Bounded input/output, path confinement, schema validation; no execution |
| Silenced safeguards or duplicate writers | Preserve thresholds; fresh existing readiness checks |
| Overclaimed recovery | Separate source, installed and native evidence |

## Rollback Plan
Revert individual slice commits. Back up/restore modified managed paths only; no full bootstrap, preference changes or worktree resets. Leave operator mappings untouched.

## Dependencies
Existing canonical artifacts, native owner discovery and installed hook support; unavailable native access remains explicitly blocked.

## Success Criteria
- [ ] Same-task recovery retains mode, next action, active-process facts and pending PR work.
- [ ] Compact/resume fixtures prevent stale warnings and unauthorized ownership restoration; output remains below 4 KiB.
- [ ] Critical protections, permissions, unrelated settings and aliases remain intact.
- [ ] Strict-TDD receipts distinguish tested fixtures from observed deployed/live behavior.
