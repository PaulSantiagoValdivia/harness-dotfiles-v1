#!/usr/bin/env bash
# Validate the effective Codex MCP config from every active Cocoa repo/worktree.
set -euo pipefail

CONFIG="${TRIANGULATE_CONFIG:-$HOME/.claude/triangulate.conf}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[ -f "$CONFIG" ] || fail "no existe $CONFIG"

paths=()
while IFS='=' read -r role repo; do
  [[ "$role" =~ ^(back|front|app)$ ]] || continue
  [ -d "$repo" ] || fail "repo $role ausente: $repo"
  paths+=("$repo")
  for worktree in "$repo"/.claude/worktrees/triangulate-*; do
    [ -d "$worktree" ] && paths+=("$worktree")
  done
done < "$CONFIG"

[ "${#paths[@]}" -ge 3 ] || fail "triangulate.conf no resolvió los tres repos"

for path in "${paths[@]}"; do
  if ! output="$(cd "$path" && codex mcp list 2>&1)"; then
    printf '%s\n' "$output" >&2
    fail "config MCP efectiva inválida en $path"
  fi
done

# Reproduce the TUI path that originally failed: app-server reloads skills and
# resolves the project-scoped config while forceReload=true.
front="$(awk -F= '$1 == "front" { print substr($0, index($0, "=") + 1); exit }' "$CONFIG")"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-mcp-layering.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
cp "$HOME/.codex/config.toml" "$tmp/config.toml"
[ -d "$HOME/.codex/skills" ] && ln -s "$HOME/.codex/skills" "$tmp/skills"
responses="$tmp/skills-list.jsonl"
{
  printf '%s\n' \
    '{"method":"initialize","id":1,"params":{"clientInfo":{"name":"cocoa_mcp_layering_test","title":"Cocoa MCP layering test","version":"1.0"}}}' \
    '{"method":"initialized","params":{}}' \
    "{\"method\":\"skills/list\",\"id\":2,\"params\":{\"cwds\":[\"$front\"],\"forceReload\":true}}"
  sleep 1
} | (cd "$front" && CODEX_HOME="$tmp" codex app-server --strict-config --listen stdio://) \
  > "$responses" || fail "app-server rechazó skills/list en el panel"

jq -e 'select(.id == 2 and .error == null) | .result.data | all(.errors | length == 0)' \
  "$responses" >/dev/null || fail "skills/list forceReload no devolvió un resultado limpio"

printf 'PASS: MCP Codex válido en %d roots/worktrees y skills/list recarga sin conflicto\n' "${#paths[@]}"
