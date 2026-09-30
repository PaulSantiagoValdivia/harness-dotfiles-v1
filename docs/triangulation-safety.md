# Triangulation safety

## Diagnostic stop is not cleanup

Run `triangulate stop <slug> [back,front,app]` to inspect local worktrees.
It preserves every working file (including ignored/generated-looking data),
Git index/ref/worktree metadata, branches, and sessions. It never fetches,
prunes, resets, removes worktrees, or terminates an owner.

Exit 0 means the requested diagnostic completed, NOT that sessions stopped,
work is published, or write ownership is available. `ahead` compares a local
upstream ref snapshot only. Missing paths/upstreams or failed Git inspection
report BLOCKED and exit nonzero; no clean/zero fallback is permitted.

Contact the existing owner through the authorized native channel. Inspect
changes and committed/pushed receipts before coordinating an explicit handoff.
Unknown `.atl/`, agent-memory, database, or ignored files remain recovery data
until the owner establishes otherwise. Do not delete them to silence warnings.

`bash tests/triangulate_launcher_test.sh` exercises this diagnostic against
real disposable Git worktrees with injected errors and complete byte snapshots.
Its transport is mocked; it does not certify live cmux messaging.

## Registry producer repair

SessionStart refreshes at the physical owning worktree root, not nested source
cwd. Exact HOME remains global; unresolved/nonrepository paths skip visibly.
Deploy with `python3 files/shared/lib/install-registry-hooks.py "$HOME" "$BACKUP"`
using a fresh backup directory. It installs the helper before recognized hook
command changes, retaining other configuration; bootstrap reapplies this overlay.
Rollback only saved managed paths after checking for later edits. Existing nested
`.atl` remains owner-controlled: preserve it and keep formatter gates unchanged.

## Fresh launch only

From an authorized cmux terminal, `triangulate codex <new-slug>` or
`triangulate claude <new-slug>` binds the exact canonical authority, checks
transport before mutations, and reserves all three repositories in sorted order.
Existing target paths/branches and unknown reservations are BLOCKED; historical
worktree directories alone do not establish liveness. `--force` cannot bypass
these gates. Resume does not launch another writer: continue via the existing
native owner after explicit handoff.

Both client prompts carry the declared authority, including explicit aliases.
Provisioning may precede plan artifacts, but implementation stays BLOCKED until
those exact artifacts exist. A launched topology is not a coordination PASS.
On partial failure, preserve created worktrees/sessions and inspect the reported
paths; only this invocation's matching-nonce reservations are released.

## Existing sessions: coordinate without relaunching

Use the known canonical coordinator, not a new launcher invocation. Reload the
installed `triangulation-orchestrator` skill there; discover exact sibling
paths/native identities, preserve their owners, and request current workers to
reload the same protocol. Use a fresh nonce and revision-bound HELLO/ACK before
implementation. Do not use `triangulate resume` or start replacement writers.

Routine dependencies, receipt corrections and safe read/test reassignment go
worker → lead → worker without human relay. Unresolved requirements, scope changes,
permissions and ownership conflicts stop affected work for a human decision.
Unavailable native tools or held/refused inboxes are diagnosed and BLOCKED, never
worked around by changing security settings. These prompt instructions cannot force compliance.

Generated-packet and instruction-contract tests leave live coordination UNTESTED.
The original C1 live-smoke prerequisite and historical failed verification report
remain intact; only actual retained native observations can certify operation.

## Live smoke: currently BLOCKED, not simulated PASS

The external session cannot access the cmux socket. Fixture PASS and installed
file parity do not prove live messaging, reassignment, current-session reload,
or production gates. Do not bypass socket policy or disturb existing sessions.
The following procedure is UNTESTED here; execute only with explicit permission
for three disposable repositories and isolated sessions inside authorized cmux.

### Bounded authorized procedure

1. Record the authorized scope, three Git roots/HEADs/dirty states, client/tool
   versions and session IDs. Run `cmux list-workspaces` from the authorized
   terminal: nonzero means BLOCKED before provisioning; do not retry externally.
2. Prepare one canonical fixture contract and record its SHA-256. Use a new slug
   and a fresh random nonce for this probe. Launch the native topology: Claude's
   three named sessions or Codex primary plus two workers, never unrelated peers.
   Confirm every worker receives the exact canonical path and read/test-only scope.
3. Coordinator records `time.monotonic_ns()` immediately before sending each
   `PROBE(nonce, contract_sha, role, request_id)` through the native channel.
   Workers read their own `git rev-parse HEAD` and ACK the same nonce, request,
   role, contract SHA and observed HEAD. Record ACK arrival on the SAME
   coordinator clock; do not subtract timestamps from different machines.
4. Allow at most 30 seconds per ACK and one retransmission with the same request
   ID. ACKs are idempotent; duplicates never create another assignment. A missing,
   mismatched or late ACK is FAIL/TIMEOUT, not success inferred from a pane.
5. Coordinator changes only the disposable contract, records its new SHA, and
   requires both workers to ACK that revision. Replay one old receipt: it MUST
   be rejected as stale, with no write assignment or completion authorized.
6. Through the live channel, reassign one idle worker an unblocked read/test
   task in a sibling fixture (for example, reading its HEAD). Require the owner
   boundary to remain unchanged. Allow 60 seconds for its receipt; never create
   a replacement writer or change repository ownership to make the probe pass.
7. Collect back/front/app receipts containing current nonce, contract SHA, role,
   session ID, repository HEAD/dirty qualification, command/exit, and result.
   Reject any stale or missing receipt. Coordinator alone consolidates outcomes
   and measured ACK/reassignment latencies. Overall budget: 180 seconds from
   first PROBE; after exhaustion stop assigning work and preserve sessions/data.

PASS requires both current ACKs, observed safe reassignment and all three valid
receipts within those bounds. Failed negative/stale tests mean FAIL. Missing
permission, socket access or ownership means BLOCKED; unexecuted steps remain
UNTESTED. Preserve local logs and actual timings; never invent them. Do not
publish product branches or automatically close/delete probe sessions/worktrees.

## Preserve gate failures and logs

`false; echo format_rc=$?; true; echo lint_rc=$?` exits zero despite formatting
failure. The last echo's status is NOT a gate receipt. Use the protocol's `&&`
chain for fail-fast execution, or continue diagnostics while preserving aggregate failure.
The following recipe returns the last nonzero exit (zero only if all gates pass):

```bash
rc=0
npm run format:check > "$EVIDENCE/format.log" 2>&1 || rc=$?
npm run typecheck > "$EVIDENCE/typecheck.log" 2>&1 || rc=$?
npm run lint > "$EVIDENCE/lint.log" 2>&1 || rc=$?
exit "$rc"
```

Set `EVIDENCE` to an existing private local directory first. Record each command's
actual exit separately when collecting multi-gate receipts. Do not upload logs,
truncate away failures, or interpret this example as replacing required unit tests.
`bash tests/triangulation_evidence_test.sh` extracts this exact block and checks six
all-success/single-/multiple-failure cases with fake npm, ordered calls and retained
stdout/stderr logs. This explicitly amends C2 test coverage, not historical results.

## Finding dispositions

Local receipts below live under `/tmp/triangulation-safety-evidence/` and are
machine-local evidence, not portable attachments or proof of later revisions.

| Finding | Disposition / evidence | Remaining ownership |
| --- | --- | --- |
| A1 wrong/newest authority | Corrected exact/alias binding; `authority-receipt.json`, `launch-receipt.json` | Missing operator aliases remain BLOCKED, never guessed |
| A2 incomplete commands | Full backend/app gates; `verification-receipt.json` | Real product gate execution needs authorized owners |
| A3 skip-as-success | Executed-PASS admission; `verification-receipt.json`, `installed-skip-probe.json` | No bypass; skipped work cannot promote |
| A4 directories imply liveness | Fresh-only reserved launch; `launch-receipt.json` | Historical/unknown owners preserved; live smoke BLOCKED |
| A5 destructive stop | Read-only snapshots and failures; `stop-receipt.json` | No cleanup/session termination authorized |
| A6 static parity implies live proof | Explicit static/mocked labels and bounded procedure above | Live coordination remains BLOCKED/UNTESTED |
| Nested registry writes | Root producer repaired; `registry-receipt.json`, `installed-registry-prettier-probes.json` | Existing residue owner-controlled; no formatter weakening |
| Semicolon/echo status masking | Reproduced in `gate-status-masking-probe.json`; aggregate regression fixture | Keep logs/individual exits; require full production gates |

## Final verification handoff

See the [fourteen-scenario evidence map](../openspec/changes/triangulation-safety/scenario-evidence.md).
Apply prepares source, scoped deployments and this map. After deployment parity
is recorded, the dedicated verifier owns ONE full `./verify.sh` invocation and
its complete log/exit; do not run it once merely to tick an apply prerequisite.
A full harness PASS still cannot certify the blocked live smoke. Report source
verification separately from live certification and retain that archive blocker.
