# Closure comes from checked evidence, not a completion message

The existing DevTools archive setter now calls `verify_closure`. Both manual
HTTP archival and promote-and-archive use that setter; caller prose cannot
supply a PASS. Restore remains available and never deletes worktrees.

## Verification

`python3 ~/Documents/cocoa-devtools.py --verify-closure <slug>` returns JSON:
`PASS`, `BLOCKED` (known failed prerequisite), or `UNVERIFIED` (tool/access failure).
Non-PASS exits 2. It does not archive, push, fetch refs, or contact peer sessions.
When prerequisites pass it runs the existing fixed functional suites. During
promote-and-archive, only server-produced results from that same operation are
reused at the exact current revision; there is no persistent test cache.

Required evidence:
- Three configured distinct owners, clean worktrees, exact branch pushed,
  current HEAD included in provider-observed dev (unknown local object fails).
- Strict v2 recovery in all roles, validated phase, no waiting, pending delivery
  or blocker. Assigning a pending check to the user does not satisfy it.
- Canonical state/proposal/spec/design/tasks tracked; recovery checks their
  hashes. The clean backend HEAD must also pass the remote containment gate.
- Every checkpoint receipt points to bounded JSON with exactly these keys:
  `role`, `revision`, `status: "complete"`, `remaining: []`, `checks`.
- Each check has exactly `name`, `state: "PASS"`, `revision`, `path`, `sha256`.
  Required names: `functional`, `contract`, plus `device` for app. Revisions
  equal that owner's HEAD; paths name regular local evidence files, at most
  4 MiB each, with matching SHA-256. Duplicate names are rejected.

Legacy prose receipts and PR-number-only receipts are UNVERIFIED/BLOCKED, not
silently upgraded. This deliberately requires migration by existing owners.
Archive integration proof is provider ancestry, not a PR number claimed in YAML.
Actual PR identity corrections remain the canonical owner's responsibility.

## Limits and deployment

A hash proves evidence integrity, not that the model interpreted a crash log
correctly. Functional suites execute; contract/device evidence is recorded
attestation and still needs the established independent verification lane.
This gate cannot prevent misleading chat messages, certify native communication,
or stop an arbitrary process from editing the registry directly. Old archive
entries are not retroactively certified.

Installing source does not reload a running server. Do not restart a server
with active jobs to adopt it. The one-shot CLI executes the installed version
without creating another server; HTTP enforcement requires that version loaded.
Missing native peer access remains an exact capability blocker, not user work.

## Tests and rollback

`python3 tests/closure_gate_test.py` exercises isolated provider/hook/runner
fixtures; `python3 tests/cocoa_devtools_test.py` covers real disposable Git repos
and the free-text closure regression. Neither certifies live product QA.
Revert this source/test/docs unit and restore the guarded installed-file backup.
No product files or existing archive entries are changed by installation.
