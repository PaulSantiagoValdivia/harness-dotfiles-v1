# Harness health finding dispositions

Baseline: `/tmp/astra-harness-verify.log`, 2026-09-09, **701 PASS / 17 WARN / 7 FAIL**. This ledger separates defects in diagnostics from state owned by other sessions. Counts and branch positions are point-in-time observations; inspect again before any integration or cleanup.

## Failures

| ID | Baseline finding | Evidence and disposition | Owner / next action |
|---|---|---|---|
| F1 | backend temporary `wt-onboard/CLAUDE.md` absent | Directory remains without `.git`; corrected stale-checkout classification with GREEN fixtures, not file recreation | Harness verifier; preserve residual data |
| F2 | backend temporary `wt-onboard/AGENTS.md` absent | Same metadata failure as F1, not a second live-checkout defect | Harness verifier; one actionable stale classification |
| F3 | `/private/tmp/wt-pf-dev/CLAUDE.md` absent | Residual directory without `.git`; corrected classification with GREEN fixtures | Harness verifier; preserve residual data |
| F4 | `/private/tmp/wt-pf-dev/AGENTS.md` absent | Same metadata failure as F3 | Harness verifier; no fabricated instructions |
| F5 | `/private/tmp/wt-pf-master/CLAUDE.md` absent | Residual directory without `.git`; corrected classification with GREEN fixtures | Harness verifier; preserve residual data |
| F6 | `/private/tmp/wt-pf-master/AGENTS.md` absent | Same metadata failure as F5 | Harness verifier; no fabricated instructions |
| F7 | panel canonical checkout does not ignore `.claude/worktrees/` | Confirmed with `git check-ignore`; resolved with backed-up local common-directory exclude protection | Local harness; do not edit/reset stale panel `main` |

## Warnings

| ID | Baseline finding | Disposition | Owner / next action |
|---|---|---|---|
| W1 | Three Codex marketplace staging directories, 79 MB total staging | Retained; age is not proof of safe deletion | Runtime owner: inspect active installer/file usage before scoped cleanup |
| W2 | Codex storage exceeds 2 GB | Retained; sessions and SQLite files may be live | Runtime owner: retention plan with clients closed; never unlink a live database |
| W3 | backend `wt-onboard` stale registration | Retained recovery metadata and residual files | Worktree owner: inspect recoverable data and refs before explicit prune |
| W4 | backend `wt-pf-dev` stale registration | Retained recovery metadata and residual files | Worktree owner: inspect before explicit prune |
| W5 | backend `wt-pf-master` stale registration | Retained recovery metadata and residual files | Worktree owner: inspect before explicit prune |
| W6 | backend `triangulate-agropartners-organigrama`, four tracked dirty paths | Active work preserved; counts may change | Owning session: test, commit and push its own changes |
| W7 | backend `triangulate-qa-modulos-parity`, five tracked dirty paths | Active work preserved | Owning session: test, commit and push |
| W8 | backend `triangulate-reconocimientos-unificacion`, fifteen tracked dirty paths | Active work preserved, including previously hidden untracked source | Owning session: reconcile full tracked/untracked inventory |
| W9 | backend `feat/reconocimientos-motor-slice-15` not contained in local remote refs | Preserve commits; wording must not claim a live remote query | Owning session: fetch, compare, test and push when ready |
| W10 | panel canonical checkout does not ignore `.atl/` | Resolved locally with F7; applied twice idempotently | Local harness; generated files remain on disk |
| W11 | panel `main` not contained in local remote refs | Preserve local commit `b3ba1be`; observed ahead 1 / behind 530 | Panel owner: recover onto appropriate dev-based branch; never reset or push main |
| W12 | panel `triangulate-qa-modulos-parity`, four tracked dirty paths | Active work preserved | Owning session: test, commit and push |
| W13 | panel `triangulate-reconocimientos-unificacion`, three tracked dirty paths | Active work preserved | Owning session: test, commit and push |
| W14 | app canonical checkout, one tracked dirty path | Work preserved | Owning session: inspect ownership before commit |
| W15 | app temporary `wt-crash` stale registration | Retained metadata/residual recovery source | Worktree owner: inspect before explicit prune |
| W16 | app `release-a2`, one tracked dirty path | Active work preserved | Owning session: test, commit and push |
| W17 | app `triangulate-qa-modulos-parity`, two tracked dirty paths | Active work preserved | Owning session: test, commit and push |

## Scope and verification

Panel `origin/dev` already contains `.claude/worktrees/` and `.atl/` ignore rules. The stale local `main` does not. Local Git excludes protect this machine without creating a product-code change or disturbing its unpublished commit. This does not promote the old checkout to a current branch or integrate its code.

A corrected audit may report more pending work because it includes untracked source instead of hiding it. That is improved visibility, not a regression or permission to delete files. Legacy Conductor worktrees remain valid recovery sources.

Implementation and final-run receipts will update the pending dispositions above. No cleanup, commit or push of sibling work is implied by completion of the harness change.

Local repair receipt: `/tmp/harness-hardening-evidence/panel-local-protection.json` and sidecars. Two applies produced identical exclude SHA-256 `9877594d5dae30c534ecb099482f1150281ca23ddb655d7e98f0bb56553eee83`. `git check-ignore -v` resolves both rules; panel HEAD remains `b3ba1be`, and tracked/index diffs remain empty. No product files or refs changed.

## Final execution and formal closure

Independent final run on `6f33ef4`: **679 PASS / 16 WARN / 0 FAIL**, exit 0.
All seven baseline failures are resolved; sixteen owner/recovery warnings remain intentionally preserved.
Full log SHA-256: `493afd8d26371806b27c21dff8c93ebfe73caf293808dcbedd1f08132dba9109`.
The negotiated native post-apply review gate allows the approved, explicitly bound lineage.
OpenSpec closure is nevertheless **pending**: its earlier authority-only failed verification evidence
requires a compact remediation transaction. No supported evidence-reuse shortcut was established.
The valid failed report is retained rather than fabricated as PASS or archived. See the verification report.
