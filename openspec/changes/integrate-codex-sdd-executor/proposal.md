# Proposal: Integrate Codex as an Optional SDD Apply Backend

## Intent

Add `codex-build` as an opt-in `sdd-apply` backend without weakening OpenSpec authority, Strict TDD, resumability, or independent verification. Its current parallel fan-out model cannot safely execute ordered SDD units or update SDD state.

## Scope

### In Scope
- Select `native` (default) or `codex` per apply run while keeping `sdd-apply` the sole OpenSpec writer.
- Add a single-work-unit SDD mode with lineage, conventional commit, independent audit, and content-bound receipt.
- Fail closed on overlapping dirty paths, unreproducible bases, spec gaps, invalid evidence, or integration conflicts; independently rerun gates before recording progress.
- Add acceptance coverage, overlay checks, and documentation.

### Out of Scope
- Parallel SDD implementation, workflow-owned task/progress updates, automatic PR integration, silent backend fallback, or replacing `sdd-verify`.
- Changing standalone `codex-build` fan-out behavior.

## Capabilities

### New Capabilities
- `codex-sdd-execution-backend`: Transactional Codex execution of one bounded unit, covering eligibility, lineage, receipt, integration, TDD, and failures.

### Modified Capabilities
- None.

## Approach

`sdd-apply` selects one pending unit and invokes SDD mode against an accepted base. Codex produces TDD evidence and one conventional commit; Claude audits the diff and returns a receipt. `sdd-apply` validates and integrates it, reruns authoritative checks, then alone updates tasks and progress. Missing or contradictory requirements return `spec-gap` without a commit.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `files/claude/{skills,agents,workflows}` | Modified | Backend routing and transactional adapter |
| `files/{claude/CLAUDE.md,codex/AGENTS.md}` | Modified | Cross-client ownership contract |
| `bootstrap.sh`, `verify.sh`, `tests/` | Modified | Installation and acceptance evidence |
| `README.md`, `docs/PRD.md` | Modified | Operator guidance and boundaries |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Apply agent cannot invoke workflow safely | Medium | Prove boundary before enabling backend |
| Dirty state or stale receipts corrupt lineage | High | Reject overlap, identity mismatch, or missing evidence |
| Workflow audit is mistaken for final verification | Medium | Keep `sdd-verify` independent and mandatory |

## Rollback Plan

Default or switch to `native`; revert SDD-mode additions while retaining standalone behavior. Restore installed files from bootstrap backups; never edit installed copies as source.

## Dependencies

- Available Claude workflow and Codex CLI; reproducible Git base; `./verify.sh`.
- Unresolved: exact workflow invocation boundary must be confirmed by acceptance tests.

## Success Criteria

- [ ] Native behavior and standalone `codex-build` remain compatible.
- [ ] Codex mode processes resumable units sequentially and accepts only audited conventional commits.
- [ ] Strict TDD, dirty-workspace safety, spec-gap stops, and receipt rejection are proven by `./verify.sh`.
- [ ] Only `sdd-apply` updates OpenSpec state; `sdd-verify` independently evaluates integrated work.
