#!/usr/bin/env bash
# PreToolUse(Bash) — política de force push: "casi nunca" hecho estructura.
#
# Regla del usuario (2026-08-31, textual: "casi nunca debería ocurrir un
# force push"):
#   1. Force push (cualquier variante) a ramas de AMBIENTE
#      (dev/test/master/main/prod) → BLOQUEADO SIEMPRE. Complementa la regla
#      branch-lifecycle del backend (los ambientes están siempre vivos) y el
#      deny estático `git push --force*`, que no matchea `git -C ... push`.
#   2. `--force`/`-f` a secas (sin lease) → BLOQUEADO en cualquier rama:
#      pisa trabajo remoto sin chequeo. La única forma tolerada es
#      `--force-with-lease`, y solo en ramas de trabajo (feature/fix/
#      triangulate/rescue/...), típicamente tras un rebase.
#
# "Cualquier variante" incluye las DOS que este guard dejaba pasar hasta el
# 2026-09-07, encontradas al escribir su suite de contrato:
#   a) el refspec `HEAD:<ambiente>` — la regla 1 solo miraba el nombre pelado,
#      así que `--force-with-lease origin HEAD:main` reescribía un ambiente.
#   b) el prefijo `+` de refspec, que ES un force push y NO necesita el flag
#      `--force`. El pre-filtro exigía --force/-f para siquiera llegar a la
#      regla 1, y por eso el `\+?` que la regla 1 ya tenía escrito nunca se
#      evaluaba: era código muerto.
# Contrato ejecutable: hooks/tests/force-push-guard-tests.sh
#
# Fail-open ante input no parseable (exit 0) — igual que los demás guards.

set -uo pipefail

input="$(cat 2>/dev/null || true)"
case "$input" in *push*) ;; *) exit 0 ;; esac

command -v jq >/dev/null 2>&1 || exit 0
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[ -z "$cmd" ] && exit 0

# ¿Es un push que puede reescribir historia? --force / -f / --force-with-lease,
# o un refspec con `+` (force por sintaxis, sin flag).
printf '%s' "$cmd" | grep -qE 'push[^|;&]*(--force|-f([[:space:]]|$)|[[:space:]]\+)' || exit 0

deny() { printf '%s\n' "$1" >&2; exit 2; }

# Regla 1: nunca contra ramas de ambiente. Dos formas de nombrarlas:
#   - nombre pelado:   `origin dev`, `origin +dev`, `origin refs/heads/dev`
#   - refspec destino: `HEAD:dev`, `+HEAD:master`, `x:refs/heads/prod`
# Si el push es implícito (rama actual), no podemos resolverla barato acá; la
# regla 2 más el lease acotan el daño.
ENV_BR='(dev|test|master|main|prod)'
if printf '%s' "$cmd" | grep -qE "push[^|;&]*[[:space:]](origin[[:space:]]+)?(\+?(refs/heads/)?${ENV_BR})([[:space:]]|:|$)" \
   || printf '%s' "$cmd" | grep -qE "push[^|;&]*[[:space:]][^[:space:]|;&]*:(refs/heads/)?${ENV_BR}([[:space:]]|$)"; then
  deny "BLOQUEADO (force-push-guard): force push contra una rama de AMBIENTE (dev/test/master/main/prod). Esas ramas nunca se reescriben — regla branch-lifecycle. Si necesitás integrar, va por PR de promoción."
fi

# Regla 2: --force pelado (sin lease) prohibido en cualquier rama.
if printf '%s' "$cmd" | grep -qE 'push[^|;&]*(--force([[:space:]]|$)|-f([[:space:]]|$))' \
   && ! printf '%s' "$cmd" | grep -q 'force-with-lease'; then
  deny "BLOQUEADO (force-push-guard): --force sin lease pisa trabajo remoto sin verificación. Usá --force-with-lease (y solo en ramas de trabajo, tras un rebase verificado)."
fi

exit 0
