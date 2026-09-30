```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:a7856f0f30620162eed3c54d2ab9706826eea1882fddfc0aad38a6b5c3274492
verdict: fail
blockers: 1
critical_findings: 0
requirements: 8/8
scenarios: 11/11
test_command: ./verify.sh
test_exit_code: 0
test_output_hash: sha256:493afd8d26371806b27c21dff8c93ebfe73caf293808dcbedd1f08132dba9109
build_command: bash -n bootstrap.sh verify.sh files/claude/statusline.sh && bash -n files/shared/lib/worktree-health.sh files/shared/lib/install-shared-skill.sh tests/worktree_health_test.sh tests/harness_evidence_test.sh tests/standalone_runtime_parity_test.sh && node --check files/claude/workflows/codex-build.js && node --check files/claude/workflows/dual-review.js && PYTHONPYCACHEPREFIX=/tmp/harness-hardening-evidence/pycache python3 -m py_compile files/shared/bin/harness-local-protect tests/local_protection_test.py
build_exit_code: 0
build_output_hash: sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
```

## Verification Report

**Change**: harness-evidence-hardening. **Mode**: Strict TDD, full spec-driven artifacts.
**Runtime judgment**: PASS WITH WARNINGS. **Native completion judgment**: blocked; not archive-ready.

### Identity and evidence boundary

Executed on 2026-09-09 in `/Users/cocoa/harness-dotfiles`, branch `docs/harness-hardening-verification`, HEAD `6f33ef45766dca83433a2ac1f536c76e1590f87b` (implementation `75e2703`). Git status was empty before and after execution, before this report was written. Installed state and external repositories are separate, time-varying targets; clean harness HEAD does not identify their complete contents.

Exact local logs, retained RED/GREEN receipts and evidence index are under `/tmp/harness-hardening-evidence/`. `verification-evidence-index.json` is the retained preimage of `evidence_revision`; its hashes identify inspected bytes, not their truth. Candidate report bytes remain in `verify-report.candidate.md`. No recording, upload, product edit, cleanup, commit or push was performed by this verifier.

### Completeness

| Metric | Result |
|---|---|
| Authoritative requirements/scenarios | 8 / 11, independently recounted |
| Implementation tasks | 14 complete / 14 total; zero unchecked |
| Baseline finding ledger | F1–F7 and W1–W17 individually present with ownership/actions |
| Missing artifact dimensions | None |

### Build & Tests Execution

| Command / target | Exit | Observed result / retained output |
|---|---:|---|
| `./verify.sh` | 0 | **679 PASS / 16 WARN / 0 FAIL**, `final-verify.log` |
| Envelope build command | 0 | No syntax/compiler output, `final-build.log` |
| `bash tests/worktree_health_test.sh && python3 tests/local_protection_test.py && bash tests/harness_evidence_test.sh && bash tests/standalone_runtime_parity_test.sh` | 0 | 2 health groups, 9 Python tests, 3 evidence groups, live parity group; `final-focused.log` |
| `shellcheck -x files/shared/lib/worktree-health.sh files/shared/lib/install-shared-skill.sh tests/worktree_health_test.sh tests/harness_evidence_test.sh` | 0 | No new-shell findings, `final-lint.log` |
| `python3 -` (inline document/ledger/live-receipt assertions) | 0 | 8/11/14/24 counts; actual panel exclusions/HEAD/index; template privacy/uncertainty contracts, `final-contract.log` |

Additional SHA-256: focused `c395d54d343b5f1863877f93fd76e0b37781ed0592816a45128aec7e365ca352`; document/live contract `8746c279ad91b46154df73ac80a986c06c70ca14f184389d155626a1302ce746`. Empty lint output has the same SHA-256 as empty build output.

### Spec Compliance Matrix

Document-contract scenarios concern authored guidance/template behavior, not an automated recorder. Their runtime assertions parse the actual shipped files; they do not prove future operators follow instructions.

| Requirement | Scenario | Passing runtime evidence | Result |
|---|---|---|---|
| Checkout identity | Residual or misplaced checkout | `worktree_health_test.sh`: absent/residual/malformed, main/linked, spaces, physical aliases, relative root and ancestor selector | COMPLIANT |
| Checkout identity | Genuine instruction defect | Same suite invokes actual core/app validator definitions; live root lacks instructions and emits FAIL, residual does not | COMPLIANT |
| Honest ownership evidence | Dirty or unreadable checkout | Same suite: exact `2 2 2` counts, rename/newline, generated-only, user `.atl`, injected status error; full live audit | COMPLIANT |
| Honest ownership evidence | Local remote coverage | Same suite: local ref absent/present/error, no fetch; live output explicitly qualifies local refs | COMPLIANT |
| Nonmutation and local protection | Shared checkout repair | Nine `local_protection_test.py` tests: main/linked prepare/apply twice/rollback, index/HEAD/source preservation, concurrent additions, drift and nonregular refusal | COMPLIANT |
| Finding dispositions | External ownership remains | Runtime ledger assertions find all 24 rows; full verifier retains all 16 unresolved warnings, removes only resolved W10 | COMPLIANT |
| Identified observations | Dirty runtime observation | `harness_evidence_test.sh` plus document-contract execution: actual-target and dirty-HEAD limitations present, unknown identity never asserted | COMPLIANT |
| Honest outcomes and comparisons | Missing prior evidence | Same suite parses UNTESTED/null defaults with unavailable reasons; real output hashes independently calculated | COMPLIANT |
| Local privacy boundary | Optional visual proof | Document-contract execution asserts textual fallback, no automatic screen/upload, no bypass, no report-command evaluation and retained SDD authority | COMPLIANT |
| Installation and regression guarantees | Fresh installation and rerun | Evidence suite runs actual installer/bootstrap/parity stanzas in fresh/customized homes; backups, collision, rerun, restore, extra/supporting-file drift | COMPLIANT |
| Installation and regression guarantees | Verification boundaries | Retained RED/GREEN, fresh full suite and installed parity; this report separates source, installed and external observations | COMPLIANT |

**Compliance summary**: 11/11 scenarios and 8/8 requirements have passing bounded evidence.

### Correctness and design coherence

| Area | Finding |
|---|---|
| Identity/ownership | Own Git metadata and canonical root required; checked errors, NUL status parsing and optional-lock suppression preserve honest diagnostics. |
| Local protection | Immutable receipt, explicit operation, shared Git exclude resolution and closed rollback protect concurrent work within documented coordination assumptions. |
| Evidence contract | Original local-only skill/template, shared client source, no recorder or competing receipt authority. |
| Installation | Only managed skill directories touched by scoped deployment; backup/collision and full-tree parity tested. Global preference hashes still match coordinator preimage. |
| Design adjustment | Added source-only `harness-local-protect` and `install-shared-skill.sh` beyond original path table; bounded helpers make safety/idempotence testable and avoid global bootstrap. No spec conflict. |
| Protected behavior | Full acceptance/installed parity retain Astra/cmux/routing, Strict TDD and existing SDD overlays. No claim of new manual multi-agent or visual smoke coverage. |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD cycle evidence reported | PASS | Present in apply-progress; all nine implementation/refactor rows inspected. |
| Tests exist | PASS | All referenced health/protection/evidence/parity files exist. |
| RED confirmed | PASS | Retained exit-1 logs cover missing helpers/skill, ancestor selector, wiring, unsafe rollback/permissions and guidance. |
| GREEN confirmed | PASS | Fresh focused execution passes all referenced suites. |
| Triangulation | PASS | Seven current root cases plus clean/dirty/error states; nine protection tests; fresh/customized installation and drift/rollback. Historical identity logs recorded eight cases before consolidation. |
| Safety net | PASS | Retained baseline parity/syntax and health receipts precede respective modified seams; new helper paths verified new against planning base. |

**TDD compliance**: 6/6 checks supported; receipts use explicit filenames/exits rather than the skill template's decorative checkmark labels. Historical logs are retained local evidence, not independently timestamp-attested executions. Documentation/deployment task coverage is consolidated into the corresponding nine rows, not nine total project tasks.

### Test Layer Distribution and Assertion Quality

| Layer | Executed units | Files |
|---|---|---:|
| Isolated integration/contract | 9 named Python tests + 5 shell groups (with multiple assertions/cases) | 3 |
| Installed acceptance | 1 aggregate shell group | 1 |
| Unit / browser E2E | No separate suites added | 0 |

Full `verify.sh` provides 679 top-level PASS checks; counts are not inferred inner-framework test totals. Bash/Git/Python integration follows configured capabilities. All four changed test files inspected: actual Git/installer operations, meaningful value/error assertions, fixed nonempty client loops, and production-document contracts; no tautologies or vacuous loops found. Metadata/wording assertions are structural evidence only, not behavioral proof of future evidence collection.

Coverage analysis skipped: no configured coverage tool. No type checker configured. Changed new shell files pass ShellCheck; existing verifier baseline SC2015/SC2088/SC2295 is documented and not silently represented as a clean full-project lint run.

### Baseline dispositions and retained warnings

F1–F6 no longer generate missing-instruction checks for residual directories; each residual receives one actionable warning. F7 and W10 are resolved by local common-directory excludes. Live exclude SHA-256 matches the immutable receipt: `9877594d5dae30c534ecb099482f1150281ca23ddb655d7e98f0bb56553eee83`; panel HEAD remains `b3ba1be`, tracked/index diffs empty.

All other sixteen warnings remain: W1 staging age, W2 Codex storage, W3–W5/W15 stale recovery sources, W6–W8/W12–W14/W16–W17 owner work, W9/W11 local-ref publication uncertainty. Newly visible untracked work includes backend recognition 35 paths, panel recognition 1, and app QA 3; this is not permission to remove them. Owners/actions remain in `docs/research/harness-health-dispositions.md`. Lower PASS count than baseline reflects skipping invalid-checkout checks, not suppressed legitimate failures.

### Issues Found

**CRITICAL**: None in implementation/runtime evidence.

**BLOCKER (updated after bounded follow-up)**: Review authority is now approved and explicitly bound, but native SDD still requires compact remediation for the existing failed evidence revision `sha256:a7856f0f30620162eed3c54d2ab9706826eea1882fddfc0aad38a6b5c3274492`. The documented dispatcher requires a charged attempt and atomic finish with expected binding, approved successor lineage and remediated evidence revision. The special authority-only preflight recovery shape requires commands that were never executed (exit 125); these commands actually succeeded, so that shape cannot truthfully replace this report. No contract permitting a bare PASS replacement or reuse-only completion was established in this bounded follow-up. No new review, runtime attempt, gate disable or test repetition was performed.

**WARNING**: Sixteen external-owner/cache warnings remain; historical manual acceptance items were not performed. Remaining failed-evidence remediation belongs to the coordinator; this verifier starts no additional review lane.

**SUGGESTION**: None beyond recorded owner actions.

### Verdict

**FAIL for native completion admission; runtime PASS WITH WARNINGS.** All scoped requirements have bounded passing evidence, but this report does not assert native closure or archive readiness while the persisted failed-evidence remediation gate remains unresolved. Preserve the exact evidence bytes; do not rerun expensive suites merely to replace successful output without a changed source or justified invalidation.

### Bounded authority follow-up

Source HEAD remains `6f33ef45766dca83433a2ac1f536c76e1590f87b`, with no tracked diff. Existing test/build logs and hashes are unchanged, retained as observations rather than relabelled as new execution.

- `gentle-ai review validate --contract gentle-ai.review-integration/v2 --gate post-apply --cwd "$PWD"` exited 0 / ALLOW for exact candidate `8574942c77944948adb40775cb1102078b30dc5b`. Authority revision: `sha256:7e10da84a5505fc7e38f8693b6c771f97e94c77210938711809668ceb41f345c`.
- `gentle-ai review bind-sdd --contract gentle-ai.review-integration/v2 --cwd "$PWD" --change harness-evidence-hardening --lineage review-80f6e2ac74d42816 --expected-binding-revision ''` exited 0. Native binding revision: `sha256:c944324394448dc688f5682b2e2644bdd3ec9287b3fd74ac03b0c59a329c1bc7`; receipt hash `sha256:0f5a5376efee54c4d6febc8e24cc8064a1d3e979cac65fe711b35b5fc7111bb1`.
- Subsequent `gentle-ai sdd-status harness-evidence-hardening` exited 0 but reported `next: remediate`, verify/archive blocked; `sdd-attempt status` confirms zero attempts and binding above. Exact receipts: `followup-bind-sdd.json`, `followup-sdd-status.txt`, `followup-attempt-status.json` under the retained evidence directory.
- Negotiated capabilities enumerate only post-apply, pre-commit, pre-push, pre-pr and release gates. An unsupported `archive` gate is not evidence of corrupt authority. No legacy repair is justified by that command.
