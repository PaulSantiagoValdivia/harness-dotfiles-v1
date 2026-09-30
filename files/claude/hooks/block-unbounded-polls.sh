#!/usr/bin/env bash
# PreToolUse(Bash) — bloquea polling sin techo ANTES de que corra.
#
# Complemento preventivo de reap-stale-polls.sh (que solo limpia DESPUÉS,
# al cierre del turno). Nace del mismo incidente 2026-08-25: loops
# `until gh pr checks ... | grep ...; do sleep; done` girando 11 y 92 min
# esperando un CI que ya había terminado.
#
# Qué bloquea (exit 2 => el comando NO corre y Claude recibe el motivo):
#   1. Loops until/while + sleep SIN techo (sin contador acotado ni timeout).
#   2. `gh run watch` / `gh pr checks --watch` sin envoltura con techo.
#   3. `sleep N` con N >= 300s (5 min muertos sin chequear nada), con o sin
#      sufijo de unidad: 300, 5m, 1h y 1d bloquean por igual.
#
# Qué deja pasar:
#   - Loops con contador acotado EN LA CONDICIÓN: `[ $i -lt 30 ]`, `(( i < 30 ))`.
#   - Loops con contador acotado en el cuerpo ACOMPAÑADO de `break`.
#   - Loops envueltos en timeout/gtimeout (si coreutils está instalado).
#   - Todo lo demás (fail-open: si no se puede parsear el input, exit 0).
#
# Un loop dentro de comillas (bash -c 'until ...; do sleep 10; done') es un loop
# REAL y se bloquea igual: el anclaje incluye la comilla de apertura. Lo
# contrario dejaba pasar el loop ejecutable y bloqueaba el texto que lo
# menciona — exactamente al revés de lo útil (medido 2026-09-07).
#
# CONTRATO VERIFICABLE: ~/.claude/hooks/tests/block-unbounded-polls-tests.sh
# (54 casos). Correlo SIEMPRE después de tocar este archivo. Los límites que
# NO cubre están fijados ahí como casos, para que taparlos sea una decisión.

set -uo pipefail

input="$(cat 2>/dev/null || true)"

# Pre-filtro barato: si el JSON crudo no menciona sleep/watch, no hay nada
# que bloquear — salir sin pagar el spawn de jq (camino común, ~cada Bash).
case "$input" in
  *sleep*|*watch*) ;;
  *) exit 0 ;;
esac

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# Falso positivo cazado 2026-08-30: un comando que ESCRIBE un archivo por
# heredoc (cat > script <<'EOF' ... EOF, python3 - <<'PY' con un patch adentro)
# contiene el texto de un loop con sleep pero no lo EJECUTA. Bloqueó 3 veces
# la autoría de un script legítimo. Antes de escanear, descartar los cuerpos
# de heredoc: del marcador <<XXX hasta la línea que solo contiene XXX.
# 2026-09-07: `<<- EOF` (guion Y espacio) es sintaxis VÁLIDA de bash y no se
# reconocía, así que ese cuerpo se escaneaba como código a ejecutar. El
# terminador de un `<<-` viene indentado con tabs: se compara ya trimeado.
scan_src="$(printf '%s' "$cmd" | awk '
  inhd { line=$0; sub(/^[ \t]+/, "", line); if (line == hd_end) inhd=0; next }
  match($0, /<<-?[ \t]*['"'"'"]?[A-Za-z_][A-Za-z_0-9]*/) {
    hd_end = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[ \t]*['"'"'"]?/, "", hd_end)
    inhd = 1
    print; next
  }
  { print }
')"

# Aplanar a una línea: los loops suelen venir multilínea.
flat="$(printf '%s' "$scan_src" | tr '\n' ' ')"

# Anclaje de inicio de comando: separadores, apertura de subshell, espacio Y
# comillas. Sin las comillas, `bash -c 'until ...'` esquivaba la regla 1 entera.
ANCHOR="(^|[;&|(\"'[:space:]])"

block() {
  printf '%s\n' "$1" >&2
  printf 'Regla: "Background Tasks and Waiting" de ~/.claude/CLAUDE.md. Preferí el chequeo DIRECTO una sola vez (ej: gh pr checks <PR> / gh run view <id> --json status,conclusion) y volvé a consultar en el próximo turno — el harness te re-invoca al completar background tasks, no hace falta polear. Si un loop es imprescindible: (1) nombrá el input concreto que hace verdadera la condición de salida, (2) ponele techo con contador: i=0; until <cond> || [ $i -ge 30 ]; do sleep 10; i=$((i+1)); done — y si se agota, informalo.\n' >&2
  exit 2
}

# Tramo de comando en el que vive el primer match de $1: desde el último
# separador (; & |) ANTERIOR al match. Un escape solo vale si está en el MISMO
# tramo que el comando peligroso — `echo "usa timeout 30"; until ...` no está
# envuelto en nada. (Misma clase de bug de ámbito que el `cd` posterior al
# deploy en deploy-checkout-guard, 2026-09-07.)
seg_before() {
  printf '%s' "$flat" | awk -v re="$1" '
    match($0, re) { p = substr($0, 1, RSTART-1); n = split(p, a, /[;&|]/); print a[n] }'
}

has_timeout() { printf '%s' "$1" | grep -qE '(^|[;&|([:space:]])g?timeout +[0-9]'; }

# Contador con techo: forma test (`-lt 30`) o aritmética (`(( i < 30 ))`).
CAP_RE='\-(lt|le|ge|gt) +[0-9]+|\(\([^)]*[<>]=? *[0-9]+'

# ── 3. sleep largo a secas (>= 300s): tiempo muerto sin chequear nada. ──
# El sufijo de unidad se INTERPRETA: leer solo el número dejaba pasar
# `sleep 30m` (1800s), que es justo la sintaxis natural de una espera larga.
while read -r tok; do
  [ -z "$tok" ] && continue
  num="${tok%%[smhd]}"
  unit="${tok#"$num"}"
  case "$unit" in
    ""|s) secs="$num" ;;
    m)    secs=$(( num * 60 )) ;;
    h)    secs=$(( num * 3600 )) ;;
    d)    secs=$(( num * 86400 )) ;;
    *)    continue ;;
  esac
  [ "$secs" -ge 300 ] 2>/dev/null && \
    block "BLOQUEADO (anti-polling): sleep ${tok} deja el turno muerto ${secs}s sin chequear nada."
done < <(printf '%s' "$flat" | grep -oE "${ANCHOR}sleep +[0-9]+[smhd]?" | grep -oE '[0-9]+[smhd]?$')

# ── 2. watchers de gh sin techo. ──
# El corte en `; & |` permite flags entre el binario y el subcomando
# (`gh --repo o/r run watch`) sin comerse comandos ajenos. Exigir adyacencia
# dejaba ciega justo la variante que usás cuando el cwd no es el repo.
WATCH_RE='gh[^;&|]*run[^;&|]*watch|gh[^;&|]*pr[^;&|]*checks[^;&|]*--watch'
if printf '%s' "$flat" | grep -qE "$WATCH_RE"; then
  has_timeout "$(seg_before "$WATCH_RE")" || \
    block "BLOQUEADO (anti-polling): gh ... --watch / gh run watch sin techo puede colgarse indefinidamente (PR cerrado, run equivocado)."
fi

# ── 1. Loop until/while + sleep sin techo. ──
LOOP_RE="${ANCHOR}(until|while) "
if printf '%s' "$flat" | grep -qE "$LOOP_RE.*sleep +[0-9]"; then
  # Escape válido a: envuelto en timeout/gtimeout, en el MISMO tramo.
  has_timeout "$(seg_before '(until|while) ')" && exit 0
  # Escape válido b: contador acotado en la CONDICIÓN del loop (entre el
  # until/while y su `do`). Buscarlo en todo el comando era falso: un
  # `[ $j -lt 5 ]` en el cuerpo, sin break, no es techo de nada.
  cond="$(printf '%s' "$flat" | awk '
    match($0, /(until|while) /) {
      r = substr($0, RSTART)
      if (match(r, /(^|[;&[:space:]])do([;&[:space:]]|$)/)) r = substr(r, 1, RSTART-1)
      print r
    }')"
  printf '%s' "$cond" | grep -qE "$CAP_RE" && exit 0
  # Escape válido c: contador acotado en el cuerpo, pero SOLO si hay un
  # `break` que lo convierta en salida real.
  if printf '%s' "$flat" | grep -qE "${ANCHOR}break([;&[:space:]]|$)"; then
    printf '%s' "$flat" | grep -qE "$CAP_RE" && exit 0
  fi
  block "BLOQUEADO (anti-polling): loop until/while + sleep SIN techo de iteraciones."
fi

exit 0
