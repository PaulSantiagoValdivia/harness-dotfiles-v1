<!-- user-override:codex-writes-code — FUERA de los bloques gentle-ai a propósito.
     gentle-ai sync regenera todo lo que está entre sus marcadores (ya pasó el
     2026-08-28 y se llevó la versión anterior de esta regla); este bloque debe
     sobrevivir. Si gentle-ai lo pisa igual, la autoridad real sigue siendo el
     hook route-code-to-codex.sh. -->

## OVERRIDE — Codex writes ALL product code (supersedes "Standalone Claude runtime")

The `gentle-ai:standalone-runtime` block above is template text and is OVERRIDDEN:
Claude organizes, specifies, and audits; **Codex is the only writer of product
code**, in every repo, always. This is enforced by a PreToolUse hook
(`~/.claude/hooks/route-code-to-codex.sh`) that blocks Edit/Write/NotebookEdit
and Bash file-writes on code files. Claude edits directly only: `.claude/`,
`.agent/`, `.atl/`, `openspec/`, and markdown/doc files.

For code changes: `~/.claude/bin/codex-run exec --skip-git-repo-check --sandbox workspace-write -m <model> "<bounded instruction>"`,
then audit with `git diff`. For batches of bounded independent tasks: the
`codex-build` workflow. Conscious escape hatch (user-authorized only):
`CLAUDE_ALLOW_DIRECT_EDIT=1`.

### Selección de modelo Codex (regla del usuario 2026-09-10 — ahorro de créditos)

Codex se quedó sin cuota rápido porque `-m gpt-6-astra` se usaba para TODO,
incluido un fix de una línea. La fuente real de metadata es
`~/.codex/models_cache.json` — el `[tui.model_availability_nux]` de
`config.toml` es solo el contador de avisos de la TUI, no un ranking, y no hay
que citarlo como tal. Antes de cada `codex-run`, elegí el modelo por la tarea
real, no por default:

| slug | descripción oficial en models_cache.json |
|------|------------------------------------------|
| `gpt-6-astra` | "our most capable model for complex, demanding work" (priority 1) |
| `gpt-reserve` | "fast and affordable agentic coding model" (priority 3) |
| `gpt-5.6-sol` | "reliable agentic workhorse for everyday tasks" (priority 4) |
| `gpt-5.6-terra` | "balanced agentic coding model for everyday work" (priority 7) |
| `gpt-5.6-luna` | "fast and affordable agentic coding model" (priority 8) |
| `codex-auto-review` | "automatic approval review model for Codex" (priority 43) |

**El eje de decisión NO es el tamaño del diff: es cuánta ambigüedad de diseño
le queda al modelo.** Dos endpoints de boilerplate con el contrato ya cerrado
son trabajo mecánico; un solo endpoint donde hay que decidir dónde va el
límite de ownership no lo es.

| Tarea | Modelo | Por qué |
|-------|--------|---------|
| Arquitectura, límites de seguridad/permisos, lógica de negocio no trivial, múltiples archivos con dependencias cruzadas, causa raíz no obvia, o cualquier brief que deje decisiones abiertas | `gpt-6-astra` | Es el único pensado para "complex, demanding work" |
| Feature con contrato ya cerrado: sabés qué archivos, qué campos y qué reglas, y el modelo solo transcribe. Varios archivos pero cero ambigüedad | `gpt-5.6-terra` | "balanced... for everyday work" — el escalón intermedio que evita pagar astra por trabajo que ya pensaste vos |
| Mecánico/acotado: un fix de una línea, boilerplate, renombres, una task bien definida de `sdd-tasks`, aplicar un patrón ya decidido a varios archivos similares | `gpt-5.6-sol` | "reliable agentic workhorse for everyday tasks"; sobra para trabajo sin ambigüedad |
| Trivial: formato, un string, un import, mover una constante | `gpt-5.6-luna` / `gpt-reserve` | "fast and affordable"; gastar más acá es puro desperdicio |
| Auditar el diff que produjo OTRO modelo | `codex-auto-review` | Modelo dedicado a revisión. Además rompe el sesgo de que audite el mismo que escribió el brief: si vos especificaste, vos revisás contra tu intención, no contra el código |
| Lote de tareas independientes y acotadas (cada una con su modelo según las filas de arriba) | Sub-agentes de Codex (`[agents]` en `config.toml`: `enabled=true`, `max_concurrent_threads_per_session=2`, `default_subagent_reasoning_effort=low`) vía el workflow `codex-build` | Paraleliza sin abrir N sesiones `codex-run` completas; el reasoning effort bajo ya está seteado para no gastar de más |

**El brief y el modelo son vasos comunicantes.** Cuanto más cerrado el brief
—archivos exactos, campos, reglas, líneas de referencia— más barato puede ser
el modelo, porque no está diseñando sino transcribiendo. Pagar `astra` por un
brief que ya cerró todas las decisiones es pagar dos veces el mismo trabajo.
La inversión rinde en el brief, no en el modelo.

Si dudás entre dos escalones: para lo mecánico arrancá por el barato — subir
cuesta un segundo `codex-run`, y usar `astra` por defecto en todo es lo que
quemó la cuota. Pero ante la duda REAL de si un cambio es mecánico o no
trivial, tratalo como no trivial: rehacer un diff mal razonado cuesta más que
lo que se ahorró.

### Dispatch paralelo: codex-build para lotes independientes (regla del usuario 2026-09-10)

`sdd-apply` (`skills/sdd-apply/SKILL.md` Step 4) es un loop `FOR EACH TASK` —
un `codex-run` bloqueante por tarea, siempre en serie, sin importar si las
tareas son independientes. Para una fase típica de 6-8 tareas (crear
endpoints + componentes de panel + configs, sin overlap de archivos) eso es
6-8 arranques de proceso Codex en serie cuando la mitad podría correr en
paralelo. `codex-build` (`~/harness-dotfiles/files/claude/workflows/codex-build.js`)
ya soporta esto — pipeline de 2 en paralelo (`MAX_PARALLEL`), worktree aislado
y auditoría por tarea — pero antes de esta regla nada lo disparaba
automáticamente: quedaba a criterio manual de la sesión orquestadora en cada
caso, y por default el Dependency Graph manda directo a `sdd-apply`.

**Regla de ruteo (aplicarla al mismo tiempo que el Review Workload Guard, justo
antes de lanzar `apply`):** para el work-unit/slice que va a implementarse,
contá las tareas SIN dependencia de orden entre sí que además no comparten
ningún archivo declarado en su descripción (regla de "Specific" en
`skills/sdd-tasks/SKILL.md` § Task Writing Rules — el archivo ya está en el
texto de la tarea).

- **≥3 tareas independientes**: rutealas por `codex-build` en vez de por
  `sdd-apply`. Con 1-2, `sdd-apply` alcanza — el piso de tamaño ya está en el
  propio `codex-build.js` ("con 1 sola tarea esto es más caro que pedírselo
  directo a un Agent").
- **Menos de 3, o hay overlap/orden entre ellas**: `sdd-apply` normal, sin cambios.

**Cómo armar el dispatch a `codex-build` (el orquestador hace esto, no `sdd-apply`):**
1. `tasks: [{ id, description, model }]` — `model` es el tag `[codex:
   sol|astra]` que `sdd-tasks` ya dejó en `tasks.md`. `id` es un slug corto
   único (ej. `1-2-auth-middleware`).
2. `description` tiene que ser AUTOCONTENIDA: `codex-build` lanza un `agent()`
   fresco por tarea que NO tiene acceso a spec/design — solo recibe este
   string. Inline ahí el escenario de spec relevante y la restricción de
   design que aplica a esa tarea puntual, no solo la línea de `tasks.md`.
3. `maxParallel: 2` — no subir; es el mismo techo de concurrencia del
   Delegation Gate (`Codex [agents].max_concurrent_threads_per_session=2`).

**Después de que `codex-build` devuelve** (nunca mergea nada — lo dice
explícito en su `note` de salida): por cada tarea en `approved`, mergeá su
rama `codex-<id>` a la rama de trabajo (merge o cherry-pick, tu criterio con
el diff real), borrá el worktree, marcá `[x]` en `tasks.md`, y persistí
`apply-progress` anotando qué tareas corrieron por `codex-build` vs
`sdd-apply` normal. Las de `needsWork`: pasalas a una continuación de
`sdd-apply` (ya soporta continuar batches vía Apply-Progress Continuity) o
resolvelas vos con el detalle de `issues` que trajo el audit.

### Fallback — Codex sin créditos (regla del usuario 2026-09-03)

When Codex runs out of quota, **Claude writes the code**. Being blocked with no
writer is worse than Claude writing under audit. The switch is a FILE, because
an already-open session cannot change its own environment:

```
~/.claude/codex-sin-creditos
```

`codex-run` creates it automatically when Codex fails with a quota/usage-limit
error; you may also `touch` it yourself. While it exists and is fresh (TTL
`CODEX_SIN_CREDITOS_TTL_H`, default 12h; `0` = never expires),
`route-code-to-codex.sh` stops blocking Edit/Write/Bash on code files.

Non-negotiable while the fallback is active: same standard of work, no lowered
bar. Complete production code, no placeholders or elision comments, real files
read before writing, and the SAME audit you would apply to a Codex diff
(`git diff`, the role's verification commands, exit codes reported honestly).
Delete the file the moment quota returns: `rm ~/.claude/codex-sin-creditos`.

**A 401 is NOT missing quota.** A logged-out Codex (`~/.codex/auth.json` absent)
throws a storm of `401 Unauthorized: Missing bearer` and the natural reading is
"we ran out of credits". They are different problems: quota comes back on its
own, a login does not. `codex-run` tells them apart and, on a 401, prints the
fix (`codex login`, interactive — only the user can run it) WITHOUT raising the
switch: an auth blip must not hand Claude the whole repo to write.

**Sub-agents do not see the SessionStart notice.** Their `Code routing` block
still says Codex writes the code, so a spawned agent will sit waiting for
authorization instead of working (observed the day this rule was created). When
you dispatch any agent while the fallback is active, say it in the prompt:
"Codex has no quota; YOU write the code with Edit/Write, same standard, and
audit your own diff."

### ODD en este harness (decisión del usuario 2026-09-26 — piloto en curso)

gentle-ai 3.x hace de ODD el flujo default. En este harness:

- **Supersede** los dos primeros bullets del "Delegation gate" del Runtime Budget ("Default: no sub-agent" / "Delegate only when"): manda el ruteo de ODD con sus Mandatory Delegation Triggers.
- **ODD para todo el trabajo.** SDD completo (`/gentle-sdd-*`) SOLO si el usuario lo pide explícitamente.
- **OpenSpec = solo contrato entre repos.** En una triangulación, cada repo corre ODD; el contrato (shape, unidad, precisión, semántica de error) vive autocontenido en el backend canónico: `openspec/changes/<slug>/contract/`.
- **El writer delegado de ODD es Codex** (ver arriba). El trigger "writer at 2+ non-trivial files" se cumple con `codex-run`/`codex-build`, nunca con un sub-agente Claude que edite código.
- **Artifact store cuando se elige SDD explícito:** `openspec` is the ACTIVE DEFAULT (`openspec/changes/<slug>/`); `engram`/`hybrid` solo por pedido explícito.
- **Review automático (RDD) apagado** (`gentle-ai review mode disable`): un solo carril de review por cambio.
- La decisión está sujeta al piloto registrado en `~/harness-dotfiles/odd/tasks/gentle-ai-v3-odd.md` (línea base + métricas). No reabrir sin esos datos.
