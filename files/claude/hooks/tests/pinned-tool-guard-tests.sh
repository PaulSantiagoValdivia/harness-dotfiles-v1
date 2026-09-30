#!/usr/bin/env bash
# Contrato de ~/.claude/hooks/pinned-tool-guard.sh
#
# El hook decide por el TEXTO del comando Y por el ESTADO del filesystem
# (existencia de node_modules/.bin/<tool>), asi que la suite arma fixtures de
# paquetes sinteticos. Modelo mixto: force-push-guard-tests.sh (texto) +
# deploy-checkout-guard-tests.sh (fixtures).
#
# Los payloads viven DENTRO de este archivo a proposito: nombrar `npx <tool>`
# en la linea de comando dispara el propio guard que estamos probando.
#
# rc=2 -> BLOQUEA (deny).  rc=0 -> PASA (allow / fail-open).

set -uo pipefail

HOOK="${HOOK:-$HOME/.claude/hooks/pinned-tool-guard.sh}"
[ -f "$HOOK" ] || { echo "FAIL: no existe $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq no disponible"; exit 0; }

PASS=0; FAIL=0

FX="$(mktemp -d)"
HOMEFX="$(mktemp -d "$HOME/.pinned-tool-guard-fx.XXXXXX")"
trap 'rm -rf "$FX" "$HOMEFX"' EXIT

mkpkg() { # <ruta> [binarios...]
  local d="$1"; shift
  mkdir -p "$d"
  printf '{"name":"fx"}\n' > "$d/package.json"
  if [ "$#" -gt 0 ]; then
    mkdir -p "$d/node_modules/.bin"
    local b
    for b in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$d/node_modules/.bin/$b"; chmod +x "$d/node_modules/.bin/$b"; done
  fi
}

# --- fixtures ---------------------------------------------------------------
mkpkg "$FX/con-bin" prettier eslint tsc vitest   # paquete con todo instalado
mkpkg "$FX/sin-bin"                              # package.json sin node_modules
mkdir -p "$FX/con-bin/src/deep" "$FX/sin-bin/src" # subdirs: obligan a subir el árbol
mkpkg "$FX/solo-eslint" eslint                   # eslint local, prettier AUSENTE
mkpkg "$FX/mono" prettier                        # monorepo: bin hoisteado en la raiz
mkpkg "$FX/mono/apps/web"                        #   workspace sin .bin propio
mkdir -p "$FX/sin pkg"                           # ni package.json ni node_modules
mkpkg "$HOMEFX/sin-bin"                          # bajo $HOME, para probar `cd ~/...`

# --- runner -----------------------------------------------------------------
run() { # <cwd> <comando> -> imprime rc
  local cwd="$1" cmd="$2" json rc
  json="$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')"
  ( cd "$cwd" 2>/dev/null && printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  printf '%s' "$rc"
}

check() { # <esperado 0|2> <etiqueta> <cwd> <comando>
  local want="$1" label="$2" cwd="$3" cmd="$4" got
  got="$(run "$cwd" "$cmd")"
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); printf 'PASS  %s\n' "$label"
  else
    FAIL=$((FAIL+1)); printf 'FAIL  %s  (esperaba rc=%s, obtuvo rc=%s)\n' "$label" "$want" "$got"
  fi
}

check_raw() { # <esperado> <etiqueta> <stdin literal>
  local want="$1" label="$2" payload="$3" got
  printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); printf 'PASS  %s\n' "$label"
  else FAIL=$((FAIL+1)); printf 'FAIL  %s  (esperaba rc=%s, obtuvo rc=%s)\n' "$label" "$want" "$got"; fi
}

# Nombres de las herramientas armados en runtime: escribirlos pegados a `npx`
# en este archivo no molesta (no se ejecuta), pero se mantiene el mismo estilo
# que el resto de la suite para que grepear la suite no dispare el guard.
N=npx; P=prettier; E=eslint; T=tsc; V=vitest

echo "== PROMESA: lo que la cabecera del hook declara =="
check 2 "P1  sin binario local -> BLOQUEA"                 "$FX/sin-bin" "$N $P --write ."
check 0 "P2  con binario local -> PASA"                    "$FX/con-bin" "$N $P --write ."
check 0 "P3  npx de OTRA herramienta (vite) -> PASA"       "$FX/sin-bin" "$N vite build"
check 0 "P4  comando sin npx -> PASA"                      "$FX/sin-bin" "git status --short"
check 2 "P5  $E sin binario local -> BLOQUEA"              "$FX/sin-bin" "$N $E ."
check 2 "P6  $T sin binario local -> BLOQUEA"              "$FX/sin-bin" "$N $T --noEmit"
check 2 "P7  $V sin binario local -> BLOQUEA"              "$FX/sin-bin" "$N $V run"
check 0 "P8  $E con binario local -> PASA"                 "$FX/con-bin" "$N $E ."
check 0 "P9  sin package.json en toda la cadena -> PASA"   "$FX/sin pkg" "$N $P --write ."

echo
echo "== FAIL-OPEN ante lo no parseable =="
check_raw 0 "FO1 stdin que no es JSON -> PASA"             "esto no es json pero dice npx $P"
check_raw 0 "FO2 JSON sin .tool_input.command -> PASA"     '{"tool_name":"Bash","tool_input":{}}'
check_raw 0 "FO3 command vacio -> PASA"                    '{"tool_name":"Bash","tool_input":{"command":""}}'

echo
echo "== A1 ADYACENCIA npx/herramienta (clase repetida: firebase --project X deploy) =="
check 2 "A1a --yes entre npx y la herramienta"             "$FX/sin-bin" "$N --yes $P --write ."
check 2 "A1b -y entre npx y la herramienta"                "$FX/sin-bin" "$N -y $P --write ."
check 2 "A1c -p <pkg>@<ver> <tool> (version flotante explicita)" "$FX/sin-bin" "$N -p $P@3.9.6 $P --write ."
check 2 "A1d --package=<pkg> <tool>"                       "$FX/sin-bin" "$N --package=$P $P --write ."
check 2 "A1e -p typescript $T (idiom oficial de npx)"      "$FX/sin-bin" "$N -p typescript $T --noEmit"
check 2 "A1f --no-install <tool> (igual falta npm ci)"     "$FX/sin-bin" "$N --no-install $P --write ."
check 0 "A1g --yes CON binario local -> no molesta"        "$FX/con-bin" "$N --yes $P --write ."
check 0 "A1h flags npx + OTRA herramienta -> PASA"         "$FX/sin-bin" "$N --yes vite build"

echo
echo "== A2 SEPARADOR entre npx y la herramienta =="
check 2 "A2a dos espacios"                                 "$FX/sin-bin" "$N  $P --write ."
check 2 "A2b tabulador"                                    "$FX/sin-bin" "$(printf '%s\t%s --write .' "$N" "$P")"

echo
echo "== A3 AMBITO del cd: solo cuenta el cd ANTERIOR a esa invocacion =="
check 2 "A3a cd sin-bin && npx <tool> ; cd con-bin (cd POSTERIOR no salva)" \
        "$FX" "cd $FX/sin-bin && $N $P --write . ; cd $FX/con-bin"
check 2 "A3b cd dentro de un echo POSTERIOR no salva" \
        "$FX" "cd $FX/sin-bin; $N $P --write .; echo 'ahora cd $FX/con-bin'"
check 0 "A3c cd con-bin && npx <tool> -> PASA"             "$FX" "cd $FX/con-bin && $N $P --write ."
check 2 "A3d cd sin-bin && npx <tool> -> BLOQUEA"          "$FX" "cd $FX/sin-bin && $N $P --write ."
check 2 "A3e cd con-bin && npx <tool> && cd sin-bin && npx <tool2>" \
        "$FX" "cd $FX/con-bin && $N $P --write . && cd $FX/sin-bin && $N $E ."
check 0 "A3f cd por invocacion: la que importa esta en con-bin" \
        "$FX" "cd $FX/sin-bin && $N vite build && cd $FX/con-bin && $N $P --write ."
check 2 "A3g cd con ~ se expande a \$HOME"                 "$FX" "cd ~/${HOMEFX##*/}/sin-bin && $N $P --write ."

echo
echo "== A4 se evaluan TODAS las invocaciones, no solo la primera =="
check 2 "A4a $E local OK + $P AUSENTE, $E primero"         "$FX/solo-eslint" "$N $E . && $N $P --write ."
check 2 "A4b $E local OK + $P AUSENTE, $P primero"         "$FX/solo-eslint" "$N $P --write . && $N $E ."
check 0 "A4c ambos locales -> PASA"                        "$FX/con-bin" "$N $E . && $N $P --write ."
check 2 "A4d tres invocaciones, la del medio falta"        "$FX/solo-eslint" "$N $E . ; $N $V run ; $N $E ."

echo
echo "== S SUBIDA DEL ARBOL: npx desde un subdirectorio del paquete =="
check 0 "S1  desde <pkg>/src con bin en la raiz del pkg -> PASA"   "$FX/con-bin/src" "$N $P --write ."
check 2 "S2  desde <pkg>/src SIN bin en la raiz del pkg -> BLOQUEA" "$FX/sin-bin/src" "$N $P --write ."
check 0 "S3  dos niveles abajo, bin en la raiz del pkg -> PASA"    "$FX/con-bin/src/deep" "$N $P --write ."
check 2 "S4  cd a un subdirectorio y luego npx"                    "$FX" "cd $FX/sin-bin/src && $N $P --write ."

echo
echo "== F1 FRONTERA de la herramienta: paquetes DISTINTOS no se bloquean =="
check 0 "F1a ${T}-alias no es $T"                          "$FX/sin-bin" "$N ${T}-alias -p tsconfig.json"
check 0 "F1b ${P}-eslint no es $P"                         "$FX/sin-bin" "$N ${P}-eslint ."
check 0 "F1c ${V}-preview no es $V"                        "$FX/sin-bin" "$N ${V}-preview run"
check 0 "F1d ${E}-config-prettier no es $E"                "$FX/sin-bin" "$N ${E}-config-$P"
check 0 "F1e ${E}_d no es $E"                              "$FX/sin-bin" "$N ${E}_d ."
check 2 "F1f <tool>@<version> SI es la herramienta"        "$FX/sin-bin" "$N $P@3.9.6 --write ."
check 2 "F1g la herramienta como ultimo token del comando" "$FX/sin-bin" "$N $T"

echo
echo "== LIMITES fijados A PROPOSITO (medidos, no descuidos) =="
check 0 "L1a pnpm dlx fuera del contrato (decision de producto)" "$FX/sin-bin" "pnpm dlx $P --write ."
check 0 "L1b bunx fuera del contrato"                      "$FX/sin-bin" "bunx $P --write ."
check 0 "L1c yarn dlx fuera del contrato"                  "$FX/sin-bin" "yarn dlx $P --write ."
check 2 "L2  monorepo con hoisting: el bin del padre NO prueba el pin del hijo" \
        "$FX/mono/apps/web" "$N $P --write ."
check 0 "L3  cd a ruta con espacios no se resuelve -> fail-open" \
        "$FX" "cd \"$FX/sin pkg\" && $N $P --write ."
check 2 "L4  cd relativo no resoluble cae al cwd del proceso" \
        "$FX/sin-bin" "cd - && $N $P --write ."
check 2 "L5  texto entre comillas se toma como comando"    "$FX/sin-bin" "git commit -m 'evitar $N $P flotante'"
check 2 "L6  ...y por eso bash -c '<comando real>' SI se bloquea" \
        "$FX/sin-bin" "bash -c \"$N $P --write .\""

echo
printf 'Resultado: %s PASS / %s FAIL\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
