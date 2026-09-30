# Harness Health Diagnostics Specification

## Purpose
Diagnose health safely.

## ADDED Requirements

### Requirement: Checkout identity
Validation MUST require the candidate's own valid Git metadata and matching canonical checkout root, not ancestor discovery. Stale candidates MUST receive one actionable classification, not missing-instruction failures.

#### Scenario: Residual or misplaced checkout
- GIVEN an absent path, residual directory, invalid metadata, or subdirectory inside another repository
- WHEN audited
- THEN it is not validated as an active checkout, including paths containing spaces.

#### Scenario: Genuine instruction defect
- GIVEN a valid main or linked checkout lacking required instructions
- WHEN validated
- THEN the missing instructions fail acceptance.

### Requirement: Honest ownership evidence
Diagnostics MUST expose meaningful tracked/untracked work, exclude only identified generated registry noise, report inspection failures explicitly, and qualify remote coverage as locally observed refs.

#### Scenario: Dirty or unreadable checkout
- GIVEN tracked edits, untracked source, generated registry files, or a failed Git status operation
- WHEN audited
- THEN real work remains visible and failed inspection never implies cleanliness.

#### Scenario: Local remote coverage
- GIVEN no local remote ref contains HEAD
- WHEN audited
- THEN wording describes local evidence without claiming the server lacks the commit or fetching.

### Requirement: Nonmutation and local protection
Audit MUST NOT mutate repositories or delete data. Explicit ignore repair MUST be backed up, idempotent, limited to local worktree/registry protection, and reversible without removing concurrent additions.

#### Scenario: Shared checkout repair
- GIVEN an owned sibling checkout and existing local exclusions
- WHEN protection is explicitly applied twice and rolled back
- THEN tracked files, refs, work, prior exclusions, and concurrent additions remain unchanged.

### Requirement: Finding dispositions
Delivery MUST map all seven baseline failures and seventeen warnings to evidence, disposition, ownership, and next action. Residual work/cache warnings MUST NOT be hidden or described as resolved.

#### Scenario: External ownership remains
- GIVEN stale registrations, cache-size warnings, dirty work, or unpublished commits
- WHEN reporting completion
- THEN each finding is corrected or explicitly retained for its owner without automatic cleanup, commit, or push.

