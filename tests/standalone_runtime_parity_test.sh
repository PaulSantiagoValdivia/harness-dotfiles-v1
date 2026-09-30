#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

claude --version >/dev/null || fail 'Claude runtime cannot start'
codex --version >/dev/null || fail 'Codex runtime cannot start'

awk '
  BEGIN { in_root=1 }
  /^\[/ { in_root=0 }
  in_root && /^approval_policy = "never"$/ { approval=1 }
  in_root && /^sandbox_mode = "danger-full-access"$/ { sandbox=1 }
  END { exit(approval && sandbox ? 0 : 1) }
' "$HOME/.codex/config.toml" \
  || fail 'Codex global full-access/no-approval policy is not active'

# Con --codex-enforcement bootstrap anexa el OVERRIDE (files/claude/patches/
# claude-md-codex-override.md) al final del CLAUDE.md instalado; la paridad se
# evalúa contra source+override cuando el hook está registrado.
if grep -q 'route-code-to-codex' "$HOME/.claude/settings.json" 2>/dev/null; then
  cmp -s <(cat "$ROOT/files/claude/CLAUDE.md"; echo; cat "$ROOT/files/claude/patches/claude-md-codex-override.md") "$HOME/.claude/CLAUDE.md" \
    || fail 'installed Claude instructions differ from source + codex override'
else
  cmp -s "$ROOT/files/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" \
    || fail 'installed Claude instructions differ from source'
fi
cmp -s "$ROOT/files/codex/AGENTS.md" "$HOME/.codex/AGENTS.md" \
  || fail 'installed Codex instructions differ from source'
cmp -s "$ROOT/files/shared/bin/triangulate" "$HOME/.local/bin/triangulate" \
  || fail 'installed triangulate launcher differs from source'
cmp -s "$ROOT/files/shared/bin/devtools" "$HOME/.local/bin/devtools" \
  || fail 'installed devtools launcher differs from source'
cmp -s "$ROOT/files/shared/devtools/cocoa-devtools.py" "$HOME/Documents/cocoa-devtools.py" \
  || fail 'installed Cocoa DevTools server differs from source'
cmp -s "$ROOT/files/shared/devtools/cocoa-reference.html" "$HOME/Documents/cocoa-reference.html" \
  || fail 'installed Cocoa DevTools HTML differs from source'

jq -e '
  .crossSessionInbound == "accept" and
  .isolatePeerMachines == true and
  .teammateMode == "in-process" and
  .env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"
' "$HOME/.claude/settings.json" >/dev/null \
  || fail 'Claude direct messaging/team runtime is not enabled safely'

for file in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
  grep -q 'gentle-ai:coordinated-worktrees' "$file" \
    || fail "coordinated worktree contract missing in $file"
  grep -q 'Three worktrees may remain active concurrently' "$file" \
    || fail "three-worktree distinction missing in $file"
  grep -q 'Legacy Conductor recovery' "$file" \
    || fail "legacy worktree recovery rule missing in $file"
  ! grep -q 'Conductor owns the UI effort' "$file" \
    || fail "active Conductor runtime rule remains in $file"
  grep -q 'gentle-ai:automatic-triangulation' "$file" \
    || fail "automatic triangulation contract missing in $file"
done


cmp -s \
  <(sed -n '/gentle-ai:automatic-triangulation -->/,/\/gentle-ai:automatic-triangulation -->/p' "$HOME/.claude/CLAUDE.md") \
  <(sed -n '/gentle-ai:automatic-triangulation -->/,/\/gentle-ai:automatic-triangulation -->/p' "$HOME/.codex/AGENTS.md") \
  || fail 'Claude and Codex automatic triangulation contracts diverge'

for client in claude codex; do
  skill="$HOME/.$client/skills/triangulation-orchestrator/SKILL.md"
  protocol="$HOME/.$client/skills/triangulation-orchestrator/references/protocol.md"
  test -f "$skill" || fail "triangulation skill missing for $client"
  test -f "$protocol" || fail "triangulation protocol missing for $client"
  cmp -s "$ROOT/files/shared/skills/triangulation-orchestrator/SKILL.md" "$skill" \
    || fail "installed triangulation skill differs for $client"
  cmp -s "$ROOT/files/shared/skills/triangulation-orchestrator/references/protocol.md" "$protocol" \
    || fail "installed triangulation protocol differs for $client"
done

# BEGIN harness-evidence parity
# shellcheck source=files/shared/lib/install-shared-skill.sh
source "$ROOT/files/shared/lib/install-shared-skill.sh"
for client in claude codex; do
  shared_skill_matches "$ROOT/files/shared/skills/harness-evidence" "$HOME/.$client/skills/harness-evidence" \
    || fail "installed evidence skill tree differs for $client"
done
# END harness-evidence parity

grep -q 'one primary plus two spawned agent threads' "$HOME/.codex/AGENTS.md" \
  || fail 'Codex coordinated topology is not explicit'
grep -q 'ListAgents.*SendMessage' "$HOME/.claude/CLAUDE.md" \
  || fail 'Claude native direct-session channel is not explicit'

claude_mcp=$(claude mcp list 2>&1 || true)
! grep -q '^codex:' <<<"$claude_mcp" || fail 'Claude still depends on legacy Codex MCP'
grep -q '^engram:' <<<"$claude_mcp" || fail 'Claude direct Engram MCP missing'
! grep -q '^plugin:engram:' <<<"$claude_mcp" || fail 'Claude duplicates Engram through plugin and direct MCP'

awk '
  /^\[agents\]$/ { in_agents=1; next }
  /^\[/ { in_agents=0 }
  in_agents && /^enabled = true$/ { enabled=1 }
  in_agents && /^max_concurrent_threads_per_session = 2$/ { max=1 }
  in_agents && /^default_subagent_reasoning_effort = "low"$/ { effort=1 }
  END { exit(enabled && max && effort ? 0 : 1) }
' "$HOME/.codex/config.toml" || fail 'Codex per-session agent limits are incomplete'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$HOME/.codex/config.toml" "$tmp/config.toml"
CODEX_HOME="$tmp" codex app-server --strict-config --listen stdio:// </dev/null \
  || fail 'Codex rejected standalone strict config'

pass 'Claude/Codex static configuration/contracts; live messaging UNTESTED'
