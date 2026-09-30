# Codex SDD Execution Backend Specification

## Purpose

Define safe Codex execution across supported runtimes.

## Requirements

### Requirement: Explicit Backend Routing

Each run MUST select `native` or `codex`, default to `native`, and MUST NOT silently fall back after Codex starts. Ineligibility MUST stop and MAY offer explicit native retry.

#### Scenario: Backend is unavailable
- GIVEN a run selects `codex`
- WHEN the backend cannot start
- THEN implementation and OpenSpec state MUST remain unchanged

### Requirement: Content-Bound Packet

The backend MUST accept one unit with lineage, base SHA, content identities, criteria, allowed paths, and verification command. Invalid references MUST be rejected.

#### Scenario: Referenced content changed
- GIVEN a packet identifies artifacts and a base
- WHEN either identity cannot be reproduced
- THEN no integratable commit MUST be created

### Requirement: Sequential Single Writer

Codex SDD mode MUST execute one unit at a time. Only `sdd-apply` SHALL integrate work and update tasks or progress; the backend MUST NOT write OpenSpec state.

#### Scenario: Multiple units are pending
- GIVEN ordered pending units
- WHEN Codex mode runs
- THEN only the next unit MUST execute

### Requirement: TDD and Spec Gaps

Under Strict TDD, packet and receipt MUST evidence RED, GREEN, and REFACTOR. Missing or contradictory requirements MUST produce `spec-gap`, no integratable commit, and no completed task.

#### Scenario: Criteria conflict
- GIVEN Codex cannot derive one testable behavior
- WHEN it reports `spec-gap`
- THEN implementation and progress MUST stop

### Requirement: Dirty Workspace Safety

The caller MUST reject dirty assigned paths or a non-reproducible base. It MUST NOT stash, reset, clean, overwrite, or commit unrelated work.

#### Scenario: Dirty paths overlap
- GIVEN an assigned path has user changes
- WHEN eligibility is checked
- THEN execution MUST not start and changes MUST remain intact

### Requirement: Audited Receipt and Commit

Success MUST yield one conventional work-unit commit and a receipt binding lineage, base, commit, tree/diff, commands, results, and audit verdict. Invalid evidence MUST be rejected.

#### Scenario: Receipt names another tree
- GIVEN a successful-looking receipt
- WHEN its tree differs from the commit
- THEN integration and progress MUST stop

### Requirement: Integration and Verification Gates

Conflicts MUST stop without automatic resolution. After integration, `sdd-apply` MUST rerun authoritative gates before recording progress. Workflow audit MUST NOT replace independent `sdd-verify`.

#### Scenario: Authoritative gate fails
- GIVEN an audited commit integrates
- WHEN a writer-workspace gate fails
- THEN the unit MUST remain incomplete

### Requirement: Resumable Reconciliation

Progress MUST bind each completed unit to lineage, commit, receipt, and gates. Resume MUST skip only reconciled units and MUST stop on contradictory or partial records.

#### Scenario: Integration lacks progress
- GIVEN a commit exists but progress is absent
- WHEN apply resumes
- THEN it MUST reconcile state without duplicating or silently completing work

### Requirement: Standalone and Bootstrap Compatibility

Standalone `codex-build` MUST remain compatible. Fresh and repeated bootstrap MUST install overlays, preserve preferences and adaptation, and MUST NOT create another SDD writer.

#### Scenario: Bootstrap reruns
- GIVEN customized settings and installed overlays
- WHEN bootstrap runs again
- THEN overlays MUST match sources and preferences MUST remain preserved

### Requirement: Conductor Runtime Adaptation and Parity

Claude Code in Conductor MUST discover and invoke `codex-build`. Direct Codex MUST receive optimized native effort, concurrency, SDD, and memory configuration without Claude or `codex-build`; unsupported agent scalars MUST NOT be emitted. Both paths MUST preserve lifecycle guarantees while documented invocation MAY differ.

#### Scenario: Claude runtime delegates
- GIVEN Claude Code runs inside Conductor
- WHEN an eligible apply selects `codex`
- THEN live validation MUST prove workflow discovery and invocation

#### Scenario: Direct Codex runtime is native
- GIVEN Codex is the Conductor agent
- WHEN bootstrap and strict startup validation run
- THEN live behavior MUST prove native configuration, SDD, and memory operation
- AND validation MUST exceed file-existence checks
