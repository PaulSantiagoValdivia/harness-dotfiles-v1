#!/usr/bin/env bash
# Suite de contrato de block-unacked-bg.sh — el Stop hook que BLOQUEA el cierre
# del turno cuando queda trabajo en background sin reconocer.
#
# Este hook falla mudo en las dos direcciones y las dos son caras:
#   - de MENOS: deja cerrar el turno con un Agent/Workflow/Bash colgado. El
#     usuario nunca se entera de que había algo corriendo.
#   - de MÁS: bloquea y no se puede salir. Su propia cabecera (líneas 10-13) lo
#     pone como la promesa más fuerte: "un bug acá NUNCA debe dejar al usuario
#     sin poder cerrar un turno". Por eso el eje A mide exit 0 contra un ledger
#     roto, ausente y mentiroso — no sólo contra el camino feliz.
#
# El mensaje NO es cosmético: es la única salida del hook, la consume el modelo
# en CADA Stop hasta el ack, y es lo que le dice qué ackear. Un mensaje corrido
# de campos manda a ackear un id que no existe.
#
# Relación con bg-track-tests.sh: aquella mide el LEDGER y tiene 7 casos de
# integración de este hook (bloquea / deja pasar). Esta mide su CONTRATO: el
# canal de salida, la integridad de los campos y el fail-open. Solape barato.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/block-unacked-bg-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/block-unacked-bg.sh}"
LEDGER_HOOK="$HOME/.claude/hooks/bg-track.sh"
fails=0
total=0

if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — el turno se cierra sin control de background." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis (un Stop hook roto traba el turno)." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
[ -f "$LEDGER_HOOK" ] || { echo "FATAL: no existe $LEDGER_HOOK." >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: falta jq." >&2; exit 3; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/bub-tests.XXXXXX")" || exit 3
cleanup(){ [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

sbox(){ # → HOME nuevo con su copia del ledger (mktemp -d: $(sbox) es un SUBSHELL)
  local h; h="$(mktemp -d "$TMP/home.XXXXXX")"
  mkdir -p "$h/.claude/hooks/state"
  cp "$LEDGER_HOOK" "$h/.claude/hooks/bg-track.sh" 2>/dev/null
  printf '%s' "$h"
}

bt(){ local h="$1"; shift; HOME="$h" bash "$h/.claude/hooks/bg-track.sh" "$@"; }

# Entradas CRUDAS al ledger. Los casos interesantes (label vacío, kind vacío) son
# justo los que el productor ya no genera: fabricarlos con `launch` mediría otra
# cosa. Ver [[tsv-no-representa-campo-vacio]]: las entradas mutiladas van crudas.
rawled(){ # rawled <home> <session> <id> <kind> <label> [edad-en-segundos]
  local h="$1" s="$2" ts=$(( $(date +%s) - ${6:-5} ))
  jq -nc --arg id "$3" --arg k "$4" --arg l "$5" --argjson ts "$ts" \
    '{op:"launch", id:$id, kind:$k, label:$l, ts:$ts}' \
    >> "$h/.claude/hooks/state/$s.jsonl"
}

rc(){ # rc <home> <session> → exit code del Stop
  local h="$1" s="$2"
  printf '{"session_id":"%s"}' "$s" | HOME="$h" bash "$HOOK" >/dev/null 2>&1
  printf '%s' "$?"
}

err(){ # err <home> <session> → SOLO el stderr del Stop
  local h="$1" s="$2"
  printf '{"session_id":"%s"}' "$s" | HOME="$h" bash "$HOOK" 2>&1 >/dev/null
}

out(){ # out <home> <session> → SOLO el stdout del Stop
  local h="$1" s="$2"
  printf '{"session_id":"%s"}' "$s" | HOME="$h" bash "$HOOK" 2>/dev/null
}

has(){ case "$1" in (*"$2"*) printf '%s' "$3";; (*) printf '%s' "$4";; esac; }

# La edad se compara por RANGO, nunca por string exacto: entre que el fixture
# escribe el ts y que el hook lo lee pasa tiempo real. Un caso flaky no sirve.
agein(){ # agein <msg> <min> <max> → SI/NO
  local a; a="$(printf '%s' "$1" | sed -n 's/.*hace \([0-9][0-9]*\)s.*/\1/p' | head -1)"
  if [ -n "$a" ] && [ "$a" -ge "$2" ] && [ "$a" -le "$3" ]; then printf SI; else printf NO; fi
}

check(){
  total=$((total+1))
  if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
  else fails=$((fails+1)); printf '  FAIL %s\n       esperado: [%s]\n       obtenido: [%s]\n' "$1" "$2" "$3"; fi
}

echo "== A) Promesa más fuerte: NUNCA deja al usuario sin cerrar el turno ====="
h=$(sbox); check "input vacío deja pasar"        0 "$(printf '' | HOME="$h" bash "$HOOK" >/dev/null 2>&1; printf '%s' $?)"
h=$(sbox); check "JSON inválido deja pasar"      0 "$(printf 'no-json{{{' | HOME="$h" bash "$HOOK" >/dev/null 2>&1; printf '%s' $?)"
h=$(sbox); check "sin session_id deja pasar"     0 "$(printf '{"foo":1}' | HOME="$h" bash "$HOOK" >/dev/null 2>&1; printf '%s' $?)"
h=$(sbox); check "sesión sin ledger deja pasar"  0 "$(rc "$h" S)"
h=$(sbox); rm -f "$h/.claude/hooks/bg-track.sh"
           check "ledger AUSENTE deja pasar"     0 "$(rc "$h" S)"
h=$(sbox); rawled "$h" S t1 agent "algo"
           printf '#!/usr/bin/env bash\nexit 1\n' > "$h/.claude/hooks/bg-track.sh"
           check "ledger que FALLA deja pasar"   0 "$(rc "$h" S)"
h=$(sbox); rawled "$h" S t1 agent "algo"
           printf 'if then fi(((\n' > "$h/.claude/hooks/bg-track.sh"
           check "ledger con error de sintaxis deja pasar" 0 "$(rc "$h" S)"
h=$(sbox); printf 'basura no-json\n' >> "$h/.claude/hooks/state/S.jsonl"
           check "ledger corrupto deja pasar"    0 "$(rc "$h" S)"

echo "== B) Bloquea cuando hay trabajo sin reconocer =========================="
h=$(sbox); rawled "$h" S t1 agent "revisar el diff" 7
           check "un pendiente BLOQUEA (exit 2)" 2 "$(rc "$h" S)"
m="$(err "$h" S)"
           check "el mensaje nombra el id"       SI "$(has "$m" 'id=t1' SI NO)"
           check "el mensaje nombra el kind"     SI "$(has "$m" '[agent]' SI NO)"
           check "el mensaje nombra el label"    SI "$(has "$m" 'revisar el diff' SI NO)"
           check "el mensaje muestra la edad"    SI "$(agein "$m" 7 20)"
           check "el mensaje ofrece el ack"      SI "$(has "$m" 'bg-track.sh ack' SI NO)"
           check "el mensaje ofrece el escape hatch" SI "$(has "$m" 'unblock --all' SI NO)"
# El canal importa: un Stop hook comunica con el modelo por STDERR + exit 2. Si
# el mensaje se fuera por stdout, el hook bloquearía MUDO — el usuario vería el
# turno trabado sin ninguna instrucción de cómo salir.
           check "el mensaje va por STDERR"      SI "$(has "$m" 'BLOQUEADO' SI NO)"
           check "stdout queda VACÍO"            "" "$(out "$h" S)"

echo "== C) Ciclo completo: ack y unblock ====================================="
h=$(sbox); rawled "$h" S t1 agent "uno"; rawled "$h" S t2 workflow "dos"; rawled "$h" S t3 bash-bg "tres"
           check "tres pendientes bloquean"      2 "$(rc "$h" S)"
m="$(err "$h" S)"
           check "los tres aparecen en el mensaje" "SI SI SI" \
             "$(has "$m" 'id=t1' SI NO) $(has "$m" 'id=t2' SI NO) $(has "$m" 'id=t3' SI NO)"
           bt "$h" ack t2 "listo" S >/dev/null 2>&1
           check "tras ackear uno SIGUE bloqueando" 2 "$(rc "$h" S)"
m="$(err "$h" S)"
           check "el ackeado ya no aparece"      NO "$(has "$m" 'id=t2' SI NO)"
           check "los otros dos siguen"          "SI SI" \
             "$(has "$m" 'id=t1' SI NO) $(has "$m" 'id=t3' SI NO)"
           bt "$h" ack t1 "listo" S >/dev/null 2>&1; bt "$h" ack t3 "listo" S >/dev/null 2>&1
           check "con todo ackeado deja pasar"   0 "$(rc "$h" S)"
h=$(sbox); rawled "$h" S t1 agent "uno"; rawled "$h" S t2 agent "dos"
           bt "$h" unblock --all S >/dev/null 2>&1
           check "tras unblock --all deja pasar" 0 "$(rc "$h" S)"

echo "== D) Integridad de campos: el TSV no puede representar un campo vacío ==="
# `while IFS=$'\t' read -r id kind label age` NO conserva los campos vacíos: el
# TAB es IFS-whitespace, las secuencias se colapsan y la línea se relee CORRIDA.
# Con label vacío el mensaje mostraba `[bash-bg] "0" (hace s)`: el label se comió
# la EDAD y la edad quedó vacía. Medido 2026-09-08. Manda a ackear con los datos
# equivocados, que es exactamente lo que este mensaje existe para evitar.
h=$(sbox); rawled "$h" S t1 bash-bg "" 9
           check "label vacío: sigue bloqueando"     2 "$(rc "$h" S)"
m="$(err "$h" S)"
           check "label vacío: el id NO se corre"    SI "$(has "$m" 'id=t1' SI NO)"
           check "label vacío: el kind NO se corre"  SI "$(has "$m" '[bash-bg]' SI NO)"
           check "label vacío: la edad NO se corre"  SI "$(agein "$m" 9 25)"
           check "label vacío: la edad no queda VACÍA"       NO "$(has "$m" 'hace s' SI NO)"
           check "label vacío: muestra algo legible en su lugar" SI "$(has "$m" 'sin etiqueta' SI NO)"
h=$(sbox); rawled "$h" S t2 "" "una etiqueta" 4
           check "kind vacío: la edad NO se corre"   SI "$(agein "$(err "$h" S)" 4 20)"
           check "kind vacío: el label NO se corre"  SI "$(has "$(err "$h" S)" 'una etiqueta' SI NO)"
           check "kind vacío: muestra '?' en su lugar"      SI "$(has "$(err "$h" S)" '[?]' SI NO)"
# El hook NO controla lo que `pending` le entrega. Si el ledger emitiera una
# linea mutilada, imprimir sus campos crudos produciria un mensaje MENTIROSO
# (una edad en blanco se lee como "recien lanzado"). Ante basura, dice '?'.
h=$(sbox); printf '#!/usr/bin/env bash\nprintf "t9\\tagent\\tetiqueta\\tno-es-un-numero\\n"\n' > "$h/.claude/hooks/bg-track.sh"
           check "pending mutilado: sigue bloqueando"        2 "$(rc "$h" S)"
           check "pending mutilado: no inventa una edad"     SI "$(has "$(err "$h" S)" 'hace ?s' SI NO)"

# Un label con espacios NO debe partirse: con IFS=$'\t' sólo el TAB separa, pero
# si alguien "arregla" el parseo con un IFS por defecto, este caso lo caza.
h=$(sbox); rawled "$h" S t3 agent "tres palabras juntas" 4
           check "label con espacios llega entero"   SI "$(has "$(err "$h" S)" 'tres palabras juntas' SI NO)"
           check "label con espacios: edad intacta"  SI "$(agein "$(err "$h" S)" 4 20)"
# bg-track escapa los saltos a \n antes de emitir el TSV, así que una entrada
# multilínea ocupa UNA línea del mensaje y no fabrica entradas fantasma.
h=$(sbox); rawled "$h" S t4 agent "linea uno
linea dos" 4
           check "label multilínea: UNA sola entrada listada" 1 \
             "$(err "$h" S | grep -c 'id=' | tr -d ' ')"

# Una linea de `pending` con el id vacio no debe producir una entrada fantasma:
# el mensaje mandaria a ackear un id que no existe.
h=$(sbox); {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "\\tagent\\tfantasma\\t5\\nt7\\tagent\\treal\\t5\\n"\n'
  } > "$h/.claude/hooks/bg-track.sh"
           check "pending con id vacío: no lista el fantasma" 1 "$(err "$h" S | grep -c 'id=' | tr -d ' ')"
           check "pending con id vacío: sí lista la real"     SI "$(has "$(err "$h" S)" 'id=t7' SI NO)"

echo "== E) Aislamiento por sesión ============================================"
h=$(sbox); rawled "$h" A t1 agent "de A"
           check "pendiente en A bloquea el Stop de A"    2 "$(rc "$h" A)"
           check "pendiente en A NO bloquea el Stop de B" 0 "$(rc "$h" B)"

echo "== F) LÍMITES declarados a propósito ===================================="
# El hook confía en `pending`: si el ledger miente (de menos), el Stop deja pasar
# sin avisar. Es fail-open CIEGO y es deliberado — la alternativa es trabar el
# turno por un bug del propio ledger, que la cabecera prohíbe explícitamente.
h=$(sbox); rawled "$h" S t1 agent "algo"
           printf '#!/usr/bin/env bash\nexit 0\n' > "$h/.claude/hooks/bg-track.sh"
           check "LÍMITE: un ledger que miente de menos deja pasar mudo" 0 "$(rc "$h" S)"
# El hook NO verifica que el ack sea VERAZ: un `ack <id> "cualquier cosa"` limpia
# el pendiente aunque el trabajo siga corriendo. Es por diseño — el ledger mide
# el RECONOCIMIENTO, no la terminación del proceso.
h=$(sbox); rawled "$h" S t1 agent "sigue corriendo"
           bt "$h" ack t1 "mentira" S >/dev/null 2>&1
           check "LÍMITE: el ack no se valida contra el proceso real" 0 "$(rc "$h" S)"

echo
if [ "$fails" -eq 0 ]; then
  printf 'Resultado: %s PASS / 0 FAIL\n' "$total"; exit 0
fi
printf 'Resultado: %s PASS / %s FAIL (de %s)\n' "$((total-fails))" "$fails" "$total"
exit 1
