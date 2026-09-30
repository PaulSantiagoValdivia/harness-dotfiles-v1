#!/usr/bin/env bash
# Stop — mide el presupuesto de contexto y CACHEA el aviso para el proximo
# prompt. La mitad cara del enforcement que antes vivia en UserPromptSubmit.
#
# Origen (2026-09-08): `UserPromptSubmit hook timed out after 30s -- output
# discarded` aparecia una y otra vez en las triangulaciones. El diagnostico del
# 2026-09-07 fue correcto —contencion de CPU, load 395, el hook es fail-open y
# no se pierde el prompt— pero se cerro sin arreglar nada, asi que el error
# siguio. Medido: context-budget.sh tarda 0.149s idle contra un transcript de
# 10MB. No es lento; para llegar a 30s hace falta un frenon de ~200x. Con 12
# forks (5 de ellos jq, uno slurpeando megabytes) es justo lo que una maquina
# saturada le hace.
#
# Bajar el costo no alcanzaba: 1.7x no saca de un 200x. Lo que lo elimina es
# sacar la medicion de UserPromptSubmit. Stop sigue siendo sincrono salvo
# configuracion explicita: mide aca, escribe el aviso, y UserPromptSubmit se
# limita a leerlo sin forkear.
#
# Compactacion reduce el contexto: SessionStart compact invalida el aviso
# de esa sesion; Stop descarta usage anterior al ultimo compact_boundary.
# No se usa un TTL ni se cambia el lector sin forks.
#
# Umbrales (contexto = input + cache_read + cache_creation del ultimo request):
#   < 200k  -> silencio total
#   >= 200k -> AVISO: terminar la unidad de trabajo, no abrir frentes nuevos
#   >= 300k -> ALTO: checkpoint y compactacion nativa para la misma tarea
#   >= 400k -> CRITICO: zona de quemado; cada turno relee todo esto
# Edad de sesion:
#   >= 10h  -> sumar aviso de sesion larga (96% del consumo venia de 8h+)
#
# Fail-open en todo: sin jq, sin transcript, sin usage -> se borra el cache y
# se sale sin ruido. Un Stop hook jamas puede trabar el cierre de un turno.

set -uo pipefail

CACHE_DIR="${CLAUDE_CTX_CACHE_DIR:-$HOME/.claude/hooks/state/ctx-budget}"

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"

# SessionStart compact solo invalida su cache, nunca mide el transcript antiguo.
if [[ "$input" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"SessionStart\" ]]; then
  [[ "$input" =~ \"source\"[[:space:]]*:[[:space:]]*\"compact\" ]] || exit 0
  case "$session" in ''|.|..|*[!A-Za-z0-9._-]*) exit 0 ;; esac
  case "$CACHE_DIR" in /*/ctx-budget) ;; *) exit 0 ;; esac
  ancestor="$CACHE_DIR"
  while [ -n "$ancestor" ] && [ "$ancestor" != / ]; do
    [ ! -L "$ancestor" ] || exit 0
    ancestor="${ancestor%/*}"
  done
  [ ! -L "$CACHE_DIR/$session" ] || exit 0
  rm -f "$CACHE_DIR/$session" 2>/dev/null
  exit 0
fi

# Sin session_id no hay a quien dejarle el aviso: el lector se indexa por ahi.
[ -n "$session" ] || exit 0
# La clave va saneada: entra en una ruta de archivo.
session="${session//[^A-Za-z0-9._-]/_}"
case "$session" in ''|.|..) exit 0 ;; esac

mkdir -p "$CACHE_DIR" 2>/dev/null || exit 0
cache="$CACHE_DIR/$session"

# Purga de sesiones viejas. Acotada al directorio propio y por nombre: este
# hook BORRA, y en un hook con efectos el fail-open es fail-DANINO. Si la
# variable no quedo con el valor esperado, no se borra nada.
case "$CACHE_DIR" in
  */ctx-budget) find "$CACHE_DIR" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null || true ;;
esac

drop() { rm -f "$cache" 2>/dev/null; exit 0; }

[ -n "$transcript" ] && [ -f "$transcript" ] || drop

# Contexto actual: ultimo registro del transcript que traiga usage. Se lee la
# cola (no el archivo entero: llegan a 16MB). Cada compact_boundary invalida
# usage anterior; solo un usage posterior puede producir un aviso nuevo.
ctx="$(tail -n 400 "$transcript" 2>/dev/null | jq -rs '
  reduce (.[] | select(type == "object")) as $row (0;
    if $row.type == "system" and $row.subtype == "compact_boundary" then 0
    elif ($row.message.usage? | type) == "object" then
      $row.message.usage | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
    else . end)' 2>/dev/null || echo 0)"

case "$ctx" in ''|*[!0-9]*) drop ;; esac
[ "$ctx" -gt 0 ] || drop

# Edad de la sesion: primer timestamp del transcript contra ahora.
age_h=0
first_ts="$(head -n 40 "$transcript" 2>/dev/null | jq -rs '
  [ .[] | select(type == "object") | .timestamp // empty ] | first // empty' 2>/dev/null || true)"
if [ -n "$first_ts" ]; then
  # -u OBLIGATORIO: los timestamps del transcript son UTC (sufijo Z). Sin -u,
  # BSD date los interpreta como hora local y la edad sale corrida por el offset
  # del huso (en La Paz, UTC-4, una sesion de 8h se leia como 4h y esquivaba el
  # umbral). Bug cazado al probar el hook contra un transcript real.
  first_s="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "${first_ts%%.*}" +%s 2>/dev/null || echo 0)"
  case "$first_s" in ''|*[!0-9]*) first_s=0 ;; esac
  [ "$first_s" -gt 0 ] && age_h=$(( ( $(date +%s) - first_s ) / 3600 ))
fi

ctx_k=$(( ctx / 1000 ))

level=""
if   [ "$ctx" -ge 400000 ]; then level=CRITICO
elif [ "$ctx" -ge 300000 ]; then level=ALTO
elif [ "$ctx" -ge 200000 ]; then level=AVISO
fi

# Sesion larga con contexto todavia sano: avisar igual, pero sin escalar.
[ -z "$level" ] && [ "$age_h" -ge 10 ] && level=AVISO

[ -z "$level" ] && drop

# MODO EJECUCION — silencio deliberado (2026-09-01).
#
# Los umbrales originales (120k/180k, edad 6h) se calibraron para EXPLORACION,
# donde el contexto crece porque se esta leyendo de mas. Pero cuando el plan ya
# esta cerrado —una SDD con proposal, spec, design y tasks definidos— el
# contexto grande no es desperdicio: es el contrato que hay que respetar. Ahi el
# aviso interrumpe trabajo legitimo y empuja a cortar sesiones que deberian
# terminar la tanda.
#
# Con el interruptor puesto se callan AVISO y ALTO. CRITICO NUNCA se silencia:
# a 400k el costo es real (tamano x requests, casi todo cache read) y ese fue
# el hallazgo de la auditoria del 2026-08-31. Un interruptor que apaga el techo
# no es un interruptor, es sacarle el fusible al tablero.
#
#   Prender:  touch ~/.claude/.ctx-quiet     (o CLAUDE_CTX_QUIET=1)
#   Apagar:   rm ~/.claude/.ctx-quiet
if [ "$level" != "CRITICO" ]; then
  if [ -f "$HOME/.claude/.ctx-quiet" ] || [ "${CLAUDE_CTX_QUIET:-0}" = "1" ]; then
    drop
  fi
fi

age_note=""
[ "$age_h" -ge 6 ] && age_note=" La sesion lleva ${age_h}h abiertas: arrastras el contexto del primer problema hasta el ultimo commit."

# Escritura atomica en el MISMO directorio: el lector no puede encontrarse un
# aviso a medio escribir.
tmp="$(mktemp "$CACHE_DIR/.tmp.XXXXXX" 2>/dev/null)" || exit 0
{
case "$level" in
  AVISO)
    printf 'PRESUPUESTO DE CONTEXTO — AVISO: %sk tokens en juego.%s\n' "$ctx_k" "$age_note"
    printf 'No abra frentes nuevos. Preserve checkpoint y use /compact nativo para continuar la misma tarea; conserve pendientes y decisiones aprobadas.\n'
    ;;
  ALTO)
    printf 'PRESUPUESTO DE CONTEXTO — ALTO: %sk tokens por request.%s\n' "$ctx_k" "$age_note"
    printf 'Cada turno relee esos %sk. Preserve checkpoint y use /compact nativo antes de continuar la misma tarea. No reinicie herramientas activas ni reabra decisiones aprobadas.\n' "$ctx_k"
    ;;
  CRITICO)
    printf 'PRESUPUESTO DE CONTEXTO — CRITICO: %sk tokens por request.%s\n' "$ctx_k" "$age_note"
    printf 'Esto es zona de quemado: el costo es tamaño_de_contexto x cantidad_de_requests y ya estás pagando %sk en CADA turno, casi todo cache read.\n' "$ctx_k"
    printf 'Detenga la exploracion. Preserve checkpoint y use /compact nativo; recupere la misma tarea y valide propietario/procesos antes de continuar. Si no esta disponible, informe esa limitacion concreta. Contexto no demuestra cuota agotada ni autoriza reset.\n'
    ;;
esac
} > "$tmp" 2>/dev/null

if [ -s "$tmp" ]; then
  mv -f "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null
else
  rm -f "$tmp" 2>/dev/null
fi
exit 0
