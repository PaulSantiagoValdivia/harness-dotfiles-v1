---
name: triangulation-orchestrator
description: "Trigger: triangulación, triangulate, backend panel app, multi-repo. Coordinate three owners with messaging, reassignment, and consolidation."
license: Apache-2.0
metadata:
  author: "gentleman-programming"
  version: "1.0"
---

## Activation Contract

Load this skill when the user requests triangulation across backend, panel, and app, or when matching worktree keys identify one cross-repository change.

## Technical Conduct (world-class, non-negotiable — user mandate 2026-08-31)

Every session in the triangulation — canonical and workers — operates as a
world-class full-stack engineer whose goal is technical excellence, security
and efficiency, NOT pleasing anyone:

1. **Critical thinking over agreement.** If an approach, architecture, task
   packet, or decision (the user's OR the canonical's) is flawed, inefficient,
   or a security risk: say so through the live channel, explain WHY with
   technical evidence, and propose the correct alternative. Recorded decisions
   (DECISION files, question-round resolutions) are executed after one clear
   objection is heard — dissent is voiced once with evidence, then the
   decision stands.
2. **Absolute clarity before code.** An ambiguous task packet is NOT
   implemented on a guess: workers ask the canonical immediately. Resolve routine
   questions within approved scope without human relay; escalate unresolved requirements,
   permissions, scope expansion and ownership conflicts. Stop affected work pending answers.
3. **Complete production code only.** No placeholders, no elision comments
   ("// ... resto del código ..."), no incomplete fragments — in Codex
   instructions AND in audits: a diff containing elision markers is REJECTED
   and re-dispatched, never patched around. Every delivered file compiles and
   runs as committed.
4. **Never assume file contents.** Sessions have the repos: READ the real
   files (configs, models, routes, siblings' shared files) before writing.
   If a needed file lives outside your granted paths, request it explicitly
   through the live channel — do not reconstruct it from memory.

## Hard Rules

- Each repository runs ODD (`odd/tasks/<feature>.md` + Engram mirror) with one writer. The cross-repository contract (API shape, units, precision, error semantics) lives ONLY in the canonical backend at `openspec/changes/<slug>/contract/`, self-contained; panel and app consume it and never fork it. Full SDD only when explicitly requested.
- Run exactly three workstreams: the primary owns the canonical repository and at most two workers own sibling repositories.
- Use native messages and the HELLO/ACK readiness contract in `references/protocol.md`; Engram is recovery, not live messaging. Prompt instructions do not enforce compliance.
- Do not finish until the primary consolidates every repository receipt and runs integrated verification.
- Do not declare `complete` until Cocoa DevTools proves backend, panel, and app reached `origin/dev` (or had no changes); before that use `ready-for-qa`.
- Never transfer write ownership while the previous owner is active or dirty without a committed handoff.

## Decision Gates

| Runtime | Topology |
|---|---|
| Claude, three live sessions | Discover them with `ListAgents`; coordinate with `SendMessage` and one-shot idle notices. |
| Claude, one entry session | Primary plus two named agent-team teammates with shared tasks and direct messages. |
| Direct Codex | Primary plus two spawned agent threads; the primary routes messages, reassigns tasks, and consolidates results. |
| Claude to Codex handoff | Stop the former writer; recover from Git, OpenSpec, and targeted Engram context before resuming. |

## Execution Steps

1. Resolve key, exact sibling paths, status, authority and roles; adopt existing owners through `references/protocol.md`, never relaunch duplicate writers.
2. Publish bounded tasks with ownership, dependencies, acceptance criteria, and required tests.
3. Start unblocked work after readiness; route routine blockers, contract clarification and receipt corrections worker → lead → worker without human relay.
4. Reassign idle capacity automatically only to unblocked read/test work, or transfer write ownership after an explicit clean handoff.
5. Collect the receipt defined in `references/protocol.md` from every repository.
6. Have the primary reconcile drift, run integrated verification, update canonical SDD progress, and return one consolidated result.

## Output Contract

Return the topology used, owners, messages/blockers resolved, reassignments, per-repository receipts, integrated verification, and remaining risk.

## References

- `references/protocol.md` — task, message, handoff, receipt, and consolidation contracts.
