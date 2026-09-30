#!/usr/bin/env bash
# Contrato de memory-snapshot, el historial Git local de ~/.claude/memory.
#
# Las pruebas usan una memoria descartable: nunca leen ni ejecutan el script
# contra la memoria real. Cada corrida compara los hashes de TODOS los archivos
# fuera de `.git`, porque el snapshot puede versionarlos pero jamás tocarlos.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT="$REPO_DIR/files/shared/bin/memory-snapshot"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/memory-snapshot-test.XXXXXX")"
cleanup() {
  case "${TMP_ROOT:-}" in
    *memory-snapshot-test.*) rm -rf "$TMP_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[ -x "$SNAPSHOT" ] || fail "no existe o no es ejecutable $SNAPSHOT"
bash -n "$SNAPSHOT" || fail "memory-snapshot no pasa el chequeo de sintaxis"

MEMORY="$TMP_ROOT/memory"
GLOBAL_CONFIG="$TMP_ROOT/global.gitconfig"
printf '%s\n' '[user]' '  name = Config global intacta' > "$GLOBAL_CONFIG"
global_before="$(shasum "$GLOBAL_CONFIG")"

working_hashes() {
  if [ ! -d "$MEMORY" ]; then
    printf '%s\n' 'DIRECTORIO_AUSENTE'
    return
  fi

  find "$MEMORY" -type f ! -path "$MEMORY/.git/*" -print \
    | LC_ALL=C sort \
    | while IFS= read -r file; do
        printf '%s  %s\n' "$(shasum "$file" | awk '{print $1}')" "${file#"$MEMORY/"}"
      done
}

run_snapshot() {
  local before after
  before="$(working_hashes)"
  RUN_OUTPUT="$(MEMORY_DIR="$MEMORY" GIT_CONFIG_GLOBAL="$GLOBAL_CONFIG" "$SNAPSHOT" "$@" 2>&1)"
  RUN_RC=$?
  after="$(working_hashes)"
  [ "$before" = "$after" ] \
    || fail "memory-snapshot modificó archivos fuera de .git:\nANTES:\n$before\nDESPUÉS:\n$after"
}

commit_count() { git -C "$MEMORY" rev-list --count HEAD; }

# --- 1. Directorio inexistente: no falla ni crea nada -----------------------
run_snapshot
[ "$RUN_RC" -eq 0 ] || fail "directorio inexistente debería salir 0, salió $RUN_RC: $RUN_OUTPUT"
[ ! -e "$MEMORY" ] || fail "creó el directorio de memoria inexistente"

mkdir -p "$MEMORY"
printf '%s\n' '# Índice' > "$MEMORY/MEMORY.md"
printf '%s\n' '# Arquitectura' > "$MEMORY/architecture.md"
printf '%s\n' '# Flujo de trabajo' > "$MEMORY/workflow.md"

# --- 2. Dry-run inicial: informa, pero ni siquiera crea .git ----------------
run_snapshot --dry-run
[ "$RUN_RC" -eq 0 ] || fail "dry-run inicial debería salir 0, salió $RUN_RC: $RUN_OUTPUT"
[ ! -e "$MEMORY/.git" ] || fail "dry-run creó .git"
printf '%s' "$RUN_OUTPUT" | grep -q 'DRY-RUN: inicializaría' \
  || fail "dry-run no informó que inicializaría el repositorio: $RUN_OUTPUT"

# --- 3. Primera corrida: repo main, un commit y árbol limpio ----------------
run_snapshot
[ "$RUN_RC" -eq 0 ] || fail "primera corrida falló: $RUN_OUTPUT"
[ -d "$MEMORY/.git" ] || fail "primera corrida no creó .git"
[ "$(git -C "$MEMORY" branch --show-current)" = "main" ] || fail "el repo no quedó en main"
[ "$(commit_count)" -eq 1 ] || fail "el snapshot inicial no creó exactamente un commit"
[ -z "$(git -C "$MEMORY" status --porcelain)" ] || fail "el árbol quedó sucio tras el snapshot inicial"
[ "$(git -C "$MEMORY" config --local user.name)" = "memory-snapshot" ] \
  || fail "no configuró user.name local"
[ "$(git -C "$MEMORY" config --local user.email)" = "memory-snapshot@localhost" ] \
  || fail "no configuró user.email local"
[ -z "$(git -C "$MEMORY" remote)" ] || fail "el snapshot agregó un remote"

# --- 4. Segunda corrida sin cambios: no agrega un commit --------------------
run_snapshot
[ "$RUN_RC" -eq 0 ] || fail "segunda corrida sin cambios falló: $RUN_OUTPUT"
[ "$(commit_count)" -eq 1 ] || fail "creó un commit sin cambios"

# --- 5. Modificar y agregar: crea un único snapshot nuevo -------------------
printf '%s\n' '# Arquitectura' 'contenido nuevo' > "$MEMORY/architecture.md"
printf '%s\n' '# Hallazgo nuevo' > "$MEMORY/discovery.md"
run_snapshot --dry-run
[ "$RUN_RC" -eq 0 ] || fail "dry-run con cambios falló: $RUN_OUTPUT"
[ "$(commit_count)" -eq 1 ] || fail "dry-run con cambios creó un commit"
printf '%s' "$RUN_OUTPUT" | grep -q 'architecture.md' \
  || fail "dry-run no listó los cambios pendientes: $RUN_OUTPUT"
run_snapshot
[ "$RUN_RC" -eq 0 ] || fail "corrida con cambios falló: $RUN_OUTPUT"
[ "$(commit_count)" -eq 2 ] || fail "los cambios no crearon exactamente el segundo commit"
[ -z "$(git -C "$MEMORY" status --porcelain)" ] || fail "el árbol quedó sucio tras el segundo snapshot"

# --- 6. Los hashes se comparan dentro de run_snapshot en TODAS las corridas -
# La propiedad no se prueba con una sola muestra: cada invocación de arriba y
# de abajo queda envuelta por la misma comparación de todos los archivos.

# --- 7. Rama distinta de main: exit 3 y ningún commit -----------------------
git -C "$MEMORY" checkout -b proposal/test >/dev/null 2>&1 \
  || fail "no se pudo crear la rama de prueba"
printf '%s\n' 'cambio deliberado en otra rama' >> "$MEMORY/workflow.md"
before_commits="$(commit_count)"
run_snapshot
[ "$RUN_RC" -eq 3 ] || fail "rama distinta debería salir 3, salió $RUN_RC: $RUN_OUTPUT"
[ "$(commit_count)" = "$before_commits" ] || fail "commiteó sobre una rama distinta de main"
printf '%s' "$RUN_OUTPUT" | grep -q "no 'main'" || fail "no avisó por la rama distinta: $RUN_OUTPUT"

# --- 8. index.lock: sale limpio, no toca nada y no crea commit --------------
git -C "$MEMORY" checkout main >/dev/null 2>&1 || fail "no se pudo volver a main"
: > "$MEMORY/.git/index.lock"
before_commits="$(commit_count)"
run_snapshot
[ "$RUN_RC" -eq 0 ] || fail "index.lock debería salir 0, salió $RUN_RC: $RUN_OUTPUT"
[ "$(commit_count)" = "$before_commits" ] || fail "commiteó con index.lock presente"
[ -e "$MEMORY/.git/index.lock" ] || fail "eliminó un index.lock ajeno"
rm -f "$MEMORY/.git/index.lock"

# --- 9. La configuración global queda byte-idéntica -------------------------
global_after="$(shasum "$GLOBAL_CONFIG")"
[ "$global_before" = "$global_after" ] \
  || fail "memory-snapshot modificó la configuración global de Git"

printf 'OK: memory-snapshot versiona sólo en Git local sin tocar la memoria (9 casos)\n'
