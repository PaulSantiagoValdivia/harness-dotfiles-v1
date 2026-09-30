#!/usr/bin/env bash
# Suite de contrato de route-code-to-codex.sh — "Codex escribe TODO el código".
#
# Existe por los DOS incidentes del 2026-08-30/31:
#   1. Un ;; huérfano dejó el hook sin parsear → bloqueó Bash/Edit/Write de
#      toda la sesión, incluidas las herramientas para repararlo.
#   2. SAFE_RE eximía /.claude/ y los worktrees de triangulación viven en
#      .claude/worktrees/<slug>/ → Claude escribió código de producto directo
#      en las triangulaciones del usuario, sin routing a Codex.
#
# Este archivo ES el contrato: cada agujero descubierto se agrega como caso.
# Lo corre validate-enforcement.sh en cada SessionStart; también correlo a
# mano SIEMPRE después de editar el hook:  bash ~/.claude/hooks/tests/route-hook-tests.sh

set -uo pipefail

# Por defecto prueba el hook hermano del checkout (o de ~/.claude cuando esta
# suite ya está instalada); así `bash files/.../route-hook-tests.sh` no depende
# de que el HOME tenga todavía la revisión más nueva.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${1:-$HOOK_DIR/../route-code-to-codex.sh}"
fails=0
total=0

# 0) Precondiciones duras: existe y parsea. Sin esto no hay enforcement.
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — el enforcement Codex-escribe-código NO está activo." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis — bloquea TODOS los tool calls de la sesión." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi

# Los casos base miden el DEFAULT (Codex escribe). Si la máquina real tiene el
# flag de "Codex sin créditos" puesto, el hook deja pasar código y estos casos
# darían rojo por estado de la máquina, no por un agujero — pasó el 2026-09-03,
# apenas se activó el fallback la suite entera se puso en rojo. Por eso el
# default se mide SIEMPRE contra un flag inexistente; el fallback tiene sus
# propios casos abajo, con el flag inyectado a mano.
FLAG_NULO="$(mktemp -u)"   # ruta que no existe, a propósito

check() { # nombre payload exit_esperado
  local rc
  printf '%s' "$2" | CODEX_SIN_CREDITOS_FLAG="$FLAG_NULO" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  total=$((total+1))
  if [ "$rc" != "$3" ]; then
    fails=$((fails+1))
    echo "FALLA: $1 (exit=$rc esperado=$3)" >&2
  fi
}

# jq arma los payloads: escapa comillas, pipes y slashes de verdad. La
# versión anterior usaba sed y generaba JSON inválido con \" adentro →
# el hook (fail-open ante JSON roto) devolvía 0 y el test daba falso FALLA.
w(){ jq -cn --arg p "$1" '{tool_name:"Write",tool_input:{file_path:$p}}'; }
e(){ jq -cn --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p}}'; }
b(){ jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

# ── Código de producto: SIEMPRE bloqueado (Codex lo escribe) ──
check "Write código repo normal"        "$(w /repo/src/app.ts)" 2
check "Edit código repo normal"         "$(e /repo/lib/main.dart)" 2
check "Write código python"             "$(w /repo/api/views.py)" 2
# Incidente #2: worktrees de triangulación bajo .claude/worktrees/
check "código en worktree triangulate"  "$(w /srv/repos/x/.claude/worktrees/triangulate-demo/functions/src/city.service.ts)" 2
check "código en worktree SDD"          "$(e /repo/.claude/worktrees/shared-contract-types/src/types/city.ts)" 2
check "Bash sed -i código en worktree"  "$(b 'sed -i "" s/a/b/ /repo/.claude/worktrees/t-x/lib/main.dart')" 2
# Escrituras por Bash (v1 del hook no las cubría)
check "Bash sed -i código"              "$(b 'sed -i "" s/a/b/ /repo/api/views.py')" 2
check "Bash heredoc a .go"              "$(b 'cat > /repo/cmd/main.go <<EOF')" 2
check "Bash tee a .tsx"                 "$(b 'echo x | tee /repo/src/Btn.tsx')" 2
# Un `cd` literal solo exime escrituras relativas dentro del scratchpad; un
# repo de producto sigue bloqueado y una variable sin expandir también.
check "Bash scratchpad literal + redirección relativa" \
  "$(b 'cd /private/tmp/claude-route-tests/session/scratchpad && echo x > x.go')" 0
check "Bash scratchpad literal + target quoted" \
  "$(b 'cd /private/tmp/claude-route-tests/session/scratchpad && echo x > "x.go"')" 0
check "Bash repo literal + target quoted" \
  "$(b 'cd /repo && echo x > "x.go"')" 2
check "Bash repo literal + tee target quoted" \
  "$(b 'cd /repo && echo x | tee "x.go"')" 2
check "Bash scratchpad literal + redirección con punto y coma" \
  "$(b 'cd /private/tmp/claude-route-tests/session/scratchpad; echo x > x.go')" 0
check "Bash scratchpad + traversal relativa" \
  "$(b 'cd /private/tmp/claude-route-tests/session/scratchpad && echo x > ../repo.go')" 2
check "Bash repo literal + redirección relativa" \
  "$(b 'cd /repo && echo x > x.go')" 2
check "Bash cd posterior cambia contexto" \
  "$(b 'cd /private/tmp/claude-route-tests/session/scratchpad && cd /repo && echo x > x.go')" 2
multiline_later_cd="$(printf '%s\n' \
  'cd /private/tmp/claude-route-tests/session/scratchpad && echo pre' \
  'cd /repo && echo x > x.go')"
check "Bash cd posterior en línea multilinea" "$(b "$multiline_later_cd")" 2
multiline_split_cd="$(printf '%s\n' \
  'cd /private/tmp/claude-route-tests/session/scratchpad &&' \
  'cd /repo && echo x > x.go')"
check "Bash cd posterior multilinea tras &&" "$(b "$multiline_split_cd")" 2
check "Bash cd con variable + redirección relativa" \
  "$(b 'cd $S && echo x > x.go')" 2
check "Bash redirección relativa sin cd"              "$(b 'echo x > x.go')" 2

# Incidente #3: código real dentro de dirs .claude/ de repo (qa-sweep)
check "playwright.config.ts en .claude/" "$(w /repo/.claude/qa-sweep/playwright.config.ts)" 2
check "spec.ts en .claude/qa-sweep"      "$(w /repo/.claude/qa-sweep/specs/t1.spec.ts)" 2
check "script .sh en .claude/ de repo"   "$(w /repo/.claude/scripts/deploy.sh)" 2
check "settings.local.json (config)"     "$(e /repo/.claude/settings.local.json)" 0
check "SKILL.md en .claude/ repo"        "$(w /repo/.claude/skills/x/SKILL.md)" 0
# Rutas del HOME via $HOME, no /Users/<alguien>: el hook exime "$HOME/.claude/" y el
# test tiene que valer en cualquier máquina (gap visto en HOME limpio, 2026-09-03).
check "workflows .js del HOME harness"   "$(e "$HOME"/.claude/workflows/codex-build.js)" 0
check "hook .sh del HOME harness"        "$(e "$HOME"/.claude/hooks/foo.sh)" 0

# ── Codex sin launcher: bloqueado (incidente de cuelgues por shim cmux) ──
check "codex exec directo"              "$(b 'codex exec --sandbox workspace-write -m gpt-6-astra fix')" 2
check "/usr/local/bin/codex exec"       "$(b '/usr/local/bin/codex exec fix')" 2

# ── Vías legítimas: SIEMPRE pasan ──
check "codex-run launcher"              "$(b '~/.claude/bin/codex-run exec -m gpt-6-astra fix')" 0
check "grep con codex en texto"         "$(b 'grep -rn "codex exec" ~/.claude/skills/')" 0
check "git status"                      "$(b 'git status')" 0
check "openspec repo normal"            "$(w /repo/openspec/changes/x/spec.md)" 0
check "openspec DENTRO de worktree"     "$(w /repo/.claude/worktrees/shared-contract-types/openspec/changes/x/tasks.md)" 0
check ".claude/skills dentro worktree"  "$(w /repo/.claude/worktrees/t-x/.claude/skills/foo/SKILL.md)" 0
check "markdown dentro de worktree"     "$(e /repo/.claude/worktrees/t-x/README.md)" 0
check "config global ~/.claude"         "$(w "$HOME"/.claude/agents/x.md)" 0
check "hooks del harness"               "$(e "$HOME"/.claude/hooks/foo.sh)" 0
check "markdown repo normal"            "$(e /repo/README.md)" 0
check "Read nunca bloquea"              '{"tool_name":"Read","tool_input":{"file_path":"/repo/src/app.ts"}}' 0
check "input vacío fail-open"           '' 0

# ── Codex sin créditos (regla 2026-09-03): con el flag fresco, Claude escribe ──
# El flag se inyecta por CODEX_SIN_CREDITOS_FLAG para no tocar el HOME real.
flag_dir="$(mktemp -d)"
touch "$flag_dir/fresco"
touch -t 202001010000 "$flag_dir/viejo"
check_flag() { # nombre flag payload exit_esperado
  local rc
  printf '%s' "$3" | CODEX_SIN_CREDITOS_FLAG="$2" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  total=$((total+1))
  if [ "$rc" != "$4" ]; then
    fails=$((fails+1))
    echo "FALLA: $1 (exit=$rc esperado=$4)" >&2
  fi
}
check_flag "flag fresco: Write código pasa"      "$flag_dir/fresco"   "$(w /repo/src/app.ts)" 0
check_flag "flag fresco: sed -i código pasa"     "$flag_dir/fresco"   "$(b 'sed -i "" s/a/b/ /repo/api/views.py')" 0
check_flag "flag caducado: sigue bloqueando"     "$flag_dir/viejo"    "$(w /repo/src/app.ts)" 2
check_flag "flag inexistente: sigue bloqueando"  "$flag_dir/no-existe" "$(w /repo/src/app.ts)" 2
# El fallback NO apaga el resto del hook. `codex exec` sin launcher se cuelga por
# el shim de cmux tenga o no tenga cuota la cuenta: sigue bloqueado con el flag
# puesto. (Primer intento del fallback: un `exit 0` temprano que apagaba esto.)
check_flag "flag fresco: codex exec directo SIGUE bloqueado" "$flag_dir/fresco" \
  "$(b 'codex exec --sandbox workspace-write -m gpt-6-astra fix')" 2
check_flag "flag fresco: markdown pasa igual"    "$flag_dir/fresco"   "$(e /repo/README.md)" 0
rm -rf "$flag_dir"


# 2026-09-09 pinned Astra for every coding redirect after trying Sol; 2026-09-10
# confirmed that pin was just an experiment (no documented quality incident) and
# replaced it with per-task selection (CLAUDE.md § "Selección de modelo Codex").
# Guard the NEW contract instead: redirects must show the <astra|sol> choice
# placeholder, never hardcode either real model slug (regression in either
# direction — always-Astra burned quota, a silent revert to always-Sol would
# repeat 2026-09-09's untested guess).
if grep -q -- "-m gpt-6-astra \"" "$HOOK" || grep -q -- "-m gpt-5.6-sol \"" "$HOOK"; then
  echo "FAIL: coding redirects must offer astra|sol choice, not hardcode either model" >&2
  exit 1
fi
if ! grep -q -- '-m <astra|sol>' "$HOOK"; then
  echo "FAIL: coding redirects must show the <astra|sol> selection placeholder" >&2
  exit 1
fi

if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails/$total casos fallan — el enforcement Codex-escribe-código tiene agujeros." >&2
  exit 1
fi
echo "OK: $total/$total casos del contrato de routing pasan."
exit 0
