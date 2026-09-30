## Exploration: triangulation-context-recovery

### Current State
- Source inspection at clean initial revision `a906875`, branch `fix/triangulation-context-recovery`; one repository worktree, no product writes or live session actions performed. No main specs exist beyond an empty directory placeholder. Strict TDD uses `./verify.sh`; exploration did not rerun the broad gate.
- `triangulate-handoff.sh` resolves exact backend authority and validates mappings, Git roots, ownership of worktrees and path confinement. It emits fewer than 4 KiB, Git status, filtered state flags and three pending tasks; it neither reads a task/process/receipt checkpoint nor certifies live coordination.
- State parsing accepts `execution_mode` but existing change state files use `mode: auto`. Claude settings run the handoff only on `startup|clear`, excluding recovery after resume/compact.
- Actual Stop-side measurement thresholds are 200k/300k/400k; CLAUDE.md inaccurately documents 120k/180k/400k, alongside advisory shared 80k/100k planning limits. ALTO asks the user for `/compact` or `/clear`; CRITICO asks for `/clear`. CLAUDE.md also prescribes `/clear` after each work unit. These instructions plausibly explain interruption of an unfinished same-task delivery, but are not proof of the pasted session's cause.
- UserPromptSubmit only reads the cached warning, fail-open and without subprocesses. Its comment assumes context only grows: invalid across compaction. Measure code removes warnings when valid new measurements are below threshold, but a cached pre-compaction warning can survive until measurement refresh. Preserve this low-overhead architecture.
- Codex compact prompt mandates summary persistence followed by broad `mem_context`, losing the opportunity for checkpoint-targeted recovery. Existing protocol already defines fresh HELLO/ACK, owner adoption, receipt validation and dev integration closure: recovery should reuse these, not add parallel gates.
- Pasted session's claimed 319k context, weekly `/limit-reset` control, and pending ~4,400-line PR split are reported observations, not locally certified current measurements. A quota control does not establish that quota caused the stop. Coordinator reports a completed private read-only measurement at `/tmp/cmux-recovery-audit/report.json`; this executor has not inspected it. Native coordination certification remains separate. No measurement tooling is needed in this change.

### Affected Areas
- `files/claude/hooks/triangulate-handoff.sh`, `files/claude/settings.json`, `tests/triangulate_handoff_test.sh` — bounded checkpoint reload, mode compatibility, recovery event registration and safety fixtures.
- `files/claude/hooks/context-budget-measure.sh`, `files/claude/hooks/context-budget.sh`, `files/claude/CLAUDE.md` — recovery wording, truthful measurement documentation and stale-warning lifecycle tests.
- `files/shared/runtime-budget.md`, `files/codex/engram-compact-prompt.md` — same-task continuation and targeted cross-client recovery.
- `files/shared/skills/triangulation-orchestrator/references/protocol.md` — checkpoint schema, blocker taxonomy and reuse of existing ownership/readiness/closure contracts.
- Focused tests plus `verify.sh` registration if introducing new fixtures; scoped backup/install only for explicitly selected managed files, never full bootstrap of active sessions.

### Approaches
1. **Instruction-only clarification** — replace ambiguous clear/compact messages and document checkpoint fields.
   - Pros: small and independently reviewable; immediate safety improvement.
   - Cons: does not repair lost mode, compact/resume reload or cached warning lifecycle; agents can still omit checkpoint creation.
   - Effort: Low.
2. **Bounded checkpoint plus read-only recovery** — combine clarified messages with one explicit versioned, size-limited checkpoint under canonical recovery authority, allowlisted summary loading, event registration and existing coordinator revalidation.
   - Pros: carries exact task/receipt/process/ownership state across interruption; protects cached automatic delivery decisions; fixtures can prove parser and lifecycle behavior.
   - Cons: needs strict validation and deliberate coordinator-owned writes; cannot enforce model compliance or prove native live readiness by reading files.
   - Effort: Medium. Recommended.
3. **Automatic clear/relaunch/quota reset** — terminal automation replaces stalled owners.
   - Pros: superficially reduces manual steps.
   - Cons: destroys active-context/process evidence, can duplicate writers, spends user-controlled quota and bypasses permission boundaries.
   - Effort: High; reject as unsafe and outside scope.

### Recommendation
Use approach 2, delivered as autonomous review slices with authored changes below 400 lines each (planning artifacts count toward authored review size):
1. Context taxonomy, measured-threshold documentation, same-task native compact preference and cached-warning recovery with focused tests. Do not alter numeric thresholds or critical-warning protection merely to eliminate friction.
2. Explicit checkpoint contract and deterministic reload: version, slug/role/exact authority, recorded revision/dirty status, execution and delivery choices, task/next safe action, receipt/test pointers with revision, pending PR/integration/deploy work, observed native owner identity, active process handle/status, blocker classification/evidence/time. Bound checkpoint input before parsing and output below 4 KiB; treat fields as untrusted data, never executable instructions or fresh authorization. Workers submit recovery facts through the existing native channel; the canonical owner persists one bounded checkpoint. No background checkpoint daemon, transport or new orchestration engine. Missing/stale/invalid records mean recovery information unavailable, never alternate authority selection or fabricated ownership.
3. Client event/prompt wiring, scoped deploy/rollback receipts and focused end-to-end recovery fixture; reuse the coordinator’s existing private measurement rather than build new measurement tooling. Preserve existing native readiness handshake and integration gates exactly once.

Recovery distinguishes context pressure (checkpoint then native compact for the same task), quota exhaustion (observed provider evidence; no automatic reset/purchase/account change), active tool/process (inspect existing handle, do not duplicate), unresolved dependency (route to owner and continue independent work), permission denial (no bypass), and pending deploy/PR work (not complete). Compact is not a quota reset. A new session is for an intentional task switch or explicit supported handoff, not automatic abandonment of unfinished delivery.

Acceptance scenarios to turn into strict RED/GREEN fixtures:
- `mode: auto` round trip, legacy `execution_mode`, contradictory flags fail safely; delivery/chain choices survive without repeated user gates.
- Same task with pending PR split retains pending status and next slice after compact; pushed commits alone never imply integrated completion.
- Startup/resume/compact hook matcher coverage; missing checkpoint remains safe and legacy-compatible; stale identity/revision never restores readiness.
- Malformed/oversized/symlink-escaping checkpoint, unknown schema, command-like strings and multibyte overflow never execute or exceed payload budget.
- Active process receipt prevents duplicate test/run dispatch; unavailable native channel remains BLOCKED rather than relaunching writers.
- Measured warnings at exact boundaries retain quiet-mode behavior and unsilenceable critical warning; compact invalidates stale cache without slowing ordinary UserPromptSubmit.
- Cold reload preserves explicit scoped permissions and owner boundaries; fresh coordinator validation reuses existing HELLO/ACK requirements.
- Disposable-home scoped install/rerun/rollback preserves aliases, preferences and unrelated files; source fixtures are not reported as active-session or deployed proof.

### Risks
- Hook instructions cannot guarantee autonomous compliance; no live-certification claim without observed native round trips and receipts.
- Coordinator verified official Claude hook documentation: SessionStart `compact` fires after manual/automatic compaction; `resume` covers continue/resume. Source: https://code.claude.com/docs/en/hooks . Verify exact installed behavior during scoped deployment; source matchers alone are not deployed evidence.
- Checkpoint persistence must not give sibling workers canonical write rights or store sensitive transcripts; retain only bounded data/pointers.
- Context threshold documentation currently conflicts; align descriptions without silently changing guard thresholds.
- Stale warnings, checkpoint identity and in-flight tools require explicit lifecycle handling; clearing every warning indiscriminately would disable a safeguard.
- Full integration acceptance is expensive and was not run in exploration. Prior test counts are inherited receipts, not current candidate verification.

### Ready for Proposal
Yes — minimum end-to-end scope is identifiable. Keep cached automatic execution and feature-branch-chain delivery; plan slices before implementation. Report live cmux recovery separately from deterministic fixtures and leave quota/reset/update/product writes outside authorization.
