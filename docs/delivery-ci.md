# Deliver with focused source CI

`harness-ci` is the replacement delivery gate for the Gentle AI 2.7 migration.
It does NOT replace installed-runtime acceptance or erase previous reviews.
Repository protection must be configured separately before treating this gate as enforced.

## Run and interpret

Run `bash tests/ci_verify.sh` from any directory using its absolute path when
outside the repository. Prerequisites: Bash, Python 3, Git, jq, and ShellCheck.
Missing prerequisites, missing suites, or any failed subcheck fail the run.

| Check | What it proves |
| --- | --- |
| Runner syntax, ShellCheck, negative fixtures | Explicit suite mapping and failed subprocess propagation |
| Engram concurrency | Eight real-Git cases with disposable HOME and controlled exporters |
| Engram source contract | 89 assertions against the absolute repository hook path, not an installed copy |
| Verification diagnostics | Exit codes, private receipts, and receipt-write failure handling |
| Evidence skill | Source/template contract and temporary installation fixtures |

The orchestration negative fixtures substitute subprocesses ONLY in a temporary
copy of the runner. They do not count as runtime assertions. All actual suites
also execute unchanged against repository source.

## Delivery policy

- The stable required context is `harness-ci`, with no matrix suffix.
- Pull requests to **all branches** run it, including stacked/intermediate targets;
  pushes to `main` and manual dispatch also run it. There are no path filters.
- The job has read-only repository permissions and no persisted checkout credentials.
  It runs on Ubuntu without models, service credentials, live cmux, or global HOME installation.
- Keep old review records and findings intact as historical evidence. Do not forge,
  rewrite, or delete transaction receipts to satisfy the new delivery path.
- A maintainer must separately require `harness-ci` in repository rules/protection
  for each intended merge target and require an up-to-date tested branch. Merely
  adding this workflow does not configure protection or migrate native hook policy.
- Merge only the exact tested tree: verify the latest head SHA, base SHA, current
  PR merge-check result, and passing context before each merge. A changed head or
  base requires a fresh run; a green manual or old-head run is not interchangeable.
  Stacked children must rerun after their parent merges/rebases.

## Activation status

Protection activation is BLOCKED: the private repository account rejected the
protection update with HTTP 403 (GitHub Pro or public-repository capability
required). Keep this migration in draft and preserve the existing delivery gate
until an authorized, enforceable replacement is available. Do not change repository
visibility or account billing merely to make CI appear enforced.

## Limits and rollback

A local pass is source-fixture evidence, not an observed GitHub Actions pass.
This subset deliberately omits `verify.sh`, live cmux, provider/model invocation,
installed-client parity, and full machine acceptance. Context-budget age parsing
uses BSD `date -j`; model-suffix fixtures use BSD `stat -f`. Both suites are
excluded from this Ubuntu subset rather than weakening their assertions. Run the relevant installed
checks separately when a change touches those boundaries; do not claim they passed
from `harness-ci` alone. A failing historical runtime check remains a failure.

Rollback this delivery work unit by reverting the workflow, both CI runner files,
and this document together. Coordinate any protection/native-policy rollback
separately; deleting a required workflow without updating protection blocks merges.
