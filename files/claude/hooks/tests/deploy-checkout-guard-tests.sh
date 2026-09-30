#!/usr/bin/env bash
# Suite de contrato de deploy-checkout-guard.sh — el incidente del 2026-08-31
# hecho estructura verificable.
#
# Por qué este guard importa: `firebase deploy` REEMPLAZA la config completa.
# Un deploy desde un checkout que no tiene el fieldOverride de otra rama no
# "falla": BORRA silenciosamente una exemption que estaba building, y hay que
# detectarlo por REST. Igual que force-push-guard, falla MUDO.
#
# NOTA DE MÉTODO — este guard no se puede probar con payloads solos: decide
# leyendo el ESTADO DE GIT del repo que resuelve desde el cwd del comando.
# Cada caso corre contra un repo sintético con su propio origin local, armado
# en un tmpdir y borrado al salir. La máquina real NUNCA se toca.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/deploy-checkout-guard-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/deploy-checkout-guard.sh}"
fails=0
total=0

# 0) Precondiciones duras. Un PreToolUse(Bash) con error de sintaxis no falla
#    abierto: bloquea TODOS los Bash de la sesión, incluidos los que lo reparan.
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — la política de deploy NO está activa." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis — bloquea TODOS los Bash de la sesión." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v jq  >/dev/null 2>&1 || { echo "FATAL: falta jq; los payloads no se pueden armar." >&2; exit 3; }
command -v git >/dev/null 2>&1 || { echo "FATAL: falta git; los fixtures no se pueden armar." >&2; exit 3; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dcg-tests.XXXXXX")" || exit 3
cleanup(){ [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# git silencioso y reproducible: sin hooks del usuario, sin firma, sin
# templates. Un fixture que hereda la config global no prueba el hook, prueba
# la máquina.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

g(){ git -C "$1" "${@:2}" >/dev/null 2>&1; }

# Fixture base: un repo `w` con rama dev pusheada a un origin local `up.git`.
# Los tres archivos de config existen y están commiteados.
mkrepo(){ # $1 = nombre → imprime la ruta del working tree
  local n="$1" root="$TMP/$1"
  mkdir -p "$root"
  git init --bare -q "$root/up.git"
  git init -q -b dev "$root/w"
  printf '{"indexes":[]}\n'  > "$root/w/firestore.indexes.json"
  printf 'rules_version="2";\n' > "$root/w/firestore.rules"
  printf '{"firestore":{}}\n' > "$root/w/firebase.json"
  mkdir -p "$root/w/src"; printf 'export const a=1\n' > "$root/w/src/a.ts"
  g "$root/w" add -A
  g "$root/w" commit -m base
  g "$root/w" remote add origin "$root/up.git"
  g "$root/w" push -u origin dev
  printf '%s' "$root/w"
}

b(){ jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

check() { # nombre payload exit_esperado [cwd]
  local rc cwd="${4:-$TMP}"
  ( cd "$cwd" 2>/dev/null && printf '%s' "$2" | bash "$HOOK" ) >/dev/null 2>&1
  rc=$?
  total=$((total+1))
  if [ "$rc" != "$3" ]; then
    fails=$((fails+1))
    echo "FALLA: $1 (exit=$rc esperado=$3)" >&2
  fi
}

# ── Fixtures ────────────────────────────────────────────────────────────────
# A) SINCRONIZADO: HEAD == origin/dev, working tree limpio. El caso feliz.
A="$(mkrepo sync)"

# B) DIRTY: la config de Firebase tiene cambios sin commitear. Este es
#    literalmente el incidente: el deploy publica el ESTADO DEL ARCHIVO.
B="$(mkrepo dirty)"
printf '{"indexes":[{"x":1}]}\n' > "$B/firestore.indexes.json"

# C) APARTE/ATRASADO: dev avanzó con config nueva; mi HEAD es una rama lateral
#    que NO la contiene. Deployar desde acá PISA la config de dev.
C="$(mkrepo behind)"
g "$C" checkout -b side
printf 'export const a=2\n' > "$C/src/a.ts"; g "$C" add -A; g "$C" commit -m side
# dev avanza en el remoto, por fuera de mi HEAD.
# El `checkout -B dev origin/dev` NO es decorativo: el bare de `git init` deja
# HEAD en una rama que no existe, así que un clon queda sin rama checkouteada y
# el push falla con "src refspec dev does not match any". La primera versión de
# esta suite lo tenía silenciado y el caso de la regla 2 daba ROJO por fixture
# roto, no por agujero del hook. De ahí el bloque de validación de abajo.
CU="$TMP/behind/up.git"; CO="$TMP/behind/other"
git clone -q "$CU" "$CO" >/dev/null 2>&1
g "$CO" checkout -B dev origin/dev
printf '{"indexes":[{"otro":true}]}\n' > "$CO/firestore.indexes.json"
g "$CO" add -A; g "$CO" commit -m "dev avanza"; g "$CO" push origin dev
g "$C" fetch origin dev

# D) ADELANTADO: mi HEAD contiene todo dev y además tiene el override nuevo
#    commiteado. Permitido explícitamente por la cabecera del hook.
D="$(mkrepo ahead)"
printf '{"indexes":[{"nuevo":true}]}\n' > "$D/firestore.indexes.json"
g "$D" add -A; g "$D" commit -m "override nuevo"

# E) DIRTY PERO FUERA DE LA CONFIG: código sucio no es asunto de este guard.
E="$(mkrepo dirtysrc)"
printf 'export const a=99\n' > "$E/src/a.ts"

# F) SIN ORIGIN: el fetch falla → fail-open declarado (línea 53).
F="$(mkrepo noremote)"
g "$F" remote remove origin

# G) NO ES UN REPO: deploys ad-hoc fuera de git no se bloquean (línea 43).
G="$TMP/norepo"; mkdir -p "$G"

# H) RUTA CON ESPACIOS: copia sucia de B, para fijar el límite conocido.
H="$TMP/con espacio"; mkdir -p "$H"; cp -R "$B/." "$H/" 2>/dev/null

# ── Validación de fixtures ──────────────────────────────────────────────────
# Un fixture que no representa lo que su nombre dice produce un resultado
# CIERTO POR LA RAZÓN EQUIVOCADA — el equivalente al mutante vacío que devuelve
# 0 y hace creer que la suite lo detectó. Cada escenario se afirma antes de
# medir nada; si uno no se cumple, es FATAL, no una falla de caso.
fx=0
fxassert(){ # descripción condición_rc
  [ "$2" = 0 ] || { echo "FATAL(fixture): $1" >&2; fx=1; }
}
[ -n "$(git -C "$B" status --porcelain -- firestore.indexes.json)" ]; fxassert "B deberia tener la config sucia" $?
[ -z "$(git -C "$A" status --porcelain -- firestore.indexes.json firestore.rules firebase.json)" ]; fxassert "A deberia estar limpio" $?
git -C "$A" merge-base --is-ancestor origin/dev HEAD; fxassert "A deberia contener origin/dev" $?
git -C "$C" diff --quiet HEAD origin/dev -- firestore.indexes.json; [ $? -ne 0 ]; fxassert "C deberia diferir de origin/dev en la config" $?
git -C "$C" merge-base --is-ancestor origin/dev HEAD; [ $? -ne 0 ]; fxassert "C NO deberia contener origin/dev" $?
git -C "$D" merge-base --is-ancestor origin/dev HEAD; fxassert "D deberia contener origin/dev (adelantado)" $?
git -C "$D" diff --quiet HEAD origin/dev -- firestore.indexes.json; [ $? -ne 0 ]; fxassert "D deberia diferir de origin/dev en la config" $?
[ -z "$(git -C "$E" status --porcelain -- firestore.indexes.json firestore.rules firebase.json)" ]; fxassert "E deberia tener sucio SOLO el codigo" $?
[ -z "$(git -C "$F" remote)" ]; fxassert "F no deberia tener remotes" $?
[ "$fx" = 0 ] || { echo "FATAL: los fixtures no representan sus escenarios; ningun resultado seria creible." >&2; exit 3; }

# ── Regla 1: config sucia bloquea, en todas las formas de invocar un deploy ──
check "dirty + firebase deploy"          "$(b "cd $B && firebase deploy --only firestore:indexes")" 2
check "dirty + npm indexes:deploy:test"  "$(b "cd $B && npm run indexes:deploy:test")" 2
check "dirty + npm rules:deploy:prod"    "$(b "cd $B && npm run rules:deploy:prod")" 2
check "dirty + pnpm indexes:deploy"      "$(b "cd $B && pnpm indexes:deploy:staging")" 2
check "dirty + firebase deploy 2 espacios" "$(b "cd $B && firebase  deploy")" 2
check "dirty + git -C como resolutor"    "$(b "git -C $B status && firebase deploy")" 2
check "dirty + deploy sin cd (usa PWD)"  "$(b 'firebase deploy --only firestore:rules')" 2 "$B"

# ── Regla 2: el HEAD tiene que CONTENER el estado de origin/dev ──────────────
check "rama aparte que no contiene dev"  "$(b "cd $C && firebase deploy --only firestore:indexes")" 2
check "adelantado a dev: PERMITIDO"      "$(b "cd $D && firebase deploy --only firestore:indexes")" 0
check "sincronizado y limpio: PERMITIDO" "$(b "cd $A && firebase deploy --only firestore:indexes")" 0

# ── Vías legítimas: un guard que estorba se desactiva a la semana ────────────
check "src sucio no es config"           "$(b "cd $E && firebase deploy --only firestore:indexes")" 0
check "sin remote origin: fail-open"     "$(b "cd $F && firebase deploy")" 0
check "fuera de un repo git: fail-open"  "$(b "cd $G && firebase deploy")" 0
check "deploy que no es de firebase"     "$(b "cd $B && npm run deploy:docs")" 0
check "emuladores no son un deploy"      "$(b "cd $B && firebase emulators:start")" 0
check "comando sin la palabra deploy"    "$(b "cd $B && git status")" 0

# ── Autoría vs ejecución: el texto citado NO es un deploy (línea 28-32) ──────
check "indexes:deploy en comillas dobles" "$(b "cd $B && gh pr comment 1 --body \"corré indexes:deploy:test\"")" 0
check "firebase deploy en comillas simples" "$(b "cd $B && echo 'primero firebase deploy y despues'")" 0

# ── Resolución del directorio: el ÚLTIMO cd, no el primero (línea 35-39) ─────
# Bug propio del 2026-08-31: evaluaba el checkout base stale aunque el deploy
# salía de un worktree fresco.
check "ultimo cd manda (limpio despues de sucio)" "$(b "cd $B && cd $A && firebase deploy")" 0
check "ultimo cd manda (sucio despues de limpio)" "$(b "cd $A && cd $B && firebase deploy")" 2
check "~ se expande a HOME"              "$(b 'cd ~ && firebase deploy')" 0
check "cd a directorio inexistente cae a PWD" "$(b "cd $TMP/no-existe && firebase deploy")" 2 "$B"

# ── AGUJEROS VERIFICADOS el 2026-09-07 al escribir esta suite ───────────────
# Los tres daban rc=0 (pasar) contra el hook de entonces. Ninguno apareció
# LEYENDO el hook: aparecieron al enumerar lo que la cabecera PROMETE
# ("antes de `firebase deploy`", "el ÚLTIMO cd ANTES del deploy") y medir.
#
#   a) un flag entre `firebase` y `deploy` esquivaba el pre-filtro entero.
#      `firebase --project cocoa-test deploy` es la forma que documenta
#      Firebase, no un caso de laboratorio.
#   b) `firebase-tools deploy` (invocación por npx) tampoco matcheaba.
#   c) el ÚLTIMO cd se buscaba en TODO el comando, no en el prefijo anterior al
#      deploy: un `cd` a un checkout limpio DESPUÉS del deploy hacía que el
#      guard evaluara el repo equivocado. Es el mismo bug que ya se había
#      arreglado el 2026-08-31 en la otra dirección (tomaba el primero).
check "AGUJERO a: --project entre firebase y deploy" \
  "$(b "cd $B && firebase --project cocoa-test deploy --only firestore:indexes")" 2
check "AGUJERO a: --config entre medio"  "$(b "cd $B && firebase --config fb.json deploy")" 2
check "AGUJERO b: npx firebase-tools deploy" "$(b "cd $B && npx firebase-tools deploy --only firestore:rules")" 2
check "AGUJERO c: cd limpio DESPUES del deploy" \
  "$(b "cd $B && firebase deploy --only firestore:indexes && cd $A")" 2

# No-regresión de formas que YA estaban cubiertas (medidas, no supuestas):
check "separador ; en vez de &&"         "$(b "cd $B ; firebase deploy")" 2
check "yarn indexes:deploy"              "$(b "cd $B && yarn indexes:deploy:test")" 2
check "sustitucion de comando en el flag" "$(b "cd $B && firebase deploy --project \$(cat .p)")" 2

# La frontera del agujero (a): ensanchar el pre-filtro NO puede empezar a
# bloquear cualquier comando que mencione firebase y deploy en distintos
# tramos. El corte en ; & | es lo que lo sostiene.
check "firebase use + deploy de docs no es deploy" "$(b "cd $B && firebase use test && npm run deploy:docs")" 0
check "build de firebase + deploy ajeno"           "$(b "cd $B && npm run build:firebase && npm run deploy:docs")" 0

# ── LÍMITES CONOCIDOS Y ACEPTADOS (medidos el 2026-09-07) ───────────────────
# Los dos dejan PASAR un deploy real. Se documentan en vez de taparse, y la
# suite los fija para que el día que alguien los tape sea una DECISIÓN y no un
# accidente silencioso.
#
# 1) El comando real dentro de comillas se descarta: es exactamente la misma
#    regla que evita bloquear un `gh pr comment --body "corré indexes:deploy"`.
#    Acotarla (perdonar sólo tras bash -c/ssh) agregaría falsos positivos a un
#    guard que YA elige estorbar. El incidente real fue un `npm run
#    indexes:deploy:test` directo, no un deploy citado.
check "LIMITE: deploy real dentro de bash -c" "$(b "cd $B && bash -c 'firebase deploy'")" 0
check "LIMITE: deploy real por ssh"           "$(b "ssh host \"cd $B && firebase deploy\"")" 0
# 2) Una ruta con espacios rompe la resolución del repo (el patrón corta en el
#    espacio y las comillas ya se descartaron). Cae a $PWD, y si $PWD no es un
#    repo, sale por el fail-open de la línea 43. Ningún checkout de deploy vive
#    en una ruta con espacios; taparlo cuesta más de lo que rinde.
check "LIMITE: ruta con espacios cae a PWD"   "$(b "cd '$TMP/con espacio' && firebase deploy")" 0 "$G"

# ── Fail-open ante input no parseable (contrato explícito, línea 18) ─────────
check "input vacio"                      '' 0
check "input no-JSON con la palabra deploy" 'basura deploy adentro' 0
check "JSON sin command"                 '{"tool_name":"Bash","tool_input":{}}' 0
check "tool que no es Bash"              '{"tool_name":"Write","tool_input":{"file_path":"/r/a.ts"}}' 0

if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails/$total casos fallan — la política de deploy tiene agujeros." >&2
  exit 1
fi
echo "OK: $total/$total casos del contrato de deploy pasan."
exit 0
