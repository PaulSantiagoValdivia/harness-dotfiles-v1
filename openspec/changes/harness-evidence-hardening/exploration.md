## Exploration: Harness evidence hardening

### Current State

Fix the verifier's checkout classification, retain honest ownership warnings, and add a small original evidence contract shared by Claude and Codex. Do not import the upstream collection wholesale.

- `openspec/config.yaml` enables Strict TDD with `./verify.sh`. The verifier combines isolated source tests, installed-state comparisons, and live sibling-repository checks. Main specs currently contain only `.gitkeep`.
- The provided baseline `/tmp/astra-harness-verify.log` reports **701 PASS / 17 WARN / 7 FAIL**. This exploration inspected code and current Git state; it did not rerun that acceptance suite or mutate installed state.
- **Six failures are classification defects.** The three backend paths under `/private/tmp` still exist, but have no `.git`: `wt-onboard`, `wt-pf-dev`, and `wt-pf-master`. `validate_core_root()` checks only directory existence, then demands `CLAUDE.md` and `AGENTS.md`. Later, `audit_worktrees()` correctly recognizes missing `.git`. These are residual directories, not entirely absent paths; pruning registration is not a substitute for fixing the predicate.
- **One failure is real local protection drift.** The canonical `cocoa-core-next` checkout does not ignore `.claude/worktrees/`; read-only `git status --short --branch` exposes multiple nested worktrees as untracked. `.atl/` also lacks an ignore rule. Its checkout is `main`, ahead 1 and behind 530 against locally known `origin/main`: do not commit there or rebase unrelated work.
- **Warnings include other sessions' real work.** Read-only inspection confirmed dirty backend/panel/app worktrees and unpublished commits. `audit_worktrees()` currently uses `--untracked-files=no`, hiding untracked source files, including backend `hr-reconocimiento.audiencia-par.ts` and its test. Remote containment checks use existing remote refs, not a fresh remote query.
- Cache-age and disk-size warnings are advisory evidence, not proof that files are safe to delete. Legacy Conductor worktrees are recovery sources, not new runtime targets.
- `bootstrap.sh` already backs up and copies a shared triangulation skill to both clients. `tests/standalone_runtime_parity_test.sh` compares source and installed content; `tests/agent_patches_test.sh` exercises isolated installation, idempotence, and drift handling. These are the natural integration seams.
- The existing `openspec/changes/integrate-codex-sdd-executor/` owns optional backend routing and transactional receipts. Preserve its artifacts and do not introduce competing apply/verify ownership.

### Affected Areas

| Area | Proposed responsibility |
| --- | --- |
| `verify.sh` | Use one real-checkout classification for core/app validation and hygiene; surface untracked work and qualify remote-ref evidence. |
| `tests/` (new focused fixture suite) | Reproduce residual directory, valid checkout missing instructions, tracked/untracked dirt, generated registry exclusions, and nonmutation cases. |
| `files/shared/` (small helper if needed) | Share checkout classification only where duplicated; avoid a broad audit framework. |
| `files/shared/skills/` (new original evidence skill) | Bound evidence by revision, working state, command, exit code, observed result, and explicit unavailable checks. |
| `bootstrap.sh` | Install the new shared skill in both clients with backups, idempotence, and registry refresh. |
| `tests/standalone_runtime_parity_test.sh`, focused installer tests | Check both installed clients and supporting files; detect drift and preserve existing skills. |
| `README.md` / concise evidence guidance | Explain local-only receipts, optional visual evidence, sanitation ownership, rollback, and residual warnings. |
| External `cocoa-core-next` Git common-directory `info/exclude` | Candidate narrow local remediation for worktree/registry ignores; separate from tracked product changes and only after backup/status inspection. |

Skill audit paths: `/Users/cocoa/.claude/skills/skill-improver/SKILL.md`, its bundled `references/skill-style-guide.md`, and the upstream `SKILL.md` files under `/tmp/harness-skills-research/upstream/`. No existing skill was edited.

### Approaches

1. **Suppress findings and clean everything** — prune worktrees, delete caches, hide dirt, or bulk-install upstream skills.
   - Pros: Superficially smaller warning count.
   - Cons: Risks concurrent work, destroys useful evidence, retains the verifier defect, and imports licensing/policy conflicts.
   - Effort: Low initially; unacceptable recovery and correctness risk.

2. **Harden evidence at existing seams** — regression-test checkout classification, report ownership honestly, and add one original client-neutral evidence skill.
   - Pros: Small reviewable changes; preserves Strict TDD, runtime parity, and one review lane; does not depend on screen recording or external accounts.
   - Cons: Legitimate external warnings remain; installed-state checks still need a controlled deployment after source tests.
   - Effort: Medium; deliver as autonomous test-plus-code/documentation slices.

3. **Vendor a full visual-testing/review stack** — import recorder, screenshot uploader, and Greptile loops.
   - Pros: Richer optional UI artifacts.
   - Cons: New dependencies, disclosure risk, license uncertainty, review-lane conflict, and substantial authored review volume.
   - Effort: High; defer to an explicit separately scoped change.

### Recommendation

Choose approach 2, with a clear distinction between harness fixes and owner-controlled machine sanitation.

1. Write failing isolated tests before production edits. A leftover directory without `.git` must not be treated as an active checkout; a valid checkout missing required instructions must still fail. Preserve all leftover files and registration during verification. Test app/core classification consistently and include checkout paths containing spaces.
2. Include untracked source in pending-work evidence while excluding only known generated registry files. Do not equate an unavailable Git/status operation with a clean checkout. Describe remote coverage as locally observed refs; do not fetch inside the verifier.
3. For panel ignores, prefer a backed-up, idempotent local `info/exclude` update resolved through the Git common directory rather than a tracked commit on its stale `main`. This protects this machine without touching product code. A later owner-reviewed `.gitignore` PR to `dev` is the durable team-wide alternative. Never commit, push, prune, reset, or delete other sessions' work merely to improve the count.
4. Add an original compact evidence contract: exact tested revision plus dirty-state qualification, explicit command and exit status, before/after only where meaningful, local artifact paths, PASS/FAIL/BLOCKED/UNTESTED distinctions, and reproducible limitations. It supplements existing Strict TDD and SDD verification, not another review lane. Never imply a screenshot proves behavior not exercised, or a green fixture proves deployed runtime health.
5. Install the shared evidence skill in both clients using the existing backup/copy pattern and full supporting-file parity tests. Do not overwrite global instruction files with upstream `AGENTS.md`, change cmux launchers or Astra model selection, force architecture rewrites, or activate another Engram provider.

Upstream research is pinned to `513f8a24aae6383b00356fa285144b1bc3730dc1`. Local inspection shows `new-feature` mandates `origin/main`, conflicting with this harness's dev-first flow; `code-structure` is narrower than the user's architecture conventions; `unslop` overlaps existing documentation skills. The coordinator's independent research additionally reports absent licensing for custom evidence/code-structure/new-feature material, restrictive screenshot-tool licensing with public-upload behavior, and review loops incompatible with the one-lane policy. Do not vendor those files or recorder code. Capture concept-level lessons in an original local contract; the coordinator owns the detailed cited research report.

### Risks

- Eliminating every warning would be dishonest while active sibling work and disk usage remain. Completion must distinguish corrected defects, safely remediated local configuration, and unresolved owner actions.
- Residual directories may contain recoverable files even without `.git`; neither verification nor bootstrap should delete them.
- Whole-screen capture or automatic uploads could disclose unrelated work, credentials, or private customer data. Default to local textual evidence; require explicit scope for capture/publication.
- A bare `HEAD` is insufficient when the tested tree is dirty. Evidence must not overstate snapshot identity or mutate the existing transactional SDD receipt contract.
- Shared helper extraction can introduce deployment dependencies; ensure source tests and installed script paths remain self-contained or copied together.
- Run isolated regression tests first, then full `./verify.sh` after controlled installation. Record existing environmental failures independently of RED/GREEN feature evidence.
- New shared skill metadata must meet the local quoted-description/author/version/license contract; only declare a license the local author can legitimately grant.
- Preserve `integrate-codex-sdd-executor` and the prior Astra fix. Use the agreed feature-branch chain rather than mixing unrelated work into one oversized PR.

### Ready for Proposal

Yes. Define acceptance around corrected classification, truthful nonmutating audit output, safe local ignore protection, and original shared evidence guidance. Keep cache deletion, sibling commits/pushes, full recorder integration, external uploads, architecture migration, and review-loop adoption out of scope. Report residual external warnings explicitly instead of promising a clean machine.
