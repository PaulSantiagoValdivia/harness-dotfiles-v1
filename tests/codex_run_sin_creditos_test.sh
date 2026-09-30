#!/usr/bin/env bash
# Contrato del fallback "Codex sin créditos" (regla del usuario 2026-09-03).
#
# Cuando Codex se queda sin cuota, el escritor de código pasa a ser Claude. El
# interruptor es un ARCHIVO (~/.claude/codex-sin-creditos) y no una variable de
# entorno, porque una sesión ya abierta no puede cambiar su propio entorno: el
# fallback tiene que servir en la sesión donde se descubre la falta de cuota.
#
# Dos mitades, las dos se prueban acá:
#   1. codex-run levanta el flag SOLO ante un error de cuota (no ante cualquier
#      fallo: un flag levantado por un error común abriría el paso para siempre).
#   2. route-code-to-codex.sh deja de bloquear con el flag fresco, y vuelve a
#      bloquear con el flag caducado o ausente.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/files/claude/bin/codex-run"
HOOK="$ROOT/files/claude/hooks/route-code-to-codex.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0

fail() { fails=$((fails+1)); echo "FALLA: $*" >&2; }

cat > "$TMP/codex-quota" <<'STUB'
#!/usr/bin/env bash
echo "stream error: You've hit your usage limit. Try again later." >&2
exit 1
STUB
cat > "$TMP/codex-otro-error" <<'STUB'
#!/usr/bin/env bash
echo "error: no such file or directory" >&2
exit 1
STUB
chmod +x "$TMP/codex-quota" "$TMP/codex-otro-error"

# 1) Error de cuota → flag puesto.
FLAG="$TMP/flag"
CODEX_RUN_BIN="$TMP/codex-quota" CODEX_SIN_CREDITOS_FLAG="$FLAG" \
  bash "$RUN" exec "x" >/dev/null 2>&1
[ -f "$FLAG" ] || fail "error de cuota no levantó el flag"

# 2) Error común → flag NO puesto.
rm -f "$FLAG"
CODEX_RUN_BIN="$TMP/codex-otro-error" CODEX_SIN_CREDITOS_FLAG="$FLAG" \
  bash "$RUN" exec "x" >/dev/null 2>&1
[ -f "$FLAG" ] && fail "un error común levantó el flag (abriría el paso sin motivo)"

# 2b) Sesión caída (401) → NI flag NI silencio. Sin esta rama, un Codex
#     deslogueado escupe una tormenta de 401 y el diagnóstico natural —el que se
#     hizo el 2026-09-03— es "se acabaron los créditos". Son cosas distintas: la
#     cuota vuelve sola, el login no, y abrirle el paso a Claude para escribir
#     todo el repo por un problema de auth es la reacción equivocada.
cat > "$TMP/codex-401" <<'STUB'
#!/usr/bin/env bash
echo "ERROR: unexpected status 401 Unauthorized: Missing bearer or basic authentication in header, url: https://api.openai.com/v1/responses" >&2
exit 1
STUB
chmod +x "$TMP/codex-401"
rm -f "$FLAG"
out401="$(CODEX_RUN_BIN="$TMP/codex-401" CODEX_SIN_CREDITOS_FLAG="$FLAG" \
  bash "$RUN" exec "x" 2>&1 >/dev/null)"
[ -f "$FLAG" ] && fail "un 401 de auth levantó el flag de cuota (son problemas distintos)"
printf '%s' "$out401" | grep -q 'codex login' \
  || fail "un 401 no dice cómo arreglarlo (el login es interactivo, solo lo hace el usuario)"

# 3) Hook: flag fresco deja escribir código; caducado y ausente siguen bloqueando.
payload='{"tool_name":"Write","tool_input":{"file_path":"/repo/src/app.ts"}}'
touch "$TMP/fresco"
touch -t 202001010000 "$TMP/viejo"

printf '%s' "$payload" | CODEX_SIN_CREDITOS_FLAG="$TMP/fresco" bash "$HOOK" >/dev/null 2>&1
[ $? = 0 ] || fail "flag fresco: el hook siguió bloqueando (Claude no puede codear sin Codex)"

printf '%s' "$payload" | CODEX_SIN_CREDITOS_FLAG="$TMP/viejo" bash "$HOOK" >/dev/null 2>&1
[ $? = 2 ] || fail "flag caducado: el hook dejó pasar (el fallback no debe quedar abierto para siempre)"

printf '%s' "$payload" | CODEX_SIN_CREDITOS_FLAG="$TMP/no-existe" bash "$HOOK" >/dev/null 2>&1
[ $? = 2 ] || fail "sin flag: el hook dejó pasar (Codex sigue siendo el escritor por default)"

# 4) TTL 0 = no caduca (para una sequía larga de cuota, decidida a conciencia).
printf '%s' "$payload" | CODEX_SIN_CREDITOS_FLAG="$TMP/viejo" CODEX_SIN_CREDITOS_TTL_H=0 \
  bash "$HOOK" >/dev/null 2>&1
[ $? = 0 ] || fail "TTL 0: debería no caducar nunca"

# 5) El fallback se ANUNCIA al arrancar la sesión. Incidente 2026-09-03: con el
#    flag puesto, un sub-agente igual se quedó esperando autorización porque su
#    bloque "Code routing" dice que Codex escribe el código. El aviso de deny()
#    solo lo ve quien INTENTA escribir; el que se cree bloqueado no intenta.
VAL="$ROOT/files/claude/hooks/validate-enforcement.sh"
if [ -f "$VAL" ]; then
  out="$(CODEX_SIN_CREDITOS_FLAG="$TMP/fresco" bash "$VAL" 2>&1)"
  printf '%s' "$out" | grep -q 'CLAUDE ESCRIBE EL CÓDIGO' \
    || fail "SessionStart no anuncia el fallback con el flag puesto"
  out="$(CODEX_SIN_CREDITOS_FLAG="$TMP/no-existe" bash "$VAL" 2>&1)"
  printf '%s' "$out" | grep -q 'CLAUDE ESCRIBE EL CÓDIGO' \
    && fail "SessionStart anuncia el fallback sin flag (ruido de contexto por sesión)"
fi

if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails casos del fallback sin-créditos fallan." >&2
  exit 1
fi
echo "PASS: fallback Codex-sin-créditos — flag solo por cuota, TTL respetado, default intacto"
exit 0
