# Automatic three-repository triangulation

## Invariants

| Concern | Contract |
|---|---|
| Authority | One canonical OpenSpec change, normally in backend. |
| Parallelism | Three workstreams: canonical primary + panel owner + app owner. |
| Writers | One active writer per repository. A worker may read siblings but cannot edit them without an ownership transfer. |
| Live coordination | Native runtime messages carry decisions, blockers, API drift, and receipts. |
| Recovery | Git + OpenSpec are authoritative; Engram preserves durable handoffs across client/quota changes. |
| Completion | The primary alone consolidates results and declares the multi-repository change complete. |

## Runtime topology

### Claude

If the user already opened three same-key sessions, the canonical session becomes
lead. It uses `ListAgents` to match sessions by working directory and
`SendMessage` for direct delivery. It requests one-shot idle notices rather than
polling.

If only one session exists, use an agent team with two predictable teammate
names. The primary owns the canonical repository; each teammate receives an
exact sibling path and owns one repository. Use the shared task list for
dependency state and direct teammate messages for contract changes.

### Direct Codex

Do not open three independent top-level Codex sessions and call them coordinated:
Codex has no native peer channel between those sessions. Use one primary Codex
thread in the canonical repository and spawn exactly two named children for the
sibling repositories. The primary continues canonical work while children run,
routes follow-ups, waits for mailbox updates, and consolidates their results.

## Launcher

Use the managed launcher from a terminal already running inside cmux:

```bash
triangulate claude <change-slug>
triangulate codex <change-slug>
```

The Claude command opens three named top-level sessions. The Codex command
creates three fresh worktrees, rejects existing targets, grants both sibling
paths with `--add-dir`, and opens one canonical primary whose initial prompt spawns exactly
two agent threads. Use `triangulate plan codex <change-slug>` to inspect the
resolved topology and command without mutating Git or opening cmux panes.
Preserve existing worktrees as recovery sources; coordinate with their current
owners rather than relaunching another writer.

## Native startup readiness

Every launcher packet activates this skill and binds a fresh 128-bit run nonce,
role, own worktree/write boundary, sibling paths and exact canonical artifacts.
Missing artifacts permit read-only discovery and back-owned canonical SDD planning,
not implementation. Workers never create a competing plan or delegate.

1. Discover native identities and match exact paths/roles, not names alone. Claude
   uses `ListAgents`/`SendMessage`; Codex forwards scoped packets to two children.
   Allow two discovery attempts: initial and one event-triggered retry, or one
   scheduled retry within 10 seconds if no event. Missing peers after the second
   attempt are BLOCKED; never poll or wait indefinitely before HELLO.
2. Before implementation, send HELLO with nonce, request ID, observed native identity,
   role, worktree, authority, actual current contract-artifact SHA-256, task and write
   boundary. Never fabricate hashes before artifacts exist. Both distinct workers
   must ACK those fields and accepted scope through the native channel.
3. Require observed bidirectional delivery. Missing, duplicate, stale, late,
   wrong-role/path/authority, mismatched hash/identity/scope or refused ACKs cannot
   establish readiness. Duplicates never authorize another assignment.
4. Allow one same-request follow-up per peer within 120 coordinator-clock seconds
   from HELLO issuance, not startup/planning. Unavailable tools, inbox refusal or
   exhausted bounds are BLOCKED; preserve owners/data, never bypass permissions.
5. Revisions/replacements invalidate readiness and require fresh ACKs. Replacement
   additionally requires a stopped owner and clean handoff; never duplicate writers.

This is an instruction contract, not enforced write authorization or guaranteed
model compliance. Dispatch/fixture PASS leaves live coordination UNTESTED. Native
round trips, safe follow-up and three receipts remain required for certification;
the separate bounded smoke retains its 180-second overall budget.

## Autonomous routing and existing-session adoption

| Situation | Required action |
|---|---|
| Routine dependency clarification, test failures, drift within approved scope, receipt corrections | Route worker → lead → worker immediately; resolve from canonical artifacts without human relay. |
| Idle capacity | Assign safe unblocked read/test work or the next task inside existing ownership; no busywork or polling. |
| Unresolved requirements, scope expansion, permissions, ownership conflicts | Stop affected work and request the human decision; continue only independent safe work. |

Use the known existing coordinator for an already running change:

1. Reload the installed skill and this protocol in the existing coordinator;
   inspect canonical artifacts, statuses and exact sibling paths. Ask current
   workers through the native channel to reload the same contract.
2. Discover observed native identities and verify existing ownership. Generate a
   fresh nonce and run the bounded readiness handshake with current artifact hashes;
   require fresh ACK from both exact workers before implementation dispatch.
3. Never launch another top-level session or use `triangulate resume` to adopt
   owners. Never create a replacement writer or overwrite an active worktree.
   Replacements require the existing stop/clean-handoff contract.
4. Diagnose unavailable tools or a held/refused inbox with the actual runtime,
   provider/tool availability and observed inbound status. Report BLOCKED;
   never change permissions, security settings or transport to force delivery.

Reloading files or seeing named panes is not an observed handshake. These rules
cannot force model compliance; retain native replies, safe follow-up and all three
receipts before claiming certified coordinated delivery.

## Receipt dispatch is a tool action, not a chat question

Before ending a turn that needs worker receipts, issue the missing requests through
`SendMessage` to discovered current identities. Include request ID, nonce, exact
worktree/role, contract revision and required receipt fields. Never address peers
only in user-facing final text or ask the user to forward routine requests.
Inspect structured send success, including `success:false` inside a normal tool
result. Track requested → accepted/held/refused → replied → validated separately;
accepted delivery is not an ACK, receipt, or completed dependency.
If already sent, do not resend just to satisfy a hook. Use the existing bounded
follow-up/one-shot idle mechanism; on refusal or exhausted budget report the exact
blocker and continue independent work. Rediscover stale identities only within the
existing retry budget, never guess a peer or bypass inbound controls.
Device confirmation may remain a user-owned blocker for that acceptance check,
not for gathering technical receipts. Preserve actual test evidence; never mark
an unexecuted device check PASS or call an ACK a completed feature.

The Claude Stop relay guard is a narrow, one-continuation wording detector. It
uses `last_assistant_message`, skips `stop_hook_active`, and neither sends messages
nor proves native execution. Codex consumes this protocol without pretending to
have that Claude hook. Real native receipts remain required in either client.

## Canonical authority and scoped recovery

The requested slug binds `back/.claude/worktrees/triangulate-<slug>/openspec/changes/<slug>`.
Fresh provisioning may precede that directory; implementation/handoff remains BLOCKED
until the exact authority exists. Never select another plan by name or timestamp.
Repository roles are literal unique `back=`, `front=`, `app=` absolute Git roots in
`TRIANGULATE_CONFIG` (default `~/.claude/triangulate.conf`). Explicit aliases use
`slug=change-slug` in `TRIANGULATE_CHANGES_CONFIG` (default
`~/.claude/triangulate-changes.conf`); duplicate keys, conflicting existing exact
changes, invalid identifiers, escaping paths, and failed Git checks are BLOCKED.
Aliases are operator-owned: installation must never generate or overwrite them.
A handoff is bounded local context, not proof of live coordination or write ownership.

Scoped deployment: back up the existing managed hook before copying
`files/claude/hooks/triangulate-handoff.sh` to `~/.claude/hooks/`; do not run full
bootstrap for this correction. Source `files/shared/lib/install-shared-skill.sh`
and call `install_shared_skill files/shared/skills/triangulation-orchestrator "$HOME" "$BACKUP"`
with a fresh explicit backup directory. This updates the whole skill tree in both
clients, preserves unchanged installs, and refuses backup collisions. Compare source
and installed hook with `cmp`, both skill trees with `diff -qr`; leave mappings and
client preferences untouched. Rollback only those managed paths from saved copies
(or remove newly installed managed paths on fresh homes), never worktree data.
`bash tests/triangulate_handoff_test.sh` proves this sequence in disposable homes.

## Same-task recovery checkpoint

Before native compaction, the coordinator atomically writes each received role's
bounded facts to `<authority>/recovery/<role>.json` (`back|front|app`). Workers send
facts through the existing native channel; they never write canonical artifacts.
Do not create a daemon, reset quota, clear the session or relaunch a writer.

Schema v1 requires exactly these fields (unknown/duplicate fields are rejected):
| Fields | Contract |
|---|---|
| `version`, `slug`, `role`, `authority`, `worktree` | Integer `1`; exact requested slug/role and resolved absolute canonical/worktree paths |
| `branch`, `revision`, `dirty`, `observed_at` | Recorded branch/HEAD, boolean dirty status, timezone-aware ISO timestamp |
| `execution_mode`, `delivery_strategy`, `chain_strategy` | Existing mode/delivery/chain enums; agree with current state if present |
| `task`, `next_action` | Nonempty recorded task and next safe action, not executable commands |
| `owner` | Exactly `identity` (nonempty observed identity), `status` (`active|stopped|unknown`) |
| `process` | Exactly `handle`, `status` (`running|finished|unknown`), `observed_at`; running requires a handle |
| `receipts` | List of `{path, revision}`; existing resolved pointers inside owned worktree/canonical authority, Git SHA |
| `pending_delivery` | List of nonempty pending PR/integration/deploy facts; pushed commits do not mean complete |
| `blocker` | Exactly `kind` (`none|context|quota|tool|dependency|permission|delivery`), `evidence`, `observed_at` |
| `artifact_hashes` | Exact SHA-256 map for proposal/design/tasks and every `specs/<domain>/spec.md` |

Keep input ≤8192 bytes, each string ≤512 UTF-8 bytes, lists ≤16 and maps ≤32 entries;
no controls, transcripts or secrets. State input is bounded at 64 KiB and each
hashed artifact at 256 KiB. Paths must remain inside authority; checkpoint and
hashed artifacts must be regular, non-symlink files. `mode` and legacy
`execution_mode` accept equal values; contradictory, duplicate or invalid values
block recovery. Missing/stale/invalid checkpoint retains only legacy discovery.

Read the shared installed handoff after recovery, including from Codex's known
worktree. Output stays below 3999 bytes with safety notice and checkpoint pointer
before optional data; a truncation notice requests targeted reload. Inspect current
Git, dirty bytes, receipts and existing process handles before dispatch. Recorded
facts never authorize ownership; reuse existing fresh HELLO/ACK and closure gates.
Unavailable native transport remains BLOCKED, not fixture-proven coordination.

### Scoped recovery overlay

Run from the harness checkout with an explicit existing HOME and a NEW backup path:
`python3 files/shared/lib/install-triangulation-recovery.py install "$HOME" "$BACKUP"`.
The wrapper stages the shared skill via `install-shared-skill.sh`, changes only
recognized recovery hooks/managed blocks, and preserves unrelated settings/model,
permissions and mappings. It does not bootstrap normal hooks in a fresh home.
The backup manifest and originals remain immutable; identical reruns are no-ops.
Rollback: `python3 files/shared/lib/install-triangulation-recovery.py rollback "$HOME" "$BACKUP"`.
Rollback refuses drift instead of overwriting newer work. Files replace atomically;
whole skill trees use a guarded rename pair (brief absence is possible). On partial
failure, preserve the backup and inspect; never reset active product worktrees.

## Task states and recoverable waits

ACK means scope received, never implementation, device acceptance or delivery done.
Use `acknowledged`, `working`, `receipt_pending`, `validated`, or `blocked` for the
current task; keep change completion subject to all existing final delivery gates.
Technical validation and remaining delivery/human acceptance are separate facts.

Before yielding for a dependency, persist recovery schema v2 in the existing
`recovery/<role>.json`, not a competing plan. Keep all v1 fields, set `version: 2`
and add exactly `coordination: {phase, wait}`. `wait` is empty for nonwaiting phases;
`receipt_pending` and `blocked` require a nonempty wait with these exact fields:
`kind` (peer|human), `owner`, `request_id`, `event`, `mechanism`, `handle`, `scope`,
`started_at`, `deadline`, `next_action`. Strings are bounded by the existing limits;
timestamps include timezone, deadline follows start. Native mechanisms are
`native_reply` or `idle_notice`; human waits use `user_response`. Use `unavailable`
with an empty handle only to record a missing mechanism, never pretend it is armed.
All available mechanisms require the observed request/subscription handle. Never
invent a notification or recipient. An unavailable mechanism is a capability
blocker, not permission to repeatedly ask the user or start another writer.

Record only the affected scope, e.g. device smoke, not the entire triangulation.
Route independent receipts/contract checks while that acceptance remains blocked.
The coordinator may go idle after dispatch but remains responsible: do not close,
clear or abandon the lead while promising a later integration without an explicit
safe handoff. On the real event, reload this state, revalidate identities/artifacts,
and resume `next_action`; do not ask again for an authorization already recorded.
An expired recorded deadline requires revalidation using the existing retry budget,
not automatic resend, publication or a new loop. Deadlines are persisted wall-clock
recovery hints; measure live latency on the coordinator monotonic clock.

`validated` requires recorded clean state, current receipt pointers and no blocker;
it never overrides pending delivery or proves receipt content by itself. SessionStart
validates structure/current artifacts, not native message delivery. Legacy v1 stays
readable with `LEGACY_WAIT_UNVERIFIED`; enrich it from current owner facts before
relying on a waiting mechanism. Never rewrite existing product checkpoints blindly.

## Task packet

Every assigned task includes:

- change/worktree key and repository role;
- exact repository/worktree path;
- canonical proposal, spec, design, and task paths;
- allowed write boundary;
- dependencies and current blockers;
- acceptance criteria and focused test command;
- receipt destination: the primary/coordinator.

## Message rules

Send a live message immediately when any of these occurs:

- API, schema, date/time, validation, or error semantics change;
- a dependency becomes ready or blocked;
- a worker detects conflicting edits or incorrect task ownership;
- focused tests fail because of another repository's contract;
- a task or repository receipt is ready.

Batch non-urgent updates. Never run a polling loop. An idle notification, agent
mailbox update, or completed worker result is the wake-up signal.

## Automatic reassignment

When an owner becomes idle, the primary checks the dependency graph and:

1. assigns the next unblocked task inside that owner's repository;
2. otherwise assigns read-only analysis, tests, or receipt validation for a
   sibling repository;
3. transfers write ownership only after the previous owner stops, records
   branch/commit/status, and confirms there are no uncommitted conflicting
   edits;
4. leaves the owner idle when no safe task exists. Never create busywork merely
   to keep all workers occupied.

## Module Definition of Done (MANDATORY — closes the "half-delivered module" class)

Root cause of most "worked module A, module B broke" incidents is not drift:
it is a module merged without its operational pieces (audit §7: readiness that
lies). Every receipt whose work TOUCHED a module MUST answer this checklist —
`yes`, `no` (with blocker), or `n/a` (with one-line reason). Silence on any
item makes the receipt INVALID, same rule as verification commands.

```text
module_dod:
  contract_migrated: yes | no | n/a     # typed XWire + panel re-export (rule: touched module = migrated module)
  seeds_applied:     yes | no | n/a     # nav / perms seeds for the target env
  indexes_deployed:  yes | no | n/a     # composite indexes the new queries need
  rules_updated:     yes | no | n/a     # Firestore rules for new collections/fields
  backfill:          done | scheduled | n/a   # old docs reshaped, or explicitly scheduled
  readiness_updated: yes | no | n/a     # module readiness reflects real config state
  route_smoke:       pass | fail | n/a  # the module's page/route loads without JS/HTTP errors
  wire_defects_filed: yes | none        # defects found in the wire are FILED as contract_changes, never fixed in the same PR
  reader_before_writer: yes | n/a       # deploy-order: every consumer that READS a new field ships BEFORE the writer starts writing it (post-mortem "saldo invisible" 2026-08-19)
  sessions_refresh: yes | n/a           # if perms/nav/modules changed: how do LIVE sessions get them? (seed alone leaves 403 until logout/login — company.inbox runbook)
```

The primary consolidates `module_dod` blocks; any `no` without blocker or
missing item sends the receipt back. Wire fixes always ship as separate,
deliberate contract PRs (see Contract-drift rule) — a migration PR photographs
the wire as-is minus `_legacy_*`.

## Repository receipt

Each owner returns one bounded receipt:

```text
role: backend | panel | app
runtime: claude | codex
status: complete | blocked | handed-off
path: <absolute worktree path>
branch: <branch>
base: <rebased base commit>
commits: <ordered commit hashes>
files: <changed files summary>
contract_changes: <API/schema/behavior changes or none>
tests: <exact commands and results>
dev: pending | integrated:<commit> | no-changes:<commit>
remaining: <blockers or none>
```

Completed work must be committed and pushed according to the global Git policy.
For a client handoff, preserve dirty but incomplete work only when committing it
would misrepresent correctness; the incoming owner must inspect it before any
edit.

## Verification commands (the ONLY definition of "verified")

"Tests pass" and "contract checks" are these exact commands — not judgment calls:

| role  | working dir            | command                                   |
|-------|------------------------|-------------------------------------------|
| back  | `<worktree>/functions` | `npm run typecheck && npm run format:check && npm run lint && npm run test:unit` |
| front | `<worktree>`           | `npm run check:all`                       |
| app   | `<worktree>`           | `flutter analyze && flutter test`         |

A receipt's `tests:` field MUST contain these commands and their real exit
status. A receipt whose `tests:` line omits the role's command is INVALID and
the primary must send it back, not consolidate it.

## Contract-drift rule (MANDATORY — root cause of "backend done, panel broken")

The panel duplicates backend contracts by hand (`src/types/*.ts`, zod schemas
marked "Source of truth: cocoa-core-backend/..."). Nothing fails at compile
time when the backend changes shape — drift only surfaces at runtime. Therefore:

1. Any backend commit that changes an API/schema/callable shape REQUIRES an
   immediate live message to front (and app if affected) naming the exact
   endpoint/type and the backend file that is now source of truth.
2. On receiving that message, the front owner updates the mirrored types/schemas
   in the same triangulation and re-runs `npm run check:all` BEFORE its receipt.
3. A front receipt is STALE if its verification predates the last backend
   `contract_changes` message. The primary must not consolidate a stale receipt
   — request a re-run; front re-verifies against the backend branch as it will
   land, not as it was when front started.
4. `contract_changes: none` in the backend receipt is an explicit claim the
   primary spot-checks (diff over `functions/src/**` routes/modules), not a
   default to be trusted blindly.

## Consolidation gate

The primary may close the triangulation only after it:

1. receives all three receipts;
2. fetches/rebases each branch and checks overlapping contracts;
3. verifies backend API and consumer expectations agree;
4. checks owners' exact commands, results and revisions against current worktrees
   and final backend contract; rejects missing, failed or stale receipts and routes
   corrections to the owning session, without duplicate writers;
5. updates the canonical OpenSpec tasks/apply progress;
6. reports commits, pushes, tests, blockers, and any safe reassignment performed;
7. receives the Cocoa DevTools receipt proving backend, panel, and app reached
   `origin/dev` (or had no changes) after QA verification.

Until step 7 succeeds, report `ready-for-qa`, not `complete`.

Do not rerun the full per-repository suites merely to consolidate owner receipts.
This removes only the redundant middle run, not owner verification or the
mandatory final verification in the existing delivery lane. Receipt inspection
is not a reusable verification cache and never authorizes skipping that gate.
Preserve explicit review/SDD requirements; the coordinator still performs
cross-repository contract checks and resolves drift. If a head/base, contract,
dependency or environment changes, route the affected verification to its owner
and require current final validation. Unknown freshness is not PASS. Do not
invent an environment fingerprint or claim same-SHA receipts are interchangeable.

The final verifier reports `elapsed_seconds` on its monotonic clock for the
whole attempt, including preflight. Record state, executed, returncode and tested
revision alongside duration; SKIPPED/BLOCKED timing is not executed-test time.
Measure observed redundant executions separately; do not claim time saved from
policy text alone. No new cache, alternate delivery lane or protection bypass.

## Local QA control plane

Run `devtools` after owners have returned their receipts. Cocoa DevTools groups
all matching worktrees from the managed backend, panel, and app repositories;
it does not replace live coordination or OpenSpec.

The operator may mark one triangulation as QA verified only after checking its
tests and receipt evidence. Dev integration runs the verification commands
table per role and fails closed on any non-zero exit — a promote that pushed
without running them is a bug, not a fast path. Dev integration requires all three repository roles
and blocks before the first push if any worktree is dirty, detached, or behind
`origin/dev`. It preserves each feature branch, then fast-forwards dev without
force-pushing. It publishes the immutable SHA that passed prevalidation, never
a mutable `HEAD`, and proves that SHA remains reachable from the final
`origin/dev`. Backend, panel, and app all use `origin/dev`; new triangulation
work never starts from `main`.

Git cannot atomically update three separate remotes. If one dev ref moves after
prevalidation, that push must fail closed, return a partial receipt, and keep
the triangulation open until the coordinator safely retries the remaining repo.

Merged PRs do not remove local worktrees. After a successful final receipt (or
when equivalent work was merged through replacement PRs), archive the slug in
Cocoa DevTools with PR/commit evidence. Archiving only hides historical entries
from the active QA queue; it never deletes worktrees, branches, or local files,
and the operator can restore the entry for audit or recovery.

Functional receipts carry `role`, `command`, `executed`, `state`, `returncode`, and
`tested_revision`. Only executed PASS with unchanged pre/post-test SHA, branch and
clean worktree qualifies; revalidate all three snapshots before the first push.
SKIPPED (`VERIFY_SKIP=1`), BLOCKED prerequisites/spawn failures, FAIL, TIMEOUT, or
unknown states never authorize publication, regardless of numeric exit code.
Disposable fixtures inject executable runners, never a production success bypass.

## Evidence admission

Static configuration parity and mocked transport topology are not live messaging
proof. Live smoke requires authorized isolated scope, nonce/current-contract ACKs,
safe read/test reassignment, three current receipts and measured coordinator-clock
latencies. Stale/missing receipts block consolidation; unavailable transport is
BLOCKED, never bypassed. Follow the bounded harness `docs/triangulation-safety.md`
runbook when operating from its checkout; no automatic smoke or cleanup.
Preserve command logs and individual exits. A semicolon-separated command list
ending in a successful `echo` does not prove earlier gates passed. Use the exact
`&&` gates above, or aggregate nonzero exits without dropping required checks.
