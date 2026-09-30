#!/usr/bin/env bash
# Contrato de strip-1m-model.sh (SessionStart).
#
# El hook promete, en su cabecera:
#   1. Sacar el sufijo [1m] CONSERVANDO el modelo elegido.
#   2. Anclar el sufijo al FINAL: un [1m] en otra posicion no es un modelo de
#      un millon y no se toca.
#   3. Fail-open total: sin jq, sin archivo, JSON invalido, sin permiso de
#      escritura -> exit 0 y CERO cambios. Un hook de arranque nunca puede
#      impedir que una sesion arranque.
#   4. Escribir el DESTINO de un symlink, no reemplazar el enlace.
#   5. No dejar "model" vacio en el caso degenerado "[1m]".
#   6. Ser idempotente y no dejar temporales.
#   7. Preservar el resto del archivo intacto.
#
# Cada promesa se mide caso por caso. Escribir el contrato ES la auditoria:
# los agujeros no aparecen leyendo el hook, aparecen al medir lo que promete.
#
# Todos los fixtures viven en un TMPDIR aislado y el hook se apunta ahi con
# CLAUDE_SETTINGS_FILE: la configuracion real del usuario NO se toca nunca.
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="${HOOK_UNDER_TEST:-$REPO_DIR/files/claude/hooks/strip-1m-model.sh}"

[ -f "$HOOK" ] || { printf 'FAIL: no existe el hook bajo prueba: %s\n' "$HOOK" >&2; exit 1; }

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/strip-1m-model-test.XXXXXX")" || exit 1
cleanup() {
  case "${TMP_ROOT:-}" in
    *strip-1m-model-test.*) chmod -R u+rwX "$TMP_ROOT" 2>/dev/null; rm -rf "$TMP_ROOT" ;;
  esac
}
trap cleanup EXIT

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); printf '  FAIL [%s] %s\n' "$1" "$2" >&2; }

CASE_N=0
mkcase() { # mkcase <contenido crudo del settings.json> -> imprime la ruta
  CASE_N=$((CASE_N+1))
  local d="$TMP_ROOT/c$CASE_N"
  mkdir -p "$d"
  printf '%s' "$1" > "$d/settings.json"
  printf '%s' "$d/settings.json"
}

# ---------------------------------------------------------------------------
# Helper central: corre el hook y verifica modelo resultante + rc.
# ---------------------------------------------------------------------------
expect_model() { # expect_model <id> <json de entrada> <modelo esperado o __NONE__>
  local id="$1" json="$2" want="$3" f got rc out
  f="$(mkcase "$json")"
  out="$(CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$id" "el hook devolvio rc=$rc; un hook de arranque SIEMPRE sale 0"
    return
  fi
  got="$(jq -r '.model // "__NONE__"' "$f" 2>/dev/null)" || got="__UNPARSEABLE__"
  if [ "$got" = "$want" ]; then ok; else
    bad "$id" "modelo esperado '$want', quedo '$got'"
  fi
}

# --- A. El caso central: se saca el sufijo y se conserva el modelo ----------
expect_model A01 '{"model":"opus[1m]"}'            'opus'
expect_model A02 '{"model":"sonnet[1m]"}'          'sonnet'
expect_model A03 '{"model":"claude-opus-5[1m]"}'   'claude-opus-5'
expect_model A04 '{"model":"claude-fable-5-1[1m]"}' 'claude-fable-5-1'
expect_model A05 '{"model":"haiku[1m]"}'           'haiku'

# --- B. Modelos SIN sufijo: intocables -------------------------------------
# El harness no elige el pool de cuota del usuario. Cambiar de modelo es libre.
expect_model B01 '{"model":"sonnet"}'              'sonnet'
expect_model B02 '{"model":"opus"}'                'opus'
expect_model B03 '{"model":"claude-fable-5-1"}'    'claude-fable-5-1'
expect_model B04 '{"model":"claude-haiku-4-5-20251001"}' 'claude-haiku-4-5-20251001'
expect_model B05 '{"enableWorkflows":true}'        '__NONE__'
expect_model B06 '{"model":null}'                  '__NONE__'
# OJO: en jq, `//` solo trata null y false como falsy. Una cadena vacia es
# truthy, asi que `.model // "__NONE__"` devuelve "" y NO el centinela. Esperar
# __NONE__ aca era un error del BANCO, no un agujero del hook.
expect_model B07 '{"model":""}'                    ''

# --- C. ANCLAJE. Va al FINAL de la cadena, no en cualquier lado -------------
# Trampa conocida: un anclaje flojo convierte el guard en su contrario.
expect_model C01 '{"model":"[1m]opus"}'            '[1m]opus'
expect_model C02 '{"model":"op[1m]us"}'            'op[1m]us'
expect_model C03 '{"model":"opus[1M]"}'            'opus[1M]'
expect_model C04 '{"model":"opus[2m]"}'            'opus[2m]'
expect_model C05 '{"model":"opus[1m] "}'           'opus[1m] '
expect_model C06 '{"model":"opus1m"}'              'opus1m'
expect_model C07 '{"model":"opus[1m][1m]"}'        'opus[1m]'
# Degenerado: sin modelo base. Dejarlo vacio seria peor que dejarlo como esta.
expect_model C08 '{"model":"[1m]"}'                '[1m]'

# Un modelo sin sufijo al final no solo conserva su valor: el hook NO puede
# escribir el archivo NI anunciar un cambio que no hizo.
#
# Este bloque nacio de un mutante que escapaba (anclaje flojo, `*"[1m]"*`). Con
# el, "[1m]opus" pasaba el `case`, `${model%...}` no encontraba sufijo, el valor
# quedaba igual -- y los casos C solo miraban el valor, asi que daban VERDE.
# Pero el hook reescribia el archivo y ADEMAS imprimia "se quito el sufijo
# [1m] ... queda [1m]opus": mentia. Mirar solo el resultado y no el efecto
# dejaba pasar un hook que miente.
expect_untouched() { # expect_untouched <id> <json de entrada>
  local id="$1" json="$2" f before out
  f="$(mkcase "$json")"
  before="$(cat "$f")"
  out="$(CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" 2>/dev/null)"
  if [ "$(cat "$f")" != "$before" ]; then
    bad "$id" "reescribio un archivo que no tenia sufijo [1m] al final"
    return
  fi
  ok
  if [ -n "$out" ]; then
    bad "${id}b" "anuncio un cambio que no hizo: '$out'"
  else ok; fi
}
expect_untouched C09 '{"model":"[1m]opus"}'
expect_untouched C10 '{"model":"op[1m]us"}'
expect_untouched C11 '{"model":"opus[1M]"}'
expect_untouched C12 '{"model":"opus[2m]"}'
expect_untouched C13 '{"model":"opus[1m] "}'
expect_untouched C14 '{"model":"sonnet"}'

# --- D. Integridad del resto del archivo -----------------------------------
D_JSON='{"model":"opus[1m]","enableWorkflows":true,"permissions":{"defaultMode":"bypassPermissions"},"env":{"FOO":"bar"}}'
f="$(mkcase "$D_JSON")"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
if [ "$(jq -r '.enableWorkflows' "$f" 2>/dev/null)" = "true" ]; then ok; else bad D01 "se perdio enableWorkflows"; fi
if [ "$(jq -r '.permissions.defaultMode' "$f" 2>/dev/null)" = "bypassPermissions" ]; then ok; else bad D02 "se perdio permissions.defaultMode"; fi
if [ "$(jq -r '.env.FOO' "$f" 2>/dev/null)" = "bar" ]; then ok; else bad D03 "se perdio env.FOO"; fi
if [ "$(jq -r 'keys|length' "$f" 2>/dev/null)" = "4" ]; then ok; else bad D04 "cambio la cantidad de claves de nivel superior"; fi

# Un [1m] que vive en OTRA clave (un escape ANSI dentro del comando de un hook)
# no puede ser tocado: el hook opera sobre .model, no sobre el texto del archivo.
D_ANSI='{"model":"sonnet","hooks":{"Stop":[{"hooks":[{"command":"printf '\\033[1mhola\\033[0m'"}]}]}]}'
f="$(mkcase "$D_ANSI")"
before="$(cat "$f")"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
if [ "$(cat "$f")" = "$before" ]; then ok; else bad D05 "toco un archivo sin modelo [1m] (el [1m] estaba en otra clave)"; fi

# Un modelo CON sufijo y ademas un [1m] textual en otra clave: se saca solo el
# del modelo. Este caso separa "opera sobre .model" de "reemplaza en el texto".
D_BOTH='{"model":"opus[1m]","note":"literal [1m] que no se toca"}'
f="$(mkcase "$D_BOTH")"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
if [ "$(jq -r '.model' "$f" 2>/dev/null)" = "opus" ]; then ok; else bad D06 "no saco el sufijo del modelo"; fi
if [ "$(jq -r '.note' "$f" 2>/dev/null)" = "literal [1m] que no se toca" ]; then ok; else bad D07 "modifico un [1m] que no era el del modelo"; fi

# --- E. Fail-open. Ninguna de estas puede romper el arranque ---------------
# E01 archivo ausente
d="$TMP_ROOT/e01"; mkdir -p "$d"
CLAUDE_SETTINGS_FILE="$d/settings.json" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad E01 "rc distinto de 0 sin settings.json"
[ -e "$d/settings.json" ] && bad E02 "creo un settings.json que no existia" || ok

# E03 JSON invalido: NO se toca (reescribirlo lo destruiria)
BROKEN='{"model":"opus[1m]", esto no es json'
f="$(mkcase "$BROKEN")"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok || bad E03 "rc=$rc con JSON invalido"
[ "$(cat "$f")" = "$BROKEN" ] && ok || bad E04 "modifico un settings.json con JSON invalido"

# E13 JSON con la COLA rota. Este es el caso que hace load-bearing a la
# validacion `jq -e .`, y no es obvio: con '{"model":"opus[1m]"}\n{bad',
# `jq -r '.model'` sale con rc=5 pero IGUAL imprime "opus[1m]" por stdout. Como
# la captura del modelo lleva `|| true`, sin la validacion previa el hook
# tomaria ese valor por bueno, reescribiria el archivo y se comeria en silencio
# la parte rota. Lo delato un mutante que quitaba la validacion y escapaba.
STREAM='{"model":"opus[1m]"}
{bad'
f="$(mkcase "$STREAM")"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok || bad E13 "rc=$rc con un JSON de cola rota"
[ "$(cat "$f")" = "$STREAM" ] && ok || bad E14 "reescribio un settings.json con la cola rota (perdida de datos)"

# E15 STREAM de dos objetos validos. Este es el que obliga a que la validacion
# sea ESTRICTA: `jq -e .` sobre un stream devuelve rc=0, asi que un chequeo
# obvio lo deja pasar, y la reescritura devuelve LOS DOS objetos e inyecta
# .model en el segundo. Era un agujero real del hook, no del banco.
STREAM2='{"model":"opus[1m]"}
{"x":1}'
f="$(mkcase "$STREAM2")"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
rc=$?
[ "$rc" -eq 0 ] && ok || bad E15 "rc=$rc con un stream de dos objetos"
[ "$(cat "$f")" = "$STREAM2" ] && ok || bad E16 "reescribio un stream de dos objetos (corrupcion de settings.json)"

# E17 el JSON de nivel superior no es un objeto
for scalar in '"solo-un-string"' '[1,2,3]' '42' 'null'; do
  f="$(mkcase "$scalar")"
  CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
  if [ $? -eq 0 ] && [ "$(cat "$f")" = "$scalar" ]; then ok; else
    bad E17 "toco o fallo con un JSON de nivel superior no-objeto: $scalar"
  fi
done

# E05 archivo vacio
f="$(mkcase '')"
CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad E05 "rc distinto de 0 con archivo vacio"
[ ! -s "$f" ] && ok || bad E06 "escribio sobre un archivo vacio"

# E07 la ruta es un directorio
d="$TMP_ROOT/e07/settings.json"; mkdir -p "$d"
CLAUDE_SETTINGS_FILE="$d" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad E07 "rc distinto de 0 cuando la ruta es un directorio"

# E08 sin jq en el PATH.
# El interprete va por ruta ABSOLUTA a proposito: con un PATH vacio, un `bash`
# sin ruta no se resuelve y el caso no ejercitaria nada -- daria "rojo" sin
# haber corrido jamas el hook. Un caso que no ejercita lo que cree no prueba
# nada.
mkdir -p "$TMP_ROOT/empty-bin"
f="$(mkcase '{"model":"opus[1m]"}')"
CLAUDE_SETTINGS_FILE="$f" PATH="$TMP_ROOT/empty-bin" /bin/bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad E08 "rc distinto de 0 sin jq en el PATH"
[ "$(grep -c '1m' "$f")" -eq 1 ] && ok || bad E09 "modifico el archivo sin jq disponible"

# E10 directorio de solo lectura: no se puede crear el temporal
d="$TMP_ROOT/e10"; mkdir -p "$d"
printf '%s' '{"model":"opus[1m]"}' > "$d/settings.json"
chmod a-w "$d"
CLAUDE_SETTINGS_FILE="$d/settings.json" bash "$HOOK" >/dev/null 2>&1
rc=$?
chmod u+w "$d"
[ "$rc" -eq 0 ] && ok || bad E10 "rc=$rc con el directorio de solo lectura"
[ "$(jq -r '.model' "$d/settings.json")" = "opus[1m]" ] && ok || bad E11 "cambio el archivo en un directorio sin permiso de escritura"

# E12 no deja temporales tirados en NINGUN caso
leftovers="$(find "$TMP_ROOT" -name '.settings.json.*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$leftovers" = "0" ] && ok || bad E12 "dejo $leftovers temporales sin borrar"

# --- F. Symlink: se escribe el destino, el enlace sobrevive -----------------
d="$TMP_ROOT/f01"; mkdir -p "$d/real"
printf '%s' '{"model":"opus[1m]"}' > "$d/real/settings.json"
ln -s "$d/real/settings.json" "$d/link.json"
CLAUDE_SETTINGS_FILE="$d/link.json" bash "$HOOK" >/dev/null 2>&1
[ -L "$d/link.json" ] && ok || bad F01 "el symlink fue reemplazado por un archivo regular"
[ "$(jq -r '.model' "$d/real/settings.json")" = "opus" ] && ok || bad F02 "no escribio el destino del symlink"

# Symlink relativo
d="$TMP_ROOT/f03"; mkdir -p "$d"
printf '%s' '{"model":"sonnet[1m]"}' > "$d/settings.json"
ln -s "settings.json" "$d/rel.json"
CLAUDE_SETTINGS_FILE="$d/rel.json" bash "$HOOK" >/dev/null 2>&1
[ "$(jq -r '.model' "$d/settings.json")" = "sonnet" ] && ok || bad F03 "no resolvio un symlink relativo"

# Symlink colgado
d="$TMP_ROOT/f04"; mkdir -p "$d"
ln -s "$d/no-existe.json" "$d/dangling.json"
CLAUDE_SETTINGS_FILE="$d/dangling.json" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok || bad F04 "rc distinto de 0 con un symlink colgado"

# --- G. Idempotencia y permisos --------------------------------------------
d="$TMP_ROOT/g01"; mkdir -p "$d"
printf '%s' '{"model":"opus[1m]"}' > "$d/settings.json"
# 0640 A PROPOSITO, no 0600: mktemp crea su temporal justo en 0600, asi que un
# fixture en 600 pasaba aunque el hook NO preservara nada. Lo delato un mutante
# que borraba el chmod y escapaba. Un caso puede pasar por la razon equivocada.
chmod 640 "$d/settings.json"
CLAUDE_SETTINGS_FILE="$d/settings.json" bash "$HOOK" >/dev/null 2>&1
first="$(cat "$d/settings.json")"
CLAUDE_SETTINGS_FILE="$d/settings.json" bash "$HOOK" >/dev/null 2>&1
[ "$(cat "$d/settings.json")" = "$first" ] && ok || bad G01 "la segunda corrida no es idempotente"
[ "$(jq -r '.model' "$d/settings.json")" = "opus" ] && ok || bad G02 "la segunda corrida rompio el modelo"
[ "$(stat -f '%Lp' "$d/settings.json" 2>/dev/null)" = "640" ] && ok || bad G03 "no preservo los permisos del archivo original"

# --- H. Ruido: solo habla cuando hace algo ---------------------------------
f="$(mkcase '{"model":"sonnet"}')"
out="$(CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" 2>/dev/null)"
[ -z "$out" ] && ok || bad H01 "imprimio algo sin haber hecho ningun cambio: '$out'"

f="$(mkcase '{"model":"opus[1m]"}')"
out="$(CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" 2>/dev/null)"
case "$out" in *opus*) ok ;; *) bad H02 "no informo el cambio (salida: '$out')" ;; esac

# El caso degenerado avisa pero no toca.
f="$(mkcase '{"model":"[1m]"}')"
out="$(CLAUDE_SETTINGS_FILE="$f" bash "$HOOK" 2>/dev/null)"
[ -n "$out" ] && ok || bad H03 "no aviso del modelo degenerado \"[1m]\""

# --- I. El source versionado nunca puede traer un modelo [1m] --------------
if [ -f "$REPO_DIR/files/claude/settings.json" ]; then
  if grep -Eq '"model": *"[^"]*\[1m\]"' "$REPO_DIR/files/claude/settings.json"; then
    bad I01 "files/claude/settings.json trae un modelo [1m]"
  else ok; fi
fi

printf 'strip-1m-model: %s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
