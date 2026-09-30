# Autonomous defaults and Stop network boundary

Authorized by the user's “perfecto haz todo” after the recovery/Stop audit.
This is a bounded follow-up, not approval of the live product plans.

- New SDD changes default to auto / auto-chain / feature-branch-chain.
  Explicit choices and the exact canonical change's persisted values win.
  Existing interactive plans and authority aliases are NOT rewritten.
- Chain identifiers resolve to dev when it exists, otherwise the repository
  default branch. A legacy name never permits a production-branch shortcut.
- Stop no longer performs remote Engram fetch/export/push. SessionStart pull
  and SessionEnd push remain. Local Engram memory persists; remote replication
  is delayed until session close or explicit synchronization. A crashed session
  may not publish remotely until a later successful synchronization.
- No asynchronous worker, scheduler, socket bypass or duplicate writer is added.
  This does not solve concurrent SessionEnd sync or offline network failures.

`python3 tests/friction_defaults_test.py` exercises a disposable HOME, unrelated
settings preservation, idempotence, guarded rollback, and unsafe overlay refusal.
The scoped installer accepts only recognized policy sections. Existing custom
sections stop installation before writes; originals are immutable in the chosen
backup. Installation is per-file guarded, not an atomic whole-HOME transaction.
Rollback: the same installer with `rollback HOME BACKUP`, refusing concurrent edits.
Source regression is not proof of active-session adoption or live timing savings.

## Installed observation

Installed the recognized three-file overlay after the predecessor's full suite
finished, using immutable backup `~/.claude/backups/friction-defaults-20260910T001455Z`.
Actual transformed bytes matched the installer; unrelated settings, all other
hook events, Codex model configuration, mappings and sync script were unchanged.
Global configured Stop hooks decreased from five to four. The project hook and
three unidentified hooks from the historical nine-hook UI report are separate.
Evidence: `/tmp/harness-friction-evidence/actual-install.json` (private local receipt).
No active cmux communication/adoption test: the socket probe returned connection
refused. Full predecessor suite: 686 PASS / 10 WARN / 0 FAIL in 513.330 seconds;
this follow-up has its own focused PASS and must not borrow that full-suite claim.
