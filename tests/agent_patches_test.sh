#!/usr/bin/env bash
# agent_patches_test.sh — contrato de files/claude/bin/apply-agent-patches.sh.
#
# Instala gentle-ai en un HOME temporal (la misma versión que tiene la máquina)
# y verifica que los parches versionados: (1) reemplazan los tools del plugin
# Engram por los del MCP directo, (2) insertan cada bloque una sola vez en los
# agents correctos, (3) son idempotentes, (4) --check detecta drift y (5) el modo
# sin Codex retira el bloque "Code routing" sin destruir el archivo.
#
# El skill sdd-archive es generado por gentle-ai 3.7; el gate se aplica al
# agent, no mediante un overlay completo del skill.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/files/claude/bin/apply-agent-patches.sh"
PATCHES="$ROOT/files/claude/patches"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agent-patches-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

test -x "$SCRIPT" || fail 'apply-agent-patches.sh ausente o sin +x'
bash -n "$SCRIPT" || fail 'apply-agent-patches.sh no parsea'
for p in step0-openspec module-dod code-routing bg-wait archive-gate; do
  test -s "$PATCHES/agents/$p.md" || fail "falta el parche $p.md"
done
test ! -e "$PATCHES/skills/sdd-archive/SKILL.md" || fail 'el overlay eliminado de sdd-archive volvió a aparecer'

# bootstrap instala esta fuente junto a los demás patches. La suite reproduce
# ese layout sin depender de ~/.claude ni modificar los archivos versionados.
PATCHES_FIXTURE="$TMP/patches"
cp -a "$PATCHES" "$PATCHES_FIXTURE"
mkdir -p "$PATCHES_FIXTURE/codex"
cp "$ROOT/files/codex/AGENTS.md" "$PATCHES_FIXTURE/codex/AGENTS.md"

# Fixture real: lo que gentle-ai instala hoy, en un HOME aislado.
command -v gentle-ai >/dev/null 2>&1 || fail 'gentle-ai no está en PATH'
HOME="$TMP/home" gentle-ai install --scope global --agents claude-code,codex --preset full-gentleman --sdd-mode multi \
  </dev/null >"$TMP/install.log" 2>&1 || true
TARGET="$TMP/home/.claude"
CODEX_TARGET="$TMP/home/.codex"
test -f "$CODEX_TARGET/skills/sdd-archive/SKILL.md" || fail "gentle-ai no generó el skill sdd-archive de Codex (ver $TMP/install.log)"
test -f "$TARGET/agents/sdd-apply.md" || fail "gentle-ai no generó agents en el HOME temporal (ver $TMP/install.log)"
grep -q 'mcp__plugin_engram_engram__' "$TARGET/agents/sdd-apply.md" \
  || echo "INFO: gentle-ai ya no declara tools de plugin; el parche de tool names es no-op"
# Fixture de regresión: gentle-ai 3.7 puede dejar un tool directo repetido.
tmp_agent="$TMP/sdd-apply.md"
awk '!done && /^tools:/ { print $0 ", mcp__engram__mem_search"; done=1; next } { print }' \
  "$TARGET/agents/sdd-apply.md" > "$tmp_agent" && mv "$tmp_agent" "$TARGET/agents/sdd-apply.md"

# Fixtures post-sync: un hook de skill-registry en UserPromptSubmit y Context7
# en transporte HTTP deben quedar reparados sin tocar otras tablas TOML.
jq '.hooks.UserPromptSubmit = [
  {"matcher":"", "hooks":[
    {"type":"command", "command":"bash ~/.claude/hooks/skill-registry-refresh.sh"}
  ]},
  {"matcher":"", "hooks":[
    {"type":"command", "command":"bash ~/.claude/hooks/skill-registry-refresh.sh"},
    {"type":"command", "command":"bash ~/.claude/hooks/context-budget.sh"}
  ]}
]' "$TARGET/settings.json" > "$TMP/settings.json" && mv "$TMP/settings.json" "$TARGET/settings.json"

test -f "$CODEX_TARGET/config.toml" || fail 'gentle-ai no generó config.toml de Codex'
grep -q '^\[mcp_servers\.context7\]$' "$CODEX_TARGET/config.toml" \
  || fail 'gentle-ai no generó la tabla MCP Context7'
tmp_config="$TMP/config.toml"
awk '
  /^\[mcp_servers\.context7\]$/ { in_context7 = 1; print; next }
  /^\[/ { in_context7 = 0 }
  in_context7 && /^[[:space:]]*(url|command|args)[[:space:]]*=/ { next }
  { print }
' "$CODEX_TARGET/config.toml" > "$tmp_config" && mv "$tmp_config" "$CODEX_TARGET/config.toml"

# gentle-ai sync 3.7 vuelve a agregar estos límites. Solo deben retirarse de la
# tabla exacta [agents]; claves homónimas de otras tablas deben sobrevivir.
tmp_config="$TMP/config.toml"
awk '
  /^\[agents\]$/ {
    in_agents = 1
    print
    print "max_depth = 2"
    print "max_threads = 4"
    next
  }
  /^\[/ { in_agents = 0 }
  in_agents && /^[[:space:]]*(max_depth|max_threads)[[:space:]]*=/ { next }
  { print }
  END {
    print ""
    print "[fixture_outside_agents]"
    print "max_depth = 7"
    print "max_threads = 8"
  }
' "$CODEX_TARGET/config.toml" > "$tmp_config" && mv "$tmp_config" "$CODEX_TARGET/config.toml"
printf 'gentle-ai reemplazó este archivo\n' > "$CODEX_TARGET/AGENTS.md"
tmp_config="$TMP/config.toml"
awk '
  /^\[mcp_servers\.context7\]$/ { in_context7 = 1; print; next }
  /^\[/ {
    if (in_context7) print "url = \"https://mcp.context7.com/mcp\""
    in_context7 = 0
  }
  { print }
  END { if (in_context7) print "url = \"https://mcp.context7.com/mcp\"" }
' "$CODEX_TARGET/config.toml" > "$tmp_config" && mv "$tmp_config" "$CODEX_TARGET/config.toml"

# (4) --check sobre el fixture virgen debe reportar drift.
check_config_hash="$(shasum -a 256 "$CODEX_TARGET/config.toml" | cut -d' ' -f1)"
check_agents_hash="$(shasum -a 256 "$CODEX_TARGET/AGENTS.md" | cut -d' ' -f1)"
if bash "$SCRIPT" --target "$TARGET" --codex-target "$CODEX_TARGET" --patches "$PATCHES_FIXTURE" --check --quiet; then
  fail '--check no detectó drift sobre un fixture sin parchear'
fi
[ "$check_config_hash" = "$(shasum -a 256 "$CODEX_TARGET/config.toml" | cut -d' ' -f1)" ] \
  || fail '--check modificó config.toml'
[ "$check_agents_hash" = "$(shasum -a 256 "$CODEX_TARGET/AGENTS.md" | cut -d' ' -f1)" ] \
  || fail '--check modificó AGENTS.md'

# (1)(2) aplicar con Codex routing.
bash "$SCRIPT" --target "$TARGET" --codex-target "$CODEX_TARGET" --patches "$PATCHES_FIXTURE" --codex-routing >"$TMP/pass1.log"
! grep -rq 'mcp__plugin_engram_engram__' "$TARGET/agents" || fail 'quedaron tools del plugin Engram'
grep -q 'tools duplicados' "$TMP/pass1.log" || fail 'no se registró la deduplicación de tools'
for agent in "$TARGET"/agents/*.md; do
  if awk '
    /^tools:/ {
      n = split(substr($0, 7), item, ",")
      delete seen
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", item[i])
        if (item[i] != "" && seen[item[i]]++) found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$agent"; then
    fail "tools repetidos después del parche: $agent"
  fi
done
grep -q '^tools: [^,]' "$TARGET/agents/sdd-apply.md" || fail 'tools deduplicados con formato inválido'
! grep -q '^tools:,' "$TARGET/agents/sdd-apply.md" || fail 'tools deduplicados dejaron una coma tras tools:'
grep -q '^tools: Read, Edit, Write, Glob, Grep, Bash, mcp__engram__mem_search' "$TARGET/agents/sdd-apply.md" \
  || fail 'tools deduplicados no conservaron formato/orden de primera aparición'
grep -q '^tools:.*mcp__engram__mem_search' "$TARGET/agents/sdd-design.md" || fail 'sdd-design sin tools del MCP directo'
grep -qE '^tools:.*Bash' "$TARGET/agents/sdd-archive.md" || fail 'sdd-archive sin Bash'
! jq -e '[(.hooks.UserPromptSubmit // [])[]?.hooks[]? | select((.command // "") | contains("skill-registry"))] | length > 0' "$TARGET/settings.json" \
  || fail 'skill-registry quedó en UserPromptSubmit'
jq -e '[(.hooks.UserPromptSubmit // [])[]?.hooks[]? | select((.command // "") | contains("context-budget"))] | length == 1' "$TARGET/settings.json" \
  || fail 'el hook no skill-registry de UserPromptSubmit se perdió'
! awk '
  /^\[mcp_servers\.context7\]$/ { in_context7 = 1; next }
  /^\[/ { in_context7 = 0 }
  in_context7 && /^url = / { found_url = 1 }
  in_context7 && /^command = "npx"$/ { found_command = 1 }
  in_context7 && /^args = \["-y", "@upstash\/context7-mcp@latest"\]$/ { found_args = 1 }
  END { exit (found_url || !found_command || !found_args) }
' "$CODEX_TARGET/config.toml" && fail 'Context7 no quedó en stdio'
! awk '
  /^\[agents\]$/ { in_agents = 1; next }
  /^\[/ { in_agents = 0 }
  in_agents && /^[[:space:]]*(max_depth|max_threads)[[:space:]]*=/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$CODEX_TARGET/config.toml" || fail 'quedaron max_depth/max_threads dentro de [agents]'
awk '
  /^\[fixture_outside_agents\]$/ { in_fixture = 1; next }
  /^\[/ { in_fixture = 0 }
  in_fixture && /^max_depth = 7$/ { depth = 1 }
  in_fixture && /^max_threads = 8$/ { threads = 1 }
  END { exit !(depth && threads) }
' "$CODEX_TARGET/config.toml" || fail 'se tocaron claves homónimas fuera de [agents]'
cmp -s "$PATCHES_FIXTURE/codex/AGENTS.md" "$CODEX_TARGET/AGENTS.md" \
  || fail 'AGENTS.md de Codex no fue restaurado desde patches'
for a in sdd-apply sdd-archive sdd-design sdd-explore sdd-init sdd-onboard sdd-propose sdd-spec sdd-tasks sdd-verify; do
  [ "$(grep -c 'Step 0 — resolve the artifact store' "$TARGET/agents/$a.md")" = 1 ] || fail "Step 0 no está exactamente una vez en $a"
done
! grep -q 'Step 0 — resolve the artifact store' "$TARGET/agents/sdd-research.md" || fail 'Step 0 se coló en sdd-research'
[ "$(grep -c 'Module DoD in task generation' "$TARGET/agents/sdd-tasks.md")" = 1 ] || fail 'Module DoD ausente o duplicado en sdd-tasks'
grep -q '^1\. Read spec artifact' "$TARGET/agents/sdd-tasks.md" || fail 'Module DoD pisó la lista numerada de sdd-tasks'
for a in sdd-apply sdd-init sdd-onboard jd-fix-agent; do
  [ "$(grep -c '## Code routing (MANDATORY' "$TARGET/agents/$a.md")" = 1 ] || fail "Code routing ausente o duplicado en $a"
done
for a in sdd-apply sdd-init sdd-onboard sdd-verify; do
  [ "$(grep -c '## Background wait discipline' "$TARGET/agents/$a.md")" = 1 ] || fail "Background wait ausente o duplicado en $a"
done
! grep -q '## Code routing' "$TARGET/agents/sdd-design.md" || fail 'Code routing se coló en sdd-design'
[ "$(grep -c '## Archive Gate (MANDATORY' "$TARGET/agents/sdd-archive.md")" = 1 ] || fail 'Archive Gate ausente o duplicado'
grep -q 'ONLY after the Archive Gate above passed' "$TARGET/agents/sdd-archive.md" || fail 'status gate ausente en sdd-archive'
# Orden: Code routing antes que Background wait, ambos antes de ## Instructions.
awk '/## Code routing/{c=NR} /## Background wait/{b=NR} /^## Instructions/{i=NR} END{exit !(c && b && i && c<b && b<i)}' "$TARGET/agents/sdd-apply.md" \
  || fail 'orden de bloques incorrecto en sdd-apply'

# (3) idempotencia: segunda pasada sin cambios y --check limpio.
settings_hash="$(shasum -a 256 "$TARGET/settings.json" | cut -d' ' -f1)"
config_hash="$(shasum -a 256 "$CODEX_TARGET/config.toml" | cut -d' ' -f1)"
bash "$SCRIPT" --target "$TARGET" --codex-target "$CODEX_TARGET" --patches "$PATCHES_FIXTURE" --codex-routing >"$TMP/pass2.log"
grep -q 'nada que hacer' "$TMP/pass2.log" || fail "segunda pasada volvió a cambiar algo: $(cat "$TMP/pass2.log")"
[ "$settings_hash" = "$(shasum -a 256 "$TARGET/settings.json" | cut -d' ' -f1)" ] || fail 'segunda pasada cambió settings.json'
[ "$config_hash" = "$(shasum -a 256 "$CODEX_TARGET/config.toml" | cut -d' ' -f1)" ] || fail 'segunda pasada cambió config.toml'
bash "$SCRIPT" --target "$TARGET" --codex-target "$CODEX_TARGET" --patches "$PATCHES_FIXTURE" --codex-routing --check --quiet || fail '--check reporta drift tras aplicar'

# (5) modo sin Codex: retira el bloque sin destruir el archivo.
before="$(wc -l < "$TARGET/agents/sdd-apply.md")"
bash "$SCRIPT" --target "$TARGET" --codex-target "$CODEX_TARGET" --patches "$PATCHES_FIXTURE" --no-codex-routing >/dev/null
after="$(wc -l < "$TARGET/agents/sdd-apply.md")"
! grep -q '## Code routing' "$TARGET/agents/sdd-apply.md" || fail 'Code routing no fue retirado'
grep -q '## Background wait discipline' "$TARGET/agents/sdd-apply.md" || fail 'retirar Code routing borró Background wait'
grep -q '^## Instructions' "$TARGET/agents/sdd-apply.md" || fail 'retirar Code routing borró Instructions'
[ "$after" -lt "$before" ] && [ "$after" -gt $(( before / 2 )) ] || fail "tamaño sospechoso tras retirar el bloque: $before -> $after"
bash "$SCRIPT" --target "$TARGET" --codex-target "$CODEX_TARGET" --patches "$PATCHES_FIXTURE" --no-codex-routing --check --quiet || fail '--check sin Codex reporta drift'

printf 'agent patches contract: OK (fixture gentle-ai %s)\n' "$(gentle-ai --version 2>/dev/null | tr -d '\n')"
