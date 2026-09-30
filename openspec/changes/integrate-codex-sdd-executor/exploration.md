## Exploration: Integrate `codex-build` as an optional `sdd-apply` backend

### Current State

OpenSpec already governs SDD planning and verification, and `sdd-apply` already enforces the key lifecycle invariants: it consumes spec/design/tasks, honors the 400-line delivery decision, resolves Strict TDD from `openspec/config.yaml`, updates task checkboxes, emits cumulative apply-progress evidence, and returns control for independent `sdd-verify`.

`codex-build.js` is currently a standalone fan-out workflow, not an SDD executor. It creates one branch/worktree per task from the same `HEAD`, runs up to two tasks concurrently, asks Codex to edit without the SDD artifacts or TDD protocol, and has Claude inspect each worktree diff. It intentionally neither commits nor integrates changes. Its latest source and installed copy match, and a recorded smoke run proves worktree execution and independent audit work, but also documents why audit must fail closed when the worktree disappears.

That contract conflicts with SDD apply in five places: parallel tasks do not observe preceding work units; isolated worktrees do not include uncommitted authoritative workspace changes; no commit/transfer boundary exists; workflow audit is not the required runtime verification receipt; and the workflow cannot own OpenSpec task/progress state without creating two writers. The current working tree is already dirty, including relevant SDD/workflow files, so any implementation must preserve those edits and test dirty-baseline behavior explicitly.

### Affected Areas

- `files/claude/skills/sdd-apply/SKILL.md` — define backend selection, eligibility, handoff, integration, fail-closed, and evidence rules while retaining OpenSpec authority.
- `files/claude/agents/sdd-apply.md` — expose the workflow capability and pass the selected backend without turning the Codex runner into a second SDD orchestrator.
- `files/claude/workflows/codex-build.js` — add an SDD-compatible, sequential single-work-unit mode with structured receipts, base identity, TDD/commit requirements, and safe failure semantics; preserve standalone fan-out compatibility.
- `files/claude/CLAUDE.md` and `files/codex/AGENTS.md` — document backend ownership and routing consistently where client capabilities differ.
- `bootstrap.sh` — continue installing the workflow overlay and preserve architecture-specific `codexBin` patching; no second source of SDD truth.
- `verify.sh` and `tests/` — add source-level contract tests plus isolated integration fixtures for sequential lineage, dirty scope, rejected audit, resumability, and installed overlay parity.
- `README.md` and `docs/PRD.md` — explain the optional path, safety constraints, and the distinction between workflow audit and `sdd-verify`.
- Installed `~/.claude/{skills,agents,workflows}` — evidence only during development; bootstrap-managed source remains authoritative.

### Approaches

1. **Make `codex-build` the complete SDD apply engine** — pass all artifacts to the workflow and let it update tasks/progress and integrate results.
   - Pros: one invocation; most behavior lives in the workflow.
   - Cons: duplicates SDD state logic, creates competing writers, weakens OpenSpec authority, and makes resume/verification coupling opaque.
   - Effort: High

2. **Use `codex-build` as a transactional work-unit adapter owned by `sdd-apply`** — `sdd-apply` selects one pending work unit, invokes an SDD mode sequentially, accepts only a content-bound audited commit/receipt, integrates it into the authoritative writer workspace, independently reruns gates, then alone updates tasks and cumulative apply-progress.
   - Pros: preserves one OpenSpec writer, strict sequencing, conventional work-unit commits, resumability, independent verification, and standalone workflow compatibility.
   - Cons: requires a precise receipt/lineage contract and a clean-or-nonoverlapping workspace gate; workflow invocation support from the apply agent must be verified by acceptance tests.
   - Effort: Medium

3. **Bypass the workflow and call `codex exec` directly from `sdd-apply`** — implement Codex routing entirely in the skill/agent.
   - Pros: simpler control flow and direct access to artifacts.
   - Cons: discards the proven worktree/audit mechanism, duplicates Codex runner logic, and does not satisfy first-class integration of the existing workflow.
   - Effort: Medium

### Recommendation

Adopt Approach 2 with an explicit backend value such as `apply_backend: native | codex` (default `native`). OpenSpec artifacts remain the only planning authority, and the `sdd-apply` executor remains the sole state writer. The Codex workflow receives only one bounded work unit per invocation plus acceptance criteria, design constraints, strict-TDD command/protocol, allowed edit roots, expected base revision, and a unique lineage ID.

In SDD mode, force concurrency to one. Create the worktree from the exact accepted base, require Codex to produce RED/GREEN/REFACTOR evidence and one conventional work-unit commit, then have Claude independently inspect the real diff and rerun the focused/runtime gates before returning a structured receipt containing lineage, base SHA, commit SHA, tree/diff identity, commands, and audit verdict. The caller must reject missing, stale, ambiguous, or unverified receipts; integrate only the accepted commit; rerun authoritative gates in the writer workspace; then update `tasks.md` and cumulative apply-progress. `sdd-verify` remains the final independent spec gate and MUST NOT trust workflow audit as a substitute.

For dirty workspaces, fail closed when assigned implementation paths overlap uncommitted changes or when the accepted base cannot be reproduced. Do not stash, reset, clean, or snapshot unrelated user work. Report the spec/workspace gap and allow an explicit switch to the native backend; never silently fall back after Codex has started. If Codex discovers missing or contradictory acceptance criteria, it must make no integratable commit and return `spec-gap` so the apply phase stops without checking off tasks.

### Risks

- Claude workflow availability inside an `sdd-apply` sub-agent is not proven by the current agent tool allowlist; acceptance tests must establish the supported invocation boundary before relying on it.
- A worktree based on `HEAD` cannot represent overlapping uncommitted user changes. The Codex backend needs a hard eligibility gate rather than unsafe stashing or implicit commits.
- Existing `codex-build` task indexing assumes result order matches task order; SDD mode should avoid this ambiguity by accepting exactly one work unit or by binding every result to an explicit ID.
- Strict TDD evidence can be fabricated in prose. Receipts must bind commands and results to unchanged revision/tree state, and `sdd-apply` must independently rerun final gates after integration.
- Cherry-pick/integration conflicts must stop before artifact updates; automatic conflict resolution would violate safe stop and single-writer guarantees.
- The existing workflow note recommends `dual-review`, but the runtime policy permits exactly one review lane and SDD already uses `sdd-verify`; SDD mode must suppress that recommendation.
- Source overlays and installed copies can drift until bootstrap runs; verification must check both source contracts and installed state without editing installed files directly.

### Ready for Proposal

Yes. The proposal should scope a backward-compatible SDD mode for `codex-build`, explicit native/Codex backend selection, a fail-closed receipt and workspace-eligibility contract, tests before production changes under `./verify.sh`, and documentation/overlay verification. It should explicitly exclude parallel SDD implementation, workflow ownership of OpenSpec artifacts, automatic PR merges, silent fallback, and replacement of `sdd-verify`.
