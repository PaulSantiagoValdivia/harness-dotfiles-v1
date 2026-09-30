#!/usr/bin/env bash
# UserPromptSubmit — entrega el aviso de presupuesto de contexto que ya calculo
# context-budget-measure.sh en el Stop anterior.
#
# Este hook NO MIDE NADA, y esa es toda la idea.
#
# Origen (2026-09-08): la version que media aca se caia con
# `UserPromptSubmit hook timed out after 30s -- output discarded`, una y otra
# vez, en las triangulaciones. Medido: 0.149s idle contra un transcript de
# 10MB. No era lento; hacia 12 forks (5 de ellos jq, uno slurpeando megabytes)
# y una Mac con load 395 se los cobraba todos. Reescribirlo a un solo fork daba
# 1.7x, y 1.7x no saca de un frenon de ~200x.
#
# Subir el `timeout`, que es lo que sugiere el propio mensaje del harness, es la
# PEOR opcion: UserPromptSubmit corre ANTES de que el prompt se procese, asi que
# un timeout mas largo hace ESPERAR al usuario en vez de perder un aviso que no
# le costaba nada perder. Cambia ruido barato por latencia cara.
#
# La medicion vive en Stop, fuera de UserPromptSubmit; Stop sigue siendo
# sincrono salvo configuracion explicita. Aca solo se lee el resultado, y con CERO forks: `read` es builtin, el
# session_id sale con una regex de bash en vez de jq, y `$(<archivo)` es una
# redireccion builtin. En el camino comun —sin aviso vigente— este hook no
# ejecuta un solo proceso externo, asi que la contencion de CPU no tiene de
# donde agarrarlo.
#
# Compactacion puede reducir el contexto: SessionStart compact invalida el
# cache de esa sesion. Stop descarta usage anterior a compact_boundary; este
# lector sigue sin medir ni ejecutar procesos externos.
#
# Fail-open, como siempre: sin entrada, sin session_id o sin cache -> exit 0
# mudo. Nunca bloquea el prompt.

set -uo pipefail

CACHE_DIR="${CLAUDE_CTX_CACHE_DIR:-$HOME/.claude/hooks/state/ctx-budget}"

# Lectura de stdin SIN forkear (nada de `cat`).
input=""
line=""
while IFS= read -r line || [ -n "$line" ]; do
  input+="$line"
  line=""
done
[ -n "$input" ] || exit 0

# session_id con regex de bash: jq seria un fork, y este hook no puede pagarlo.
[[ "$input" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] || exit 0
session="${BASH_REMATCH[1]}"
[ -n "$session" ] || exit 0
session="${session//[^A-Za-z0-9._-]/_}"
case "$session" in ''|.|..) exit 0 ;; esac

cache="$CACHE_DIR/$session"
[ -f "$cache" ] || exit 0

# `$(<archivo)` es builtin: lee sin lanzar un proceso.
msg="$(<"$cache")" || exit 0
[ -n "$msg" ] || exit 0

printf '%s\n' "$msg"
exit 0
