# Harness Evidence Specification

## Purpose
Make claims traceable through an original shared local evidence contract.

## ADDED Requirements

### Requirement: Identified observations
Manifests MUST identify repository, branch/revision, dirty-state qualification, scope, environment, timestamp, command/interaction, expected/observed result, exit status where applicable, and limitations. Dirty HEAD MUST NOT be presented as exact tested bytes.

#### Scenario: Dirty runtime observation
- GIVEN a dirty checkout or deployed target
- WHEN recording evidence
- THEN identity limitations and the actual tested target accompany the result.

### Requirement: Honest outcomes and comparisons
Evidence MUST distinguish PASS, FAIL, BLOCKED, and UNTESTED; before/after references MUST be comparable or explicitly unavailable with reasons. Checksums MUST derive from actual retained bytes, never fabricated claims.

#### Scenario: Missing prior evidence
- GIVEN an unreproducible old failure or missing artifact
- WHEN reporting
- THEN absence remains explicit, without invented results, checksums, or a PASS inference.

### Requirement: Local privacy boundary
Evidence MUST remain local by default, outside tracked source. Recording/uploading MUST NOT occur automatically; evidence MUST NOT introduce another review lane, provider, or authoritative SDD receipt format.

#### Scenario: Optional visual proof
- GIVEN unavailable capture permissions or publication approval
- WHEN gathering evidence
- THEN local textual proof or an explicit limitation replaces capture/upload without weakening protections.

### Requirement: Installation and regression guarantees
Both clients MUST receive identical original skill/support files. Installation MUST preserve unrelated preferences, back up replacements, support idempotent reruns/rollback, and retain Astra/cmux, Strict TDD, and existing SDD behavior.

#### Scenario: Fresh installation and rerun
- GIVEN isolated fresh and customized homes
- WHEN installed twice and restored from backup
- THEN parity, preservation, and rollback are demonstrated by fixtures.

#### Scenario: Verification boundaries
- GIVEN isolated RED/GREEN regression evidence and a fresh full verification run
- WHEN reporting acceptance
- THEN source, installed-state, and external ownership results remain distinct.
