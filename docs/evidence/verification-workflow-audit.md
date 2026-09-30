# Follow-up workflow audit

Scope: bounded fixes after approved `7789afe`; its approval does not extend to
this new candidate. No active product writer, authority map or review policy change.

## Confirmed and corrected

1. `check()` discarded stdout/stderr and the original failure code. Failures now
   retain private output with the original code. Passing raw logs are removed.
   An unavailable receipt blocks that check, rather than claiming an execution.
2. Only total suite latency was observable. Each `check()` now announces its start
   and records whole-second duration in a private TSV, with source HEAD/dirty state.
   Direct checks outside this function are NOT instrumented. This is measurement,
   not a claim that execution itself got faster or a timeout/retry mechanism.
3. The manual checklist prescribed a second dual-review lane and a stale skill
   count. It now asks for the chosen review receipt and invocability metadata.
4. Engram's clean-index early exit skipped already-committed unpublished memory
   after a network failure. Publication is now separate from commit creation;
   identical exports retry pending commits without creating empty commits. Exhausted
   push failure ends with a pending-publication log, not a misleading `ok`.
5. The Engram gate ran installed test bytes, potentially omitting new regressions.
   It now checks source/installed hook parity and runs versioned fixtures against
   the installed hook. No need to execute the same fixture suite twice.

## Verification and boundaries

- Diagnostics: real baseline function loses rc/output (RED); changed helper retains
  both (GREEN). Disposable tests cover argv literals, timing, permissions, counters,
  and receipt failure. Logs are local, directory 0700/files 0600, never uploaded or
  printed automatically. Inspect/redact before sharing; raw failure output may be sensitive.
- Engram: original hook fails 2/89 cases (offline retry and false success log);
  corrected hook passes 89/89 using disposable HOME/local bare Git only.
- Bash 3.2 missing `source` plus EXIT trap returned zero in the first test setup.
  That was INVALID RED evidence. Explicit file preconditions and a Python-driven
  baseline probe replaced it; retained `diagnostics-before.log` is the genuine RED.
- Default shellcheck reports a pre-existing SC2016 informational warning in the
  Engram README string; warning-level checks pass. New diagnostics files pass fully.
- Concurrent sync writers remain a separate, unresolved risk. No locking or async
  conversion is claimed here. cmux still refuses the live socket connection.

Rollback: revert either conventional work unit independently. Restore only the
scoped Engram hook/test backup if deployed; never remove another owner's worktree.
