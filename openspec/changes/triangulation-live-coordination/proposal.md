# Proposal: Make native triangulation coordination explicit

## Intent
Make the three repository owners discover each other, acknowledge scope, and resolve routine dependencies autonomously. Current launch dispatch establishes neither task acceptance nor observed native messaging readiness.

## Scope
### In Scope
- Shared role-aware bootstrap packets for every Claude session and the Codex primary, with exact sibling paths and canonical authority.
- Finite native discovery and correlated HELLO/ACK readiness, bounded follow-up, and explicit routine-versus-human escalation rules.
- Behavioral packet tests and an explicitly authorized C2 evidence-test amendment: execute the extracted documentation recipe against fake npm; preserve the old verification report.
### Out of Scope
- New mailbox/state services, transport bridges, topology migration, model/security changes, product worktree edits, or automatic ownership transfer.
- Hard write-enforcement claims: a prompt contract cannot force model compliance.

## Capabilities
### New Capabilities
- `triangulation-live-coordination`: role-scoped native startup, readiness, autonomous coordination, and truthful evidence boundaries.
### Modified Capabilities
- None; `openspec/specs/` has no existing domain specification. C2 is an explicit amendment to prior change testing, not a rewrite of historical evidence.

## Approach
Keep supported independent Claude sessions using native cross-session discovery/messages; keep Codex primary plus two children. Define correlated role/path/authority HELLO/ACK exchanges before implementation, reject missing or mismatched readiness, and route routine blockers through the lead. Use finite discovery/follow-up without polling; unresolved requirements, permissions, and ownership conflicts still require human decisions. Launcher output remains UNTESTED for live coordination until an actual smoke proves round trips and follow-up.

## Affected Areas
| Area | Impact |
|---|---|
| `files/shared/bin/triangulate` | Shared role-aware bootstrap generation and dispatch |
| `files/shared/skills/triangulation-orchestrator/{SKILL.md,references/protocol.md}` | Readiness and autonomy contract |
| `tests/triangulate_launcher_test.sh`, `tests/triangulation_evidence_test.sh` | Packet assertions and bounded C2 correction |
| `docs/triangulation-safety.md` | Accurate test/live-evidence recipe |

## Risks
Prompt compliance is not enforced transport or write authorization. Fixtures cannot prove live readiness; unavailable native discovery/inbox access stays BLOCKED. Existing historical failures and live-smoke blockers remain visible.

## Rollback Plan
Revert this change's commits. If scoped deployment occurs, back up and restore only the managed launcher and shared skill trees in both clients; preserve mappings, user settings, worktrees, and historical evidence. No global bootstrap or security configuration overwrite is required.

## Dependencies
Supported native runtime tools, verified single-writer ownership, canonical artifacts, and an authorized terminal for actual smoke. Strict TDD uses `./verify.sh`; focused fixtures do not replace live verification.

## Success Criteria
- [ ] Tests execute and inspect actual launcher packets for all roles and both runtimes.
- [ ] Protocol defines finite discovery, matched ACKs, routine autonomous resolution, and safe escalation.
- [ ] Extracted docs-recipe C2 test passes; historical report remains unchanged.
- [ ] Runtime is reported UNTESTED/BLOCKED unless retained native smoke observations justify readiness.
