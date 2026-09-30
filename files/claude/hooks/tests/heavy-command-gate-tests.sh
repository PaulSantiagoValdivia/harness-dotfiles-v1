#!/usr/bin/env bash
# Suite de contrato de heavy-command-gate.sh — control de admisión por carga.
#
# El hook decide con load y cores REALES; acá se fijan por entorno
# (HEAVY_GATE_LOAD1 / HEAVY_GATE_NCPU / HEAVY_GATE_RUNNER_BUSY) para que cada
# caso sea determinista. Los payloads viven acá adentro por el mismo motivo
# que en block-unbounded-polls-tests.sh: un PreToolUse(Bash) inspecciona el
# comando que lo invoca.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/heavy-command-gate-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/heavy-command-gate.sh}"
fails=0
total=0

if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK" >&2; exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis — bloquearía TODOS los Bash de la sesión." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v jq >/dev/null 2>&1 || { echo "FATAL: falta jq" >&2; exit 3; }

payload() { jq -cn --arg c "$1" --arg t "${2:-Bash}" '{tool_name:$t,tool_input:{command:$c}}'; }

# run <nombre> <exit esperado> <stdout esperado: empty|context> <comando> [ENV=VAL ...]
run() {
  local name="$1" want_rc="$2" want_out="$3" cmd="$4"; shift 4
  local out rc
  total=$((total+1))
  out="$(env HEAVY_GATE_RUNNER_BUSY=0 "$@" bash "$HOOK" <<<"$(payload "$cmd")" 2>/dev/null)"; rc=$?
  local ok=1
  [ "$rc" -eq "$want_rc" ] || ok=0
  case "$want_out" in
    empty)   [ -z "$out" ] || ok=0 ;;
    context) printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | length > 0' >/dev/null 2>&1 || ok=0 ;;
  esac
  if [ "$ok" -eq 1 ]; then echo "ok   $name"; else echo "FAIL $name (rc=$rc quería $want_rc; stdout='${out:0:80}')"; fails=$((fails+1)); fi
}

# --- 1. Comandos livianos: nunca opina, con cualquier carga ---
run "ls con load altísimo"            0 empty   "ls -la"                         HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16
run "git status con load altísimo"    0 empty   "git status --short"             HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16
run "grep de 'test' en texto no cuenta" 0 empty "grep -rn 'test' src/"           HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16
run "cat de un archivo vitest.config"  0 empty  "cat vitest.config.ts"           HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16

# --- 2. Comandos pesados con carga normal: pasa en silencio ---
run "vitest con load bajo"            0 empty   "npx vitest run src/x.test.ts"   HEAVY_GATE_LOAD1=4 HEAVY_GATE_NCPU=16
run "check:all justo bajo el umbral"  0 empty   "npm run check:all"              HEAVY_GATE_LOAD1=31.9 HEAVY_GATE_NCPU=16
run "flutter test load bajo"          0 empty   "flutter test"                   HEAVY_GATE_LOAD1=10 HEAVY_GATE_NCPU=16

# --- 3. Pesados con carga alta, modo warn (default): corre y avisa ---
run "check:all en el umbral avisa"    0 context "npm run check:all"              HEAVY_GATE_LOAD1=32 HEAVY_GATE_NCPU=16
run "vitest load 300 avisa"           0 context "npx vitest run"                 HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16
run "eslint encadenado avisa"         0 context "cd functions && npx eslint src" HEAVY_GATE_LOAD1=100 HEAVY_GATE_NCPU=16
run "playwright avisa"                0 context "npx playwright test --project=panel" HEAVY_GATE_LOAD1=100 HEAVY_GATE_NCPU=16
run "next build avisa"                0 context "npm run build"                  HEAVY_GATE_LOAD1=100 HEAVY_GATE_NCPU=16

# --- 4. Modo block: pesados con carga alta NO corren ---
run "block: check:all load 100"       2 empty   "npm run check:all"              HEAVY_GATE_LOAD1=100 HEAVY_GATE_NCPU=16 HEAVY_GATE_MODE=block
run "block: vitest justo en umbral"   2 empty   "npx vitest run"                 HEAVY_GATE_LOAD1=32 HEAVY_GATE_NCPU=16 HEAVY_GATE_MODE=block
run "block: pesado con load bajo pasa" 0 empty  "npx vitest run"                 HEAVY_GATE_LOAD1=5 HEAVY_GATE_NCPU=16 HEAVY_GATE_MODE=block
run "block: liviano con load alto pasa" 0 empty "git log --oneline -3"           HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16 HEAVY_GATE_MODE=block

# --- 5. Factor configurable ---
run "factor 4: load 50 en 16 cores pasa" 0 empty "npm test"                      HEAVY_GATE_LOAD1=50 HEAVY_GATE_NCPU=16 HEAVY_GATE_FACTOR=4
run "factor 1: load 17 en 16 cores avisa" 0 context "npm test"                   HEAVY_GATE_LOAD1=17 HEAVY_GATE_NCPU=16 HEAVY_GATE_FACTOR=1

# --- 6. Runner de CI ocupado: avisa aunque la carga sea baja; nunca bloquea por sí solo ---
total=$((total+1))
out="$(env HEAVY_GATE_RUNNER_BUSY=1 HEAVY_GATE_LOAD1=3 HEAVY_GATE_NCPU=16 bash "$HOOK" <<<"$(payload 'npm run check:all')" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("runner")' >/dev/null 2>&1; then echo "ok   runner ocupado avisa (warn)"; else echo "FAIL runner ocupado avisa (rc=$rc)"; fails=$((fails+1)); fi
total=$((total+1))
out="$(env HEAVY_GATE_RUNNER_BUSY=1 HEAVY_GATE_LOAD1=3 HEAVY_GATE_NCPU=16 HEAVY_GATE_MODE=block bash "$HOOK" <<<"$(payload 'npm run check:all')" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ]; then echo "ok   runner ocupado + load bajo no bloquea en modo block"; else echo "FAIL runner ocupado no debería bloquear (rc=$rc)"; fails=$((fails+1)); fi

# --- 7. Fail-open ---
total=$((total+1))
out="$(printf 'esto no es json' | bash "$HOOK" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "ok   input no-JSON => exit 0 en silencio"; else echo "FAIL input no-JSON (rc=$rc)"; fails=$((fails+1)); fi
total=$((total+1))
out="$(env HEAVY_GATE_LOAD1=300 HEAVY_GATE_NCPU=16 bash "$HOOK" <<<"$(payload 'npm run check:all' Edit)" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "ok   tool_name != Bash => exit 0"; else echo "FAIL tool_name != Bash (rc=$rc)"; fails=$((fails+1)); fi
total=$((total+1))
out="$(env HEAVY_GATE_LOAD1=basura HEAVY_GATE_NCPU=16 bash "$HOOK" <<<"$(payload 'npm run check:all')" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "ok   load ilegible => exit 0"; else echo "FAIL load ilegible (rc=$rc)"; fails=$((fails+1)); fi

echo
echo "heavy-command-gate: $((total-fails))/$total ok"
[ "$fails" -eq 0 ] || exit 1
