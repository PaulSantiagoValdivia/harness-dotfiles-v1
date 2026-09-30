**Module DoD in task generation (MANDATORY — the user's bottleneck lives at planning time).**
For EVERY module the change touches, the tasks list MUST include explicit task
items (or a per-module DoD sub-checklist) covering: typed contract migrated
(touched module = migrated module), nav/permission seeds, Firestore composite
indexes, rules updates, backfill for existing docs (done or scheduled), module
readiness updated, and a route smoke check. Mark inapplicable items `n/a` with
a one-line reason INSIDE the tasks doc — never silently omit them. A plan that
ships code tasks without these operational tasks produces "half-delivered
modules" (readiness that lies), which is the recurring failure this rule kills.
Reference: ~/.claude/skills/triangulation-orchestrator/references/protocol.md
section "Module Definition of Done".
