# Skills assessment for the Cocoa harness

Adopt stronger evidence and workspace-ownership contracts, not this repository wholesale. Keep the existing SDD, Strict TDD, review selection, cmux launchers and Astra coding route. Introduce a small, independently authored evidence workflow shared by Claude and Codex. Do not install recording or public-upload tools by default.

## Scope and source identity

This assessment covers all seven skill directories, the workflow template, upload scripts, recorder lifecycle and supplied test inventory in `michaelshimeles/skills`. The reviewed checkout is commit `513f8a24aae6383b00356fa285144b1bc3730dc1`, dated 2026-09-03. Retrieval was on 2026-09-09. Findings below are static analysis unless explicitly identified as local runtime observations. Upstream scripts were not executed, installed, or granted access to accounts. Sources use immutable commit links where possible.[1]

The local comparison covers `bootstrap.sh`, `verify.sh`, shared skill overlays, Claude routing hooks, OpenSpec testing configuration and the installed harness. A separate real smoke test already established that the installed `codex-run` selects `gpt-6-astra` and returns successfully. That test does not prove arbitrary coding tasks correct.

## Decision matrix

| Component | Useful contribution | Decision | Main constraint |
|---|---|---|---|
| `evidence-driven-testing` | Explicit assertions, environment and revision identity, failed/untested outcomes, before/after proof | Implement a compact original local evidence contract | Custom recorder has no explicit license found; broad screen capture and external dependencies are unnecessary defaults |
| `before-and-after` | Comparable visual states and reusable PR evidence | Support local pairs in the evidence contract; defer upstream tooling | Restricted license, default public upload, automatic installation, stale helper invocation |
| `new-feature` | Worktree ownership, shared-port/database awareness, overlap checks | Incorporate missing ownership checks into existing workflow | Hardcoded `origin/main`, forced fresh worktrees and branch deletion conflict with this harness |
| `code-structure` | Explicit I/O, incremental extraction of repeated operations | Retain as scoped design guidance, not a mandatory architecture | Existing clean/hexagonal architecture rules must remain authoritative |
| `greploop` | Bounded review attempts and attention to review freshness | Preserve one existing review lane; no new automatic dependency | Score chasing and ten fix cycles add cost and conflict with the existing review budget |
| `greploop-apps` | Documents a fallback for a particular hosted reviewer | Do not adopt | Large-PR workaround undermines review slicing; timestamp freshness is not commit identity |
| `unslop` | Plain words, specific claims, minimal filler | Keep existing documentation/comment skills | Always-on editing adds context and can remove necessary uncertainty or impose an unwanted voice |
| Root `AGENTS.md` | Connects isolation, implementation, evidence and delivery | Do not copy | Replaces established branch flow, orchestration, review and writing contracts |

These are integration judgments, not claims that every upstream skill is unsuitable for every project. The upstream collection explicitly combines these components into a workflow, whereas this harness already has a structured lifecycle.[1][2]

## Licensing and provenance

The inspected root has no license file, and GitHub's repository metadata reports `license: null`. The custom `new-feature`, `code-structure` and `evidence-driven-testing` directories do not supply their own license. Folder-specific licenses exist for `before-and-after`, `greploop`, `greploop-apps` and `unslop`. A license in one folder is not treated as permission for unrelated folders.[3]

The engineering decision is conservative: do not redistribute unlicensed custom scripts or prose. Record source links and write requirements and implementation independently. GitHub's licensing guidance distinguishes visibility/forking from general permission to reproduce and distribute. This assessment is not a legal opinion; obtain permission or qualified review before vendoring uncertain material.[4]

`greploop` and `unslop` include MIT notices naming Greptile AI and Lauren Tan respectively. Their provenance must be retained if their text is ever copied. `before-and-after` includes a license labelled PolyForm Shield with a competing-product/service restriction; do not silently classify it as MIT or permissive. The current integration does not need to take on that restriction.[5][6][7]

## Evidence: the strongest opportunity

The useful requirement is a reproducible link between a claim and an observation. The harness already mandates tests and runtime receipts, but scattered prose and transient terminal output are harder to compare and recover than a small structured report. A local evidence workflow can require the exact repository and revision, dirty-state disclosure, command or interaction, expected result, observed result, exit status, and retained artifact path.

Three evidence types should remain distinct. A unit/integration test proves the behavior within its test boundary. A runtime probe proves a particular deployed or installed path. A screenshot or recording can demonstrate a visible state but does not replace assertions or tests. None alone proves that the entire system works perfectly.

For regressions, record the old failure before applying the fix when feasible, then the new result under comparable conditions. If the old state cannot safely be recreated, label that evidence unavailable and explain why. Never reconstruct a failure or reuse synthetic footage as though it were a live application test. Failed and untested checks must remain visible rather than being omitted.[8]

### Proposed local evidence contract

Use a gitignored artifact directory, not a public host. The report should identify:

- Repository, branch, commit and whether the checkout was dirty.
- Scope, test target and expected observation.
- Exact command or interaction, timestamp, observed outcome and exit code where meaningful.
- Before and after references, with missing prerequisites explicitly marked.
- Artifact paths and checksums for retained files.
- Limitations, sensitive-data handling and which checks were not performed.

A checksum ties a report to bytes, not to the truth of an assertion. A successful recorder exit proves media finalization, not application correctness. The agent must inspect the actual evidence before making a pass claim.

The same skill source should be installed for Claude and Codex, with one schema and no duplicated provider, global hook payload or automatic recorder. Existing SDD verification remains the authority for task completion. Evidence is an input to verification, not a second review lane.

## Recorder analysis and operational cost

The upstream recorder is a substantial optional tool: 1,344 source lines and an 823-line test file in the local checkout. It implements source detection, session state, locking, subprocess ownership and recovery. Its test inventory includes concurrent annotations, retryable finalization, PID identity mismatch, supervised startup failure, synthetic capture and platform-source selection. Tests were inspected, not run; cross-platform coverage declarations are not evidence of a successful capture on this Mac.[9][10]

There are thoughtful safety mechanisms. Linux uses a process-instance handle for signalling; other platforms use a supervisor owning the recorder child. Lost-recorder recovery refuses to finalize while the known process is alive. These are relevant design lessons for any future process tool, not reasons to import an entire recorder now.[9]

A macOS adoption would also need verified FFmpeg capabilities, capture permissions, crop selection, retention limits and proof that unrelated windows or customer data cannot be recorded. The source's `verified` result describes successful media processing. It cannot attest that every recorded assertion is correct. Prefer an existing approved browser capture tool or non-UI command receipts until there is a concrete visual-testing requirement.

## Screenshot and upload risks

The upload helper selects `0x0st` by default. Its Gist adapter explicitly creates public gists. A Markdown-output convenience operation can therefore publish screenshots. This is a poor default for a harness used with private repositories and authenticated customer applications. Local capture and publication must be separate actions, with explicit approval of destination and content before any upload.[11]

The capture helper uses shell command names such as `agent-browser:open`, while the current primary CLI documentation shows `agent-browser open`. The skill also says not to default to full-page capture, but its helper defaults to `MODE="full"`. These are concrete mismatches to resolve before adopting that path, not failures observed in a live execution.[12][13]

The adapters use `curl` without explicit total timeout or HTTP failure handling. The wrapper also interpolates the adapter name into a filesystem path without a narrow allowlist. Environment-controlled adapter selection should not become arbitrary script selection. Existing trusted tools plus a local report avoid introducing these unnecessary risks.[11]

Do not use browser sandbox bypasses or weaken deployment protection merely to obtain a screenshot. Record a blocked prerequisite instead. Do not copy a bypass token into a command, report, issue or public artifact.

## Worktrees and concurrency

The upstream worktree skill contains useful warnings about shared ports and databases. A worktree isolates files, not running services, test databases, external accounts or caches. Any runtime claim should identify which process and revision answered the probe.[14]

Its default `origin/main` base conflicts with this harness's `dev`-first policy wherever `origin/dev` exists. Its automatic dependency installation and cleanup instructions also need adaptation. Existing managed worktrees and legacy Conductor recovery sources must be preserved, not replaced because a new skill expects another layout. A branch must not be force-deleted merely because a PR appears merged; check reachability and ownership first.[14]

For the current health findings, distinguish three states: a valid checkout with a real defect, a stale worktree registration whose checkout metadata is gone, and another session's active dirty/unpushed work. Only the first is automatically a repair target. The second needs precise diagnosis and safe recovery, not six misleading missing-instruction errors. The third is work to protect, not clutter to remove.

## Review loops and writing

The Greptile skills are integrations with an external review service, not generic correctness proofs. They default to ten review/fix cycles. The large-PR variant additionally accepts an edited summary comment based on its update time; an update after a trigger does not itself bind a result to the current diff. A future adapter would need exact SHA/snapshot binding, explicit reviewer selection and the existing bounded correction policy.[15][16]

No Greptile installation or credential setup is justified for this change. Preserve the selected SDD verification path and avoid automatically chaining it with Judgment Day or a hosted score loop. Split large changes rather than relying on a special reviewer mention to bypass a file-count limit.

The plain-language ideas in `unslop` overlap the existing `comment-writer` and `cognitive-doc-design` skills. Its universal punctuation/style bans and invitation to add opinions are not appropriate universal rules for technical evidence. Preserve necessary uncertainty, citations, schemas and the user's Spanish-language preference. Improving prose should not make an unsupported claim sound more confident.[17]

## Implementation priorities

1. Correct checkout-validity diagnosis with isolated fixtures. Report stale records once and continue checking live checkouts. Keep untracked source visible.
2. Add safe, explicit local housekeeping and ownership diagnostics. Do not auto-commit, push, prune or delete another session's work to obtain zero warnings.
3. Add the shared local evidence skill and any minimal, tested report tooling. Verify clean installation, idempotent reruns and preservation of user settings in both clients.
4. Include revision-aware before/after and optional visual-evidence guidance, without adding global hooks, screen recorders or upload dependencies.
5. Retain this assessment as the provenance and rejection ledger. Reconsider optional tools only when a real task demonstrates a missing capability.

Use small reviewable changes with tests and rollback boundaries. The source snapshot is fixed for this assessment; do not fetch new upstream versions during installation. Future changes require another compatibility and license check.

## Acceptance and limitations

Acceptance requires passing isolated regression tests, installed/source parity for the shared additions, preserved Astra routing, an idempotent installer and a fresh full verification receipt. Environmental warnings must include ownership and next action rather than being hidden. A clean harness checkout is not proof that every sibling repository is ready to integrate.

No live recording, upload, browser-authentication bypass, Greptile review or upstream test execution was performed for this assessment. Legal status beyond the inspected notices is not established. The user-approved scope covers justified improvements, not indiscriminate installation or takeover of other sessions.

## Sources

1. Michael Shimeles. [Repository inventory and README](https://github.com/michaelshimeles/skills/tree/513f8a24aae6383b00356fa285144b1bc3730dc1), reviewed 2026-09-09.
2. Michael Shimeles. [Workflow template](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/AGENTS.md).
3. GitHub. [Repository metadata](https://api.github.com/repos/michaelshimeles/skills), retrieved 2026-09-09; local immutable inventory inspected separately.
4. GitHub Docs. [Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository), accessed 2026-09-09.
5. James Clements. [Bundled before-and-after license](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/before-and-after/LICENSE).
6. Greptile AI. [Bundled MIT license](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/greploop/LICENSE).
7. Lauren Tan. [Bundled MIT license](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/unslop/LICENSE).
8. Michael Shimeles. [Evidence-driven testing skill](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/evidence-driven-testing/SKILL.md).
9. Michael Shimeles. [Recorder implementation](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/evidence-driven-testing/scripts/evidence.py).
10. Michael Shimeles. [Recorder test inventory](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/tests/test_evidence.py).
11. James Clements / vendored source. [Upload wrapper and adapters](https://github.com/michaelshimeles/skills/tree/513f8a24aae6383b00356fa285144b1bc3730dc1/before-and-after/scripts).
12. James Clements / vendored source. [Capture helper](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/before-and-after/scripts/capture.sh).
13. Vercel Labs. [agent-browser CLI documentation](https://github.com/vercel-labs/agent-browser#quick-start), accessed 2026-09-09.
14. Michael Shimeles. [New-feature skill](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/new-feature/SKILL.md).
15. Greptile AI / vendored source. [Greploop](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/greploop/SKILL.md).
16. Michael Shimeles / Greptile AI. [Greploop Apps](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/greploop-apps/SKILL.md).
17. Lauren Tan / vendored source. [Unslop](https://github.com/michaelshimeles/skills/blob/513f8a24aae6383b00356fa285144b1bc3730dc1/unslop/SKILL.md).
