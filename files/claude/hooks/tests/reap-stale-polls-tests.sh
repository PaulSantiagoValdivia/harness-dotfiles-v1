#!/usr/bin/env bash
# Suite de contrato de reap-stale-polls.sh
#
# Por que un banco SINTETICO y no procesos reales: este hook es MACHINE-WIDE y
# ejecuta kill de verdad sobre cualquier proceso de la maquina en cada Stop.
# Correrlo contra procesos reales para probarlo mataria loops legitimos de otras
# sesiones y del runner de CI — el dano exacto que el hook promete no hacer.
# Por eso la suite fabrica una TABLA DE PROCESOS y stubea ps/pkill; `kill` es
# builtin de bash, asi que va por funcion exportada (PATH no lo intercepta).
#
# Formato de la tabla:  pid <TAB> ppid <TAB> etime <TAB> command...
set -uo pipefail

HOOK="${REAP_HOOK:-$HOME/.claude/hooks/reap-stale-polls.sh}"
[ -f "$HOOK" ] || { echo "FATAL: no existe $HOOK"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reap-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.claude"

cat >"$TMP/bin/ps" <<'PSEOF'
#!/usr/bin/env bash
T="${FAKE_PS_TABLE:?}"
mode=""; want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -eo) mode="list"; shift 2;;
    -o) case "$2" in ppid=*) mode="ppid";; command=*) mode="command";; esac; shift 2;;
    -p) want="$2"; shift 2;;
    *) shift;;
  esac
done
[ -n "$mode" ] || mode="exists"

# El TSV no puede representar un campo VACIO: el tab es IFS-whitespace, asi que
# `read` colapsa los campos vacios y la linea se relee corrida. Para probar como
# parsea el HOOK una linea rara de ps, se emiten lineas CRUDAS desde FAKE_PS_RAW.
if [ "$mode" = "list" ] && [ -n "${FAKE_PS_RAW:-}" ] && [ -f "$FAKE_PS_RAW" ]; then
  cat "$FAKE_PS_RAW"
fi

# Auto-proteccion: el hook se saltea su propio $$ y su $PPID. Esos PIDs solo se
# conocen en tiempo de ejecucion, asi que el stub sube por sus ancestros (con el
# ps REAL, solo lectura) hasta encontrar el proceso del hook, y fabrica para el
# una linea de polling viejo. Si el hook se mata a si mismo, el caso lo ve.
if [ "$mode" = "list" ] && [ "${FAKE_PS_SELF:-0}" = "1" ]; then
  # El stub es el primer comando del pipeline dentro del `< <(...)` del hook:
  # su padre es la subshell del process substitution, y la madre de esa subshell
  # ES el hook. Dos saltos FIJOS. Buscar al hook por nombre no sirve: engancha
  # ancestros ajenos que llevan el path en su argv (medido: identificaba 16142
  # cuando el hook era 16221), y ademas hace el caso no determinista.
  hook_pid="$(/bin/ps -o ppid= -p "$$" 2>/dev/null | tr -d ' ')"
  [ -n "$hook_pid" ] && hook_pid="$(/bin/ps -o ppid= -p "$hook_pid" 2>/dev/null | tr -d ' ')"
  hook_ppid=""
  [ -n "$hook_pid" ] && hook_ppid="$(/bin/ps -o ppid= -p "$hook_pid" 2>/dev/null | tr -d ' ')"
  if [ -n "$hook_pid" ]; then
    printf '%5s %11s %s\n' "$hook_pid" "20:00" "${FAKE_SELF_CMD:?}"
    [ -n "$hook_ppid" ] && printf '%5s %11s %s\n' "$hook_ppid" "20:00" "${FAKE_SELF_CMD:?}"
  fi
fi

[ -f "$T" ] || { [ "$mode" = "exists" ] && exit 1; exit 0; }
while IFS=$'\t' read -r pid ppid etime cmd; do
  [ -n "$pid" ] || continue
  case "$mode" in
    list)    printf '%5s %11s %s\n' "$pid" "$etime" "$cmd";;
    ppid)    [ "$pid" = "$want" ] && echo "$ppid";;
    command) [ "$pid" = "$want" ] && echo "$cmd";;
    exists)  [ "$pid" = "$want" ] && exit 0;;
  esac
done <"$T"
[ "$mode" = "exists" ] && exit 1
exit 0
PSEOF

cat >"$TMP/bin/pkill" <<'PKEOF'
#!/usr/bin/env bash
echo "pkill $*" >>"${FAKE_KILL_LOG:?}"
exit 0
PKEOF
chmod +x "$TMP/bin/ps" "$TMP/bin/pkill"

# `kill` es builtin: la funcion exportada tiene precedencia en el bash hijo.
kill() { echo "kill $*" >>"${FAKE_KILL_LOG:?}"; }
export -f kill

PASS=0; FAIL=0; FAILED_NAMES=()

# tabla <pid> <ppid> <etime> <cmd> [pid ppid etime cmd ...]
tabla() {
  : >"$TMP/table.tsv"
  while [ $# -ge 4 ]; do
    printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$TMP/table.tsv"
    shift 4
  done
}

# corre el hook contra la tabla actual. Env extra por variables REAP_ENV[].
REAP_ENV=()
# bash 3.2 (macOS) revienta con "${arr[@]}" sobre un array VACIO bajo set -u:
# la expansion va siempre protegida con ${arr[@]+...}.
correr() {
  : >"$TMP/killed.log"
  : >"$TMP/home/.claude/reaped-polls.log"
  OUT="$(env PATH="$TMP/bin:$PATH" \
             FAKE_PS_TABLE="$TMP/table.tsv" \
             FAKE_KILL_LOG="$TMP/killed.log" \
             HOME="$TMP/home" \
             ${REAP_ENV[@]+"${REAP_ENV[@]}"} bash "$HOOK" 2>&1)"
  RC=$?
  # Sin `grep -q` al final de un pipe: bajo pipefail cierra el pipe al primer
  # match, el productor muere por SIGPIPE y el pipeline devuelve !=0 CON el
  # match presente. Se compara siempre sobre variables ya capturadas.
  KILLS="$(cat "$TMP/killed.log")"
  LOGFILE="$(cat "$TMP/home/.claude/reaped-polls.log" 2>/dev/null)"
  REAP_ENV=()
}

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }

# Espera que el hook HAYA matado exactamente estos pids (orden irrelevante).
esperar_kill() { # <nombre> <pid>...
  local name="$1"; shift
  local faltan="" sobran=""
  local p
  for p in "$@"; do
    case "$KILLS" in *"kill $p"*) ;; *) faltan="$faltan $p";; esac
  done
  local linea
  while IFS= read -r linea; do
    [ -n "$linea" ] || continue
    case "$linea" in kill\ -9\ *) continue;; kill\ *) ;; *) continue;; esac
    local kp="${linea#kill }"
    local encontrado=0
    for p in "$@"; do [ "$kp" = "$p" ] && encontrado=1; done
    [ "$encontrado" = "0" ] && sobran="$sobran $kp"
  done <<<"$KILLS"
  if [ -n "$faltan" ] || [ -n "$sobran" ]; then
    bad "$name" "esperaba matar [$*]; faltaron:[${faltan:-ninguno}] sobraron:[${sobran:-ninguno}]"
  else ok; fi
}

esperar_sin_kill() { # <nombre>
  local name="$1"
  if [ -n "$KILLS" ]; then bad "$name" "NO debia matar nada, pero mato: $(echo "$KILLS" | tr '\n' ' ')"
  else ok; fi
}

esperar_rc0() { # <nombre>
  [ "$RC" = "0" ] && ok || bad "$1" "exit esperado 0, obtenido $RC"
}

contiene() { # <nombre> <texto-esperado> <cadena>
  case "$3" in *"$2"*) ok;; *) bad "$1" "esperaba encontrar '$2' en: ${3:-<vacio>}";; esac
}

no_contiene() { # <nombre> <texto-prohibido> <cadena>
  case "$3" in *"$2"*) bad "$1" "NO debia aparecer '$2' en: $3";; *) ok;; esac
}

LOOP='bash -c until curl -sf localhost:9999; do sleep 5; done'
VIEJO="20:00"

echo "== G1  deteccion del patron: que ES un loop de polling =="

tabla 101 1 "$VIEJO" "$LOOP";                                  correr; esperar_kill "G1.01 until+sleep viejo se mata" 101
tabla 102 1 "$VIEJO" 'bash -c while ! ok; do sleep 5; done';    correr; esperar_kill "G1.02 while+sleep se mata" 102
tabla 103 1 "$VIEJO" 'bash -c while true; do sleep 30; done';   correr; esperar_kill "G1.03 while true; do sleep se mata" 103
tabla 104 1 "$VIEJO" 'bash -c until ok; do sleep 5; done; echo fin'; correr; esperar_kill "G1.04 loop con cola despues del done" 104
tabla 105 1 "$VIEJO" 'sleep 3600';                              correr; esperar_sin_kill "G1.05 sleep suelto sin loop no se toca"
tabla 106 1 "$VIEJO" 'bash -c until ok; do date; done';         correr; esperar_sin_kill "G1.06 loop SIN sleep no se toca"
tabla 107 1 "$VIEJO" 'bash -c untilx ok; do sleep 5; done';     correr; esperar_sin_kill "G1.07 untilx no es until (exige separador)"
tabla 108 1 "$VIEJO" 'bash -c until ok; do sleep5; done';       correr; esperar_sin_kill "G1.08 sleep5 no es sleep (exige separador)"
tabla 109 1 "$VIEJO" 'bash -c UNTIL ok; do SLEEP 5; done';      correr; esperar_sin_kill "G1.09 el patron es sensible a mayusculas"
tabla 110 1 "$VIEJO" 'bash -c for i in 1 2 3; do sleep 5; done'; correr; esperar_sin_kill "G1.10 LIMITE A PROPOSITO: for+sleep es espera acotada"
tabla 111 1 "$VIEJO" 'bash -c until ok; do sleep; done';        correr; esperar_sin_kill "G1.11 LIMITE: sleep sin argumento no matchea"

echo "== G2  el hook NO puede ser ciego a los loops que usan grep =="

tabla 201 1 "$VIEJO" 'bash -c until ls x | grep -v pass | grep pass; do sleep 5; done'
correr; esperar_kill "G2.01 EL CASO QUE ORIGINO EL HOOK (grep -v pass | grep pass)" 201
tabla 202 1 "$VIEJO" 'bash -c until grep -q ok out.txt; do sleep 5; done'
correr; esperar_kill "G2.02 loop que espera con grep" 202
tabla 203 1 "$VIEJO" 'bash -c until egrep ok out.txt; do sleep 5; done'
correr; esperar_kill "G2.03 loop con egrep" 203
tabla 204 1 "$VIEJO" 'bash -c until /usr/local/grepper/bin/check; do sleep 5; done'
correr; esperar_kill "G2.04 la subcadena grep dentro de un path ajeno" 204
tabla 205 1 "$VIEJO" 'bash -c until rg ok out.txt; do sleep 5; done'
correr; esperar_kill "G2.05 control: el mismo loop con rg" 205
tabla 206 1 "$VIEJO" 'bash -c until ls | ripgrep ok; do sleep 5; done'
correr; esperar_kill "G2.06 ripgrep contiene grep como subcadena" 206

echo "== G3  falsos positivos: mencionar el patron no es correrlo =="

tabla 301 1 "$VIEJO" 'node /srv/app/server.js --watch';         correr; esperar_sin_kill "G3.01 dev server no se toca"
tabla 302 1 "$VIEJO" 'rg -n while true; do sleep 5; done /srv';  correr; esperar_sin_kill "G3.02 rg BUSCANDO el patron no es un loop"
tabla 303 1 "$VIEJO" 'grep -rn while true; do sleep 5; done /srv'; correr; esperar_sin_kill "G3.03 grep buscando el patron no es un loop"
tabla 304 1 "$VIEJO" 'vim /tmp/until ok; do sleep 5; done.md';   correr; esperar_sin_kill "G3.04 un editor con el patron en el nombre del archivo"
tabla 305 1 "$VIEJO" 'codex exec arregla el until ok; do sleep 5; done del script'
correr; esperar_sin_kill "G3.05 un agente con el patron en su prompt"
tabla 306 1 "$VIEJO" 'tail -f /var/log/app.log';                correr; esperar_sin_kill "G3.06 tail -f no se toca"
tabla 307 1 "$VIEJO" 'node_modules/.bin/webpack --watch';       correr; esperar_sin_kill "G3.07 bundler en watch no se toca"

echo "== G4  umbral de edad =="

tabla 401 1 "04:59" "$LOOP"; correr; esperar_sin_kill "G4.01 299s < 300 no se mata"
tabla 402 1 "05:00" "$LOOP"; correr; esperar_kill "G4.02 300s == umbral se mata (>=)" 402
tabla 403 1 "05:01" "$LOOP"; correr; esperar_kill "G4.03 301s > umbral se mata" 403
tabla 404 1 "00:30" "$LOOP"; REAP_ENV=(CLAUDE_POLL_STALE_SECS=10); correr; esperar_kill "G4.04 umbral custom mas bajo" 404
tabla 405 1 "20:00" "$LOOP"; REAP_ENV=(CLAUDE_POLL_STALE_SECS=99999); correr; esperar_sin_kill "G4.05 umbral custom mas alto perdona"
tabla 406 1 "00:01" "$LOOP"; REAP_ENV=(CLAUDE_POLL_STALE_SECS=0); correr; esperar_kill "G4.06 umbral 0 mata todo lo que matchee" 406

echo "== G5  umbral invalido: un hook que MATA no puede fallar hacia el gatillo =="

# El valor VACIO queda FUERA de esta lista a proposito: `${VAR:-default}` trata
# vacio igual que no-seteado, asi que cae al default sin avisar. Es el
# comportamiento correcto (una variable vacia es "no configurada", no un error
# del usuario) y se fija como caso aparte mas abajo.
for v in 5m abc 300s 1e3 " "; do
  tabla 501 1 "00:30" "$LOOP"; REAP_ENV=(CLAUDE_POLL_STALE_SECS="$v"); correr
  esperar_sin_kill "G5 umbral invalido '<$v>' NO puede matar un proceso joven"
  contiene "G5 umbral invalido '<$v>' avisa por stderr" "CLAUDE_POLL_STALE_SECS" "$OUT"
done
tabla 502 1 "20:00" "$LOOP"; REAP_ENV=(CLAUDE_POLL_STALE_SECS=5m); correr
esperar_kill "G5.07 con umbral invalido cae al default y el VIEJO igual se mata" 502
tabla 503 1 "00:30" "$LOOP"; REAP_ENV=(CLAUDE_POLL_STALE_SECS=); correr
esperar_sin_kill "G5.08 LIMITE: valor vacio == no configurado, cae al default"
no_contiene "G5.09 LIMITE: valor vacio no hace ruido" "CLAUDE_POLL_STALE_SECS" "$OUT"

echo "== G6  parseo de etime =="

tabla 601 1 "45" "$LOOP";          REAP_ENV=(CLAUDE_POLL_STALE_SECS=40); correr; esperar_kill "G6.01 etime SS" 601
tabla 602 1 "10:00" "$LOOP";       correr; esperar_kill "G6.02 etime MM:SS" 602
tabla 603 1 "01:00:00" "$LOOP";    correr; esperar_kill "G6.03 etime HH:MM:SS" 603
tabla 604 1 "2-03:04:05" "$LOOP";  correr; esperar_kill "G6.04 etime DD-HH:MM:SS" 604
tabla 605 1 "08:09" "$LOOP";       REAP_ENV=(CLAUDE_POLL_STALE_SECS=488); correr; esperar_kill "G6.05 ceros a la izquierda en base 10, no octal" 605
tabla 606 1 "00:08" "$LOOP";       REAP_ENV=(CLAUDE_POLL_STALE_SECS=9); correr; esperar_sin_kill "G6.06 08 segundos < 9 (base 10)"
tabla 607 1 "1:2:3:4" "$LOOP";     correr; esperar_sin_kill "G6.07 etime de 4 campos cae a 0 y no se mata"

echo "== G7  etime no parseable: tampoco puede fallar hacia el gatillo =="

# Los tres primeros los descarta el pre-filtro de formato; los que siguen
# PASAN ese filtro (solo digitos, ':', '.', '-') y llegan al parser: son los que
# de verdad ejercitan la validacion de etime_to_secs. Sin ellos, quitar esa
# validacion es un mutante que ESCAPA (medido 2026-09-08).
for e in "??:??" "-" "a:b" "??" "1.5" "1..2" "12.34.56" "9-" "::"; do
  tabla 701 1 "$e" "$LOOP"; correr
  esperar_sin_kill "G7 etime no parseable '<$e>' NO puede matar"
  esperar_rc0 "G7 etime no parseable '<$e>' igual sale 0"
done

echo "== G8  auto-proteccion y entradas mutiladas =="

# El PID del hook y el de su padre solo existen en ejecucion: los fabrica el
# stub (ver FAKE_PS_SELF). Si el hook se matara a si mismo, el turno del usuario
# se llevaria por delante al propio Stop hook.
: >"$TMP/table.tsv"
REAP_ENV=(FAKE_PS_SELF=1 FAKE_SELF_CMD="$LOOP"); correr
esperar_sin_kill "G8.01 NO se mata a si mismo ni mata a su proceso padre"

tabla "PID" 1 "$VIEJO" "$LOOP";    correr; esperar_sin_kill "G8.02 la cabecera de ps (pid no numerico) se saltea"
tabla "12ab" 1 "$VIEJO" "$LOOP";   correr; esperar_sin_kill "G8.03 pid alfanumerico se saltea"

# Lineas CRUDAS: lo que el hook recibiria de un ps con salida mutilada.
: >"$TMP/table.tsv"
printf '%s\n' " $LOOP" > "$TMP/raw.txt"
REAP_ENV=(FAKE_PS_RAW="$TMP/raw.txt"); correr
esperar_sin_kill "G8.04 linea sin pid (ps mutilado) no se convierte en un kill"
printf '%s\n' "" "   " > "$TMP/raw.txt"
REAP_ENV=(FAKE_PS_RAW="$TMP/raw.txt"); correr
esperar_sin_kill "G8.05 lineas en blanco no se convierten en un kill"
printf '%s\n' "  PID       ELAPSED ARGS" > "$TMP/raw.txt"
REAP_ENV=(FAKE_PS_RAW="$TMP/raw.txt"); correr
esperar_sin_kill "G8.06 la cabecera literal de ps no se convierte en un kill"

# El hook se excluye a si mismo por NOMBRE: es su proteccion real en produccion
# (el Stop hook de otra sesion no debe matar al de esta).
: >"$TMP/table.tsv"
printf '%s\n' " 4242       20:00 bash /Users/x/.claude/hooks/reap-stale-polls.sh" > "$TMP/raw.txt"
REAP_ENV=(FAKE_PS_RAW="$TMP/raw.txt"); correr
esperar_sin_kill "G8.09 no mata a otra instancia del propio hook"

# El caso anterior NO ejercita la exclusion por nombre: esa linea no lleva el
# patron de polling, asi que el pre-filtro ya la descarta (medido: quitar el
# `grep -v reap-stale-polls` no rompia ningun caso). Para que la exclusion
# importe, el proceso tiene que mencionar al hook Y tener forma de loop.
tabla 4243 1 "$VIEJO" 'bash -c until pgrep -f reap-stale-polls; do sleep 5; done'
correr; esperar_sin_kill "G8.10 un loop que MENCIONA al hook queda excluido por nombre"

: >"$TMP/table.tsv";               correr; esperar_sin_kill "G8.07 tabla vacia no mata nada"
: >"$TMP/table.tsv";               correr; esperar_rc0 "G8.08 tabla vacia sale 0"

echo "== G9  inmunidad del actions-runner =="

RUNNER='/Users/runner/actions-runner/bin/Runner.Worker'
tabla 901 902 "$VIEJO" 'bash -c until [ -f /tmp/emu ]; do sleep 5; done' 902 1 "30:00" "$RUNNER"
correr; esperar_sin_kill "G9.01 hijo directo del runner es inmune"
tabla 903 904 "$VIEJO" 'bash -c until [ -f /tmp/emu ]; do sleep 5; done' 904 905 "30:00" 'bash step' 905 1 "30:00" "$RUNNER"
correr; esperar_sin_kill "G9.02 nieto del runner es inmune"
tabla 906 907 "$VIEJO" 'bash -c until ok; do sleep 5; done' 907 1 "30:00" '/opt/actions-runner/run.sh'
correr; esperar_sin_kill "G9.03 reconoce actions-runner por path"
tabla 908 909 "$VIEJO" 'bash -c until ok; do sleep 5; done' 909 1 "30:00" 'Runner.Listener'
correr; esperar_sin_kill "G9.04 reconoce Runner.Listener"
tabla 910 911 "$VIEJO" 'bash -c until ok; do sleep 5; done' 911 1 "30:00" 'bash /srv/mi-script.sh'
correr; esperar_kill "G9.05 un ancestro que NO es del runner no da inmunidad" 910
tabla 912 912 "$VIEJO" 'bash -c until ok; do sleep 5; done'
correr; esperar_kill "G9.06 ppid que apunta a si mismo no cuelga la busqueda" 912

echo "== G10  bitacora y ruido =="

tabla 1001 1 "$VIEJO" "$LOOP"; correr
contiene "G10.01 loguea el pid matado"        "pid=1001"          "$LOGFILE"
contiene "G10.02 loguea la edad"              "edad=1200s"        "$LOGFILE"
contiene "G10.03 avisa por stderr"            "reaped stale poll" "$OUT"
contiene "G10.04 resume cuantos mato"         "1 loop"            "$OUT"
tabla 1002 1 "00:10" "$LOOP"; correr
esperar_sin_kill "G10.05 sin victimas no mata"
no_contiene "G10.06 sin victimas no ensucia el log" "pid=" "$LOGFILE"
no_contiene "G10.07 sin victimas no habla por stderr" "reaped" "$OUT"

echo "== G11  BOUNDED_WAIT_OK: esperas acotadas exentas =="

tabla 1101 1 "$VIEJO" 'bash -c i=0; until ok || [ $i -ge 20 ]; do sleep 30; i=$((i+1)); done  # BOUNDED_WAIT_OK'
correr; esperar_sin_kill "G11.01 marcador al final exime"
tabla 1102 1 "$VIEJO" 'bash -c # BOUNDED_WAIT_OK  i=0; until ok; do sleep 30; done'
correr; esperar_sin_kill "G11.02 marcador al principio exime"
tabla 1103 1 "$VIEJO" 'bash -c until ok; do sleep 30; done  # bounded_wait_ok'
correr; esperar_kill "G11.03 el marcador en minusculas NO exime (es literal)" 1103

echo "== G12  contrato de salida: nunca bloquea el turno =="

tabla 1201 1 "$VIEJO" "$LOOP"; correr; esperar_rc0 "G12.01 sale 0 cuando mata"
tabla 1202 1 "00:10" "$LOOP"; correr; esperar_rc0 "G12.02 sale 0 cuando no mata"
tabla 1203 1 "$VIEJO" "$LOOP"
: >"$TMP/killed.log"
OUT="$(env PATH="$TMP/bin:$PATH" FAKE_PS_TABLE="$TMP/table.tsv" FAKE_KILL_LOG="$TMP/killed.log" \
        HOME="$TMP/home/no-existe-este-dir" bash "$HOOK" 2>&1)"; RC=$?
esperar_rc0 "G12.03 sale 0 aunque el log no se pueda escribir"
KILLS="$(cat "$TMP/killed.log")"
esperar_kill "G12.04 y aun asi hace su trabajo" 1203

echo
echo "Resultado: $PASS PASS / $FAIL FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'Fallaron:\n'; printf '  - %s\n' "${FAILED_NAMES[@]}"
  exit 1
fi
exit 0
