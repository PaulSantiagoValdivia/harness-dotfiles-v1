<!-- gentle-ai:runtime-budget -->
## Runtime Budget and Orchestration (MANDATORY)

Claude Code and Codex MUST expose the same SDD, memory, review, and implementation capabilities. Optimize invocation, not capability: the primary agent executes ordinary work inline and loads expensive machinery only when the task needs it.

### Delegation gate

- Routing follows the ODD protocol and its Mandatory Delegation Triggers (mapping at 4+ files, writer at 2+ non-trivial files, preparation reads, long-session backstop). Below those triggers, work inline.
- In this harness the delegated WRITER is always Codex (`codex-run` for one task, `codex-build` for 3+ independent tasks); mapping/exploration delegation uses one Claude sub-agent on the cheapest adequate model. An SDD phase uses its dedicated executor only when SDD was explicitly selected.
- Keep one implementation writer. Never let a child delegate again; sequential phases remain allowed.
- Concurrency inside one primary session: one active child by default; **maximum two spawned children** only for independent work (including the SDD spec/design pair and explicit dual judgment). This cap does not limit separate top-level Claude/Codex sessions running in isolated Git worktrees.
- Use the cheapest adequate model/reasoning for delegated work: low for mechanical or bounded tasks, medium only when complexity or risk justifies it, and never ultra unless the user explicitly requests it.
- Enforce the same two-child ceiling in orchestration policy and in Codex `[agents].max_concurrent_threads_per_session`. Keep top-level cross-repository parallelism separate from spawned-agent concurrency.

### Context and memory budget

- At roughly 80k tokens, stop broad exploration and checkpoint; at 100k, persist and prefer native compact for the same task. These are planning guidance, not the measured Claude warning thresholds (200k/300k/400k). Preserve task/next action, decisions, receipt pointers, owner and active tool handles. Never automatically clear, relaunch writers or restart an active tool.
- Distinguish measured context from observed quota denial, dependency, permission and delivery blockers. Compact does not reset quota; never activate limit-reset, change accounts or bypass permissions automatically. Route dependencies through the coordinator; report exact unavailable capabilities instead of inventing a user decision.
- After compact, reload bounded canonical pointers and targeted memory; inspect current Git/process/owner facts and reuse existing readiness gates. Preserve approved auto/delivery choices; pending PR splitting, integration or deployment remains pending even when commits are pushed. New sessions are for intentional task switches or explicit safe handoffs, not automatic abandonment.
- Keep hook/additional-context payloads under 4 KiB. Never inject full plans, transcripts, diffs, or memory dumps at session start. Retrieve the full observation only after a targeted search shows it is relevant.
- Search Engram on recall/continuation, an unfamiliar referenced topic, or before work likely done earlier; do not search merely because it is the first prompt. Save durable decisions, fixes, discoveries, conventions, and one concise close summary—not routine reads or repeated reminders.

### One review lane

Choose exactly one final review mechanism per change: normal fresh review, Judgment Day, `dual-review`, or a project review plugin/command. Do not chain them automatically. `sdd-verify` proves the spec and tests; it does not require a second review unless risk or the user requests one.
<!-- /gentle-ai:runtime-budget -->
