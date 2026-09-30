#!/usr/bin/env bash
# Contrato del presupuesto de contexto, repartido en dos hooks:
#   context-budget-measure.sh  (Stop)              -- mide y CACHEA el aviso
#   context-budget.sh          (UserPromptSubmit)  -- solo LEE el aviso
#
# Lo que prometen sus cabeceras, y que se mide caso por caso aca:
#   1. El lector no ejecuta NINGUN proceso externo. Es la razon de ser del
#      cambio: con 12 forks, una Mac saturada lo mataba a los 30s.
#   2. Los umbrales: 200k AVISO, 300k ALTO, 400k CRITICO, y edad >= 10h.
#   3. El interruptor .ctx-quiet calla AVISO y ALTO pero NUNCA CRITICO.
#   4. Fail-open total en los dos: nunca un rc != 0, nunca bloquear un prompt.
#   5. El cache se BORRA cuando ya no corresponde avisar (un aviso viejo no
#      puede quedar pegado para siempre).
#   6. Escritor y lector tienen que coincidir en como sanean el session_id: si
#      divergen, el aviso no llega nunca y NADIE SE ENTERA. Es el unico modo de
#      falla silenciosa del diseno, y tiene casos propios (bloque RT).
#
# Todo corre contra un CLAUDE_CTX_CACHE_DIR aislado y transcripts sinteticos.
# Un hook con efectos NO se prueba contra el sistema real.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${HOOKS_UNDER_TEST:-$REPO_DIR/files/claude/hooks}"
READER="${READER_UNDER_TEST:-$HOOKS_DIR/context-budget.sh}"
WRITER="${WRITER_UNDER_TEST:-$HOOKS_DIR/context-budget-measure.sh}"

for h in "$READER" "$WRITER"; do
  [ -f "$h" ] || { printf 'FAIL: no existe el hook bajo prueba: %s\n' "$h" >&2; exit 1; }
done

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/context-budget-test.XXXXXX")" || exit 1
cleanup() {
  case "${TMP_ROOT:-}" in
    *context-budget-test.*) rm -rf "$TMP_ROOT" ;;
  esac
}
trap cleanup EXIT
TMP_ROOT="$(cd "$TMP_ROOT" && pwd -P)"  # Explicit physical cache authority.

# HOME aislado: el interruptor .ctx-quiet vive en $HOME y no se puede tocar el
# del usuario.
FAKE_HOME="$TMP_ROOT/home"
mkdir -p "$FAKE_HOME/.claude"
CACHE="$TMP_ROOT/ctx-budget"
mkdir -p "$CACHE"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf '  FAIL [%s] %s\n' "$1" "$2" >&2; }

N=0
# Transcript sintetico: <tokens de contexto> <horas de antiguedad>
mk_transcript() {
  local ctx="$1" hours="${2:-0}"
  N=$((N+1))
  local f="$TMP_ROOT/t$N.jsonl"
  python3 - "$f" "$ctx" "$hours" <<'PY'
import json, sys, datetime
path, ctx, hours = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
start = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=hours)
with open(path, "w") as fh:
    fh.write(json.dumps({"type": "user", "timestamp":
        start.strftime("%Y-%m-%dT%H:%M:%S.000Z")}) + "\n")
    for _ in range(5):
        fh.write(json.dumps({"type": "assistant"}) + "\n")
    fh.write(json.dumps({"type": "assistant", "message": {"usage": {
        "input_tokens": ctx, "cache_read_input_tokens": 0,
        "cache_creation_input_tokens": 0}}}) + "\n")
PY
  printf '%s' "$f"
}

run_writer() { # run_writer <session> <transcript> [env...]
  local s="$1" t="$2"; shift 2
  printf '{"session_id":"%s","transcript_path":"%s"}' "$s" "$t" \
    | env "$@" HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$WRITER" >/dev/null 2>&1
}
run_reader() { # run_reader <session>
  printf '{"session_id":"%s"}' "$1" \
    | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$READER" 2>/dev/null
}

# ===========================================================================
# W. Umbrales del escritor
# ===========================================================================
check_level() { # check_level <id> <tokens> <horas> <nivel esperado o VACIO>
  local id="$1" ctx="$2" hours="$3" want="$4" t out
  t="$(mk_transcript "$ctx" "$hours")"
  run_writer "s-$id" "$t"
  out="$(run_reader "s-$id")"
  if [ -z "$want" ]; then
    [ -z "$out" ] && ok || bad "$id" "se esperaba silencio con ${ctx} tokens / ${hours}h, salio: '${out%%$'\n'*}'"
    return
  fi
  case "$out" in
    *"$want"*) ok ;;
    *) bad "$id" "se esperaba nivel $want con ${ctx} tokens / ${hours}h, salio: '${out%%$'\n'*}'" ;;
  esac
}

check_level W01      1000  0 ''
check_level W02    199999  0 ''
check_level W03    200000  0 'AVISO'
check_level W04    299999  0 'AVISO'
check_level W05    300000  0 'ALTO'
check_level W06    399999  0 'ALTO'
check_level W07    400000  0 'CRITICO'
check_level W08    900000  0 'CRITICO'
# Edad: una sesion larga avisa aunque el contexto este sano, pero NO escala.
check_level W09      5000  9 ''
check_level W10      5000 11 'AVISO'
check_level W11    350000 11 'ALTO'

# El numero informado es el real, en miles.
t="$(mk_transcript 311100 0)"; run_writer s-W12 "$t"
case "$(run_reader s-W12)" in *311k*) ok ;; *) bad W12 "no informo 311k" ;; esac

# La nota de sesion larga aparece desde las 6h, no antes.
t="$(mk_transcript 250000 7)"; run_writer s-W13 "$t"
case "$(run_reader s-W13)" in *7h*) ok ;; *) bad W13 "no menciono las 7h de sesion" ;; esac
t="$(mk_transcript 250000 2)"; run_writer s-W14 "$t"
case "$(run_reader s-W14)" in *"h abiertas"*) bad W14 "menciono la edad con solo 2h" ;; *) ok ;; esac

# El contexto suma los tres campos de usage, no solo input_tokens.
f="$TMP_ROOT/split.jsonl"
python3 - "$f" <<'PY'
import json, sys, datetime
with open(sys.argv[1], "w") as fh:
    fh.write(json.dumps({"type":"user","timestamp":
        datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")})+"\n")
    fh.write(json.dumps({"type":"assistant","message":{"usage":{
        "input_tokens":100000,"cache_read_input_tokens":150000,
        "cache_creation_input_tokens":60000}}})+"\n")
PY
run_writer s-W15 "$f"
case "$(run_reader s-W15)" in *310k*) ok ;; *) bad W15 "no sumo cache_read + cache_creation (esperaba 310k)" ;; esac

# ===========================================================================
# Q. El interruptor .ctx-quiet. CRITICO no se silencia NUNCA.
# ===========================================================================
: > "$FAKE_HOME/.claude/.ctx-quiet"
t="$(mk_transcript 250000 0)"; run_writer s-Q01 "$t"
[ -z "$(run_reader s-Q01)" ] && ok || bad Q01 "el interruptor no callo un AVISO"
t="$(mk_transcript 350000 0)"; run_writer s-Q02 "$t"
[ -z "$(run_reader s-Q02)" ] && ok || bad Q02 "el interruptor no callo un ALTO"
t="$(mk_transcript 450000 0)"; run_writer s-Q03 "$t"
case "$(run_reader s-Q03)" in
  *CRITICO*) ok ;;
  *) bad Q03 "el interruptor callo un CRITICO; un interruptor que apaga el techo no es un interruptor" ;;
esac
rm -f "$FAKE_HOME/.claude/.ctx-quiet"

t="$(mk_transcript 250000 0)"
run_writer s-Q04 "$t" CLAUDE_CTX_QUIET=1
[ -z "$(run_reader s-Q04)" ] && ok || bad Q04 "CLAUDE_CTX_QUIET=1 no callo un AVISO"
t="$(mk_transcript 450000 0)"
run_writer s-Q05 "$t" CLAUDE_CTX_QUIET=1
case "$(run_reader s-Q05)" in *CRITICO*) ok ;; *) bad Q05 "CLAUDE_CTX_QUIET=1 callo un CRITICO" ;; esac

# ===========================================================================
# S. El aviso viejo NO queda pegado.
# ===========================================================================
t="$(mk_transcript 450000 0)"; run_writer s-S01 "$t"
[ -n "$(run_reader s-S01)" ] && ok || bad S01 "no dejo el aviso inicial"
t2="$(mk_transcript 10000 0)"; run_writer s-S01 "$t2"
[ -z "$(run_reader s-S01)" ] && ok || bad S02 "el aviso quedo pegado despues de bajar del umbral"
[ ! -f "$CACHE/s-S01" ] && ok || bad S03 "no borro el archivo de cache al dejar de corresponder"

# Transcript ausente o sin usage: se limpia, no se conserva un aviso viejo.
t="$(mk_transcript 450000 0)"; run_writer s-S04 "$t"
run_writer s-S04 "$TMP_ROOT/no-existe.jsonl"
[ -z "$(run_reader s-S04)" ] && ok || bad S04 "conservo el aviso con un transcript ausente"
t="$(mk_transcript 450000 0)"; run_writer s-S05 "$t"
empty="$TMP_ROOT/sin-usage.jsonl"; printf '{"type":"user"}\n' > "$empty"
run_writer s-S05 "$empty"
[ -z "$(run_reader s-S05)" ] && ok || bad S05 "conservo el aviso con un transcript sin usage"

# ===========================================================================
# RT. Round-trip escritor <-> lector.
#
# Unico modo de falla SILENCIOSA del diseno: si los dos sanean el session_id
# distinto, el escritor deja el aviso en un nombre y el lector lo busca en
# otro. No falla nada, no avisa nadie, y el enforcement desaparece.
# ===========================================================================
#
# LIMITE A PROPOSITO: un session_id con una comilla ESCAPADA ('con\"comilla')
# si diverge. jq lo desescapa a 'con"comilla' y la regex de bash del lector
# corta en la barra y devuelve 'con\'. Es real, y es INALCANZABLE: el harness
# genera el session_id como UUID. Enseniar a la regex a desescapar JSON en bash
# puro seria un agujero de conejo para una entrada que no existe, y le pondria
# al lector justo el costo que este cambio vino a sacarle. Queda escrito aca en
# vez de tapado.
for s in 'abc-123' 'ABC_def.456' 'd0031573-88a1-410f-a708-dafe8aaf4cb0' \
         'con espacios' 'con/barra' 'con:dos:puntos' \
         'acentuada-ñ' 'con$dolar' '../fuera' 'a*b?c'; do
  t="$(mk_transcript 450000 0)"
  run_writer "$s" "$t"
  case "$(run_reader "$s")" in
    *CRITICO*) ok ;;
    *) bad "RT[$s]" "escritor y lector no coinciden al sanear el session_id" ;;
  esac
done

# Traversal: un session_id malicioso no puede leer fuera del directorio.
secreto="$TMP_ROOT/secreto.txt"
printf 'CONTENIDO SECRETO\n' > "$secreto"
out="$(printf '{"session_id":"../secreto.txt"}' \
  | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$READER" 2>/dev/null)"
case "$out" in
  *SECRETO*) bad RT11 "el lector escapo del directorio de cache con ../" ;;
  *) ok ;;
esac

# ===========================================================================
# R. El lector. Lo central: NO forkea.
# ===========================================================================
# Con PATH vacio ningun binario externo es alcanzable. Si aun asi entrega el
# aviso, es que no lanza ninguno. Es la prueba de la promesa entera del cambio.
printf 'MENSAJE DE PRUEBA\n' > "$CACHE/sess-nofork"
out="$(printf '{"session_id":"sess-nofork"}' \
  | env -i HOME="$FAKE_HOME" PATH="" CLAUDE_CTX_CACHE_DIR="$CACHE" /bin/bash "$READER" 2>/dev/null)"
case "$out" in
  *"MENSAJE DE PRUEBA"*) ok ;;
  *) bad R01 "el lector no funciona con PATH vacio: esta forkeando algun binario externo" ;;
esac
# Y el camino comun (sin aviso) tambien tiene que ser mudo sin PATH.
out="$(printf '{"session_id":"sess-inexistente"}' \
  | env -i HOME="$FAKE_HOME" PATH="" CLAUDE_CTX_CACHE_DIR="$CACHE" /bin/bash "$READER" 2>/dev/null)"
rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok || bad R02 "el camino comun no es mudo/limpio con PATH vacio"

# Fail-open del lector: nada de esto puede dar rc != 0 ni ensuciar la salida.
reader_silent() { # reader_silent <id> <entrada cruda>
  local id="$1" out rc
  out="$(printf '%s' "$2" | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$READER" 2>/dev/null)"
  rc=$?
  [ "$rc" -eq 0 ] || { bad "$id" "rc=$rc"; return; }
  ok
  [ -z "$out" ] && ok || bad "${id}b" "no fue mudo: '$out'"
}
reader_silent R03 ''
reader_silent R04 'no es json'
reader_silent R05 '{}'
reader_silent R06 '{"session_id":""}'
reader_silent R07 '{"session_id":"sin-cache-asociado"}'
reader_silent R08 '{"otra_clave":"x"}'
reader_silent R09 '{"session_id":null}'

# Cache vacio -> MUDO, y mudo de verdad: cero bytes, no una linea en blanco.
#
# Se cuentan BYTES a proposito. `$(...)` se come los saltos de linea finales,
# asi que un hook que imprime "\n" da exactamente el mismo "" que uno que no
# imprime nada. Con la comparacion de cadena, un mutante que borraba el guard
# `[ -n "$msg" ]` ESCAPABA: metia una linea en blanco en el contexto del modelo
# en cada prompt y la suite lo daba por bueno.
: > "$CACHE/sess-vacio"
bytes="$(printf '{"session_id":"sess-vacio"}' \
  | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$READER" 2>/dev/null \
  | wc -c | tr -d ' ')"
[ "$bytes" = "0" ] && ok || bad R10 "con el cache vacio emitio $bytes bytes en vez de callarse"

# Un aviso multilinea llega COMPLETO: los niveles ALTO y CRITICO son de 2 y 3
# lineas, y entregar solo la primera perderia justamente la instruccion.
printf 'linea uno\nlinea dos\nlinea tres\n' > "$CACHE/sess-multi"
out="$(run_reader sess-multi)"
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = "2" ] && ok || bad R11 "no entrego el aviso multilinea completo"
case "$out" in *"linea tres"*) ok ;; *) bad R12 "se perdio la ultima linea del aviso" ;; esac

# El directorio de cache puede no existir todavia (primer prompt de la vida).
out="$(printf '{"session_id":"x"}' | env HOME="$FAKE_HOME" \
  CLAUDE_CTX_CACHE_DIR="$TMP_ROOT/no-existe-aun" bash "$READER" 2>/dev/null)"
rc=$?
[ -z "$out" ] && [ "$rc" -eq 0 ] && ok || bad R13 "fallo con el directorio de cache ausente"

# ===========================================================================
# E. Fail-open del escritor y limpieza.
# ===========================================================================
writer_ok() { # writer_ok <id> <entrada cruda>
  printf '%s' "$2" | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$WRITER" >/dev/null 2>&1
  [ $? -eq 0 ] && ok || bad "$1" "el escritor devolvio rc != 0"
}
writer_ok E01 ''
writer_ok E02 'no es json'
writer_ok E03 '{}'
writer_ok E04 '{"session_id":"x"}'
writer_ok E05 '{"session_id":"x","transcript_path":"/no/existe"}'

# Sin jq no se rompe nada.
mkdir -p "$TMP_ROOT/empty-bin"
t="$(mk_transcript 450000 0)"
printf '{"session_id":"s-E06","transcript_path":"%s"}' "$t" \
  | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" PATH="$TMP_ROOT/empty-bin" \
    /bin/bash "$WRITER" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad E06 "el escritor fallo sin jq en el PATH"

# No deja temporales tirados.
left="$(find "$CACHE" -name '.tmp.*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$left" = "0" ] && ok || bad E07 "dejo $left temporales en el directorio de cache"

# La purga solo actua en un directorio que se llame ctx-budget. Un hook que
# BORRA no puede confiar en una variable con cualquier valor: en un hook con
# efectos el fail-open es fail-DANINO.
OTHER="$TMP_ROOT/directorio-cualquiera"
mkdir -p "$OTHER"
printf 'no me borres\n' > "$OTHER/archivo-viejo"
touch -t 202001010000 "$OTHER/archivo-viejo"
t="$(mk_transcript 450000 0)"
printf '{"session_id":"s-E08","transcript_path":"%s"}' "$t" \
  | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$OTHER" bash "$WRITER" >/dev/null 2>&1
[ -f "$OTHER/archivo-viejo" ] && ok || bad E08 "purgo archivos en un directorio que no es ctx-budget"

# Y en el suyo SI purga lo viejo, sin tocar lo reciente.
printf 'viejo\n' > "$CACHE/sesion-abandonada"
touch -t 202001010000 "$CACHE/sesion-abandonada"
printf 'reciente\n' > "$CACHE/sesion-viva"
t="$(mk_transcript 450000 0)"; run_writer s-E09 "$t"
[ ! -f "$CACHE/sesion-abandonada" ] && ok || bad E09 "no purgo una sesion abandonada de hace anios"
[ -f "$CACHE/sesion-viva" ] && ok || bad E10 "purgo una sesion reciente"

# C. Same-task recovery: dispatch the real writer through the compact event.
compact() {
  printf '{"hook_event_name":"SessionStart","source":"compact","session_id":"%s","transcript_path":"%s"}' "$1" "$2" \
    | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="${3:-$CACHE}" bash "$WRITER" >/dev/null 2>&1
}
t="$(mk_transcript 450000 0)"; run_writer recovery-A "$t"; run_writer recovery-B "$t"
compact recovery-A "$t"
[ -z "$(run_reader recovery-A)" ] && ok || bad C01 'compact retained stale warning'
case "$(run_reader recovery-B)" in *CRITICO*) ok ;; *) bad C02 'compact touched another session' ;; esac
# Real transcript compaction boundary must discard older usage at next Stop.
printf '{"type":"system","subtype":"compact_boundary"}\n' >> "$t"
run_writer recovery-A "$t"
[ -z "$(run_reader recovery-A)" ] && ok || bad C03 'Stop resurrected precompact usage'
printf '{"type":"assistant","message":{"usage":{"input_tokens":1000}}}\n' >> "$t"
run_writer recovery-A "$t"
[ -z "$(run_reader recovery-A)" ] && ok || bad C04 'low postcompact context warned'
printf '{"type":"assistant","message":{"usage":{"input_tokens":400000}}}\n' >> "$t"
run_writer recovery-A "$t" CLAUDE_CTX_QUIET=1
case "$(run_reader recovery-A)" in *CRITICO*) ok ;; *) bad C05 'fresh critical warning suppressed' ;; esac
for level in 200000 300000 400000; do
  t="$(mk_transcript "$level" 0)"; run_writer recovery-wording "$t"
  out="$(run_reader recovery-wording)"
  case "$out" in *'/compact'*) ok ;; *) bad C06 'missing same-task compact guidance' ;; esac
  case "$out" in *'/clear'*) bad C07 'warning mandates destructive context reset' ;; *) ok ;; esac
done
# Compact must not reinterpret unsafe keys or delete outside its cache.
printf 'preserve\n' > "$CACHE/.._victim"
compact '../victim' "$t"
[ "$(cat "$CACHE/.._victim")" = preserve ] && ok || bad C08 'unsafe compact key was sanitized into deletion'
printf 'preserve\n' > "$OTHER/victim"
compact victim "$t" "$OTHER"
[ "$(cat "$OTHER/victim")" = preserve ] && ok || bad C09 'compact deleted arbitrary configured file'
mkdir "$TMP_ROOT/linked"
ln -s "$CACHE" "$TMP_ROOT/linked/ctx-budget"
compact recovery-B "$t" "$TMP_ROOT/linked/ctx-budget"
[ -f "$CACHE/recovery-B" ] && ok || bad C10 'compact followed symlinked cache directory'
ln -s "$OTHER/victim" "$CACHE/link-victim"
compact link-victim "$t"
[ -L "$CACHE/link-victim" ] && ok || bad C11 'compact removed untrusted cache symlink'
# Symlink ancestors are also unsafe, even when the cache leaf is a real directory.
mkdir -p "$TMP_ROOT/outside/ctx-budget"
printf 'preserve\n' > "$TMP_ROOT/outside/ctx-budget/victim"
ln -s "$TMP_ROOT/outside" "$TMP_ROOT/alias"
compact victim "$t" "$TMP_ROOT/alias/ctx-budget"
[ -f "$TMP_ROOT/outside/ctx-budget/victim" ] && ok || bad C16 'compact escaped through symlink ancestor'
# Multiple boundaries and ignorable non-object records cannot revive old usage.
printf '{"type":"system","subtype":"compact_boundary"}\nnull\n42\n"ignored"\n' >> "$t"
run_writer recovery-A "$t"
[ -z "$(run_reader recovery-A)" ] && ok || bad C13 'second compact boundary kept old usage'
printf '{"type":"assistant","message":{"usage":{"input_tokens":400000}}}\n' >> "$t"
run_writer recovery-A "$t"
case "$(run_reader recovery-A)" in *CRITICO*) ok ;; *) bad C14 'non-object transcript records hid new critical usage' ;; esac
# Other SessionStart sources are not compact; they preserve the existing cache.
printf '{"hook_event_name":"SessionStart","source":"resume","session_id":"recovery-B"}' \
  | env HOME="$FAKE_HOME" CLAUDE_CTX_CACHE_DIR="$CACHE" bash "$WRITER"
[ -f "$CACHE/recovery-B" ] && ok || bad C15 'resume unexpectedly cleared warning'
# Client settings and shared guidance are executable/configuration contracts.
python3 - "$REPO_DIR" <<'PYTEST'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
settings = json.loads((root/'files/claude/settings.json').read_text())
compact = [g for g in settings['hooks']['SessionStart'] if g.get('matcher') == 'compact'
           and any(h.get('command') == 'bash ~/.claude/hooks/context-budget-measure.sh' for h in g['hooks'])]
assert len(compact) == 1, 'missing unique compact cache invalidation hook'
shared = (root/'files/shared/runtime-budget.md').read_text().strip()
for client in ('files/claude/CLAUDE.md', 'files/codex/AGENTS.md'):
    text = (root/client).read_text()
    block = re.search(r'<!-- gentle-ai:runtime-budget -->.*?<!-- /gentle-ai:runtime-budget -->', text, re.S).group()
    assert block == shared, client
for term in ('quota', 'active tool', 'pending PR', 'same task', 'native compact'):
    assert term in shared, term
claude = (root/'files/claude/CLAUDE.md').read_text().split('<!-- user-override:context-budget')[1].split('## Verificación')[0]
assert '200k' in claude and '300k' in claude and '120k, exige' not in claude
assert '`/clear` al cerrarla' not in claude
PYTEST
[ $? -eq 0 ] && ok || bad C12 'recovery event/guidance contract'

printf 'context-budget: %s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
