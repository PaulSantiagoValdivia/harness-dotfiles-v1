#!/usr/bin/env bash
# Integration test for the Codex portion of bootstrap.sh.
# Every fixture uses an isolated HOME; the real user configuration is untouched.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_PATH="$PATH"
REAL_CODEX="$(command -v codex)"
REAL_ENGRAM="$(command -v engram)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-codex-test.XXXXXX")"

STRICT_CODEX_BINS=("$REAL_CODEX")

cleanup() {
  case "${TMP_ROOT:-}" in
    *bootstrap-codex-test.*) rm -rf "$TMP_ROOT" ;;
  esac
}
trap cleanup EXIT

STUB_BIN="$TMP_ROOT/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/brew" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--prefix" ]; then
  printf '%s\n' /usr/local
  exit 0
fi
exit 0
EOF

cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
# bootstrap only needs successful MCP list/add operations in this isolated HOME.
if [ "${1:-}" = "mcp" ]; then exit 0; fi
if [ "${1:-}" = "--version" ]; then printf '%s\n' 'test-claude'; fi
exit 0
EOF

cat > "$STUB_BIN/gentle-ai" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "install" ]; then
  mkdir -p "$HOME/.codex"
  # Reproduce an older installer output with legacy agent keys. Bootstrap must
  # migrate them to the current supported per-session settings.
  if [ ! -f "$HOME/.codex/config.toml" ]; then
    cat > "$HOME/.codex/config.toml" <<'CONFIG'
model = "gpt-5.6-sol"

[plugins."engram@engram"]
enabled = true

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"

[agents]
max_threads = 4
max_depth = 2
CONFIG
  fi
  # Simulate a preset refresh overwriting primary model preferences. The
  # harness must restore values captured before invoking Gentle AI.
  tmp="$HOME/.codex/config.toml.tmp"
  awk '
    BEGIN { in_root=1 }
    /^\[/ && in_root {
      if (!seen_effort) print "model_reasoning_effort = \"xhigh\""
      in_root=0
    }
    in_root && /^model[[:space:]]*=/ { print "model = \"installer-overwrite\""; seen_model=1; next }
    in_root && /^model_reasoning_effort[[:space:]]*=/ { print "model_reasoning_effort = \"xhigh\""; seen_effort=1; next }
    { print }
  ' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
  exit 0
fi
if [ "${1:-}" = "skill-registry" ]; then
  mkdir -p "$HOME/.atl"
  : > "$HOME/.atl/skill-registry.md"
  exit 0
fi
exit 0
EOF

chmod +x "$STUB_BIN/brew" "$STUB_BIN/claude" "$STUB_BIN/gentle-ai"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

root_setting_is() {
  local config="$1" key="$2" expected="$3"
  awk -v key="$key" -v expected="$expected" '
    BEGIN { in_root=1 }
    /^\[/ { in_root=0 }
    in_root && index($0, key " = ") == 1 {
      count++
      value=$0
      sub(/^[^=]+=[[:space:]]*/, "", value)
    }
    END { exit(count == 1 && value == expected ? 0 : 1) }
  ' "$config"
}

section_setting_is() {
  local config="$1" header="$2" key="$3" expected="$4"
  awk -v header="$header" -v key="$key" -v expected="$expected" '
    $0 == header { inside=1; next }
    /^\[/ { inside=0 }
    inside && index($0, key " = ") == 1 {
      count++
      value=$0
      sub(/^[^=]+=[[:space:]]*/, "", value)
    }
    END { exit(count == 1 && value == expected ? 0 : 1) }
  ' "$config"
}

assert_common() {
  local home="$1" expected_primary_effort="${2:-medium}" config
  config="$home/.codex/config.toml"

  root_setting_is "$config" model_instructions_file \
    "\"$home/.codex/engram-instructions.md\"" || fail "model_instructions_file ausente o fuera de root"
  root_setting_is "$config" experimental_compact_prompt_file \
    "\"$home/.codex/engram-compact-prompt.md\"" || fail "compact prompt ausente o fuera de root"
  root_setting_is "$config" approval_policy '"never"' \
    || fail "Codex todavía puede solicitar aprobaciones"
  root_setting_is "$config" sandbox_mode '"danger-full-access"' \
    || fail "Codex no tiene acceso completo por defecto"
  test -f "$home/.codex/engram-instructions.md" || fail "engram-instructions.md no fue instalado"
  test -x "$home/.local/bin/triangulate" || fail "launcher triangulate no fue instalado"
  test -x "$home/.local/bin/devtools" || fail "launcher devtools no fue instalado"
  test -x "$home/Documents/cocoa-devtools.py" || fail "servidor Cocoa DevTools no fue instalado"
  test -f "$home/Documents/cocoa-reference.html" || fail "HTML Cocoa DevTools no fue instalado"
  cmp -s "$REPO_DIR/files/shared/devtools/cocoa-devtools.py" \
    "$home/Documents/cocoa-devtools.py" || fail "servidor Cocoa DevTools diverge del source"
  cmp -s "$REPO_DIR/files/shared/devtools/cocoa-reference.html" \
    "$home/Documents/cocoa-reference.html" || fail "HTML Cocoa DevTools diverge del source"
  test -f "$home/.codex/skills/triangulation-orchestrator/SKILL.md" || fail "skill de triangulación no fue instalado en Codex"
  test -f "$home/.claude/skills/triangulation-orchestrator/SKILL.md" || fail "skill de triangulación no fue instalado en Claude"
  test -f "$home/.codex/skills/triangulation-orchestrator/references/protocol.md" || fail "protocolo de triangulación no fue instalado en Codex"
  test -f "$home/.claude/skills/triangulation-orchestrator/references/protocol.md" || fail "protocolo de triangulación no fue instalado en Claude"
  cmp -s "$home/.codex/skills/triangulation-orchestrator/SKILL.md" \
    "$home/.claude/skills/triangulation-orchestrator/SKILL.md" || fail "skill de triangulación diverge entre clientes"

  section_setting_is "$config" '[agents]' enabled true || fail "agents.enabled no quedó activo"
  section_setting_is "$config" '[agents]' max_concurrent_threads_per_session 2 || fail "límite de subagentes != 2"
  section_setting_is "$config" '[agents]' default_subagent_reasoning_effort '"low"' || fail "effort de subagente != low"
  root_setting_is "$config" model_reasoning_effort "\"$expected_primary_effort\"" || fail "effort primary != $expected_primary_effort"
  if awk '/^\[agents\]$/{a=1;next} /^\[/{a=0} a && /^(max_threads|max_depth)[[:space:]]*=/{bad=1} END{exit bad?0:1}' "$config"; then
    fail "quedó una clave legacy en [agents]"
  fi
  grep -q 'maximum two' "$home/.codex/AGENTS.md" || fail "política de máximo dos ausente"
  grep -q 'Children must not spawn additional agents' "$home/.codex/AGENTS.md" || fail "política de no recursión ausente"
  grep -q 'Use low reasoning for bounded/mechanical children' "$home/.codex/AGENTS.md" || fail "política de effort barato ausente"

  [ "$(grep -c '^\[mcp_servers\.engram\]$' "$config")" = 1 ] || fail "Engram MCP no es único"
  section_setting_is "$config" '[mcp_servers.engram]' command "\"$REAL_ENGRAM\"" || fail "command de Engram incorrecto"
  section_setting_is "$config" '[mcp_servers.engram]' args '["mcp", "--tools=agent"]' || fail "args de Engram incorrectos"
  [ "$(grep -c '^\[mcp_servers\.context7\]$' "$config")" = 1 ] || fail "Context7 MCP no es único"
  section_setting_is "$config" '[mcp_servers.context7]' command '"npx"' || fail "Context7 no usa stdio"
  section_setting_is "$config" '[mcp_servers.context7]' args '["-y", "@upstash/context7-mcp@latest"]' \
    || fail "args de Context7 incorrectos"
  if awk '/^\[mcp_servers\.context7\]$/{inside=1;next} /^\[/{inside=0} inside && /^url[[:space:]]*=/{bad=1} END{exit bad?0:1}' "$config"; then
    fail "Context7 conserva url junto al transporte stdio"
  fi
  section_setting_is "$config" '[plugins."engram@engram"]' enabled false || fail "plugin Engram no quedó deshabilitado"

  project="$home/context7-layer-fixture"
  mkdir -p "$project/.codex"
  project="$(cd "$project" && pwd -P)"
  cat > "$project/.codex/config.toml" <<'PROJECT_CONFIG'
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp@latest"]
PROJECT_CONFIG
  cat >> "$config" <<EOF

[projects."$project"]
trust_level = "trusted"
EOF

  for codex_bin in "${STRICT_CODEX_BINS[@]}"; do
    CODEX_HOME="$home/.codex" "$codex_bin" app-server --strict-config --listen stdio:// </dev/null \
      || fail "$("$codex_bin" --version 2>/dev/null): rechazó config.toml en modo estricto"
    (cd "$project" && CODEX_HOME="$home/.codex" "$codex_bin" mcp list >/dev/null) \
      || fail "$("$codex_bin" --version 2>/dev/null): falló al fusionar Context7 global + repo"
    responses="$home/skills-list.jsonl"
    {
      printf '%s\n' \
        '{"method":"initialize","id":1,"params":{"clientInfo":{"name":"cocoa_config_smoke","title":"Cocoa config smoke","version":"1.0"}}}' \
        '{"method":"initialized","params":{}}' \
        "{\"method\":\"skills/list\",\"id\":2,\"params\":{\"cwds\":[\"$project\"],\"forceReload\":true}}"
      sleep 1
    } | (cd "$project" && CODEX_HOME="$home/.codex" "$codex_bin" app-server --strict-config --listen stdio://) \
      > "$responses" \
      || fail "$("$codex_bin" --version 2>/dev/null): app-server rechazó skills/list"
    jq -e 'select(.id == 2 and .error == null) | .result.data | all(.errors | length == 0)' \
      "$responses" >/dev/null \
      || fail "$("$codex_bin" --version 2>/dev/null): skills/list forceReload no devolvió un resultado limpio"
  done
}

run_bootstrap() {
  local home="$1"
  HOME="$home" PATH="$STUB_BIN:$REAL_PATH" "$REPO_DIR/bootstrap.sh" --yes >/dev/null
}

# Fixture 1: HOME realmente limpio. Gentle AI simulado crea la configuración
# parcial que antes dejaba cero proveedores al deshabilitar el plugin.
CLEAN_HOME="$TMP_ROOT/home-clean"
mkdir -p "$CLEAN_HOME"
run_bootstrap "$CLEAN_HOME"
run_bootstrap "$CLEAN_HOME"
assert_common "$CLEAN_HOME"
grep -q '^\[agents\]$' "$CLEAN_HOME/.codex/config.toml" || fail "[agents] no fue creado en HOME limpio"

# Fixture 2: configuración del usuario con rol y secret propios. No hay tabla
# raíz [agents], MCP Engram ni instruction files; bootstrap debe agregarlos sin
# reubicar ni perder las tablas existentes.
ROLE_HOME="$TMP_ROOT/home-role"
mkdir -p "$ROLE_HOME/.codex"
cat > "$ROLE_HOME/.codex/config.toml" <<'EOF'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"

[plugins."engram@engram"]
enabled = true

[agents.reviewer]
description = "preserve-role-fixture"

[mcp_servers.private]
command = "/bin/true"
env = { TOKEN = "preserve-secret-fixture" }

[mcp_servers.context7]
url = "https://mcp.context7.com/mcp"
EOF

run_bootstrap "$ROLE_HOME"
run_bootstrap "$ROLE_HOME"
assert_common "$ROLE_HOME" high
root_setting_is "$ROLE_HOME/.codex/config.toml" model '"gpt-5.6-sol"' || fail "modelo preexistente no fue restaurado"
root_setting_is "$ROLE_HOME/.codex/config.toml" model_reasoning_effort '"high"' || fail "effort preexistente no fue restaurado"
grep -q '^\[agents\]$' "$ROLE_HOME/.codex/config.toml" || fail "[agents] no fue creado junto al rol personalizado"
grep -q '^\[agents\.reviewer\]$' "$ROLE_HOME/.codex/config.toml" || fail "rol personalizado eliminado"
grep -q '^description = "preserve-role-fixture"$' "$ROLE_HOME/.codex/config.toml" || fail "rol personalizado alterado"
grep -q 'TOKEN = "preserve-secret-fixture"' "$ROLE_HOME/.codex/config.toml" || fail "secret personalizado alterado"

printf 'PASS: bootstrap Codex standalone, Context7 compatible, límites actuales, rol preservado e idempotencia\n'
