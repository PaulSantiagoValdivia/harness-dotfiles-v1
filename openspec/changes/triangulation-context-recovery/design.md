# Design: Triangulation Context Recovery

## Technical Approach

Extend existing read-only handoff and warning lifecycle; retain one canonical OpenSpec authority. Both clients consume the same checkpoint contract. Recovery restores facts, never authorization. No daemon, polling, Stop retry gate, native-channel facade, report reset, or product writes.

## Architecture Decisions

| Option | Tradeoff | Decision / rationale |
|---|---|---|
| Instructions only | Small, loses structured state | Reject; deterministic recovery needs bounded data. |
| Existing `triangulate-handoff.sh` parser shared by client invocation | Claude-named installed path, no second parser | Choose; Codex invokes the same explicit installed hook from its known worktree. No fabricated native hook support. |
| Coordinator-owned per-role checkpoint under canonical authority | Three bounded files; workers need live delivery | Choose; workers message facts, coordinator alone writes. Avoid cross-repository worker writes. |
| New ownership recovery protocol | Duplicates readiness | Reject; existing adoption HELLO/ACK and consolidation gates remain authoritative. |
| Scoped installer versus bootstrap | More focused preservation tests | Choose scoped overlay; bootstrap can overwrite unrelated active preferences. |

## Data Flow

Worker facts → existing native channel → coordinator checkpoint → native compact → validated handoff → current Git/artifact/process inspection → existing fresh readiness → next approved action.

Missing native access remains BLOCKED. Pushed commits, reported “all done,” or a weekly limit-reset control never prove completed delivery or authorize reset. Pending PR splitting/integration/deployment survives recovery.

## Interfaces / Contracts

Canonical `<authority>/recovery/<role>.json`, roles `back|front|app`, schema version `1`. Coordinator writes atomically; no automatic checkpoint producer. Allowlisted fields: version, slug, role, authority, worktree, branch, revision, dirty, observed_at, artifact_hashes, execution_mode, delivery_strategy, chain_strategy, task, next_action, owner, process, receipts, pending_delivery, blocker. Nested fields are explicitly allowlisted, bounded strings/lists; no transcripts or secrets.

Maximum input: 8192 bytes, bounded read before JSON parsing. Maximum total hook output: 3999 UTF-8 bytes including newline; retain safety footer before optional summaries. Reject duplicate/unknown keys, invalid types/enums/version, control characters, escaping/symlinked checkpoint paths, incorrect role/slug/authority/worktree. Resolve receipt pointers only inside the mapped worktree or canonical authority; never execute command-like values or automatically follow arbitrary pointers.

`artifact_hashes` binds proposal/spec/design/tasks relative paths to SHA-256; require exact current bounded artifact verification, otherwise mark checkpoint unavailable/stale. Recorded HEAD/branch mismatch also invalidates operational reuse; matching hashes/HEAD do not validate dirty bytes, ownership, tests, or readiness. Dirty snapshots require explicit inspection. Process stores observed handle/status/time, not a restart command; inspect the existing handle before dispatch.

Accept state `mode` and legacy `execution_mode` when valid/equal; contradictory aliases block recovery. Delivery enums remain existing domains. Unknown, missing, or stale checkpoint emits bounded unavailable reason and legacy authority pointers, never alternate-plan discovery or implementation authorization.

Compact lifecycle invalidates only the identified session's cached warning; reject unsafe cache paths. Preserve zero-fork normal UserPromptSubmit, 200k/300k/400k boundaries, quiet behavior and unsilenceable critical warnings. Measurement must not resurrect precompact usage; test compact-boundary lifecycle explicitly.

## File Changes

| Paths | Change |
|---|---|
| `files/claude/hooks/context-budget{,-measure}.sh` | Compact invalidation, truthful same-task wording. |
| `files/claude/hooks/triangulate-handoff.sh` | Bounded checkpoint and mode validation. |
| `files/claude/settings.json` | Handoff `startup|resume|clear|compact`; session-specific compact invalidation only. |
| `files/shared/runtime-budget.md`, `files/claude/CLAUDE.md`, `files/codex/AGENTS.md`, `files/codex/engram-compact-prompt.md` | Consistent continuity; targeted recovery instead of broad memory reload. |
| `files/shared/skills/triangulation-orchestrator/references/protocol.md` | Checkpoint, taxonomy, existing gates. |
| `files/shared/lib/install-triangulation-recovery.py` | Explicit HOME/backup scoped overlay following `install-registry-hooks.py`; reuse `install-shared-skill.sh`. |
| `tests/context_budget_test.sh`, `tests/triangulate_handoff_test.sh`, `tests/triangulation_recovery_install_test.sh`, `verify.sh` | Regression and installer acceptance. |

## Testing Strategy

Strict RED→GREEN→REFACTOR; runner `./verify.sh`. Disposable homes/repos only. Cover schema attacks, multibyte bounds, command strings, aliases, stale hashes, active-process/pending-PR continuity, warning boundaries and compact lifecycle. Installer tests cover fresh/rerun/rollback, backup collisions, symlinks and unrelated settings/aliases; modify only recognized hooks and managed instruction blocks, refusing ambiguous overlays.

## Threat Matrix

| Boundary | Applicability / safe-failure behavior | RED tests |
|---|---|---|
| Documentation-like paths | N/A: no executable classification | None |
| Git repository selection | Applicable: literal argv `git -C`, validated roots; invalid selector blocks | Relative/absolute/spaced paths; wrong repository |
| Commit state | N/A: no commit automation | None |
| Push state | N/A: no push automation | None |
| PR commands | N/A: pending metadata only | None |

## Migration / Rollout

Three autonomous slices: warnings; checkpoint; wiring/install. Each includes tests, stays below 400 authored lines including planning, and rolls back independently. Feature-branch-chain; only tracker targets dev/default exception. Scoped immutable backups, atomic replacements and concurrent-change checks; preserve permissions/preferences/mappings. Reuse `/tmp/cmux-recovery-audit/report.json`; separate fixtures, installed probes and native certification.

## Open Questions

None blocking; no live recovery claim without observed native evidence.
