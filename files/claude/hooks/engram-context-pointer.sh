#!/bin/bash
# SessionStart (startup|clear): inyecta un PUNTERO acotado al último cierre de
# sesión de Engram. No es la memoria: es el hilo, para que la sesión nueva sepa
# que hay algo y decida si vale traer más.
#
# Por qué existe: hasta el 2026-08-31 nada cargaba Engram al hacer /clear, pero
# sesiones le decian al usuario que si. El dato estaba guardado (1388 obs) y
# nadie lo buscaba. Ver ~/.claude/CLAUDE.md, seccion Engram.
#
# Presupuesto: salida acotada a MAXBYTES. Nunca un volcado de memoria.

set -uo pipefail

DB="$HOME/.engram/engram.db"
[ -f "$DB" ] || exit 0

DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Mismo criterio que usa Engram (project_source: git_remote): basename del remote.
PROJECT="$(git -C "$DIR" remote get-url origin 2>/dev/null \
  | sed -e 's#.*[/:]##' -e 's#\.git$##')"

# SIN fallback a basename (2026-09-01). Lo había, y arrancar fuera de un repo
# —en el home, por ejemplo— fabricaba el "proyecto" `cocoa` a partir del nombre
# de la carpeta. Ese nombre existe en Engram, así que el puntero inyectaba el
# cierre de un frente COMPLETAMENTE distinto al que se iba a trabajar. Visto en
# vivo: sesión abierta en ~ para tocar cocoa-core-backend, puntero con el Goal
# de la triangulación de RRHH. Un puntero al hilo equivocado es peor que ninguno:
# arranca la sesión orientada hacia otra cosa.
# Sin remote no hay proyecto identificable: mejor callar.
[ -n "$PROJECT" ] || exit 0

MAXBYTES=1500 MAXAGEH="${CLAUDE_ENGRAM_POINTER_MAX_AGE_H:-24}" \
  python3 - "$DB" "$PROJECT" <<'PYEOF' 2>/dev/null
import os, re, sqlite3, sys
from datetime import datetime, timezone

db, project = sys.argv[1], sys.argv[2]
maxbytes = int(os.environ.get("MAXBYTES", "1500"))

try:
    cx = sqlite3.connect(f"file:{db}?mode=ro", uri=True, timeout=2.0)
except sqlite3.Error:
    sys.exit(0)

def q(sql, args):
    try:
        return cx.execute(sql, args).fetchall()
    except sqlite3.Error:
        return []

last = q("""SELECT content, created_at FROM observations
            WHERE project=? AND type='session_summary' AND deleted_at IS NULL
            ORDER BY created_at DESC LIMIT 1""", (project,))
if not last:
    sys.exit(0)
content, created = last[0]

# Frescura: un cierre viejo ya no es "el hilo", es trabajo archivado. Traerlo
# arranca la sesión mirando hacia atrás, hacia algo que probablemente ya se
# cerró o se superó. Pasado el techo, silencio: el detalle sigue disponible con
# mem_search cuando el trabajo lo pida.  Techo: CLAUDE_ENGRAM_POINTER_MAX_AGE_H
# (default 24h; 0 = sin límite, comportamiento previo).
maxageh = int(os.environ.get("MAXAGEH", "24") or 0)
if maxageh > 0:
    try:
        _t = datetime.strptime(created, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
        if (datetime.now(timezone.utc) - _t).total_seconds() > maxageh * 3600:
            sys.exit(0)
    except ValueError:
        pass  # created ilegible: no es motivo para callar (fail-open)

def section(name, body, limit):
    m = re.search(rf"^\s*#*\s*{name}\s*:?\s*$|^\s*#*\s*{name}\s*:", body,
                  re.I | re.M)
    if not m:
        return ""
    rest = body[m.end():]
    nxt = re.search(r"^\s*#{1,4}\s+\S|^\s*\*\*[A-Z]", rest, re.M)
    chunk = rest[:nxt.start()] if nxt else rest
    chunk = " ".join(chunk.split())
    return chunk[:limit].rstrip()

goal = section("Goal", content, 300) or section("Objetivo", content, 300)
nxt = (section("Next Steps", content, 420) or section("Next", content, 420)
       or section("Siguientes pasos", content, 420))
if not goal:
    goal = " ".join(content.split())[:300]

age = ""
try:
    t = datetime.strptime(created, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    h = int((datetime.now(timezone.utc) - t).total_seconds() // 3600)
    age = f", hace {h}h" if h < 48 else f", hace {h // 24}d"
except ValueError:
    pass

recent = [t for (t,) in q("""SELECT title FROM observations
                            WHERE project=? AND type!='session_summary'
                              AND deleted_at IS NULL AND TRIM(title)!=''
                            ORDER BY created_at DESC LIMIT 3""", (project,))]

out = [f"CONTEXTO ENGRAM — PUNTERO (no es la memoria completa) — proyecto {project}",
       f"Último cierre de sesión ({created}{age}):",
       f"  Goal: {goal}"]
if nxt:
    out.append(f"  Next: {nxt}")
if recent:
    out.append("Observaciones recientes: " + " | ".join(r[:70] for r in recent))
out.append("Esto es un PUNTERO, no la memoria cargada. El detalle se trae con "
           "mem_search + mem_get_observation, y solo si el trabajo lo necesita. "
           "NUNCA le digas al usuario que /clear carga Engram entero: no lo hace.")

text = "\n".join(out)
if len(text.encode()) > maxbytes:
    text = text.encode()[:maxbytes].decode(errors="ignore").rstrip() + " […]"
print(text)
PYEOF

exit 0
