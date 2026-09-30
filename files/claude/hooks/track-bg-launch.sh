#!/usr/bin/env bash
# PreToolUse(Agent|Workflow|Bash) — anota en el ledger cada lanzamiento de
# trabajo en background. Puro instrumental: NUNCA bloquea (exit 0 siempre),
# solo alimenta a bg-track.sh para que block-unacked-bg.sh (Stop) sepa qué
# falta reconocer. Ver bg-track.sh para el modelo completo.

set -uo pipefail

input="$(cat 2>/dev/null || true)"
[ -z "$input" ] && exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
tool_use_id="$(printf '%s' "$input" | jq -r '.tool_use_id // empty' 2>/dev/null || true)"
[ -z "$session" ] || [ -z "$tool_use_id" ] && exit 0

kind=""
label=""

# Primer candidato string NO VACIO, con los saltos colapsados y tope duro de 120.
#
# Por que no alcanza `//` de jq: solo lo dispara con null y false, asi que un
# description:"" pasa el filtro y deja el label VACIO. Aguas abajo el TSV de
# `pending` no puede representar un campo vacio (el TAB es IFS-whitespace): el
# consumidor corre los campos y el mensaje de bloqueo muestra la edad en el
# lugar del label. Medido 2026-09-08: `[bash-bg] "0" (hace s)`.
#
# Por que el tope va aca y no con `cut -c1-120`: cut trunca POR LINEA, asi que
# un label multilinea topeaba en 120 x N lineas, o sea en nada. Ese label viaja
# entero al mensaje de bloqueo, que el modelo consume en CADA Stop hasta el ack.
label_pick(){ # label_pick <fallback> <campo...>
  local fb="$1"; shift
  printf '%s' "$input" | jq -r --arg fb "$fb" --args '
    ( .tool_input? // {} ) as $ti
    | [ $ARGS.positional[] | $ti[.]? ]
    | map(select(type == "string"))
    | map(gsub("\\s+"; " ") | sub("^ ";"") | sub(" $";""))
    | map(select(length > 0))
    | (first // $fb)
    | .[0:120]
  ' "$@" 2>/dev/null || printf '%s' "$fb"
}

case "$tool" in
  Agent)
    kind="agent"
    label="$(label_pick agent description subagent_type)"
    ;;
  Workflow)
    kind="workflow"
    label="$(label_pick workflow name scriptPath)"
    ;;
  Bash)
    bg="$(printf '%s' "$input" | jq -r '.tool_input.run_in_background // false' 2>/dev/null || echo false)"
    [ "$bg" != "true" ] && exit 0
    kind="bash-bg"
    label="$(label_pick bash description command)"
    ;;
  *)
    exit 0
    ;;
esac

bash "$HOME/.claude/hooks/bg-track.sh" launch "$session" "$tool_use_id" "$kind" "$label" >/dev/null 2>&1 || true
exit 0
