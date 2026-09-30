# Design: Integrate Codex as an Optional SDD Apply Backend

## Technical Approach

Keep `sdd-apply` as integrator, gate runner, and sole OpenSpec writer. A compatible `mode: "sdd"` in `codex-build.js` executes one immutable packet in a temporary worktree and returns a content-bound receipt. Standalone fan-out is unchanged.

## Architecture Decisions

| Decision | Alternatives | Rationale |
|---|---|---|
| Apply owns selection, integration, reruns, and state; workflow owns execution/audit | Workflow owns SDD state | Preserves one writer and resumability. |
| One packet/worktree/commit per sequential invocation | Parallel SDD fan-out | Units observe accepted predecessors and have clear rollback. |
| Versioned JSON packet/receipt with hashes and Git identities | Prose handoff | Rejects stale, substituted, or incomplete evidence. |
| Never stash, clean, reset, resolve conflicts, or silently use `native` | Best-effort recovery | Protects edits and lineage; `spec-gap` has no commit. |
| Workflow audit is admission evidence | Reuse it as verification | Keeps `sdd-verify` independent and final. |

## Data Flow and Lifecycle

    sdd-apply -> eligibility/packet -> codex-build SDD mode
         ^                              | worktree(base) -> Codex -> commit -> audit
         |                              v
    tasks/progress <- gates <- cherry-pick <- validated receipt

Apply resolves `HEAD`, generation, allowed and dirty paths. Overlap, unreproducible base, duplicate lineage, or missing criterion stops. The workflow creates a worktree from `base_sha`, runs forwarded TDD commands, limits paths, requires one conventional commit, audits it, and emits a receipt. Apply validates identities/evidence, verifies `commit^ == base_sha`, and cherry-picks onto unchanged `HEAD`; conflict stops before state updates.

After authoritative reruns, apply marks the accepted unit complete and appends lineage, receipt, commit, results, and integrated revision. Resume reconciles Git and checkboxes; mismatches block.

## Conductor Runtime Paths

| Path | Contract |
|---|---|
| Claude Code inside Conductor | Uses installed `~/.claude/{CLAUDE.md,skills,agents,workflows}`. It MUST discover and invoke `codex-build` SDD mode, using bootstrap-patched `codexBin`; absence, wrong binary, or non-structured receipt fails closed. |
| Codex directly inside Conductor | Bypasses Claude and `codex-build`; uses Conductor's bundled Codex with generated `~/.codex/config.toml`, managed `~/.codex/AGENTS.md`, native SDD skills, and one direct Engram MCP. It MUST NOT impersonate workflow receipts. |

Both preserve OpenSpec, SDD, on-demand memory, one writer, Strict TDD, maximum-two/no-recursion, and independent verify. Claude delegates through its workflow at `medium`; direct Codex is native with Conductor default `medium` and review `high`. Neither uses `ultra`. Policy lives in instructions, never incompatible root `[agents]` scalars. Bootstrap owns home overlays; `files/conductor/settings.toml` owns UI defaults; app/DB/binary are runtime state.

## Interfaces / Contracts

`gentle-ai.sdd-execution-packet/v1` requires lineage/generation/unit, repo/base/tree, requirements/scenarios/constraints, allowed paths, Strict-TDD commands, and canonical payload hash.

`gentle-ai.sdd-execution-receipt/v1` requires packet digest, `accepted|rejected|spec-gap`, Git/diff hashes, touched paths, conventional subject, worktree, TDD records, audit verdict/issues, and receipt hash. Only `accepted` has one commit; `spec-gap` names missing/contradictory requirements and has none.

## File Changes

| File | Action | Description |
|---|---|---|
| `files/claude/workflows/codex-build.js` | Modify | Add isolated transactional SDD mode; retain standalone behavior. |
| `files/claude/skills/sdd-apply/SKILL.md`, `files/claude/agents/sdd-apply.md` | Modify | Route backend, validate/integrate receipt, reconcile progress. |
| `files/claude/CLAUDE.md`, `files/codex/AGENTS.md` | Modify | Shared authority contract with client-specific invocation notes. |
| `bootstrap.sh`, `verify.sh`, `tests/codex_sdd_backend_test.sh` | Modify/Create | Install from source overlay and exercise acceptance fixtures. |
| `README.md`, `docs/PRD.md` | Modify | Operator contract and limitations. |

## Testing Strategy

Strict TDD uses `./verify.sh`; applicable threats start as failing fixtures. `tests/codex_sdd_backend_test.sh` uses disposable repos/fake Codex to prove lineage, one commit, spec-gap, dirty overlap, tampered receipts, audit/conflict stops, resume, and state ordering. Runtime smokes separately prove: Claude-in-Conductor discovers/invokes the installed workflow and receives a valid receipt; direct Codex starts `app-server --strict-config`, loads native SDD/Engram once, and never invokes `codex-build`. Run both global and Conductor-bundled Codex strict-config checks. `verify.sh` also proves native/standalone compatibility, bootstrap idempotence/backups, overlay parity, `codexBin` patching, policy efforts/concurrency, and fail-closed behavior when either runtime prerequisite is absent.

## Threat Matrix

| Boundary | Applicability | Safe/failure behavior and planned RED test |
|---|---|---|
| Documentation-like paths | N/A | No executable-file classification changes. |
| Git repository selection | Applicable | Canonical packet repo/cwd only; reject relative escape, wrong absolute repo, or mismatched `git -C`. RED fixtures cover all three selectors. |
| Commit state | Applicable | Empty initial index; accept only one explicit commit of allowed paths; reject pre-staged data, `commit -a` leakage, and empty commit. RED fixtures cover each state. |
| Push state | N/A | Workflow never pushes. |
| PR commands | N/A | Workflow never creates PRs. |

## Migration / Rollout

`native` remains default; standalone arguments retain fan-out. Enable workflow Codex only after its runtime smoke passes. Bootstrap backs up overlays and patches installed `codexBin`; installed files are never source. Roll back to `native` or restore backups. Older receiptless progress remains native-compatible but is not Codex evidence.

## Open Questions

None; runtime capability is an acceptance gate.
