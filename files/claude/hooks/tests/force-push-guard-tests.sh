#!/usr/bin/env bash
# Suite de contrato de force-push-guard.sh — "casi nunca debería ocurrir un
# force push" (regla del usuario, 2026-08-31) hecha estructura verificable.
#
# El guard es de los MÁS CAROS si falla mudo: no rompe nada visible cuando deja
# pasar de más, simplemente un día una rama de ambiente queda reescrita y el
# trabajo de otra sesión desaparece del remoto. Un guard sin suite es una
# promesa, no un control.
#
# NOTA DE MÉTODO — por qué los payloads viven en este archivo y no en la línea
# de comando: el guard inspecciona `tool_input.command` del Bash que lo invoca.
# Cualquier intento de sondearlo con `bash -c 'echo ... push --force ...'` se
# bloquea a sí mismo antes de correr. Los casos tienen que estar EN un archivo
# que se ejecuta; la línea de comando solo lo nombra.
#
# Correlo a mano SIEMPRE después de tocar el hook:
#   bash ~/.claude/hooks/tests/force-push-guard-tests.sh

set -uo pipefail

HOOK="${1:-$HOME/.claude/hooks/force-push-guard.sh}"
fails=0
total=0

# 0) Precondiciones duras. Un PreToolUse(Bash) con error de sintaxis no falla
#    abierto: bloquea TODOS los Bash de la sesión, incluidos los que lo reparan.
if [ ! -f "$HOOK" ]; then
  echo "FATAL: no existe $HOOK — la política de force push NO está activa." >&2
  exit 3
fi
if ! bash -n "$HOOK" 2>/dev/null; then
  echo "FATAL: $HOOK tiene error de sintaxis — bloquea TODOS los Bash de la sesión." >&2
  bash -n "$HOOK" 2>&1 | head -3 >&2
  exit 3
fi
command -v jq >/dev/null 2>&1 || { echo "FATAL: falta jq; los payloads no se pueden armar." >&2; exit 3; }

# jq arma el JSON: escapa comillas, `+`, `:` y pipes de verdad. (Lección de
# route-hook-tests: con sed se generaba JSON inválido y el hook, fail-open,
# devolvía 0 — falso VERDE en un test que creíamos rojo-capaz.)
b(){ jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

check() { # nombre payload exit_esperado
  local rc
  printf '%s' "$2" | bash "$HOOK" >/dev/null 2>&1
  rc=$?
  total=$((total+1))
  if [ "$rc" != "$3" ]; then
    fails=$((fails+1))
    echo "FALLA: $1 (exit=$rc esperado=$3)" >&2
  fi
}

# ── Regla 1: ramas de AMBIENTE nunca se reescriben. Ni con lease. ──
# Complementa el deny estático `git push --force*` de settings.json, que no
# matchea `git -C <dir> push` ni las variantes por refspec.
check "force a dev"                    "$(b 'git push --force origin dev')" 2
check "force a master"                 "$(b 'git push --force origin master')" 2
check "-f a dev"                       "$(b 'git push -f origin dev')" 2
check "lease NO salva a dev"           "$(b 'git push --force-with-lease origin dev')" 2
check "lease NO salva a test"          "$(b 'git push --force-with-lease origin test')" 2
check "lease NO salva a prod"          "$(b 'git push --force-with-lease origin prod')" 2
check "git -C esquiva el deny estatico" "$(b 'git -C /r push --force-with-lease origin main')" 2
check "refs/heads/ explicito"          "$(b 'git push --force origin refs/heads/dev')" 2
check "encadenado con &&"              "$(b 'cd /r && git push --force origin dev')" 2

# Agujeros VERIFICADOS el 2026-09-07 al escribir esta suite (los cuatro daban
# rc=0 contra el hook de entonces). Un ambiente reescrito es un ambiente
# reescrito, se llegue por el nombre pelado o por refspec:
#   a) refspec destino `HEAD:<ambiente>` esquivaba la regla 1 entera, así que
#      --force-with-lease reescribía main/dev sin que nadie lo viera.
#   b) el prefijo `+` ES un force push y no necesita el flag --force: la línea
#      27 exigía --force/-f para siquiera llegar a la regla 1, y el `\+?` que
#      la regla 1 ya tenía escrito era CÓDIGO MUERTO.
check "AGUJERO a: HEAD:dev con lease"           "$(b 'git push --force-with-lease origin HEAD:dev')" 2
check "AGUJERO a: HEAD:refs/heads/master"       "$(b 'git push --force-with-lease origin HEAD:refs/heads/master')" 2
check "AGUJERO b: refspec + a dev"              "$(b 'git push origin +dev')" 2
check "AGUJERO b: refspec + a refs/heads/dev"   "$(b 'git push origin +refs/heads/dev')" 2
check "AGUJERO b: refspec + HEAD:master"        "$(b 'git push origin +HEAD:master')" 2

# ── Regla 2: --force pelado (sin lease) prohibido en CUALQUIER rama ──
check "force pelado en rama de trabajo" "$(b 'git push --force origin feature/x')" 2
check "-f pelado en rama de trabajo"    "$(b 'git push -f origin feature/x')" 2
check "force implicito (rama actual)"   "$(b 'git push --force')" 2
check "force a rama triangulate"        "$(b 'git push --force origin triangulate-qa-lote')" 2

# ── Vías legítimas: SIEMPRE pasan. Un guard que bloquea el trabajo normal se
#    desactiva a la semana, y entonces no protege nada. ──
check "push normal"                     "$(b 'git push origin feature/x')" 0
check "push -u normal"                  "$(b 'git push -u origin feature/x')" 0
check "lease en rama de trabajo"        "$(b 'git push --force-with-lease origin feature/x')" 0
check "lease en rama fix/"              "$(b 'git push --force-with-lease origin fix/algo')" 0
check "lease implicito rama actual"     "$(b 'git push --force-with-lease')" 0
check "lease a HEAD:feature/x"          "$(b 'git push --force-with-lease origin HEAD:feature/x')" 0
# Nombres que CONTIENEN un ambiente pero no SON el ambiente. Acá es donde un
# guard mal anclado empieza a bloquear trabajo real:
check "rama feature/dev-tools"          "$(b 'git push --force-with-lease origin feature/dev-tools')" 0
check "rama dev-rescue"                 "$(b 'git push --force-with-lease origin dev-rescue')" 0
check "rama HEAD:feature/dev"           "$(b 'git push --force-with-lease origin HEAD:feature/dev')" 0
check "rama master-notes"               "$(b 'git push --force-with-lease origin master-notes')" 0
check "rama prod-config"                "$(b 'git push --force-with-lease origin feature/prod-config')" 0
# El `+` en una rama de TRABAJO queda fuera de la regla 1 a propósito: esa es
# la zona tolerada. La regla 1 es sobre ambientes, no sobre el signo.
check "refspec + a rama de trabajo"     "$(b 'git push origin +feature/x')" 0
# Hablar de un force push casi nunca es hacerlo, y el guard lo tolera mientras
# el texto no tenga la forma exacta de un comando peligroso:
check "grep que menciona force push"    "$(b 'grep -rn "push --force" ~/.claude')" 0
check "commit cuyo mensaje lo menciona" "$(b 'git commit -m "doc: no hacer push --force" ')" 0

# FALSO POSITIVO CONOCIDO Y ACEPTADO (2026-09-07). Mecanismo exacto, medido:
# el pre-filtro y la regla 1 son DOS greps independientes sobre el comando
# completo, y grep trabaja por línea. En un comando compuesto se pueden
# satisfacer en LÍNEAS DISTINTAS: alcanza con que un heredoc mencione
# `push ... --force` (aunque sea prosa) y que otra línea haga un push normal a
# un ambiente. Me bloqueó el commit de este mismo cambio.
# No se acota a propósito: entre estorbar (hay vía inmediata — el texto va a un
# archivo y se usa `git commit -F archivo`) y dejar pasar (un ambiente
# reescrito, trabajo de otra sesión perdido), este guard elige estorbar.
MULTI='git commit -F - <<EOF
el prefijo + de refspec ES un force push y no necesita --force
EOF
git push -q origin main'
check "prosa con force + push a ambiente en otra linea" "$(b "$MULTI")" 2
# La frontera del falso positivo: mencionar un refspec a ambiente en UNA sola
# línea no alcanza — el destino tiene que quedar al final o seguido de espacio,
# y ahí la comilla de cierre lo salva.
check "mencion de HEAD:main dentro de un -m"  \
  "$(b 'git commit -m "doc: bloquear push --force-with-lease a HEAD:main"')" 0
check "la via de escape: commit -F archivo"   \
  "$(b 'git commit -F /tmp/msg.txt')" 0

# ── Fail-open ante input no parseable (contrato explícito del hook) ──
check "input vacio"                     '' 0
check "input no-JSON"                   'basura con la palabra push adentro' 0
check "JSON sin command"                '{"tool_name":"Bash","tool_input":{}}' 0
check "tool que no es Bash"             '{"tool_name":"Write","tool_input":{"file_path":"/r/a.ts"}}' 0
check "comando sin push"                "$(b 'git status')" 0

if [ "$fails" -gt 0 ]; then
  echo "ROTO: $fails/$total casos fallan — la política de force push tiene agujeros." >&2
  exit 1
fi
echo "OK: $total/$total casos del contrato de force push pasan."
exit 0
