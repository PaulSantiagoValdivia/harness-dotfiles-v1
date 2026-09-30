# Triangulation Lifecycle Safety

## ADDED Requirements

### Requirement: Preflight before mutation
Start/resume MUST verify transport, declared canonical identity, and ownership before mutation/launch. Fresh provisioning MAY precede creation of its declared authority; implementation handoff MUST remain BLOCKED until it exists. Directories MUST NOT imply live writers; reuse/force MUST NOT bypass uncertain ownership.

#### Scenario: Verified ownership
- GIVEN authorized transport, declared canonical identity, and verified available ownership
- WHEN starting or resuming
- THEN permitted fresh topology starts without touching historical work; missing artifacts block implementation.

#### Scenario: Denied or uncertain launch
- GIVEN denied cmux access, an active same-slug writer, or unavailable liveness evidence
- WHEN start/resume is requested, including force
- THEN BLOCKED occurs before worktree creation, agent launch, or session modification.

### Requirement: Non-destructive diagnostic stop
Stop MUST inspect/report only, preserving worktrees, branches, ignored/unknown files, and sessions. Failed Git inspection MUST yield BLOCKED, not clean/zero assumptions or cleanup success.

#### Scenario: Stop preserves all work
- GIVEN clean, dirty, unpublished, or unreadable worktrees, including unknown generated-looking files
- WHEN stop runs
- THEN no removal, reset, pruning, branch deletion, or session termination occurs; inspection failures remain explicit.
