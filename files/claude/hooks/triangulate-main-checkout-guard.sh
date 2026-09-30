#!/usr/bin/env bash
# SessionStart + PreToolUse(Bash) — una triangulación se coordina DESDE su worktree.
#
# Incidente 2026-09-01: la triangulación RRHH (estructura-organigrama-nextgen)
# quedó coordinada por un `claude` pelado lanzado en el checkout PRINCIPAL de
# cocoa-core-backend, parado en la rama de OTRO fix (fix/819) y sin --name.
# Consecuencias: no corrió triangulate-handoff.sh (solo dispara dentro de
# .claude/worktrees/triangulate-*), la sesión no era direccionable por rol,
# despachaba Codex a los worktrees "a distancia", y cualquier git/npm sin -C
# caía en la rama equivocada. Todo eso lo evita `triangulate claude <slug>` o
# `triangulate resume <rol> <slug>`; el agujero era que nada impedía saltearlo.
#
# Dos modos, según haya tool_input o no:
#   SessionStart: si el cwd es un repo base de triangulate.conf y existen
#     worktrees triangulate-* en él, AVISA fuerte (no bloquea el arranque).
#   PreToolUse(Bash): si la sesión NO vive en un worktree triangulate-* y el
#     comando ESCRIBE dentro de uno (codex-run, git commit/push/rebase/…, npm),
#     BLOQUEA con la instrucción de relanzar. Leer (status/log/diff) sigue
#     permitido: auditar desde afuera es legítimo; escribir no.
#
# Escape consciente: TRIANGULATE_ALLOW_MAIN_CHECKOUT=1. Fail-open ante lo no parseable.

set -uo pipefail

input="$(cat 2>/dev/null || true)"   # leer stdin SIEMPRE antes de salir: evita SIGPIPE en el productor
[ "${TRIANGULATE_ALLOW_MAIN_CHECKOUT:-0}" = "1" ] && exit 0

CONFIG="${TRIANGULATE_CONFIG:-$HOME/.claude/triangulate.conf}"
DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

in_triangulate_worktree() { case "$1" in */.claude/worktrees/triangulate-*) return 0 ;; esac; return 1; }

list_open_triangulations() {
  local base d
  [ -f "$CONFIG" ] || return 0
  while IFS='=' read -r _ base; do
    [ -n "$base" ] && [ -d "$base/.claude/worktrees" ] || continue
    for d in "$base"/.claude/worktrees/triangulate-*/; do
      [ -d "$d" ] && basename "${d%/}"
    done
  done < <(grep -E '^[a-z]+=' "$CONFIG" 2>/dev/null) | sed 's/^triangulate-//' | sort -u
}

# ---------------- PreToolUse(Bash) ----------------
if printf '%s' "$input" | grep -q '"tool_input"'; then
  command -v jq >/dev/null 2>&1 || exit 0
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  [ -z "$cmd" ] && exit 0
  in_triangulate_worktree "$DIR" && exit 0
  # Texto citado es autoría, no ejecución (misma regla que deploy-checkout-guard).
  scan="$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
  printf '%s' "$scan" | grep -q '\.claude/worktrees/triangulate-' || exit 0
  printf '%s' "$scan" | grep -qE 'codex-run|codex +exec|git +(-C +[^ ]+ +)?(commit|push|rebase|reset|checkout|switch|merge|add|stash|cherry-pick)|npm +(run|install|ci)|npx |pnpm |yarn ' || exit 0
  wt="$(printf '%s' "$scan" | grep -oE '[^ ;&|"]*\.claude/worktrees/triangulate-[^ /;&|"]+' | head -1)"
  slug="$(basename "${wt:-triangulate-?}")"; slug="${slug#triangulate-}"
  cat >&2 <<MSG
BLOQUEADO (triangulate-main-checkout-guard): esta sesión vive en $DIR
y quiere ESCRIBIR en el worktree de la triangulación '$slug'.
Una triangulación se coordina DESDE su worktree, con sesión nombrada por rol:
  triangulate resume back $slug      (o front / app)
Ahí sí corre el handoff determinista, la sesión es direccionable y git/npm
caen en la rama correcta. Desde acá solo se permite leer (status/log/diff).
Escape consciente, solo con autorización del usuario: TRIANGULATE_ALLOW_MAIN_CHECKOUT=1
MSG
  exit 2
fi

# ---------------- SessionStart ----------------
in_triangulate_worktree "$DIR" && exit 0
[ -f "$CONFIG" ] || exit 0
grep -qE "^[a-z]+=${DIR}\$" "$CONFIG" || exit 0   # solo repos base de la config
open="$(list_open_triangulations | paste -sd' ' -)"
[ -n "$open" ] || exit 0
branch="$(git -C "$DIR" branch --show-current 2>/dev/null)"
cat <<MSG
⚠️ CHECKOUT PRINCIPAL, NO WORKTREE: esta sesión arrancó en $DIR (rama ${branch:-?}).
Triangulaciones abiertas en este repo: $open
Si esta sesión va a trabajar en una de ellas, NO lo hagas desde acá: cerrá y relanzá con
  triangulate resume <back|front|app> <slug>
Escribir en un worktree triangulate-* desde acá está BLOQUEADO por hook (leer sí).
MSG
exit 0
