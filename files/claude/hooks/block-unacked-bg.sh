#!/usr/bin/env bash
# Stop hook — bloquea el cierre del turno si hay trabajo en background
# lanzado y todavía no reconocido (ver bg-track.sh para el modelo). Esta es
# la versión "completa y más cara" pedida explícitamente por el usuario
# (2026-08-27): a diferencia de report-live-children.sh (informativo, nunca
# bloquea), esta SÍ bloquea — pero solo puede desbloquearse con una mutación
# de estado real (`bg-track.sh ack`), así que no genera el loop de bloqueo
# infinito que motivó que report-live-children.sh fuera solo informativo.
#
# Fail-open: cualquier error de bg-track.sh/jq deja pasar el turno (exit 0).
# Esta herramienta es nueva y puede tener bugs propios — un bug acá NUNCA
# debe dejar al usuario sin poder cerrar un turno. Escape manual si algo se
# traba: `bash ~/.claude/hooks/bg-track.sh unblock --all`.

set -uo pipefail

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -z "$session" ] && exit 0

pending="$(bash "$HOME/.claude/hooks/bg-track.sh" pending "$session" 2>/dev/null || true)"
[ -z "$pending" ] && exit 0

{
  printf 'BLOQUEADO (background sin reconocer): lanzaste esto y todavía no lo diste por reconocido:\n'
  # El TAB es IFS-whitespace, asi que `read` con IFS=$'\t' COLAPSA los campos
  # vacios y relee la linea CORRIDA: con un label vacio, la edad se imprimia en
  # el lugar del label y la edad quedaba en blanco (`[bash-bg] "0" (hace s)`,
  # medido 2026-09-08). El mensaje mandaba a ackear con datos falsos, que es
  # justo lo que existe para evitar. awk -F'\t' no colapsa los vacios.
  printf '%s\n' "$pending" | awk -F'\t' '
    $1 == "" { next }
    {
      kind  = ($2 == "" ? "?" : $2)
      label = ($3 == "" ? "(sin etiqueta)" : $3)
      age   = ($4 ~ /^[0-9]+$/ ? $4 : "?")
      printf "  [%s] \"%s\" (hace %ss) — id=%s\n", kind, label, age, $1
    }'
  printf '\nPara cada uno, ANTES de responder de nuevo:\n'
  printf '  - Si ya terminó y reportaste el resultado: bash ~/.claude/hooks/bg-track.sh ack <id> "<qué encontró/hizo>"\n'
  printf '  - Si sigue corriendo A PROPÓSITO: decilo en tu respuesta (qué es, por qué, cuándo esperar el resultado) y después bash ~/.claude/hooks/bg-track.sh ack <id> "sigue corriendo: <por qué>"\n'
  printf '  - Si esto es un falso positivo (bug del propio ledger): bash ~/.claude/hooks/bg-track.sh unblock --all\n'
} >&2

exit 2
