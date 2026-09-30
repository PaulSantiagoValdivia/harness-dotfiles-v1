# Proposal: Harden harness diagnostics and evidence

## Intent

Make health claims reproducible without endangering concurrent work. Address six false failures, one ignore defect, and seventeen warnings with explicit dispositions—not suppression.

## Scope

### In Scope
- Fixture-tested valid/stale checkout classification and tracked/untracked ownership diagnostics.
- Backed-up, idempotent local ignore protection; disposition ledger for every baseline warning and failure.
- Original shared `harness-evidence` skill and local manifest contract covering revision, dirty state, before/after references, commands, exits, statuses, artifact checksums, and limitations.
- Claude/Codex installation parity, documentation, and regression verification.

### Out of Scope
- Deleting working data, caches, sessions, or residual directories; automatic pruning or sibling commits/pushes.
- Vendoring unlicensed upstream material, default recording/uploading, new hosted reviewers, architecture/style replacement.
- Changing Astra/cmux, Engram providers, Strict TDD, existing SDD receipt authority, or `integrate-codex-sdd-executor`.

## Capabilities

### New Capabilities
- `harness-health-diagnostics`: Nonmutating classification, ownership visibility, safe local protection, and accountable dispositions.
- `harness-evidence`: Client-neutral, local-only evidence manifests and installation guarantees.

### Modified Capabilities
None; no main capabilities exist.

## Approach

Use isolated RED/GREEN fixtures, controlled installation, then fresh `./verify.sh`. Share duplicated checkout mechanics; include untracked source, qualify local remote-ref evidence, and expose inspection failures.

Resolve panel ignores through its Git common-directory `info/exclude`, preserving existing content; defer team-wide `.gitignore` changes to an owner-reviewed dev-based PR. Keep legitimate owner/cache warnings visible with next actions.

Author original guidance. Store artifacts locally; distinguish PASS, FAIL, BLOCKED, and UNTESTED. Evidence supplements verification, not another review lane. Deliver autonomous test-plus-change slices within 400 authored changed lines using the agreed feature-branch chain.

## Affected Areas

| Area | Impact |
| --- | --- |
| `verify.sh`, `tests/` | Classification and regression coverage |
| `files/shared/skills/harness-evidence/`, `bootstrap.sh` | Shared contract and installation |
| `docs/`, `README.md` | Evidence/disposition guidance |
| External Git `info/exclude` | Narrow local protection only |

## Risks

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| Concurrent work loss | High | No cleanup or ownership takeover |
| Overstated evidence | Medium | Revision/dirty disclosure; explicit gaps |
| Sensitive disclosure | Medium | Local-only default; no automatic capture/upload |

## Rollback Plan

Revert only this change's commits; restore backed-up managed skill files. Remove only newly added ignore lines, preserving concurrent edits. Retain evidence and sibling data.

## Dependencies

Bash/Git, OpenSpec configuration, and `docs/research/michaelshimeles-skills-assessment.md`.

## Success Criteria

- [ ] Fixtures distinguish stale records from genuine missing instructions without mutation.
- [ ] Every baseline finding has evidence, disposition, owner/action, and honest residual status.
- [ ] Both clients install identical evidence contracts idempotently without preference loss.
- [ ] Fresh verification preserves Astra/cmux and existing SDD behavior; unresolved external findings remain explicit.
