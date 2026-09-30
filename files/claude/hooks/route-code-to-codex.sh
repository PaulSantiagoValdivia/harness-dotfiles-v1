#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit|Bash) — Claude organiza, CODEX escribe código.
#
# Regla del usuario (2026-08-27, reafirmada 2026-08-30): en cualquier repo de
# producto, Claude especifica/organiza/audita y Codex es el ÚNICO que escribe
# código. Una regla en CLAUDE.md no alcanza como enforcement — y menos ahora,
# que el template de gentle-ai 2.2.2 manda la regla CONTRARIA en el bloque
# <!-- gentle-ai:standalone-runtime --> ("Do not force code edits through a
# Codex MCP"). Este hook es la autoridad real; la prosa es solo documentación.
#
# Cubre DOS superficies (la v1 del 2026-08-27 solo cubría la primera, y por eso
# era trivialmente evitable escribiendo con `sed -i` o un heredoc desde Bash):
#   1. Edit / Write / NotebookEdit sobre un archivo de código.
#   2. Bash que escribe archivos de código: sed -i, tee, cat > f, > f, >> f.
#
# Deja pasar SIEMPRE (son el trabajo legítimo de Claude):
#   - Rutas bajo .claude/, .agent/, .atl/, openspec/, .git/
#   - Extensiones de documentación/artefacto: .md .mdx .txt .rst
#   - Cualquier extensión que no esté en la lista de código de abajo
#   - Todo lo que no se pueda parsear (fail-open: exit 0)
#
# Escape consciente: CLAUDE_ALLOW_DIRECT_EDIT=1 en el entorno de la sesión.
#
# Fallback SIN CRÉDITOS DE CODEX (regla del usuario 2026-09-03): cuando Codex
# no tiene cuota, Claude escribe el código. El interruptor es un archivo,
# no una variable de entorno, porque las sesiones ya abiertas no pueden
# cambiar su entorno y el hook lo lee en cada tool call:
#   ~/.claude/codex-sin-creditos   (lo crea codex-run al detectar cuota
#                                   agotada, o el usuario con `touch`)
# Caduca a CODEX_SIN_CREDITOS_TTL_H horas (default 12; 0 = no caduca) para
# que el fallback no quede abierto para siempre y Codex vuelva a ser el
# escritor cuando la cuota se renueve. Para cerrarlo antes: rm del archivo.

set -uo pipefail

# Trazabilidad de los saltos del guard (2026-09-07) -------------------------
# Se registra UNA vez por sesión y por motivo: el objetivo es que una auditoría
# posterior pueda separar "fallback autorizado" de "guard apagado sin que nadie
# se enterara", no llenar un log con una línea por tool call.
BYPASS_DIR="${CLAUDE_ROUTING_BYPASS_DIR:-$HOME/.claude/hooks/state/routing-bypass}"
BYPASS_LOG="$BYPASS_DIR/bypass.log"
trace_bypass() {
  local reason="$1" key marker
  mkdir -p "$BYPASS_DIR" 2>/dev/null || return 0
  # Clave de dedupe en bash puro, sin shasum/cut/tr: este hook tiene que seguir
  # avisando incluso con el PATH degradado, que es justamente uno de los casos
  # en los que el guard se apaga.
  key="${CLAUDE_SESSION_ID:-pid$PPID}-${reason%% *}"
  key="${key//[^A-Za-z0-9._-]/_}"
  marker="$BYPASS_DIR/.seen-${key:0:64}"
  [ -f "$marker" ] && return 0
  : > "$marker" 2>/dev/null
  printf '%s\tsession=%s\tpid=%s\tcwd=%s\t%s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "${CLAUDE_SESSION_ID:-desconocida}" "$$" "$PWD" "$reason" \
    >> "$BYPASS_LOG" 2>/dev/null
  echo "[routing] GUARD SALTEADO: $reason" >&2
  echo "[routing] En esta sesión Claude puede escribir código de producto SIN pasar por Codex." >&2
  echo "[routing] Queda registrado en $BYPASS_LOG — el estándar de trabajo NO baja." >&2
}

if [ "${CLAUDE_ALLOW_DIRECT_EDIT:-0}" = "1" ]; then
  trace_bypass "CLAUDE_ALLOW_DIRECT_EDIT=1 en el entorno (escape consciente)"
  exit 0
fi

# OJO: el fallback NO es un `exit 0` temprano. Eso fue el primer intento y era
# un agujero: apagaba TAMBIÉN el bloqueo de `codex exec` sin launcher, que no
# tiene nada que ver con el routing (existe por los cuelgues del shim de cmux
# del 2026-08-30 y sigue valiendo con o sin cuota). El flag solo neutraliza
# deny(), es decir las escrituras de código; todo lo demás sigue igual.
SIN_CREDITOS=0
SIN_CREDITOS_FLAG="${CODEX_SIN_CREDITOS_FLAG:-$HOME/.claude/codex-sin-creditos}"
if [ -f "$SIN_CREDITOS_FLAG" ]; then
  ttl_h="${CODEX_SIN_CREDITOS_TTL_H:-12}"
  if [ "$ttl_h" = "0" ]; then
    SIN_CREDITOS=1
  else
    mtime="$(stat -f %m "$SIN_CREDITOS_FLAG" 2>/dev/null || stat -c %Y "$SIN_CREDITOS_FLAG" 2>/dev/null || echo 0)"
    age=$(( $(date +%s) - mtime ))
    [ "$age" -lt $(( ttl_h * 3600 )) ] && SIN_CREDITOS=1
  fi
fi

input="$(cat 2>/dev/null || true)"
# stdin vacío no se traza: no hubo tool call que evaluar, y pasa en toda
# invocación directa del hook (tests incluidos). Trazar esto sólo llenaba el
# registro de ruido y tapaba los dos saltos que sí importan.
[ -z "$input" ] && exit 0

# jq ausente era el peor de los tres: fail-open total y mudo. El guard entero
# depende de jq para leer el payload, así que sin jq no protege NADA.
if ! command -v jq >/dev/null 2>&1; then
  trace_bypass "jq AUSENTE: el guard de routing no puede parsear el payload y queda apagado por completo (instalá jq: brew install jq)"
  exit 0
fi

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
agent="$(printf '%s' "$input" | jq -r '.agent_type // empty' 2>/dev/null || true)"

# Extensiones que cuentan como "código de producto".
CODE_RE='\.(ts|tsx|js|jsx|mjs|cjs|dart|py|go|rb|rs|java|kt|kts|swift|c|h|cc|cpp|hpp|cs|php|scala|ex|exs|sql|sh|bash|zsh|vue|svelte|astro|css|scss|sass|less|html|json|ya?ml|toml|xml|gradle|proto|graphql|prisma)$'
# Rutas donde Claude SÍ manda (organización, specs, config del propio harness).
SAFE_RE='(^|/)(\.claude|\.agent|\.atl|openspec|\.git)/'

is_code() {
  local p="$1"
  [ -n "$p" ] || return 1
  # AGUJERO CERRADO 2026-08-31: los worktrees de triangulación viven en
  # <repo>/.claude/worktrees/<slug>/ — sin este strip, TODO archivo adentro
  # matcheaba "/.claude/" en SAFE_RE y Claude escribía código de producto
  # directo en cada triangulación (detectado por el usuario en vivo).
  # Se recorta el prefijo hasta el worktree y se evalúa la ruta INTERNA:
  # así openspec/ o .claude/ DENTRO del worktree siguen exentos, pero
  # functions/src/... vuelve a estar protegido.
  p="$(printf '%s' "$p" | sed -E 's#^.*/\.claude/worktrees/[^/]+/##')"
  # AGUJERO CERRADO 2026-08-31 (#2, detectado por el usuario en vivo): una
  # sesión escribía specs de Playwright (.ts) en <repo>/.claude/qa-sweep/ —
  # un dir .claude/ usado como área de trabajo. La exención de harness ya NO
  # es total: dentro de .claude/.agent/.atl/openspec/.git solo pasa
  # config/documentación (md, json, yaml, toml, txt, lock). Código real
  # (ts, js, py, sh, ...) se bloquea también ahí.
  # Única exención completa: ~/.claude/ del HOME (hooks .sh y workflows .js
  # del propio harness, que Claude sí mantiene).
  case "$1" in "$HOME/.claude/"*|'~/.claude/'*) return 1 ;; esac
  # Scratchpad de sesión: mesa de trabajo del orquestador para reportes,
  # digests y artifacts (HTML/JSON de entrega directa al usuario) — nunca
  # código de producto. Exento (2026-08-31).
  case "$1" in /private/tmp/claude-*/*/scratchpad/*|/tmp/claude-*/*/scratchpad/*) return 1 ;; esac
  if printf '%s' "$p" | grep -qE "$SAFE_RE|^(\.claude|\.agent|\.atl|openspec|\.git)/"; then
    printf '%s' "$p" | grep -qiE '\.(md|mdx|txt|rst|json|ya?ml|toml|lock|csv)$' && return 1
    printf '%s' "$p" | grep -qiE "$CODE_RE" && return 0
    return 1
  fi
  printf '%s' "$p" | grep -qiE "$CODE_RE"
}

deny() {
  local what="$1"
  # Codex sin cuota: Claude es el escritor. Se deja pasar, pero se AVISA, para
  # que nadie confunda el fallback con una relajación del estándar.
  if [ "$SIN_CREDITOS" = "1" ]; then
    cat >&2 <<MSG
[routing] Codex SIN CUOTA ($SIN_CREDITOS_FLAG): escribís vos este cambio.
Mismo estándar que un diff de Codex: código completo, sin placeholders, archivos
reales leídos antes de escribir, y auditoría con git diff + los comandos de
verificación del rol. Cuando vuelva la cuota: rm $SIN_CREDITOS_FLAG
MSG
    return 0
  fi
  if [ -n "$agent" ]; then
    cat >&2 <<MSG
BLOQUEADO (routing a Codex): $what
Sos un subagente ($agent) y no podés escribir código de producto directamente.

Tenés Bash: hacé el cambio con Codex y verificá el diff vos mismo.
  ~/.claude/bin/codex-run exec --skip-git-repo-check --sandbox workspace-write -m <astra|sol> \\
    "<instrucción precisa y acotada del cambio>"
  (elegí el modelo por complejidad real: CLAUDE.md § "Selección de modelo Codex" — sol para lo mecánico, astra para lo no trivial)
  git diff        # verificá ANTES de reportar que quedó hecho

Si no tenés Bash ni la tool MCP de Codex: abortá y devolvé el control al
orquestador explicando qué cambio hacía falta. No pidas saltarte el hook.
MSG
  else
    cat >&2 <<MSG
BLOQUEADO (routing a Codex): $what
Regla del usuario: Claude organiza, especifica y audita; CODEX escribe el código.

Vía correcta:
  ~/.claude/bin/codex-run exec --skip-git-repo-check --sandbox workspace-write -m <astra|sol> \\
    "<instrucción precisa y acotada del cambio>"
  (elegí el modelo por complejidad real: CLAUDE.md § "Selección de modelo Codex" — sol para lo mecánico, astra para lo no trivial)
  git diff        # auditá el resultado antes de reportarlo

Si la tarea puede pasar de ~8 min, lanzala en BACKGROUND. El tool Bash corta a
600s y mata el árbol entero: ahí el VEREDICTO de codex-run no llega a
imprimirse y perdés el aviso de "el trabajo landeó, no re-despaches".

Para tandas de tareas acotadas e independientes: el workflow codex-build.
Esto NO aplica a .claude/, .agent/, .atl/, openspec/ ni a markdown — eso es
trabajo de Claude y pasa sin bloqueo.
MSG
  fi
  exit 2
}

case "$tool" in
  Edit|Write|NotebookEdit)
    path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)"
    is_code "$path" && deny "$tool sobre $path"
    ;;

  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    [ -z "$cmd" ] && exit 0
    # Codex directo está PROHIBIDO fuera del launcher: el shim de cmux va
    # primero en el PATH y cuelga codex fuera de un pane de cmux (incidente
    # 2026-08-30, DOS cuelgues el mismo día — el segundo con los flags
    # -c hooks=[] puestos, porque los flags no anulan al wrapper). codex-run
    # esquiva el shim, cierra stdin y pone techo duro de tiempo.
    # Solo cuenta como invocación si `codex` está en POSICIÓN DE COMANDO
    # (inicio, o después de ; && || | ( ` $( ). Mencionarlo como texto en un
    # grep/echo/sed es dato, no ejecución (falso positivo cazado 2026-08-30).
    codex_invoked=0
    if printf '%s' "$cmd" | grep -qE '(^|[;&|(`]|\$\()[[:space:]]*([A-Za-z_][A-Za-z_0-9]*=[^ ]* +)*("?[^ "]*/)?"?codex"? +(exec|e) '; then
      codex_invoked=1
    fi
    case "$cmd" in
      *codex-run*) exit 0 ;;               # la vía canónica pasa siempre
    esac
    if [ "$codex_invoked" = "1" ]; then
        cat >&2 <<'CXMSG'
BLOQUEADO (codex sin launcher): `codex exec` directo se cuelga fuera de cmux
(el shim de cmux intercepta el PATH; ya pasó dos veces hoy, con 0.1s de CPU y
espera infinita). Usá SIEMPRE el launcher canónico:

  ~/.claude/bin/codex-run exec --skip-git-repo-check --sandbox workspace-write -m <astra|sol> "<instrucción>"

Techo de tiempo: 600s por default; CODEX_RUN_TIMEOUT=900 por delante para
tareas largas. Si expira devuelve exit 124 — reportalo como blocker con el
comando exacto, no lo reintentes idéntico.
CXMSG
      exit 2
    fi

    # Autoría vs ejecución (mismo fix que block-unbounded-polls, 2026-08-31):
    # un heredoc que ESCRIBE un script puede contener "sed -i ... x.py" como
    # TEXTO. Descartar cuerpos de heredoc antes de escanear: la línea que abre
    # el heredoc (con su posible redirect de destino) se conserva.
    cmd="$(printf '%s' "$cmd" | awk '
      inhd { if ($0 == hd_end) inhd=0; next }
      match($0, /<<-?['"'"'"]?[A-Za-z_][A-Za-z_0-9]*/) {
        hd_end = substr($0, RSTART, RLENGTH)
        sub(/^<<-?['"'"'"]?/, "", hd_end)
        inhd = 1
        print; next
      }
      { print }
    ')"

    # Una escritura relativa puede pertenecer al scratchpad de Claude si el
    # primer segmento hizo `cd` a una ruta literal. Variables y sustituciones
    # no se resuelven: conservar el bloqueo evita que una ruta desconocida
    # convierta el guard en fail-open.
    cd_dir=""
    cd_unresolved=0
    first_cd="$(printf '%s\n' "$cmd" | sed -nE '1s/^[[:space:]]*cd[[:space:]]+([^;&|]+)[[:space:]]*(;|&&).*/\1/p')"
    first_cd="$(printf '%s' "$first_cd" | sed -E 's/[[:space:]]+$//')"
    if [ -n "$first_cd" ]; then
      case "$first_cd" in
        \"*\") first_cd="${first_cd#\"}"; first_cd="${first_cd%\"}" ;;
        \'*\') first_cd="${first_cd#\'}"; first_cd="${first_cd%\'}" ;;
      esac
      case "$first_cd" in
        *\$*|*'`'*|*'$('*) cd_unresolved=1 ;;
        *) cd_dir="$first_cd" ;;
      esac
    fi
    later_segments="$(printf '%s\n' "$cmd" | awk '
      NR == 1 {
        sub(/^[[:space:]]*cd[[:space:]]+[^;&|]+[[:space:]]*(;|&&)[[:space:]]*/, "")
        print
        next
      }
      { print }
    ')"
    if printf '%s\n' "$later_segments" | grep -qE '(^|[;&| (])[[:space:]]*cd[[:space:]]+'; then
      cd_dir=""
      cd_unresolved=1
    fi
    normalize_target() {
      awk '
        {
          absolute = (substr($0, 1, 1) == "/")
          n = split($0, part, "/")
          count = 0
          for (i = 1; i <= n; i++) {
            if (part[i] == "" || part[i] == ".") continue
            if (part[i] == ".." && count > 0 && stack[count] != "..") {
              delete stack[count--]
            } else if (part[i] != ".." || !absolute) {
              stack[++count] = part[i]
            }
          }
          output = absolute ? "/" : ""
          for (i = 1; i <= count; i++) {
            if (output != "" && output != "/") output = output "/"
            output = output stack[i]
          }
          print output
        }
      '
    }
    resolve_target() {
      local target="$1"
      case "$target" in
        /*|~/*) printf '%s\n' "$target" ;;
        *)
          if [ -n "$cd_dir" ] && [ "$cd_unresolved" = 0 ]; then
            case "$cd_dir" in
              /) printf '/%s\n' "$target" | normalize_target ;;
              *) printf '%s/%s\n' "$cd_dir" "$target" | normalize_target ;;
            esac
          else
            printf '%s\n' "$target"
          fi
          ;;
      esac
    }

    # Pre-filtro barato: sin operador de escritura no hay nada más que mirar.
    case "$cmd" in
      *'sed -i'*|*'>'*|*'tee '*|*'dd '*) ;;
      *) exit 0 ;;
    esac

    # `sed -i` se trata aparte: BSD sed (macOS) pide el sufijo como ARGUMENTO
    # separado (`sed -i "" s/a/b/ f.py`), así que el destino no queda pegado al
    # flag y una regex posicional no lo ve. Si hay `sed -i`, cualquier token del
    # comando que sea ruta de código es, por definición, un destino de escritura.
    case "$cmd" in
      *'sed -i'*)
        for t in $(printf '%s\n' "$cmd" | tr ' \t|;&()' '\n' | tr -d '"'"'"'"'); do
          resolved="$(resolve_target "$t")"
          is_code "$resolved" && deny "Bash escribiendo $t (sed -i)"
        done
        ;;
    esac

    # Candidatos a destino de escritura, uno por línea.
    targets="$(printf '%s\n' "$cmd" \
      | grep -oE "(sed -i[^ ]* +(-e +'[^']*' +)?|tee +(-a +)?|>>? *)(\"[^\"]+\"|'[^']+'|[^ |&;<>()\"']+)" 2>/dev/null \
      | sed -E "s/^(sed -i[^ ]* +(-e +'[^']*' +)?|tee +(-a +)?|>>? *)//" || true)"
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case "$t" in /dev/*|\&*) continue ;; esac
      case "$t" in
        \"*\") t="${t#\"}"; t="${t%\"}" ;;
        \'*\') t="${t#\'}"; t="${t%\'}" ;;
      esac
      resolved="$(resolve_target "$t")"
      is_code "$resolved" && deny "Bash escribiendo $t (sed -i / redirección / tee)"
    done <<< "$targets"
    ;;
esac

exit 0
