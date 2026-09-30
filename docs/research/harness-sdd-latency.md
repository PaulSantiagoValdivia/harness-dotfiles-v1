# Feature / SDD latency: measured boundaries

Measured 2026-09-09 on this machine. Do not attribute total task time to OpenSpec or Astra without a model-only benchmark. Keep Astra and safety controls; remove deterministic failures before reducing review quality.

| Finding | Evidence | Effect / boundary |
|---|---|---|
| Invalid Codex argument placement | Installed Codex 0.153.4: `codex exec --ask-for-approval never --help` exits 2; `codex --ask-for-approval never exec --sandbox danger-full-access --help` exits 0 | Both managed and installed codex-build SDD and dual-review prompts contain the invalid placement. These paths can fail before generation; direct native Codex SDD does not necessarily invoke them. |
| Unsafe retry instruction | codex-build ordinary Execute prompt says to forcibly remove an existing worktree | A repeated task identifier can destroy recovery work rather than resume. Existing SDD mode already rejects collisions. |
| Review interface mismatch | Legacy `review validate --gate archive` reported authority_corrupted; help does NOT support archive. Negotiated integration/v2 + post-apply allows the same approved lineage | Correct the caller, not the review store. This is not evidence of actual corrupted state. |
| Persisted failed verification requires remediation | sdd-status reports an authority-only failed evidence revision and recommends remediate after review approval | Stop after a bounded diagnosis; restarting review/testing blindly risks a control-flow loop. |
| Status cost | Three sequential `gentle-ai sdd-status harness-evidence-hardening` calls: 1.316 / 1.286 / 1.340 seconds, exit 0; median 1.316s | Measures entire local command, not YAML parsing alone. It does not explain a multi-minute feature by itself. |
| Real-time watchdog fixtures | Four fixtures intentionally wait approximately 30 + 60 + 30 + 25 seconds, plus polling/grace | Full verification includes deliberate wall time; use focused tests while editing and retain full final verification. Do not shorten production watchdogs to accelerate tests. |
| Review workload | Default native RDD selected four lenses for the aggregate 27-file / 1428-line shell/process change; dual-review additionally includes cross-check and skeptic stages when selected | Selection cost is real; keep exactly one final review lane. Four lenses are not evidence of four independent reviewers in this run. |
| Outer timeout versus inner watchdog | route-code-to-codex warns Bash can stop at 600s; codex-run defaults idle180s / absolute2700s | Long foreground work can be killed by the caller before the wrapper's final receipt. Use background execution for long work, inspect Git before retrying. No automatic retries found in the inspected wrapper. |

## Interpretation

There are confirmed workflow defects and avoidable orchestration costs. We have NOT measured that Astra is slower than Sol, that cmux is currently hanging, or that all feature launches suffer these paths. Historical timings in code comments are not new benchmarks.

Next representative feature should record monotonic timestamps for launch, first model output, each phase, implementation, focused tests, full tests and final review; attach model/reasoning, invocation path, exit code, retry count and Git identity. Compare equivalent changes before claiming an end-to-end speedup. Never persist prompts, credentials or full transcripts merely to measure timing.

## Bounded corrections

Corrected both approval-option call sites and replaced forced worktree removal with STOP/preserve instructions. Regression test failed before correction and passes afterward; real CLI parsing uses `--help` only. The existing SDD workflow fixtures pass 20/20. This is a prompt-contract safety improvement, not a transactional worktree lock or an end-to-end LLM execution proof.

Rollback boundary: the two workflow files, their new focused regression test and one verify.sh entry; documentation is independent. Installed files are backed up before replacement; preserve later edits before restoring. No new routing through legacy Conductor was introduced. Native direct Codex remains the supported SDD route.

One fresh bounded review found a minor reporting gap: missing Codex could silently skip the CLI probe. The test now explicitly reports SKIP; both installed-Codex and mocked-absent paths were checked. The installed wrapper also accepts the corrected command with `--help` (exit 0). No provider request or destructive worktree operation was needed to test these boundaries.

Final post-correction `./verify.sh`: **680 PASS / 16 WARN / 0 FAIL**, exit 0. Log retained locally at `/tmp/harness-hardening-evidence/post-workflow-verify.log`, SHA-256 `7581618961451ea9545beb7b1e5a7088fdb2943ab1c3056e4ec72234e3d6b6d0`. Sixteen warnings remain owner/recovery actions, not permission for cleanup. This runtime result does not overwrite the earlier formal SDD failed-envelope/remediation state.

## Final triangulation measurement

At clean `424433e`, the single final `./verify.sh` completed in **1273.678s
(21m13.678s)** with **685 PASS / 13 WARN / 0 FAIL**, exit 0. The retained
`/tmp/triangulation-safety-evidence/final-runtime.json` records monotonic duration;
`final-verify.log` SHA-256 is `df933b1d405b64f49d04039d88ba3ad794a278d4d90b0df4b555d860e556d603`.
A separate focused DevTools run took 219.968s for 18 temporary-Git tests. These
are different executions, not a stage breakdown or a comparable speedup test.
The runner kept advancing, including deliberate watchdog fixtures; no complete
per-stage attribution was collected. Use focused tests during edits and reserve
one full suite for final verification. Formal SDD remains FAIL for missing live
smoke and generic shell-probe assertion quality, not a demonstrated gate failure.
