#!/usr/bin/env bash
# Suite de contrato de triangulate-main-checkout-guard.sh:
# "una triangulación se coordina DESDE su worktree". Correla tras editar el hook:
#   bash ~/.claude/hooks/tests/triangulate-guard-tests.sh
set -uo pipefail
HOOK="${1:-$HOME/.claude/hooks/triangulate-main-checkout-guard.sh}"
[ -f "$HOOK" ] || { echo "FATAL: no existe $HOOK" >&2; exit 3; }
bash -n "$HOOK" || { echo "FATAL: $HOOK no parsea" >&2; exit 3; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BASE="$T/repo"; WT="$BASE/.claude/worktrees/triangulate-demo"
mkdir -p "$WT"; git -C "$BASE" init -q 2>/dev/null || true
export TRIANGULATE_CONFIG="$T/conf"; printf 'back=%s\n' "$BASE" > "$TRIANGULATE_CONFIG"
unset TRIANGULATE_ALLOW_MAIN_CHECKOUT
fails=0; total=0
payload() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
check() { # nombre project_dir comando exit_esperado
  local rc; printf '%s' "$(payload "$3")" | CLAUDE_PROJECT_DIR="$2" bash "$HOOK" >/dev/null 2>&1; rc=$?
  total=$((total+1)); [ "$rc" = "$4" ] || { fails=$((fails+1)); echo "FALLA: $1 (exit=$rc esperado=$4)" >&2; }
}
check "codex-run al worktree desde base: bloquea"      "$BASE" "cd $WT && ~/.claude/bin/codex-run exec -m x 'foo'" 2
check "git -C commit en worktree desde base: bloquea"  "$BASE" "git -C $WT commit -m wip" 2
check "git push desde cd worktree, base: bloquea"      "$BASE" "cd $WT && git push -u origin x" 2
check "npm run test en worktree desde base: bloquea"   "$BASE" "cd $WT && npm run test" 2
check "desde HOME suelto también bloquea"              "$HOME" "cd $WT && git rebase origin/dev" 2
check "git status en worktree desde base: permite"     "$BASE" "git -C $WT status --short" 0
check "git log/diff desde base: permite"               "$BASE" "git -C $WT log --oneline -3; git -C $WT diff --stat" 0
check "ruta solo dentro de comillas (autoría): permite" "$BASE" "echo 'git -C $WT commit' > notas.md" 0
check "desde el propio worktree: permite"              "$WT"   "cd $WT && git commit -m ok" 0
check "comando sin worktree triangulate: permite"      "$BASE" "git commit -m 'fix' && npm run test" 0
check "payload sin comando: permite"                   "$BASE" "" 0
export TRIANGULATE_ALLOW_MAIN_CHECKOUT=1; check "escape explícito: permite" "$BASE" "cd $WT && git push" 0; unset TRIANGULATE_ALLOW_MAIN_CHECKOUT

# SessionStart: en base con triangulación abierta AVISA (exit 0 + texto); en worktree calla.
out="$(CLAUDE_PROJECT_DIR="$BASE" bash "$HOOK" </dev/null 2>/dev/null)"; total=$((total+1))
printf '%s' "$out" | grep -q 'CHECKOUT PRINCIPAL' || { fails=$((fails+1)); echo "FALLA: SessionStart en base no avisó" >&2; }
out="$(CLAUDE_PROJECT_DIR="$WT" bash "$HOOK" </dev/null 2>/dev/null)"; total=$((total+1))
[ -z "$out" ] || { fails=$((fails+1)); echo "FALLA: SessionStart en worktree imprimió ruido" >&2; }
out="$(CLAUDE_PROJECT_DIR="$T" bash "$HOOK" </dev/null 2>/dev/null)"; total=$((total+1))
[ -z "$out" ] || { fails=$((fails+1)); echo "FALLA: SessionStart fuera de la config imprimió ruido" >&2; }

echo "triangulate-guard: $((total-fails))/$total OK"
[ "$fails" -eq 0 ]
