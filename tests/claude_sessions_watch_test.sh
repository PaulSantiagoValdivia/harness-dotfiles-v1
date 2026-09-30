#!/usr/bin/env bash
# Contrato de claude-sessions-watch, el vigilante launchd.
#
# El vigilante nació de una premisa que se cayó: avisar de "sesiones viejas"
# medidas por antigüedad de PROCESO. `/clear` no reinicia el proceso, así que
# esa medición no dice nada de la conversación — un vigilante encima habría
# industrializado el falso positivo cada 30 minutos hasta volverse ignorable.
#
# Lo que se construyó avisa por PESADA Y QUIETA, la única condición que ninguna
# otra barrera puede ver (context-budget.sh corre en UserPromptSubmit, o sea
# sólo cuando el usuario escribe; una sesión abandonada no escribe nunca más).
#
# Cada caso de abajo fija una propiedad que, si se rompe, devuelve el vigilante
# a ser ruido. Se corre con un inspector de mentira: no se leen las sesiones
# reales del usuario ni se emite una sola notificación.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCH="$REPO_DIR/files/shared/bin/claude-sessions-watch"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/claude-sessions-watch-test.XXXXXX")"
cleanup() {
  case "${TMP_ROOT:-}" in
    *claude-sessions-watch-test.*) rm -rf "$TMP_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -x "$WATCH" ] || fail "no existe o no es ejecutable $WATCH"
bash -n "$WATCH" || fail "el vigilante no pasa el chequeo de sintaxis"

STUB="$TMP_ROOT/inspector"
STATE="$TMP_ROOT/state"
LOG="$TMP_ROOT/log"

# Inspector de mentira: emite las filas que le pongamos en $TMP_ROOT/rows, en el
# mismo formato tab-separated que `claude-sessions --porcelain`.
cat > "$STUB" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = "--porcelain" ] || exit 64
cat "$TMP_ROOT/rows"
EOF
chmod +x "$STUB"

run() {
  CLAUDE_SESSIONS_BIN="$STUB" \
  CLAUDE_SESSIONS_WATCH_STATE="$STATE" \
  CLAUDE_SESSIONS_WATCH_LOG="$LOG" \
  "$WATCH" "$@"
}
tab="$(printf '\t')"
rows() { printf '%s\n' "$@" | tr '|' "$tab" > "$TMP_ROOT/rows"; }

# --- 1. Pesada Y quieta: avisa ----------------------------------------------
rows '111|250000|180|AVISO|1|0|repo-abandonado'
out="$(run --dry-run)" || fail "el vigilante falló con una sesión olvidada"
printf '%s' "$out" | grep -q 'repo-abandonado' \
  || fail "no avisó por una sesión pesada y quieta: $out"
printf '%s' "$out" | grep -q 'pid 111' \
  || fail "no identificó el PID de una sesión no ambigua"

# --- 2. Pesada pero ACTIVA: no avisa ----------------------------------------
# Su propio hook ya le avisa a ella; duplicarlo es ruido.
rows '111|250000|1|AVISO|0|0|repo-trabajando'
out="$(run --dry-run)"
printf '%s' "$out" | grep -q 'repo-trabajando' \
  && fail "avisó por una sesión pesada que está trabajando"

# --- 3. Quieta pero LIVIANA: no avisa ---------------------------------------
# Es el corazón de la corrección: una sesión vieja e inactiva no paga nada.
rows '111|30000|3000|ok|0|0|repo-viejo-y-liviano'
out="$(run --dry-run)"
printf '%s' "$out" | grep -q 'repo-viejo-y-liviano' \
  && fail "avisó por una sesión inactiva sin contexto: no paga nada"

# --- 4. Métrica del directorio: no se señala un PID que no se puede señalar --
rows '222|250000|200|AVISO|1|1|repo-compartido'
out="$(run --dry-run)"
printf '%s' "$out" | grep -q 'repo-compartido' \
  || fail "no avisó por una sesión olvidada en un directorio compartido"
printf '%s' "$out" | grep -q 'pid 222' \
  && fail "señaló un PID cuando la medición es del directorio (shared=1)"
printf '%s' "$out" | grep -q 'alguna sesión' \
  || fail "no dijo que la atribución es ambigua"

# --- 5. Contexto NO medible: no se decide sobre un dato que no existe -------
rows '333|-|-|?|0|0|repo-sin-medicion'
out="$(run --dry-run)"
printf '%s' "$out" | grep -q 'repo-sin-medicion' \
  && fail "avisó sobre una sesión cuyo contexto no se pudo medir"

# --- 6. Anti-ruido: no repite el mismo aviso -------------------------------
rm -f "$STATE"
rows '444|250000|200|AVISO|1|0|repo-repetido'
run >/dev/null || fail "la corrida real falló"
grep -q '^444' "$STATE" || fail "no registró el aviso en el estado"
before="$(wc -l <"$LOG")"
run >/dev/null || fail "la segunda corrida falló"
after="$(wc -l <"$LOG")"
[ "$before" = "$after" ] \
  || fail "repitió el aviso de una sesión sin cambios: un aviso que se repite se aprende a ignorar"

# --- 7. Si escala de estado, vuelve a avisar --------------------------------
rows '444|350000|260|ALTO|1|0|repo-repetido'
run >/dev/null || fail "la corrida de escalada falló"
[ "$(wc -l <"$LOG")" -gt "$after" ] \
  || fail "no volvió a avisar cuando la sesión escaló de AVISO a ALTO"

# --- 8. Sin inspector: no inventa, loguea y sale limpio ---------------------
out="$(CLAUDE_SESSIONS_BIN="$TMP_ROOT/no-existe" \
       CLAUDE_SESSIONS_WATCH_STATE="$STATE" \
       CLAUDE_SESSIONS_WATCH_LOG="$LOG" "$WATCH" --dry-run)"; rc=$?
[ "$rc" -eq 0 ] || fail "sin inspector debería salir 0 (un vigilante ruidoso se desinstala), salió $rc"
grep -q 'ERROR: no existe' "$LOG" || fail "no dejó constancia de que no pudo medir"
printf '%s' "$out" | grep -q 'sesión' \
  && fail "afirmó algo sobre las sesiones sin haberlas podido medir"

# --- 9. Nunca mata nada ------------------------------------------------------
# Con un límite de atribución conocido (shared), un vigilante que cierre
# sesiones por su cuenta es el falso positivo en su forma destructiva.
code="$(grep -v '^[[:space:]]*#' "$WATCH")"
printf '%s' "$code" | grep -qE '\bkill\b|pkill|killall' \
  && fail "el vigilante contiene una llamada para matar procesos: sólo debe avisar"

# --- 10. Nunca bloquea con un diálogo modal ---------------------------------
# `display dialog` cuelga a quien lo dispare y a cualquiera que lo espere.
printf '%s' "$code" | grep -q 'display dialog' \
  && fail "usa 'display dialog', que bloquea; debe ser 'display notification'"
printf '%s' "$code" | grep -q 'display notification' \
  || fail "no notifica con 'display notification'"

# --- 11. bootstrap no toca launchd cuando el HOME no es el real --------------
# `launchctl` es GLOBAL y no respeta $HOME. Sin esta guarda, cada corrida de
# verify.sh (que ejecuta bootstrap en un HOME temporal) descargaba el vigilante
# real del usuario y cargaba uno apuntando a un tmpdir que el test borra.
# Verificado el 2026-09-03 mirando `launchctl list`, no el plist en disco.
boot="$REPO_DIR/bootstrap.sh"
grep -q 'REAL_HOME=' "$boot" \
  || fail "bootstrap.sh perdió la guarda de HOME real antes de tocar launchd"
awk '/^REAL_HOME=/,/^fi$/' "$boot" | grep -q 'launchctl load' \
  || fail "el launchctl load de bootstrap.sh quedó fuera de la guarda de HOME real"

# --- 12. el chequeo de carga de verify.sh no puede morir por SIGPIPE ---------
# El 2026-09-03 verify.sh reportó "vigilante no cargado" con el vigilante
# cargado: listaba TODOS los servicios y filtraba con `grep -q`, que cierra el
# pipe al primer match; el productor muere con SIGPIPE (141) y el `pipefail` de
# verify.sh hace que ese 141 sea el resultado del `if`. Es una carrera — dos
# corridas seguidas dieron 0 y 141 con el mismo estado del sistema —, así que
# un test que sólo mirara el resultado sería flaky: se fija el IDIOMA, que es
# lo que elimina la carrera. Se inspecciona el CÓDIGO sin comentarios: los
# comentarios que documentan el bug describen el patrón viejo y darían un
# falso positivo contra la documentación en vez de contra el código.
ver="$REPO_DIR/verify.sh"
[ -f "$ver" ] || fail "no encuentro verify.sh para chequear el idioma de launchctl"
ver_code="$(sed 's/#.*//' "$ver")"
printf '%s' "$ver_code" | grep -qE 'launchctl[[:space:]]+list[^|]*\|' \
  && fail "verify.sh volvió a pipear 'launchctl list': SIGPIPE + pipefail da falso negativo"
printf '%s' "$ver_code" | grep -q 'launchctl print' \
  || fail "verify.sh ya no consulta el label cargado con 'launchctl print'"

printf 'OK: claude-sessions-watch avisa sólo por pesada+quieta (12 casos)\n'
