# Triangulation Authority

## ADDED Requirements

### Requirement: Explicit canonical mapping
Roles MUST share canonical identity declared by the requested slug or explicit alias mapping. Ambiguous, malformed, or escaping mappings MUST report BLOCKED. Handoff requires existing authority; absence MUST NOT select another plan by name or timestamp.

#### Scenario: Valid shared authority
- GIVEN a backend change mapping and three role paths
- WHEN any role resolves its handoff
- THEN the same canonical root is returned without fallback.

#### Scenario: Unresolved authority
- GIVEN absent authority, conflicting aliases, or invalid mapping and multiple plans
- WHEN resolving handoff
- THEN BLOCKED names configuration corrections without suggesting unrelated tasks.

### Requirement: Bounded compatible deployment
Handoff output MUST remain below 4 KiB. Scoped installation MUST back up managed replacements, preserve operator mappings/preferences, and provide idempotent Claude/Codex contract parity.

#### Scenario: Fresh and customized installations
- GIVEN fresh and customized client homes
- WHEN installed twice and restored from backups
- THEN source parity, preserved mappings, and bounded handoffs hold.

### Requirement: Worktree-rooted registry generation
Registry SessionStart hooks in both clients MUST refresh only at the owning Git worktree root, never a nested working directory or another checkout's Git common root. Exact HOME invocation MUST retain the global registry; nonrepository paths and failed root resolution MUST produce no registry write. Backed-up scoped installation and bootstrap reruns MUST preserve unrelated hooks/preferences and this behavior. The fix MUST NOT delete product data or weaken formatting exclusions.

#### Scenario: Nested checkout invocation
- GIVEN a main or linked worktree and a nested source cwd, including spaces or physical-path aliases
- WHEN either client invokes registry refresh
- THEN generation targets only that worktree root, with no nested `.atl` and no write to another checkout.

#### Scenario: HOME and unresolved location
- GIVEN exact HOME, a nonrepository directory, or failed Git root resolution
- WHEN registry refresh runs
- THEN only exact HOME may refresh globally; other cases skip without creating `.atl` or claiming success.

#### Scenario: Scoped persistent installation
- GIVEN customized client hook entries/settings and source bootstrap wiring
- WHEN installed twice, then restored from backup in fixtures
- THEN root targeting persists without duplicate refresh hooks, unrelated configuration loss, product deletion, or new formatter ignores.
