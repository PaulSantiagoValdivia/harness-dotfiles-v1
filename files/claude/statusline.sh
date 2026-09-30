#!/usr/bin/env bash
# ~/.claude/statusline.sh
# Flutter-focused Claude Code status line

input=$(cat)

# --- Colors (ANSI escapes) ---
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
MAGENTA='\033[0;35m'
DIM='\033[2m'
RESET='\033[0m'

# --- 1. Directory (from JSON cwd, with ~ substitution) ---
cwd=$(echo "$input" | jq -r '.cwd // empty')
if [ -n "$cwd" ]; then
  home="$HOME"
  display_dir="${cwd/#$home/\~}"
else
  display_dir="~"
fi

# --- 2. Git branch (from cwd) ---
branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# --- 3. Flutter flavor (most recently modified main_*.dart) ---
flavor=""
if [ -n "$cwd" ]; then
  lib_dir="$cwd/lib"
  if [ -d "$lib_dir" ]; then
    # Find the most recently modified main_*.dart among known flavor files
    latest_file=$(ls -t \
      "$lib_dir/main_local.dart" \
      "$lib_dir/main_dev.dart" \
      "$lib_dir/main_staging.dart" \
      "$lib_dir/main_prod.dart" \
      2>/dev/null | head -1)
    case "$latest_file" in
      *main_local.dart)   flavor="LOCAL"   ;;
      *main_dev.dart)     flavor="DEV"     ;;
      *main_staging.dart) flavor="STAGING" ;;
      *main_prod.dart)    flavor="PROD"    ;;
    esac
  fi
fi

# --- 4. Model display name ---
model=$(echo "$input" | jq -r '.model.display_name // empty')

# --- 5. Centinela del enforcement "Codex escribe el código" -----------------
# Capa independiente de settings.json (2026-08-31): si un sync/edición borra
# el REGISTRO de los hooks, el hook y su validador de SessionStart mueren
# juntos sin aviso. El statusline corre en cada render y no depende de esa
# registración, así que detecta: hook ausente, hook sin parsear, o hook/
# validador desregistrados de settings.json. Chequeo barato con cache de 60s.
# El enforcement es OPT-IN del harness (bootstrap --codex-enforcement): si ni el
# hook existe ni está registrado, la máquina no lo adoptó y el centinela calla.
ENF_FLAG=""
ENF_CACHE="/tmp/claude-enforcement-check-$(id -u)"
now=$(date +%s)
cache_age=999
[ -f "$ENF_CACHE" ] && cache_age=$(( now - $(stat -f %m "$ENF_CACHE" 2>/dev/null || echo 0) ))
if [ "$cache_age" -ge 60 ]; then
  st="OK"
  HK="$HOME/.claude/hooks/route-code-to-codex.sh"
  if [ ! -f "$HK" ] && ! grep -q "route-code-to-codex" "$HOME/.claude/settings.json" 2>/dev/null; then st="OK"
  elif [ ! -f "$HK" ]; then st="SIN-HOOK"
  elif ! bash -n "$HK" 2>/dev/null; then st="HOOK-ROTO"
  elif ! grep -q "route-code-to-codex" "$HOME/.claude/settings.json" 2>/dev/null; then st="DESREGISTRADO"
  elif ! grep -q "validate-enforcement" "$HOME/.claude/settings.json" 2>/dev/null; then st="SIN-VALIDADOR"
  fi
  printf '%s' "$st" > "$ENF_CACHE" 2>/dev/null
fi
enf_state=$(cat "$ENF_CACHE" 2>/dev/null || echo OK)
[ "$enf_state" != "OK" ] && ENF_FLAG="$enf_state"

# --- 6. Contexto en juego (auditoría de consumo 2026-08-31) ----------------
# El costo real es tamaño_de_contexto x cantidad_de_requests: con 400k de
# mediana y cero compactaciones, el 84% del gasto era cache read. El hook
# context-budget.sh avisa al modelo; esto lo pone a la VISTA del usuario, que
# es quien decide el /clear. Cache de 10s: el statusline se re-renderiza mucho
# y no vale pagar un jq por frame.
CTX_FLAG=""
sid=$(echo "$input" | jq -r '.session_id // empty')
tpath=$(echo "$input" | jq -r '.transcript_path // empty')
if [ -n "$tpath" ] && [ -f "$tpath" ]; then
  CTX_CACHE="/tmp/claude-ctx-$(id -u)-${sid:-x}"
  ctx_age=999
  [ -f "$CTX_CACHE" ] && ctx_age=$(( $(date +%s) - $(stat -f %m "$CTX_CACHE" 2>/dev/null || echo 0) ))
  if [ "$ctx_age" -ge 10 ]; then
    tail -n 400 "$tpath" 2>/dev/null | jq -rs '
      [ .[] | select(type == "object") | .message.usage // empty
        | (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
      ] | last // 0' 2>/dev/null > "$CTX_CACHE" || true
  fi
  ctx=$(cat "$CTX_CACHE" 2>/dev/null || echo 0)
  case "$ctx" in ''|*[!0-9]*) ctx=0 ;; esac
  if [ "$ctx" -gt 0 ]; then
    ctx_k=$(( ctx / 1000 ))
    # Mismos umbrales que context-budget.sh: verde <120k, amarillo <180k, rojo.
    if   [ "$ctx" -ge 180000 ]; then CTX_FLAG="$(printf '\033[0;31m%sk\033[0m' "$ctx_k")"
    elif [ "$ctx" -ge 120000 ]; then CTX_FLAG="$(printf '\033[0;33m%sk\033[0m' "$ctx_k")"
    else                             CTX_FLAG="$(printf "${DIM}%sk${RESET}" "$ctx_k")"
    fi
  fi
fi

# --- 7. Carga de la máquina (auditoría 2026-09-17) ------------------------
# Doce sesiones más el runner de CI en la misma Mac: load 314 con 16 cores y
# un check:all rojo por timeouts que no eran evidencia. El contexto se veía;
# la CPU compartida no. Mismos umbrales que heavy-command-gate.sh: amarillo
# desde 1x cores, rojo desde 2x. Un sysctl por frame, sin jq.
LOAD_FLAG=""
load_raw=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')
ncpu=$(sysctl -n hw.ncpu 2>/dev/null || echo 0)
load_int="${load_raw%%.*}"
case "$load_int" in ''|*[!0-9]*) load_int="" ;; esac
case "$ncpu" in ''|*[!0-9]*) ncpu=0 ;; esac
if [ -n "$load_int" ] && [ "$ncpu" -gt 0 ]; then
  if   [ "$load_int" -ge $(( ncpu * 2 )) ]; then LOAD_FLAG="$(printf '\033[0;31m%s\033[0m' "$load_int")"
  elif [ "$load_int" -ge "$ncpu" ];         then LOAD_FLAG="$(printf '\033[0;33m%s\033[0m' "$load_int")"
  else                                            LOAD_FLAG="$(printf "${DIM}%s${RESET}" "$load_int")"
  fi
fi

# --- Assemble ---
line=""

# Directory
line="${line}$(printf "${CYAN}%s${RESET}" "$display_dir")"

# Branch
if [ -n "$branch" ]; then
  line="${line} $(printf "${YELLOW}(%s)${RESET}" "$branch")"
fi

# Flavor
if [ -n "$flavor" ]; then
  line="${line} $(printf "${MAGENTA}[%s]${RESET}" "$flavor")"
fi

# Pipe + model
if [ -n "$model" ]; then
  line="${line} $(printf "${DIM}|${RESET} %s" "$model")"
fi

# Contexto en juego
if [ -n "$CTX_FLAG" ]; then
  line="${line} $(printf "${DIM}|${RESET} ctx %b" "$CTX_FLAG")"
fi

# Carga de la máquina
if [ -n "$LOAD_FLAG" ]; then
  line="${line} $(printf "${DIM}|${RESET} load %b" "$LOAD_FLAG")"
fi

printf "%b\n" "$line"
