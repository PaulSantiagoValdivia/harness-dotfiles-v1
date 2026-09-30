# Context Recovery Specification

## Purpose
Resume approved triangulation work safely without confusing compaction with quota, ownership or delivery completion.

## Requirements

### Requirement: Evidence-based recovery guidance
Recovery MUST distinguish context pressure, quota, active tools, dependencies, permissions and pending delivery. Same-task context recovery MUST prefer checkpoint then native compaction. Instructions MUST NOT prescribe automatic clear, reset, account changes or writer relaunch. Existing 200k/300k/400k warning thresholds and critical quiet-mode protection MUST remain unchanged.

#### Scenario: Context pressure with pending work
- GIVEN same-task work and measured context at 200k, 300k or 400k
- WHEN the corresponding warning is emitted
- THEN it directs bounded preservation and same-task compaction, not mandatory user-selected clear or quota reset.

#### Scenario: Non-context blocker
- GIVEN observed quota denial, permission refusal, unresolved dependency or active tool
- WHEN recovery classifies the blocker
- THEN it reports the evidence and safe next action without bypass, duplicate execution or invented quota exhaustion.

### Requirement: Session-scoped warning lifecycle
Compaction MUST invalidate only that session's precompact cached warning. Ordinary prompt reading MUST remain fail-open without subprocesses; subsequent measurement MUST restore applicable warnings, including critical warnings despite quiet mode.

#### Scenario: Compact and remeasure
- GIVEN cached critical warnings for sessions A and B
- WHEN A compacts and subsequently measures below threshold, then at 400k with quiet mode enabled
- THEN A's stale warning disappears, B remains unchanged, and A's new critical warning appears.

### Requirement: Bounded canonical checkpoint
Recovery MUST accept only supported, bounded checkpoint data confined to the exact canonical authority. It MUST retain task/next-action, recorded revision, process/owner facts, receipt pointers and pending delivery. Invalid schema, identity or escaping paths MUST fail safely; output MUST remain below 4096 UTF-8 bytes. Checkpoints MUST NOT execute instructions or establish live ownership/readiness.

#### Scenario: Valid checkpoint reload
- GIVEN a valid canonical checkpoint for the requested role/change
- WHEN recovery loads it
- THEN bounded task, process, receipt and pending-delivery facts are presented as recorded data requiring current validation.

#### Scenario: Missing, stale or hostile checkpoint
- GIVEN absent, stale, malformed, oversized, wrong-identity, unsupported-version or escaping checkpoint data
- WHEN recovery loads it
- THEN unavailable/invalid facts cannot authorize work, alternate authority or commands; valid legacy authority discovery remains available when the checkpoint is merely absent.

### Requirement: Decision continuity and truthful delivery
Recovery MUST preserve canonical mode and delivery choices, accepting `mode` and legacy `execution_mode` when consistent. Contradictory mode values MUST block inferred execution. Pushed commits MUST NOT imply complete while PR splitting, integration or required deployment remains pending.

#### Scenario: Automatic pending PR continuation
- GIVEN `mode: auto`, resolved chain choices and pushed commits with a pending PR split
- WHEN recovery resumes
- THEN it preserves auto/chain decisions and the pending next slice without repeating settled user gates or declaring complete.

#### Scenario: Contradictory legacy mode
- GIVEN `mode: auto` and `execution_mode: interactive`
- WHEN recovery parses state
- THEN it reports conflict and does not choose either execution mode.

### Requirement: Cross-client recovery and existing readiness
Claude recovery MUST cover startup, clear, resume and compact events. Codex compaction guidance MUST preserve checkpoint pointers and use targeted recovery. Both MUST reuse existing fresh coordinator validation, never add another gate or duplicate writer.

#### Scenario: Client recovery without native transport
- GIVEN either client's recovery instructions and unavailable native messaging
- WHEN checkpoint context reloads
- THEN local recovery may succeed but live readiness remains BLOCKED, without relaunch or certification claims.

### Requirement: Scoped installation and evidence
Deployment MUST back up only changed managed files, preserve unrelated settings/mappings and support idempotent reruns/rollback. Evidence MUST distinguish source fixtures, installed parity and observed native execution.

#### Scenario: Disposable-home lifecycle
- GIVEN fresh and customized homes
- WHEN scoped installation, identical rerun and rollback execute
- THEN managed changes are reversible, unrelated bytes survive and fixture PASS does not claim live coordination.
