#!/usr/bin/env bash
# SessionStart — saca el sufijo [1m] del modelo en settings.json, conservando
# el modelo elegido.
#
# Origen (2026-09-08): el usuario cambia de modelo segun la tarea, y eso esta
# bien. El problema no es cual elige: es que `/model` PERSISTE la eleccion en
# settings.json, sufijo incluido. Asi, un `[1m]` pedido para una sesion puntual
# se convierte en el default de todas las siguientes. verify.sh lo declara FAIL
# (saca el techo de contexto que fuerza la compactacion: la sesion del
# 2026-09-07 llego a 16h y 188k con tres avisos y sin cortar nunca), y limpiarlo
# a mano es disciplina, no enforcement.
#
# La logica correcta ya existia en bootstrap.sh:196-206 -- conservar el modelo,
# descartar el millon -- pero bootstrap corre una sola vez, en la instalacion.
# Este hook la aplica en cada arranque.
#
# POR QUE SessionStart ES SEGURO (no hay carrera): los hooks se DEFINEN dentro
# de settings.json, asi que Claude Code ya lo leyo antes de poder ejecutar
# ninguno. Cuando este hook escribe, el modelo de la sesion en curso ya esta
# fijado; la escritura solo afecta al proximo arranque. Esa es exactamente la
# semantica buscada: [1m] se pide por sesion con /model y NO se hereda.
#
# Fail-open en todo: sin jq, sin archivo, JSON invalido, sin permiso de
# escritura -> exit 0 sin ruido y sin tocar nada. Un hook de arranque jamas
# puede impedir que una sesion arranque.

set -uo pipefail

SETTINGS="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"

# Fail-open: nada que hacer sin herramienta o sin archivo.
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$SETTINGS" ] || exit 0

# Si es un symlink se escribe el DESTINO. Sin esto, el mv atomico reemplazaria
# el enlace por un archivo regular y romperia el dotfile enlazado.
if [ -L "$SETTINGS" ]; then
  target="$(cd "$(dirname "$SETTINGS")" 2>/dev/null && readlink "$SETTINGS")" || exit 0
  case "$target" in
    /*) SETTINGS="$target" ;;
    *)  SETTINGS="$(dirname "$SETTINGS")/$target" ;;
  esac
  [ -f "$SETTINGS" ] || exit 0
fi

# JSON invalido -> no se toca. Reescribirlo lo destruiria.
#
# La validacion es ESTRICTA (un unico objeto) y no el `jq -e .` obvio. Con el
# obvio, un archivo que sea un STREAM de dos objetos —'{...}\n{...}'— pasa con
# rc=0, y la reescritura posterior devuelve LOS DOS objetos y ademas inyecta
# .model en el segundo: settings.json queda corrupto. Cazado con una sonda al
# escribir este contrato, no leyendo el hook.
jq -s -e 'length == 1 and (.[0] | type == "object")' "$SETTINGS" >/dev/null 2>&1 || exit 0

model="$(jq -r '.model // empty' "$SETTINGS" 2>/dev/null || true)"
[ -n "$model" ] || exit 0

# ANCLAJE: el sufijo se busca al FINAL de la cadena. Un `[1m]` en el medio (o en
# cualquier otro lugar del archivo, como un escape ANSI dentro del comando de un
# hook) no es un modelo de un millon y no se toca.
case "$model" in
  *"[1m]") ;;
  *) exit 0 ;;
esac

stripped="${model%\[1m\]}"

# Degenerado: el modelo era literalmente "[1m]". Dejarlo vacio seria peor que
# dejarlo como esta -- un settings.json con "model": "" no arranca en el modelo
# que el usuario espera. Se reporta y no se toca.
if [ -z "$stripped" ]; then
  printf 'AVISO: settings.json tiene "model": "[1m]" (sin modelo base). No se toca; corregilo con /model.\n'
  exit 0
fi

# Escritura atomica en el MISMO directorio: un mv entre filesystems no es
# atomico. Si jq falla, el original queda intacto.
dir="$(dirname "$SETTINGS")"
tmp="$(mktemp "$dir/.settings.json.XXXXXX" 2>/dev/null)" || exit 0
if jq --arg m "$stripped" '.model = $m' "$SETTINGS" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
  # Conservar permisos del original antes de reemplazarlo.
  chmod --reference="$SETTINGS" "$tmp" 2>/dev/null \
    || chmod "$(stat -f '%Lp' "$SETTINGS" 2>/dev/null || echo 644)" "$tmp" 2>/dev/null || true
  if mv -f "$tmp" "$SETTINGS" 2>/dev/null; then
    printf 'MODELO: se quito el sufijo [1m] de settings.json (queda "%s"). El millon de contexto se pide por sesion con /model; no se hereda.\n' "$stripped"
    exit 0
  fi
fi
rm -f "$tmp" 2>/dev/null
exit 0
