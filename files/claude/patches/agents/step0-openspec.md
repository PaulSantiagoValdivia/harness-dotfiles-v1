**Step 0 — resolve the artifact store BEFORE any read or write.**
`openspec` is the ACTIVE DEFAULT in this harness (see `~/.claude/CLAUDE.md`); the
`mem_*` calls listed below describe `engram` mode only. In `openspec` or `hybrid`
mode, read and write the files under `openspec/changes/{change-name}/`
(`proposal.md`, `specs/`, `design.md`, `tasks.md`) per
`~/.claude/skills/_shared/openspec-convention.md`, and treat every
`mem_search` / `mem_get_observation` / `mem_save` step below as its file
equivalent. NEVER report a required artifact as missing because an Engram lookup
came back empty — check the OpenSpec path first.
