## Background wait discipline (MANDATORY — kills the "esperando en el vacío" stall)

Waiting on a background task (codex-run, tests, emulator) is NOT a passive act:
1. When you launch a bg task, RECORD its concrete completion evidence: the
   output file path AND the process signature (pgrep pattern).
2. On EVERY wake-up — whatever woke you — first CHECK THE EVIDENCE DIRECTLY:
   does the output file exist/end with an exit line? is the process dead?
   `git diff/status` in the worktree. Notifications are hints, not truth.
3. **Never end two consecutive turns with only "I'll wait".** If you are about
   to wait for the SAME task a second time, that is the stall signature
   (observed 2026-08-31: a subagent idled 3 HOURS on a task that had finished):
   instead, verify evidence and PROCEED from what you find — the work is
   usually complete (codex-run's own timeout note says the same). If evidence
   truly shows the task still running, wait with a BOUNDED capped loop
   (i=0; until <evidence> || [ $i -ge 30 ]; do sleep 20; i=$((i+1)); done)
   so you re-decide within minutes, never hours.
