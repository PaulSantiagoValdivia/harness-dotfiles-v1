#!/usr/bin/env bash
# engram-git-sync.sh — comparte la memoria Engram de UN repo por git, sin manos.
#
#   engram-git-sync.sh pull   # SessionStart: trae la rama engram-sync del repo actual e importa
#   engram-git-sync.sh push   # SessionEnd/manual: importa, exporta lo nuevo del proyecto, commit, push
#
# Cada repo lleva su propia memoria en una rama huérfana `engram-sync` (sin código,
# sin CI, sin PRs), con checkout aparte en ~/.engram-git/<repo>/ y `.engram/` en la raíz.
# El proyecto Engram se asume igual al nombre del repo (override: ENGRAM_PROJECT).
# Si la rama no existe en el remoto, se crea vacía en el primer push.
#
# Nunca falla la sesión: los errores van a ~/.engram/git-sync.log y el exit es 0.

set -u
MODE="${1:-push}"
SRC="${CLAUDE_PROJECT_DIR:-$PWD}"
BRANCH="engram-sync"
LOG="$HOME/.engram/git-sync.log"
# El directorio del log tiene que existir ANTES de la primera redirección. Sin él,
# `git clone ... 2>>"$LOG"` NO CORRE: bash falla al abrir el archivo y ni siquiera
# ejecuta el comando. En una máquina recién bootstrapeada —justo donde querés
# importar la memoria de las otras— el hook era un no-op mudo (medido 2026-09-08).
mkdir -p "${LOG%/*}" 2>/dev/null
log() { printf '%s %s %s\n' "$(date -u +%FT%TZ)" "$MODE" "$*" >>"$LOG"; }

# Dos modos y sólo dos. Antes, cualquier otra palabra caía en la rama de PUSH: un
# typo en settings.json convertía la lectura de SessionStart en una ESCRITURA al
# remoto de cada repo. Ante la duda, no se escribe afuera.
case "$MODE" in
  pull|push) ;;
  *) log "modo desconocido: '$MODE' (usá pull o push)"; exit 0 ;;
esac

command -v engram >/dev/null 2>&1 || { log "engram no instalado"; exit 0; }
URL="$(git -C "$SRC" remote get-url origin 2>/dev/null)" || { log "sin remote en $SRC"; exit 0; }
REPO="$(basename -s .git "$URL")"
PROJECT="${ENGRAM_PROJECT:-$REPO}"
# Lock the basename namespace BEFORE checkout selection/bootstrap: two origins
# with the same basename otherwise race to create the same directory. Different
# basenames remain independent. Kernel locks survive while inherited fd 9 is open.
command -v python3 >/dev/null 2>&1 || { log "lock no disponible: falta python3"; exit 0; }
LOCK_ROOT="$HOME/.engram/git-sync-locks"
if [ -L "$HOME/.engram" ] || [ -L "$LOCK_ROOT" ]; then log "lock inseguro: symlink"; exit 0; fi
(umask 077; mkdir -p "$LOCK_ROOT") || { log "lock no disponible"; exit 0; }
LOCK_KEY="$(printf '%s' "$REPO" | cksum | awk '{print $1}')"
LOCK_FILE="$LOCK_ROOT/$LOCK_KEY.lock"
if [ -L "$LOCK_FILE" ] || { [ -e "$LOCK_FILE" ] && [ ! -f "$LOCK_FILE" ]; }; then
  log "lock inseguro: archivo no regular"; exit 0
fi
(umask 077; : >> "$LOCK_FILE") || { log "lock no disponible"; exit 0; }
exec 9>>"$LOCK_FILE" || { log "lock no disponible"; exit 0; }
python3 - "$LOCK_FILE" <<'PYLOCK'
import fcntl, os, stat, sys
try:
    opened, named = os.fstat(9), os.lstat(sys.argv[1])
    if not stat.S_ISREG(named.st_mode) or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
        sys.exit(1)
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(75)
except OSError:
    sys.exit(1)
PYLOCK
LOCK_RC=$?
case "$LOCK_RC" in
  0) ;;
  75) log "sincronización diferida: otro escritor activo ($REPO); reintentar en el próximo hook o manualmente"; exit 0 ;;
  *) log "lock no disponible; sincronización no ejecutada"; exit 0 ;;
esac
# Never unlink the lock file: replacement could give contenders different inodes.
DIR="$HOME/.engram-git/$REPO"
# Dos repos distintos pueden compartir basename (orgA/api y orgB/api). Indexar el
# checkout sólo por el nombre hacía que el segundo exportara su memoria DENTRO del
# checkout del primero —y la empujara al remoto del primero—, y su propio remoto no
# recibía nada nunca (medido 2026-09-08). Sólo se desambigua cuando hay conflicto
# real, así que ningún checkout existente se invalida.
if [ -e "$DIR/.git" ] && [ "$(git -C "$DIR" remote get-url origin 2>/dev/null)" != "$URL" ]; then
  DIR="$DIR-$(printf '%s' "$URL" | cksum | awk '{print $1}')"
fi

# Bootstrap del checkout aparte.
if [ ! -e "$DIR/.git" ]; then
  mkdir -p "$HOME/.engram-git"
  if ! git clone -q --branch "$BRANCH" --single-branch "$URL" "$DIR" 2>>"$LOG"; then
    # La rama no existe todavía: crearla huérfana.
    git clone -q --depth 1 "$URL" "$DIR" 2>>"$LOG" || { log "clone falló"; exit 0; }
    git -C "$DIR" checkout -q --orphan "$BRANCH" && git -C "$DIR" rm -rfq --cached . && git -C "$DIR" clean -fdxq .
    # `clone --depth 1` implica --single-branch: el refspec queda clavado en la rama
    # default y `origin/engram-sync` nunca existe → "not something we can merge" en
    # cada sesión y la memoria de otras máquinas jamás se importa (2026-09-03).
    git -C "$DIR" config remote.origin.fetch "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
    printf '# engram-sync\n\nMemoria Engram del proyecto `%s`, exportada por hooks de Claude Code. Sin código, sin CI, sin PRs.\n' "$PROJECT" >"$DIR/README.md"
    git -C "$DIR" add README.md && git -C "$DIR" commit -q -m "chore(engram): rama de sync de memoria"
    # La rama se PUBLICA en el primer push, no en un pull. Un SessionStart no
    # escribe una rama nueva en el remoto de cada repo que abrís.
    if [ "$MODE" = push ]; then
      git -C "$DIR" push -q -u origin "$BRANCH" 2>>"$LOG" || log "no pude crear $BRANCH"
    fi
  fi
fi
cd "$DIR" || exit 0

# 1. Traer lo de los demás. Self-heal del refspec para checkouts creados antes del fix.
if ! git config --get-all remote.origin.fetch | grep -Eq "refs/heads/(\*|$BRANCH):"; then
  git config remote.origin.fetch "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  log "refspec corregido a $BRANCH"
fi
git fetch -q origin "$BRANCH" 2>>"$LOG" || log "fetch falló (offline?)"
git merge -q --ff-only "origin/$BRANCH" 2>>"$LOG" || true

# 2. Importar chunks ajenos (idempotente).
[ -d .engram ] && { engram sync --import >/dev/null 2>>"$LOG" || log "import falló"; }

[ "$MODE" = "pull" ] && { log "ok $PROJECT"; exit 0; }

# 3. Exportar lo nuevo del proyecto de este repo.
engram sync --project "$PROJECT" >/dev/null 2>>"$LOG" || log "export falló"

# 4. Committing and publishing are different decisions: a failed earlier push
# leaves a clean index with unpublished commits. Retry those without empty commits.
git add -A .engram 2>>"$LOG"
if ! git diff --cached --quiet; then
  git commit -q -m "sync: $(hostname -s) $(date -u +%FT%TZ)" 2>>"$LOG" || { log "commit falló"; exit 0; }
fi
LOCAL_HEAD="$(git rev-parse HEAD 2>/dev/null)" || { log "HEAD no disponible"; exit 0; }
REMOTE_HEAD="$(git rev-parse --verify "refs/remotes/origin/$BRANCH" 2>/dev/null)" || REMOTE_HEAD=""
if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then log "sin cambios $PROJECT"; exit 0; fi
if ! git push -q origin "$BRANCH" 2>>"$LOG"; then
  if ! { git pull -q --rebase origin "$BRANCH" 2>>"$LOG" && git push -q origin "$BRANCH" 2>>"$LOG"; }; then
    log "push falló; publicación pendiente $PROJECT"
    exit 0
  fi
fi
log "ok $PROJECT"
exit 0
