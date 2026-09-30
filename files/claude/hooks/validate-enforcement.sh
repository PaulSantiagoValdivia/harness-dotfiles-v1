#!/usr/bin/env bash
# SessionStart — verifica que el enforcement "Codex escribe el código" esté
# VIVO antes de que la sesión haga nada. Si está roto, lo dice en el contexto
# de arranque con instrucciones precisas; ninguna sesión vuelve a trabajar
# semanas con un agujero sin saberlo (como pasó el 2026-08-30/31).
#
# Barato: corre la suite de contrato (~30 casos de bash puro, <1s). Fail-open
# operacional (exit 0 siempre) — un validador roto no debe impedir trabajar,
# solo AVISAR fuerte.

set -uo pipefail

# Guard de routing APAGADO (2026-09-07) ------------------------------------
# El escape consciente y el fail-open por jq eran mudos: una sesión podía
# escribir código de producto durante horas con el guard apagado sin que nadie
# lo supiera. El deny() sólo avisa si alguien INTENTA escribir, y el que se
# cree bloqueado no intenta nunca — así que el aviso tiene que ir al arranque.
if [ "${CLAUDE_ALLOW_DIRECT_EDIT:-0}" = "1" ]; then
  echo "🚨 GUARD DE ROUTING APAGADO: CLAUDE_ALLOW_DIRECT_EDIT=1 está en el entorno de esta sesión."
  echo "Claude puede escribir código de producto sin pasar por Codex. Si NO era tu intención,"
  echo "la variable quedó exportada en el shell del pane: cerrá la sesión y abrí una limpia."
  echo "Si SÍ era tu intención: el estándar no baja — código completo, sin placeholders, y la"
  echo "misma auditoría que le harías a un diff de Codex (git diff + verificación con exit code)."
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "🚨 FALTA jq: el guard de routing hace fail-open y NO protege nada. Instalalo: brew install jq"
fi
BYPASS_LOG="${CLAUDE_ROUTING_BYPASS_DIR:-$HOME/.claude/hooks/state/routing-bypass}/bypass.log"
if [ -f "$BYPASS_LOG" ]; then
  recientes="$(find "$BYPASS_LOG" -mtime -1 2>/dev/null)"
  if [ -n "$recientes" ]; then
    echo "ℹ️ El guard de routing se salteó en las últimas 24h. Últimas entradas:"
    tail -3 "$BYPASS_LOG" | sed 's/^/   /'
  fi
fi

TESTS="$HOME/.claude/hooks/tests/route-hook-tests.sh"
HOOK="$HOME/.claude/hooks/route-code-to-codex.sh"

if [ ! -f "$TESTS" ]; then
  echo "⚠️ ENFORCEMENT SIN VALIDAR: falta $TESTS. El contrato Codex-escribe-código no puede verificarse. Restauralo desde git/backup antes de escribir código."
  exit 0
fi

out="$(CLAUDE_ALLOW_DIRECT_EDIT=0 bash "$TESTS" "$HOOK" 2>&1)"
rc=$?

if [ "$rc" -ne 0 ]; then
  echo "🚨 ENFORCEMENT ROTO (Codex-escribe-código): la suite de contrato falló (rc=$rc)."
  printf '%s\n' "$out" | head -12
  echo ""
  echo "REGLA PARA ESTA SESIÓN mientras esté roto: NO escribas ni edites código de"
  echo "producto con ninguna herramienta. Arreglá primero $HOOK"
  echo "(editá con el tool Edit, corré bash -n y después la suite: bash $TESTS)."
fi
# Segundo contrato (2026-09-01): "una triangulación se coordina desde su worktree".
TG_TESTS="$HOME/.claude/hooks/tests/triangulate-guard-tests.sh"
TG_HOOK="$HOME/.claude/hooks/triangulate-main-checkout-guard.sh"
if [ -f "$TG_TESTS" ]; then
  out="$(CLAUDE_ALLOW_DIRECT_EDIT=0 bash "$TG_TESTS" "$TG_HOOK" 2>&1)" || {
    echo "🚨 ENFORCEMENT ROTO (triangulación-desde-worktree): la suite falló."
    printf '%s\n' "$out" | head -8
    echo "Arreglá $TG_HOOK y corré: bash $TG_TESTS"
  }
fi
# Fallback "Codex sin créditos" (regla del usuario 2026-09-03) --------------
# Incidente que lo motiva, el mismo día que se creó el fallback: una sesión
# tenía el flag puesto y su sub-agente igual se quedó ESPERANDO AUTORIZACIÓN
# en vez de escribir, porque su bloque "Code routing" dice que Codex escribe el
# código y nadie le avisó de la excepción. Un fallback que no se anuncia no
# existe: el aviso de deny() solo aparece si el agente INTENTA escribir, y el
# que se cree bloqueado no intenta nunca. Por eso se anuncia al arrancar.
SIN_CREDITOS_FLAG="${CODEX_SIN_CREDITOS_FLAG:-$HOME/.claude/codex-sin-creditos}"
if [ -f "$SIN_CREDITOS_FLAG" ]; then
  ttl_h="${CODEX_SIN_CREDITOS_TTL_H:-12}"
  mtime="$(stat -f %m "$SIN_CREDITOS_FLAG" 2>/dev/null || stat -c %Y "$SIN_CREDITOS_FLAG" 2>/dev/null || echo 0)"
  age=$(( $(date +%s) - mtime ))
  if [ "$ttl_h" = "0" ] || [ "$age" -lt $(( ttl_h * 3600 )) ]; then
    echo "⚠️ CODEX SIN CRÉDITOS — en esta sesión CLAUDE ESCRIBE EL CÓDIGO."
    echo "Flag activo: $SIN_CREDITOS_FLAG (hace $((age/3600))h; TTL ${ttl_h}h)."
    echo "Esto SUPERSEDE el bloque 'Codex writes ALL product code' de CLAUDE.md y"
    echo "el bloque 'Code routing' de los agents: NO despaches codex-run, falla por"
    echo "cuota. Escribí con Edit/Write; el hook ya no bloquea código."
    echo "El estándar NO baja: código completo sin placeholders ni elisiones,"
    echo "archivos reales leídos antes de escribir, y la misma auditoría que le"
    echo "harías a un diff de Codex (git diff + los comandos de verificación del"
    echo "rol, con su exit code real). Sin segundo motor, tu auditoría es la única red."
    echo "Cuando vuelva la cuota: rm $SIN_CREDITOS_FLAG"
  fi
fi

# En verde no imprime nada: cero ruido de contexto por sesión.
exit 0
