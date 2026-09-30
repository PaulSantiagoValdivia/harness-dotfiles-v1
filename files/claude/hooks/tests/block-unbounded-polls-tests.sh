#!/usr/bin/env bash
# Suite de contrato de block-unbounded-polls.sh — el guard anti-polling.
#
# Es el hook cuya falla muda se paga en CUOTA: cuando deja pasar de más no se
# rompe nada visible, simplemente un loop gira 92 minutos esperando un CI que
# ya terminó (incidente 2026-08-25) y el turno se come el contexto. Nadie ve
# que el guard no bloqueó; se ve la factura. Un guard sin suite es una promesa.
#
# NOTA DE MÉTODO — por qué los payloads viven EN este archivo: el guard
# inspecciona `tool_input.command` del Bash que lo invoca. Cualquier sondeo
# escrito en la línea de comando (`bash -c 'until ...; do sleep 10; done'`) se
# bloquea a sí mismo antes de correr. Los casos tienen que estar en un archivo
# que se ejecuta; la línea de comando sólo lo nombra.
#
# Las expectativas NO se dedujeron leyendo el hook: cada caso sospechoso se
# SONDEÓ contra el hook vivo antes de fijarse. De 20 sospechosos medidos, 5
# eran agujeros, 2 falsos positivos, 4 límites y el resto ya estaba cubierto.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/block-unbounded-polls-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/block-unbounded-polls.sh}"
fails=0
total=0

# 0) Precondiciones duras. Un PreToolUse(Bash) con error de sintaxis no falla
#    abierto: bloquea TODOS los Bash de la sesión, incluidos los que lo reparan.
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — la política anti-polling NO está activa." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis — bloquea TODOS los Bash de la sesión." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v jq >/dev/null 2>&1 || { echo "FATAL: falta jq; los payloads no se pueden armar." >&2; exit 3; }

# jq arma el JSON: escapa comillas, pipes, `$` y saltos de línea de verdad.
# (Lección de route-hook-tests: con sed se generaba JSON inválido y el hook,
# fail-open, devolvía 0 — falso VERDE en un test que creíamos rojo-capaz.)
b(){ jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

check() { # nombre payload exit_esperado
  local rc
  printf '%s' "$2" | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  total=$((total+1))
  if [ "$rc" != "$3" ]; then
    fails=$((fails+1))
    echo "FALLA: $1 (exit=$rc esperado=$3)" >&2
  fi
}

# ── Regla 3: `sleep N` a secas con N >= 300 es tiempo muerto sin chequear nada ──
check "sleep 300 (borde exacto)"        "$(b 'sleep 300')" 2
check "sleep 299 (justo abajo)"         "$(b 'sleep 299')" 0
check "sleep 600"                       "$(b 'sleep 600')" 2
check "sleep 2 (normal)"                "$(b 'sleep 2')" 0
# AGUJERO A1 (medido 2026-09-07, daba rc=0): el umbral leía sólo el número y
# tiraba la UNIDAD. `sleep 30m` son 1800s de turno muerto — la sintaxis más
# natural justo para las esperas largas que la regla existe para impedir.
check "A1 sleep 5m (=300s exacto)"      "$(b 'sleep 5m')" 2
check "A1 sleep 4m (=240s, NO debe)"    "$(b 'sleep 4m')" 0
check "A1 sleep 30m"                    "$(b 'sleep 30m')" 2
check "A1 sleep 1h"                     "$(b 'sleep 1h')" 2
check "A1 sleep 1d"                     "$(b 'sleep 1d')" 2
check "A1 sleep 10s (sufijo, normal)"   "$(b 'sleep 10s')" 0
# La regla 3 gana sobre el techo de iteraciones: un loop acotado que duerme
# 600s por vuelta sigue siendo tiempo muerto.
check "loop acotado PERO sleep 600"     "$(b 'i=0; until gh pr checks 1 || [ $i -ge 5 ]; do sleep 600; i=$((i+1)); done')" 2

# ── Regla 2: watchers de gh sin techo ──
check "gh run watch"                    "$(b 'gh run watch 123')" 2
check "gh pr checks --watch"            "$(b 'gh pr checks 1 --watch')" 2
# AGUJERO A2 (medido, daba rc=0): el pre-filtro exigía ADYACENCIA `gh +run
# +watch`, así que un flag entre el binario y el subcomando esquivaba el guard
# entero. `--repo` es justo lo que usás cuando el cwd no es el repo. Es la
# MISMA clase que `firebase --project X deploy` en deploy-checkout-guard
# (2026-09-07): la variante documentada del comando era la ciega.
check "A2 gh --repo o/r run watch"      "$(b 'gh --repo owner/r run watch 123')" 2
check "A2 gh run --repo o/r watch"      "$(b 'gh run --repo owner/r watch 123')" 2
check "A2 gh --repo o/r pr checks --watch" "$(b 'gh --repo owner/r pr checks 1 --watch')" 2
# Envuelto en techo: pasa.
check "timeout 300 gh run watch"        "$(b 'timeout 300 gh run watch 123')" 0
check "gtimeout 300 gh run watch"       "$(b 'gtimeout 300 gh run watch 123')" 0
# La vía correcta — el chequeo DIRECTO — nunca se estorba:
check "gh run view --json status"       "$(b 'gh run view 123 --json status,conclusion')" 0
check "gh pr checks sin --watch"        "$(b 'gh pr checks 1')" 0
check "gh api de watchers"              "$(b 'gh api /repos/o/r/subscribers --jq ".[].login"')" 0

# ── Regla 1: loop until/while + sleep sin techo de iteraciones ──
check "until + sleep sin techo"         "$(b 'until gh pr checks 1 | grep -q pass; do sleep 10; done')" 2
check "while + sleep sin techo"         "$(b 'while ! gh pr checks 1; do sleep 30; done')" 2
check "loop multilinea"                 "$(b "$(printf 'until gh pr checks 1\ndo\n  sleep 10\ndone')")" 2
# Escapes VÁLIDOS: un guard que bloquea el trabajo acotado se desactiva a la
# semana, y entonces no protege nada.
check "contador -ge en la condicion"    "$(b 'i=0; until gh pr checks 1 || [ $i -ge 30 ]; do sleep 10; i=$((i+1)); done')" 0
check "contador -lt en la condicion"    "$(b 'i=0; while [ $i -lt 20 ]; do gh pr checks 1 && break; sleep 5; i=$((i+1)); done')" 0
# AGUJERO A5 (medido, daba rc=0) — el más grave: el anclaje de la regla 1 no
# incluía la comilla de apertura, así que un loop DENTRO de comillas —forma
# perfectamente ejecutable y la que usás cuando el loop es largo— esquivaba el
# guard entero. El guard quedaba al revés de lo útil: bloqueaba el TEXTO que
# menciona un loop (ver L3) y dejaba correr el loop REAL. Es además la razón
# por la que el escape por `timeout` era código MUERTO: la regla 1 nunca
# llegaba a consultarlo, porque no matcheaba de entrada.
check "A5 bash -c con until+sleep sin techo" "$(b "bash -c 'until gh pr checks 1; do sleep 10; done'")" 2
check "A5 bash -c con while+sleep sin techo" "$(b 'bash -c "while ! gh pr checks 1; do sleep 30; done"')" 2
check "A5 ssh host con until+sleep"          "$(b "ssh host 'until curl -sf x; do sleep 20; done'")" 2
check "A5 sleep 600 dentro de comillas"      "$(b "bash -c 'sleep 600'")" 2
check "timeout envolviendo el loop"     "$(b "timeout 300 bash -c 'until gh pr checks 1; do sleep 10; done'")" 0
# FALSO POSITIVO F1 (medido, daba rc=2): el escape sólo entendía `-lt/-ge`, así
# que la aritmética de bash —un techo REAL— se bloqueaba.
check "F1 (( i < 30 )) en la condicion" "$(b 'i=0; while (( i < 30 )); do gh pr checks 1 && break; sleep 10; ((i++)); done')" 0
check "F1 (( i++ < 30 )) con break"     "$(b 'i=0; while gh pr checks 1; do sleep 10; (( i++ < 30 )) || break; done')" 0
# AGUJEROS A3/A4 (medidos, daban rc=0): los DOS escapes se buscaban en TODO el
# comando aplanado en vez del ÁMBITO que les corresponde. Es el mismo bug de
# ámbito que el `cd` posterior al deploy (2026-09-07), en dos variantes:
#   A3 — un `-lt` en el CUERPO, sin `break`, no es techo de nada.
#   A4 — la palabra `timeout` en un texto cualquiera no envuelve nada.
check "A3 -lt en el cuerpo, sin break"  "$(b 'until gh pr checks 1; do if [ $j -lt 5 ]; then echo x; fi; sleep 10; done')" 2
check "A4 timeout mencionado en un echo" "$(b 'echo "usa timeout 30"; until gh pr checks 1; do sleep 10; done')" 2
check "A4 timeout en un echo + gh watch" "$(b 'echo "usa timeout 30"; gh run watch 123')" 2

# ── Heredocs: el comando que ESCRIBE un loop no lo EJECUTA ──
# (falso positivo cazado el 2026-08-30: bloqueó 3 veces la autoría de un script)
check "heredoc que solo escribe un loop" "$(b "$(printf 'cat > s.sh <<EOF\nuntil x; do sleep 10; done\nEOF')")" 0
check "heredoc con comillas <<'EOF'"     "$(b "$(printf 'cat > s.sh <<%sEOF%s\nuntil x; do sleep 10; done\nEOF' "'" "'")")" 0
check "python3 - <<PY con sleep"         "$(b "$(printf 'python3 - <<%sPY%s\nimport time\nwhile True:\n    time.sleep(10)\nPY' "'" "'")")" 0
check "heredoc + loop REAL despues"      "$(b "$(printf 'cat > s.sh <<EOF\nhola\nEOF\nuntil gh pr checks 1; do sleep 10; done')")" 2
# FALSO POSITIVO F2 (medido, daba rc=2): `<<- EOF` con espacio es sintaxis
# VÁLIDA de bash y el stripping no la reconocía, así que el cuerpo del heredoc
# se escaneaba como si fuera código a ejecutar.
check "F2 heredoc <<- EOF con espacio"   "$(b "$(printf 'cat > s.sh <<- EOF\nuntil x; do sleep 10; done\n\tEOF')")" 0
check "F2 heredoc <<-EOF pegado"         "$(b "$(printf 'cat > s.sh <<-EOF\nuntil x; do sleep 10; done\n\tEOF')")" 0

# ── LÍMITES ABIERTOS A PROPÓSITO ─────────────────────────────────────────────
# Fijados como casos para que taparlos sea una DECISIÓN, no un accidente.
#
# L1. `watch(1)` de coreutils es polling puro sin techo, pero la cabecera del
#     hook sólo promete los watchers de gh. Ampliar el contrato a `watch -n` es
#     una decisión de producto, no un arreglo de este guard.
check "L1 watch(1) -n 5 (fuera del contrato)" "$(b 'watch -n 5 gh pr checks 1')" 0
# L2. `for` sobre un rango es acotado POR DEFINICIÓN aunque el total sea largo;
#     la regla 1 habla de until/while a propósito.
check "L2 for acotado + sleep"          "$(b 'for i in $(seq 1 1000); do sleep 10; done')" 0
# L3. El texto dentro de comillas se toma literal — MISMA regla que salva a
#     `gh pr comment --body "..."` en los otros guards. Acotarla exige parsear
#     bash de verdad y agrega falsos negativos a un guard que ya elige estorbar.
check "L3 echo que menciona gh run watch" "$(b 'echo "no uses gh run watch, usa gh run view"')" 2
check "L3 comentario con sleep 600"     "$(b '# sleep 600')" 2
# L4. Fracciones en el sufijo (`sleep 0.5h`) no se interpretan: el umbral
#     trabaja con enteros. Es tiempo muerto que pasa, y está medido.
check "L4 sleep 0.5h (fraccion)"        "$(b 'sleep 0.5h')" 0
# L5. Un heredoc sin terminador se come el resto del comando — pero ese comando
#     es sintácticamente inválido y bash no lo ejecutaría igual.
check "L5 heredoc sin cerrar"           "$(b "$(printf 'cat > s.sh <<EOF\nhola\nuntil gh pr checks 1; do sleep 10; done')")" 0

# ── Fail-open ante input no parseable (contrato explícito del hook) ──
check "input vacio"                     '' 0
check "input no-JSON"                   'basura con la palabra sleep adentro' 0
check "JSON sin command"                '{"tool_name":"Bash","tool_input":{}}' 0
check "tool que no es Bash"             '{"tool_name":"Write","tool_input":{"file_path":"/r/a.ts"}}' 0
check "comando sin sleep ni watch"      "$(b 'git status')" 0
check "comando inocente"                "$(b 'npm test')" 0

if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails/$total casos fallan — la política anti-polling tiene agujeros." >&2
  exit 1
fi
echo "OK: $total/$total casos del contrato anti-polling pasan."
exit 0
