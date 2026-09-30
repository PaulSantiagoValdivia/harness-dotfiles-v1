#!/usr/bin/env bash
# heavy-command-gate.sh — PreToolUse(Bash): control de admisión por CARGA para
# comandos pesados (tests, lint, builds, Playwright).
#
# Por qué existe: 2026-09-17, doce sesiones Claude en la misma Mac que el
# runner self-hosted de CI. Load 314 con 16 cores. El check:all del panel
# salió rojo por "Test timed out in 5000ms" en cuatro tests ajenos al cambio,
# y el commit se hizo con --no-verify. Un falso rojo por carga cuesta más que
# esperar diez minutos: se descarta evidencia, se bypassea un gate, y el
# siguiente PR hereda un "n/a" argumentado. El harness medía CONTEXTO por
# sesión pero nada medía la CPU compartida.
#
# Qué hace:
#   - Solo mira Bash cuyo comando matchea HEAVY_RE (vitest, jest, eslint,
#     playwright, flutter test/build, next build, tsc, check:all, npm test...).
#   - Lee el load de 1 minuto y los cores. Umbral = HEAVY_GATE_FACTOR x cores
#     (default 2x: en 16 cores, 32).
#   - modo warn (default): deja correr y le avisa a Claude por additionalContext
#     que el resultado puede estar contaminado y que un rojo por timeout con
#     esta carga NO es evidencia.
#   - modo block: exit 2 => el comando NO corre; Claude recibe el motivo y el
#     valor actual para decidir cuándo relanzar (una sola vez, sin polling).
#   - Si el runner de CI está ejecutando un job (Runner.Worker vivo), lo avisa
#     también: el deploy de prod no debería esperar a un lint de feature.
#   - Fail-open: sin jq, sin sysctl, input raro => exit 0 sin ruido.
#
# Config por entorno (todas opcionales):
#   HEAVY_GATE_MODE=warn|block   (default warn)
#   HEAVY_GATE_FACTOR=2          (umbral = factor x cores)
#   HEAVY_GATE_LOAD1 / HEAVY_GATE_NCPU  (override para la suite de tests)
#   HEAVY_GATE_RUNNER_PATTERN=Runner.Worker
#
# Suite (correrla SIEMPRE después de tocar esto):
#   bash ~/.claude/hooks/tests/heavy-command-gate-tests.sh

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -n "$cmd" ] && [ "$cmd" != "null" ] || exit 0

HEAVY_RE='(^|[^[:alnum:]_-])(vitest|jest|eslint|playwright|tsc|next build|flutter (test|build|analyze)|npm (run )?(test|check:all|check|lint|build|typecheck|e2e)|pnpm (run )?(test|check:all|check|lint|build)|yarn (test|check:all|lint|build)|npx (vitest|jest|eslint|playwright|tsc)|xcodebuild|gradlew?)([^[:alnum:]_./-]|$)'
printf '%s' "$cmd" | grep -qE "$HEAVY_RE" || exit 0

mode="${HEAVY_GATE_MODE:-warn}"
factor="${HEAVY_GATE_FACTOR:-2}"
case "$factor" in ''|*[!0-9]*) factor=2 ;; esac

ncpu="${HEAVY_GATE_NCPU:-}"
[ -n "$ncpu" ] || ncpu="$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 0)"
case "$ncpu" in ''|*[!0-9]*) exit 0 ;; esac
[ "$ncpu" -gt 0 ] || exit 0

load1="${HEAVY_GATE_LOAD1:-}"
if [ -z "$load1" ]; then
  raw="$(sysctl -n vm.loadavg 2>/dev/null || true)"   # macOS: "{ 1.23 4.56 7.89 }"
  [ -n "$raw" ] || raw="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || true)"
  load1="$(printf '%s' "$raw" | tr -d '{}' | awk '{print $1}')"
fi
load_int="${load1%%.*}"
case "$load_int" in ''|*[!0-9]*) exit 0 ;; esac

threshold=$(( ncpu * factor ))
runner_pat="${HEAVY_GATE_RUNNER_PATTERN:-Runner.Worker}"
runner_busy=0
if [ -n "${HEAVY_GATE_RUNNER_BUSY:-}" ]; then
  runner_busy="$HEAVY_GATE_RUNNER_BUSY"
elif pgrep -qf "$runner_pat" 2>/dev/null; then
  runner_busy=1
fi

over=0
[ "$load_int" -ge "$threshold" ] && over=1
[ "$over" -eq 0 ] && [ "$runner_busy" -eq 0 ] && exit 0

msg="heavy-command-gate: load1=${load1} con ${ncpu} cores (umbral ${threshold})."
[ "$runner_busy" -eq 1 ] && msg="$msg El runner de CI está ejecutando un job en esta máquina."

if [ "$mode" = "block" ] && [ "$over" -eq 1 ]; then
  {
    echo "BLOQUEADO: $msg"
    echo "Un comando pesado con esta carga produce timeouts que NO son evidencia."
    echo "Esperá a que uptime dé load1 < ${threshold} y relanzalo UNA vez (sin loops de polling)."
  } >&2
  exit 2
fi

ctx="$msg"
if [ "$over" -eq 1 ]; then
  ctx="$ctx El comando corre igual (modo warn), pero un rojo por timeout con esta carga NO es evidencia: no lo reportes como falla ni lo bypassees con --no-verify; esperá load1 < ${threshold} y relanzá UNA vez."
else
  ctx="$ctx Si el comando es opcional ahora, dejalo para después del job: el CI de prod no debería esperar a un lint local."
fi
jq -cn --arg c "$ctx" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$c}}'
exit 0
