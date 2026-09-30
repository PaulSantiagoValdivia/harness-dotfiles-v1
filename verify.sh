#!/usr/bin/env bash
# verify.sh — checklist de aceptación del harness (PRD §8), parte automatizable.
# Imprime PASS/FAIL por chequeo y termina con exit 1 si algo falló.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=files/shared/lib/worktree-health.sh
source "$REPO_DIR/files/shared/lib/worktree-health.sh"
PASS=0; FAIL=0; WARN=0
ok()   { printf '  \033[0;32mPASS\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  \033[0;31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
warn() { printf '  \033[0;33mWARN\033[0m %s\n' "$1"; WARN=$((WARN+1)); }
info() { printf '  INFO %s\n' "$1"; }
# shellcheck source=files/shared/lib/verification-diagnostics.sh
source "$REPO_DIR/files/shared/lib/verification-diagnostics.sh" || exit 1
verify_receipts_init || exit 1
codex_agents_has_legacy_key() {
  awk '
    /^\[agents\]$/ { in_agents=1; next }
    /^\[/ { in_agents=0 }
    in_agents && /^(max_threads|max_depth)[[:space:]]*=/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$HOME/.codex/config.toml"
}
codex_config_strict_load() {
  # --version y varios subcomandos administrativos no deserializan todo el
  # config. App-server sí lo hace. Un CODEX_HOME temporal evita que el sandbox
  # convierta una configuración válida en falso FAIL por state_5.sqlite.
  local codex_bin="$1" tmp rc
  tmp="$(mktemp -d)" || return 1
  cp "$HOME/.codex/config.toml" "$tmp/config.toml" || { rm -rf "$tmp"; return 1; }
  CODEX_HOME="$tmp" "$codex_bin" app-server --strict-config --listen stdio:// </dev/null
  rc=$?
  rm -rf "$tmp"
  return "$rc"
}

# Rutas de los repos canónicos: salen de triangulate.conf (por máquina), nunca
# hardcodeadas. Gap detectado el 2026-09-03 probando bootstrap.sh en un HOME
# limpio: con las rutas del PO fijas, cualquier otra máquina daba FAIL.
TRIANGULATE_CONF="$HOME/.claude/triangulate.conf"
conf_repo() { # conf_repo back|front|app -> ruta absoluta o vacío
  [ -f "$TRIANGULATE_CONF" ] || return 1
  awk -F= -v k="$1" '$1 == k { print substr($0, index($0, "=") + 1); exit }' "$TRIANGULATE_CONF"
}
triangulate_conf_ready() { # 0 si existe y no tiene las rutas de ejemplo
  [ -f "$TRIANGULATE_CONF" ] && ! grep -q '/Users/<usuario>/' "$TRIANGULATE_CONF"
}
agents_tools_unique() {
  local agent
  for agent in "$HOME"/.claude/agents/*.md; do
    awk '
      /^tools:/ {
        n = split(substr($0, 7), item, ",")
        delete seen
        for (i = 1; i <= n; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", item[i])
          if (item[i] != "" && seen[item[i]]++) exit 1
        }
      }
    ' "$agent" || return 1
  done
}

ARCH="$(uname -m)"
check "verification diagnostics contract" bash "$REPO_DIR/tests/verification_diagnostics_test.sh"
check "friction defaults and safe overlay" python3 "$REPO_DIR/tests/friction_defaults_test.py"
echo "== Binarios =="
for bin in claude codex engram jq gentle-ai; do
  check "'$bin' en PATH" command -v "$bin"
done
for bin in claude codex engram; do
  p="$(command -v "$bin" 2>/dev/null)" || continue
  if file -L "$p" | grep -qE 'shell script|script text executable'; then
    if "$bin" --version >/dev/null 2>&1; then ok "'$bin' launcher de shell funcional"; else bad "'$bin' launcher existe pero no ejecuta"; fi
  elif file -L "$p" | grep -q "$ARCH"; then ok "'$bin' nativo $ARCH"; else bad "'$bin' NO es nativo $ARCH ($(file -L "$p" | cut -d: -f2))"; fi
done
command -v claude >/dev/null 2>&1 && echo "  info: $(claude --version 2>/dev/null)"
command -v codex  >/dev/null 2>&1 && echo "  info: $(codex --version 2>/dev/null)"
command -v engram >/dev/null 2>&1 && echo "  info: $(engram --version 2>/dev/null)"
check "'gentle-ai' en PATH (hook de skill-registry, PRD R14)" command -v gentle-ai
check "Gentle AI acepta instalación Claude Code + Codex" \
  gentle-ai install --scope global --agents claude-code,codex --preset full-gentleman --sdd-mode multi --dry-run
check "gentle-ai versión mayor >= 3" bash -c '
  major="$(gentle-ai --version 2>/dev/null | sed -E "s/[^0-9]*([0-9]+).*/\\1/")"
  [ -n "$major" ] && [ "$major" -ge 3 ]
'
check "gentle-ai install --help conserva --dry-run" bash -c \
  'gentle-ai install --help 2>&1 | grep -Fq -- "--dry-run"'
check "review mode apagado (RDD off)" bash -c \
  'gentle-ai review mode status 2>&1 | grep -Fq "receipt-driven development: off"'
check "bootstrap Codex aislado: clean HOME + rol preservado" \
  bash "$REPO_DIR/tests/bootstrap_codex_config_test.sh"
check "bootstrap conserva el modelo de Claude y descarta la variante [1m]" \
  bash "$REPO_DIR/tests/bootstrap_claude_model_test.sh"
check "contrato de strip-1m-model: saca el sufijo y conserva el modelo elegido" \
  bash "$REPO_DIR/tests/strip_1m_model_test.sh"
check "contrato del presupuesto de contexto (medicion en Stop, lectura sin forks)" \
  bash "$REPO_DIR/tests/context_budget_test.sh"
check "overlay recovery conserva preferencias y rollback (fixtures)" bash "$REPO_DIR/tests/triangulation_recovery_install_test.sh"
check "handoff triangulate resuelve autoridad exacta (fixtures)" bash "$REPO_DIR/tests/triangulate_handoff_test.sh"
check "evidencia triangulate distingue fixtures de coordinación viva" bash "$REPO_DIR/tests/triangulation_evidence_test.sh"
check "launcher triangulate: Git real y transporte simulado" \
  bash "$REPO_DIR/tests/triangulate_launcher_test.sh"
check "Cocoa DevTools descubre, valida y protege tres repositorios" \
  python3 "$REPO_DIR/tests/cocoa_devtools_test.py"
check "Cocoa DevTools expone la auditoría QA consolidada" \
  bash "$REPO_DIR/tests/cocoa_devtools_ui_test.sh"
if triangulate_conf_ready; then
  check "Codex fusiona MCP global/repo y recarga skills sin conflictos" \
    bash "$REPO_DIR/tests/codex_mcp_layering_test.sh"
else
  warn "layering MCP de Codex no verificado: triangulate.conf sin rutas reales (editalo y volvé a correr verify.sh)"
fi
check "parches sobre agents/skills de gentle-ai: aplican, son idempotentes y detectan drift" \
  bash "$REPO_DIR/tests/agent_patches_test.sh"
if [ -x "$HOME/.local/bin/triangulate" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/triangulate" "$HOME/.local/bin/triangulate"; then
  ok "launcher triangulate instalado e idéntico al source"
else
  bad "launcher triangulate ausente o divergente"
fi
if [ -x "$HOME/.local/bin/claude-sessions" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/claude-sessions" "$HOME/.local/bin/claude-sessions"; then
  ok "inspector claude-sessions instalado e idéntico al source"
else
  bad "inspector claude-sessions ausente o divergente"
fi
# Los umbrales de claude-sessions y los del hook context-budget.sh tienen que
# ser los mismos: hasta el 2026-09-03 la herramienta decía PESADA a 120k y el
# hook recién avisaba a 200k, así que la tabla contradecía a la barrera.
check "umbrales de claude-sessions alineados con el hook que mide" \
  bash "$REPO_DIR/tests/claude_sessions_test.sh"
if [ -x "$HOME/.local/bin/memory-snapshot" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/memory-snapshot" "$HOME/.local/bin/memory-snapshot"; then
  ok "memory-snapshot instalado e idéntico al source"
else
  bad "memory-snapshot ausente o divergente"
fi
if [ -x "$HOME/.local/bin/memory-lint" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/memory-lint" "$HOME/.local/bin/memory-lint"; then
  ok "memory-lint instalado e idéntico al source"
else
  bad "memory-lint ausente o divergente"
fi
if [ -x "$HOME/.local/bin/memory-consolidate" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/memory-consolidate" "$HOME/.local/bin/memory-consolidate"; then
  ok "memory-consolidate instalado e idéntico al source"
else
  bad "memory-consolidate ausente o divergente"
fi
# El plist se instala con __HOME__ sustituido; se compara el template renderizado.
if [ -f "$HOME/Library/LaunchAgents/com.cocoa.memory-consolidate.plist" ] && \
   sed "s|__HOME__|$HOME|g" "$REPO_DIR/files/shared/launchd/com.cocoa.memory-consolidate.plist" \
     | cmp -s - "$HOME/Library/LaunchAgents/com.cocoa.memory-consolidate.plist"; then
  ok "LaunchAgent del consolidador instalado e idéntico al source"
else
  bad "LaunchAgent del consolidador ausente o divergente"
fi
if consolidate_state="$(launchctl print "gui/$(id -u)/com.cocoa.memory-consolidate" 2>&1)"; then
  ok "consolidador nocturno cargado en launchd"
else
  warn "consolidador nocturno no cargado en launchd (corré bootstrap.sh o launchctl load): ${consolidate_state%%$'\n'*}"
fi
if [ -x "$HOME/.local/bin/claude-sessions-watch" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/claude-sessions-watch" "$HOME/.local/bin/claude-sessions-watch"; then
  ok "vigilante claude-sessions-watch instalado e idéntico al source"
else
  bad "vigilante claude-sessions-watch ausente o divergente"
fi
# El plist se instala con __HOME__ ya sustituido, así que se compara contra el
# source renderizado y no contra el template.
if [ -f "$HOME/Library/LaunchAgents/com.cocoa.claude-sessions-watch.plist" ] && \
   sed "s|__HOME__|$HOME|g" "$REPO_DIR/files/shared/launchd/com.cocoa.claude-sessions-watch.plist" \
     | cmp -s - "$HOME/Library/LaunchAgents/com.cocoa.claude-sessions-watch.plist"; then
  ok "LaunchAgent del vigilante instalado e idéntico al source"
else
  bad "LaunchAgent del vigilante ausente o divergente"
fi
# Este chequeo daba WARN con el vigilante CARGADO, y el WARN sobrevivió una
# sesión entera porque la explicación plausible ("faltó bootstrap") tapaba la
# real. Listar todos los servicios y filtrar con un grep silencioso es una
# carrera: el filtro corta el pipe apenas encuentra el match, el productor
# muere con SIGPIPE (141) y `set -o pipefail` (línea 4) convierte ese 141 en
# el resultado del `if`. A veces el productor alcanzaba a escribir todo y daba
# PASS; con la salida de launchd de esta máquina, casi nunca.
# Se consulta el label directo: sin pipe no hay carrera, y el estado que se
# lee es el del servicio CARGADO, no el del .plist en disco (el check de
# arriba ya cubre el archivo, y un plist impecable puede tener cargado un
# Program inexistente). El motivo del fallo se muestra en el WARN en vez de
# descartarse: del silencio no se saca ninguna conclusión.
if watch_state="$(launchctl print "gui/$(id -u)/com.cocoa.claude-sessions-watch" 2>&1)"; then
  ok "vigilante cargado en launchd"
else
  warn "vigilante no cargado en launchd (corré bootstrap.sh o launchctl load): ${watch_state%%$'\n'*}"
fi
check "el vigilante avisa sólo por sesiones pesadas Y quietas, y nunca mata nada" \
  bash "$REPO_DIR/tests/claude_sessions_watch_test.sh"
if [ -x "$HOME/.local/bin/devtools" ] && \
   cmp -s "$REPO_DIR/files/shared/bin/devtools" "$HOME/.local/bin/devtools" && \
   cmp -s "$REPO_DIR/files/shared/devtools/cocoa-devtools.py" "$HOME/Documents/cocoa-devtools.py" && \
   cmp -s "$REPO_DIR/files/shared/devtools/cocoa-reference.html" "$HOME/Documents/cocoa-reference.html"; then
  ok "Cocoa DevTools instalado e idéntico al source gestionado"
else
  bad "Cocoa DevTools ausente o divergente"
fi

echo "== Claude Code =="
check "source Claude usa contexto estándar (no modelo 1M)" \
  jq -e '.model == "sonnet"' "$REPO_DIR/files/claude/settings.json"
check "source Claude usa effort medium" \
  jq -e '.effortLevel == "medium"' "$REPO_DIR/files/claude/settings.json"
# Se mira el VALOR de .model, no el texto del archivo. El grep de substring que
# habia antes ('1m') matcheaba cualquier aparicion, y el 2026-09-08 empezo a
# dispararse con el NOMBRE del hook que existe justamente para sacar el sufijo
# (strip-1m-model.sh): el guard se bloqueaba a si mismo. Trampa de AMBITO,
# septima vez: buscar en todo el archivo en vez del campo que corresponde.
if jq -e '(.model // "") | test("\\[1m\\]")' "$REPO_DIR/files/claude/settings.json" >/dev/null 2>&1; then
  bad "source Claude conserva un modelo/contexto 1M"
else
  ok "source Claude no reactiva contexto 1M"
fi
check "~/.claude/CLAUDE.md existe" test -f "$HOME/.claude/CLAUDE.md"
check "CLAUDE.md conserva el bloque ODD" grep -q '### ODD protocol' "$HOME/.claude/CLAUDE.md"
check "settings.json es JSON válido" jq -e . "$HOME/.claude/settings.json"
check "enableWorkflows activado" jq -e '.enableWorkflows == true' "$HOME/.claude/settings.json"
check "workflowKeywordTriggerEnabled activado" jq -e '.workflowKeywordTriggerEnabled == true' "$HOME/.claude/settings.json"
check "hook SessionStart de skill-registry presente (no corre por prompt)" \
  jq -e '[.hooks.SessionStart[].hooks[].command | select(test("skill-registry-refresh"))] | length == 1' "$HOME/.claude/settings.json"
check "skill-registry NO corre en UserPromptSubmit (costaba un refresh por prompt)" \
  jq -e '[(.hooks.UserPromptSubmit // [])[].hooks[].command | select(test("skill-registry"))] | length == 0' "$HOME/.claude/settings.json"
check "presupuesto de contexto con enforcement (context-budget.sh en UserPromptSubmit)" \
  jq -e '[(.hooks.UserPromptSubmit // [])[].hooks[].command | select(test("context-budget"))] | length == 1' "$HOME/.claude/settings.json"
check "parches de agents se re-aplican en SessionStart" \
  jq -e '[.hooks.SessionStart[].hooks[].command | select(test("apply-agent-patches"))] | length == 1' "$HOME/.claude/settings.json"
check "context-budget-measure registrado en Stop (la medicion vive fuera del prompt)" \
  jq -e '[.hooks.Stop[].hooks[].command | select(test("context-budget-measure"))] | length == 1' "$HOME/.claude/settings.json"
# El lector de UserPromptSubmit NO puede invocar binarios externos. Es la razon
# del cambio del 2026-09-08: con 12 forks (5 de ellos jq) una Mac saturada lo
# mataba a los 30s, una y otra vez, con "output discarded". Si alguien vuelve a
# meter un jq/tail/head/date ahi, el timeout vuelve. El check es estructural
# porque el sintoma solo aparece BAJO CARGA, y para entonces ya es tarde.
# El grep va sobre el CODIGO, sin las lineas de comentario: la cabecera del
# hook EXPLICA por que no usa jq, y buscarlo en todo el archivo daba un falso
# positivo por su propia documentacion. Es la trampa de AMBITO de siempre.
ctx_reader_code="$(grep -v '^[[:space:]]*#' "$REPO_DIR/files/claude/hooks/context-budget.sh")"
if printf '%s' "$ctx_reader_code" \
     | grep -Eq '(^|[^-[:alnum:]_])(jq|tail|head|date|sed|awk|cat|grep)[[:space:]]'; then
  bad "context-budget.sh (UserPromptSubmit) volvio a forkear binarios externos"
else
  ok "context-budget.sh (UserPromptSubmit) no forkea binarios externos"
fi
check "hook strip-1m-model registrado en SessionStart" \
  jq -e '[.hooks.SessionStart[].hooks[].command | select(test("strip-1m-model"))] | length == 1' "$HOME/.claude/settings.json"
if grep -Eq '"model": *"[^"]*\[1m\]"' "$HOME/.claude/settings.json"; then
  bad "settings.json instalado usa un modelo [1m] (saca el techo que fuerza la compactación; pedilo por sesión con /model)"
else
  ok "settings.json instalado sin modelo [1m]"
fi

echo "== Hooks del harness =="
ENFORCEMENT_HOOKS="route-code-to-codex.sh validate-enforcement.sh"
# Los dos hooks de enforcement son OPT-IN: una máquina puede no tenerlos y eso
# NO es un fallo. Pero hasta el 2026-09-07 se salteaban por completo, así que
# tampoco se comparaba su contenido cuando SÍ estaban: el trabajo del watchdog
# (2026-09-07) vivió sin versionar con verify en 0 FAIL. Ausente = ok; presente
# y distinto del repo = FAIL, como cualquier otro hook.
for hook in "$REPO_DIR"/files/claude/hooks/*.sh; do
  name="$(basename "$hook")"
  optional=0
  case " $ENFORCEMENT_HOOKS " in *" $name "*) optional=1 ;; esac
  if [ ! -f "$HOME/.claude/hooks/$name" ]; then
    if [ "$optional" = 1 ]; then ok "hook $name ausente (enforcement opt-in, coherente)"
    else bad "hook $name ausente"; fi
    continue
  fi
  if ! bash -n "$HOME/.claude/hooks/$name" 2>/dev/null; then
    bad "hook $name no parsea"
    continue
  fi
  if cmp -s "$hook" "$HOME/.claude/hooks/$name"; then ok "hook $name instalado e idéntico al source"; else bad "hook $name divergente del source (repo y máquina tienen versiones distintas)"; fi
done
# --- >>> contrato: suites de tests versionadas (NO borrar los marcadores: la
# suite verify-tests-drift extrae ESTE tramo y lo mide) ---
# El loop de arriba compara `files/claude/hooks/*.sh`: un glob que NO entra al
# subdirectorio tests/. Y verify.sh CORRE las suites desde $HOME, no desde el
# repo. Hasta el 2026-09-08 una suite ablandada en la máquina daba 648 PASS /
# 0 FAIL con la suite estricta versionada intacta: el recibo lo firmaba un
# artefacto que nadie comparaba. Misma clase de agujero que la exención de los
# hooks de enforcement (2026-09-07).
TESTS_REPO_DIR="$REPO_DIR/files/claude/hooks/tests"
TESTS_HOME_DIR="$HOME/.claude/hooks/tests"
for suite in "$TESTS_REPO_DIR"/*.sh; do
  [ -e "$suite" ] || continue   # sin nullglob, un dir vacío deja el patrón literal
  name="$(basename "$suite")"
  inst="$TESTS_HOME_DIR/$name"
  if [ ! -f "$inst" ]; then
    bad "suite $name ausente en la máquina (verify.sh corre la de la máquina)"
  elif ! bash -n "$inst" 2>/dev/null; then
    bad "suite $name no parsea"
  elif ! cmp -s "$suite" "$inst"; then
    bad "suite $name divergente del source (verify.sh estaría corriendo otra)"
  else
    ok "suite $name instalada e idéntica al source"
  fi
  # Una suite versionada que ningún check ejecuta es un recibo que nadie cobra.
  # El prefijo `hooks/tests/` ancla el nombre: evita que foo-tests.sh haga pasar
  # por enchufada a oo-tests.sh.
  if grep -Fq "hooks/tests/$name" "$REPO_DIR/verify.sh" 2>/dev/null; then
    ok "suite $name enchufada a un check de verify.sh"
  else
    bad "suite $name versionada pero ningún check de verify.sh la corre"
  fi
done
# Dirección inversa: una suite que sólo vive en la máquina es trabajo sin
# versionar y se pierde con el próximo bootstrap (es lo que pasó con el
# watchdog). Los ocultos (.probe-*, .mutate-*) quedan fuera A PROPÓSITO: son
# scratch de una sesión y el glob de bash no matchea dotfiles.
for inst in "$TESTS_HOME_DIR"/*.sh; do
  [ -e "$inst" ] || continue
  name="$(basename "$inst")"
  [ -f "$TESTS_REPO_DIR/$name" ] || bad "suite $name existe en la máquina y NO está versionada"
done
# --- <<< contrato: suites de tests versionadas ---
# Cada hook registrado en settings.json debe existir en disco (un registro huérfano
# bloquea TODOS los tool calls de la sesión si el runner falla al abrirlo).
while IFS= read -r hk; do
  [ -n "$hk" ] || continue
  f="${hk/#\~/$HOME}"
  check "hook registrado existe: $(basename "$f")" test -f "$f"
done < <(jq -r '.. | .command? // empty' "$HOME/.claude/settings.json" | grep -oE '~/\.claude/(hooks|bin)/[^ ]+' | sort -u)
check "suite de contrato triangulate-main-checkout-guard verde" \
  bash "$HOME/.claude/hooks/tests/triangulate-guard-tests.sh"
# Control de admisión por carga (2026-09-17): en warn no bloquea nada, pero un
# error de sintaxis en un PreToolUse(Bash) bloquea todos los Bash de la sesión.
check "suite de contrato heavy-command-gate verde" \
  bash "$HOME/.claude/hooks/tests/heavy-command-gate-tests.sh"
# El guard de force push es el más caro si falla mudo: no rompe nada visible
# cuando deja pasar de más, hasta el día que una rama de ambiente queda reescrita.
check "suite de contrato force-push-guard verde" \
  bash "$HOME/.claude/hooks/tests/force-push-guard-tests.sh"
# Este guard también falla mudo porque Firebase REEMPLAZA la config completa:
# un deploy desde un checkout desactualizado BORRA silenciosamente índices o exemptions de otra rama (incidente 2026-08-31).
check "suite de contrato deploy-checkout-guard verde" \
  bash "$HOME/.claude/hooks/tests/deploy-checkout-guard-tests.sh"
# Este guard falla mudo y se paga en CUOTA: cuando deja pasar de más nadie ve
# nada, un loop gira 92 minutos esperando un CI terminado (incidente 2026-08-25).
check "suite de contrato block-unbounded-polls verde" \
  bash "$HOME/.claude/hooks/tests/block-unbounded-polls-tests.sh"
# Este guard falla en la dirección de OBLIGAR A REHACER TRABAJO: un formatter/linter con versión flotante
# formatea con otras reglas que el pin del repo (incidente 2026-08-31: prettier 3.9.6 vs 3.8.3, 24 falsos warnings y re-formateo).
check "suite de contrato pinned-tool-guard verde" \
  bash "$HOME/.claude/hooks/tests/pinned-tool-guard-tests.sh"
# Este ledger falla mudo en las DOS direcciones: de menos deja cerrar el turno con trabajo en background sin reportar,
# y de mas bloquea el turno sin que `unblock --all` pueda desbloquearlo (medido 2026-09-07: ids con tab/newline/backslash y numericos).
check "suite de contrato bg-track verde" \
  bash "$HOME/.claude/hooks/tests/bg-track-tests.sh"
# El PRODUCTOR del ledger. Lo que no anota, el Stop no puede bloquear. Su rama Workflow no habia ejecutado
# UN SOLO test (medido 2026-09-08) y el fallback de label ignoraba el string vacio: un Bash-bg con
# description:"" perdia el comando y dejaba el campo vacio, que aguas abajo corria los campos del mensaje.
# El tope de 120 se aplicaba POR LINEA, asi que un label multilinea no tenia tope y quemaba contexto en
# CADA Stop hasta el ack.
check "suite de contrato track-bg-launch verde" \
  bash "$HOME/.claude/hooks/tests/track-bg-launch-tests.sh"
# El CONSUMIDOR: el unico que bloquea el cierre del turno. Su mensaje es la unica salida que tiene y le dice
# al modelo QUE ackear. Leia el TSV con `IFS=$'\t' read`, que colapsa los campos vacios (el TAB es
# IFS-whitespace): con un label vacio el mensaje mostraba la edad en el lugar del label y mandaba a ackear
# con datos falsos. Su promesa mas fuerte es no dejar al usuario sin poder cerrar el turno: el fail-open se
# mide contra un ledger ausente, roto y mentiroso.
check "suite de contrato block-unacked-bg verde" \
  bash "$HOME/.claude/hooks/tests/block-unacked-bg-tests.sh"
# El hermano INFORMATIVO del ledger: no bloquea ni mata, asi que su unica salida es el texto que imprime.
# Un CLAUDE_REPORT_CHILDREN_MIN_AGE no numerico escupia `[: 5m: integer expression expected` UNA VEZ POR
# PROCESO, intercalado dentro del propio reporte y sin decir nunca que paso (medido 2026-09-08). Mismo bug
# que tenia reap-stale-polls, donde ademas era mortal; bg-track ya lo resolvia bien avisando una vez y
# cayendo al default. La suite arma un ARBOL DE PROCESOS REAL porque PPID no se puede falsear por entorno.
check "suite de contrato report-live-children verde" \
  bash "$HOME/.claude/hooks/tests/report-live-children-tests.sh"
# Este es el UNICO hook del harness que ejecuta una accion DESTRUCTIVA (kill) y es
# machine-wide: corre en cada Stop sobre los procesos de TODAS las sesiones. Sus guardas
# fallaban hacia el gatillo (medido 2026-09-08: un CLAUDE_POLL_STALE_SECS="5m" o un etime
# ilegible mataban procesos de 30s), era ciego justo a los loops que esperan con grep
# —el incidente que lo originó— y mataba comandos que solo MENCIONAN un loop.
check "suite de contrato reap-stale-polls verde" \
  bash "$HOME/.claude/hooks/tests/reap-stale-polls-tests.sh"
# Este es el UNICO hook que muta estado FUERA de esta maquina: hace `git push` al remoto de CADA repo
# donde abris sesion, y corre `git clean -fdx` / `git rm -r --cached`. Ademas falla MUDO POR DISENO
# (todo error es una linea de log y exit 0), asi que cuando deja de sincronizar nadie se entera nunca.
# Medido el 2026-09-08: sin ~/.engram era un no-op TOTAL (bash no podia abrir la redireccion del log y
# ni ejecutaba el clone), el `pull` PUBLICABA una rama nueva en el remoto de cada repo que abrias, un
# typo en el modo caia en la rama de push, y dos repos con el mismo basename compartian checkout
# —la memoria del segundo se exportaba al checkout del primero y su remoto no recibia nada—.
check "Engram excluye escritores concurrentes (fixtures)" python3 "$REPO_DIR/tests/engram_sync_concurrency_test.py"
check "engram-git-sync instalado idéntico al source" \
  cmp -s "$REPO_DIR/files/claude/hooks/engram-git-sync.sh" "$HOME/.claude/hooks/engram-git-sync.sh"
check "suite versionada engram-git-sync contra hook instalado" \
  bash "$REPO_DIR/files/claude/hooks/tests/engram-git-sync-tests.sh" "$HOME/.claude/hooks/engram-git-sync.sh"
check "codex-run instalado y ejecutable" test -x "$HOME/.claude/bin/codex-run"
# codex-run es el launcher que hace cumplir el routing y el watchdog. Nunca se
# comparaba contra el repo: el watchdog por inactividad del 2026-09-07 estuvo
# cuatro días sólo en disco, sin historial, y verify daba verde.
if cmp -s "$REPO_DIR/files/claude/bin/codex-run" "$HOME/.claude/bin/codex-run"; then
  ok "codex-run instalado e idéntico al source"
else
  bad "codex-run divergente del source (repo y máquina tienen versiones distintas)"
fi
check "suite de contrato del watchdog de codex-run verde" \
  bash "$HOME/.claude/hooks/tests/codex-run-watchdog-tests.sh"
# Este chequeo protege a TODOS los anteriores: verify.sh corre las suites desde
# $HOME, así que sin él una suite ablandada en la máquina firma el recibo.
check "suite de contrato verify-tests-drift verde" \
  bash "$HOME/.claude/hooks/tests/verify-tests-drift-tests.sh"
embedded="$(grep -o 'CODEX_RUN_BIN:-[^}]*' "$HOME/.claude/bin/codex-run" | head -1 | sed 's/CODEX_RUN_BIN:-//')"
if [ -n "$embedded" ] && [ -x "$embedded" ]; then ok "codex-run apunta a un binario real ($embedded)"; else bad "codex-run apunta a un binario inexistente (${embedded:-vacío}) — gotcha PRD R11"; fi
check "apply-agent-patches.sh instalado" test -x "$HOME/.claude/bin/apply-agent-patches.sh"
check "parches versionados presentes en ~/.claude/patches" test -f "$HOME/.claude/patches/agents/step0-openspec.md"
check "sync no reintrodujo regresiones" \
  bash "$HOME/.claude/bin/apply-agent-patches.sh" --check
if grep -rq 'mcp__plugin_engram_engram__' "$HOME/.claude/agents" 2>/dev/null; then
  bad "agents declaran tools del plugin Engram (mcp__plugin_engram_engram__*) — el harness usa el MCP directo"
else
  ok "agents usan los tools del MCP Engram directo"
fi
check "triangulate.conf presente (rutas por máquina)" test -f "$HOME/.claude/triangulate.conf"
if grep -q '/Users/<usuario>/' "$HOME/.claude/triangulate.conf" 2>/dev/null; then
  warn "triangulate.conf todavía tiene las rutas de ejemplo — editalo con los repos reales"
fi

echo "== Enforcement Codex (opt-in: bootstrap --codex-enforcement) =="
if jq -e '[.. | .command? // empty | select(test("route-code-to-codex"))] | length > 0' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
  ok "enforcement adoptado en esta máquina"
  check "route-code-to-codex.sh instalado" test -f "$HOME/.claude/hooks/route-code-to-codex.sh"
  check "validate-enforcement.sh registrado en SessionStart" \
    jq -e '[.hooks.SessionStart[].hooks[].command | select(test("validate-enforcement"))] | length == 1' "$HOME/.claude/settings.json"
  check "suite de contrato route-code-to-codex verde" bash "$HOME/.claude/hooks/tests/route-hook-tests.sh"
  # El fallback sin-créditos (regla 2026-09-03) es parte del enforcement: si el
  # flag no abre el paso, una sequía de cuota de Codex deja la máquina SIN
  # escritor de código; si abre de más, el routing se vuelve decorativo.
  check "fallback Codex-sin-créditos con contrato verde" bash "$REPO_DIR/tests/codex_run_sin_creditos_test.sh"
  check "codex-run instalado con detección de cuota" \
    grep -q 'CODEX SIN CUOTA' "$HOME/.claude/bin/codex-run"
  check "CLAUDE.md lleva el OVERRIDE 'Codex writes ALL product code'" grep -q 'user-override:codex-writes-code' "$HOME/.claude/CLAUDE.md"
  check "agents SDD llevan el bloque Code routing" grep -q '## Code routing (MANDATORY' "$HOME/.claude/agents/sdd-apply.md"
else
  ok "enforcement no adoptado (Claude escribe código); se activa con bootstrap --codex-enforcement"
  for name in $ENFORCEMENT_HOOKS; do
    if [ -f "$HOME/.claude/hooks/$name" ]; then bad "$name presente pero desregistrado (estado inconsistente)"; else ok "$name ausente, coherente con settings.json"; fi
  done
  if grep -q 'user-override:codex-writes-code' "$HOME/.claude/CLAUDE.md"; then bad "CLAUDE.md lleva el OVERRIDE de Codex sin el hook que lo hace cumplir"; else ok "CLAUDE.md sin OVERRIDE de Codex"; fi
  if grep -q '## Code routing (MANDATORY' "$HOME/.claude/agents/sdd-apply.md" 2>/dev/null; then bad "agents SDD conservan el bloque Code routing sin enforcement"; else ok "agents SDD sin bloque Code routing"; fi
fi
check "Claude acepta mensajes directos entre sesiones locales" \
  jq -e '.crossSessionInbound == "accept"' "$HOME/.claude/settings.json"
check "Claude exige aprobación para mensajería fuera de esta máquina" \
  jq -e '.isolatePeerMachines == true' "$HOME/.claude/settings.json"
check "Claude Agent Teams habilitado en modo in-process" \
  jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1" and .teammateMode == "in-process"' "$HOME/.claude/settings.json"
check "plugins livianos habilitados; Engram/Codex plugins deshabilitados" \
  jq -e '(.enabledPlugins["engram@engram"] == false) and ((.enabledPlugins["codex@openai-codex"] // false) == false) and .enabledPlugins["swift-lsp@claude-plugins-official"] and .enabledPlugins["code-simplifier@claude-plugins-official"]' "$HOME/.claude/settings.json"
check "marketplace engram declarado" \
  jq -e '.extraKnownMarketplaces.engram.source.repo == "Gentleman-Programming/engram"' "$HOME/.claude/settings.json"
check "statusline.sh existe (se invoca con 'bash', no requiere +x)" test -f "$HOME/.claude/statusline.sh"
check "presupuesto runtime instalado en Claude" grep -q 'gentle-ai:runtime-budget' "$HOME/.claude/CLAUDE.md"
check "OpenSpec es el store SDD por defecto en Claude" \
  grep -q 'openspec.*ACTIVE DEFAULT' "$HOME/.claude/CLAUDE.md"
check "principios de ingeniería instalados en Claude" \
  grep -q 'gentle-ai:engineering-principles' "$HOME/.claude/CLAUDE.md"
check "Claude conserva el contrato ODD" bash -c \
  'grep -q "### ODD en este harness" "$HOME/.claude/CLAUDE.md" && grep -q "Supersede" "$HOME/.claude/CLAUDE.md"'

echo "== Skills / agents / workflows =="
n_skills="$(find "$HOME/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n_skills" -ge 22 ]; then ok "skills: $n_skills SKILL.md (esperado >= 22)"; else bad "skills: $n_skills SKILL.md (esperado >= 22)"; fi
n_agents="$(find "$HOME/.claude/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
if [ "$n_agents" -ge 8 ]; then ok "agents: $n_agents (esperado >= 8, fases SDD)"; else bad "agents: $n_agents (esperado >= 8)"; fi
check "workflow dual-review.js presente" test -f "$HOME/.claude/workflows/dual-review.js"
check "workflow codex-build.js presente" test -f "$HOME/.claude/workflows/codex-build.js"
check "dual-review limita concurrencia a 2" \
  grep -q 'const MAX_PARALLEL = Math.min(2' "$HOME/.claude/workflows/dual-review.js"
check "codex-build limita concurrencia a 2" \
  grep -q 'const MAX_PARALLEL = Math.min(2' "$HOME/.claude/workflows/codex-build.js"

# PRD R11: los workflows no embeben el binario de codex; invocan codex-run (que sí
# lo embebe y se verifica arriba). Un workflow que vuelva a `/usr/local/bin/codex`
# directo revive el cuelgue del shim de cmux (incidente 2026-08-30).
# Además, cada workflow instalado tiene que ser IDÉNTICO al del repo: el 2026-09-03
# la máquina llevaba desde el 30-ago una versión con codex-run que el repo no tenía,
# y verify.sh pasaba porque solo miraba ~/.claude.
for wf in "$REPO_DIR/files/claude/workflows/"*.js; do
  name="$(basename "$wf")"
  inst="$HOME/.claude/workflows/$name"
  if [ ! -f "$inst" ]; then bad "workflow $name no instalado en ~/.claude/workflows"; continue; fi
  if cmp -s "$wf" "$inst"; then ok "workflow $name idéntico al source"; else bad "workflow $name divergente del source (repo y máquina tienen versiones distintas)"; fi
  if grep -q '\.claude/bin/codex-run' "$inst"; then
    ok "$name: invoca codex-run (sin shim, con timeout)"
  else
    bad "$name: no invoca codex-run — codex directo cuelga bajo el shim de cmux"
  fi
done

echo "== MCP =="
claude_mcp="$(claude mcp list 2>/dev/null || true)"
if printf '%s\n' "$claude_mcp" | grep -q '^codex:'; then bad "Claude conserva el MCP legacy 'codex'"; else ok "Claude y Codex permanecen runtimes standalone"; fi
if printf '%s\n' "$claude_mcp" | grep -q '^engram:'; then ok "Engram MCP directo registrado en Claude"; else bad "Engram MCP directo no registrado en Claude"; fi
if printf '%s\n' "$claude_mcp" | grep -q '^plugin:engram:'; then bad "Engram plugin sigue activo (duplica hooks/contexto)"; else ok "Engram plugin no duplica el MCP directo"; fi

echo "== Codex =="
check "~/.codex/config.toml existe" test -f "$HOME/.codex/config.toml"
STRICT_CODEX_BINS=("$(command -v codex)")
for codex_bin in "${STRICT_CODEX_BINS[@]}"; do
  check "config estricto: $("$codex_bin" --version 2>/dev/null) [$codex_bin]" \
    codex_config_strict_load "$codex_bin"
done
check "engram-instructions.md existe" test -f "$HOME/.codex/engram-instructions.md"
check "engram-compact-prompt.md existe" test -f "$HOME/.codex/engram-compact-prompt.md"
check "AGENTS.md gestionado existe" test -f "$HOME/.codex/AGENTS.md"
check "presupuesto runtime instalado en Codex" grep -q 'gentle-ai:runtime-budget' "$HOME/.codex/AGENTS.md"
check "OpenSpec es el store SDD por defecto en Codex" \
  grep -q 'openspec.*ACTIVE DEFAULT' "$HOME/.codex/AGENTS.md"
check "principios de ingeniería instalados en Codex" \
  grep -q 'gentle-ai:engineering-principles' "$HOME/.codex/AGENTS.md"
if cmp -s \
  <(sed -n '/gentle-ai:engineering-principles -->/,/\/gentle-ai:engineering-principles -->/p' "$HOME/.claude/CLAUDE.md") \
  <(sed -n '/gentle-ai:engineering-principles -->/,/\/gentle-ai:engineering-principles -->/p' "$HOME/.codex/AGENTS.md"); then
  ok "Claude y Codex comparten principios de ingeniería idénticos"
else
  bad "principios de ingeniería divergentes entre Claude y Codex"
fi
if cmp -s \
  <(sed -n '/gentle-ai:runtime-budget -->/,/\/gentle-ai:runtime-budget -->/p' "$HOME/.claude/CLAUDE.md") \
  <(sed -n '/gentle-ai:runtime-budget -->/,/\/gentle-ai:runtime-budget -->/p' "$HOME/.codex/AGENTS.md"); then
  ok "Claude y Codex comparten el mismo presupuesto runtime"
else
  bad "presupuesto runtime divergente entre Claude y Codex"
fi
if cmp -s \
  <(sed -n '/gentle-ai:automatic-triangulation -->/,/\/gentle-ai:automatic-triangulation -->/p' "$HOME/.claude/CLAUDE.md") \
  <(sed -n '/gentle-ai:automatic-triangulation -->/,/\/gentle-ai:automatic-triangulation -->/p' "$HOME/.codex/AGENTS.md"); then
  ok "Claude y Codex comparten el mismo contrato de triangulación automática"
else
  bad "contrato de triangulación automática divergente entre Claude y Codex"
fi
for client in claude codex; do
  check "skill triangulation-orchestrator instalado en $client" \
    test -f "$HOME/.$client/skills/triangulation-orchestrator/SKILL.md"
  check "protocolo de triangulación instalado en $client" \
    test -f "$HOME/.$client/skills/triangulation-orchestrator/references/protocol.md"
done
check "Codex conserva el routing ODD" grep -q 'Routing follows the ODD' "$HOME/.codex/AGENTS.md"
check "Codex aplica máximo dos por política" grep -q 'maximum two\|maximum two spawned children' "$HOME/.codex/AGENTS.md"
check "Codex impide recursión por política" grep -q 'Children must not spawn additional agents' "$HOME/.codex/AGENTS.md"
check "Codex usa effort barato por política" grep -q 'Use low reasoning for bounded/mechanical children' "$HOME/.codex/AGENTS.md"
check "Codex trabaja sin solicitudes de aprobación" \
  awk '/^\[/{root=0} NR==1{root=1} root && /^approval_policy = "never"$/{ok=1} END{exit ok?0:1}' "$HOME/.codex/config.toml"
check "Codex tiene acceso completo por preferencia del owner" \
  awk '/^\[/{root=0} NR==1{root=1} root && /^sandbox_mode = "danger-full-access"$/{ok=1} END{exit ok?0:1}' "$HOME/.codex/config.toml"
check "Codex agents.enabled activo" \
  awk '/^\[agents\]$/{a=1;next} /^\[/{a=0} a && /^enabled = true$/{ok=1} END{exit ok?0:1}' "$HOME/.codex/config.toml"
check "Codex limita a dos subagentes por sesión" \
  awk '/^\[agents\]$/{a=1;next} /^\[/{a=0} a && /^max_concurrent_threads_per_session = 2$/{ok=1} END{exit ok?0:1}' "$HOME/.codex/config.toml"
if codex_agents_has_legacy_key; then
  bad "Codex conserva claves legacy en [agents]"
else
  ok "Codex mantiene [agents] sin claves legacy"
fi
check "plugin Engram de Codex instalado pero deshabilitado" \
  awk '/^\[plugins\."engram@engram"\]$/{p=1;next} /^\[/{p=0} p && /^enabled = false$/{ok=1} END{exit ok?0:1}' "$HOME/.codex/config.toml"
# Gotcha PRD R3: ruta de engram inexistente = MCP muerto sin error visible
engram_cmd="$(grep -A2 '\[mcp_servers\.engram\]' "$HOME/.codex/config.toml" 2>/dev/null | grep '^command' | sed 's/.*= *"\(.*\)"/\1/')"
if [ -n "$engram_cmd" ] && [ -x "$engram_cmd" ]; then
  ok "mcp_servers.engram apunta a binario existente ($engram_cmd)"
else
  bad "mcp_servers.engram apunta a '$engram_cmd' (vacío o inexistente — gotcha PRD R3)"
fi
codex_engram_count="$(codex mcp list 2>/dev/null | grep -c '^engram ' || true)"
if [ "$codex_engram_count" = 1 ]; then ok "Codex expone un solo MCP Engram activo"; else bad "Codex expone $codex_engram_count MCP Engram (esperado 1)"; fi

# Gentle AI instala comandos SDD con nombres distintos por cliente: Claude usa
# `gentle-sdd-*`, mientras Codex conserva skills/meta-comandos `sdd-*`; no se
# crea openspec/ durante esta verificación.
# Gentle AI 3.7 instala las fases SDD de Codex como skills (~/.codex/skills/<fase>/
# SKILL.md); ~/.codex/prompts/*.md es el layout anterior y NO existe en una instalación
# nueva (gap visto en HOME limpio el 2026-09-03). Los meta-comandos new/ff/continue no
# son skills en ningún cliente: los orquesta AGENTS.md.
for phase in apply archive continue explore ff init new onboard verify; do
  cmd="gentle-sdd-$phase"
  skill="sdd-$phase"
  claude_ok=0; codex_ok=0
  [ -f "$HOME/.claude/commands/$cmd.md" ] && claude_ok=1
  { [ -f "$HOME/.codex/skills/$skill/SKILL.md" ] || [ -f "$HOME/.codex/prompts/$skill.md" ]; } && codex_ok=1
  case "$phase" in
    new|ff|continue) grep -q "/sdd-$phase" "$HOME/.codex/AGENTS.md" 2>/dev/null && codex_ok=1 ;;
  esac
  if [ "$claude_ok" = 1 ] && [ "$codex_ok" = 1 ]; then
    ok "SDD '$cmd' disponible en Claude y Codex"
  else
    bad "SDD '$cmd' no tiene paridad Claude/Codex (claude=$claude_ok codex=$codex_ok)"
  fi
done
check "agents Claude sin tools repetidos" agents_tools_unique

echo "== Runtimes standalone =="
check "Claude/Codex: configuración/contratos estáticos; mensajería viva UNTESTED" \
  bash "$REPO_DIR/tests/standalone_runtime_parity_test.sh"

check "worktree health: isolated identity/ownership fixtures" bash "$REPO_DIR/tests/worktree_health_test.sh"
check "local protection: isolated backup/rollback fixtures" python3 "$REPO_DIR/tests/local_protection_test.py"
check "workflow invocation: CLI options and worktree preservation" python3 "$REPO_DIR/tests/workflow_invocation_test.py"
check "shared evidence: isolated contract/install fixtures" bash "$REPO_DIR/tests/harness_evidence_test.sh"
echo "== Presupuesto de repositorios canónicos =="
CORE_BACKEND="$(conf_repo back || true)"
validate_core_root() {
  local root="$1" label start_bytes tests
  label="${root#$HOME/}"
  health_checkout "$root" || return 0 # A7 reports stale/uncertain roots once.
  case "$root" in "$HOME"/conductor/*) info "worktree Conductor legacy preservado, fuera del runtime activo: $root"; return ;; esac
  # La rama huérfana engram-sync (memoria Engram por repo) no lleva código ni harness.
  case "$root" in "$HOME"/.engram-git/*) info "worktree engram-sync (solo memoria): $root"; return ;; esac
  for f in CLAUDE.md AGENTS.md; do check "$label/$f existe" test -f "$root/$f"; done
  check "$label SessionStart existe" test -f "$root/.claude/hooks/on-session-start.sh"
  start_bytes="$(cd "$root" && bash .claude/hooks/on-session-start.sh 2>/dev/null | wc -c | tr -d ' ')"
  [ "$start_bytes" -le 4096 ] && ok "$label SessionStart acotado: ${start_bytes} bytes" || bad "$label SessionStart excede 4 KiB: ${start_bytes} bytes"
  if grep -Eq 'cat[[:space:]]+.*(SNAPSHOT|ACTIVE_PLAN)|full content' "$root/.claude/hooks/on-session-start.sh"; then bad "$label inyecta snapshot/plan completo"; else ok "$label referencia continuidad sin cat completo"; fi
  if grep -Eq 'architecture-planner.*scope-discipline|/review.*agent:code-reviewer' "$root/.claude/hooks/on-prompt-routing.sh"; then bad "$label conserva routing automático costoso"; else ok "$label sin routing automático a planner/reviewer"; fi
  check "$label deshabilita plugins review/setup/frontend" jq -e '(.enabledPlugins["code-review@claude-plugins-official"] == false) and (.enabledPlugins["claude-code-setup@claude-plugins-official"] == false) and (.enabledPlugins["frontend-design@claude-plugins-official"] == false)' "$root/.claude/settings.json"
  for tests in "$root/.claude/hooks/tests/run.sh" "$root/.codex/hooks/tests/run.sh"; do
    check "$label test hooks usa fixture temporal" grep -q 'SOURCE_REPO=.*mktemp\|REPO=.*mktemp' "$tests"
    if grep -Fq 'console.log("leak")' "$tests" || grep -Eq '(SOURCE_REPO|Documents/cocoa).*(index\.ts|errors\.ts).*(>>|sed|tee)' "$tests"; then bad "$label test hooks puede mutar source real"; else ok "$label test hooks no muta source real"; fi
  done
}
if [ -d "$CORE_BACKEND" ]; then
  health_each_root "$CORE_BACKEND" validate_core_root
else
  warn "cocoa-core-backend canónico no disponible (triangulate.conf back=${CORE_BACKEND:-sin definir}); presupuesto no verificado"
fi

COCOA_V2="$(conf_repo app || true)"
validate_cocoa_root() {
  local root="$1" label output bytes
  label="${root#$HOME/}"
  health_checkout "$root" || return 0 # A7 reports stale/uncertain roots once.
  case "$root" in "$HOME"/conductor/*) info "worktree Conductor legacy preservado, fuera del runtime activo: $root"; return ;; esac
  for f in CLAUDE.md AGENTS.md; do check "$label/$f existe" test -f "$root/$f"; done
  check "$label flavor hook syntax" bash -n "$root/.claude/hooks/inject-flavor-context.sh"
  output="$(cd "$root" && CLAUDE_PROJECT_DIR="$root" bash .claude/hooks/inject-flavor-context.sh 2>/dev/null)"
  bytes="$(printf '%s' "$output" | wc -c | tr -d ' ')"
  if [ "$bytes" -eq 0 ]; then info "$label flavor hook sin entry activo; sintaxis validada"; elif [ "$bytes" -le 240 ] && printf '%s' "$output" | jq -e . >/dev/null 2>&1; then ok "$label flavor output JSON acotado: ${bytes} bytes"; else bad "$label flavor output inválido o >240 bytes: ${bytes}"; fi
}
if [ -d "$COCOA_V2" ]; then
  health_each_root "$COCOA_V2" validate_cocoa_root
else
  warn "cocoa_v2 canónico no disponible (triangulate.conf app=${COCOA_V2:-sin definir}); presupuesto no verificado"
fi
if [ -d "$HOME/conductor/workspaces" ]; then
  info "Conductor está inactivo; sus worktrees legacy se preservan para recuperación y cierre, no para trabajo nuevo"
fi

echo "== Auditoría de la máquina (hallazgos 2026-09-03 convertidos en checks) =="
# A1. engram-sync: cada checkout de ~/.engram-git debe ver origin/engram-sync. El
#     bootstrap huérfano (clone --depth 1 = single-branch) dejaba el refspec en la
#     rama default y la memoria de otras máquinas nunca se importaba.
if [ -d "$HOME/.engram-git" ]; then
  for d in "$HOME"/.engram-git/*/; do
    [ -e "$d/.git" ] || continue
    name="$(basename "$d")"
    if git -C "$d" config --get-all remote.origin.fetch | grep -Eq 'refs/heads/(\*|engram-sync):'; then
      ok "engram-sync $name: refspec incluye la rama engram-sync"
    else
      bad "engram-sync $name: refspec sin engram-sync (nunca importa memoria ajena; el hook lo auto-corrige en la próxima sesión)"
    fi
    if git -C "$d" rev-parse --verify -q origin/engram-sync >/dev/null; then
      ok "engram-sync $name: origin/engram-sync resuelve"
    else
      bad "engram-sync $name: origin/engram-sync no existe (merge imposible)"
    fi
  done
fi
# A2. Codex: trust entries a rutas que ya no existen (scratchpads, workspaces Conductor).
if [ -f "$HOME/.codex/config.toml" ]; then
  dead=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -d "$p" ] || { dead=$((dead+1)); warn "Codex confía en un proyecto inexistente: $p (borrar su [projects] de ~/.codex/config.toml)"; }
  done < <(sed -n 's/^\[projects\."\(.*\)"\]$/\1/p' "$HOME/.codex/config.toml")
  [ "$dead" -eq 0 ] && ok "Codex sin trust entries a rutas muertas"
fi
# A3. Claude: plugins instalados para proyectos que ya no existen y el plugin legacy codex.
IP="$HOME/.claude/plugins/installed_plugins.json"
if [ -f "$IP" ]; then
  dead=0
  while IFS=$'\t' read -r pname ppath; do
    [ -n "$ppath" ] || continue
    [ -d "$ppath" ] || { dead=$((dead+1)); warn "plugin $pname instalado para un proyecto inexistente: $ppath"; }
  done < <(jq -r '.plugins | to_entries[] | .key as $n | .value[] | select(.projectPath != null) | [$n, .projectPath] | @tsv' "$IP")
  [ "$dead" -eq 0 ] && ok "plugins de Claude sin proyectos muertos"
  if jq -e '.plugins["codex@openai-codex"]' "$IP" >/dev/null 2>&1; then
    warn "plugin legacy codex@openai-codex sigue instalado (runtimes standalone: claude plugin uninstall codex@openai-codex)"
  else
    ok "plugin legacy codex@openai-codex no instalado"
  fi
fi
# A4. Registries .atl sembrados fuera de repos por el refresh de SessionStart con cwd suelto.
check "registry refresh usa la raíz del worktree (fixtures aislados)" bash "$REPO_DIR/tests/skill_registry_root_test.sh"
check "helper registry instalado coincide con fuente" cmp "$REPO_DIR/files/shared/bin/skill-registry-refresh" "$HOME/.local/bin/skill-registry-refresh"
for client in claude codex; do
  registry_config="$HOME/.$client/hooks.json"
  registry_cwd='$PWD'
  [ "$client" != claude ] || { registry_config="$HOME/.claude/settings.json"; registry_cwd='${CLAUDE_PROJECT_DIR:-$PWD}'; }
  check "$client registry hook usa helper compartido y cwd explícito" jq -e --arg command "\"\$HOME/.local/bin/skill-registry-refresh\" \"$registry_cwd\"" \
    '[.hooks.SessionStart[].hooks[].command | select(. == $command)] | length == 1' "$registry_config"
done
stray=0
while IFS= read -r d; do
  parent="$(dirname "$d")"
  [ "$parent" = "$HOME" ] && continue
  git -C "$parent" rev-parse --is-inside-work-tree >/dev/null 2>&1 && continue
  stray=$((stray+1)); warn "skill-registry huérfano fuera de un repo: $d (preservar; inspeccionar propietario antes de cualquier limpieza)"
done < <(find "$HOME" -maxdepth 4 -type d -name .atl -not -path '*/node_modules/*' -not -path "$HOME/.Trash/*" 2>/dev/null)
[ "$stray" -eq 0 ] && ok "sin skill-registry (.atl) huérfanos fuera de repos"
# A5. Disco de Codex: staging de marketplaces abandonado (un clone por upgrade fallido) y sesiones/logs.
STAGING="$HOME/.codex/.tmp/marketplaces/.staging"
if [ -d "$STAGING" ]; then
  stale="$(find "$STAGING" -maxdepth 1 -mindepth 1 -type d -mtime +1 | wc -l | tr -d ' ')"
  if [ "$stale" -gt 0 ]; then
    warn "Codex dejó $stale staging de marketplace de más de un día en $STAGING ($(du -sh "$STAGING" 2>/dev/null | cut -f1)); inspeccionar propietario y uso antes de borrar"
  else
    ok "Codex sin staging de marketplaces abandonado"
  fi
fi
if [ -d "$HOME/.codex" ]; then
  kb="$(du -sk "$HOME/.codex" 2>/dev/null | cut -f1)"
  if [ "${kb:-0}" -gt $((2 * 1024 * 1024)) ]; then
    warn "~/.codex ocupa $((kb / 1024 / 1024)) GB: $(du -sh "$HOME/.codex/.tmp" "$HOME/.codex/sessions" "$HOME"/.codex/logs_*.sqlite 2>/dev/null | awk '{printf "%s %s; ", $1, $2}' | sed "s#$HOME/.codex/##g")"
  else
    ok "~/.codex por debajo de 2 GB"
  fi
fi
# A6. ~/.claude.json conserva proyectos inexistentes (Claude Code reescribe el archivo: limpiar con el CLI cerrado).
if [ -f "$HOME/.claude.json" ]; then
  deadp="$(jq -r '.projects // {} | keys[]' "$HOME/.claude.json" | while IFS= read -r p; do [ -d "$p" ] || printf '%s\n' "$p"; done)"
  if [ -n "$deadp" ]; then
    warn "~/.claude.json conserva $(printf '%s\n' "$deadp" | wc -l | tr -d ' ') proyectos inexistentes: $(printf '%s' "$deadp" | tr '\n' ' ')"
  else
    ok "~/.claude.json sin proyectos muertos"
  fi
fi
# A7. Higiene de worktrees en los repos canónicos: ignorados, prunables, sucios o con commits que ningún remoto tiene.
audit_worktrees() {
  local repo="$1" label tracked_atl rc=0
  label="${repo#$HOME/}"
  health_checkout "$repo" || { health_audit_root "$repo"; return; }
  if health_git -C "$repo" check-ignore -q .claude/worktrees/x; then
    ok "$label ignora .claude/worktrees/"
  else
    rc=$?
    if [ "$rc" -gt 1 ]; then warn "$label: ignore inspection unavailable"; else
      bad "$label NO ignora .claude/worktrees/ (aparecen como untracked y un git add -A los sube)"
    fi
  fi
  # .atl/ lo regenera el hook de skill-registry en cada sesión: trackeado deja dev sucio y sube rutas de la máquina.
  if ! tracked_atl=$(health_git -C "$repo" ls-files .atl 2>/dev/null); then
    warn "$label: tracked registry inspection unavailable"
  elif [ -n "$tracked_atl" ]; then
    bad "$label trackea .atl/ (el hook lo regenera cada sesión: dev sucio y rutas absolutas de un worktree en git)"
  elif health_git -C "$repo" check-ignore -q .atl/x; then
    ok "$label ignora .atl/"
  else
    rc=$?
    if [ "$rc" -gt 1 ]; then warn "$label: ignore inspection unavailable"; else
      warn "$label no ignora .atl/ (el hook lo regenera cada sesión y queda como untracked)"
    fi
  fi
  health_each_root "$repo" health_audit_root
}
for role in back front app; do
  r="$(conf_repo "$role" || true)"
  if [ -z "$r" ] || [ ! -d "$r" ]; then info "A7 omitido para '$role': repo no configurado o ausente (${r:-triangulate.conf})"; continue; fi
  audit_worktrees "$r"
done
echo "== Skill registry =="
check "~/.atl/skill-registry.md existe" test -f "$HOME/.atl/skill-registry.md"

echo
echo "Resultado: $PASS PASS / $WARN WARN / $FAIL FAIL"
cat <<'EOF'

CHEQUEOS MANUALES RESTANTES (PRD §8, no automatizables):
  - En una sesión nueva de Claude Code y otra de Codex: tools mem_* responden desde el MCP directo.
  - Las skills marcadas como invocables aparecen en autocomplete; las exclusivas de ejecutores no.
  - Comprobar el recibo de la única vía de revisión elegida; NO añadir dual-review como segunda revisión obligatoria.
  - En Claude: enlazar tres sesiones con /list-agents; comprobar mensaje directo, idle notice y consolidación.
  - En Codex: iniciar un primary, crear dos agent threads y comprobar follow-up/reasignación y consolidación.
  - Inspeccionar worktrees legacy de Conductor antes de archivarlos; preservar cualquier commit o cambio pendiente.
  - Statusline muestra dir + branch (+ flavor en repos Flutter).
EOF

[ "$FAIL" -eq 0 ]
