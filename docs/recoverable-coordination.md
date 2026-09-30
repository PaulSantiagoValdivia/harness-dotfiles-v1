# ACK, resultados y esperas recuperables

Esta corrección no agrega hooks ni procesos residentes. Extiende el checkpoint
que ya lee SessionStart y el protocolo común a ambos clientes.

- ACK solo confirma alcance recibido; no equivale a resultado validado ni entrega.
- Cada espera identifica responsable, petición, evento, mecanismo observado,
  límite y siguiente acción. Sin mecanismo disponible se registra el bloqueo,
  no una promesa de continuación automática.
- La aceptación humana queda limitada a su comprobación: no impide recopilar
  receipts técnicos ni continuar tareas independientes.

Los nuevos checkpoints usan v2 con `coordination.phase` y `coordination.wait`.
La referencia completa está en el protocolo del skill. v1 sigue recuperándose,
pero no se presume que tenga una espera operativa. No se migran automáticamente
checkpoints ajenos ni se fabrican suscripciones para rellenar campos.

El lector rechaza estados `complete/done`, esperas sin responsable/evento/handle,
fechas inválidas y validaciones sin evidencia mínima. Conserva esperas vencidas
como datos a revalidar; no dispara reintentos ni modifica autoridades. Un JSON
bien formado no demuestra que el mensaje llegó o que el resultado es correcto.
La autorización final sigue en los gates existentes, no en esta estructura.

Observación histórica: el backend ya solicitó receipts por SendMessage a las
17:20:57Z y 17:21:01Z del 10/09/2026. Luego anunció cierre con dispositivo pendiente.
Esto justifica conservar responsabilidad y continuación; no demuestra que el
nuevo hook causara los envíos (fueron anteriores a su instalación).

Prueba: `bash tests/triangulate_handoff_test.sh` ejecuta recuperación real en
worktrees descartables y casos negativos. No certifica obediencia de sesiones vivas.

Despliegue: actualizar únicamente handoff y protocolos de ambos clientes con
respaldo y comparación previa. No reiniciar sesiones, ejecutar compact/clear ni
escribir planes de producto. Rollback de esos tres archivos solo si no hay drift;
restaurar fuente/pruebas/documentación como una unidad. Un rollback a lector v1
no interpreta v2: conservar checkpoints y volver a recuperar hechos, sin borrarlos.

## Explicit recovery verification (not the SessionStart exit code)

Run `bash ~/.claude/hooks/triangulate-handoff.sh --verify` from each actual
triangulation worktree. Exit 0 means its v2 checkpoint passes local schema,
identity and artifact checks. Exit 2 means missing/invalid recovery, legacy v1,
wrong directory or invalid arguments. A directory containing only `state.yaml`
is insufficient. The default SessionStart mode remains informational and may
return 0 with `RECOVERY UNAVAILABLE`; never use that as an adoption gate.

Even explicit verification does not prove live messages, committed/pushed
artifacts, deployment, or completion. Recorded waits can have expired; the owner
must reconcile them rather than interpreting this probe as permission to wait.

### Closing the observed coordination gaps

The existing canonical writer owns these repairs; an external auditor must not
write its product worktree or impersonate native messages.

| Gap | Required evidence before closure |
| --- | --- |
| Recovery | Recover approved proposal/spec/design/tasks (do not invent requirements), persist them with commit/push, record current v2 recovery facts, and run the explicit probe in all three worktrees. Respect the existing storage policy for checkpoints; never claim an untracked state file is preserved. |
| Stale integration | Compare the exact candidate against current remote dev. Confirmed ancestry proves history containment, not deployed behavior. Do not create a duplicate PR for an already-contained candidate. Separately track new planning changes. |
| Contradictory receipt | Verify PR number, merge revision and actual checks from the provider; reconcile structured fields with prose. Keep crash/build status current and distinguish pending technical work from device acceptance. |
| Suspected crash cause | The app owner compares symbolicated logs, SDK/version and lifecycle configuration with the upstream issue, then validates a reproduction/fix. Similar stack frames alone are a hypothesis; unit-test success is not device-startup proof. |
| Human relay | The canonical owner routes technical requests through native messages within approved scope. Track the existing build handle, owner and result event without duplicate builds or indefinite polling. Escalate only actual scope/permission/release decisions, not routine PR approval. |

A preexisting crash can remain a release blocker. Assign investigation and track
its outcome; do not silently expand implementation scope or declare the overall
triangulation complete while required app evidence remains missing.

Rollback this probe by reverting its hook/test/documentation work unit and using
the guarded installer backup for the hook. No settings, product files, messages,
processes, or writer ownership are changed by the probe.
