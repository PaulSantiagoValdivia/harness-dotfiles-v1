# Scenario evidence and final-run handoff

Eight requirements / fourteen scenarios. Fixture receipts are scoped to their
recorded snapshots, not blanket claims about current installed or live behavior.
Local evidence root: `/tmp/triangulation-safety-evidence/`. Dedicated verifier
must run final `./verify.sh` once after deployment parity, inspect complete output,
and bind the final revision/dirty snapshot to its verify-report.

| # | Normative scenario | Proof / current limitation |
| --- | --- | --- |
| 1 | Valid shared authority | `authority-receipt.json`; exact/alias three-role fixtures |
| 2 | Unresolved authority | Same; missing/conflicting/invalid mappings BLOCKED |
| 3 | Fresh and customized installations | Same; scoped parity/backups/rerun/restore fixtures |
| 4 | Nested checkout invocation | `registry-receipt.json`; main/linked/alias roots; installed probes separate |
| 5 | HOME and unresolved location | Same; exact HOME only, nonrepo/Git failures skip without writes |
| 6 | Scoped persistent installation | Same; complete config preservation/refusal and bootstrap wiring |
| 7 | Verified ownership | `launch-receipt.json`; real fresh worktrees, mocked authorized transport only |
| 8 | Denied or uncertain launch | Same; denied transport/existing targets/unknown reservations/force/resume refusal |
| 9 | Stop preserves all work | `stop-receipt.json`; byte snapshots, ignored/dirty/unpublished/error cases |
| 10 | Complete execution | `verification-receipt.json`; exact role commands through injected runners, not product gates |
| 11 | Skipped or unsuccessful check | Same; SKIPPED/FAIL/BLOCKED/TIMEOUT/unknown cannot publish |
| 12 | Revision race or partial promotion | Same; tested SHA binding, temporary remotes, rejection leaves group open |
| 13 | Authorized smoke | UNTESTED: prerequisite BLOCKED by external cmux policy; no live ACK/reassignment/latency evidence |
| 14 | Missing live prerequisites | Observed socket denial; explicit BLOCKED/UNTESTED, no fabricated live PASS |

Final verifier: reconcile hashes/current source and scoped installed parity;
execute wired fixtures and the full harness; record warnings/external ownership
without cleanup. Scenario 13 remains unproven until separately authorized live
smoke succeeds. Source completion is not full live certification or permission
to silently archive this unresolved requirement.
