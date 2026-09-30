#!/usr/bin/env bash
# PreToolUse(Bash) — herramientas de calidad SIEMPRE en su versión pineada.
#
# Incidente 2026-08-31 (clase "fallo que obliga a reintentar"): en un worktree
# fresco sin node_modules, `npx prettier --write` bajó prettier 3.9.6 (el repo
# pinea 3.8.3) y formateó con OTRAS reglas — 24 falsos warnings y un commit
# que casi entra mal; hubo que instalar la versión pineada y re-formatear.
#
# Regla: prettier/eslint/tsc/vitest via npx SOLO si existe el binario local
# (node_modules/.bin/<tool>) en el paquete objetivo. Sin binario local →
# bloquear con instrucción de `npm ci` primero. Un formatter/linter/compiler
# con versión flotante produce resultados no reproducibles contra CI.
#
# Fail-open ante lo no parseable. No toca npx de OTRAS herramientas.
#
# Contrato ejecutable: ~/.claude/hooks/tests/pinned-tool-guard-tests.sh
#
# El comando se TOKENIZA (no se matchea con un regex suelto) porque las tres
# clases de agujero medidas el 2026-09-07 salían justamente del matcheo suelto:
#   - ADYACENCIA: `npx --yes <tool>` esquivaba `npx +<tool>` — y --yes es
#     justo el flag que GARANTIZA la descarga flotante.
#   - ÁMBITO: el `cd` se buscaba en TODO el comando con `tail -1`, así que un
#     `cd` POSTERIOR al npx (o dentro de un `echo`) elegía el directorio.
#   - PRIMERA OCURRENCIA: `head -1` evaluaba sólo la primera herramienta, así
#     que `npx eslint . && npx prettier .` con eslint instalado y prettier no
#     dejaba entrar el prettier flotante — el incidente original exacto.
# La herramienta se compara por TOKEN EXACTO (no por `\b`) porque `tsc-alias`,
# `prettier-eslint` y `vitest-preview` son paquetes DISTINTOS y se bloqueaban.
#
# LÍMITES abiertos a propósito, medidos y fijados como casos en la suite:
#   L1 `pnpm dlx` / `bunx` / `yarn dlx` están fuera del contrato (ampliarlo es
#      decisión de producto: hacen lo mismo que npx).
#   L2 en un monorepo con hoisting, un workspace con package.json y sin .bin
#      propio se bloquea: el binario del padre NO prueba el pin del hijo.
#   L3 un `cd` a una ruta con espacios no se resuelve → se conserva el dir
#      anterior (fail-open).
#   L4 `cd -` y otros relativos no resolubles → se conserva el dir anterior.
#   L5 el texto entre comillas se toma como comando, así que
#      `git commit -m 'evitar npx prettier'` se bloquea. Es el precio de L6.
#   L6 ...y gracias a eso `bash -c "npx prettier"` —comando REAL entre
#      comillas— sí se bloquea. Para commitear sobre este tema: `git commit -F`.

set -uo pipefail

input="$(cat 2>/dev/null || true)"
case "$input" in *npx*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

PINNED=" prettier eslint tsc vitest "

# Separadores de comando como tokens propios, para que `cd /a;npx x` tokenice.
norm="$(printf '%s' "$cmd" | sed 's/[;&|()]/ & /g')"
# Comillas fuera: un comando real dentro de comillas (`bash -c "npx x"`) debe
# seguir viéndose. El precio es L5.
norm="${norm//\"/ }"
norm="${norm//\'/ }"

read -r -d '' -a tok <<< "$norm" || true
n=${#tok[@]}

dir="$PWD"
i=0
while [ "$i" -lt "$n" ]; do
  t="${tok[$i]}"

  if [ "$t" = "cd" ] && [ $((i+1)) -lt "$n" ]; then
    cand="${tok[$((i+1))]}"
    cand="${cand/#\~/$HOME}"
    [ -d "$cand" ] && dir="$cand"
    i=$((i+2)); continue
  fi

  if [ "$t" = "npx" ]; then
    j=$((i+1))
    # saltar flags de npx (y el valor de los que lo llevan separado)
    while [ "$j" -lt "$n" ]; do
      u="${tok[$j]}"
      case "$u" in
        -p|--package|-c|--call) j=$((j+2)) ;;
        -*)                     j=$((j+1)) ;;
        *)                      break ;;
      esac
    done
    if [ "$j" -lt "$n" ]; then
      tool="${tok[$j]%%@*}"          # <tool>@<version> sigue siendo <tool>
      case "$PINNED" in
        *" $tool "*)
          probe="$dir"
          while [ "$probe" != "/" ] && [ -n "$probe" ]; do
            [ -x "$probe/node_modules/.bin/$tool" ] && break
            if [ -f "$probe/package.json" ]; then
              printf 'BLOQUEADO (pinned-tool-guard): `npx %s` sin binario local en %s.\nnpx bajaría una versión FLOTANTE (pasó el 2026-08-31: prettier 3.9.6 vs 3.8.3 pineado → formateo incompatible con CI y trabajo rehecho).\nCorré `npm ci` en ese paquete primero, o invocá ./node_modules/.bin/%s.\n' "$tool" "$probe" "$tool" >&2
              exit 2
            fi
            probe="$(dirname "$probe")"
          done
          ;;
      esac
      i="$j"; continue
    fi
  fi

  i=$((i+1))
done
exit 0
