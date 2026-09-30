#!/usr/bin/env bash
# Bounded anti-relay nudge. No transcript scan, network, ledger, or peer impersonation.
# stop_hook_active caps correction at one continuation, including other Stop hooks.
exec python3 /dev/fd/3 3<<'PY'
import json
import re
import sys

try:
    raw = sys.stdin.buffer.read(1048577)
    if len(raw) > 1048576:
        raise ValueError("oversized hook payload")
    event = json.loads(raw)
    if not isinstance(event, dict):
        raise ValueError("expected hook object")
    if event.get("hook_event_name") != "Stop" or event.get("stop_hook_active", False) is not False:
        sys.exit(0)
    cwd = event.get("cwd", "")
    message = event.get("last_assistant_message")
    if not isinstance(cwd, str) or not re.search(r"/\.claude/worktrees/triangulate-[^/]+(?:/|$)", cwd):
        sys.exit(0)
    if not isinstance(message, str) or len(message) > 98304:
        sys.exit(0)
    # Deliberately narrow: direct peer-addressed receipt questions, not generic waits.
    # Ignore quoted/code examples; this is a wording detector, not dispatch evidence.
    fenced = False
    matched = False
    for line in message.splitlines():
        line = line.strip()
        if line.startswith(("```", "~~~")):
            fenced = not fenced
            continue
        if fenced or line.startswith(">") or len(line) > 512:
            continue
        plain = line.replace("*", "")
        if (re.match(r"¿?(?:front|panel|app|backend|back)\b", plain, re.I)
                and "?" in plain and re.search(r"\breceipts?\b", plain, re.I)
                and re.search(r"\b(?:p[aá]s(?:a|e)(?:me|nme)|send|compart[ae]|env[ií](?:a|e))\b", plain, re.I)):
            matched = True
    if matched:
        print("RECEIPT_DISPATCH_GUARD: peer request in user-facing text; one correction", file=sys.stderr)
        print(json.dumps({"decision": "block", "reason":
            "Tu respuesta pide receipts a otros agentes en el chat del usuario. "
            "Eso no es despacho nativo. Revisa los envíos del turno: si falta la solicitud, "
            "usa SendMessage hacia identidades actuales con petición correlacionada. "
            "No reenvíes si ya está enviada: informa el estado sin pedir al usuario que la retransmita. "
            "Comprueba el success estructurado; envío aceptado no es ACK ni receipt. "
            "Si el canal falta, fue rechazado o el presupuesto se agotó, reporta el bloqueo exacto "
            "y continúa solo trabajo independiente. No cambies permisos ni inventes mensajes. "
            "La confirmación humana en dispositivo es separada. Esta corrección es única, no un bucle."}, ensure_ascii=False))
except (ValueError, TypeError, OSError) as error:
    print("RECEIPT_DISPATCH_GUARD: unavailable input; no continuation: " + str(error)[:120], file=sys.stderr)
PY
