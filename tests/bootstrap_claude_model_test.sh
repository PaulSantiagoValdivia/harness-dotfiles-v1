#!/usr/bin/env bash
# Contrato del modelo de Claude en bootstrap.sh.
#
# El modelo es una preferencia de cuenta y bootstrap lo conserva al sincronizar
# el resto de settings.json. La variante [1m] es la excepción: saca el techo de
# contexto que fuerza la compactación y verify.sh la declara FAIL, así que
# preservarla dejaría a bootstrap reinstalando en cada corrida un estado que su
# propia verificación rechaza.
#
# Cada fixture usa un HOME aislado; la configuración real del usuario no se toca.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_PATH="$PATH"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-claude-model-test.XXXXXX")"

cleanup() {
  case "${TMP_ROOT:-}" in
    *bootstrap-claude-model-test.*) rm -rf "$TMP_ROOT" ;;
  esac
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

STUB_BIN="$TMP_ROOT/bin"
mkdir -p "$STUB_BIN"

cat > "$STUB_BIN/brew" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--prefix" ]; then
  printf '%s\n' /usr/local
  exit 0
fi
exit 0
EOF

cat > "$STUB_BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "mcp" ]; then exit 0; fi
if [ "${1:-}" = "--version" ]; then printf '%s\n' 'test-claude'; fi
exit 0
EOF

cat > "$STUB_BIN/gentle-ai" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "skill-registry" ]; then
  mkdir -p "$HOME/.atl"
  : > "$HOME/.atl/skill-registry.md"
  exit 0
fi
exit 0
EOF

chmod +x "$STUB_BIN/brew" "$STUB_BIN/claude" "$STUB_BIN/gentle-ai"

run_bootstrap() {
  local home="$1"
  HOME="$home" PATH="$STUB_BIN:$REAL_PATH" "$REPO_DIR/bootstrap.sh" --yes >/dev/null
}

installed_model() {
  jq -r '.model // empty' "$1/.claude/settings.json"
}

seed_settings() {
  local home="$1" model="$2"
  mkdir -p "$home/.claude"
  printf '{"model": "%s"}\n' "$model" > "$home/.claude/settings.json"
}

# El source versionado nunca puede traer un modelo [1m]: es lo que se instala en
# un HOME sin preferencia previa.
if grep -Eq '"model": *"[^"]*\[1m\]"' "$REPO_DIR/files/claude/settings.json"; then
  fail "files/claude/settings.json trae un modelo [1m]"
fi

# Fixture 1: preferencia con millón de contexto. Se conserva el modelo, se
# descarta el [1m]. Dos corridas para probar idempotencia.
DROP_HOME="$TMP_ROOT/home-1m"
seed_settings "$DROP_HOME" 'opus[1m]'
run_bootstrap "$DROP_HOME"
[ "$(installed_model "$DROP_HOME")" = "opus" ] \
  || fail "modelo [1m] no fue degradado a 'opus' (quedó '$(installed_model "$DROP_HOME")')"
run_bootstrap "$DROP_HOME"
[ "$(installed_model "$DROP_HOME")" = "opus" ] \
  || fail "segunda corrida no es idempotente (quedó '$(installed_model "$DROP_HOME")')"

# Fixture 2: preferencia normal. Bootstrap no la toca — el harness no elige el
# pool de cuota del usuario.
KEEP_HOME="$TMP_ROOT/home-normal"
seed_settings "$KEEP_HOME" 'opus'
run_bootstrap "$KEEP_HOME"
[ "$(installed_model "$KEEP_HOME")" = "opus" ] \
  || fail "modelo preexistente no fue preservado (quedó '$(installed_model "$KEEP_HOME")')"

# Fixture 3: HOME sin preferencia previa. Se instala el modelo del source.
CLEAN_HOME="$TMP_ROOT/home-clean"
mkdir -p "$CLEAN_HOME"
run_bootstrap "$CLEAN_HOME"
SOURCE_MODEL="$(jq -r '.model // empty' "$REPO_DIR/files/claude/settings.json")"
[ "$(installed_model "$CLEAN_HOME")" = "$SOURCE_MODEL" ] \
  || fail "HOME limpio no recibió el modelo del source (esperaba '$SOURCE_MODEL', quedó '$(installed_model "$CLEAN_HOME")')"

printf 'PASS: bootstrap conserva el modelo de Claude y descarta la variante [1m]\n'
