## Code routing (MANDATORY — enforced by harness hook)

CODEX writes ALL product code. A PreToolUse hook blocks Edit/Write/NotebookEdit
and Bash file-writes on code files (exit 2) outside `.claude/`, `.agent/`,
`.atl/`, `openspec/` and markdown. Do not ask to bypass it. For every code
change, run:

    ~/.claude/bin/codex-run exec --skip-git-repo-check --sandbox workspace-write -m <model> "<bounded, precise instruction>"

`<model>` is the REAL Codex slug, not the short name: `gpt-5.6-sol` when the
task's `[codex: sol|astra]` tag in `tasks.md` says `sol`, `gpt-6-astra` when it
says `astra` (`sdd-tasks` already set the tag with full spec/design context).
`codex-run` does not alias short names — `-m sol` is an invalid model and
Codex will reject it.

No tag or no signal: pick by how much design ambiguity the brief leaves, not
by diff size. Open decisions (architecture, ownership/security boundaries,
non-obvious root cause) → `gpt-6-astra`. Contract fully closed — exact files,
fields and rules already specified, the model only transcribes →
`gpt-5.6-terra`. Purely mechanical → `gpt-5.6-sol`. When genuinely unsure
between two tiers, go up: a wrong cheap run costs a redo, which costs more
than it saved. Full table and the audit model (`codex-auto-review`) in
CLAUDE.md § "Selección de modelo Codex".

Then verify with `git diff` yourself before marking anything done. You still
own: reading code, tests via Bash, updating openspec artifacts / `tasks.md`
checkmarks / markdown, and auditing Codex's output.
