# Receipts por canal nativo, no por intermediación humana

Incidente verificado: el coordinador envió HELLO por SendMessage y luego terminó
con «¿Front y app: pasame vuestros receipts?», sin solicitudes nativas posteriores.
El canal funcionaba; el cierre del turno no cumplía el protocolo.

Corrección: el protocolo separa pedido, aceptación, respuesta y validación. Un
resultado de herramienta sin is_error puede contener success:false. La confirmación
física de dispositivo no impide pedir los comprobantes técnicos pendientes.

El hook Claude `receipt-dispatch-guard.sh` detecta preguntas directas a roles sobre
receipts en la última respuesta, únicamente en worktrees triangulate. Devuelve
una corrección Stop para usar el canal real o comunicar su bloqueo. Si ya hubo
un envío, instruye NO repetirlo. No es un validador de la entrega ni del ACK.

Límites deliberados:
- Una continuación como máximo: stop_hook_active evita ciclos, incluso si otro
  Stop hook inició la continuación. No cambia límites de Claude.
- No lee transcripts, ejecuta modelos, toca sockets, escribe ledgers ni hace polling.
- Entrada limitada a 1 MiB, respuesta a 96 Ki caracteres, líneas a 512; timeout 2s.
- Ignora código citado, blockquotes, otros eventos y preguntas al usuario sobre
  dispositivo/negocio. Un error de entrada permite cerrar y deja diagnóstico.
- Es heurístico: otras formulaciones pueden pasar y una pregunta de ejemplo sin
  citar puede generar una corrección. La segunda respuesta no se bloquea de nuevo.
- Codex recibe el protocolo común; no se afirma paridad de enforcement Stop.

Pruebas ejecutan el hook real con entradas controladas y reproducen el texto del
incidente. Eso no prueba que una sesión viva envíe después el mensaje. Medir esa
corrección en su transcript, sin fabricar receipts ni reenviar al usuario.

Instalación acotada con respaldo: hook primero, protocolo de ambos clientes y
registro de Stop conservando las demás opciones. No reiniciar sesiones ni ejecutar
bootstrap global. Los clientes activos pueden requerir su adopción normal; no
prometer recarga en caliente. Rollback solo de esos cuatro archivos si coinciden
con la identidad instalada, preservando cambios posteriores.

Referencia: [Stop hooks oficiales](https://code.claude.com/docs/en/hooks#stop).
