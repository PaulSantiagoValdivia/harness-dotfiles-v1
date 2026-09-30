#!/usr/bin/env bash
# apply-agent-patches.sh — re-aplica los parches del harness sobre los agents y
# skills que GENERA gentle-ai (`gentle-ai install` / `sync` los regenera y se
# lleva cualquier edición a mano; pasó el 2026-08-28).
#
# Por qué existe (auditoría 2026-09-03): gentle-ai 3.7 declara los tools de
# memoria con AMBOS prefijos: `mcp__plugin_engram_engram__*` (plugin) y
# `mcp__engram__*` (directo). Por eso este parche los convierte al prefijo
# directo y los deduplica. Los demás bloques nacen de incidentes reales
# documentados en cada archivo de patches/agents/*.md.
#
# Uso:
#   apply-agent-patches.sh                 # aplica sobre ~/.claude (idempotente)
#   apply-agent-patches.sh --check         # no toca nada; exit 1 si hay drift
#   apply-agent-patches.sh --quiet         # solo habla si cambió algo (SessionStart)
#   apply-agent-patches.sh --codex-routing | --no-codex-routing
#       Fuerza el bloque "Code routing" (Codex escribe el código). Sin flag se
#       autodetecta: presente si settings.json registra route-code-to-codex.
#   apply-agent-patches.sh --target DIR --patches DIR   # para tests
#
# Fail-open: siempre exit 0 salvo en --check. Un parcheador roto no debe impedir
# trabajar, solo AVISAR.
set -uo pipefail

TARGET="$HOME/.claude"
CODEX_TARGET="$HOME/.codex"
PATCHES="$HOME/.claude/patches"
CODEX=""
QUIET=0
CHECK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift ;;
    --codex-target) CODEX_TARGET="$2"; shift ;;
    --patches) PATCHES="$2"; shift ;;
    --codex-routing) CODEX=1 ;;
    --no-codex-routing) CODEX=0 ;;
    --quiet) QUIET=1 ;;
    --check) CHECK=1 ;;
    *) echo "apply-agent-patches: flag desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done

AG="$TARGET/agents"
PA="$PATCHES/agents"
changed=0
drift=0
log()  { [ "$QUIET" = 1 ] || printf '[agent-patches] %s\n' "$*"; }
note() { printf '[agent-patches] %s\n' "$*"; }   # siempre visible
warn() { printf '[agent-patches] AVISO: %s\n' "$*" >&2; }

[ -d "$AG" ] || { warn "no existe $AG — ¿corrió gentle-ai install?"; exit 0; }
[ -d "$PA" ] || { warn "no existe $PA — faltan los parches versionados"; exit 0; }

if [ -z "$CODEX" ]; then
  if grep -q 'route-code-to-codex' "$TARGET/settings.json" 2>/dev/null; then CODEX=1; else CODEX=0; fi
fi

mark() { changed=1; drift=1; }

# Reemplaza el archivo solo si --check está apagado. Un tmp vacío o más chico
# que la mitad del original es un awk roto, no un parche: se descarta y se avisa
# (la primera versión de este script vació cuatro agents por un regex mal
# escapado; esta guarda existe por eso).
commit_file() { # commit_file <tmp> <dest>
  local tmp="$1" dest="$2" a b
  if [ "$CHECK" = 1 ]; then rm -f "$tmp"; return 0; fi
  a="$(wc -c < "$tmp" | tr -d ' ')"; b="$(wc -c < "$dest" | tr -d ' ')"
  if [ "$a" -eq 0 ] || [ $(( a * 2 )) -lt "$b" ]; then
    warn "resultado sospechoso para $(basename "$dest") ($a bytes vs $b) — no se aplica"
    rm -f "$tmp"; return 1
  fi
  mv "$tmp" "$dest"
}

# ── 1. Tool names: plugin → MCP directo ─────────────────────────────────────
for f in "$AG"/*.md; do
  [ -f "$f" ] || continue
  if grep -q 'mcp__plugin_engram_engram__' "$f"; then
    mark; log "tools → MCP directo: $(basename "$f")"
    if [ "$CHECK" = 0 ]; then
      tmp="$(mktemp)"; sed 's/mcp__plugin_engram_engram__/mcp__engram__/g' "$f" > "$tmp" && mv "$tmp" "$f"
    fi
  fi
done

# ── 1b. Tools directos duplicados tras la conversión plugin → MCP ───────────
# gentle-ai 3.7 puede renderizar el prefijo plugin y el nombre directo en la
# misma línea. La conversión de arriba deja ambos nombres directos; conserva
# solo la primera aparición de cada tool para que el parche sea idempotente.
for f in "$AG"/*.md; do
  [ -f "$f" ] || continue
  if awk '
    /^tools:/ {
      n = split(substr($0, 7), item, ",")
      delete seen
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", item[i])
        if (item[i] != "" && seen[item[i]]++) { found = 1 }
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$f"; then
    mark; log "tools duplicados → $(basename "$f")"
    if [ "$CHECK" = 0 ]; then
      tmp="$(mktemp)"
      awk '
        function trim(s) {
          sub(/^[[:space:]]+/, "", s)
          sub(/[[:space:]]+$/, "", s)
          return s
        }
        /^tools:/ {
          n = split(substr($0, 7), item, ",")
          delete seen
          output = ""
          for (i = 1; i <= n; i++) {
            value = trim(item[i])
            if (value != "" && !seen[value]++) {
              if (output == "") output = "tools: " value
              else output = output ", " value
            }
          }
          print output
          next
        }
        { print }
      ' "$f" > "$tmp"
      commit_file "$tmp" "$f"
    fi
  fi
done

# ── 2. sdd-archive necesita Bash (git mv del archive; fix 2026-09-01) ───────
f="$AG/sdd-archive.md"
if [ -f "$f" ] && grep -q '^tools:' "$f" && ! grep -qE '^tools:.*(^|[ ,])Bash([ ,]|$)' "$f"; then
  mark; log "tools + Bash: sdd-archive.md"
  if [ "$CHECK" = 0 ]; then
    tmp="$(mktemp)"; sed -E '/^tools:/ s/, mcp__/, Bash, mcp__/' "$f" > "$tmp" && mv "$tmp" "$f"
  fi
fi

# ── 2b. Code routing ya insertado: astra fijo → <model> leído de tasks.md ──
# insert_block es idempotente por MARCADOR de sección, no por contenido: si el
# bloque "Code routing" ya está insertado en un agent, editar code-routing.md
# no lo vuelve a copiar. Este reemplazo dirigido corrige el `-m gpt-6-astra`
# fijo (causa real de consumo, confirmada por el usuario 2026-09-10) ya
# insertado en los agents que lo tienen, sin duplicar el bloque.
for a in sdd-apply sdd-init sdd-onboard jd-fix-agent; do
  f="$AG/$a.md"
  [ -f "$f" ] || continue
  if grep -qF -- '-m gpt-6-astra "<bounded, precise instruction>"' "$f"; then
    mark; log "code-routing: -m <model> (tasks.md) → $(basename "$f")"
    if [ "$CHECK" = 0 ]; then
      tmp="$(mktemp)"
      awk '
        /-m gpt-6-astra "<bounded, precise instruction>"/ {
          sub(/-m gpt-6-astra/, "-m <model>")
          print
          print ""
          print "`<model>` is the REAL Codex slug, not the short name: `gpt-5.6-sol` when the"
          print "task'"'"'s `[codex: sol|astra]` tag in `tasks.md` says `sol`, `gpt-6-astra` when it"
          print "says `astra` (`sdd-tasks` already set the tag with full spec/design context)."
          print "`codex-run` does not alias short names — `-m sol` is an invalid model and Codex"
          print "will reject it. No tag or no signal: default to `gpt-6-astra` — a wrong"
          print "`gpt-5.6-sol` costs a redo, which costs more than the `sol` saved (CLAUDE.md §"
          print "\"Selección de modelo Codex\")."
          next
        }
        { print }' "$f" > "$tmp"
      commit_file "$tmp" "$f"
    fi
  fi
done

# ── 2b-bis. Corrige el bug del 2b anterior: `-m sol` no es un modelo real ───
# codex-run no alias-ea nombres cortos; el slug real es gpt-5.6-sol/gpt-6-astra
# (verificado en models_cache.json). El texto insertado por el 2b de una
# versión previa decía "`<model>` is `sol` or `astra`" literal — un sdd-apply
# que lo siguiera al pie de la letra mandaría `-m sol` y Codex lo rechazaría.
for f in "$AG"/*.md; do
  [ -f "$f" ] || continue
  if grep -qF -- '`<model>` is `sol` or `astra`' "$f"; then
    mark; log "code-routing: <model> → slug real (gpt-5.6-sol/gpt-6-astra) en $(basename "$f")"
    if [ "$CHECK" = 0 ]; then
      tmp="$(mktemp)"
      awk '
        /^`<model>` is `sol` or `astra`/ { skip = 1 }
        skip && /saved \(CLAUDE\.md § "Selección de modelo Codex"\)\.$/ {
          print "`<model>` is the REAL Codex slug, not the short name: `gpt-5.6-sol` when the"
          print "task'"'"'s `[codex: sol|astra]` tag in `tasks.md` says `sol`, `gpt-6-astra` when it"
          print "says `astra` (`sdd-tasks` already set the tag with full spec/design context)."
          print "`codex-run` does not alias short names — `-m sol` is an invalid model and Codex"
          print "will reject it. No tag or no signal: default to `gpt-6-astra` — a wrong"
          print "`gpt-5.6-sol` costs a redo, which costs more than the `sol` saved (CLAUDE.md §"
          print "\"Selección de modelo Codex\")."
          skip = 0
          next
        }
        skip { next }
        { print }' "$f" > "$tmp"
      commit_file "$tmp" "$f"
    fi
  fi
done

# ── 2c. Cosmético: "then verify" quedó en minúscula tras el 2b de arriba ────
for f in "$AG"/*.md; do
  [ -f "$f" ] || continue
  if grep -qF -- '`[codex: sol|astra]`' "$f" && grep -qx -- 'then verify with `git diff` yourself before marking anything done. You still' "$f"; then
    mark; log "cosmético: Then verify → $(basename "$f")"
    if [ "$CHECK" = 0 ]; then
      tmp="$(mktemp)"
      sed 's/^then verify with `git diff`/Then verify with `git diff`/' "$f" > "$tmp"
      commit_file "$tmp" "$f"
    fi
  fi
done

# ── Helpers de inserción por ancla (idempotentes por marcador) ──────────────
# insert_block <agent> <marker-fixed-string> <mode> <anchor-regex> <patchfile>
#   mode=after : ancla, línea en blanco, bloque      (el blanco existente sigue)
#   mode=before: bloque, línea en blanco, ancla
#   sin ancla  : se anexa al final con una línea en blanco antes
insert_block() {
  local file="$1" marker="$2" mode="$3" anchor="$4" patch="$5" tmp
  [ -f "$file" ] || return 0
  [ -f "$patch" ] || { warn "falta el parche $patch"; return 0; }
  grep -qF -- "$marker" "$file" && return 0
  mark; log "+ $(basename "$patch" .md) → $(basename "$file")"
  [ "$CHECK" = 1 ] && return 0
  tmp="$(mktemp)"
  if grep -qE -- "$anchor" "$file"; then
    awk -v pf="$patch" -v anchor="$anchor" -v mode="$mode" '
      function emit() { while ((getline l < pf) > 0) print l; close(pf) }
      !done && $0 ~ anchor {
        if (mode == "before") { emit(); print ""; print; done = 1; next }
        print; print ""; emit(); done = 1; next
      }
      { print }' "$file" > "$tmp"
  else
    { cat "$file"; echo; cat "$patch"; } > "$tmp"
  fi
  commit_file "$tmp" "$file"
}

# remove_section <agent> <heading-prefix (texto fijo)>: borra desde la línea que
# EMPIEZA con ese texto hasta el próximo "## " (excluido). Texto fijo, no regex:
# los headings llevan paréntesis y awk -v los reinterpreta.
remove_section() {
  local file="$1" heading="$2" tmp
  [ -f "$file" ] || return 0
  grep -qF -- "$heading" "$file" || return 0
  mark; log "- sección '$heading' ← $(basename "$file")"
  [ "$CHECK" = 1 ] && return 0
  tmp="$(mktemp)"
  awk -v h="$heading" '
    index($0, h) == 1 { skip = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }' "$file" | cat -s > "$tmp"
  commit_file "$tmp" "$file"
}

# ── 3. Step 0: OpenSpec es el store por defecto (10 agents SDD) ─────────────
for a in sdd-apply sdd-archive sdd-design sdd-explore sdd-init sdd-onboard sdd-propose sdd-spec sdd-tasks sdd-verify; do
  insert_block "$AG/$a.md" 'Step 0 — resolve the artifact store' after '^Also read shared conventions' "$PA/step0-openspec.md"
done

# ── 4. Module DoD en la generación de tareas ────────────────────────────────
insert_block "$AG/sdd-tasks.md" 'Module DoD in task generation' after 'check the OpenSpec path first\.$' "$PA/module-dod.md"

# ── 5. Code routing a Codex (opt-in) — va ANTES de bg-wait para quedar primero
for a in sdd-apply sdd-init sdd-onboard jd-fix-agent; do
  if [ "$CODEX" = 1 ]; then
    insert_block "$AG/$a.md" '## Code routing (MANDATORY' before '^## Instructions' "$PA/code-routing.md"
  else
    remove_section "$AG/$a.md" '## Code routing (MANDATORY'
  fi
done

# ── 6. Disciplina de espera en background ───────────────────────────────────
for a in sdd-apply sdd-init sdd-onboard sdd-verify; do
  insert_block "$AG/$a.md" '## Background wait discipline' before '^## Instructions' "$PA/bg-wait.md"
done

# ── 7. Archive Gate: `done` solo con prueba en disco ────────────────────────
insert_block "$AG/sdd-archive.md" '## Archive Gate (MANDATORY' before '^## Result Contract' "$PA/archive-gate.md"
f="$AG/sdd-archive.md"
if [ -f "$f" ] && grep -qF -- '- `status`: `done` | `blocked` | `partial`' "$f" && ! grep -qF 'ONLY after the Archive Gate' "$f"; then
  mark; log "status gate → sdd-archive.md"
  if [ "$CHECK" = 0 ]; then
    tmp="$(mktemp)"
    sed 's/^- `status`: `done` | `blocked` | `partial`$/& — `done` ONLY after the Archive Gate above passed/' "$f" > "$tmp"
    commit_file "$tmp" "$f"
  fi
fi

# ── 8. Skill sdd-tasks: overlay completo, tag de modelo Codex por tarea ────
# Regla del usuario 2026-09-10: elegir astra/sol por tarea DESPUÉS de que
# sdd-apply ya está corriendo (sin spec/design cargados) es peor decisión que
# elegirlo en sdd-tasks, que sí tiene el contexto completo. Mismo mecanismo
# de reemplazo completo guardado por hash, aplicado a ambos
# clientes porque gentle-ai genera el mismo SKILL.md para los dos.
FRESH_SDD_TASKS_SHA='0b5d4f801450fec790a6885515055f2767d49c06f89a6a3ff4bcdd9475cf2391'
ov="$PATCHES/skills/sdd-tasks/SKILL.md"
for client_home in "$TARGET" "$CODEX_TARGET"; do
  sk="$client_home/skills/sdd-tasks/SKILL.md"
  [ -f "$sk" ] && [ -f "$ov" ] || continue
  cur="$(shasum -a 256 "$sk" | cut -d' ' -f1)"
  ovs="$(shasum -a 256 "$ov" | cut -d' ' -f1)"
  if [ "$cur" = "$ovs" ]; then
    :
  elif [ "$cur" = "$FRESH_SDD_TASKS_SHA" ]; then
    mark; log "overlay skills/sdd-tasks/SKILL.md (Codex Model Hint) en $client_home"
    [ "$CHECK" = 0 ] && cp "$ov" "$sk"
  else
    warn "$sk no es el template 3.7 ni el overlay: gentle-ai cambió. Revisar $ov antes de aplicarlo."
  fi
done

# ── 9. Regresiones post-sync: hooks por prompt y Context7 ────────────────────
# gentle-ai puede volver a registrar skill-registry durante UserPromptSubmit;
# el refresh debe vivir en SessionStart para no pagar un proceso por prompt.
settings="$TARGET/settings.json"
if [ -f "$settings" ] && jq -e '
  [ .hooks.UserPromptSubmit[]?.hooks[]?
    | ((.command // "") | tostring | contains("skill-registry"))
  ] | any
' "$settings" >/dev/null 2>&1; then
  mark; log "skill-registry fuera de UserPromptSubmit"
  if [ "$CHECK" = 0 ]; then
    tmp="$(mktemp)"
    jq '
      .hooks.UserPromptSubmit |= map(
        .hooks |= map(
          select(((.command // "") | tostring | contains("skill-registry")) | not)
        )
        | select((.hooks | length) > 0)
      )
    ' "$settings" > "$tmp" && commit_file "$tmp" "$settings"
    rm -f "$tmp"
  fi
fi

# Context7 ya no debe depender del transporte HTTP remoto: Codex lo ejecuta por
# stdio con npx. El estado de otras tablas TOML queda intacto.
config="$CODEX_TARGET/config.toml"
if [ -f "$config" ] && awk '
  /^\[mcp_servers\.context7\]$/ { in_context7 = 1; next }
  /^\[/ { in_context7 = 0 }
  in_context7 && /^[[:space:]]*url[[:space:]]*=[[:space:]]*"https:\/\/mcp\.context7\.com\/mcp"[[:space:]]*$/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$config"; then
  mark; log "Context7 URL → stdio en $config"
  if [ "$CHECK" = 0 ]; then
    tmp="$(mktemp)"
    awk '
      /^\[mcp_servers\.context7\]$/ { in_context7 = 1; print; next }
      /^\[/ { in_context7 = 0 }
      in_context7 && /^[[:space:]]*url[[:space:]]*=[[:space:]]*"https:\/\/mcp\.context7\.com\/mcp"[[:space:]]*$/ {
        print "command = \"npx\""
        print "args = [\"-y\", \"@upstash/context7-mcp@latest\"]"
        next
      }
      { print }
    ' "$config" > "$tmp" && commit_file "$tmp" "$config"
    rm -f "$tmp"
  fi
fi

# gentle-ai 3.7 agrega profundidad y cantidad total de threads bajo [agents].
# El harness controla la concurrencia con max_concurrent_threads_per_session y
# no permite recursión; se quitan solo esas dos claves de esa tabla exacta.
if [ -f "$config" ] && awk '
  /^\[agents\][[:space:]]*$/ { in_agents = 1; next }
  /^\[/ { in_agents = 0 }
  in_agents && /^[[:space:]]*(max_depth|max_threads)[[:space:]]*=[[:space:]]*[0-9]+([[:space:]]*#.*)?$/ { found = 1 }
  END { exit(found ? 0 : 1) }
' "$config"; then
  mark; log "límites recursivos fuera de [agents] en $config"
  if [ "$CHECK" = 0 ]; then
    tmp="$(mktemp)"
    awk '
      /^\[agents\][[:space:]]*$/ { in_agents = 1; print; next }
      /^\[/ { in_agents = 0 }
      in_agents && /^[[:space:]]*(max_depth|max_threads)[[:space:]]*=[[:space:]]*[0-9]+([[:space:]]*#.*)?$/ { next }
      { print }
    ' "$config" > "$tmp" && commit_file "$tmp" "$config"
    rm -f "$tmp"
  fi
fi

# gentle-ai también reemplaza AGENTS.md de Codex. Restaura la copia del
# harness solo cuando bootstrap dejó una fuente local en patches/codex.
codex_agents_patch="$PATCHES/codex/AGENTS.md"
codex_agents="$CODEX_TARGET/AGENTS.md"
if [ -f "$codex_agents_patch" ] && ! cmp -s "$codex_agents_patch" "$codex_agents"; then
  mark; log "AGENTS.md del harness → $codex_agents"
  if [ "$CHECK" = 0 ]; then
    mkdir -p "$CODEX_TARGET"
    cp "$codex_agents_patch" "$codex_agents"
  fi
fi

# ── Resultado ───────────────────────────────────────────────────────────────
if [ "$CHECK" = 1 ]; then
  if [ "$drift" = 1 ]; then note "DRIFT: hay parches sin aplicar (correr sin --check)"; exit 1; fi
  log "sin drift"; exit 0
fi
if [ "$changed" = 1 ]; then
  note "parches re-aplicados sobre $AG (codex_routing=$CODEX)"
else
  log "nada que hacer (codex_routing=$CODEX)"
fi
exit 0
