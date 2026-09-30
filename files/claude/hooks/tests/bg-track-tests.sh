#!/usr/bin/env bash
# Suite de contrato de bg-track.sh — el ledger de background hecho estructura
# verificable.
#
# Por qué este ledger importa: es el ÚNICO mecanismo que impide que un Agent,
# un Workflow o un Bash en background queden lanzados y en silencio. Falla
# MUDO en las dos direcciones y las dos son caras:
#   - de menos: `pending` devuelve vacío y el Stop deja cerrar el turno con
#     trabajo sin reportar. El usuario no se entera de que había algo.
#   - de más: el Stop bloquea y `unblock --all` NO desbloquea, así que el
#     usuario queda sin poder cerrar el turno. Eso viola la promesa más fuerte
#     del hook (cabecera, línea 21: "un bug acá nunca debe dejar al usuario
#     sin poder cerrar un turno").
#
# NOTA DE MÉTODO — este hook no decide por el TEXTO de un comando: decide por
# el ESTADO de un ledger JSONL en disco. Cada caso arma su propio HOME
# sintético con su STATE_DIR, así que el ledger REAL de las sesiones vivas
# nunca se toca. Modelo: deploy-checkout-guard-tests.sh, no
# force-push-guard-tests.sh.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/bg-track-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/bg-track.sh}"
CONSUMER_STOP="$HOME/.claude/hooks/block-unacked-bg.sh"
CONSUMER_PRE="$HOME/.claude/hooks/track-bg-launch.sh"
fails=0
total=0

# 0) Precondiciones duras. Un ledger con error de sintaxis no falla abierto:
#    rompe el Stop hook y el PreToolUse que dependen de él.
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — el ledger de background NO está activo." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v jq >/dev/null 2>&1 || { echo "FATAL: falta jq; el ledger no se puede leer." >&2; exit 3; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bgt-tests.XXXXXX")" || exit 3
cleanup(){ [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

NOW="$(date +%s)"

# ── Helpers ──────────────────────────────────────────────────────────────────
# Cada caso corre en su propio HOME sintético: el STATE_DIR sale de $HOME, así
# que un caso no puede contaminar a otro ni tocar el ledger de la máquina.
sbox(){ # → imprime la ruta de un HOME nuevo
  local h; h="$(mktemp -d "$TMP/home.XXXXXX")"
  mkdir -p "$h/.claude/hooks/state"
  # block-unacked-bg.sh y track-bg-launch.sh invocan "$HOME/.claude/hooks/bg-track.sh"
  # por ruta absoluta. Sin esta copia los casos de integración medirían un hook
  # AUSENTE (fail-open) y darían verde por la razón equivocada.
  cp "$HOOK" "$h/.claude/hooks/bg-track.sh" 2>/dev/null
  printf '%s' "$h"
}

# Comparar sobre una variable ya capturada, nunca con un grep silencioso al
# final de un pipe: ese grep cierra el pipe apenas matchea, y bajo
# `set -o pipefail` (línea 25) el productor muere por SIGPIPE y el pipeline
# devuelve ≠0 CON EL MATCH PRESENTE. Es una carrera: falla de a ratos.
has(){ # has <texto> <patrón> <si> <no>
  case "$1" in (*"$2"*) printf '%s' "$3";; (*) printf '%s' "$4";; esac
}

bt(){ # bt <home> <args...> — corre el hook con ese HOME
  local h="$1"; shift
  HOME="$h" CLAUDE_CODE_SESSION_ID="" bash "$HOOK" "$@"
}

# Escribe una línea de ledger cruda (para fabricar estados que `launch` no
# produce: ids numéricos, líneas corruptas, timestamps viejos).
raw(){ # raw <home> <session> <linea...>
  local h="$1" s="$2"; shift 2
  printf '%s\n' "$@" >> "$h/.claude/hooks/state/$s.jsonl"
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

# Los ids pendientes, en una sola línea separada por '|' — comparar strings
# exactos hace que un cambio de orden o un campo de más se vea.
ids(){ # ids <home> <session>
  bt "$1" pending "$2" 2>/dev/null | cut -f1 | tr '\n' '|'
}

echo "== Modelo básico: pending = lanzado y todavía no reconocido =============="

H="$(sbox)"
check "ledger inexistente no tiene pendientes" "" "$(ids "$H" nada)"
bt "$H" launch s1 a1 agent "trabajo A" >/dev/null 2>&1
check "un launch queda pendiente"             "a1|" "$(ids "$H" s1)"
bt "$H" ack a1 "reportado" s1 >/dev/null 2>&1
check "el ack lo saca de pendientes"          "" "$(ids "$H" s1)"

H="$(sbox)"
bt "$H" launch s1 a1 agent "A" >/dev/null 2>&1
bt "$H" launch s1 a2 workflow "B" >/dev/null 2>&1
bt "$H" launch s1 a3 bash-bg "C" >/dev/null 2>&1
check "tres launches, orden de lanzamiento preservado" "a1|a2|a3|" "$(ids "$H" s1)"
bt "$H" ack a2 "solo el del medio" s1 >/dev/null 2>&1
check "ack selectivo: solo saca el suyo"      "a1|a3|" "$(ids "$H" s1)"

H="$(sbox)"
bt "$H" launch sA x1 agent "de A" >/dev/null 2>&1
bt "$H" launch sB x2 agent "de B" >/dev/null 2>&1
check "ledger por sesión: A no ve a B"        "x1|" "$(ids "$H" sA)"
check "ledger por sesión: B no ve a A"        "x2|" "$(ids "$H" sB)"
bt "$H" ack x1 "cerrado" sB >/dev/null 2>&1
check "un ack en la sesión equivocada NO saca de la correcta" "x1|" "$(ids "$H" sA)"

echo
echo "== Formato de salida: 4 campos TSV (id, kind, label, age) ==============="

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"f1","kind":"agent","label":"etiqueta","ts":%s}' "$((NOW-30))")"
line="$(bt "$H" pending s1 2>/dev/null)"
check "pending emite 4 campos"                "4" "$(printf '%s' "$line" | awk -F'\t' '{print NF}')"
check "campo 1 = id"                          "f1" "$(printf '%s' "$line" | cut -f1)"
check "campo 2 = kind"                        "agent" "$(printf '%s' "$line" | cut -f2)"
check "campo 3 = label"                       "etiqueta" "$(printf '%s' "$line" | cut -f3)"
# La edad se compara por RANGO: NOW se captura al arrancar la suite y el hook
# llama a date(1) al correr, así que un segundo de deriva daría un rojo que no
# es del hook. Un rango angosto sigue detectando una unidad equivocada.
age="$(printf '%s' "$line" | cut -f4)"
check "campo 4 = edad en segundos (30..40)"   "en-rango" \
  "$(if [ "$age" -ge 30 ] && [ "$age" -le 40 ] 2>/dev/null; then echo en-rango; else echo "fuera:$age"; fi)"

H="$(sbox)"
bt "$H" launch s1 f2 agent 'label con "comillas" y $dolares' >/dev/null 2>&1
check "label con comillas y \$ no rompe el JSONL" 'label con "comillas" y $dolares' "$(bt "$H" pending s1 2>/dev/null | cut -f3)"
check "el ledger sigue siendo JSONL válido"   "1" "$(jq -R 'fromjson?' "$H/.claude/hooks/state/s1.jsonl" 2>/dev/null | jq -s 'length')"

H="$(sbox)"
bt "$H" launch s1 f3 agent "$(printf 'dos\nlineas')" >/dev/null 2>&1
check "label multilínea no parte la línea del ledger" "1" "$(wc -l < "$H/.claude/hooks/state/s1.jsonl" | tr -d ' ')"
check "label multilínea deja UN solo pendiente" "f3|" "$(ids "$H" s1)"

echo
echo "== ÁMBITO TEMPORAL: un ack sólo tapa lo lanzado ANTES ==================="
# Clase de agujero que ya apareció en deploy-checkout-guard (#1998),
# block-unbounded-polls (#2019) y pinned-tool-guard (#2061): el estado se
# buscaba en TODO el archivo en vez del tramo que corresponde. Acá el tramo es
# TEMPORAL: un ack registrado ANTES de un launch no puede reconocerlo.

H="$(sbox)"
bt "$H" launch s1 r1 agent "primera corrida" >/dev/null 2>&1
bt "$H" ack r1 "primera reportada" s1 >/dev/null 2>&1
bt "$H" launch s1 r1 agent "SEGUNDA corrida, mismo id" >/dev/null 2>&1
check "relanzar un id ya reconocido vuelve a dejarlo pendiente" "r1|" "$(ids "$H" s1)"
bt "$H" ack r1 "segunda reportada" s1 >/dev/null 2>&1
check "y el ack siguiente vuelve a limpiarlo" "" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"ack","id":"p1","reason":"preventivo","ts":%s}' "$((NOW-100))")"
raw "$H" s1 "$(printf '{"op":"launch","id":"p1","kind":"agent","label":"posterior","ts":%s}' "$((NOW-10))")"
check "un ack PREVIO no reconoce un launch posterior" "p1|" "$(ids "$H" s1)"

H="$(sbox)"
bt "$H" launch s1 d1 agent "una" >/dev/null 2>&1
bt "$H" launch s1 d1 agent "otra, mismo id sin ack" >/dev/null 2>&1
check "dos launches del mismo id sin ack: ambos pendientes" "d1|d1|" "$(ids "$H" s1)"
bt "$H" ack d1 "las dos" s1 >/dev/null 2>&1
check "un ack posterior tapa a las dos"       "" "$(ids "$H" s1)"

echo
echo "== Techo de edad (MAX_AGE_SECS) ========================================="

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"v1","kind":"agent","label":"5h","ts":%s}' "$((NOW-18000))")"
check "entrada de 5h ya no está pendiente (techo 4h)" "" "$(ids "$H" s1)"
H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"v2","kind":"agent","label":"3h","ts":%s}' "$((NOW-10800))")"
check "entrada de 3h sigue pendiente"         "v2|" "$(ids "$H" s1)"

H="$(sbox)"
bt "$H" launch s1 m1 agent "viva" >/dev/null 2>&1
check "MAX_AGE explícito y numérico se respeta" "" "$(HOME="$H" CLAUDE_BG_TRACK_MAX_AGE=0 bash "$HOOK" pending s1 2>/dev/null | cut -f1 | tr '\n' '|')"

# CIEGO SILENCIOSO: el comentario del propio hook dice "# 4h" al lado del
# 14400, así que escribir CLAUDE_BG_TRACK_MAX_AGE=4h es el error natural. Con
# --argjson eso revienta jq, `|| true` se lo traga y `pending` sale VACÍO con
# rc=0: el Stop cree que no hay nada y el ledger queda apagado sin ruido.
for badv in "4h" "abc" "14400s" "1e4x" " "; do
  H="$(sbox)"
  bt "$H" launch s1 mb agent "viva" >/dev/null 2>&1
  check "MAX_AGE inválido ('$badv') NO ciega el ledger" "mb|" \
    "$(HOME="$H" CLAUDE_BG_TRACK_MAX_AGE="$badv" bash "$HOOK" pending s1 2>/dev/null | cut -f1 | tr '\n' '|')"
done
H="$(sbox)"
bt "$H" launch s1 mv agent "viva" >/dev/null 2>&1
check "MAX_AGE inválido avisa por stderr"     "aviso" \
  "$(has "$(HOME="$H" CLAUDE_BG_TRACK_MAX_AGE=4h bash "$HOOK" pending s1 2>&1 >/dev/null)" 'CLAUDE_BG_TRACK_MAX_AGE' aviso mudo)"
H="$(sbox)"
bt "$H" launch s1 mz agent "viva" >/dev/null 2>&1
check "MAX_AGE vacío cae al default (no ciega)" "mz|" \
  "$(HOME="$H" CLAUDE_BG_TRACK_MAX_AGE="" bash "$HOOK" pending s1 2>/dev/null | cut -f1 | tr '\n' '|')"

echo
echo "== Escape hatch: unblock TIENE que desbloquear =========================="
# Es la garantía más fuerte del hook y la que block-unacked-bg.sh imprime como
# última salida al usuario. Si falla, el turno no se puede cerrar.

H="$(sbox)"
bt "$H" launch s1 u1 agent "A" >/dev/null 2>&1
bt "$H" launch s1 u2 agent "B" >/dev/null 2>&1
bt "$H" unblock u1 s1 >/dev/null 2>&1
check "unblock <id> saca solo ese"            "u2|" "$(ids "$H" s1)"
bt "$H" unblock --all s1 >/dev/null 2>&1
check "unblock --all limpia todo"             "" "$(ids "$H" s1)"

# Ids que el ledger PUEDE contener (línea escrita a mano, ledger corrupto a
# medias, un futuro productor distinto): si `pending` los muestra, `unblock`
# los tiene que poder sacar. Hoy `pending` emite @tsv (escapa \t, \n y \\) y
# `ack` compara contra el valor CRUDO, así que el escape hatch no los alcanza.
H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"a\\tb","kind":"agent","label":"tab","ts":%s}' "$NOW")"
bt "$H" unblock --all s1 >/dev/null 2>&1
check "unblock --all limpia un id con TAB"    "" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"a\\nb","kind":"agent","label":"nl","ts":%s}' "$NOW")"
bt "$H" unblock --all s1 >/dev/null 2>&1
check "unblock --all limpia un id con newline" "" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"a\\\\b","kind":"agent","label":"bslash","ts":%s}' "$NOW")"
bt "$H" unblock --all s1 >/dev/null 2>&1
check "unblock --all limpia un id con backslash" "" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":123,"kind":"agent","label":"num","ts":%s}' "$NOW")"
bt "$H" unblock --all s1 >/dev/null 2>&1
check "unblock --all limpia un id NUMÉRICO"   "" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":123,"kind":"agent","label":"num","ts":%s}' "$NOW")"
bt "$H" ack 123 "por id numérico" s1 >/dev/null 2>&1
check "ack de un id numérico del ledger funciona" "" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"esp acio","kind":"agent","label":"sp","ts":%s}' "$NOW")"
bt "$H" unblock --all s1 >/dev/null 2>&1
check "unblock --all limpia un id con espacios" "" "$(ids "$H" s1)"

H="$(sbox)"
bt "$H" unblock --all s-vacia >/dev/null 2>&1
check "unblock --all sin pendientes no falla" "0" "$?"

echo
echo "== ack que no reconoce nada: NO puede ser mudo =========================="
# El caso medido el 2026-09-07 (#2061): ackear con el id que devuelve el tool
# Bash en vez del `toolu_` del ledger da rc=0 SIN HACER NADA, el Stop vuelve a
# bloquear y no hay ninguna señal de por qué. Fail-open manda: no debe fallar,
# pero tiene que DECIRLO.

H="$(sbox)"
bt "$H" launch s1 toolu_correcto agent "trabajo" >/dev/null 2>&1
out="$(bt "$H" ack bnhs8h39j "id del harness, no el del ledger" s1 2>&1 >/dev/null)"
check "ack de un id inexistente avisa"        "avisa" "$([ -n "$out" ] && echo avisa || echo mudo)"
check "ack de un id inexistente NO rompe el flujo (fail-open)" "0" \
  "$(bt "$H" ack otro-inexistente "x" s1 >/dev/null 2>&1; echo $?)"
check "ack de un id inexistente no toca a los pendientes reales" "toolu_correcto|" "$(ids "$H" s1)"
check "el aviso nombra los pendientes reales" "nombra" \
  "$(has "$(bt "$H" ack bnhs8h39j "x" s1 2>&1 >/dev/null)" 'toolu_correcto' nombra no-nombra)"
out="$(bt "$H" ack toolu_correcto "bien reportado" s1 2>&1 >/dev/null)"
check "un ack correcto NO avisa (no es ruido)" "" "$out"

echo
echo "== Fail-open: un ledger roto nunca debe trabar al usuario ==============="

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"ok1","kind":"agent","label":"buena","ts":%s}' "$NOW")" \
             '{ROTA no es json' \
             "$(printf '{"op":"launch","id":"ok2","kind":"agent","label":"buena2","ts":%s}' "$NOW")"
check "una línea corrupta no ciega al resto"  "ok1|ok2|" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 '' "$(printf '{"op":"launch","id":"ok3","kind":"agent","label":"b","ts":%s}' "$NOW")" ''
check "líneas vacías se ignoran"              "ok3|" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"sinTs","kind":"agent","label":"b"}')" \
             "$(printf '{"op":"launch","id":"conTs","kind":"agent","label":"b","ts":%s}' "$NOW")"
check "una entrada sin ts no ciega al resto"  "conTs|" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","kind":"agent","label":"sin id","ts":%s}' "$NOW")" \
             "$(printf '{"op":"launch","id":"conId","kind":"agent","label":"b","ts":%s}' "$NOW")"
check "una entrada sin id no ciega al resto"  "conId|" "$(ids "$H" s1)"

H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"otra-cosa","id":"z","ts":%s}' "$NOW")" \
             "$(printf '{"op":"launch","id":"real","kind":"agent","label":"b","ts":%s}' "$NOW")"
check "un op desconocido se ignora"           "real|" "$(ids "$H" s1)"

H="$(sbox)"
check "pending sin session_id sale limpio"    "0" "$(bt "$H" pending >/dev/null 2>&1; echo $?)"
check "pending sin session_id no imprime nada" "" "$(bt "$H" pending 2>/dev/null)"

H="$(sbox)"
check "ack sin session_id falla con mensaje"  "1" "$(bt "$H" ack idx "r" >/dev/null 2>&1; echo $?)"
check "ack sin session_id explica cómo darlo" "explica" \
  "$(has "$(bt "$H" ack idx "r" 2>&1 >/dev/null)" 'session_id' explica mudo)"

H="$(sbox)"
check "launch sin id falla (no escribe basura)" "1" "$(bt "$H" launch s1 >/dev/null 2>&1; echo $?)"
check "launch sin id no crea ledger"          "no" "$([ -f "$H/.claude/hooks/state/s1.jsonl" ] && echo si || echo no)"
check "comando desconocido sale 1 con uso"    "1" "$(bt "$H" frobnicate >/dev/null 2>&1; echo $?)"
check "sin comando sale 1 con uso"            "1" "$(bt "$H" >/dev/null 2>&1; echo $?)"

echo
echo "== Integración con los dos consumidores ================================="

if [ -f "$CONSUMER_STOP" ]; then
  H="$(sbox)"
  bt "$H" launch ses-int i1 agent "sin reconocer" >/dev/null 2>&1
  rc="$(printf '{"session_id":"ses-int"}' | HOME="$H" bash "$CONSUMER_STOP" >/dev/null 2>&1; echo $?)"
  check "Stop BLOQUEA (exit 2) con un pendiente" "2" "$rc"
  msg="$(printf '{"session_id":"ses-int"}' | HOME="$H" bash "$CONSUMER_STOP" 2>&1 >/dev/null)"
  check "el bloqueo nombra el id a ackear"    "nombra" "$(has "$msg" 'i1' nombra no-nombra)"
  check "el bloqueo ofrece el escape hatch"   "ofrece" "$(has "$msg" 'unblock --all' ofrece no-ofrece)"
  bt "$H" ack i1 "reportado" ses-int >/dev/null 2>&1
  rc="$(printf '{"session_id":"ses-int"}' | HOME="$H" bash "$CONSUMER_STOP" >/dev/null 2>&1; echo $?)"
  check "Stop DEJA PASAR (exit 0) tras el ack" "0" "$rc"
  rc="$(printf '' | HOME="$H" bash "$CONSUMER_STOP" >/dev/null 2>&1; echo $?)"
  check "Stop con input vacío deja pasar"     "0" "$rc"
  rc="$(printf '{"no":"session"}' | HOME="$H" bash "$CONSUMER_STOP" >/dev/null 2>&1; echo $?)"
  check "Stop sin session_id deja pasar"      "0" "$rc"

  # El escape hatch que el propio mensaje de bloqueo promete, ejercido de punta
  # a punta: si esto falla, el usuario lee la instrucción, la ejecuta y sigue
  # bloqueado.
  H="$(sbox)"
  raw "$H" ses-esc "$(printf '{"op":"launch","id":"a\\tb","kind":"agent","label":"raro","ts":%s}' "$NOW")"
  bt "$H" unblock --all ses-esc >/dev/null 2>&1
  rc="$(printf '{"session_id":"ses-esc"}' | HOME="$H" bash "$CONSUMER_STOP" >/dev/null 2>&1; echo $?)"
  check "tras unblock --all el Stop deja pasar de verdad" "0" "$rc"
else
  echo "  (block-unacked-bg.sh ausente: 0 casos de integración Stop)"
fi

if [ -f "$CONSUMER_PRE" ]; then
  H="$(sbox)"
  p='{"tool_name":"Agent","session_id":"ses-pre","tool_use_id":"toolu_A","tool_input":{"description":"buscar cosas"}}'
  printf '%s' "$p" | HOME="$H" bash "$CONSUMER_PRE" >/dev/null 2>&1
  check "PreToolUse registra un Agent"        "toolu_A|" "$(ids "$H" ses-pre)"
  check "el kind del Agent es 'agent'"        "agent" "$(bt "$H" pending ses-pre 2>/dev/null | cut -f2)"
  H="$(sbox)"
  p='{"tool_name":"Bash","session_id":"ses-pre","tool_use_id":"toolu_B","tool_input":{"command":"sleep 1","run_in_background":false}}'
  printf '%s' "$p" | HOME="$H" bash "$CONSUMER_PRE" >/dev/null 2>&1
  check "un Bash NO background no se registra" "" "$(ids "$H" ses-pre)"
  p='{"tool_name":"Bash","session_id":"ses-pre","tool_use_id":"toolu_C","tool_input":{"command":"sleep 1","run_in_background":true}}'
  printf '%s' "$p" | HOME="$H" bash "$CONSUMER_PRE" >/dev/null 2>&1
  check "un Bash en background SÍ se registra" "toolu_C|" "$(ids "$H" ses-pre)"
  H="$(sbox)"
  p='{"tool_name":"Read","session_id":"ses-pre","tool_use_id":"toolu_D","tool_input":{"file_path":"/x"}}'
  printf '%s' "$p" | HOME="$H" bash "$CONSUMER_PRE" >/dev/null 2>&1
  check "un tool no-background no se registra" "" "$(ids "$H" ses-pre)"
  check "PreToolUse NUNCA bloquea (exit 0)"   "0" \
    "$(printf 'basura no json' | HOME="$H" bash "$CONSUMER_PRE" >/dev/null 2>&1; echo $?)"
else
  echo "  (track-bg-launch.sh ausente: 0 casos de integración PreToolUse)"
fi

echo
echo "== LÍMITES fijados a propósito (no son bugs: son el precio elegido) ====="

# 1) El session_id lo pone el harness desde el payload del hook, nunca el
#    usuario. Un session con ../ escribe fuera del STATE_DIR, pero para llegar
#    ahí ya hay que controlar el payload del hook, que es un problema mayor.
#    Sanitizarlo cambiaría la ruta del ledger de las sesiones vivas.
H="$(sbox)"
bt "$H" launch "../state/evadida" ev agent "traversal suave" >/dev/null 2>&1
check "LÍMITE: session con ../ escribe fuera del nombre esperado" "si" \
  "$([ -f "$H/.claude/hooks/state/evadida.jsonl" ] && echo si || echo no)"

# 2) El ledger crece sin rotación: un `ack` no borra la línea del `launch`,
#    sólo la tapa. Es deliberado — el ledger es una bitácora auditable, y el
#    techo de 4h ya acota lo que se evalúa como pendiente.
H="$(sbox)"
bt "$H" launch s1 g1 agent "x" >/dev/null 2>&1
bt "$H" ack g1 "y" s1 >/dev/null 2>&1
check "LÍMITE: el ack no borra, deja bitácora" "2" "$(wc -l < "$H/.claude/hooks/state/s1.jsonl" | tr -d ' ')"

# 3) Un ledger ilegible deja `pending` vacío en silencio. Es el fail-open
#    declarado en la cabecera (línea 21): preferimos no bloquear a nadie antes
#    que trabar un turno por un permiso raro.
H="$(sbox)"
raw "$H" s1 "$(printf '{"op":"launch","id":"perm","kind":"agent","label":"x","ts":%s}' "$NOW")"
chmod 000 "$H/.claude/hooks/state/s1.jsonl" 2>/dev/null
check "LÍMITE: ledger ilegible = fail-open ciego" "" "$(ids "$H" s1)"
chmod 644 "$H/.claude/hooks/state/s1.jsonl" 2>/dev/null

# 4) Sin lock de escritura: dos launches concurrentes se apoyan en que el
#    append de una línea corta (<PIPE_BUF) es atómico. El label está cortado a
#    120 chars justamente para que la línea entre.
H="$(sbox)"
for i in 1 2 3 4 5 6 7 8; do bt "$H" launch s1 "c$i" agent "concurrente $i" >/dev/null 2>&1 & done
wait
check "LÍMITE: 8 launches concurrentes, ninguna línea partida" "8" \
  "$(jq -R 'fromjson?' "$H/.claude/hooks/state/s1.jsonl" 2>/dev/null | jq -s 'length')"

echo
if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails/$total casos fallan — el ledger de background tiene agujeros." >&2
  exit 1
fi
echo "OK: $total/$total casos del contrato del ledger de background pasan."
exit 0
