#!/usr/bin/env bash
# Contrato de claude-sessions: que lo que imprime sea lo que midió.
#
# La versión anterior (reescrita el 2026-09-03) tenía tres defectos de la misma
# familia — presentar una inferencia como una medición — y un cuarto que apareció
# al probarla. Cada caso de abajo es uno de esos defectos convertido en test:
#
#   1. cwd: decía "suelta en ~" cuando el NOMBRE del transcript no contenía
#      `triangulate-`. Eso sólo dice "no es una triangulación". El cwd se mide
#      con lsof o no se afirma.
#   2. inactividad: la derivaba de `etime`, la edad del PROCESO, que `/clear` no
#      reinicia. El 2026-09-03 el PID 28975 llevaba 28h de proceso y estaba
#      entregando trabajo. Se mide por mtime del transcript.
#   3. umbrales: avisaba PESADA a 120k mientras el hook de presupuesto recién avisa a
#      200k, así que la tabla contradecía a la barrera. Tienen que ir juntos.
#   4. mapeo cwd -> directorio de proyecto: reemplazaba sólo `/` y `.`, pero
#      Claude Code reemplaza TODO lo no alfanumérico. Con `cocoa_v2` el
#      directorio no existía y la fila entera salía "?" — un error leído como
#      ausencia de datos.
#
# No se abren sesiones ni se tocan las del usuario: se inspecciona el source.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_DIR/files/shared/bin/claude-sessions"
# Los umbrales viven en el hook que MIDE. Desde el 2026-09-08 la medicion se
# mudo a context-budget-measure.sh (Stop): context-budget.sh quedo como un
# lector sin forks y ya no contiene ningun umbral.
HOOK="$REPO_DIR/files/claude/hooks/context-budget-measure.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -f "$SRC" ]  || fail "no existe $SRC"
[ -x "$SRC" ]  || fail "$SRC no es ejecutable"
[ -f "$HOOK" ] || fail "no existe $HOOK (¿cambió de ruta el hook de presupuesto?)"

bash -n "$SRC" || fail "el source no pasa el chequeo de sintaxis"

# El source DOCUMENTA en sus comentarios los defectos que corrigió, así que
# grepear el archivo entero por "VIEJA" o "suelta en ~" daría positivo contra la
# explicación en vez de contra el código. Se inspecciona sólo el código.
CODE="$(grep -v '^[[:space:]]*#' "$SRC")"

# --- 1. El cwd se mide, no se infiere del nombre del transcript --------------
printf '%s' "$CODE" | grep -q 'lsof -a -p .* -d cwd' \
  || fail "el cwd ya no se mide con lsof"
printf '%s' "$CODE" | grep -q 'suelta en ~' \
  && fail 'volvió el literal "suelta en ~": es una inferencia sobre el cwd, no una medición'

# --- 2. La inactividad sale del transcript, no de la edad del proceso --------
printf '%s' "$CODE" | grep -q 'stat -f %m' \
  || fail "la inactividad ya no se mide por mtime del transcript"
printf '%s' "$CODE" | grep -q 'etime' \
  && fail "etime volvió a usarse: es la edad del PROCESO y /clear no la reinicia"
printf '%s' "$CODE" | grep -q 'VIEJA' \
  && fail 'volvió el estado "VIEJA": una sesión vieja e inactiva no paga nada'

# --- 3. Umbrales alineados con el hook de presupuesto ------------------------
for level in AVISO ALTO CRITICO; do
  case "$level" in
    AVISO)   var=CTX_AVISO ;;
    ALTO)    var=CTX_ALTO ;;
    CRITICO) var=CTX_CRITICO ;;
  esac
  tool="$(sed -n "s/^${var}=\"\${CLAUDE_SESSIONS_${var}:-\([0-9]*\)}\"$/\1/p" "$SRC")"
  [ -n "$tool" ] || fail "no se pudo leer el umbral $var de claude-sessions"
  hook="$(sed -n "s/^if *\[ \"\$ctx\" -ge \([0-9]*\) \]; then level=${level}\$/\1/p;s/^elif \[ \"\$ctx\" -ge \([0-9]*\) \]; then level=${level}\$/\1/p" "$HOOK" | head -1)"
  [ -n "$hook" ] || fail "no se pudo leer el umbral de $level en context-budget-measure.sh"
  [ "$tool" = "$hook" ] \
    || fail "umbral $level desalineado: claude-sessions=$tool, context-budget-measure.sh=$hook"
done

# --- 4. El mapeo cwd -> directorio de proyecto cubre todo lo no alfanumérico --
# Se ejecuta la función real del source, no una copia de su lógica.
mapped="$(
  eval "$(sed -n '/^proj_dir_of()/p' "$SRC")"
  proj_dir_of '/Users/x/cocoa_v2/.claude/worktrees/triangulate-a'
)"
expected='-Users-x-cocoa-v2--claude-worktrees-triangulate-a'
[ "$mapped" = "$expected" ] \
  || fail "mapeo cwd->proyecto incorrecto: '$mapped' != '$expected' (¿volvió el set [/.]?)"

# --- 5. Ningún error silenciado en las rutas de medición ---------------------
# Un 2>/dev/null en una medición convierte un fallo en un "no hay nada", que es
# como se coló "ninguna escritura en 6 horas" con un find que ni corrió.
if printf '%s' "$CODE" | grep -n '2>/dev/null' | grep -vE 'command -v|mktemp'; then
  fail "hay 2>/dev/null en una ruta de medición: el silencio se leería como ausencia"
fi

# --- 6. El texto del aviso no cobra por horas abiertas -----------------------
printf '%s' "$CODE" | grep -q 'el costo son los TURNOS' \
  || fail "el aviso ya no dice que el costo son los turnos, no las horas abiertas"

# --- 7. El loop de --watch conserva su techo duro ----------------------------
printf '%s' "$CODE" | grep -q 'while \[ "\$i" -lt 360 \]' \
  || fail "--watch perdió el techo de vueltas (regla del harness: ningún loop sin fin)"

printf 'OK: claude-sessions mide lo que dice medir (7 casos)\n'
