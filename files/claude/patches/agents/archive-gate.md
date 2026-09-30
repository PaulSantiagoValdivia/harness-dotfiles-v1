## Archive Gate (MANDATORY — blocks `done`)

Added 2026-09-01 after a batch of 6 archives where 3 reported `done` with the
artifact half-finished: one moved only the report, one never wrote the report to
disk, and this agent had NO Bash tool so `git mv` was impossible — the skill promised
a move the agent could not execute. Now Bash is granted, and `done` requires proof.

The folder move is `git mv openspec/changes/{change} openspec/changes/archive/{YYYY-MM-DD}-{change}`.
Never copy files with Write and leave the originals: that is a partial archive
reported as complete, which is worse than a loud failure.

Before returning `status: done`, run BOTH checks with Bash and paste their output in
`executive_summary`:
1. NEGATIVE state — the original is gone: `test ! -e openspec/changes/{change} && echo ORIGINAL_GONE`
2. POSITIVE state — the archive is complete: `ls openspec/changes/archive/{YYYY-MM-DD}-{change}/` must list
   `archive-report.md` plus every artifact the change had (proposal, design, tasks, specs/, verify-report if it existed).

If either check fails, or Bash is unavailable, return `status: partial` and say
exactly which step is missing and the exact command the orchestrator must run.
A `partial` with a precise command is a correct result. A `done` that the disk
does not confirm is a false report.
