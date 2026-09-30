#!/usr/bin/env bash
# PreToolUse(Bash) — un deploy solo sale de un checkout que representa al ambiente.
#
# Incidente 2026-08-31 (clase "fallo que obliga a reintentar"): corrí
# `indexes:deploy:test` desde un checkout cuyo firestore.indexes.json NO tenía
# el fieldOverride commiteado en otra rama — firebase REEMPLAZA la config
# completa, así que el deploy BORRÓ una exemption que estaba building y hubo
# que detectarlo por REST y re-deployar. La regla que esto codifica:
#
#   Antes de `firebase deploy` / `npm run indexes:deploy:*` / `rules:deploy:*`:
#   1. El working tree de los archivos de config (firestore.indexes.json,
#      firestore.rules, firebase.json) debe estar LIMPIO.
#   2. El HEAD debe CONTENER el estado de esos archivos en origin/dev
#      (fetch fresco) — si dev tiene config que tu checkout no, tu deploy
#      la pisa. (Deploy desde una rama ADELANTADA a dev está bien: es el
#      caso "mi rama tiene el override nuevo".)
#
# Fail-open ante lo no parseable; el bloqueo lleva instrucción concreta.
#
# Contrato verificable: ~/.claude/hooks/tests/deploy-checkout-guard-tests.sh
# (correlo SIEMPRE después de tocar este archivo). Los límites conocidos y
# aceptados —comando real dentro de comillas, ruta con espacios— están fijados
# ahí como casos, no son descuidos.

set -uo pipefail

input="$(cat 2>/dev/null || true)"
case "$input" in *deploy*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# Autoría vs ejecución (misma clase que anti-polling/route-hook, 2026-08-31):
# "indexes:deploy" DENTRO de un string citado (body de un PR, un echo, un doc)
# es texto, no un deploy. Se descartan contenidos entre comillas antes de
# matchear; un deploy real vive fuera de comillas.
cmd_scan="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"

# El patrón admite flags ENTRE el binario y el subcomando (`firebase --project
# X deploy` es la forma que documenta Firebase) y la invocación por npx
# (`firebase-tools deploy`). Agujeros medidos el 2026-09-07: ambos esquivaban
# el `firebase +deploy` original y pasaban con rc=0.
# El corte en ; & | es lo que impide que esto se coma comandos ajenos: en
# `firebase use test && npm run deploy:docs` el && corta antes del deploy.
DEPLOY_RE='firebase[^;&|]*deploy|indexes:deploy|rules:deploy'
printf '%s' "$cmd_scan" | grep -qE "$DEPLOY_RE" || exit 0

# Resolver el repo desde el cwd del comando (cd X && ... | git -C X)
# ÚLTIMO cd/git -C ANTES del deploy (no el primero, ni uno posterior):
#  - no el primero: en comandos compuestos el deploy corre desde el directorio
#    más reciente (bug propio, 2026-08-31: evaluaba el checkout base stale
#    aunque el deploy salía de un worktree fresco).
#  - no uno posterior: un `cd` a un checkout limpio DESPUÉS del deploy hacía
#    que el guard evaluara el repo equivocado y dejara pasar (agujero medido el
#    2026-09-07). Por eso se busca sólo en el PREFIJO anterior al deploy.
pre="$(printf '%s' "$cmd_scan" | awk -v re="$DEPLOY_RE" '
  { if (match($0, re)) { print substr($0, 1, RSTART-1); exit } print }')"
dir="$(printf '%s' "$pre" | grep -oE '(cd|git -C) +[^ ;&|]+' | tail -1 | awk '{print $NF}')"
dir="${dir/#\~/$HOME}"
[ -d "$dir" ] || dir="$PWD"
repo="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$repo" ] || exit 0   # sin repo detectable: no bloquear (deploys ad-hoc)

CFGS="firestore.indexes.json firestore.rules firebase.json"

dirty="$(cd "$repo" && git status --porcelain -- $CFGS 2>/dev/null | head -3)"
if [ -n "$dirty" ]; then
  printf 'BLOQUEADO (deploy-checkout-guard): config de Firebase con cambios sin commitear en %s:\n%s\nUn deploy publica el ESTADO DEL ARCHIVO, no el de git — commiteá o descartá antes de deployar.\n' "$repo" "$dirty" >&2
  exit 2
fi

git -C "$repo" fetch origin dev --quiet 2>/dev/null || exit 0
for f in $CFGS; do
  git -C "$repo" cat-file -e "origin/dev:$f" 2>/dev/null || continue
  if ! git -C "$repo" diff --quiet HEAD origin/dev -- "$f" 2>/dev/null; then
    # Distinto de dev: ¿mi HEAD CONTIENE la versión de dev (estoy adelante) o me falta config (estoy atrás/aparte)?
    if git -C "$repo" merge-base --is-ancestor origin/dev HEAD 2>/dev/null; then
      continue   # adelantado a dev: mi config es superset del futuro — permitido
    fi
    printf 'BLOQUEADO (deploy-checkout-guard): %s difiere de origin/dev y tu HEAD NO contiene el estado de dev.\nUn deploy desde acá PISA config que otra rama ya publicó (firebase reemplaza la config completa — pasó el 2026-08-31 con el fieldOverride de enrollment.hr).\nDeployá desde un checkout rebasado sobre origin/dev, o mergeá primero tu config a dev.\n' "$f" >&2
    exit 2
  fi
done
exit 0
