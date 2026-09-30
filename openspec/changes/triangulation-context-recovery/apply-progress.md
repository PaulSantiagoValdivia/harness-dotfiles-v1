# Apply Progress: Triangulation Context Recovery

## Warning slice — tasks 2.1–2.3
Strict TDD; OpenSpec/auto/auto-chain/feature-branch-chain. Branch `fix/triangulation-context-warnings`, parent `fix/triangulation-context-recovery`, base `4831854`; dirty source candidate, not yet committed or installed. Planning task 1.1 was already complete.

### TDD Cycle Evidence
| Task | Safety net | RED (written first) | GREEN | TRIANGULATE / REFACTOR |
|---|---|---|---|---|
| 2.1 | Existing suite 66 PASS | Added compact/path/guidance fixtures; 71 PASS / 11 FAIL | 82 PASS / 0 FAIL | Added second compact/non-object/resume cases; 84 PASS / 1 FAIL, then 85 PASS / 0 FAIL |
| 2.2 | Same baseline | Actual event retains cache; next Stop revives precompact usage | Real writer/reader lifecycle passes | Non-object rows ignored; native boundary resets measurement. Event detection adds no normal Stop subprocess |
| 2.3 | Same baseline | Guidance/config assertions written before managed source edits | Matched shared Claude/Codex blocks and warning text pass | Three warning levels tested; final suite remains 85 PASS / 0 FAIL |

### Work Unit Evidence
| Evidence | Result |
|---|---|
| Focused command | `bash tests/context_budget_test.sh`: final exit 0, 85 PASS / 0 FAIL |
| Runtime harness | Real source writer/reader, isolated HOME/cache/transcripts, compact/resume events and subsequent Stop: PASS; installed/native session UNTESTED |
| Syntax / whitespace | `bash -n files/claude/hooks/context-budget{,-measure}.sh tests/context_budget_test.sh` and `git diff --check`: exit 0 |
| Local retained evidence | `/tmp/triangulation-context-recovery-evidence/warnings-report.json`; baseline/RED/GREEN/triangulation/final logs, candidate diff and SHA-256 identities |
| Rollback | Revert warning measure/reader comments, compact settings entry, shared/runtime mirrored client guidance and matching tests together; no installed paths changed |

Actual 200k/300k/400k thresholds, critical quiet protection and zero-fork reader behavior are retained. No numerical tuning, automatic reset, new Stop loop, ownership gate or unrelated slow-hook changes. The source suite was already registered in `verify.sh`.

Remaining: checkpoint and scoped wiring/installation tasks 3–4; final verification/review, deployment and delivery. No complete/live-recovery claim. Root handles commit/push and next slice.

## Checkpoint slice — tasks 3.1–3.3
Strict TDD; same cached delivery choices. Branch `fix/triangulation-recovery-checkpoint`, parent `fix/triangulation-context-warnings`, base `8799389`; dirty source candidate, not yet committed/installed. Warning progress above is preserved; tasks 2 are complete.

### TDD Cycle Evidence
| Task | Safety net | RED (written first) | GREEN | TRIANGULATE / REFACTOR |
|---|---|---|---|---|
| 3.1 | Existing handoff and disposable install groups PASS | Bounds/schema/identity/path/hash cases written before parser | First GREEN: 3 groups PASS, exit 0 | Exact 8192/8193, nested/deep JSON, oversized artifact and FIFO tests added; final 3 groups PASS |
| 3.2 | Same baseline | Missing `mode: auto` fails, exit 1; conflict/process/pending cases written | First GREEN: mode/legacy/conflict and pending data PASS | Empty running handle fails, exit 1; restored strategy and truncation cases then PASS |
| 3.3 | Same baseline | All parser fixtures above precede implementation | Strict parser and documented checkpoint contract PASS | Preserve safety notice/pointer under truncation, reject malformed quoted mode; final 3 groups PASS |

### Work Unit Evidence
| Evidence | Result |
|---|---|
| Focused command | `bash tests/triangulate_handoff_test.sh`: exit 0, checkpoint + legacy authority + scoped install groups PASS |
| Runtime harness | Real Git worktrees and disposable install/restore: PASS. Valid checkpoint hook observed **1.876s** excluding setup; one local sample, not a latency guarantee. No per-turn hook/process added; native channel not certified |
| Syntax / whitespace | `bash -n files/claude/hooks/triangulate-handoff.sh tests/triangulate_handoff_test.sh`; `git diff --check`: exit 0 |
| Retained evidence | `/tmp/triangulation-context-recovery-evidence/checkpoint-report.json`; baseline/RED/GREEN/triangulation/final logs, tested diff and source hashes |
| Rollback | Revert handoff checkpoint/mode parser, protocol recovery section and associated fixtures together; no installed files changed |

Added no live authorization, gate, background producer or transport. Strings/lists/maps and artifact reads are bounded; hostile/stale data yields recovery-unavailable, not another plan. Registry refresh unnecessary: only an existing skill reference changed, not its metadata/path.
Remaining: tasks 4 and scoped deployment, full verification/review and delivery. Root handles commit/push. No final completion or native recovery claim.

## Wiring/install slice — tasks 4.1–4.3
Strict TDD; branch `fix/triangulation-recovery-install`, parent checkpoint branch, base `4aaae20`; dirty source candidate. Prior progress retained. No installed HOME/product writes or commits by executor.

### TDD Cycle Evidence
| Task | Safety net | RED | GREEN / TRIANGULATE / REFACTOR |
|---|---|---|---|
| 4.1 | New installer; existing warning/handoff baseline PASS | Missing helper fails before implementation | Fresh/custom/rerun/rollback, collision/symlink/FIFO/ambiguous overlay/concurrent-plan fixtures PASS; legacy override migration also PASS |
| 4.2 | Existing focused baselines PASS | Installer expectations precede helper/wiring | Scoped wrapper + targeted compact prompt + event parity PASS; shared tree staged via existing helper, managed blocks only |
| 4.3 | Baseline 85 warning cases + handoff groups PASS | Registry-first integration regression fails; review P2 ancestor symlink deletion fails (85 PASS / 1 FAIL) | Registry-first restored; compact-only ancestor checks: 86 PASS / 0 FAIL. Ordinary reader still zero-fork. Final four-suite aggregate PASS; installer rerun after docs/bytecode cleanup PASS |

### Work Unit Evidence
| Evidence | Result |
|---|---|
| Focused/runtime commands | `bash tests/context_budget_test.sh` (86 PASS), `bash tests/triangulation_recovery_install_test.sh`, `bash tests/triangulate_handoff_test.sh` (3 groups), `bash tests/skill_registry_root_test.sh`: all exit 0; real scripts/Git and disposable homes, not native coordination |
| Syntax / whitespace | Bash syntax, installer AST parse, `git diff --check`: exit 0 |
| Evidence | `/tmp/triangulation-context-recovery-evidence/install-report.json`; missing-helper, registry and ancestor-escape RED logs; final aggregate and refactor logs |
| Rollback | Revert this slice's helper/fixtures/wiring/prompt/comment/protocol/registration changes together. Installed rollback uses immutable manifest/originals and refuses drift; source tests prove disposable lifecycle |

Installer commands: `python3 files/shared/lib/install-triangulation-recovery.py install "$HOME" "$BACKUP"`, then identical command is a no-op; rollback substitutes `rollback` for `install`. BACKUP must be a fresh path. Preflight refuses unknown overlays, symlinked targets and concurrent changes. Files replace atomically; skill-tree rename pair can briefly leave an absent path, so partial failure retains backup for inspection rather than claiming a whole-home transaction. Fresh scoped homes gain recovery hooks, not full client bootstrap.

Corrected misleading comments: moving measurement outside UserPromptSubmit does not make synchronous Stop nonblocking. No async toggles or unrelated product-hook changes. All implementation tasks 2–4 complete; global deployment 5.2, full verification, review and delivery remain coordinator gates. No native certification claim.

## Scoped deployment and independent review
- Source candidate: `c0d95734afb10f0e84fd2a3178fc7b0bfac79219`; normal fresh source review PASS, P2 ancestor-symlink finding corrected and independently reproduced as preserved. This is not native review authority.
- Scoped actual-HOME installer exit 0; hooks, compact prompt and both full skill trees match source. Unrelated Claude preferences, Codex configuration/hooks and mappings retain hashes.
- Immutable backup: `~/.claude/backups/triangulation-recovery-20260909T184145-cd49c10b`; guarded rollback supported, not executed against the active HOME.
- Installed warning hooks with disposable HOME: 86 PASS / 0 FAIL. Registry refreshed at owning worktree root, 12 skills.
- Installed read-only front handoff: exit 2 in 1.574s, BLOCKED because exact `reconocimientos-unificacion` authority and alias are absent. Motor and campaign plans coexist; no alias was guessed or changed. Both inspected plan states record interactive execution; this install does not override those decisions.
- Native cmux inbox access remains denied to this external process. No active session restarts, messages, ownership changes, product writes or live-readiness claims.
- Evidence: `/tmp/triangulation-context-recovery-evidence/actual-install.json`, `installed-warning-probe.log`, `installed-live-readonly-handoff.json`; process measurements `/tmp/cmux-recovery-audit/report.json`.
- Separate reproduced front Stop defect: unchanged closures repeat sweep/audit/lint, and deletion/config edits miss the timestamp build cache. Product fix remains pending its live owner; not part of this installed source change.
