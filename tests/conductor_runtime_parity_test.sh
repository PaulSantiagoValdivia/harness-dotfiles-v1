#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONDUCTOR_HOME="$HOME/Library/Application Support/com.conductor.app"
CONDUCTOR_CODEX="$CONDUCTOR_HOME/bin/codex"
CONDUCTOR_DB="$CONDUCTOR_HOME/conductor.db"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$*"; }

# Claude-in-Conductor uses the normal Claude home overlay. Exercise the actual
# installed workflow code through the transactional VM fixture, not existence.
cmp -s "$ROOT/files/claude/workflows/codex-build.js" "$HOME/.claude/workflows/codex-build.js" \
  || fail 'installed Claude codex-build overlay differs from source'
bash "$ROOT/tests/codex_sdd_backend_test.sh" workflow >/dev/null \
  || fail 'transactional codex-build receipt runtime failed'
grep -q 'gentle-ai.sdd-execution-receipt/v1' "$HOME/.claude/workflows/codex-build.js" \
  || fail 'installed Claude workflow lacks transactional receipts'
codex_bin=$(sed -n "s/.*A.codexBin || '\([^']*\)'.*/\1/p" "$HOME/.claude/workflows/codex-build.js")
[[ -x "$codex_bin" ]] || fail "installed codexBin is not executable: $codex_bin"
"$codex_bin" --version >/dev/null || fail 'Claude workflow Codex binary cannot start'
claude --version >/dev/null || fail 'Claude runtime cannot start'
claude_mcp=$(claude mcp list 2>&1 || true)
grep -q '^codex:' <<<"$claude_mcp" || fail 'Claude runtime cannot discover Codex MCP'
pass 'Claude runtime discovers installed route; transactional receipt harness passes'

# Direct Codex in Conductor is native: no Claude workflow receipt contract is
# injected into AGENTS, while SDD/OpenSpec/Engram and orchestration policy remain.
[[ -x "$CONDUCTOR_CODEX" ]] || fail 'Conductor bundled Codex is absent'
[[ -f "$CONDUCTOR_DB" ]] || fail 'Conductor database is absent'
[[ $(sqlite3 "$CONDUCTOR_DB" "select value from settings where key='default_codex_thinking_level';") == medium ]] \
  || fail 'Conductor direct Codex default effort is not medium'
[[ $(sqlite3 "$CONDUCTOR_DB" "select value from settings where key='review_codex_thinking_level';") == high ]] \
  || fail 'Conductor direct Codex review effort is not high'
grep -q 'Direct Codex runtime' "$HOME/.codex/AGENTS.md" || fail 'direct Codex runtime contract missing'
! grep -q 'codex-build' "$HOME/.codex/AGENTS.md" || fail 'direct Codex must bypass codex-build'
grep -q 'maximum two' "$HOME/.codex/AGENTS.md" || fail 'maximum-two policy missing'
grep -q 'Children must not spawn additional agents' "$HOME/.codex/AGENTS.md" || fail 'no-recursion policy missing'
grep -q 'openspec.*ACTIVE DEFAULT' "$HOME/.codex/AGENTS.md" || fail 'OpenSpec default missing'
[[ $(codex mcp list 2>/dev/null | grep -c '^engram ' || true) == 1 ]] || fail 'direct Codex Engram provider is not unique'
[[ -f "$HOME/.codex/skills/sdd-apply/SKILL.md" ]] || fail 'direct Codex SDD skill missing'

for bin in "$(command -v codex)" "$CONDUCTOR_CODEX"; do
  tmp=$(mktemp -d)
  cp "$HOME/.codex/config.toml" "$tmp/config.toml"
  CODEX_HOME="$tmp" "$bin" app-server --strict-config --listen stdio:// </dev/null \
    || { rm -rf "$tmp"; fail "$bin rejected strict config"; }
  rm -rf "$tmp"
done
pass 'direct bundled/global Codex start natively with SDD and one Engram provider'
