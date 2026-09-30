# Auditoría de cmux y triangulación — 2026-09-09

## Veredicto

**Cumplimiento parcial; triangulación extremo a extremo NO demostrada.** La configuración y pruebas aisladas funcionan, pero hay brechas entre el protocolo, la selección del plan y las condiciones que permiten declarar una verificación exitosa. No afirmar que abrir tres sesiones equivale a entregar tres repositorios coordinados.

Fuente inspeccionada: harness-dotfiles `79ad925`, inicialmente limpio. cmux instalado `0.64.22 (102) [ddd4a01bc]`. Auditoría de lectura y fixtures temporales: sin lanzar agentes de producto, modificar sesiones, promover repositorios, archivar ni eliminar worktrees. Las observaciones de repositorios activos son una fotografía temporal, no su identidad final ni una evaluación del trabajo de sus propietarios.

## Evidencia ejecutada

| Control | Resultado | Tiempo |
|---|---|---|
| `cmux config check` | PASS: JSONC válido, archivo presente | No cronometrado |
| `cmux ping` / listado de workspaces | BLOCKED: «only processes started inside cmux can connect» | No cronometrado |
| Launcher instalado vs fuente | PASS: bytes idénticos | N/A |
| DevTools instalado vs fuente | PASS: bytes idénticos; no prueba de versión del proceso ya arrancado | N/A |
| `bash tests/triangulate_launcher_test.sh` | PASS, exit 0; cmux simulado | 2,893 s |
| `python3 tests/cocoa_devtools_test.py` | PASS, 10 tests, exit 0; repositorios temporales | 27,343 s |
| `bash tests/cocoa_devtools_ui_test.sh` | PASS, exit 0; assertions de fuente | 0,047 s |
| `bash tests/standalone_runtime_parity_test.sh` | PASS, exit 0; contratos/configuración, NO mensajería real | 9,786 s |
| GET `/api/health` | PASS, servicio local responde | No cronometrado |
| GET `/api/triangulations`, tres muestras | PASS, exit 0 | 1,093 / 1,074 / 1,210 s; mediana 1,093 s |
| Hook handoff, tres backend worktrees reales | Exit 0; selección canónica insegura, ver hallazgo A1 | 0,268 / 0,264 / 0,277 s |

No se ejecutaron los tests de producto en worktrees con propietarios activos. No se leyó contenido de terminales, credenciales ni transcripciones. No se desactivó la restricción de acceso de cmux.

## Hallazgos priorizados

### A1 — ALTA: autoridad OpenSpec elegida por fecha, no por identidad

`~/.claude/hooks/triangulate-handoff.sh` busca `changes/$SLUG`; si falta, usa `ls -dt .../changes/*/ | head -1`. En los tres worktrees inspeccionados falta el directorio de nombre exacto.

Resultados reales del hook:
- `agropartners-organigrama` → `vacaciones-aprobacion-superior-inmediato`.
- `qa-modulos-parity` → `vacaciones-aprobacion-superior-inmediato`.
- `reconocimientos-unificacion` → `reconocimientos-motor-otorgamiento`.

El último podría ser una asociación intencional, pero el hook no la demuestra: depende de mtime. Los dos primeros muestran nombres semánticamente ajenos, no prueba de que los agentes hayan ejecutado esas tareas. Esto facilita lectura irrelevante y retrabajo.

**Corrección propuesta:** mapa explícito worktree-key → change-root canónico, validado en los tres roles; si no existe, BLOCKED. Nunca elegir por fecha. Probar ausencia, ambigüedad y múltiples planes antes de cambiar producción.

### A2 — ALTA: gate funcional más débil que el protocolo

El protocolo instalado exige backend `npm run typecheck && npm run lint && npm run test:unit` y app `flutter analyze && flutter test`. En cambio, `VERIFY_COMMANDS` de `files/shared/devtools/cocoa-devtools.py` y su copia instalada ejecuta:
- backend: `npm run typecheck && npm run format:check`;
- app: `flutter analyze`;
- panel: `npm run check:all` (coincide).

`promote_group_to_dev` consume esos resultados. Por tanto, esta ruta no garantiza las pruebas unitarias exigidas antes de integrar. No se ejecutó ninguna promoción real.

**Corrección propuesta:** resolver un contrato único por rol, comprobar que sus comandos existen y probar que un fallo unitario impide el primer push. No debilitar el protocolo para hacer coincidir un gate incompleto.

### A3 — ALTA: omisión de verificación representada como éxito

`verify_worktree` devuelve `returncode: 0` cuando `VERIFY_SKIP=1`. Reproducción aislada: importar el módulo, crear directorio temporal, establecer esa variable sólo en el proceso de prueba y llamar al rol app. Resultado: «verificación omitida por el operador», returncode 0, sin ejecutar Flutter.

La promoción decide por returncode. No se comprobó que el servidor actualmente activo tenga esta variable; no afirmar que se esté saltando pruebas ahora. Los tests de DevTools usan ese bypass en fixtures.

**Corrección propuesta:** SKIPPED debe ser un estado explícito no promocionable; los tests deben inyectar un ejecutor simulado, no habilitar una ruta de éxito en producción.

### A4 — MEDIA: existencia de worktrees confundida con sesiones concurrentes

`guard_concurrent_triangulations` cuenta directorios `triangulate-*`, no sesiones vivas ni recibos de cierre de DevTools. Puede bloquear nuevas tareas por worktrees históricos que el protocolo exige preservar. El mismo slug se exceptúa: eso no demuestra ausencia de un escritor previo.

**Corrección propuesta:** identidad de sesión/propietario y registro de estado con detección de vida. Un worktree conservado no equivale a un escritor activo; repetir slug requiere comprobar ownership antes de abrir otra sesión.

### A5 — ALTA, riesgo estático: stop falla abierto ante errores Git

`triangulate stop` convierte errores de `git status` en salida vacía y errores de `rev-list` en cero. Filtra directorios completos (`.atl/`, entre otros) y puede terminar en `worktree remove --force`. La afirmación del comentario «SEGURO» no cubre errores de lectura ni contenido desconocido en esas rutas.

No se ejecutó stop ni se demostró pérdida real. **Corrección propuesta:** error Git = BLOCKED, lista exacta de archivos regenerables, comprobar escritor activo y conservar recibo reversible antes de cualquier limpieza autorizada.

### A6 — MEDIA: pruebas de topología no certifican coordinación

El test del launcher reemplaza cmux por un doble y comprueba comandos. La paridad comprueba instrucciones/configuración. No prueba entrega de mensajes, ACK, reasignación, incorporación de cambios de contrato ni los tres recibos finales.

Codex recibe un prompt que pide primary + dos threads. Claude abre tres sesiones nombradas; el arranque por sí solo no certifica que el coordinador haya asignado tareas. Mantener esos tests, pero etiquetarlos como contratos y añadir un smoke real aislado.

## Inventario observado

| Grupo | Roles presentes | Cambios pendientes agregados según API | Commits no publicados según refs locales/API |
|---|---|---:|---:|
| reconocimientos-unificacion | back/front/app | 22 | 1 |
| agropartners-organigrama | back/front/app | 4 | 0 |
| qa-modulos-parity | back/front/app | 14 | 39 |

Estas cifras NO equivalen a errores ni justifican limpieza; las sesiones pueden estar trabajando. No se hizo fetch/rebase en repositorios de producto y no se certificó publicación remota. La API mostró cero grupos archivados; no se deduce ausencia de entregas históricas. Se retuvo `git status --short --branch` de los nueve worktrees.

## Medición que falta para demostrar el propósito

Ejecutar desde una sesión autorizada dentro de cmux, en un workspace de auditoría separado:
1. Identificar primary/back y workers/front/app, con rutas únicas y exactamente una autoridad OpenSpec explícita.
2. Enviar un nonce del primary a cada worker y recibir ACK con el mismo nonce; registrar latencia monotónica envío/ACK y fallos.
3. Introducir un cambio de contrato ficticio, sin tocar producto; ambos consumidores deben reconocer su nueva revisión.
4. Simular un worker bloqueado; reasignar sólo lectura/test independiente, sin dos escritores sobre un repositorio.
5. Consolidar tres recibos con SHA, estado dirty, comandos y resultados. Rechazar un recibo anterior al último cambio de contrato.
6. Probar en remotos Git temporales que fallo de test, recibo obsoleto o carrera de refs bloquea promoción; fallo parcial entre remotos mantiene el grupo abierto.

Métricas: tiempo lanzamiento→ready, envío→ACK, duración por fase, número de reintentos con igual entrada/revisión, tiempo bloqueado, lecturas repetidas, pruebas ejecutadas y tiempo total hasta entrega verificable. Los pasos deben tener timeout y máximo de reintentos explícitos; un timeout no debe declararse éxito.

**Criterio de aceptación:** 100% de mensajes con ACK en el smoke, cero doble escritor, cero planes seleccionados por heurística, cero promociones con SKIPPED/FAIL o recibos obsoletos. `complete` sólo con prueba de integración de los tres repositorios; antes, `ready-for-qa` o BLOCKED. Las latencias iniciales son una línea base, no un SLO inventado.

## Límites y siguiente decisión

Esto es una auditoría de configuración, código instalado, fixtures y estado local; NO una certificación completa de cmux ni de entregas históricas. El bloqueo de socket impide comprobar aquí las sesiones y mensajes reales. Primero corregir A1–A3; después medir el smoke autorizado. Mantener seguridad y evidencias cuesta algo de tiempo, pero evita optimizar falsos éxitos.

Evidencia privada: `/tmp/cmux-triangulation-audit/`; contiene logs, tiempos, inventario, status de siblings y probes. El manifiesto SHA-256 identifica bytes, no valida su contenido; al estar en `/tmp`, es evidencia temporal. Este informe durable conserva conclusiones y mediciones sin publicar el inventario completo.
