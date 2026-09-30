#!/usr/bin/env bash
# Stop hook — muestra en stderr cualquier proceso hijo vivo del harness al
# cerrar el turno. Puramente informativo (exit 0 SIEMPRE): esto blindea la
# regla 1 de "Background Tasks and Waiting" en ~/.claude/CLAUDE.md ("nunca
# dejar background vivo al reportar que terminaste") con algo que el usuario
# VE, en vez de depender solo de que Claude se acuerde de mencionarlo.
#
# Por qué no bloquea (exit 2): un dev server o watcher legítimo que el
# usuario pidió dejar corriendo seguiría vivo turno tras turno. Si este hook
# bloqueara cada vez que lo ve, Claude respondería "sí, es a propósito" y
# volvería a intentar cerrar el turno — mismo proceso, mismo bloqueo: un loop
# de bloqueo autoinfligido. Ver reap-stale-polls.sh, mismo principio.
#
# Por qué NO mata nada (a diferencia de reap-stale-polls.sh): no hay forma de
# distinguir acá "se me olvidó matar esto" de "es un servidor que el usuario
# quiere corriendo". Matar sin esa certeza es peor que avisar de más.
#
# Límite conocido y documentado (no inventar cobertura que no existe): esto
# SOLO ve procesos de shell/Bash reales. Un Agent fork (subagent_type:
# "fork") o el tool Workflow corren en background pero son invisibles a
# nivel de proceso — el Stop hook no tiene forma de verlos. Si el usuario
# reporta "dijiste que terminaste pero seguía corriendo algo" y esta lista
# sale vacía, el candidato es un fork/Workflow, no un proceso de shell.

set -uo pipefail

self=$$
ppid_of_hook="${PPID:-0}"
MIN_AGE_SECS="${CLAUDE_REPORT_CHILDREN_MIN_AGE:-15}"

# Un valor no numerico hacia fallar `[ "$age" -lt "$MIN_AGE_SECS" ]` UNA VEZ POR
# PROCESO: el reporte salia intercalado con `[: 5m: integer expression expected`
# y el usuario nunca se enteraba de por que. Es el mismo bug que tenia
# reap-stale-polls, donde ademas era MORTAL (un CLAUDE_POLL_STALE_SECS="5m"
# mataba procesos de 30s). Avisar UNA vez y caer al default es exactamente lo
# que ya hace bg-track.sh con CLAUDE_BG_TRACK_MAX_AGE: mismo harness, misma
# forma. Medido 2026-09-08.
case "$MIN_AGE_SECS" in
  ''|*[!0-9]*)
    printf 'report-live-children: CLAUDE_REPORT_CHILDREN_MIN_AGE=%s no es un entero de segundos; uso 15\n' \
      "$MIN_AGE_SECS" >&2
    MIN_AGE_SECS=15
    ;;
esac

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
  echo $(( 10#${d:-0} * 86400 + 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${s:-0} ))
}

# Descendientes directos e indirectos de ppid_of_hook (el proceso que corrió
# este hook, típicamente el harness o un ancestro cercano) — no todo el
# sistema, para no reportar ruido de procesos ajenos a la sesión.
collect_descendants() {
  local root="$1" pid etime args
  local children
  children="$(ps -eo pid,ppid,etime,args 2>/dev/null | awk -v p="$root" '$2 == p {print $1}')"
  for pid in $children; do
    [ "$pid" = "$self" ] && continue
    ps -o pid=,etime=,args= -p "$pid" 2>/dev/null
    collect_descendants "$pid"
  done
}

[ "$ppid_of_hook" = "0" ] && exit 0

found=0
while read -r pid etime args; do
  [ -n "$pid" ] || continue
  age="$(etime_to_secs "$etime")"
  [ "$age" -lt "$MIN_AGE_SECS" ] && continue
  if [ "$found" -eq 0 ]; then
    printf 'INFO (report-live-children): procesos aún vivos al cerrar el turno — si alguno no es a propósito, decilo explícitamente en la respuesta, no lo dejes en silencio:\n' >&2
    found=1
  fi
  printf '  pid=%s edad=%ss  %.160s\n' "$pid" "$age" "$args" >&2
done < <(collect_descendants "$ppid_of_hook")

exit 0
