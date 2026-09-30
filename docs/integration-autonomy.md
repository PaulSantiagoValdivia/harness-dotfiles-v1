# Integración sin confirmaciones rutinarias

Aprobar el alcance canónico autoriza implementarlo e integrarlo al destino permitido,
no desplegar producción. La política común vive en
`files/shared/integration-autonomy.md` y se distribuye en ambas instrucciones.
Los cambios existentes conservan sus pausas explícitas y controles de entrega.

El instalador acotado actualiza únicamente `~/.claude/CLAUDE.md` y
`~/.codex/AGENTS.md`, respalda los originales y rechaza bloques personalizados,
symlinks y cambios concurrentes detectados. No ejecuta bootstrap/sync ni toca modelos,
hooks, permisos, procesos o repositorios de producto. Una instalación parcial conserva
el manifiesto para inspección y rollback; no se presenta como transacción indivisible.

Uso del operador (el agente puede ejecutarlo; no requiere copiar prompts):
`python3 files/shared/lib/install-integration-autonomy.py install HOME BACKUP_NUEVO`
Restauración: el mismo comando con `rollback`, HOME y el respaldo original.
El rollback rechaza sobrescribir ediciones posteriores.

Las sesiones ya abiertas pueden conservar instrucciones anteriores: no se promete
recarga en caliente ni se reinician escritores. Adoptar mediante el siguiente arranque
normal o un canal real autorizado, conservando la autoridad del cambio canónico.

Medición por cambio: confirmaciones rutinarias de merge (objetivo 0), escalaciones
legítimas con motivo, duración bloqueada y SHA integrado. Las pruebas de contrato
verifican distribución y seguridad del instalador; NO prueban obediencia de sesiones
vivas. Esa medición necesita una ejecución real dentro de cmux.

Rollback de fuente: revertir esta unidad completa, incluidas ambas instrucciones,
política, instalador, pruebas y conexión al CI. La protección del repositorio y los
recibos históricos permanecen intactos; esta autorización no elimina bloqueos reales.
