#!/usr/bin/env bash
# Contrato del watchdog por inactividad de codex-run.
# Sustituye el binario de codex por dobles que reproducen las dos situaciones
# que el watchdog de reloj no sabía distinguir.
SP="$(mktemp -d -t codex-wd-tests)"; trap "rm -rf $SP" EXIT
RUN="${1:-$HOME/.claude/bin/codex-run}"
pass=0; fail=0

check() { # nombre esperado_rc rc_real patron_esperado log
  local name="$1" want="$2" got="$3" pat="$4" log="$5"
  if [ "$got" = "$want" ] && grep -q "$pat" "$log" 2>/dev/null; then
    echo "  OK   $name (rc=$got)"; pass=$((pass+1))
  else
    echo "  FALLA $name — rc esperado=$want obtenido=$got; patrón '$pat' $(grep -q "$pat" "$log" && echo presente || echo AUSENTE)"
    sed -n '1,6p' "$log" | sed 's/^/        /'
    fail=$((fail+1))
  fi
}

# Doble 1: CUELGUE. Duerme sin consumir CPU y sin emitir nada. Es la firma
# exacta del incidente del 2026-08-30 (13 min, 0,1s de CPU).
cat > "$SP/fake-hang" <<'EOF'
#!/usr/bin/env bash
sleep 600
EOF
chmod +x "$SP/fake-hang"

# Doble 2: TRABAJO SANO LARGO. Quema CPU y emite a stderr, más allá del techo
# viejo de 900s en proporción: acá 60s con umbral de idle de 20s.
cat > "$SP/fake-busy" <<'EOF'
#!/usr/bin/env bash
end=$(( $(date +%s) + 60 ))
while [ "$(date +%s)" -lt "$end" ]; do
  i=0; while [ $i -lt 200000 ]; do i=$((i+1)); done
  echo "progreso $(date +%s)" >&2
done
echo "terminado bien"
EOF
chmod +x "$SP/fake-busy"

echo "== 1. cuelgue (0 CPU, 0 salida) debe morir por INACTIVIDAD, no por techo =="
t0=$(date +%s)
CODEX_RUN_BIN="$SP/fake-hang" CODEX_RUN_IDLE=30 CODEX_RUN_MAX=600 \
  "$RUN" exec >"$SP/t1.log" 2>&1
rc=$?; d=$(( $(date +%s) - t0 ))
echo "  duración=${d}s (el watchdog viejo habría esperado 600s)"
check "cuelgue detectado" 124 "$rc" "COLGADO" "$SP/t1.log"
[ "$d" -lt 90 ] && { echo "  OK   murió rápido (${d}s < 90s)"; pass=$((pass+1)); } \
                || { echo "  FALLA tardó ${d}s"; fail=$((fail+1)); }

echo "== 2. trabajo sano con CPU y salida NO debe morir aunque supere el idle =="
t0=$(date +%s)
CODEX_RUN_BIN="$SP/fake-busy" CODEX_RUN_IDLE=20 CODEX_RUN_MAX=600 \
  "$RUN" exec >"$SP/t2.log" 2>&1
rc=$?; d=$(( $(date +%s) - t0 ))
echo "  duración=${d}s"
check "trabajo sano sobrevive" 0 "$rc" "terminado bien" "$SP/t2.log"

echo "== 3. techo absoluto sigue existiendo (cuelgue con idle alto) =="
t0=$(date +%s)
CODEX_RUN_BIN="$SP/fake-hang" CODEX_RUN_IDLE=999 CODEX_RUN_MAX=30 \
  "$RUN" exec >"$SP/t3.log" 2>&1
rc=$?; d=$(( $(date +%s) - t0 ))
echo "  duración=${d}s"
check "techo absoluto" 124 "$rc" "techo absoluto" "$SP/t3.log"

echo "== 4. compat: CODEX_RUN_TIMEOUT viejo sigue mandando como techo =="
t0=$(date +%s)
CODEX_RUN_BIN="$SP/fake-hang" CODEX_RUN_TIMEOUT=25 \
  "$RUN" exec >"$SP/t4.log" 2>&1
rc=$?; d=$(( $(date +%s) - t0 ))
echo "  duración=${d}s (debe cortar cerca de 25s, no de 2700)"
[ "$rc" = 124 ] && [ "$d" -lt 70 ] && { echo "  OK   compat respetada"; pass=$((pass+1)); } \
                                   || { echo "  FALLA rc=$rc d=${d}s"; fail=$((fail+1)); }

echo
echo "RESULTADO: $pass OK, $fail FALLA"
[ "$fail" -eq 0 ]
