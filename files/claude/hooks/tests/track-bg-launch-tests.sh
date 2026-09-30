#!/usr/bin/env bash
# Suite de contrato de track-bg-launch.sh — el PRODUCTOR del ledger de background.
#
# Por qué importa: es la única fuente del ledger. Lo que este hook NO anota, el
# Stop hook no puede bloquear, y el trabajo en background se cierra en silencio.
# Lo que anota MAL viaja entero al mensaje de bloqueo, que lo consume el modelo
# en CADA Stop hasta el ack: un label sucio no es cosmético, es contexto quemado
# por turno.
#
# La promesa más fuerte está en su cabecera (línea 3): "Puro instrumental: NUNCA
# bloquea (exit 0 siempre)". Un exit ≠0 acá bloquea el PreToolUse y deja al
# usuario sin poder lanzar NADA. Por eso el eje A mide exit 0 contra entradas
# rotas, no sólo contra las felices.
#
# Relación con bg-track-tests.sh: aquella mide el LEDGER (bg-track.sh) y tiene 6
# casos de integración de este hook (Agent y Bash-bg, flujo feliz). Esta mide el
# CONTRATO del hook: los tres kinds, los fallbacks de label y el tope. El solape
# es intencional y barato.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/track-bg-launch-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/track-bg-launch.sh}"
LEDGER_HOOK="$HOME/.claude/hooks/bg-track.sh"
fails=0
total=0

# 0) Precondiciones duras. Este hook corre en CADA PreToolUse de Agent/Workflow/
#    Bash: un error de sintaxis acá no es un test rojo, es el harness trabado.
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — nada alimenta el ledger de background." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
if [ ! -f "$LEDGER_HOOK" ]; then
  echo "FATAL: no existe $LEDGER_HOOK — sin el ledger este hook no puede anotar nada." >&2
  exit 3
fi
command -v jq >/dev/null 2>&1 || { echo "FATAL: falta jq; el hook no puede parsear su input." >&2; exit 3; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tbl-tests.XXXXXX")" || exit 3
cleanup(){ [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# ── Helpers ──────────────────────────────────────────────────────────────────
# mktemp -d por caso: `sbox` se llama como $(sbox), o sea en un SUBSHELL. Un
# contador con variable NO persiste al padre y todos los casos terminarían
# compartiendo sandbox (14 falsos FAIL midiendo verify-tests-drift, 2026-09-08).
sbox(){ # → imprime la ruta de un HOME nuevo, con su copia del ledger
  local h; h="$(mktemp -d "$TMP/home.XXXXXX")"
  mkdir -p "$h/.claude/hooks/state"
  # El hook invoca "$HOME/.claude/hooks/bg-track.sh" por ruta absoluta. Sin esta
  # copia, TODOS los casos medirían un ledger AUSENTE (fail-open) y darían verde
  # por la razón equivocada.
  cp "$LEDGER_HOOK" "$h/.claude/hooks/bg-track.sh" 2>/dev/null
  printf '%s' "$h"
}

# Espia: reemplaza el ledger por un stub que anota su argv. Mide si el hook LO
# LLAMA, no si quedo una entrada. Es una promesa mas fuerte: `bg-track launch`
# rechaza un id vacio por su cuenta, asi que sin espia la guarda del hook se
# puede borrar sin que ningun caso se entere (mutante escapado, 2026-09-08).
spybox(){ # → HOME cuyo ledger es un espia
  local h; h="$(mktemp -d "$TMP/home.XXXXXX")"
  mkdir -p "$h/.claude/hooks/state"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" "$*" >> "$HOME/.spy"\n'
  } > "$h/.claude/hooks/bg-track.sh"
  printf '%s' "$h"
}
spy(){ cat "$1/.spy" 2>/dev/null | wc -l | tr -d ' '; }

fire(){ # fire <home> <json> → corre el hook, imprime su exit code
  local h="$1" json="$2" rc
  printf '%s' "$json" | HOME="$h" bash "$HOOK" >/dev/null 2>&1
  rc=$?
  printf '%s' "$rc"
}

led(){ # led <home> [session] → el ledger crudo
  cat "$1/.claude/hooks/state/${2:-S}.jsonl" 2>/dev/null
}

field(){ # field <home> <campo> [session] → un campo de la ÚLTIMA entrada
  led "$1" "${3:-S}" | tail -1 | jq -r ".${2} // \"<AUSENTE>\"" 2>/dev/null
}

# Comparar sobre variable capturada, nunca con un grep al final de un pipe: ese
# grep cierra el pipe apenas matchea y bajo `set -o pipefail` el productor muere
# por SIGPIPE, devolviendo ≠0 CON EL MATCH PRESENTE. Falla de a ratos.
has(){ # has <texto> <patrón> <si> <no>
  case "$1" in (*"$2"*) printf '%s' "$3";; (*) printf '%s' "$4";; esac
}

check(){ # check <nombre> <esperado> <obtenido>
  total=$((total+1))
  if [ "$2" = "$3" ]; then
    printf '  ok   %s\n' "$1"
  else
    fails=$((fails+1))
    printf '  FAIL %s\n       esperado: [%s]\n       obtenido: [%s]\n' "$1" "$2" "$3"
  fi
}

# Constructor de input. Fabricar el JSON con jq y no con printf evita que un
# label con comillas produzca un JSON inválido y el caso mida el parseo del
# fixture en vez del hook.
inp(){ # inp <tool> <session> <id> <json-de-tool_input>
  jq -nc --arg t "$1" --arg s "$2" --arg i "$3" --argjson ti "$4" \
    '{tool_name:$t, session_id:$s, tool_use_id:$i, tool_input:$ti}'
}

echo "== A) La promesa más fuerte: NUNCA bloquea (exit 0 en TODO camino) ======="
h=$(sbox); check "input vacío sale 0"                    0 "$(fire "$h" '')"
h=$(sbox); check "JSON inválido sale 0"                  0 "$(fire "$h" 'no-json{{{')"
h=$(sbox); check "JSON que no es objeto sale 0"          0 "$(fire "$h" '[1,2,3]')"
h=$(sbox); check "sin tool_name sale 0"                  0 "$(fire "$h" '{"session_id":"S","tool_use_id":"t"}')"
h=$(sbox); check "tool desconocido sale 0"               0 "$(fire "$h" "$(inp Read S t1 '{}')")"
h=$(sbox); check "sin session_id sale 0"                 0 "$(fire "$h" '{"tool_name":"Agent","tool_use_id":"t"}')"
h=$(sbox); check "sin tool_use_id sale 0"                0 "$(fire "$h" '{"tool_name":"Agent","session_id":"S"}')"
h=$(sbox); rm -f "$h/.claude/hooks/bg-track.sh"
           check "ledger AUSENTE sale 0 (fail-open)"     0 "$(fire "$h" "$(inp Agent S t1 '{"description":"x"}')")"
h=$(sbox); printf '#!/usr/bin/env bash\nexit 1\n' > "$h/.claude/hooks/bg-track.sh"
           check "ledger que falla sale 0"               0 "$(fire "$h" "$(inp Agent S t1 '{"description":"x"}')")"
h=$(sbox); printf 'if then fi(((\n' > "$h/.claude/hooks/bg-track.sh"
           check "ledger con error de sintaxis sale 0"   0 "$(fire "$h" "$(inp Agent S t1 '{"description":"x"}')")"
h=$(sbox); check "tool_input ausente sale 0"             0 "$(fire "$h" '{"tool_name":"Agent","session_id":"S","tool_use_id":"t"}')"

echo "== B) No anota lo que no corresponde ====================================="
h=$(sbox); fire "$h" "$(inp Read S t1 '{}')" >/dev/null
           check "tool desconocido no crea ledger"       "" "$(led "$h")"
h=$(sbox); fire "$h" '{"tool_name":"Agent","tool_use_id":"t"}' >/dev/null
           check "sin session_id no crea ledger"         "" "$(led "$h")"
h=$(sbox); fire "$h" '{"tool_name":"Agent","session_id":"S"}' >/dev/null
           check "sin tool_use_id no crea ledger"        "" "$(led "$h")"
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"command":"ls"}')" >/dev/null
           check "Bash sin run_in_background no se anota" "" "$(led "$h")"
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"command":"ls","run_in_background":false}')" >/dev/null
           check "Bash con run_in_background:false no se anota" "" "$(led "$h")"
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"command":"ls","run_in_background":null}')" >/dev/null
           check "Bash con run_in_background:null no se anota" "" "$(led "$h")"

echo "== B2) No llama al ledger cuando falta la identidad ====================="
# El caso de CONTROL va primero: sin el, un espia roto haria pasar los tres
# siguientes por la razon equivocada (todos darian 0 llamadas). Afirmar el
# fixture antes de medir con el.
h=$(spybox); fire "$h" "$(inp Agent S t1 '{"description":"x"}')" >/dev/null
           check "CONTROL: un Agent válido SÍ llama al ledger" 1 "$(spy "$h")"
h=$(spybox); fire "$h" '{"tool_name":"Agent","session_id":"S"}' >/dev/null
           check "sin tool_use_id NI SIQUIERA llama al ledger" 0 "$(spy "$h")"
h=$(spybox); fire "$h" '{"tool_name":"Agent","tool_use_id":"t1"}' >/dev/null
           check "sin session_id NI SIQUIERA llama al ledger"  0 "$(spy "$h")"
h=$(spybox); fire "$h" "$(inp Read S t1 '{}')" >/dev/null
           check "un tool desconocido no llama al ledger"      0 "$(spy "$h")"

echo "== C) Agent: kind y los TRES niveles de fallback del label =============="
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"revisar el diff"}')" >/dev/null
           check "Agent → kind=agent"                    agent            "$(field "$h" kind)"
           check "Agent → label = description"           "revisar el diff" "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"subagent_type":"Explore"}')" >/dev/null
           check "Agent sin description → subagent_type" Explore          "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{}')" >/dev/null
           check "Agent sin nada → literal 'agent'"      agent            "$(field "$h" label)"
# jq `//` sólo atrapa null y false: un "" pasa el filtro y deja el label VACÍO.
# Aguas abajo el TSV de `pending` colapsa el campo y corre la edad al lugar del
# label. Medido 2026-09-08.
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"","subagent_type":"Explore"}')" >/dev/null
           check "Agent con description VACÍA → cae a subagent_type" Explore "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"   ","subagent_type":"Explore"}')" >/dev/null
           check "Agent con description en blanco → cae a subagent_type" Explore "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"","subagent_type":""}')" >/dev/null
           check "Agent con TODO vacío → literal 'agent'" agent           "$(field "$h" label)"

echo "== D) Workflow: la rama que ningún test había ejecutado JAMÁS ==========="
h=$(sbox); fire "$h" "$(inp Workflow S t1 '{"name":"review-changes"}')" >/dev/null
           check "Workflow → kind=workflow"              workflow         "$(field "$h" kind)"
           check "Workflow → label = name"               review-changes   "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Workflow S t1 '{"scriptPath":"/tmp/wf.js"}')" >/dev/null
           check "Workflow sin name → scriptPath"        /tmp/wf.js       "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Workflow S t1 '{}')" >/dev/null
           check "Workflow sin nada → literal 'workflow'" workflow        "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Workflow S t1 '{"name":"","scriptPath":"/tmp/wf.js"}')" >/dev/null
           check "Workflow con name VACÍO → scriptPath"  /tmp/wf.js       "$(field "$h" label)"

echo "== E) Bash en background ================================================"
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"run_in_background":true,"description":"build largo"}')" >/dev/null
           check "Bash-bg → kind=bash-bg"                bash-bg          "$(field "$h" kind)"
           check "Bash-bg → label = description"         "build largo"    "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"run_in_background":true,"command":"npm test"}')" >/dev/null
           check "Bash-bg sin description → command"     "npm test"       "$(field "$h" label)"
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"run_in_background":true}')" >/dev/null
           check "Bash-bg sin nada → literal 'bash'"     bash             "$(field "$h" label)"
# El caso MÁS probable de los tres: el harness manda description opcional y el
# command siempre. Un description:"" borra el único dato que identifica qué
# quedó corriendo.
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"run_in_background":true,"description":"","command":"npm run deploy:prod"}')" >/dev/null
           check "Bash-bg con description VACÍA → command" "npm run deploy:prod" "$(field "$h" label)"

echo "== F) Tope del label: 120 chars, SIEMPRE ================================"
L200="$(printf 'x%.0s' $(seq 1 200))"
h=$(sbox); fire "$h" "$(inp Agent S t1 "$(jq -nc --arg d "$L200" '{description:$d}')")" >/dev/null
           check "label de 200 se trunca a 120"          120 "$(field "$h" label | tr -d '\n' | wc -c | tr -d ' ')"
L120="$(printf 'y%.0s' $(seq 1 120))"
h=$(sbox); fire "$h" "$(inp Agent S t1 "$(jq -nc --arg d "$L120" '{description:$d}')")" >/dev/null
           check "label de 120 exactos queda intacto"    120 "$(field "$h" label | tr -d '\n' | wc -c | tr -d ' ')"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"corto"}')" >/dev/null
           check "label corto no se toca"                corto "$(field "$h" label)"
# `cut -c1-120` trunca POR LÍNEA: el tope real era 120 × N líneas, o sea NINGUNO.
# Ese label viaja al mensaje de bloqueo, que el modelo consume en cada Stop hasta
# el ack. Un label sin tope es contexto quemado por turno. Medido 2026-09-08:
# 3 líneas de 200 chars produjeron un label de 363.
ML="$(printf 'a%.0s' $(seq 1 200))
$(printf 'b%.0s' $(seq 1 200))
$(printf 'c%.0s' $(seq 1 200))"
h=$(sbox); fire "$h" "$(inp Agent S t1 "$(jq -nc --arg d "$ML" '{description:$d}')")" >/dev/null
           check "label MULTILÍNEA también topea en 120" 120 "$(field "$h" label | tr -d '\n' | wc -c | tr -d ' ')"
           check "label multilínea deja UNA sola entrada" 1  "$(led "$h" | wc -l | tr -d ' ')"
h=$(sbox); fire "$h" "$(inp Agent S t1 "$(jq -nc --arg d "linea uno
linea dos" '{description:$d}')")" >/dev/null
           check "label multilínea no conserva saltos"   "linea uno linea dos" "$(field "$h" label)"

echo "== G) El ledger sigue siendo JSONL válido =============================="
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"con \"comillas\" y $VAR"}')" >/dev/null
           check "label con comillas y \$ → JSONL válido" SI "$(led "$h" | jq -e . >/dev/null 2>&1 && echo SI || echo NO)"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"back\\slash y \ttab"}')" >/dev/null
           check "label con backslash y tab → JSONL válido" SI "$(led "$h" | jq -e . >/dev/null 2>&1 && echo SI || echo NO)"
h=$(sbox); fire "$h" "$(inp Agent S t1 '{"description":"uno"}')" >/dev/null
           fire "$h" "$(inp Agent S t2 '{"description":"dos"}')" >/dev/null
           check "dos launches → dos entradas"           2 "$(led "$h" | wc -l | tr -d ' ')"
h=$(sbox); fire "$h" "$(inp Agent A t1 '{"description":"de A"}')" >/dev/null
           check "anota en el ledger de SU sesión"       "de A" "$(field "$h" label A)"
           check "no contamina otra sesión"              "" "$(led "$h" B)"

echo "== H) LÍMITES declarados a propósito ===================================="
# El harness manda un booleano JSON. Aceptar también el string "true" es
# deliberado: `jq -r` colapsa ambos a "true" y rechazarlo sólo agregaría una
# forma de NO anotar trabajo real. Anotar de más es barato (un ack); anotar de
# menos cierra el turno en silencio, que es el fallo que este ledger existe para
# evitar.
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"run_in_background":"true","command":"x"}')" >/dev/null
           check "LÍMITE: run_in_background string \"true\" cuenta como true" bash-bg "$(field "$h" kind)"
# Sin jq el hook no puede leer NADA y sale 0 sin anotar. Es fail-open CIEGO: no
# rompe, pero deja de proteger sin decirlo. Se acepta porque jq es precondición
# dura de todo el harness (verify.sh lo verifica aparte); avisar acá sería ruido
# en cada PreToolUse.
h=$(sbox); mkdir -p "$h/bin"; printf '#!/usr/bin/env bash\nexit 127\n' > "$h/bin/jq"; chmod +x "$h/bin/jq"
rc=$(printf '%s' "$(inp Agent S t1 '{"description":"x"}')" | PATH="$h/bin:$PATH" HOME="$h" bash "$HOOK" >/dev/null 2>&1; echo $?)
           check "LÍMITE: sin jq sale 0 (fail-open ciego)" 0 "$rc"
           check "LÍMITE: sin jq no anota nada"          "" "$(led "$h")"
# El hook NO verifica que el tool_use_id sea único: relanzar el mismo id vuelve a
# dejarlo pendiente. Es a propósito y está medido del lado del ledger
# (bg-track-tests.sh: "relanzar un id ya reconocido vuelve a dejarlo pendiente").
h=$(sbox); fire "$h" "$(inp Agent S dup '{"description":"uno"}')" >/dev/null
           fire "$h" "$(inp Agent S dup '{"description":"dos"}')" >/dev/null
           check "LÍMITE: no deduplica tool_use_id"      2 "$(led "$h" | wc -l | tr -d ' ')"
# LÍMITE ESTRUCTURAL — medido 2026-09-08 con este mismo mecanismo, en vivo.
# El hook decide en PreToolUse, donde sólo existe la INTENCIÓN declarada. Un
# Bash lanzado SIN run_in_background que el harness manda a background solo al
# vencer su timeout (120s) NO queda anotado: en PreToolUse el flag era falso.
# El Stop deja cerrar el turno con ese proceso vivo — exactamente el fallo que
# el ledger existe para evitar. NO es arreglable desde acá: la información no
# existe todavía en PreToolUse. Requiere reconciliar contra el directorio de
# tasks del harness, que es un cambio de diseño. Este caso FIJA el límite para
# que se vea; no lo tapa.
h=$(sbox); fire "$h" "$(inp Bash S t1 '{"command":"sleep 999"}')" >/dev/null
           check "LÍMITE: el auto-background del harness NO se anota" "" "$(led "$h")"

echo
if [ "$fails" -eq 0 ]; then
  printf 'Resultado: %s PASS / 0 FAIL\n' "$total"
  exit 0
fi
printf 'Resultado: %s PASS / %s FAIL (de %s)\n' "$((total-fails))" "$fails" "$total"
exit 1
