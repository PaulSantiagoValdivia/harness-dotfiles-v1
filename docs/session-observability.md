# Ver sesiones antes de diagnosticar coordinación

El monitor anterior filtraba `claude --session-id`: omitía arranques sin esa
opción y emitía una lista vacía exitosa. Ahora compara el nombre del ejecutable
con `claude` (incluidas rutas antiguas con espacios), no texto de argumentos.
Un error de `ps` devuelve error, no cero sesiones. No se limpia ni detiene nada.

`claude-sessions --porcelain` mantiene su formato. Cada fila representa un
proceso observado, no una identidad nativa validada. Puede incluir invocaciones
transitorias. El contexto corresponde al último transcript del directorio, no
necesariamente al turno actual; directorios compartidos se marcan ambiguos.
No usar el conteo como prueba de inbox, ACK, autoridad o costo facturado.

## Observación local del 10 de septiembre de 2026

Tras corregir el filtro: 10 procesos observados frente a cero del monitor previo.
Cuatro directorios tenían contexto registrado >=200k; máximo 463509 tokens.
Es una fotografía local, no un umbral nuevo ni una prueba causal de latencia.
No se cerraron sesiones ni se ejecutó clear/compact automáticamente.

Los transcripts consultados sí contienen ListAgents/SendMessage. Un resultado
nativo `success:false` por identidad no alcanzable fue seguido por un envío
`success:true`. El retorno de herramienta sin `is_error` NO equivale a éxito del
mensaje: inspeccionar también su resultado estructurado. Un envío aceptado NO
prueba recepción, lectura o resolución. No inventar ACK a partir de esos contadores.
Los registros históricos no certifican las sesiones actuales.

## Siguiente validación real

Desde el coordinador autorizado dentro de cmux: descubrir identidades actuales,
confirmar límites de escritura y ejecutar HELLO/ACK del protocolo existente.
Separar rechazos, mensajes retenidos, envíos aceptados y respuestas correlacionadas.
Registrar revisión de contrato, petición y duración con reloj del coordinador.
No reutilizar identificadores antiguos ni reenviar indefinidamente; respetar los
límites de reintento existentes. No modificar controles inbound por conjetura.

Fuente de semántica: [mensajería oficial Claude Code](https://code.claude.com/docs/en/cross-session-messaging).
El acceso externo a cmux continúa denegado; no se cambia seguridad ni se suplanta
un proceso autorizado. La certificación viva permanece pendiente.

Rollback: restaurar únicamente el ejecutable respaldado tras comprobar que no
cambió desde la instalación; revertir fuente/pruebas/CI de esta unidad juntos.
