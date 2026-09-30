#!/usr/bin/env bash
# Suite de contrato del bloque "suites de tests versionadas" de verify.sh.
#
# QUÉ MIDE Y POR QUÉ:
# verify.sh CORRE las 10 suites desde $HOME/.claude/hooks/tests/, no desde el
# repo. El loop de drift de hooks compara `files/claude/hooks/*.sh` — un glob
# que NO entra al subdirectorio tests/ — así que hasta el 2026-09-08 una suite
# ablandada en la máquina daba 648 PASS / 0 FAIL con la suite estricta
# versionada intacta. Misma clase de agujero que la exención de los hooks de
# enforcement (2026-09-07): el recibo lo firma un artefacto que nadie compara.
#
# CÓMO: extrae el tramo REAL de verify.sh entre sus marcadores y lo ejecuta con
# `ok`/`bad` stubbeados sobre un $HOME y un $REPO_DIR sintéticos. Mide el
# artefacto vivo, no una copia: si alguien borra el bloque de verify.sh, la
# extracción falla y la suite se pone roja.
#
# LÍMITES CONOCIDOS (a propósito, con su razón — taparlos sería una decisión):
#  - `cmp` compara CONTENIDO, no permisos: una suite con el bit de ejecución
#    distinto pasa (caso 5). El repo tiene suites con y sin +x y verify.sh las
#    corre con `bash <archivo>`, que no necesita el bit.
#  - Los ocultos (.probe-*.sh, .mutate-*.sh) quedan FUERA del barrido inverso:
#    el glob de bash no matchea dotfiles y son scratch de una sesión (caso 19).
#  - El eje "enchufada" es un grep de texto: una mención dentro de un COMENTARIO
#    de verify.sh cuenta como enchufe (caso 15). Distinguirlo pediría parsear
#    bash; el prefijo `hooks/tests/` ya evita el falso positivo por substring
#    de otro nombre (caso 16), que era el riesgo real.
set -uo pipefail

VERIFY="${VERIFY_SH:-$HOME/harness-dotfiles/verify.sh}"
BEGIN='# --- >>> contrato: suites de tests versionadas'
END='# --- <<< contrato: suites de tests versionadas'

PASS=0; FAIL=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf '  FAIL [%s] %s\n' "$CASE" "$1"; }

# --- extracción del tramo vivo -------------------------------------------
[ -f "$VERIFY" ] || { echo "FATAL: no encuentro verify.sh en $VERIFY"; exit 1; }
BLOCK="$TMP/block.sh"
awk -v b="$BEGIN" -v e="$END" '
  index($0,b) { on=1 } on { print } index($0,e) && on { exit }
' "$VERIFY" > "$BLOCK"
if [ ! -s "$BLOCK" ]; then
  echo "FATAL: el bloque marcado no existe en $VERIFY (¿se borraron los marcadores?)"
  exit 1
fi
grep -c . "$BLOCK" >/dev/null || true

# --- runner --------------------------------------------------------------
# Ejecuta el tramo extraído con ok/bad stubbeados. Devuelve líneas "PASS|desc"
# y "FAIL|desc" en $OUT. rc del bloque en $RC.
OUT=""; RC=0
run_block() { # run_block <home> <repo>
  local home="$1" repo="$2" runner="$TMP/run.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -uo pipefail'
    printf '%s\n' 'ok()  { printf "PASS|%s\n" "$1"; }'
    printf '%s\n' 'bad() { printf "FAIL|%s\n" "$1"; }'
    printf '%s\n' 'REPO_DIR="$REPO_UNDER_TEST"'
    cat "$BLOCK"
  } > "$runner"
  OUT="$(HOME="$home" REPO_UNDER_TEST="$repo" bash "$runner" 2>&1)"; RC=$?
}

# --- aserciones (sin forks: `case` evita el falso negativo de grep -q + pipefail) ---
has()     { case "$OUT" in *"$1"*) pass ;; *) fail "esperaba en la salida: $1${2:+ ($2)}" ;; esac; }
hasnt()   { case "$OUT" in *"$1"*) fail "NO esperaba en la salida: $1${2:+ ($2)}" ;; *) pass ;; esac; }
counts()  { # counts <patron> <n>
  local n; n="$(printf '%s\n' "$OUT" | grep -c -- "$1")"
  if [ "$n" = "$2" ]; then pass; else fail "esperaba $2 líneas '$1', hubo $n"; fi
}
rc_is()   { if [ "$RC" = "$1" ]; then pass; else fail "esperaba rc=$1, hubo rc=$RC"; fi; }

# --- banco sintético ------------------------------------------------------
# Devuelve la raíz de un sandbox nuevo con home/ y repo/ ya armados.
# OJO: se llama como `$(sandbox)`, o sea en un SUBSHELL — un contador con una
# variable NO persiste al padre y los 28 casos terminan compartiendo un sandbox
# (primer rojo de esta suite: 14 falsos FAIL por contaminación). mktemp -d es
# el único que da unicidad sin depender de estado del padre.
sandbox() {
  local root; root="$(mktemp -d "$TMP/sb.XXXXXXXX")" || exit 1
  mkdir -p "$root/home/.claude/hooks/tests" "$root/repo/files/claude/hooks/tests"
  : > "$root/repo/verify.sh"
  printf '%s\n' "$root"
}
# put_repo <root> <nombre> <contenido>
put_repo() { printf '%s\n' "$3" > "$1/repo/files/claude/hooks/tests/$2"; }
# put_home <root> <nombre> <contenido>
put_home() { printf '%s\n' "$3" > "$1/home/.claude/hooks/tests/$2"; }
# plug <root> <nombre...> — declara la(s) suite(s) como enchufadas en verify.sh
plug() { local r="$1"; shift; for n in "$@"; do printf 'check "x" bash "$HOME/.claude/hooks/tests/%s"\n' "$n" >> "$r/repo/verify.sh"; done; }
# affirm <archivo que DEBE existir> — el banco se AFIRMA antes de medir
affirm() { [ -e "$1" ] || { echo "FATAL: fixture no armado: $1"; exit 1; }; }

good='echo hola'

# =========================================================================
# A — paridad repo → máquina
# =========================================================================
CASE='1 idéntica'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh "$good"; plug "$r" a-tests.sh
affirm "$r/home/.claude/hooks/tests/a-tests.sh"
run_block "$r/home" "$r/repo"
has 'PASS|suite a-tests.sh instalada e idéntica al source'
hasnt 'FAIL|'
rc_is 0

CASE='2 ausente en la máquina'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh ausente'
hasnt 'PASS|suite a-tests.sh instalada'

CASE='3 contenido distinto (el agujero original)'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh 'echo ablandada'; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh divergente'
hasnt 'PASS|suite a-tests.sh instalada'

CASE='4 difiere en un solo byte'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; printf 'echo hola\n ' > "$r/home/.claude/hooks/tests/a-tests.sh"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh divergente'

CASE='5 LÍMITE: mismo contenido, distinto bit de ejecución → pasa'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh "$good"; plug "$r" a-tests.sh
chmod 755 "$r/repo/files/claude/hooks/tests/a-tests.sh"; chmod 644 "$r/home/.claude/hooks/tests/a-tests.sh"
run_block "$r/home" "$r/repo"
has 'PASS|suite a-tests.sh instalada e idéntica al source'

CASE='6 vacía en la máquina'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; : > "$r/home/.claude/hooks/tests/a-tests.sh"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh divergente'

CASE='7 la ruta de la máquina es un DIRECTORIO'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; mkdir -p "$r/home/.claude/hooks/tests/a-tests.sh"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh ausente'
rc_is 0

CASE='8 symlink de la máquina al archivo del repo'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; ln -s "$r/repo/files/claude/hooks/tests/a-tests.sh" "$r/home/.claude/hooks/tests/a-tests.sh"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'PASS|suite a-tests.sh instalada e idéntica al source'

CASE='9 symlink roto'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; ln -s "$r/no-existe.sh" "$r/home/.claude/hooks/tests/a-tests.sh"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh ausente'
rc_is 0

CASE='10 tests/ de la máquina no existe'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_repo "$r" b-tests.sh "$good"; plug "$r" a-tests.sh b-tests.sh
rm -rf "$r/home/.claude/hooks/tests"
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh ausente'
has 'FAIL|suite b-tests.sh ausente'
rc_is 0

# =========================================================================
# B — parseo
# =========================================================================
CASE='11 suite de la máquina rota: reporta "no parsea", no "divergente"'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh 'if [ 1'; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh no parsea'
hasnt 'divergente'
counts 'FAIL|suite a-tests.sh' 1

CASE='12 rota EN EL REPO y espejada idéntica: el drift no la cazaría, el parseo sí'
r="$(sandbox)"; put_repo "$r" a-tests.sh 'if [ 1'; put_home "$r" a-tests.sh 'if [ 1'; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh no parsea'
hasnt 'PASS|suite a-tests.sh instalada'

# =========================================================================
# C — enchufe: una suite versionada que ningún check corre
# =========================================================================
CASE='13 enchufada'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh "$good"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'PASS|suite a-tests.sh enchufada'

CASE='14 versionada pero ningún check la corre'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh "$good"
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh versionada pero ningún check'
has 'PASS|suite a-tests.sh instalada e idéntica al source'

CASE='15 LÍMITE: mención dentro de un comentario cuenta como enchufe'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh "$good"
printf '# pendiente: correr hooks/tests/a-tests.sh algún día\n' >> "$r/repo/verify.sh"
run_block "$r/home" "$r/repo"
has 'PASS|suite a-tests.sh enchufada'

CASE='16 el prefijo hooks/tests/ evita el falso enchufe por substring'
# verify.sh corre foo-tests.sh; oo-tests.sh existe y NO está enchufada.
r="$(sandbox)"; put_repo "$r" foo-tests.sh "$good"; put_home "$r" foo-tests.sh "$good"
put_repo "$r" oo-tests.sh "$good"; put_home "$r" oo-tests.sh "$good"
plug "$r" foo-tests.sh
run_block "$r/home" "$r/repo"
has 'PASS|suite foo-tests.sh enchufada'
has 'FAIL|suite oo-tests.sh versionada pero ningún check'

CASE='17 verify.sh ausente en el repo: no crash'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" a-tests.sh "$good"; rm -f "$r/repo/verify.sh"
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh versionada pero ningún check'
rc_is 0

# =========================================================================
# D — dirección inversa: máquina → repo
# =========================================================================
CASE='18 suite que sólo vive en la máquina'
r="$(sandbox)"; put_home "$r" huerfana-tests.sh "$good"
run_block "$r/home" "$r/repo"
has 'FAIL|suite huerfana-tests.sh existe en la máquina y NO está versionada'

CASE='19 LÍMITE: los ocultos de scratch quedan fuera a propósito'
r="$(sandbox)"; put_home "$r" .probe-x.sh "$good"; put_home "$r" .mutate-x.sh "$good"
run_block "$r/home" "$r/repo"
hasnt 'probe-x'
hasnt 'mutate-x'
counts 'FAIL|' 0

CASE='20 un archivo que no es .sh se ignora'
r="$(sandbox)"; printf 'hola\n' > "$r/home/.claude/hooks/tests/README.md"
run_block "$r/home" "$r/repo"
counts 'FAIL|' 0

CASE='21 un DIRECTORIO llamado x.sh en la máquina se reporta, no rompe'
r="$(sandbox)"; mkdir -p "$r/home/.claude/hooks/tests/raro.sh"
run_block "$r/home" "$r/repo"
has 'FAIL|suite raro.sh existe en la máquina y NO está versionada'
rc_is 0

CASE='22 las dos direcciones a la vez'
r="$(sandbox)"; put_repo "$r" a-tests.sh "$good"; put_home "$r" b-tests.sh "$good"; plug "$r" a-tests.sh
run_block "$r/home" "$r/repo"
has 'FAIL|suite a-tests.sh ausente'
has 'FAIL|suite b-tests.sh existe en la máquina y NO está versionada'

# =========================================================================
# E — robustez
# =========================================================================
CASE='23 el repo no tiene directorio tests/'
r="$(sandbox)"; rm -rf "$r/repo/files/claude/hooks/tests"
run_block "$r/home" "$r/repo"
counts 'FAIL|' 0
counts 'PASS|' 0
rc_is 0

CASE='24 tests/ del repo vacío: sin nullglob el patrón literal no se procesa'
r="$(sandbox)"
run_block "$r/home" "$r/repo"
hasnt '*.sh'
counts 'FAIL|' 0
rc_is 0

CASE='25 tests/ de la máquina vacío y repo vacío'
r="$(sandbox)"
run_block "$r/home" "$r/repo"
counts 'PASS|' 0
counts 'FAIL|' 0

CASE='26 nombre de suite con espacios'
r="$(sandbox)"; put_repo "$r" 'con espacio-tests.sh' "$good"; put_home "$r" 'con espacio-tests.sh' 'otro'
run_block "$r/home" "$r/repo"
has 'FAIL|suite con espacio-tests.sh divergente'

CASE='27 $HOME con espacios'
r="$(sandbox)"; mkdir -p "$r/ho me/.claude/hooks/tests"
put_repo "$r" a-tests.sh "$good"; printf '%s\n' "$good" > "$r/ho me/.claude/hooks/tests/a-tests.sh"; plug "$r" a-tests.sh
run_block "$r/ho me" "$r/repo"
has 'PASS|suite a-tests.sh instalada e idéntica al source'
counts 'FAIL|' 0

CASE='28 cuenta exacta: 5 suites sanas → 2 PASS por suite, 0 FAIL'
r="$(sandbox)"
for n in a b c d e; do put_repo "$r" "$n-tests.sh" "$good"; put_home "$r" "$n-tests.sh" "$good"; plug "$r" "$n-tests.sh"; done
run_block "$r/home" "$r/repo"
counts 'PASS|' 10
counts 'FAIL|' 0
rc_is 0

CASE='29 el enchufe es TEXTO literal: un nombre con metacaracteres de regex'
# Sin `grep -F`, un `[` en el nombre convierte el patrón en una clase de
# caracteres sin cerrar: grep sale con error, no matchea, y una suite SÍ
# enchufada se reporta como huérfana. (Mutante M10.)
r="$(sandbox)"; put_repo "$r" 'a[b-tests.sh' "$good"; put_home "$r" 'a[b-tests.sh' "$good"; plug "$r" 'a[b-tests.sh'
affirm "$r/repo/files/claude/hooks/tests/a[b-tests.sh"
run_block "$r/home" "$r/repo"
has 'PASS|suite a[b-tests.sh enchufada'
hasnt 'versionada pero ningún check'

# =========================================================================
printf '\n  %s: %d PASS / %d FAIL\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
