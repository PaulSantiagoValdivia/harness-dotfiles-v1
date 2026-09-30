#!/usr/bin/env bash
# bootstrap.sh — instala el harness standalone (Claude Code + Codex + Engram)
# según el PRD (docs/PRD.md). Idempotente: hace backup antes de sobrescribir.
#
# Uso:
#   ./bootstrap.sh              # interactivo
#   ./bootstrap.sh --yes        # acepta defaults sin preguntar
#   ./bootstrap.sh --no-bypass  # instala settings.json con defaultMode "default"
#                               # en vez de bypassPermissions (recomendado si la
#                               # máquina destino no es del owner original)
#   ./bootstrap.sh --codex-enforcement
#                               # OPT-IN: "Codex escribe TODO el código". Instala y
#                               # registra route-code-to-codex.sh + validate-enforcement.sh,
#                               # anexa el bloque OVERRIDE a CLAUDE.md y el bloque
#                               # "Code routing" a los agents SDD. Sin la flag, Claude
#                               # escribe código y esos dos hooks se retiran si existían.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$REPO_DIR/files"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.harness-backup-$TS"
ASSUME_YES=0
NO_BYPASS=0
CODEX_ENFORCEMENT=0

for arg in "$@"; do
  case "$arg" in
    --yes) ASSUME_YES=1 ;;
    --no-bypass) NO_BYPASS=1 ;;
    --codex-enforcement) CODEX_ENFORCEMENT=1 ;;
    *) echo "Flag desconocida: $arg" >&2; exit 2 ;;
  esac
done

log()  { printf '\033[0;36m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[aviso]\033[0m %s\n' "$*"; }
fail() { printf '\033[0;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

confirm() { # confirm "pregunta" -> 0 si sí
  [ "$ASSUME_YES" = 1 ] && return 0
  read -r -p "$1 [s/N] " ans
  case "$ans" in [sS]|[sS][iI]) return 0 ;; *) return 1 ;; esac
}

backup() { # backup <ruta> — mueve una copia al dir de backup si existe
  local src="$1"
  if [ -e "$src" ]; then
    mkdir -p "$BACKUP_DIR$(dirname "$src")"
    cp -a "$src" "$BACKUP_DIR$src"
  fi
}

# ── 1. Prerequisitos ─────────────────────────────────────────────────────────
ARCH="$(uname -m)"
log "Arquitectura: $ARCH"

command -v brew >/dev/null 2>&1 || fail "Homebrew no está instalado (https://brew.sh). Instalalo y reintentá."
BREW_PREFIX="$(brew --prefix)"
log "Prefix de Homebrew: $BREW_PREFIX"

for pkg in jq codex engram gentle-ai; do
  if ! command -v "$pkg" >/dev/null 2>&1; then
    if confirm "Falta '$pkg'. ¿Instalar via Homebrew?"; then
      # codex se distribuye como cask; los demás como formula
      brew install "$pkg" || brew install --cask "$pkg"
    else
      fail "'$pkg' es requerido (PRD R1–R3)."
    fi
  fi
done

if ! command -v claude >/dev/null 2>&1; then
  warn "Falta 'claude' (Claude Code). Instalalo con el instalador oficial:"
  warn "  curl -fsSL https://claude.ai/install.sh | bash"
  fail "Instalá Claude Code y volvé a correr este script."
fi

# Gotcha real del origen (PRD §9): binarios de arquitectura equivocada tras migración.
for bin in claude codex engram; do
  p="$(command -v "$bin" 2>/dev/null)" || { warn "'$bin' desapareció del PATH tras la instalación"; continue; }
  if file -L "$p" | grep -qE 'shell script|script text executable'; then
    "$bin" --version >/dev/null 2>&1 || fail "El launcher '$p' existe pero '$bin --version' falla"
    log "'$p' es un launcher de shell funcional; la arquitectura la resuelve su runtime"
    continue
  fi
  # 'file -L' sigue symlinks (los kegs de brew instalan symlinks en bin/)
  if ! file -L "$p" | grep -q "$ARCH"; then
    warn "'$p' no parece ser nativo $ARCH: $(file -L "$p" | cut -d: -f2)"
    confirm "¿Continuar igual?" || exit 1
  fi
done

CODEX_BIN="$(command -v codex)"
ENGRAM_BIN="$(command -v engram)"

# Capture user-owned model choices BEFORE Gentle AI runs. The installer may
# update config files as part of a preset; reading them afterward would preserve
# the installer's temporary defaults instead of the user's actual preferences.
CLAUDE_MODEL=""
CODEX_MODEL=""
CODEX_REASONING_EFFORT=""
if [ -f "$HOME/.claude/settings.json" ]; then
  CLAUDE_MODEL="$(jq -r '.model // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)"
fi
if [ -f "$HOME/.codex/config.toml" ]; then
  CODEX_MODEL="$(awk '/^\[/{exit} /^model[[:space:]]*=/{v=$0; sub(/^[^=]+=[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); print v; exit}' "$HOME/.codex/config.toml")"
  CODEX_REASONING_EFFORT="$(awk '/^\[/{exit} /^model_reasoning_effort[[:space:]]*=/{v=$0; sub(/^[^=]+=[[:space:]]*"/, "", v); sub(/"[[:space:]]*$/, "", v); print v; exit}' "$HOME/.codex/config.toml")"
fi

# Gentle AI es el instalador real de persona, SDD, comandos y skills para ambos
# clientes. Se ejecuta primero; los archivos versionados de abajo son overlays
# del harness (presupuesto, workflows y settings), no una segunda instalación.
log "Sincronizando Gentle AI para Claude Code + Codex (SDD multi-agent)"
# Engram puede preguntar si añade una allowlist. El harness no auto-aprueba
# permisos; stdin cerrado elige "no". Algunas versiones devuelven non-zero aun
# después de instalar por esa respuesta, por lo que verify.sh valida el estado.
if ! gentle-ai install \
  --scope global \
  --agents claude-code,codex \
  --preset full-gentleman \
  --sdd-mode multi </dev/null; then
  warn "Gentle AI terminó con advertencia; continúo con overlays y verify.sh validará componentes."
fi

# ── 2. Claude Code (~/.claude) ───────────────────────────────────────────────
log "Instalando artefactos de Claude Code (backup en $BACKUP_DIR)"
mkdir -p "$HOME/.claude"
for item in CLAUDE.md settings.json statusline.sh workflows; do
  backup "$HOME/.claude/$item"
  rm -rf "$HOME/.claude/$item"
  cp -a "$FILES/claude/$item" "$HOME/.claude/$item"
done
chmod +x "$HOME/.claude/statusline.sh"

# Hooks del harness: TODOS los de files/claude/hooks, con su suite de contrato
# (hooks/tests). Cada uno nace de un incidente real documentado en su cabecera.
# Los dos del enforcement "Codex escribe el código" son OPT-IN (--codex-enforcement):
# sin la flag no se instalan y, si existían de una instalación anterior, se retiran
# para que el estado en disco coincida con settings.json (un hook presente pero
# desregistrado es exactamente lo que el centinela del statusline denuncia).
ENFORCEMENT_HOOKS="route-code-to-codex.sh validate-enforcement.sh"
mkdir -p "$HOME/.claude/hooks/tests" "$HOME/.claude/bin"
for hook in "$FILES"/claude/hooks/*.sh; do
  name="$(basename "$hook")"
  case " $ENFORCEMENT_HOOKS " in *" $name "*) [ "$CODEX_ENFORCEMENT" = 1 ] || continue ;; esac
  backup "$HOME/.claude/hooks/$name"
  cp -a "$hook" "$HOME/.claude/hooks/$name"
  chmod +x "$HOME/.claude/hooks/$name"
done
cp -a "$FILES"/claude/hooks/tests/*.sh "$HOME/.claude/hooks/tests/"
if [ "$CODEX_ENFORCEMENT" = 0 ]; then
  for name in $ENFORCEMENT_HOOKS; do
    if [ -f "$HOME/.claude/hooks/$name" ]; then
      backup "$HOME/.claude/hooks/$name"
      rm -f "$HOME/.claude/hooks/$name"
      log "Retirado $name (enforcement Codex no adoptado; --codex-enforcement para activarlo)"
    fi
  done
fi
log "Hooks instalados: $(ls "$HOME/.claude/hooks/"*.sh | wc -l | tr -d ' ') (+ suite en hooks/tests)"

# Launchers del harness: codex-run (codex sin el shim de cmux, stdin cerrado y
# timeout duro — incidente 2026-08-30) y apply-agent-patches.sh (ver abajo).
for b in codex-run apply-agent-patches.sh; do
  backup "$HOME/.claude/bin/$b"
  cp -a "$FILES/claude/bin/$b" "$HOME/.claude/bin/$b"
  chmod +x "$HOME/.claude/bin/$b"
done
# codex-run trae el binario real hardcodeado (PRD R11); se apunta al de esta máquina.
if [ "$CODEX_BIN" != "/usr/local/bin/codex" ]; then
  log "Parcheando binario en codex-run: /usr/local/bin/codex -> $CODEX_BIN"
  sed -i '' "s|/usr/local/bin/codex|$CODEX_BIN|g" "$HOME/.claude/bin/codex-run"
fi

# Parches versionados sobre lo que genera gentle-ai (agents/skills). Se copian
# enteros: apply-agent-patches.sh los lee de ~/.claude/patches en cada SessionStart.
backup "$HOME/.claude/patches"
rm -rf "$HOME/.claude/patches"
cp -a "$FILES/claude/patches" "$HOME/.claude/patches"
mkdir -p "$HOME/.claude/patches/codex"
cp -a "$FILES/codex/AGENTS.md" "$HOME/.claude/patches/codex/AGENTS.md"

# Config de triangulación: rutas por máquina, nunca se sobrescribe si ya existe.
if [ ! -f "$HOME/.claude/triangulate.conf" ]; then
  cp "$FILES/claude/triangulate.conf.example" "$HOME/.claude/triangulate.conf"
  warn "Creado ~/.claude/triangulate.conf desde el ejemplo: EDITALO con las rutas reales de back/front/app"
fi

# El modelo es una preferencia/capacidad de la cuenta, no una pieza portable del
# harness. Conservar la selección existente evita cambiar de pool de cuota al
# sincronizar el resto de la configuración.
#
# La variante [1m] es la excepción: saca el techo de contexto que fuerza la
# compactación, y verify.sh la declara FAIL. Preservarla dejaría a bootstrap
# reinstalando en cada corrida un estado que su propia verificación rechaza. Se
# conserva el modelo, se descarta el millón; se pide por sesión con /model.
if [ -n "$CLAUDE_MODEL" ]; then
  case "$CLAUDE_MODEL" in
    *"[1m]")
      CLAUDE_MODEL="${CLAUDE_MODEL%\[1m\]}"
      warn "settings.json tenía un modelo [1m]: se conserva '$CLAUDE_MODEL' sin el millón de contexto (pedilo por sesión con /model)"
      ;;
  esac
  tmp="$(mktemp)"
  jq --arg model "$CLAUDE_MODEL" '.model = $model' \
    "$HOME/.claude/settings.json" > "$tmp" && mv "$tmp" "$HOME/.claude/settings.json"
fi

# Decisión de permisos (PRD §6.2): bypassPermissions NO es un default neutro.
if [ "$NO_BYPASS" = 0 ] && [ "$ASSUME_YES" = 0 ]; then
  echo
  echo "settings.json trae defaultMode=bypassPermissions + skipDangerousModePermissionPrompt=true."
  echo "Eso auto-aprueba casi todas las acciones (mitigado solo por la deny-list)."
  confirm "¿Conservar bypassPermissions? (N = cambiar a modo 'default')" || NO_BYPASS=1
fi
if [ "$NO_BYPASS" = 1 ]; then
  log "Cambiando defaultMode a 'default' y desactivando skipDangerousModePermissionPrompt"
  tmp="$(mktemp)"
  jq '.permissions.defaultMode = "default" | del(.skipDangerousModePermissionPrompt)' \
    "$HOME/.claude/settings.json" > "$tmp" && mv "$tmp" "$HOME/.claude/settings.json"
fi

# Los workflows ya no embeben el binario de codex: invocan ~/.claude/bin/codex-run,
# que es el que se parchea arriba (PRD R11 se cumple en un solo lugar).

# ── 2b. Enforcement "Codex escribe el código" (opt-in) ──────────────────────
if [ "$CODEX_ENFORCEMENT" = 1 ]; then
  log "Activando enforcement Codex: hooks registrados + OVERRIDE en CLAUDE.md"
  tmp="$(mktemp)"
  jq '
    .hooks.PreToolUse = ([{matcher:"Edit|Write|NotebookEdit|Bash",
                           hooks:[{type:"command", command:"bash ~/.claude/hooks/route-code-to-codex.sh"}]}]
                         + (.hooks.PreToolUse // []))
    | .hooks.SessionStart = ((.hooks.SessionStart // [])
                         + [{matcher:"startup|clear",
                             hooks:[{type:"command", command:"bash ~/.claude/hooks/validate-enforcement.sh"}]}])
  ' "$HOME/.claude/settings.json" > "$tmp" && mv "$tmp" "$HOME/.claude/settings.json"
  if ! grep -q 'user-override:codex-writes-code' "$HOME/.claude/CLAUDE.md"; then
    { echo; cat "$FILES/claude/patches/claude-md-codex-override.md"; } >> "$HOME/.claude/CLAUDE.md"
  fi
  bash "$HOME/.claude/hooks/tests/route-hook-tests.sh" >/dev/null 2>&1 \
    || warn "La suite de contrato de route-code-to-codex.sh falló; revisá con: bash ~/.claude/hooks/tests/route-hook-tests.sh"
fi

# ── 2c. Parches sobre los agents/skills generados por gentle-ai ─────────────
# gentle-ai 3.7 declara los tools de memoria con AMBOS prefijos: plugin
# (mcp__plugin_engram_engram__*) y directo (mcp__engram__*); por eso se convierten
# al prefijo directo y se deduplican. Idempotente; también corre en cada SessionStart.
if [ "$CODEX_ENFORCEMENT" = 1 ]; then
  bash "$HOME/.claude/bin/apply-agent-patches.sh" --codex-routing
else
  bash "$HOME/.claude/bin/apply-agent-patches.sh" --no-codex-routing
fi

# Claude and Codex are independent first-class runtimes. Older Conductor-era
# installs routed every Claude edit through a Codex MCP that could fail closed
# and block otherwise healthy Claude sessions. Remove only that managed legacy
# server; users can still invoke Codex directly in a separate worktree session.
if claude mcp list 2>/dev/null | grep -q '^codex:'; then
  log "Retirando MCP legacy 'codex' de Claude (runtimes standalone independientes)"
  claude mcp remove --scope user codex >/dev/null 2>&1 || \
    warn "No se pudo retirar el MCP legacy 'codex'; removelo con: claude mcp remove -s user codex"
fi

# Engram directo, igual que en Codex. El plugin queda deshabilitado porque sus
# hooks inyectan protocolo + contexto en cada sesión y duplican CLAUDE.md.
if claude mcp list 2>/dev/null | grep -q '^engram:'; then
  log "MCP 'engram' ya registrado en Claude Code"
else
  log "Registrando MCP 'engram' directo (scope user, contexto bajo demanda)"
  claude mcp add --scope user engram -- "$ENGRAM_BIN" mcp --tools=agent
fi

# ── 3. Codex (~/.codex) ──────────────────────────────────────────────────────
log "Configurando Codex"
mkdir -p "$HOME/.codex"
for f in AGENTS.md engram-instructions.md engram-compact-prompt.md; do
  backup "$HOME/.codex/$f"
  cp -a "$FILES/codex/$f" "$HOME/.codex/$f"
done

# Triangulation is one shared runtime contract installed in both clients. It
# deliberately uses native live channels (Claude peer/team messaging or Codex
# spawned-agent mailboxes) and reserves Engram for durable recovery.
TRIANGULATION_SKILL="$FILES/shared/skills/triangulation-orchestrator"
for client_home in "$HOME/.claude" "$HOME/.codex"; do
  skill_dest="$client_home/skills/triangulation-orchestrator"
  backup "$skill_dest"
  rm -rf "$skill_dest"
  mkdir -p "$(dirname "$skill_dest")"
  cp -a "$TRIANGULATION_SKILL" "$skill_dest"
done
log "Skill de triangulación automática instalado con paridad Claude/Codex"

# BEGIN harness-evidence installation
# shellcheck source=files/shared/lib/install-shared-skill.sh
source "$FILES/shared/lib/install-shared-skill.sh"
install_shared_skill "$FILES/shared/skills/harness-evidence" "$HOME" "$BACKUP_DIR"
# END harness-evidence installation

# Launcher único para iniciar la misma triangulación desde Claude o Codex.
# Claude abre tres sesiones nombradas; Codex crea los tres worktrees pero abre
# un solo primary con dos agent threads, que es la única topología con mailbox,
# reasignación y consolidación nativos en Codex.
TRIANGULATE_SOURCE="$FILES/shared/bin/triangulate"
TRIANGULATE_DEST="$HOME/.local/bin/triangulate"
backup "$TRIANGULATE_DEST"
mkdir -p "$(dirname "$TRIANGULATE_DEST")"
cp "$TRIANGULATE_SOURCE" "$TRIANGULATE_DEST"
chmod +x "$TRIANGULATE_DEST"
log "Launcher instalado: triangulate claude|codex <feature-slug>"

# env-has-key: presencia de claves en un .env SIN leer valores. Claude tiene
# prohibido leer .env* (deny en settings.json); sin esto, dos sesiones infieren
# por tamaño y fecha si un secreto está cargado y le preguntan al usuario lo
# que ya hizo (2026-09-18).
ENV_HAS_KEY_SOURCE="$FILES/shared/bin/env-has-key"
ENV_HAS_KEY_DEST="$HOME/.local/bin/env-has-key"
backup "$ENV_HAS_KEY_DEST"
cp "$ENV_HAS_KEY_SOURCE" "$ENV_HAS_KEY_DEST"
chmod +x "$ENV_HAS_KEY_DEST"
log "Helper instalado: env-has-key <archivo.env> KEY..."

# claude-sessions muestra qué sesiones están vivas, dónde viven y cuánto
# contexto paga cada turno suyo. Vivió sin versionar hasta el 2026-09-03 y por
# eso se pudrió sin que nadie lo notara: reportaba el cwd y la inactividad a
# partir de datos que no los medían. Versionado, verify.sh detecta el drift.
CLAUDE_SESSIONS_SOURCE="$FILES/shared/bin/claude-sessions"
CLAUDE_SESSIONS_DEST="$HOME/.local/bin/claude-sessions"
backup "$CLAUDE_SESSIONS_DEST"
mkdir -p "$(dirname "$CLAUDE_SESSIONS_DEST")"
cp "$CLAUDE_SESSIONS_SOURCE" "$CLAUDE_SESSIONS_DEST"
chmod +x "$CLAUDE_SESSIONS_DEST"
log "Inspector instalado: claude-sessions [--watch|--porcelain]"

# La memoria de archivos cambia con el uso diario. Antes de que un proceso
# automático proponga tocarla, este snapshot deja un rollback Git estrictamente
# local: no configura remotes y nunca hace push ni fetch.
MEMORY_SNAPSHOT_SOURCE="$FILES/shared/bin/memory-snapshot"
MEMORY_SNAPSHOT_DEST="$HOME/.local/bin/memory-snapshot"
backup "$MEMORY_SNAPSHOT_DEST"
cp "$MEMORY_SNAPSHOT_SOURCE" "$MEMORY_SNAPSHOT_DEST"
chmod +x "$MEMORY_SNAPSHOT_DEST"
log "Snapshot local instalado: memory-snapshot [--dry-run]"

# El linter es la barrera read-only entre una propuesta automática y la memoria
# real. Se instala como copia auditable, con backup igual que el resto de los
# ejecutables administrados por este bootstrap.
MEMORY_LINT_SOURCE="$FILES/shared/bin/memory-lint"
MEMORY_LINT_DEST="$HOME/.local/bin/memory-lint"
backup "$MEMORY_LINT_DEST"
cp "$MEMORY_LINT_SOURCE" "$MEMORY_LINT_DEST"
chmod +x "$MEMORY_LINT_DEST"
log "Validador instalado: memory-lint [--baseline BASE_DIR] [--json] [DIR]"

# El consolidador sólo propone en worktrees; aplicar sigue siendo una acción manual.
MEMORY_CONSOLIDATE_SOURCE="$FILES/shared/bin/memory-consolidate"
MEMORY_CONSOLIDATE_DEST="$HOME/.local/bin/memory-consolidate"
backup "$MEMORY_CONSOLIDATE_DEST"
cp "$MEMORY_CONSOLIDATE_SOURCE" "$MEMORY_CONSOLIDATE_DEST"
chmod +x "$MEMORY_CONSOLIDATE_DEST"
log "Consolidador instalado: memory-consolidate propose|review|apply|discard|status"

# El job nocturno sólo propone y se saltea si hay una propuesta pendiente. El
# plist se instala siempre; __HOME__ se renderiza porque launchd no expande
# variables en rutas ni hereda el PATH del shell.
MEMORY_CONSOLIDATE_PLIST_SOURCE="$FILES/shared/launchd/com.cocoa.memory-consolidate.plist"
MEMORY_CONSOLIDATE_PLIST_DEST="$HOME/Library/LaunchAgents/com.cocoa.memory-consolidate.plist"
backup "$MEMORY_CONSOLIDATE_PLIST_DEST"
mkdir -p "$(dirname "$MEMORY_CONSOLIDATE_PLIST_DEST")" "$HOME/Library/Logs"
sed "s|__HOME__|$HOME|g" "$MEMORY_CONSOLIDATE_PLIST_SOURCE" > "$MEMORY_CONSOLIDATE_PLIST_DEST"

# launchctl es global y no respeta HOME. Con fixtures se instala el archivo para
# verificarlo, pero NUNCA se toca el dominio launchd real del usuario.
REAL_HOME="$(eval echo "~$(id -un)")"
if [ "$HOME" = "$REAL_HOME" ]; then
  launchctl unload "$MEMORY_CONSOLIDATE_PLIST_DEST" >/dev/null 2>&1 || true
  if launchctl load "$MEMORY_CONSOLIDATE_PLIST_DEST"; then
    log "Consolidador nocturno activo: propone a las 03:30 si no hay otra propuesta"
  else
    log "AVISO: el plist del consolidador quedó instalado pero launchctl load falló; cargalo a mano"
  fi
else
  log "HOME de prueba ($HOME): plist del consolidador instalado pero NO cargado en launchd (es global)"
fi

# El vigilante cubre el único agujero que ninguna otra barrera puede ver:
# context-budget.sh corre en UserPromptSubmit, o sea sólo cuando el usuario
# escribe, y una sesión abandonada no escribe nunca más. Avisa por PESADA Y
# QUIETA; no mata, no cierra, no compacta nada.
CLAUDE_SESSIONS_WATCH_SOURCE="$FILES/shared/bin/claude-sessions-watch"
CLAUDE_SESSIONS_WATCH_DEST="$HOME/.local/bin/claude-sessions-watch"
backup "$CLAUDE_SESSIONS_WATCH_DEST"
cp "$CLAUDE_SESSIONS_WATCH_SOURCE" "$CLAUDE_SESSIONS_WATCH_DEST"
chmod +x "$CLAUDE_SESSIONS_WATCH_DEST"

# launchd no expande variables en las rutas del plist: __HOME__ se sustituye acá.
CLAUDE_SESSIONS_PLIST_SOURCE="$FILES/shared/launchd/com.cocoa.claude-sessions-watch.plist"
CLAUDE_SESSIONS_PLIST_DEST="$HOME/Library/LaunchAgents/com.cocoa.claude-sessions-watch.plist"
backup "$CLAUDE_SESSIONS_PLIST_DEST"
mkdir -p "$(dirname "$CLAUDE_SESSIONS_PLIST_DEST")" "$HOME/Library/Logs"
sed "s|__HOME__|$HOME|g" "$CLAUDE_SESSIONS_PLIST_SOURCE" > "$CLAUDE_SESSIONS_PLIST_DEST"
# GUARDA OBLIGATORIA: `launchctl` es GLOBAL y no respeta $HOME. Los tests corren
# bootstrap con un HOME temporal, así que sin esta guarda cada `verify.sh`
# descargaba el vigilante real del usuario y cargaba en su lugar uno apuntando a
# un tmpdir que el test borra al terminar — dejando un LaunchAgent cargado que
# apunta a un ejecutable inexistente. Verificado el 2026-09-03: `launchctl list
# com.cocoa.claude-sessions-watch` mostraba Program en
# `bootstrap-claude-model-test.*/home-clean/.local/bin/`. El plist en disco se
# veía perfecto; lo cargado no lo era.
#
# El plist se instala siempre (es un archivo dentro de $HOME, sin efecto global);
# sólo la carga se saltea cuando el HOME no es el del usuario real.
if [ "$HOME" = "$REAL_HOME" ]; then
  # Recargar, no sólo cargar: si ya estaba, un `load` a secas no toma los cambios.
  # El unload puede fallar legítimamente (no estaba cargado) y ese fallo se
  # descarta a propósito; no se saca ninguna conclusión de su silencio.
  launchctl unload "$CLAUDE_SESSIONS_PLIST_DEST" >/dev/null 2>&1 || true
  if launchctl load "$CLAUDE_SESSIONS_PLIST_DEST"; then
    log "Vigilante activo: claude-sessions-watch cada 30 min (avisa por pesada+quieta)"
  else
    log "AVISO: el plist quedó instalado pero launchctl load falló; cargalo a mano"
  fi
else
  log "HOME de prueba ($HOME): plist instalado pero NO cargado en launchd (es global)"
fi

# Cocoa DevTools is the local QA cockpit shared by both standalone runtimes.
# Its repository inventory comes from the same triangulate.conf used by the
# launcher, so no project path has to be entered again in the browser.
DEVTOOLS_SERVER_SOURCE="$FILES/shared/devtools/cocoa-devtools.py"
DEVTOOLS_HTML_SOURCE="$FILES/shared/devtools/cocoa-reference.html"
DEVTOOLS_SERVER_DEST="$HOME/Documents/cocoa-devtools.py"
DEVTOOLS_HTML_DEST="$HOME/Documents/cocoa-reference.html"
DEVTOOLS_LAUNCHER_SOURCE="$FILES/shared/bin/devtools"
DEVTOOLS_LAUNCHER_DEST="$HOME/.local/bin/devtools"
for dest in "$DEVTOOLS_SERVER_DEST" "$DEVTOOLS_HTML_DEST" "$DEVTOOLS_LAUNCHER_DEST"; do
  backup "$dest"
done
mkdir -p "$HOME/Documents" "$(dirname "$DEVTOOLS_LAUNCHER_DEST")"
cp "$DEVTOOLS_SERVER_SOURCE" "$DEVTOOLS_SERVER_DEST"
cp "$DEVTOOLS_HTML_SOURCE" "$DEVTOOLS_HTML_DEST"
cp "$DEVTOOLS_LAUNCHER_SOURCE" "$DEVTOOLS_LAUNCHER_DEST"
chmod +x "$DEVTOOLS_SERVER_DEST" "$DEVTOOLS_LAUNCHER_DEST"
log "Cocoa DevTools instalado: devtools (auditoría QA de backend, panel y app)"

if [ -f "$HOME/.codex/config.toml" ]; then
  backup "$HOME/.codex/config.toml"
  log "Config Codex existente respaldada; se preservan modelo, secrets, proyectos y roles"
else
  cat > "$HOME/.codex/config.toml" <<EOF
model_instructions_file = "$HOME/.codex/engram-instructions.md"
experimental_compact_prompt_file = "$HOME/.codex/engram-compact-prompt.md"
model = "gpt-6-astra"
model_reasoning_effort = "medium"
approval_policy = "never"
sandbox_mode = "danger-full-access"

[mcp_servers.engram]
command = "$ENGRAM_BIN"
args = ["mcp", "--tools=agent"]
EOF
  log "Generado ~/.codex/config.toml (engram: $ENGRAM_BIN). Los [projects] trusted se agregan al abrir cada repo."
fi

# Estas dos rutas son root settings. Si faltan, deben insertarse ANTES de la
# primera tabla TOML; anexarlas al final las convertiría en campos de la última
# tabla y rompería silenciosamente la carga del overlay.
codex_root_has_key() {
  awk -v key="$1" '
    /^\[/ { exit }
    $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$HOME/.codex/config.toml"
}

ensure_codex_root_string() {
  local key="$1" value="$2" tmp
  codex_root_has_key "$key" && return 0
  tmp="$(mktemp)"
  awk -v line="$key = \"$value\"" '
    !inserted && /^\[/ { print line; print ""; inserted=1 }
    { print }
    END { if (!inserted) print line }
  ' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
}

ensure_codex_root_string model_instructions_file "$HOME/.codex/engram-instructions.md"
ensure_codex_root_string experimental_compact_prompt_file "$HOME/.codex/engram-compact-prompt.md"
log "Rutas de instrucciones Codex presentes (sin sobrescribir valores existentes)"

set_codex_root_string() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v line="$key = \"$value\"" '
    BEGIN { in_root=1 }
    in_root && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      if (!done) print line
      done=1
      next
    }
    !inserted && /^\[/ {
      if (!done) { print line; print ""; done=1 }
      inserted=1
      in_root=0
    }
    { print }
    END {
      if (!done) print line
    }
  ' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
}

[ -n "$CODEX_MODEL" ] && set_codex_root_string model "$CODEX_MODEL"
set_codex_root_string model_reasoning_effort "${CODEX_REASONING_EFFORT:-medium}"
set_codex_root_string approval_policy "never"
set_codex_root_string sandbox_mode "danger-full-access"
log "Preferencias Codex restauradas (modelo=${CODEX_MODEL:-instalador}, effort=${CODEX_REASONING_EFFORT:-medium})"
warn "Codex queda con acceso completo y sin aprobaciones por preferencia explícita del owner"

# El MCP directo es la única ruta activa de Engram en Codex. Se gestiona en
# toda instalación, incluso si Gentle AI no creó el plugin/config previamente.
if ! grep -q '^\[mcp_servers\.engram\]$' "$HOME/.codex/config.toml"; then
  cat >> "$HOME/.codex/config.toml" <<EOF

[mcp_servers.engram]
command = "$ENGRAM_BIN"
args = ["mcp", "--tools=agent"]
EOF
else
  tmp="$(mktemp)"
  awk -v command="$ENGRAM_BIN" '
    function emit_missing() {
      if (!seen_command) print "command = \"" command "\""
      if (!seen_args) print "args = [\"mcp\", \"--tools=agent\"]"
    }
    /^\[mcp_servers\.engram\]$/ { in_mcp=1; seen_command=seen_args=0; print; next }
    /^\[/ && in_mcp { emit_missing(); in_mcp=0 }
    in_mcp && /^command[[:space:]]*=/ {
      if (!seen_command) print "command = \"" command "\""
      seen_command=1
      next
    }
    in_mcp && /^args[[:space:]]*=/ {
      if (!seen_args) print "args = [\"mcp\", \"--tools=agent\"]"
      seen_args=1
      next
    }
    { print }
    END { if (in_mcp) emit_missing() }
  ' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
fi
log "MCP Engram directo instalado en Codex ($ENGRAM_BIN)"

# Codex merges the global config with a repository-scoped .codex/config.toml.
# Cocoa's panel already declares Context7 as stdio. Gentle AI may install the
# same server globally as streamable HTTP; merging both tables produces an
# impossible hybrid (command + url) and every skills/list force reload fails.
# Keep one transport contract everywhere: the same stdio launcher used by the
# panel and Claude's .mcp.json.
tmp="$(mktemp)"
awk '
  function emit_context7() {
    print "[mcp_servers.context7]"
    print "command = \"npx\""
    print "args = [\"-y\", \"@upstash/context7-mcp@latest\"]"
    emitted=1
  }
  /^\[mcp_servers\.context7(\.|\])/{
    if (!emitted) emit_context7()
    skipping=1
    next
  }
  skipping && /^\[/ { skipping=0 }
  skipping { next }
  { print }
  END {
    if (!emitted) {
      print ""
      emit_context7()
    }
  }
' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
log "MCP Context7 normalizado a un único transporte stdio compatible con configs por repo"

# Current supported Codex releases accept scalar settings in the root [agents]
# table. Pin the hard per-primary ceiling to two while preserving custom roles
# under [agents.<role>]. This does NOT limit separate top-level worktree sessions.
tmp="$(mktemp)"
awk '
  function emit_agents() {
    print "[agents]"
    print "enabled = true"
    print "max_concurrent_threads_per_session = 2"
    print "default_subagent_reasoning_effort = \"low\""
    emitted=1
  }
  /^\[agents\]$/ {
    if (!emitted) emit_agents()
    in_agents=1
    next
  }
  /^\[/ && in_agents { in_agents=0 }
  in_agents && /^(enabled|max_concurrent_threads_per_session|max_threads|max_depth|default_subagent_reasoning_effort)[[:space:]]*=/ { next }
  !emitted && /^\[agents\./ { emit_agents(); print "" }
  { print }
  END {
    if (!emitted) {
      print ""
      emit_agents()
    }
  }
' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
log "Codex configurado con máximo 2 subagentes por sesión; roles personalizados preservados"

# Gentle AI instala el plugin Engram para conservar marketplace/actualizaciones.
# El harness lo deja instalado pero deshabilitado: el MCP directo ya provee las
# mismas tools y evita ejecutar por duplicado hooks de inicio/prompt/stop.
if ! grep -q '^\[plugins\."engram@engram"\]$' "$HOME/.codex/config.toml"; then
  cat >> "$HOME/.codex/config.toml" <<'EOF'

[plugins."engram@engram"]
enabled = false
EOF
else
  tmp="$(mktemp)"
  awk '
    /^\[plugins\."engram@engram"\]$/ { in_plugin=1; seen_enabled=0; print; next }
    /^\[/ && in_plugin { if (!seen_enabled) print "enabled = false"; in_plugin=0 }
    in_plugin && /^enabled[[:space:]]*=/ { print "enabled = false"; seen_enabled=1; next }
    { print }
    END { if (in_plugin && !seen_enabled) print "enabled = false" }
  ' "$HOME/.codex/config.toml" > "$tmp" && mv "$tmp" "$HOME/.codex/config.toml"
  log "Plugin Engram de Codex instalado pero deshabilitado (MCP directo único)"
fi

# Preserve generated Codex hooks; install producer after upstream/config overlays.
python3 "$FILES/shared/lib/install-registry-hooks.py" "$HOME" "$BACKUP_DIR/registry-hooks"

# ── 4. Skill registry ────────────────────────────────────────────────────────
if command -v gentle-ai >/dev/null 2>&1; then
  log "Generando skill registry"
  (cd "$HOME" && gentle-ai skill-registry refresh --force --no-gitignore) || warn "skill-registry refresh falló; revisá gentle-ai"
fi

# ── 5. Pasos manuales ────────────────────────────────────────────────────────
echo
log "Bootstrap terminado. Backup de lo sobrescrito: $BACKUP_DIR"
cat <<'EOF'

PASOS MANUALES RESTANTES (PRD §7):
  1. Login: correr 'claude' (cuenta Claude Pro propia) y 'codex' (cuenta Codex Plus propia).
  2. Plugins user-scope: en Claude Code -> /plugin -> instalar:
       swift-lsp@claude-plugins-official · code-simplifier@claude-plugins-official
     Engram usa MCP directo en Claude y Codex. NO habilitar engram@engram: sus hooks
     volverían a inyectar contexto y duplicar la memoria.
  3. Modelo: ajustar con /model según la cuenta y el costo/latencia deseados.
  4. Verificar todo: ./verify.sh
  5. Triangulación desde una terminal de cmux:
       triangulate claude <feature-slug>
       triangulate codex  <feature-slug>
     Codex crea tres worktrees pero abre un primary + dos agent threads. No
     abre tres top-level sin mensajería peer-to-peer.
  6. Auditoría QA e integración consolidada a dev: ejecutar 'devtools'.
EOF
