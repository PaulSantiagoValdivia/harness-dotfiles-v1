#!/usr/bin/env bash
# Suite de contrato de report-live-children.sh — el Stop hook INFORMATIVO que
# lista los procesos hijos todavía vivos al cerrar el turno.
#
# Es el hermano no-bloqueante del ledger de background: donde block-unacked-bg
# BLOQUEA, éste sólo avisa, y donde reap-stale-polls MATA, éste no toca nada. Su
# única salida es el texto que imprime: si ese texto miente, sale ruido o sale
# vacío cuando no debe, el hook no protege nada.
#
# NOTA DE MÉTODO — este hook no decide por texto ni por estado en disco: decide
# por el ÁRBOL DE PROCESOS REAL. `PPID` es una variable especial de bash que el
# shell reescribe al arrancar, así que NO se puede falsear por entorno: cada
# caso arma un árbol de verdad, con los hijos colgando del MISMO padre que corre
# el hook. Por eso los fixtures lanzan `sleep` reales y los matan al terminar.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/report-live-children-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/report-live-children.sh}"
fails=0
total=0

if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — el cierre de turno no avisa de procesos vivos." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis (un Stop hook roto traba el turno)." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v ps >/dev/null 2>&1 || { echo "FATAL: falta ps." >&2; exit 3; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rlc-tests.XXXXXX")" || exit 3
trap '[ -n "${TMP:-}" ] && rm -rf "$TMP"' EXIT

check(){
  total=$((total+1))
  if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"
  else fails=$((fails+1)); printf '  FAIL %s\n       esperado: [%s]\n       obtenido: [%s]\n' "$1" "$2" "$3"; fi
}

has(){ case "$1" in (*"$2"*) printf '%s' "$3";; (*) printf '%s' "$4";; esac; }

# ── Árbol de procesos real ───────────────────────────────────────────────────
# Los hijos se lanzan en el MISMO shell que después corre el hook, así que el
# PPID que el hook lee es el de ese shell y los `sleep` son sus descendientes.
# El `; :` del nieto es deliberado: `bash -c "sleep 30"` a secas hace exec y se
# convierte EN el sleep (un hijo directo, no un nieto), y el caso de recursión
# mediría otra cosa.
tree_err(){ # tree_err [env...] → SOLO el stderr del hook, con 2 hijos + 1 nieto
  env "$@" bash -c '
    sleep 20 >/dev/null 2>&1 &
    sleep 20 >/dev/null 2>&1 &
    bash -c "sleep 20; :" >/dev/null 2>&1 &
    bash "$0" 2>&1 >/dev/null
    kill $(jobs -p) 2>/dev/null
  ' "$HOOK" 2>/dev/null
}

tree_out(){ # tree_out [env...] → SOLO el stdout del hook
  env "$@" bash -c '
    sleep 20 >/dev/null 2>&1 &
    bash "$0" 2>/dev/null
    kill $(jobs -p) 2>/dev/null
  ' "$HOOK"
}

tree_rc(){ # tree_rc [env...] → exit code del hook
  env "$@" bash -c '
    sleep 20 >/dev/null 2>&1 &
    bash "$0" >/dev/null 2>&1
    rc=$?
    kill $(jobs -p) 2>/dev/null
    exit $rc
  ' "$HOOK"; printf '%s' "$?"
}

lonely_rc(){ # lonely_rc → exit code sin ningún hijo vivo
  env "$@" bash -c 'bash "$0" >/dev/null 2>&1; printf "%s" $?' "$HOOK"
}

lonely_err(){ env "$@" bash -c 'bash "$0" 2>&1 >/dev/null' "$HOOK"; }

# El tramo etime→segundos se extrae del archivo VIVO y se evalúa suelto: mide el
# artefacto, no una copia. Si alguien renombra o borra la función, el `eval` no
# define nada y los casos del eje E se caen — que es lo correcto.
eval "$(awk '/^etime_to_secs\(\) \{/,/^\}/' "$HOOK")" 2>/dev/null || true

echo "== A) Promesa más fuerte: es INFORMATIVO, jamás bloquea (exit 0) ========"
check "sin hijos vivos sale 0"                 0 "$(lonely_rc)"
check "con hijos vivos sale 0"                 0 "$(tree_rc CLAUDE_REPORT_CHILDREN_MIN_AGE=0)"
check "MIN_AGE no numérico sale 0"             0 "$(tree_rc CLAUDE_REPORT_CHILDREN_MIN_AGE=5m)"
check "MIN_AGE negativo sale 0"                0 "$(tree_rc CLAUDE_REPORT_CHILDREN_MIN_AGE=-1)"
check "MIN_AGE vacío sale 0"                   0 "$(tree_rc CLAUDE_REPORT_CHILDREN_MIN_AGE=)"
check "MIN_AGE gigante sale 0"                 0 "$(tree_rc CLAUDE_REPORT_CHILDREN_MIN_AGE=999999)"

echo "== B) Silencio cuando no hay nada que decir ============================="
# Un Stop hook que imprime en cada turno se vuelve ruido de fondo y deja de
# leerse. Sin nada vivo no debe emitir NI el encabezado.
check "sin hijos no imprime nada"              "" "$(lonely_err)"
check "todo por debajo de MIN_AGE: silencio"   "" "$(tree_err CLAUDE_REPORT_CHILDREN_MIN_AGE=999999)"

echo "== C) Qué reporta y por dónde =========================================="
m="$(tree_err CLAUDE_REPORT_CHILDREN_MIN_AGE=0)"
check "CONTROL: con MIN_AGE=0 ve los hijos"    SI "$(has "$m" 'sleep 20' SI NO)"
check "imprime el encabezado"                  SI "$(has "$m" 'report-live-children' SI NO)"
check "el encabezado sale UNA sola vez"        1  "$(printf '%s\n' "$m" | grep -c 'procesos aún vivos' | tr -d ' ')"
check "lista el pid"                           SI "$(has "$m" 'pid=' SI NO)"
check "lista la edad"                          SI "$(has "$m" 'edad=' SI NO)"
check "pide explicitar lo intencional"         SI "$(has "$m" 'no lo dejes en silencio' SI NO)"
# El canal importa: por stdout el aviso se mezclaría con la respuesta del turno.
check "el aviso va por STDERR"                 SI "$(has "$m" 'pid=' SI NO)"
check "stdout queda VACÍO"                     "" "$(tree_out CLAUDE_REPORT_CHILDREN_MIN_AGE=0)"
# Son CUATRO, no tres: 2 hijos directos + el bash intermedio + su nieto. El
# intermedio es un descendiente como cualquier otro y tiene que aparecer.
check "lista los 4 descendientes"              4  "$(printf '%s\n' "$m" | grep -c 'pid=' | tr -d ' ')"

echo "== D) Alcance del árbol ================================================"
# Un NIETO tiene que aparecer: el hook recorre descendientes indirectos, no sólo
# hijos directos. Con 2 hijos + 1 nieto + el bash intermedio, el conteo de arriba
# ya lo cubre; acá se afirma que el intermedio TAMBIÉN aparece.
check "el nieto aparece (recursión)"           SI "$(has "$m" 'sleep 20; :' SI NO)"
check "el hook NO se lista a sí mismo"         NO "$(has "$m" "$HOOK" SI NO)"
# Un proceso ajeno al árbol del hook no debe aparecer: el hook acota a los
# descendientes de SU padre, no a todo el sistema.
sleep 20 >/dev/null 2>&1 & foreign=$!
m2="$(tree_err CLAUDE_REPORT_CHILDREN_MIN_AGE=0)"
check "no reporta procesos de otro árbol"      NO "$(has "$m2" "pid=$foreign " SI NO)"
kill "$foreign" 2>/dev/null; wait "$foreign" 2>/dev/null

echo "== E) Parseo de etime (extraído del archivo VIVO) ======================="
check "SS"                                     45     "$(etime_to_secs 45)"
check "MM:SS"                                  125    "$(etime_to_secs 02:05)"
check "HH:MM:SS"                               3725   "$(etime_to_secs 01:02:05)"
check "DD-HH:MM:SS"                            90125  "$(etime_to_secs 1-01:02:05)"
# Los ceros a la izquierda NO deben leerse como octal: `08` y `09` son inválidos
# en base 8 y romperían la aritmética. Por eso el hook fuerza 10#.
check "ceros a la izquierda no son octal"      540    "$(etime_to_secs 09:00)"
check "08 tampoco"                             480    "$(etime_to_secs 08:00)"

echo "== F) MIN_AGE inválido: filtra o avisa, pero no ensucia el reporte ======"
# El hermano reap-stale-polls tenía este mismo bug y ahí era MORTAL (un
# CLAUDE_POLL_STALE_SECS="5m" mataba procesos de 30s). Acá no mata, pero un
# `[: 5m: integer expression expected` POR CADA PROCESO se intercala dentro del
# reporte y el usuario nunca se entera de por qué. bg-track ya resuelve esto
# bien: avisa UNA vez y cae al default. Medido 2026-09-08.
# El hook NO puede correr dentro de una sustitución de comandos: `$( )` lo hace
# hijo del subshell y `collect_descendants` recorre OTRO árbol (medía vacío y los
# dos casos daban 0 por la razón equivocada). La salida va a archivos.
bash -c '
  sleep 40 >/dev/null 2>&1 &
  sleep 17
  bash "$0" 2>"$1/a" >/dev/null
  CLAUDE_REPORT_CHILDREN_MIN_AGE=5m bash "$0" 2>"$1/b" >/dev/null
  kill $(jobs -p) 2>/dev/null
' "$HOOK" "$TMP"
check "un hijo de >15s SÍ se reporta con el default" 1 "$(grep -c 'pid=' "$TMP/a" | tr -d ' ')"
check "MIN_AGE inválido cae al MISMO default (15)"   1 "$(grep -c 'pid=' "$TMP/b" | tr -d ' ')"
mb="$(tree_err CLAUDE_REPORT_CHILDREN_MIN_AGE=5m)"
check "MIN_AGE inválido no escupe error de bash" NO "$(has "$mb" 'integer expression expected' SI NO)"
check "MIN_AGE inválido avisa qué pasó"        SI "$(has "$mb" 'no es un entero' SI NO)"
check "el aviso sale UNA sola vez"             1  "$(printf '%s\n' "$mb" | grep -c 'no es un entero' | tr -d ' ')"
check "MIN_AGE inválido nombra el valor"       SI "$(has "$mb" '5m' SI NO)"
mn="$(tree_err CLAUDE_REPORT_CHILDREN_MIN_AGE=-1)"
check "MIN_AGE negativo tampoco escupe error"  NO "$(has "$mn" 'integer expression expected' SI NO)"
check "MIN_AGE negativo avisa"                 SI "$(has "$mn" 'no es un entero' SI NO)"
me="$(tree_err CLAUDE_REPORT_CHILDREN_MIN_AGE=)"
check "MIN_AGE vacío cae al default sin avisar" NO "$(has "$me" 'no es un entero' SI NO)"

# LÍMITE: la rama `[ "$ppid_of_hook" = "0" ] && exit 0` es INALCANZABLE y por
# lo tanto NO está cubierta. bash define PPID como variable de SOLO LECTURA: no
# se puede desactivar por entorno ni con `unset` (medido 2026-09-09), así que
# `${PPID:-0}` jamás cae al default. Es código defensivo puro y su mutante
# sobrevive por eso, no por un caso faltante — se declara en vez de fabricar
# cobertura falsa. Este caso afirma la RAZÓN: si algún día PPID dejara de ser
# readonly, la guarda pasaría a ser testeable y acá saltaría el aviso.
check "LÍMITE: PPID es readonly → la guarda de PPID=0 es inalcanzable" SI \
  "$(has "$( (unset PPID) 2>&1 )" 'readonly' SI NO)"

echo "== G) LÍMITES declarados a propósito ==================================="
# Documentado en la cabecera del hook (líneas 18-23) y NO tapado acá: un Agent
# fork o un Workflow corren en background pero no son procesos de shell, así que
# este hook no puede verlos. Si el usuario reporta "seguía corriendo algo" y la
# lista salió vacía, el candidato es un fork/Workflow.
check "LÍMITE: sólo ve procesos de shell reales" "" "$(lonely_err)"
# El default de 15s crea una VENTANA CIEGA: lo recién lanzado —justo lo que uno
# olvida— es invisible en el Stop inmediato. Es deliberado (evita reportar los
# procesos efímeros del propio turno), pero es una ventana real y se declara.
check "LÍMITE: un hijo recién nacido es invisible con el default" "" "$(tree_err)"
# NO mata nada, a diferencia de reap-stale-polls: acá no hay forma de distinguir
# "me olvidé de matarlo" de "es un server que el usuario quiere vivo".
env CLAUDE_REPORT_CHILDREN_MIN_AGE=0 bash -c '
  sleep 20 >/dev/null 2>&1 & p=$!
  bash "$0" >/dev/null 2>&1
  kill -0 $p 2>/dev/null && echo VIVO || echo MUERTO
  kill $p 2>/dev/null
' "$HOOK" > /tmp/rlc-kill.$$ 2>/dev/null
check "LÍMITE: no mata lo que reporta"         VIVO "$(cat /tmp/rlc-kill.$$ 2>/dev/null)"
rm -f /tmp/rlc-kill.$$

echo
if [ "$fails" -eq 0 ]; then printf 'Resultado: %s PASS / 0 FAIL\n' "$total"; exit 0; fi
printf 'Resultado: %s PASS / %s FAIL (de %s)\n' "$((total-fails))" "$fails" "$total"
exit 1
