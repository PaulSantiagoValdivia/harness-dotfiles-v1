#!/usr/bin/env bash
# Suite de contrato de engram-git-sync.sh.
#
# Por qué ESTE hook: de los hooks del harness es el ÚNICO que muta estado FUERA
# de esta máquina — hace `git push` al remoto de CADA repo donde abrís sesión —
# y el único que corre comandos destructivos (`git clean -fdx`, `git rm -r
# --cached`). Y está diseñado para fallar MUDO: cada error es una línea de log y
# `exit 0`. Un guard que falla mudo deja pasar de más; un ESCRITOR que falla
# mudo deja de compartir la memoria entre máquinas y nadie se entera nunca.
#
# NOTA DE MÉTODO — esto no se prueba con payloads: el hook no lee stdin, ACTÚA.
# Cada caso corre contra un HOME sintético (así ~/.engram-git y ~/.engram caen
# en el tmpdir), remotos `git` locales bare, y un `engram` de mentira en el PATH
# que registra sus invocaciones. La máquina real, los repos reales y los remotos
# reales NUNCA se tocan.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/engram-git-sync-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/engram-git-sync.sh}"
fails=0
total=0

# ── 0) Precondiciones duras ─────────────────────────────────────────────────
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — la memoria no se comparte entre máquinas." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v git >/dev/null 2>&1 || { echo "FATAL: falta git; los fixtures no se pueden armar." >&2; exit 3; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/egs-tests.XXXXXX")" || exit 3
cleanup(){ [ -n "${TMP:-}" ] && rm -rf "$TMP"; }
trap cleanup EXIT

# git hermético: sin config global, sin hooks del usuario, sin firma. Un fixture
# que hereda la config de la máquina no prueba el hook, prueba la máquina.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_TERMINAL_PROMPT=0
g(){ git -C "$1" "${@:2}" >/dev/null 2>&1; }

# ── `engram` de mentira ─────────────────────────────────────────────────────
# Determinista A PROPÓSITO: el mismo proyecto exporta siempre el mismo byte, así
# el segundo push del contrato ("commit solo si cambió algo") se puede medir.
# ENGRAM_BUMP fuerza contenido nuevo; ENGRAM_RC_* fuerzan un fallo del binario.
STUB="$TMP/bin"; mkdir -p "$STUB"
cat > "$STUB/engram" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${ENGRAM_CALLS:-/dev/null}"
proj=""; import=0; prev=""
for a in "$@"; do
  [ "$a" = "--import" ] && import=1
  [ "$prev" = "--project" ] && proj="$a"
  prev="$a"
done
if [ "$import" = 1 ]; then
  ls .engram 2>/dev/null >> "${ENGRAM_IMPORTED:-/dev/null}"
  exit "${ENGRAM_RC_IMPORT:-0}"
fi
if [ -n "$proj" ]; then
  # ENGRAM_NADA: el proyecto no tiene memoria nueva que exportar. Es el caso que
  # separa "la rama se crea vacia en el primer push" de "la rama aparecio de
  # rebote porque habia algo que subir".
  if [ -z "${ENGRAM_NADA:-}" ]; then
    mkdir -p .engram
    printf 'memoria de %s%s\n' "$proj" "${ENGRAM_BUMP:-}" > ".engram/$proj.jsonl"
  fi
  exit "${ENGRAM_RC_EXPORT:-0}"
fi
exit 0
EOS
chmod +x "$STUB/engram"

# ── Fixtures ────────────────────────────────────────────────────────────────
# mkremote <ruta-relativa> → imprime la ruta del bare, sembrado con `main` y un
# archivo de código (para poder afirmar que la rama huérfana NO lleva código).
mkremote(){
  local up="$TMP/remotes/$1.git" seed="$TMP/seeds/$(echo "$1" | tr / -)"
  mkdir -p "$(dirname "$up")" "$(dirname "$seed")"
  git init --bare -q "$up"
  # Sin esto el bare queda con HEAD en una rama inexistente y los clones salen
  # raros: el fixture fallaría por sí mismo y el resultado no sería creíble.
  git -C "$up" symbolic-ref HEAD refs/heads/main
  git init -q -b main "$seed"
  printf 'export const codigo = 1\n' > "$seed/codigo.ts"
  g "$seed" add -A; g "$seed" commit -m base
  g "$seed" remote add origin "$up"; g "$seed" push -u origin main
  printf '%s' "$up"
}
# mksrc <nombre> <bare> → clon del repo "del usuario", que es donde corre la sesión
mksrc(){ local w="$TMP/src/$1"; mkdir -p "$TMP/src"; git clone -q "$2" "$w" 2>/dev/null; printf '%s' "$w"; }
# newhome <nombre> [sin-engram] → HOME sintético; sin el 2º arg crea ~/.engram
newhome(){ local h="$TMP/homes/$1"; mkdir -p "$h"; [ "${2:-}" = "sin-engram" ] || mkdir -p "$h/.engram"; printf '%s' "$h"; }

# run <home> <cwd> <modo> → deja el exit en $RC, stderr en $home/err.
# RUNENV lleva variables extra; RUNPATH reemplaza el PATH (para "engram no instalado").
RC=0
run(){
  local home="$1" cwd="$2" mode="${3-}"
  ( cd "$cwd" 2>/dev/null && env HOME="$home" \
      ENGRAM_CALLS="$home/calls" ENGRAM_IMPORTED="$home/imported" \
      PATH="${RUNPATH:-$STUB:$PATH}" ${RUNENV:-} \
      bash "$HOOK" $mode ) >"$home/out" 2>"$home/err"
  RC=$?
}
LOGOF(){ cat "$1/.engram/git-sync.log" 2>/dev/null; }
CALLS(){ cat "$1/calls" 2>/dev/null; }
has_branch(){ git -C "$1" show-ref --verify --quiet "refs/heads/$2"; }

T(){ # descripción rc_de_la_condición
  total=$((total+1))
  [ "$2" = 0 ] || { fails=$((fails+1)); echo "FALLA: $1" >&2; }
}

# ── Validación de los fixtures ──────────────────────────────────────────────
# Un fixture que no representa lo que su nombre dice da un resultado CIERTO POR
# LA RAZÓN EQUIVOCADA. Se afirma antes de medir nada; si falla, es FATAL.
fx=0
fxassert(){ [ "$2" = 0 ] || { echo "FATAL(fixture): $1" >&2; fx=1; }; }
FX_UP="$(mkremote fixture/demo)"; FX_SRC="$(mksrc fixture "$FX_UP")"
has_branch "$FX_UP" main; fxassert "el bare deberia tener main" $?
[ -f "$FX_SRC/codigo.ts" ]; fxassert "el clon deberia traer el codigo" $?
[ "$(git -C "$FX_SRC" remote get-url origin)" = "$FX_UP" ]; fxassert "el clon deberia apuntar al bare" $?
( PATH="$STUB:$PATH"; cd "$TMP" && ENGRAM_CALLS=/dev/null engram sync --project zz >/dev/null 2>&1 && [ -f "$TMP/.engram/zz.jsonl" ] ); fxassert "el stub de engram deberia exportar" $?
rm -rf "$TMP/.engram"
[ "$fx" = 0 ] || { echo "FATAL: los fixtures no representan sus escenarios." >&2; exit 3; }

echo "# --- Contrato de engram-git-sync ---" >&2

# ════════════════════════════════════════════════════════════════════════════
# C1) MODO PULL: "trae la rama engram-sync del repo actual e importa"
# ════════════════════════════════════════════════════════════════════════════
UP1="$(mkremote c1/repo1)"; SRC1="$(mksrc c1 "$UP1")"; H1="$(newhome c1)"
# Otra máquina ya publicó memoria en la rama.
OTRA="$TMP/otra1"; git clone -q "$UP1" "$OTRA" 2>/dev/null
g "$OTRA" checkout -q --orphan engram-sync; g "$OTRA" rm -rfq --cached .; rm -f "$OTRA/codigo.ts"
mkdir -p "$OTRA/.engram"; printf 'memoria ajena\n' > "$OTRA/.engram/ajena.jsonl"
g "$OTRA" add -A; g "$OTRA" commit -m "memoria de otra maquina"; g "$OTRA" push -u origin engram-sync

run "$H1" "$SRC1" pull
[ "$RC" = 0 ]; T "C1 pull: exit 0" $?
[ -d "$H1/.engram-git/repo1/.git" ]; T "C1 pull: crea el checkout en ~/.engram-git/<repo>" $?
[ -f "$H1/.engram-git/repo1/.engram/ajena.jsonl" ]; T "C1 pull: trae la memoria de la otra maquina" $?
CALLS "$H1" | grep -q -- "--import"; T "C1 pull: llama a engram sync --import" $?
CALLS "$H1" | grep -q -- "--project"; [ $? -ne 0 ]; T "C1 pull: NO exporta (eso es del push)" $?
LOGOF "$H1" | grep -q "pull ok repo1"; T "C1 pull: deja constancia en el log" $?
[ ! -f "$H1/.engram-git/repo1/codigo.ts" ]; T "C1 pull: la rama de memoria no trae codigo" $?

# Segundo pull sobre el checkout ya existente: sigue trayendo lo nuevo (ff-only).
printf 'mas memoria ajena\n' > "$OTRA/.engram/ajena2.jsonl"
g "$OTRA" add -A; g "$OTRA" commit -m "mas memoria"; g "$OTRA" push origin engram-sync
run "$H1" "$SRC1" pull
[ "$RC" = 0 ]; T "C1 pull repetido: exit 0" $?
[ -f "$H1/.engram-git/repo1/.engram/ajena2.jsonl" ]; T "C1 pull repetido: hace fast-forward de lo nuevo" $?

# ════════════════════════════════════════════════════════════════════════════
# C2) MODO PUSH: "importa, exporta lo nuevo del proyecto, commit, push"
# ════════════════════════════════════════════════════════════════════════════
UP2="$(mkremote c2/repo2)"; SRC2="$(mksrc c2 "$UP2")"; H2="$(newhome c2)"
run "$H2" "$SRC2" push
[ "$RC" = 0 ]; T "C2 push: exit 0" $?
has_branch "$UP2" engram-sync; T "C2 push: crea la rama engram-sync en el remoto" $?
git -C "$UP2" ls-tree -r --name-only engram-sync | grep -q '^\.engram/repo2\.jsonl$'; T "C2 push: publica .engram/ en la raiz de la rama" $?
git -C "$UP2" ls-tree -r --name-only engram-sync | grep -q 'codigo\.ts'; [ $? -ne 0 ]; T "C2 push: la rama huerfana NO lleva codigo" $?
CALLS "$H2" | grep -q -- "--project repo2"; T "C2 push: exporta el proyecto del repo" $?
git -C "$UP2" log -1 --format=%s engram-sync | grep -q "^sync: "; T "C2 push: el commit se llama sync: <host> <fecha>" $?
LOGOF "$H2" | grep -q "push ok repo2"; T "C2 push: deja constancia en el log" $?

# Commit SOLO si cambió algo: el segundo push seguido no agrega un commit vacío.
antes="$(git -C "$UP2" rev-list --count engram-sync)"
run "$H2" "$SRC2" push
[ "$(git -C "$UP2" rev-list --count engram-sync)" = "$antes" ]; T "C2 push sin cambios: no crea un commit vacio" $?
LOGOF "$H2" | grep -q "sin cambios repo2"; T "C2 push sin cambios: lo dice en el log" $?
[ "$RC" = 0 ]; T "C2 push sin cambios: exit 0" $?

# Con memoria nueva vuelve a publicar.
RUNENV="ENGRAM_BUMP=-nuevo" run "$H2" "$SRC2" push; RUNENV=""
[ "$(git -C "$UP2" rev-list --count engram-sync)" -gt "$antes" ]; T "C2 push con memoria nueva: publica un commit" $?

# Importa ANTES de exportar: si exportara primero, subiría su propia memoria sin
# haber integrado la de las otras máquinas.
UP2b="$(mkremote c2/repo2b)"; SRC2b="$(mksrc c2b "$UP2b")"; H2b="$(newhome c2b)"
OTRA2="$TMP/otra2"; git clone -q "$UP2b" "$OTRA2" 2>/dev/null
g "$OTRA2" checkout -q --orphan engram-sync; g "$OTRA2" rm -rfq --cached .; rm -f "$OTRA2/codigo.ts"
mkdir -p "$OTRA2/.engram"; printf 'ajena\n' > "$OTRA2/.engram/ajena.jsonl"
g "$OTRA2" add -A; g "$OTRA2" commit -m otra; g "$OTRA2" push -u origin engram-sync
run "$H2b" "$SRC2b" push
[ "$(grep -n -- '--import' "$H2b/calls" | head -1 | cut -d: -f1)" -lt "$(grep -n -- '--project' "$H2b/calls" | head -1 | cut -d: -f1)" ]; T "C2 push: importa ANTES de exportar" $?
git -C "$UP2b" ls-tree -r --name-only engram-sync | grep -q 'ajena.jsonl'; T "C2 push: no pisa la memoria ajena que ya estaba" $?

# Divergencia REAL: un push que falla deja un commit local sin publicar y otra
# máquina avanza el remoto mientras tanto.
# La primera versión de este caso era un FIXTURE ROTO: la "otra máquina" pusheaba
# desde un commit viejo, el remoto la rechazaba en silencio (g() traga stderr) y
# el escenario que el caso decía medir no existía. Ahora cada paso se AFIRMA.
UPBAK="$TMP/remotes/c2/repo2b.guardado"
mv "$UP2b" "$UPBAK"                                    # se cae el remoto
RUNENV="ENGRAM_BUMP=-sin-red" run "$H2b" "$SRC2b" push; RUNENV=""
LOGOF "$H2b" | grep -q "push falló"; T "C2 divergencia(fixture): el push sin remoto falla y queda logueado" $?
mv "$UPBAK" "$UP2b"                                    # vuelve el remoto
g "$OTRA2" pull -q --rebase origin engram-sync         # la otra maquina se pone al dia
printf 'ajena posterior\n' > "$OTRA2/.engram/posterior.jsonl"
g "$OTRA2" add -A; g "$OTRA2" commit -m posterior; g "$OTRA2" push origin engram-sync
git -C "$UP2b" ls-tree -r --name-only engram-sync | grep -q 'posterior.jsonl'; T "C2 divergencia(fixture): el remoto avanzo de verdad" $?
git -C "$UP2b" cat-file -e "$(git -C "$H2b/.engram-git/repo2b" rev-parse HEAD)^{commit}" 2>/dev/null; [ $? -ne 0 ]; T "C2 divergencia(fixture): el local tiene un commit que el remoto no" $?
RUNENV="ENGRAM_BUMP=-divergente" run "$H2b" "$SRC2b" push; RUNENV=""
[ "$RC" = 0 ]; T "C2 divergencia: exit 0" $?
git -C "$UP2b" ls-tree -r --name-only engram-sync | grep -q 'posterior.jsonl'; T "C2 divergencia: conserva lo del remoto" $?
git -C "$UP2b" show "engram-sync:.engram/repo2b.jsonl" 2>/dev/null | grep -q 'divergente'; T "C2 divergencia: sube lo propio (pull --rebase + push)" $?

# A clean export can still have a previously committed, unpublished payload.
UPP="$(mkremote pending/retry)"; SRCP="$(mksrc pending "$UPP")"; HP="$(newhome pending)"
run "$HP" "$SRCP" push
mv "$UPP" "$UPP.offline"
RUNENV="ENGRAM_BUMP=-pending" run "$HP" "$SRCP" push; RUNENV=""
pending_head="$(git -C "$HP/.engram-git/retry" rev-parse HEAD)"
LOGOF "$HP" | tail -1 | grep -q 'push falló'; T "pending offline: final log reports failed publication, not ok" $?
mv "$UPP.offline" "$UPP"
RUNENV="ENGRAM_BUMP=-pending" run "$HP" "$SRCP" push; RUNENV=""
[ "$(git -C "$UPP" rev-parse engram-sync)" = "$pending_head" ]; T "pending recovery: retries same payload without a new commit" $?
[ "$(git -C "$HP/.engram-git/retry" rev-parse HEAD)" = "$pending_head" ]; T "pending recovery: does not create an empty commit" $?

# ════════════════════════════════════════════════════════════════════════════
# C3) "El proyecto se asume igual al nombre del repo (override: ENGRAM_PROJECT)"
# ════════════════════════════════════════════════════════════════════════════
UP3="$(mkremote c3/repo3)"; SRC3="$(mksrc c3 "$UP3")"; H3="$(newhome c3)"
RUNENV="ENGRAM_PROJECT=proyecto-a-mano" run "$H3" "$SRC3" push; RUNENV=""
CALLS "$H3" | grep -q -- "--project proyecto-a-mano"; T "C3 ENGRAM_PROJECT: exporta el proyecto pedido" $?
CALLS "$H3" | grep -q -- "--project repo3"; [ $? -ne 0 ]; T "C3 ENGRAM_PROJECT: NO exporta el nombre del repo" $?
[ -d "$H3/.engram-git/repo3" ]; T "C3 ENGRAM_PROJECT: el checkout sigue siendo por REPO" $?
has_branch "$UP3" engram-sync; T "C3 ENGRAM_PROJECT: la rama sigue siendo la del repo" $?

# ════════════════════════════════════════════════════════════════════════════
# C4) "Nunca falla la sesión: los errores van al log y el exit es 0"
#     Un hook de SessionStart/Stop que devuelve != 0 ensucia cada arranque.
# ════════════════════════════════════════════════════════════════════════════
H4a="$(newhome c4a)"; SRC4a="$(mksrc c4a "$(mkremote c4/repo4)")"
RUNPATH="/usr/bin:/bin" run "$H4a" "$SRC4a" push; RUNPATH=""
[ "$RC" = 0 ]; T "C4 engram no instalado: exit 0" $?
LOGOF "$H4a" | grep -q "engram no instalado"; T "C4 engram no instalado: lo dice en el log" $?
[ ! -d "$H4a/.engram-git" ]; T "C4 engram no instalado: no clona nada" $?

H4b="$(newhome c4b)"; SIN="$TMP/src/sinremote"; git init -q -b main "$SIN"
printf 'x\n' > "$SIN/a"; g "$SIN" add -A; g "$SIN" commit -m base
run "$H4b" "$SIN" push
[ "$RC" = 0 ]; T "C4 repo sin origin: exit 0" $?
LOGOF "$H4b" | grep -q "sin remote"; T "C4 repo sin origin: lo dice en el log" $?

H4c="$(newhome c4c)"; NOREPO="$TMP/src/norepo"; mkdir -p "$NOREPO"
run "$H4c" "$NOREPO" push
[ "$RC" = 0 ]; T "C4 fuera de un repo git: exit 0" $?
[ ! -d "$H4c/.engram-git" ]; T "C4 fuera de un repo git: no clona nada" $?

H4d="$(newhome c4d)"; SRC4d="$(mksrc c4d "$(mkremote c4/repo4d)")"
g "$SRC4d" remote set-url origin "$TMP/no-existe-el-remoto.git"
run "$H4d" "$SRC4d" push
[ "$RC" = 0 ]; T "C4 remoto inexistente: exit 0" $?
LOGOF "$H4d" | grep -q "clone falló"; T "C4 remoto inexistente: lo dice en el log" $?

# $DIR ocupado por un directorio que no es un checkout: el hook NO debe borrarlo.
H4e="$(newhome c4e)"; UP4e="$(mkremote c4/repo4e)"; SRC4e="$(mksrc c4e "$UP4e")"
mkdir -p "$H4e/.engram-git/repo4e"; printf 'no me borres\n' > "$H4e/.engram-git/repo4e/importante.txt"
run "$H4e" "$SRC4e" push
[ "$RC" = 0 ]; T "C4 \$DIR ocupado: exit 0" $?
[ -f "$H4e/.engram-git/repo4e/importante.txt" ]; T "C4 \$DIR ocupado: NO destruye lo que habia" $?
LOGOF "$H4e" | grep -q "clone falló"; T "C4 \$DIR ocupado: lo dice en el log" $?
# Y se DETIENE ahi. Sin este par, quitar el `exit 0` del clone de rescate pasaba
# desapercibido: el hook seguia y escribia .engram/, README.md y config de git
# DENTRO del directorio ajeno que justamente no le pertenece (mutante m15,
# medido 2026-09-08). "No destruir lo que habia" no alcanza: tampoco debe
# agregar nada.
[ "$(ls -A "$H4e/.engram-git/repo4e" | tr -d '[:space:]')" = "importante.txt" ]; T "C4 \$DIR ocupado: no escribe NADA nuevo ahi adentro" $?
[ "$(LOGOF "$H4e" | tail -1 | grep -c 'clone falló')" = 1 ]; T "C4 \$DIR ocupado: el hook se detiene en el clone fallido" $?

# LIMITE CONOCIDO — `cd "$DIR" || exit 0` es defensa inalcanzable, a proposito.
# Quitarle el `|| exit 0` NO lo caza ningun caso, y esta medido (2026-09-08): la
# unica forma de que el cd falle es un $DIR ilegible, pero entonces el test
# `[ -e "$DIR/.git" ]` de mas arriba tambien falla, el bootstrap intenta clonar,
# el clone muere porque el directorio existe y no esta vacio, y el hook sale por
# "clone falló" ANTES de llegar al cd. Se deja el guard igual: si algun dia ese
# camino se vuelve alcanzable, la alternativa es seguir corriendo `git add`,
# `git commit` y `git push` con el cwd en el REPO DEL USUARIO.

H4f="$(newhome c4f)"; SRC4f="$(mksrc c4f "$(mkremote c4/repo4f)")"
RUNENV="ENGRAM_RC_EXPORT=1" run "$H4f" "$SRC4f" push; RUNENV=""
[ "$RC" = 0 ]; T "C4 export de engram roto: exit 0" $?
LOGOF "$H4f" | grep -q "export falló"; T "C4 export de engram roto: lo dice en el log" $?

H4g="$(newhome c4g)"; UP4g="$(mkremote c4/repo4g)"; SRC4g="$(mksrc c4g "$UP4g")"
run "$H4g" "$SRC4g" push                      # bootstrap ok
rm -rf "$UP4g"                                # el remoto desaparece
RUNENV="ENGRAM_BUMP=-x" run "$H4g" "$SRC4g" push; RUNENV=""
[ "$RC" = 0 ]; T "C4 remoto caido en el push: exit 0" $?
LOGOF "$H4g" | grep -q "push falló"; T "C4 remoto caido en el push: lo dice en el log" $?

H4h="$(newhome c4h)"; SRC4h="$(mksrc c4h "$(mkremote c4/repo4h)")"
run "$H4h" "$SRC4h" ""
[ "$RC" = 0 ]; T "C4 sin argumento: exit 0 (default push, linea 15)" $?

# ── AGUJERO 1 (medido 2026-09-08): sin ~/.engram el hook es un NO-OP MUDO ────
# `git clone ... 2>>"$LOG"` con $LOG en un directorio inexistente NO ejecuta el
# clone: bash falla al abrir la redirección y no corre el comando. En una máquina
# recién bootstrapeada — justo donde querés IMPORTAR la memoria de las otras —
# el hook no sincroniza nada, no loguea nada, y devuelve 0.
H4i="$(newhome c4i sin-engram)"; UP4i="$(mkremote c4/repo4i)"; SRC4i="$(mksrc c4i "$UP4i")"
run "$H4i" "$SRC4i" push
[ "$RC" = 0 ]; T "AGUJERO 1: sin ~/.engram, exit 0" $?
[ -f "$H4i/.engram/git-sync.log" ]; T "AGUJERO 1: sin ~/.engram, el log se crea igual" $?
has_branch "$UP4i" engram-sync; T "AGUJERO 1: sin ~/.engram, el push igual sincroniza" $?
[ ! -s "$H4i/err" ]; T "AGUJERO 1: sin ~/.engram, no vomita errores de redireccion a stderr" $?

# ════════════════════════════════════════════════════════════════════════════
# C5) "Si la rama no existe en el remoto, se crea vacía EN EL PRIMER PUSH"
#     AGUJERO 2 (medido 2026-09-08): también la creaba —y la PUBLICABA— en el
#     pull. Un SessionStart escribía una rama nueva en el remoto de cada repo
#     que abrías, incluido uno ajeno donde no querés dejar rastro.
# ════════════════════════════════════════════════════════════════════════════
UP5="$(mkremote c5/repo5)"; SRC5="$(mksrc c5 "$UP5")"; H5="$(newhome c5)"
run "$H5" "$SRC5" pull
[ "$RC" = 0 ]; T "C5 pull sin rama: exit 0" $?
has_branch "$UP5" engram-sync; [ $? -ne 0 ]; T "AGUJERO 2: pull NO publica la rama en el remoto" $?
[ -d "$H5/.engram-git/repo5/.git" ]; T "C5 pull sin rama: igual deja el checkout listo" $?
run "$H5" "$SRC5" push
has_branch "$UP5" engram-sync; T "C5: el PRIMER PUSH sí publica la rama" $?
git -C "$UP5" ls-tree -r --name-only engram-sync | grep -q '^README.md$'; T "C5: la rama nace con su README" $?

# "se crea VACIA en el primer push": sin memoria nueva que exportar el hook sale
# por la rama de "sin cambios" ANTES del push del paso 4, asi que si el bootstrap
# no publicara, la rama no existiria nunca en el remoto. Este caso es el unico que
# separa las dos cosas: sin el, borrar el push del bootstrap pasaba desapercibido
# (lo delato el mutante m07 el 2026-09-08).
UP5b="$(mkremote c5/repo5b)"; SRC5b="$(mksrc c5b "$UP5b")"; H5b="$(newhome c5b)"
RUNENV="ENGRAM_NADA=1" run "$H5b" "$SRC5b" push; RUNENV=""
LOGOF "$H5b" | grep -q "sin cambios"; T "C5 rama vacia(fixture): no habia nada que exportar" $?
has_branch "$UP5b" engram-sync; T "C5: la rama se crea VACIA en el primer push, sin memoria que subir" $?
[ "$RC" = 0 ]; T "C5 rama vacia: exit 0" $?

# ════════════════════════════════════════════════════════════════════════════
# C6) Dos modos y solo dos. AGUJERO 3 (medido 2026-09-08): cualquier otra
#     palabra caía en la rama de PUSH — un typo en settings.json convertía una
#     lectura de SessionStart en una escritura al remoto.
# ════════════════════════════════════════════════════════════════════════════
UP6="$(mkremote c6/repo6)"; SRC6="$(mksrc c6 "$UP6")"; H6="$(newhome c6)"
run "$H6" "$SRC6" pul
[ "$RC" = 0 ]; T "AGUJERO 3: modo con typo, exit 0" $?
has_branch "$UP6" engram-sync; [ $? -ne 0 ]; T "AGUJERO 3: modo con typo NO escribe en el remoto" $?
LOGOF "$H6" | grep -qi "modo"; T "AGUJERO 3: modo con typo queda registrado en el log" $?
H6b="$(newhome c6b)"; UP6b="$(mkremote c6/repo6b)"; SRC6b="$(mksrc c6b "$UP6b")"
run "$H6b" "$SRC6b" "--help"
has_branch "$UP6b" engram-sync; [ $? -ne 0 ]; T "AGUJERO 3: un flag tampoco es un modo" $?

# ════════════════════════════════════════════════════════════════════════════
# C7) "Cada repo lleva SU memoria". AGUJERO 4 (medido 2026-09-08): el checkout
#     se indexaba por `basename`, así que orgA/api y orgB/api compartían uno
#     solo. El segundo exportaba su memoria DENTRO del checkout del primero
#     (y la habría empujado al remoto del primero), y su propio remoto no
#     recibía nunca nada.
# ════════════════════════════════════════════════════════════════════════════
UPA="$(mkremote orgA/api)"; UPB="$(mkremote orgB/api)"
SRCA="$(mksrc colA "$UPA")"; SRCB="$(mksrc colB "$UPB")"; H7="$(newhome c7)"
RUNENV="ENGRAM_PROJECT=memoria-A" run "$H7" "$SRCA" push; RUNENV=""
RUNENV="ENGRAM_PROJECT=memoria-B" run "$H7" "$SRCB" push; RUNENV=""
has_branch "$UPA" engram-sync; T "AGUJERO 4: orgA/api publica su rama" $?
has_branch "$UPB" engram-sync; T "AGUJERO 4: orgB/api publica su rama (no la pisa el homonimo)" $?
git -C "$UPA" ls-tree -r --name-only engram-sync 2>/dev/null | grep -q 'memoria-A.jsonl'; T "AGUJERO 4: la memoria de A esta en el remoto de A" $?
git -C "$UPB" ls-tree -r --name-only engram-sync 2>/dev/null | grep -q 'memoria-B.jsonl'; T "AGUJERO 4: la memoria de B esta en el remoto de B" $?
git -C "$UPA" ls-tree -r --name-only engram-sync 2>/dev/null | grep -q 'memoria-B.jsonl'; [ $? -ne 0 ]; T "AGUJERO 4: la memoria de B NO se filtra al remoto de A" $?

# El caso feliz no debe pagar el arreglo: un solo repo sigue usando el nombre corto.
[ -d "$H2/.engram-git/repo2/.git" ]; T "C7: sin homonimos, el checkout se llama como el repo" $?

# ════════════════════════════════════════════════════════════════════════════
# C8) Self-heal del refspec (bug del 2026-09-03 fijado en la línea 34-37):
#     un checkout viejo creado con `clone --depth 1` tiene el refspec clavado
#     en la rama default → `origin/engram-sync` no existe nunca y la memoria de
#     las otras máquinas jamás se importa.
# ════════════════════════════════════════════════════════════════════════════
UP8="$(mkremote c8/repo8)"; SRC8="$(mksrc c8 "$UP8")"; H8="$(newhome c8)"
D8="$H8/.engram-git/repo8"; mkdir -p "$H8/.engram-git"
git clone -q --depth 1 "$UP8" "$D8" 2>/dev/null           # checkout "viejo"
g "$D8" checkout -q --orphan engram-sync; g "$D8" rm -rfq --cached .; g "$D8" clean -fdxq .
printf '# engram-sync\n' > "$D8/README.md"; g "$D8" add -A; g "$D8" commit -m base; g "$D8" push -q -u origin engram-sync
git -C "$D8" config remote.origin.fetch "+refs/heads/main:refs/remotes/origin/main"   # el refspec roto
OTRA8="$TMP/otra8"; git clone -q -b engram-sync "$UP8" "$OTRA8" 2>/dev/null
mkdir -p "$OTRA8/.engram"; printf 'ajena\n' > "$OTRA8/.engram/ajena.jsonl"
g "$OTRA8" add -A; g "$OTRA8" commit -m otra; g "$OTRA8" push origin engram-sync
run "$H8" "$SRC8" pull
git -C "$D8" config --get-all remote.origin.fetch | grep -q 'refs/heads/engram-sync:'; T "C8: corrige el refspec clavado" $?
[ -f "$D8/.engram/ajena.jsonl" ]; T "C8: con el refspec corregido, importa lo ajeno" $?
LOGOF "$H8" | grep -q "refspec corregido"; T "C8: deja constancia de la correccion" $?
run "$H8" "$SRC8" pull
[ "$(LOGOF "$H8" | grep -c 'refspec corregido')" = 1 ]; T "C8: no reescribe un refspec que ya esta bien" $?

# ════════════════════════════════════════════════════════════════════════════
# C9) El repo del USUARIO es intocable. El hook solo lee su `remote get-url`;
#     cualquier otra cosa sería escribir en el repo donde el usuario trabaja.
# ════════════════════════════════════════════════════════════════════════════
UP9="$(mkremote c9/repo9)"; SRC9="$(mksrc c9 "$UP9")"; H9="$(newhome c9)"
printf 'trabajo sin commitear\n' > "$SRC9/wip.txt"
printf 'export const codigo = 2\n' > "$SRC9/codigo.ts"
before="$(git -C "$SRC9" status --porcelain; git -C "$SRC9" rev-parse HEAD; git -C "$SRC9" branch --format='%(refname)')"
run "$H9" "$SRC9" push
after="$(git -C "$SRC9" status --porcelain; git -C "$SRC9" rev-parse HEAD; git -C "$SRC9" branch --format='%(refname)')"
[ "$before" = "$after" ]; T "C9: el repo del usuario queda intacto (estado, HEAD y ramas)" $?
[ -f "$SRC9/wip.txt" ]; T "C9: no toca el trabajo sin commitear" $?
[ ! -d "$SRC9/.engram" ]; T "C9: no deja .engram dentro del repo del usuario" $?
has_branch "$UP9" main; T "C9: no toca la rama de codigo del remoto" $?
git -C "$UP9" rev-parse main | grep -q "$(git -C "$SRC9" rev-parse origin/main)"; T "C9: main del remoto sigue en el mismo commit" $?

# El cwd puede ser un subdirectorio profundo del repo (worktrees, monorepos).
H9b="$(newhome c9b)"; UP9b="$(mkremote c9/repo9b)"; SRC9b="$(mksrc c9b "$UP9b")"
mkdir -p "$SRC9b/a/b/c"
run "$H9b" "$SRC9b/a/b/c" push
has_branch "$UP9b" engram-sync; T "C9: funciona desde un subdirectorio del repo" $?

# CLAUDE_PROJECT_DIR manda sobre el cwd (línea 16).
H9c="$(newhome c9c)"; UP9c="$(mkremote c9/repo9c)"; SRC9c="$(mksrc c9c "$UP9c")"
RUNENV="CLAUDE_PROJECT_DIR=$SRC9c" run "$H9c" "$TMP" push; RUNENV=""
has_branch "$UP9c" engram-sync; T "C9: CLAUDE_PROJECT_DIR manda sobre el cwd" $?

# ════════════════════════════════════════════════════════════════════════════
# LÍMITES CONOCIDOS Y ACEPTADOS (medidos el 2026-09-08). Se fijan acá para que
# el día que alguien los tape sea una DECISIÓN y no un accidente.
# ════════════════════════════════════════════════════════════════════════════
# L1) Concurrent calls share a nonblocking kernel lock before checkout work.
# The contender defers truthfully; detailed overlap/crash/origin scenarios live
# in tests/engram_sync_concurrency_test.py. No automatic Stop retry is promised.
UPL="$(mkremote lim/conc)"; SRCL="$(mksrc lim "$UPL")"; HL="$(newhome lim)"
run "$HL" "$SRCL" push
( RUNENV="ENGRAM_BUMP=-p1" run "$HL" "$SRCL" push ) & 
( RUNENV="ENGRAM_BUMP=-p2" run "$HL" "$SRCL" push ) &
wait
[ "$?" = 0 ]; T "LIMITE L1: dos pushes concurrentes no cuelgan la sesion" $?
has_branch "$UPL" engram-sync; T "LIMITE L1: la rama sigue existiendo tras la carrera" $?

if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails/$total casos fallan — la memoria compartida tiene agujeros." >&2
  exit 1
fi
echo "OK: $total/$total casos del contrato de engram-git-sync pasan."
exit 0
