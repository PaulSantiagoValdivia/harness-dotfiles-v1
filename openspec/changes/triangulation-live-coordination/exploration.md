## Exploration: triangulation-live-coordination

### Current State

At source revision `14d0015203c9dc2d81693c051628373ddb771587`, the launcher creates three independent named Claude CLI processes through cmux. `open_top_level_sessions` supplies only canonical-authority context, not team creation or membership. The test suite explicitly asserts that topology. Naming sessions and opening panes do not themselves establish a native message channel.

Codex already opens one primary with two authorized sibling paths and an instruction to spawn children, but dispatch success is not proof of spawn, task acceptance, or a successful reply. The final launcher output correctly labels live coordination UNTESTED. Neither client has a defined handshake/ACK readiness gate in the shared protocol.

The coordinator verified current official cross-session messaging documentation and installed Claude 2.1.267: independent sessions support `ListAgents`/`SendMessage` since 2.1.224; inbox controls can hold or refuse inbound messages. Thus the existing Claude topology is valid, but availability, discoverability, and role/task acceptance still need live verification. `TeamCreate`/`TeamDelete` are removed in current documentation and must not be introduced. The source SessionStart handoff explicitly reports local context only, not live coordination; its installed copy matches source (`cmp` exit 0). It validates canonical authority but does not authorize ownership or enforce runtime transport. OpenSpec has no archived main domain specifications beyond `.gitkeep`; existing change evidence must remain intact.

### Affected Areas

- `files/shared/bin/triangulate` — retain independent Claude sessions with explicit per-role discovery and handshake startup; distinguish dispatch from observed readiness; keep fresh-target, Git, reservation, and cmux safeguards.
- `files/shared/skills/triangulation-orchestrator/SKILL.md` and `references/protocol.md` — capability-bound topology, HELLO/ACK contract, bounded recovery, automatic routine coordination and explicit escalation boundary.
- `files/claude/CLAUDE.md`, `files/codex/AGENTS.md` — qualify discovery with actual capability and readiness checks and keep the shared coordination block aligned.
- `tests/triangulate_launcher_test.sh` — retain three-Claude-process assertions and add role-specific startup/handshake argument tests; retain Codex and destructive-edge regression checks.
- `tests/triangulation_evidence_test.sh`, `docs/triangulation-safety.md`, `verify.sh` — evidence vocabulary and focused check integration if new readiness tests are introduced.
- `files/claude/hooks/triangulate-handoff.sh` — primarily retain existing semantics; change only if necessary to state readiness is separate from local authority. No speculative new write-enforcement hook.

### Approaches

1. **Preserve native independent Claude sessions plus observed readiness** — use verified cross-session discovery/messaging and per-role startup prompts; Codex retains one primary plus two children. Both clients exchange correlated HELLO/ACK messages before implementation dispatch.
   - Pros: smallest compatible change, current official capability verified by coordinator, no homemade bus or topology migration.
   - Cons: inbox controls may block delivery; prompt instructions and textual receipts are procedural controls, not shell-enforced write authorization.
   - Effort: Medium; split launcher/test work from shared contract/evidence work if needed.

2. **Single-entry native team launch** — replace three existing Claude entries with one lead creating native workers.
   - Pros: potentially simpler lead-owned lifecycle.
   - Cons: unnecessary migration for this defect; obsolete TeamCreate/Delete APIs cannot be assumed; loses existing independent-session workflow.
   - Effort: Medium; defer unless verified peer messaging is unavailable and an explicit supported alternative is chosen.

3. **External bridge between independent sessions** — introduce a message broker or adapt an external peer transport.
   - Pros: could preserve three independent terminal sessions if a supported bridge existed.
   - Cons: adds authentication, delivery, lifecycle, ownership, and stale-message obligations; no verified bridge identified in source; contradicts preference against a homemade message bus.
   - Effort: High; reject for this change.

### Recommendation

Use approach 1 with a narrowly scoped readiness contract. The coordinator verified https://code.claude.com/docs/en/cross-session-messaging and https://code.claude.com/docs/en/agent-teams; do not replace working cross-session APIs with removed team-creation tools. Native inbox hold/refusal remains a capability blocker, not grounds to bypass controls. One-shot idle notification is scoped to a main session observing a local top-level session, not child agents. A lead sends a per-run correlated HELLO with exact role, native runtime identity, worktree, canonical artifact paths, and current write boundary; each worker returns ACK referencing that run/message and confirms its actual path and task understanding. Readiness requires both distinct expected workers and successful bidirectional native delivery; missing, duplicate, mismatched, or stale ACKs remain BLOCKED for implementation. Native delivery observations support a readiness receipt but a JSON/text parser cannot prove their authenticity. Keep launcher outcome LAUNCHED/UNTESTED until runtime evidence exists.

Routine dependency questions, test failures, contract clarifications within approved scope, and receipt corrections go worker-to-lead and back without asking the user. The lead may continue safe independent work and perform bounded native follow-up/reassignment; no polling or infinite retries. Human escalation remains necessary for unresolved requirements, permissions/capability boundaries, conflicting active owners, or changes to approved scope. Restart/replacement invalidates prior readiness and requires a fresh handshake. Existing sessions can be adopted only after exact identity/role/path discovery, fresh ACK, and ownership verification; never create duplicate writers. Replacement requires a stop/clean-handoff path.

Testing plan: Strict TDD is enabled with `./verify.sh`. First add failing disposable-repository launcher tests asserting exactly three role-named Claude CLI dispatches, correct role/canonical/sibling paths, explicit discovery and ACK startup, and absence of fabricated readiness. Add contract/readiness negative cases for missing, stale, duplicate, wrong-role/path/authority ACKs and no write authorization before both ACKs. Keep fixtures explicitly separate from observed native runtime evidence. Run launcher, handoff, evidence, shell syntax, and installed parity checks. A real authorized-terminal smoke must retain actual lead-to-worker-to-lead round trips, one unblocked follow-up, and three receipts; without it report live readiness UNTESTED/BLOCKED, not PASS.

### Risks

- Current Claude cross-session support is documented, but installed runtime discovery and inbox acceptance remain live observations to verify. Do not change models or global user-owned settings to work around capability gaps.
- Current cmux external-access denial prevents live smoke from this session; do not bypass sockets/permissions or imply terminal authorization transfers here.
- The old change's C2 assertion correction and original live-smoke blockers remain separate unfinished evidence; this change must not erase or retrospectively satisfy them. The user has authorized an explicit new-authority C2 amendment: correct the evidence assertion by extracting the actual documentation recipe and checking fake-npm execution; preserve the historical failed report until new independent verification. Include that bounded amendment in proposal/design/tasks rather than silently rewriting the old change.
- Readiness instructions are not hard process-level write protection. If a stronger guarantee is required, scope explicit tool-boundary enforcement separately rather than overclaiming a prompt or evidence validator.
- Existing worktrees, aliases, mappings, and active-owner state must be preserved; installation remains managed-path-only with backups and rollback.

### Ready for Proposal

Yes — preserve verified native Claude cross-session topology and Codex primary-plus-children topology; add explicit role discovery, truthful correlated readiness, bounded autonomous escalation, and the authorized C2 test amendment. Preserve the old blockers and require actual runtime evidence for any autonomous-coordination claim.
