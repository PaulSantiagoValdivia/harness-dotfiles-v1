# Triangulation Live Coordination Specification

## Purpose
Capability `triangulation-live-coordination`: startup instructions and evidence, not enforced compliance or certified transport.

## Requirements

### Requirement: Role-scoped bootstrap packets
The launcher MUST supply coordination-skill activation, role, own worktree, all sibling paths, canonical authority, and one-writer boundaries in Claude and Codex-primary packets. Claude MUST retain three named sessions; Codex MUST retain one primary instructing two role-named children with forwarded boundaries.
#### Scenario: Generated packets preserve identities
- GIVEN disposable repositories with spaced paths and canonical alias
- WHEN tests execute actual launcher dispatch with capturing transport fixtures
- THEN decoded packets MUST contain exact identities/paths and authority; front/app MUST NOT receive canonical ownership or create-plan instructions.
#### Scenario: Rejected launch does not change ownership
- GIVEN an existing target or unavailable authorized transport
- WHEN startup is attempted
- THEN fresh-launch protections MUST reject it without changing writers, permissions, mappings, or worktrees.

### Requirement: Finite readiness instruction contract
Packets MUST direct native discovery and correlated HELLO/ACK before implementation: 128-bit fresh nonce, request ID, role, runtime identity, worktree, authority/revision hash, and scope. The protocol MUST require two matching worker ACKs; missing, duplicate, stale, late, or mismatched ACKs MUST NOT authorize implementation. Discovery MUST permit one initial attempt and one event-triggered or scheduled retry within 10 seconds, then BLOCKED if peers remain missing, never polling; one follow-up is allowed within 120 seconds from HELLO, separate from the 180-second smoke.
#### Scenario: Startup carries the readiness gate
- GIVEN captured packets and protocol
- WHEN contract tests inspect both runtimes
- THEN they MUST find discovery/HELLO/ACK, both-worker gating, budgets, and invalid-ACK rejection; replacement/revision changes MUST invalidate readiness.
#### Scenario: Capability or delivery is unavailable
- GIVEN unavailable discovery tools, held/refused inbox delivery, or exhausted bounds
- WHEN the protocol's failure instructions are inspected
- THEN they MUST prescribe BLOCKED, cause, preserved owners/data, and no bypass or implicit readiness.

### Requirement: Routine autonomy with protected escalation
The contract MUST route dependency clarification, receipt correction, and safe unblocked read/test reassignment through native worker/lead messages without user relay. Unresolved requirements, approved-scope changes, permissions, or ownership conflicts MUST remain human decision boundaries; no automatic write-ownership transfer is authorized.
#### Scenario: Routine and exceptional decisions are distinguished
- GIVEN startup packets and protocol
- WHEN tests inspect decision routing
- THEN routine issues MUST go to the lead, safe independent work MAY continue, and protected decisions MUST stop the affected work rather than assume consent.

### Requirement: Truthful certification and deployment boundaries
Dispatch and fixture PASS MUST leave live coordination UNTESTED. Certification MUST require retained manual observations of two current native round-trip ACKs, safe follow-up, and three receipts in an authorized runtime. Documentation MUST state that prompt instructions cannot force compliance and fixtures cannot certify transport. Scoped installation MUST preserve preferences/mappings and be idempotent.
#### Scenario: Fixtures are not live observations
- GIVEN successful fixtures without native smoke
- WHEN launcher/test output and documentation are inspected
- THEN they MUST NOT claim readiness; historical failures MUST remain unchanged and smoke UNTESTED/BLOCKED.
#### Scenario: Managed deployment preserves user configuration
- GIVEN fresh/installed disposable homes with custom preferences/mappings
- WHEN managed launcher/skill deployment is exercised and repeated
- THEN only managed paths MAY change, previous bytes MUST be backed up, and unchanged reruns MUST preserve preferences/mappings and installed bytes.

### Requirement: C2 validates the actual documentation recipe
The evidence regression MUST extract and execute the gate-retention recipe from `docs/triangulation-safety.md` using private fake-npm fixtures. It MUST NOT substitute a hand-written equivalent. Every gate MUST run and retain logs after failure; all-success MUST exit zero and any failure MUST exit nonzero. Historical verification evidence MUST NOT be rewritten.
#### Scenario: Success and failures retain complete evidence
- GIVEN all-success, single-gate failures, and multiple failures with distinct exits
- WHEN the extracted recipe executes in fresh per-case evidence directories
- THEN every gate MUST be invoked in order with its output retained; successful later gates MUST NOT mask failure, and aggregate exit MUST match documented policy.
