#!/usr/bin/env bash
# Ledger de trabajo en background por sesión. Backend compartido de
# track-bg-launch.sh (PreToolUse) y block-unacked-bg.sh (Stop).
#
# Modelo: "pending" no significa "sigue corriendo" — significa "lanzado y
# todavía no dado cuenta". Un Agent fork, un Workflow o un Bash con
# run_in_background quedan en pending desde que se lanzan. Se sacan de
# pending con `ack`, que Claude debe llamar explícitamente cuando:
#   (a) llegó la notificación y ya reportó el resultado, o
#   (b) sigue corriendo A PROPÓSITO y ya lo dijo en la respuesta.
# Esto es intencional: no exige que termine, exige que no quede en silencio
# (regla 1 de "Background Tasks and Waiting" en ~/.claude/CLAUDE.md).
#
# El ack tiene ÁMBITO TEMPORAL: reconoce lo lanzado ANTES de él, nunca lo
# lanzado después. Un id relanzado vuelve a quedar pendiente aunque una
# corrida anterior con el mismo id ya se haya reconocido.
#
# Por qué esto NO es el mismo loop de bloqueo que se evitó en
# report-live-children.sh: bloquear ahí sobre un ps-scan estático re-vería
# el MISMO proceso sin cambios turno tras turno. Acá cada bloqueo exige una
# mutación de estado real (`ack`) antes de poder pasar — no hay forma de
# "decir que está bien" sin dejar rastro, así que no puede haber un bucle de
# bloqueo idéntico infinito: el ledger cambia en cada intento.
#
# Fail-open SIEMPRE ante error/ambigüedad: un bug acá nunca debe dejar al
# usuario sin poder cerrar un turno. Ver `pending`: cualquier error de
# parseo hace que esa línea se ignore, no que bloquee. Pero fail-open NO es
# licencia para fallar MUDO: un `ack` que no reconoce nada y un MAX_AGE
# inválido avisan por stderr en vez de pasar en silencio.
#
# Contrato ejecutable: ~/.claude/hooks/tests/bg-track-tests.sh

set -uo pipefail

STATE_DIR="${HOME}/.claude/hooks/state"
MAX_AGE_SECS="${CLAUDE_BG_TRACK_MAX_AGE:-14400}"  # 4h: techo duro, ver README arriba

# El valor viaja a jq por --argjson, así que uno no numérico reventaba el
# programa entero: jq fallaba, el `|| true` se lo tragaba y `pending` salía
# VACÍO con rc=0. El Stop leía "no hay nada" y el ledger quedaba APAGADO en
# silencio — justo el modo de falla que este hook existe para evitar. Y el
# comentario de acá arriba induce el error: escribir `4h` es lo natural.
case "$MAX_AGE_SECS" in
  ''|*[!0-9]*)
    printf 'bg-track: CLAUDE_BG_TRACK_MAX_AGE=%s no es un entero de segundos; uso 14400 (4h)\n' \
      "'$MAX_AGE_SECS'" >&2
    MAX_AGE_SECS=14400
    ;;
esac

mkdir -p "$STATE_DIR" 2>/dev/null

ledger_path() {
  local session="$1"
  printf '%s/%s.jsonl' "$STATE_DIR" "$session"
}

# Pendientes como JSON, fuente única de verdad para `pending` y `unblock`.
#
# Tres cosas que este programa resuelve por construcción:
#  1. ÁMBITO TEMPORAL: un ack sólo tapa launches en posiciones ANTERIORES
#     ($all[($i+1):]), en vez de comparar contra el conjunto de TODOS los acks
#     del archivo. Con lo segundo, un id relanzado tras un ack quedaba
#     invisible para siempre.
#  2. TIPO DEL id: se compara `tostring` contra `tostring`. Un ledger con
#     `"id":123` (línea escrita a mano) no se podía ackear con `123` porque
#     jq no iguala 123 con "123".
#  3. ENTRADAS MUTILADAS: una línea que es JSON válido pero sin `ts` hacía
#     estallar la aritmética y dejaba el ledger ENTERO ciego; una sin `id`
#     emitía un pendiente fantasma que nada podía ackear. Ambas se descartan
#     solas, que es lo que la cabecera promete.
JQ_PENDING='
  [ .[] | select(type == "object") ] as $all
  | [ range(0; ($all | length)) as $i
      | $all[$i] as $e
      | select(($e.op? == "launch") and ($e.id? != null) and (($e.ts? | type) == "number"))
      | ($e.id | tostring) as $eid
      | select([ $all[($i + 1):][]
                 | select((.op? == "ack") and (.id? != null) and ((.id | tostring) == $eid)) ]
               | length == 0)
      | select(($now - $e.ts) < $maxage)
      | { id: $eid,
          kind: (($e.kind // "unknown") | tostring),
          label: (($e.label // "") | tostring),
          age: (($now - $e.ts) | tostring) } ]
'

pending_json() { # <ledger> → array JSON de pendientes (siempre válido)
  local out
  # fromjson? línea por línea, no -s directo: una sola línea corrupta (write
  # a medias, línea manual mal formada) no puede envenenar el parseo de todo
  # el archivo y dejar el ledger ciego en silencio — se descarta esa línea
  # sola, el resto se sigue viendo.
  out="$(jq -R 'fromjson?' "$1" 2>/dev/null \
         | jq -s -c --argjson now "$now" --argjson maxage "$MAX_AGE_SECS" "$JQ_PENDING" 2>/dev/null)"
  [ -n "$out" ] && printf '%s' "$out" || printf '[]'
}

do_ack() { # <session> <id> <reason> — escribe el ack y avisa si no reconoció nada
  local session="$1" id="$2" reason="$3"
  local ledger ts known found=0 k
  ledger="$(ledger_path "$session")"

  known=""
  [ -f "$ledger" ] && known="$(pending_json "$ledger" | jq -r '.[].id' 2>/dev/null || true)"

  ts="$(date +%s)"
  printf '{"op":"ack","id":%s,"reason":%s,"ts":%s}\n' \
    "$(printf '%s' "$id" | jq -Rs '.')" "$(printf '%s' "$reason" | jq -Rs '.')" "$ts" >> "$ledger" 2>/dev/null

  # Un ack que no reconoce nada NO es un error (fail-open: nunca trabamos un
  # turno), pero tampoco puede ser mudo. El caso medido el 2026-09-07: ackear
  # con el id corto que devuelve el tool Bash en vez del `toolu_` del ledger
  # daba rc=0 sin efecto, el Stop volvía a bloquear y no había ninguna señal
  # de por qué.
  if [ -n "$known" ]; then
    while IFS= read -r k; do
      [ "$k" = "$id" ] && { found=1; break; }
    done <<< "$known"
  fi
  if [ "$found" -eq 0 ]; then
    {
      printf "bg-track: '%s' no estaba pendiente en la sesión %s.\n" "$id" "$session"
      printf '  El ack quedó registrado, pero NO desbloquea nada.\n'
      if [ -n "$known" ]; then
        printf '  Pendientes ahora:\n'
        while IFS= read -r k; do [ -n "$k" ] && printf '    %s\n' "$k"; done <<< "$known"
        printf '  El id del ledger es el del tool call, no el id corto que devuelve el tool Bash.\n'
        printf '  Sacá el real con: bash ~/.claude/hooks/bg-track.sh pending\n'
      else
        printf '  Esa sesión no tiene nada pendiente.\n'
      fi
    } >&2
  fi
}

cmd="${1:-}"
shift || true
now="$(date +%s)"

case "$cmd" in
  launch)
    # launch <session_id> <id> <kind> <label>
    session="${1:?session_id requerido}"; id="${2:?id requerido}"
    kind="${3:-unknown}"; label="${4:-}"
    ledger="$(ledger_path "$session")"
    esc_label="$(printf '%s' "$label" | jq -Rs '.' 2>/dev/null || printf '""')"
    printf '{"op":"launch","id":%s,"kind":%s,"label":%s,"ts":%s}\n' \
      "$(printf '%s' "$id" | jq -Rs '.')" "$(printf '%s' "$kind" | jq -Rs '.')" \
      "$esc_label" "$now" >> "$ledger" 2>/dev/null
    ;;

  ack)
    # ack <id> [reason] [session_id]  — session_id default: $CLAUDE_CODE_SESSION_ID
    id="${1:?id requerido}"; reason="${2:-}"
    session="${3:-${CLAUDE_CODE_SESSION_ID:-}}"
    [ -z "$session" ] && { echo "ack: no session_id (pasalo como 3er arg o seteá CLAUDE_CODE_SESSION_ID)" >&2; exit 1; }
    do_ack "$session" "$id" "$reason"
    ;;

  pending)
    # pending [session_id] — una línea por entrada pendiente: id\tkind\tlabel\tage_secs
    session="${1:-${CLAUDE_CODE_SESSION_ID:-}}"
    [ -z "$session" ] && exit 0
    ledger="$(ledger_path "$session")"
    [ -f "$ledger" ] || exit 0
    pending_json "$ledger" | jq -r '.[] | [.id, .kind, .label, .age] | @tsv' 2>/dev/null || true
    ;;

  unblock)
    # unblock (<id>|--all) [session_id] — escape hatch manual
    target="${1:?id o --all requerido}"
    session="${2:-${CLAUDE_CODE_SESSION_ID:-}}"
    [ -z "$session" ] && { echo "unblock: no session_id" >&2; exit 1; }
    if [ "$target" = "--all" ]; then
      ledger="$(ledger_path "$session")"
      [ -f "$ledger" ] || exit 0
      # Los ids viajan en base64, NO por la salida TSV de `pending`: @tsv
      # escapa \t, \n y \\, así que un id con cualquiera de esos tres se
      # ackeaba con el texto escapado — distinto del id real — y `unblock
      # --all` dejaba al usuario BLOQUEADO después de correr exactamente el
      # comando que el mensaje de bloqueo le ofrece como última salida.
      while IFS= read -r b64; do
        [ -n "$b64" ] || continue
        id="$(printf '%s' "$b64" | base64 -d 2>/dev/null)" || continue
        [ -n "$id" ] || continue
        do_ack "$session" "$id" "manual-unblock (--all)"
      done < <(pending_json "$ledger" | jq -r '.[].id | @base64' 2>/dev/null)
    else
      do_ack "$session" "$target" "manual-unblock"
    fi
    ;;

  *)
    echo "uso: bg-track.sh {launch|ack|pending|unblock} ..." >&2
    exit 1
    ;;
esac

exit 0
