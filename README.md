# harness-dotfiles — Claude y Codex standalone con SDD coordinado

Bootstrap reproducible para **Gentle AI + Claude Code + Codex + OpenSpec +
Engram**. La triangulación ejecuta tres frentes simultáneos con comunicación,
reasignación y consolidación reales. Claude y Codex siguen siendo runtimes
independientes y ninguno necesita Conductor.

## Quick path

1. Ejecutar `./bootstrap.sh`; crea un backup antes de sobrescribir overlays.
2. Iniciar sesión en `claude` y `codex` con las cuentas correspondientes.
3. Ejecutar `./verify.sh`; el resultado esperado es `0 FAIL`.
4. Desde una terminal de cmux, ejecutar `triangulate claude <slug>` o
   `triangulate codex <slug>`; el launcher crea/reutiliza los tres worktrees e
   inicia Cocoa DevTools en segundo plano.
5. Ejecutar `devtools` para auditar cada triangulación e integrar a `dev`
   únicamente cuando backend, panel y app estén verificados, limpios y al día.

En una máquina que no pertenece al owner original, usar
`./bootstrap.sh --no-bypass` para conservar permisos interactivos.

## Arquitectura activa

| Área           | Decisión                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------- |
| SDD            | OpenSpec es la única autoridad del cambio, normalmente en backend.                                      |
| Triangulación  | Tres frentes simultáneos: el primary canónico + dos owners de repositorio.                              |
| Comunicación   | Claude usa mensajería nativa entre sesiones/teammates; Codex usa el mailbox de sus agent threads.       |
| Reasignación   | El primary asigna la siguiente tarea desbloqueada y transfiere escritura solo con handoff limpio.       |
| Consolidación  | El primary reúne tres recibos, verifica contratos y actualiza el OpenSpec canónico.                     |
| Escritura      | Cada sesión escribe únicamente su repositorio; solo la sesión canónica actualiza OpenSpec.              |
| Subagentes     | Máximo dos hijos por sesión principal; no hay delegación recursiva.                                     |
| Memoria        | Un único MCP Engram directo por cliente, consultado bajo demanda.                                       |
| Modelos        | Sesiones principales en esfuerzo `medium`; hijos mecánicos en `low`; revisión exigente en `high`.       |
| Permisos Codex | Acceso completo y `approval_policy="never"` por preferencia explícita del owner.                        |
| Conductor      | Runtime retirado. Sus worktrees existentes se preservan solo para recuperar y cerrar trabajo pendiente. |

El límite de dos hijos produce exactamente tres frentes en modo coordinado:
primary/backend + owner/panel + owner/app. En Claude también se pueden enlazar
tres sesiones independientes ya abiertas; en Codex NO se deben abrir tres
top-level esperando comunicación peer-to-peer.

## Estructura

| Ruta                                              | Propósito                                                                                                                                                                                                             |
| ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bootstrap.sh`                                    | Instala overlays idempotentes y migra configuración legacy.                                                                                                                                                           |
| `verify.sh`                                       | Verifica arranque, MCP, SDD, concurrencia y paridad. La sección "Auditoría de la máquina" convierte cada hallazgo de configuración en un check (engram-sync, trust de Codex, plugins muertos, `.atl` huérfanos, disco de Codex, worktrees). |
| `files/claude/`                                   | Instrucciones y settings standalone de Claude.                                                                                                                                                                        |
| `files/claude/hooks/`                             | Los 16 hooks del harness con su suite de contrato (`hooks/tests`). Cada uno nace de un incidente documentado en su cabecera. `route-code-to-codex.sh` y `validate-enforcement.sh` son opt-in (`--codex-enforcement`). |
| `files/claude/bin/`                               | `codex-run` (codex sin shim de cmux, stdin cerrado, timeout duro) y `apply-agent-patches.sh` (re-aplica los parches sobre lo que genera gentle-ai; corre en cada SessionStart).                                       |
| `files/claude/patches/`                           | Parches sobre agents/skills de gentle-ai: tools del MCP Engram directo, Step 0 OpenSpec, Background wait, Archive Gate, Module DoD, Code routing (opt-in) y el OVERRIDE de CLAUDE.md.                                 |
| `files/claude/triangulate.conf.example`           | Rutas por máquina de back/front/app; bootstrap lo copia a `~/.claude/triangulate.conf` solo si no existe.                                                                                                             |
| `files/codex/`                                    | Instrucciones y prompts base de Codex.                                                                                                                                                                                |
| `files/shared/`                                   | Políticas comunes de runtime y arquitectura.                                                                                                                                                                          |
| `files/shared/skills/triangulation-orchestrator/` | Contrato compartido de mensajes, handoff, recibos y consolidación.                                                                                                                                                    |
| `files/shared/skills/harness-evidence/` | Evidencia local con revisión, estado observado y límites explícitos. [Guía y despliegue acotado](docs/harness-evidence.md). |
| `files/shared/bin/triangulate`                    | Launcher único con topologías nativas para Claude y Codex.                                                                                                                                                            |
| `files/shared/bin/devtools`                       | Abre el control local de auditoría e integración segura a dev.                                                                                                                                                        |
| `files/shared/devtools/`                          | Source gestionado del servidor y del HTML Cocoa DevTools.                                                                                                                                                             |
| `tests/standalone_runtime_parity_test.sh`         | Prueba el aislamiento Claude/Codex sin Conductor.                                                                                                                                                                     |
| `files/conductor/`                                | Configuración histórica conservada; no se instala.                                                                                                                                                                    |

## Configuración importante

- `~/.codex/config.toml` conserva modelo, proyectos, roles y secretos
  existentes. El bootstrap administra un `[agents]` soportado con
  `max_concurrent_threads_per_session = 2`.
- `~/.claude/settings.json` usa Sonnet con esfuerzo `medium`, activa Agent
  Teams y acepta mensajes de otras sesiones locales. `isolatePeerMachines=true`
  exige aprobación antes de enviar mensajes fuera de esta máquina.
- Claude ya no registra el MCP `codex` ni bloquea sus ediciones para
  enrutarlas a Codex. Para usar Codex, se abre otra sesión principal en su
  worktree.
- Los hooks y artefactos SDD se cargan desde el repositorio actual; nunca se
  copian planes completos al contexto inicial.
- `~/.codex/config.toml` instala `sandbox_mode="danger-full-access"` y
  `approval_policy="never"`. También se fijan esos flags al iniciar Codex desde
  `triangulate` o desde workflows Claude→Codex. Esto elimina las solicitudes de
  permiso, pero también elimina la barrera local contra comandos destructivos;
  se mantiene únicamente porque es una preferencia explícita del owner de esta
  máquina personal.
- Context7 usa un único transporte `stdio` tanto en la configuración global
  como en los repositorios. Esto evita que el merge de configuración construya
  un servidor inválido con `command` y `url` al recargar `skills/list`.
  `verify.sh` prueba esa recarga real y audita la configuración MCP efectiva en
  los tres repositorios y sus worktrees de triangulación.

## Triangulación automática de tres repositorios

### Capacidades verificables

| Capacidad                         | Claude                                                      | Codex directo                                                         |
| --------------------------------- | ----------------------------------------------------------- | --------------------------------------------------------------------- |
| Mensajes directos                 | Sí: `ListAgents` + `SendMessage`, o mailbox del Agent Team. | Sí dentro del primary y sus dos agent threads.                        |
| Reasignación automática           | Sí: task list/idle notice y follow-up del lead.             | Sí: el primary envía follow-ups al worker disponible.                 |
| Consolidación automática          | Sí: el lead reúne los tres recibos.                         | Sí: el primary espera resultados y ejecuta la verificación integrada. |
| Reanudación al cambiar de cliente | Git + OpenSpec + Engram.                                    | Git + OpenSpec + Engram.                                              |

**Límite técnico honesto:** tres sesiones top-level de Codex no poseen un canal
peer-to-peer nativo. Por eso el modo correcto de Codex es un primary y dos
agent threads. Esto conserva las tres ejecuciones simultáneas Y permite que el
primary reasigne y consolide.

```text
                  primary + OpenSpec canónico
                           backend
                            │
             mensajes + tareas + dependencias
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        owner backend   owner panel    owner app
        primary         worker 1       worker 2
              └─────────────┼─────────────┘
                            ▼
                recibos + verificación integrada
```

### Uso con Claude

Desde una terminal abierta dentro de cmux:

```bash
triangulate claude vacaciones-panel-descuento-fechas
```

El launcher crea/reutiliza los tres worktrees y abre tres sesiones nombradas:
`<slug>-back`, `<slug>-front` y `<slug>-app`. Iniciar la instrucción en backend:
`triangula este cambio con las sesiones front y app`. El lead descubre las
sesiones, envía tareas, recibe avisos de idle y consolida.

### Uso con Codex directo

Desde una terminal abierta dentro de cmux:

```bash
triangulate codex vacaciones-panel-descuento-fechas
```

El launcher crea/reutiliza los tres worktrees, abre **solo un primary Codex** en
backend, agrega panel/app con `--add-dir` y envía el prompt que crea exactamente
dos agent threads. Los tres avanzan en paralelo y el primary entrega un único
resultado integrado.

Para inspeccionar sin abrir nada:

```bash
triangulate plan codex vacaciones-panel-descuento-fechas
```

Las ejecuciones no hacen polling. Los mensajes, avisos de idle y resultados de
workers despiertan al coordinador. Engram se usa para recuperación durable si
se agota la cuota de Claude y se continúa con Codex; NO suplanta el canal vivo.

### Auditoría QA e integración consolidada a dev

Después de que las triangulaciones entreguen sus recibos, abre el control local:

```bash
devtools
```

La pestaña **Auditoría QA** lee `~/.claude/triangulate.conf`, agrupa por clave
todos los worktrees de backend, panel y app, y usa la base correcta por
repositorio: `origin/dev` en los tres. El estado y la
evidencia de QA permanecen en el almacenamiento local del navegador.

**La marca “QA verificado” NO sustituye las pruebas ni los recibos.** Ninguna
triangulación nueva parte de `main`; `main` queda fuera de este flujo operativo.
El botón
`Integrar verificado a dev` trabaja con una sola triangulación por vez. Exige
los tres repositorios, bloquea worktrees sucios, en detached HEAD o atrasados
respecto a `origin/dev`, y prevalida los tres antes del primer push. Primero
conserva cada rama remota y después actualiza `dev` únicamente por fast-forward;
nunca hace force-push ni publica un `HEAD` mutable: usa exactamente el SHA que
pasó la prevalidación y lo vuelve a comprobar al final. La marca `Integrado en
dev` solo la escribe el recibo exitoso del servidor, no el operador.

Tres repositorios remotos no admiten una transacción Git atómica conjunta. Si
un remoto cambia después de la prevalidación, su fast-forward se rechaza y el
recibo identifica exactamente hasta dónde llegó; la triangulación permanece
sin cerrar hasta completar el reintento. Git y OpenSpec siguen siendo la
autoridad; el HTML es el cockpit para verificar y operar esa autoridad, no una
base de datos paralela.

Cerrar o fusionar un PR no elimina automáticamente su worktree. Cocoa DevTools
mantiene un registro durable separado para esos cierres: las triangulaciones
archivadas se ocultan por defecto, pueden mostrarse o restaurarse, y conservan
la evidencia de PR/commit sin borrar ramas, worktrees ni cambios locales. Una
integración realizada desde el cockpit se archiva automáticamente después del
recibo final, dentro de la misma operación del servidor. Si el registro está
dañado o no se puede leer, la integración falla antes de modificar `dev` y no
sobrescribe la evidencia existente.

### Cambio de Claude a Codex por cuota

1. Detener al writer de Claude; nunca dejar dos clientes editando el mismo repo.
2. Conservar el estado en Git y el OpenSpec canónico; guardar un handoff Engram
   si la sesión todavía responde.
3. Ejecutar `triangulate codex <clave>`; reutiliza los worktrees existentes.
4. Codex inspecciona los tres worktrees y continúa únicamente lo pendiente.

## Verificación

```bash
bash tests/bootstrap_codex_config_test.sh
bash tests/cocoa_devtools_ui_test.sh
python3 tests/cocoa_devtools_test.py
bash tests/standalone_runtime_parity_test.sh
./verify.sh
```

`verify.sh` distingue FAIL (configuración del harness rota) de WARN (estado de la
máquina que solo el dueño puede resolver: worktrees sucios o sin remoto, proyectos
muertos en `~/.claude.json`). Un hallazgo nuevo se convierte en un check, no en una
nota: así no se vuelve a "descubrir" a mano en la próxima auditoría.

## Recuperación de trabajo legacy

No crear trabajo nuevo en Conductor. Antes de archivar un worktree antiguo:

1. Revisar `git status` y el diff.
2. Conservar cambios válidos en commits convencionales.
3. Hacer push o registrar explícitamente por qué fue supersedido.
4. Borrar el worktree únicamente después de confirmar que no contiene trabajo
   recuperable.

## Fuera de alcance

- Credenciales, logins y proyectos `trusted`.
- Toolchains de lenguajes (`fnm`, `fvm`, Ruby, Docker).
- Plugins locales de cada repositorio.
- Eliminación automática de worktrees históricos.
