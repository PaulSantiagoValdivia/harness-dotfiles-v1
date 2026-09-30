<!-- gentle-ai:engram-protocol -->
## Engram Persistent Memory — On-Demand Protocol

Engram is available through one direct MCP connection in both Claude Code and Codex. Do not inject project memory automatically and do not duplicate this protocol in plugins or project instructions.

- **Search** only for recall/continuation, an unfamiliar referenced topic, or work likely completed before. Start with `mem_context` for recent history or `mem_search` for targeted keywords; call `mem_get_observation` only for a relevant hit.
- **Save once, when durable**: architecture/design decisions, conventions, workflow/tool choices, bug fixes with root cause, non-obvious discoveries, configuration changes, and explicit user preferences. Do not save routine reads, tool output, or repeated progress nudges.
- Use stable `topic_key` values for evolving decisions. Keep content to `What`, `Why`, `Where`, and an optional `Learned` note.
- Before closing a meaningful work session, write one concise `mem_session_summary` with Goal, Discoveries, Accomplished, Next Steps, and Relevant Files.
- Before compaction, persist the bounded handoff required by the Runtime Budget. After compaction, recover only the observations needed for the immediate next step.
<!-- /gentle-ai:engram-protocol -->
