#!/usr/bin/env bash
# Stop hook — mata loops de polling huérfanos al terminar el turno.
#
# Problema que resuelve (incidente 2026-08-25):
#   Un `until <cond>; do sleep N; done` con condición de salida imposible
#   queda girando para siempre. El usuario ve "Waiting for task ..." en la UI
#   y cree que hay trabajo en curso cuando la tarea ya terminó hace rato.
#   Se encontraron DOS en simultáneo: uno de 11 min (grep -v pass | grep pass,
#   nunca matcheable) y otro de 92 min (esperaba node_modules/.bin/ng desde una
#   carpeta de componente, donde jamás iba a existir).
#
# Qué hace: al cerrar cada turno busca shells de polling (until|while + sleep)
# más viejos que STALE_AFTER_SECS y los mata. Loguea todo — nunca borra en
# silencio.
#
# Qué NO toca: servidores de dev, watchers, builds, tests. El patrón exige
# un bucle explícito CON sleep, que es la firma del polling, no la de un daemon.
#
# Salida siempre 0: informativo, no bloquea el turno. No puede generar un loop
# de re-invocación.
#
# REGLA DE DISEÑO (2026-09-08, al escribirle el contrato): este hook MATA. Una
# guarda rota en un hook destructivo no falla hacia el silencio, falla HACIA EL
# GATILLO: `[ "$age" -lt "$UMBRAL" ] && continue` con un dato inválido hace que
# el `[` devuelva !=0, el `continue` no corra, y el proceso se mate SIN QUE SE
# HAYA EVALUADO SU EDAD. Se medieron dos vías reales (umbral no numérico y etime
# no parseable): las dos mataban procesos jóvenes y legítimos, en silencio.
# Toda entrada dudosa se normaliza ANTES de la guarda, y la duda se resuelve
# SIEMPRE hacia no matar.

set -uo pipefail

STALE_AFTER_SECS_DEFAULT=300 # 5 min — en SEGUNDOS, no admite sufijos ("5m" NO)
STALE_AFTER_SECS="${CLAUDE_POLL_STALE_SECS:-$STALE_AFTER_SECS_DEFAULT}"
# El comentario de al lado invita a escribir "5m", y hasta el 2026-09-08 eso
# hacía fallar el `[ -lt ]` de más abajo => TODO proceso que matcheara el patrón
# se mataba sin mirarle la edad. Un valor inválido cae al default y AVISA.
case "$STALE_AFTER_SECS" in
  ''|*[!0-9]*)
    printf 'reap-stale-polls: CLAUDE_POLL_STALE_SECS=%s no es un entero de segundos; uso %s.\n' \
      "$STALE_AFTER_SECS" "$STALE_AFTER_SECS_DEFAULT" >&2
    STALE_AFTER_SECS="$STALE_AFTER_SECS_DEFAULT" ;;
esac
LOG="${HOME}/.claude/reaped-polls.log"

# etime de BSD ps: [DD-]HH:MM:SS | MM:SS -> segundos
etime_to_secs() {
  local e="$1" d=0 h=0 m=0 s=0
  case "$e" in
    *-*) d="${e%%-*}"; e="${e#*-}" ;;
  esac
  local IFS=:
  # shellcheck disable=SC2086
  set -- $e
  case $# in
    3) h=$1; m=$2; s=$3 ;;
    2) m=$1; s=$2 ;;
    1) s=$1 ;;
    *) echo 0; return ;;
  esac
  # Un etime con basura (columna corrida, ps mutilado) reventaba la aritmética;
  # `age` quedaba vacío, el `[ -lt ]` fallaba y el proceso se mataba IGUAL. Edad
  # desconocida => 0 => no se toca: la duda no puede resolverse matando.
  local f
  for f in "$d" "$h" "$m" "$s"; do
    case "$f" in ''|*[!0-9]*) echo 0; return ;; esac
  done
  echo $(( 10#${d:-0} * 86400 + 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${s:-0} ))
}

# El patrón vive en una variable porque se usa DOS veces: para buscar candidatos
# y para excluir al propio `grep` de este pipeline, que lleva el patrón en su
# argv y si no se auto-matchearía. Antes eso se resolvía con `grep -v grep`, que
# excluía por SUBCADENA a CUALQUIER proceso con "grep" en la línea — incluido el
# incidente que originó este hook (`until ... grep -v pass | grep pass ... sleep`,
# ver cabecera) y cualquier loop con egrep/ripgrep/un path tipo /opt/grepper/.
# El hook era ciego justo a los loops que espera con grep, que son los más
# comunes. `grep -vF -- "$PATRON_POLL"` excluye exactamente al grep del pipe.
PATRON_POLL='(until|while)[[:space:]].*sleep[[:space:]]'

# Y el último filtro exige que el proceso SEA un shell corriendo el loop inline.
# El patrón se buscaba en TODO el argv, así que cualquier comando que MENCIONARA
# un loop moría: medido con `rg -n "while true; do sleep 5; done" /srv`, con un
# editor abriendo un archivo con ese nombre y con un agente que lo lleva en su
# prompt. El `grep -v grep` tapaba por accidente el subconjunto de los greps y
# escondía el problema. LÍMITE ACEPTADO: un loop lanzado por algo que no es un
# shell (make, npm) no se ve; el incidente real venía siempre de `bash -c`.
self=$$
killed=0

# `read` con IFS por defecto colapsa runs de espacios — imprescindible acá,
# porque ps alinea las columnas con padding variable.
while read -r pid etime args; do
  [ -n "$pid" ] || continue
  [ -z "${pid//[0-9]/}" ] || continue
  [ "$pid" = "$self" ] && continue
  [ "$pid" = "${PPID:-0}" ] && continue

  age="$(etime_to_secs "$etime")"
  [ "$age" -lt "$STALE_AFTER_SECS" ] && continue

  # Inmunidad para CI self-hosted (2026-08-31): los jobs de Actions corren
  # shells con loops de espera legítimos (emulador, etc.). Matarlos cancela
  # el job y puede tumbar la sesión del runner. Si CUALQUIER ancestro del
  # candidato es un proceso del actions-runner, se salta.
  anc="$pid"; runner_child=0
  for _hop in 1 2 3 4 5 6; do
    anc="$(ps -o ppid= -p "$anc" 2>/dev/null | tr -d ' ')"
    [ -n "$anc" ] && [ "$anc" != "0" ] && [ "$anc" != "1" ] || break
    if ps -o command= -p "$anc" 2>/dev/null | grep -q 'actions-runner\|Runner\.Worker\|Runner\.Listener'; then
      runner_child=1; break
    fi
  done
  [ "$runner_child" = "1" ] && continue

  # Reapear: primero los hijos (el `sleep` colgado), después el shell.
  pkill -P "$pid" 2>/dev/null
  kill "$pid" 2>/dev/null
  sleep 0.3
  if ps -p "$pid" >/dev/null 2>&1; then
    pkill -9 -P "$pid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
  fi

  killed=$((killed + 1))
  printf '%s  pid=%s  edad=%ss  cmd=%.220s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$pid" "$age" "$args" >>"$LOG"
  printf 'reaped stale poll: pid=%s edad=%ss -> %.140s\n' "$pid" "$age" "$args" >&2
done < <(
  ps -eo pid,etime,args 2>/dev/null \
    | grep -E "$PATRON_POLL" \
    | grep -v 'reap-stale-polls' \
    | grep -v 'BOUNDED_WAIT_OK' \
    | grep -vF -- "$PATRON_POLL" \
    | sed -E 's/^[[:space:]]+//' \
    | grep -E '^[0-9]+[[:space:]]+[0-9:.-]+[[:space:]]+(/[^[:space:]]*/)?(bash|sh|zsh|ksh|dash)([[:space:]]|$)'
  # BOUNDED_WAIT_OK: marcador para esperas LEGÍTIMAS con techo de iteraciones
  # (ej. "i=0; until <cond> || [ $i -ge 20 ]; do sleep 30; i=$((i+1)); done").
  # Incidente 2026-08-31: este reaper es machine-wide y los Stop hooks de
  # OTRAS sesiones mataron 4 veces esperas acotadas de CI de esta sesión
  # (exit 144). Quien usa el marcador se compromete a que el loop tenga
  # contador con techo — el anti-polling PreToolUse lo exige igual al lanzarlo.
)

[ "$killed" -gt 0 ] && printf '%d loop(s) de polling huérfanos matados. Log: %s\n' "$killed" "$LOG" >&2

exit 0
