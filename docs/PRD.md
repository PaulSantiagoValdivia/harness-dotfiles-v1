# PRD histórico — harness con Conductor (supersedido)

> **Estado desde 2026-08-28:** Conductor ya no es un runtime activo. Este
> documento se conserva como registro de decisiones y trabajo previo para no
> abandonar worktrees ni evidencia. La configuración vigente está descrita en
> [`README.md`](../README.md) y es Claude Code + Codex standalone, OpenSpec como
> autoridad única, Engram directo y triangulación automática con tres frentes:
> Claude enlaza sesiones/teammates y Codex usa un primary + dos agent threads.
> Las reglas de MCP Codex, SQLite/cross-session routing,
> binario bundled y configuración de Conductor que aparecen debajo son
> **históricas y no deben reinstalarse**.

**Versión:** 1.1 · **Fecha:** 2026-07-27 · **Owner:** cocoa (development@cocoalatam.com) · **Ejecutor:** persona que configura el harness en otra máquina (o re-provisiona esta)

Este documento describe QUÉ debe quedar instalado y configurado, POR QUÉ cada pieza existe, y CÓMO verificar que el resultado es equivalente al harness original. Quien lo ejecute no necesita conocimiento previo del setup — todo el contenido exacto está inline o referenciado como archivo a copiar.

---

## 1. Resumen ejecutivo

El harness es un entorno de desarrollo asistido por IA con **cinco componentes que cooperan**:

| Componente      | Rol                                                                                                                                                                        | Binario / versión de referencia                                                      |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| **Claude Code** | Orquestador principal. Delega trabajo a sub-agentes, corre workflows de grafo, aplica el protocolo SDD                                                                     | `claude` 2.1.220 (`~/.local/bin/claude`)                                             |
| **Codex CLI**   | Segundo motor de IA, independiente. Usado como contra-revisor (dual-review) y como ejecutor auditado (codex-build). También expuesto como MCP server dentro de Claude Code | global 0.146.0 (`/usr/local/bin/codex`) · Conductor 0.144.1 (mínimo compatible real) |
| **Gentle AI**   | Instalador/gestor real de persona, skills y comandos SDD para ambos clientes                                                                                               | `gentle-ai` 2.2.2                                                                    |
| **Engram**      | Memoria persistente bajo demanda mediante un único MCP directo por cliente                                                                                                 | `engram` 1.20.0 (`/usr/local/bin/engram`)                                            |
| **Conductor**   | UI de escritorio para correr sesiones Claude/Codex en worktrees                                                                                                            | app de escritorio, config en `~/.conductor/settings.toml`                            |

Sobre esa base corren tres capas de comportamiento:

1. **`~/.claude/CLAUDE.md`** (499 líneas) — el "sistema operativo" del harness: reglas de orquestación (Agent Teams Lite), protocolo SDD completo, frontera Agent-vs-Workflow, tabla de modelos por fase, protocolo Engram.
2. **Skills + agents + workflows** — 22 skills en `~/.claude/skills/`, 8 agentes SDD en `~/.claude/agents/`, 2 workflows de grafo en `~/.claude/workflows/`.
3. **Skill registry auto-generado** — un hook acotado lo regenera una vez al iniciar/limpiar sesión; no inyecta planes ni memoria.

**Criterio de éxito global:** Claude y Codex ofrecen el mismo ciclo SDD (OpenSpec por defecto), memoria Engram bajo demanda y skills Gentle AI; Claude conserva además sus workflows nativos. La ejecución ordinaria es inline, con máximo 2 agentes y un solo carril de review.

---

## 2. Alcance

**Incluye:**

- Instalación de binarios (`claude`, `codex`, `engram`) y configuración de los 4 componentes.
- Copia de artefactos de configuración: `CLAUDE.md`, `settings.json`, `statusline.sh`, `skills/`, `agents/`, `workflows/`, configs de Codex y Conductor.
- Instalación de plugins user-scope y registro del marketplace de Engram.
- Verificación end-to-end.

**NO incluye:**

- Plugins de scope proyecto/local (`context7`, `firebase`, `superpowers`, `code-review`, etc.) — se instalan por repo cuando se trabaja en ese repo, no son parte del harness base.
- Toolchain de lenguajes (`fnm`, `fvm`, `rbenv`, Docker) — pre-existente en la máquina origen, fuera del alcance de este PRD.
- Credenciales: cada persona usa **sus propias cuentas** (ver §3). No se copian tokens ni logins.
- La lista de proyectos "trusted" de Codex y los proyectos de Conductor — se regeneran en la máquina destino según los repos que existan ahí.

---

## 3. Prerequisitos

| Requisito                    | Detalle                                                                                                                                                                                                                                                                                  |
| ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cuenta Claude                | Plan **Claude Pro** (o superior). Login propio de quien usa la máquina.                                                                                                                                                                                                                  |
| Cuenta Codex                 | Plan **Codex Plus** (o superior). Cuenta **distinta e independiente** de la de Claude.                                                                                                                                                                                                   |
| macOS                        | El origen es una **Mac Intel (x86_64)**. En Apple Silicon, instalar los equivalentes **arm64 nativos** — no asumir Rosetta.                                                                                                                                                              |
| Homebrew                     | En Intel el prefix es `/usr/local`; en Apple Silicon es `/opt/homebrew`. **Gotcha real del origen:** esta máquina fue migrada desde Apple Silicon y hubo binarios arm64 heredados que no corrían. Ante cualquier error raro de un binario, verificar `file <binario>` contra `uname -m`. |
| Acceso a los archivos origen | Los artefactos a copiar (§5) viven en la máquina origen. Empaquetarlos (tar/repo de dotfiles) antes de empezar.                                                                                                                                                                          |
| `jq`                         | Lo usa `statusline.sh`.                                                                                                                                                                                                                                                                  |

---

## 4. Arquitectura del harness (por qué cada pieza)

```
                    ┌─────────────────────────────────┐
                    │        Claude Code (CLI)        │
                    │  orquestador · CLAUDE.md global │
                    └──┬──────────┬──────────┬────────┘
          Agent tool   │          │ Workflow │  MCP
        (fases SDD,    │          │  tool    │
         delegación)   │          │          │
                       ▼          ▼          ▼
              8 agentes SDD   dual-review   codex mcp-server
              (~/.claude/     codex-build   (Codex como tool)
               agents/)       (~/.claude/
                               workflows/)
                       │          │
                       └────┬─────┘
                            ▼
                 Engram (memoria persistente)
              MCP directo en Claude y Codex
```

Decisiones de diseño que el ejecutor debe respetar (todas documentadas y razonadas en `CLAUDE.md`):

| Decisión                   | Regla                                                                                                                                                                                                   |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Frontera Agent vs Workflow | Trabajo ordinario → inline. Fases SDD → agente dedicado. Fan-out explícito → workflow en lotes de máximo 2.                                                                                             |
| Diamante SDD               | `spec` y `design` son hermanos; pueden ocupar los 2 slots. En modo automático las demás fases siguen secuencialmente.                                                                                   |
| Modelos por fase SDD       | propose/design → `opus`; archive → `haiku`; resto → `sonnet`. Está duplicado en la tabla de `CLAUDE.md` y en el frontmatter de cada agente — deben coincidir.                                           |
| Dual-review vs codex-build | Simétricos e inversos: en `dual-review` Claude revisa y Codex contra-revisa ciego; en `codex-build` Codex implementa en worktrees aislados y Claude audita. **Ninguno mergea automáticamente.**         |
| Codex effort               | `codex-build` nunca usa `effort=ultra` (dispara el multi-agente propio de Codex, no deseado bajo orquestación de Claude). El default standalone es `low`; los workflows pinean `medium` explícitamente. |
| Skill registry             | El orquestador pasa **paths** de `SKILL.md` a sub-agentes, nunca resúmenes. El registry es un índice, no un bundle.                                                                                     |

---

## 5. Manifiesto de archivos a copiar

> **Actualización 2026-09-03 — gentle-ai genera, el harness parchea.** `gentle-ai install`
> es la fuente de agents, skills, commands y bloques de CLAUDE.md; el repo NO versiona
> copias de esa salida (el snapshot anterior de `files/claude/{agents,skills}` era peso
> muerto que bootstrap nunca instalaba). Lo que sí versiona son los PARCHES que el harness
> necesita encima (`files/claude/patches/`) y el script idempotente que los aplica
> (`files/claude/bin/apply-agent-patches.sh`), porque gentle-ai 2.2.2 declara los tools de
> memoria como plugin (`mcp__plugin_engram_engram__*`) y este harness usa el MCP directo
> (`mcp__engram__*`): sin el parche, los sub-agentes SDD arrancan sin memoria. Los 16 hooks,
> `codex-run` y el statusline también se versionan e instalan. El enforcement "Codex escribe
> el código" es opt-in (`bootstrap.sh --codex-enforcement`); `context-budget.sh` es de equipo.
> `~/.claude/memory` es personal y no se versiona.

Copiar **tal cual** desde la máquina origen (misma ruta relativa a `$HOME`):

| #   | Origen                                                                     | Qué es                                                         | ¿Editar tras copiar?                  |
| --- | -------------------------------------------------------------------------- | -------------------------------------------------------------- | ------------------------------------- |
| 1   | `~/.claude/CLAUDE.md`                                                      | Instrucciones globales del orquestador (499 líneas)            | No                                    |
| 2   | `~/.claude/settings.json`                                                  | Config de Claude Code (contenido exacto en §6.2)               | Sí — ver notas de §6.2                |
| 3   | `~/.claude/statusline.sh`                                                  | Statusline bash (dir, branch git, flavor Flutter, modelo)      | No (requiere `jq`)                    |
| 4   | Gentle AI global                                                           | Instala skills y comandos SDD nativos para Claude Code y Codex | Gestionado por `gentle-ai install`    |
| 5   | Gentle AI global                                                           | Instala los 8 ejecutores de fase SDD                           | Gestionado por `gentle-ai install`    |
| 6   | `~/.claude/workflows/` (completo)                                          | `dual-review.js` y `codex-build.js`                            | No                                    |
| 7   | `~/.codex/config.toml`                                                     | Config de Codex (contenido en §6.4)                            | Sí — quitar `[projects.*]` del origen |
| 8   | `~/.codex/AGENTS.md`, `engram-instructions.md`, `engram-compact-prompt.md` | Overlay Codex equivalente a Claude                             | No                                    |
| 9   | `~/.conductor/settings.toml`                                               | Config de Conductor (contenido en §6.5)                        | No                                    |

**No copiar:** `~/.claude.json` (estado de la app: onboarding, caches, machineID — se regenera), `~/.claude/plugins/` (se regenera al instalar plugins), `.atl/skill-registry.md` (auto-generado por el hook).

---

## 6. Requisitos por componente

### 6.1 Binarios base

- **R1.** `claude` ≥ 2.1.220 instalado (instalador oficial → `~/.local/bin/claude`).
- **R2.** `codex` (codex-cli) ≥ 0.145.0 instalado vía Homebrew, standalone. En Intel queda en `/usr/local/bin/codex`; en Apple Silicon quedará en `/opt/homebrew/bin/codex` — ver nota de rutas en R11.
- **R3.** `engram` ≥ 1.20.0 en el prefix de Homebrew. **Gotcha documentado:** en el origen, la config de Codex apuntó a `/opt/homebrew/bin/engram` (inexistente en Intel) y el MCP nunca arrancaba, sin error visible. Verificar la ruta real con `which engram` y usar esa ruta absoluta en las configs.
- **R4.** Todos los binarios nativos para la arquitectura de la máquina (`file $(which claude codex engram)` debe coincidir con `uname -m`).

### 6.2 Claude Code

- **R5.** `~/.claude/settings.json` con este contenido exacto (origen, 2026-07-27):

```json
{
  "permissions": {
    "deny": [
      "Bash(rm -rf /)",
      "Bash(sudo rm -rf /)",
      "Bash(rm -rf ~)",
      "Bash(sudo rm -rf ~)",
      "Read(.env)",
      "Read(.env.*)",
      "Edit(.env)",
      "Edit(.env.*)",
      "Bash(git push --force*)",
      "Bash(git push -f*)",
      "Bash(git reset --hard*)"
    ],
    "defaultMode": "bypassPermissions"
  },
  "model": "claude-fable-5[1m]",
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|clear",
        "hooks": [
          {
            "type": "command",
            "command": "gentle-ai skill-registry refresh --quiet --no-gitignore --cwd \"${CLAUDE_PROJECT_DIR:-$PWD}\" || true"
          }
        ]
      }
    ]
  },
  "enableWorkflows": true,
  "workflowKeywordTriggerEnabled": true,
  "workflowSizeGuideline": "small",
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline.sh"
  },
  "enabledPlugins": {
    "engram@engram": false,
    "swift-lsp@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {
    "engram": {
      "source": {
        "source": "github",
        "repo": "Gentleman-Programming/engram"
      }
    }
  },
  "tui": "fullscreen",
  "skipDangerousModePermissionPrompt": true,
  "theme": "dark"
}
```

Notas para el ejecutor:

- **`defaultMode: "bypassPermissions"` + `skipDangerousModePermissionPrompt: true` es una decisión consciente del owner**, mitigada por la deny-list. Quien configure SU PROPIA máquina con este PRD debe decidir explícitamente si adopta ese modo o usa `acceptEdits`/default. No es un valor "neutro": auto-aprueba casi todo.
- `model`: ajustar al modelo disponible en el plan de quien usa la máquina.
- El hook `SessionStart` requiere Gentle AI y corre una vez por sesión/clear; `--quiet` evita añadir payload al contexto.
- **R6.** `swift-lsp` y `code-simplifier` quedan habilitados. `engram@engram` queda instalado/deshabilitado: Engram usa MCP directo en Claude y Codex para evitar hooks/protocolo/contexto duplicados.
- **R7.** MCP server `codex` registrado user-scope en Claude Code:
  ```bash
  claude mcp add --scope user codex -- codex mcp-server
  ```
  Registrar además `engram -- mcp --tools=agent` como MCP user-scope. Deben aparecer `codex` y un solo `engram`; nunca `plugin:engram` simultáneo.

### 6.3 Skills, agents y workflows

- **R8.** Ejecutar `gentle-ai install --scope global --agents claude-code,codex --preset full-gentleman --sdd-mode multi`. Es la única instalación de persona/skills/SDD; los archivos del repo son overlays, no otro plugin.
- **R9.** Gentle AI instala los 8 agentes en Claude y los comandos/prompts equivalentes en Codex, con modelos intactos: `sdd-explore` (sonnet), `sdd-propose` (opus), `sdd-spec` (sonnet), `sdd-design` (opus), `sdd-tasks` (sonnet), `sdd-apply` (sonnet), `sdd-verify` (sonnet), `sdd-archive` (haiku). Si el plan destino no tiene acceso a Opus, `CLAUDE.md` ya define el fallback: sustituir por `sonnet`.
- **R10.** Los 2 workflows copiados a `~/.claude/workflows/`:

  | Workflow         | Patrón                                                                                                                           | Args (defaults)                                                                                                                                                                         |
  | ---------------- | -------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | `dual-review.js` | Diamante: Scope → Review (lentes Claude en paralelo) → CrossCheck (Codex ciego) → Verify (escépticos adversariales) → Synthesize | `repo` (`.`), `spec` (`HEAD`; acepta `origin/master...HEAD`, `9bb8473^..9bb8473`), `maxFindings` (4), `maxParallel` (2), `reviewEffort` (`medium`), `codexBin` (`/usr/local/bin/codex`) |
  | `codex-build.js` | Inverso: Execute (Codex por tarea, worktree aislado) → Audit (Claude contra lo pedido). Nunca mergea                             | `repo` (requerido), `tasks` (`[{id, description}]`), `executeEffort` (`medium`, **nunca `ultra`**), `maxParallel` (2), `codexBin` (`/usr/local/bin/codex`)                              |

- **R11.** ⚠️ **Ajuste obligatorio en Apple Silicon:** ambos workflows tienen `codexBin` default `/usr/local/bin/codex`. En una Mac arm64 el binario estará en `/opt/homebrew/bin/codex`. Opciones: editar el default en ambos `.js`, o pasar `codexBin` en cada invocación. Elegir la primera y dejarlo documentado.

### 6.4 Codex

- **R12.** `~/.codex/config.toml` con esta base (adaptar rutas al prefix real y regenerar `[projects.*]` con los repos de la máquina destino):

```toml
model_instructions_file = "/Users/<usuario>/.codex/engram-instructions.md"
experimental_compact_prompt_file = "/Users/<usuario>/.codex/engram-compact-prompt.md"
model = "gpt-5.6-sol"
model_reasoning_effort = "low"

[mcp_servers.engram]
command = "<prefix-homebrew>/bin/engram"
args = ["mcp", "--tools=agent"]
```

- No declarar escalares en la tabla raíz `[agents]`. El Codex 0.144.1 embebido en Conductor solo admite roles allí y falla con `expected struct AgentRoleToml`. Máximo 2, no recursión y effort barato se aplican como política en `AGENTS.md`; `[agents.<role>]` sí se preserva.

- `model_reasoning_effort = "low"` es el default standalone deliberado (costo); los workflows y Conductor lo suben cuando hace falta.
- Los archivos `engram-instructions.md` / `engram-compact-prompt.md` se copian del origen (manifiesto §5, ítem 8).
- Las entradas `[projects."<ruta>"] trust_level = "trusted"` se agregan por repo en la máquina destino (Codex las ofrece al abrir cada proyecto).

### 6.5 Conductor

- **R13.** App Conductor instalada y `~/.conductor/settings.toml` con:

```toml
"$schema" = "https://conductor.build/schemas/settings.schema.json"
claude_provider = "default"
tool_approvals_enabled = false

[git]
branch_prefix_type = "github_username"

[models]
default = "opus-5-1m"

[models.codex]
default_thinking_level = "high"
review_thinking_level = "high"
```

- **No configurar overrides de ruta de ejecutable** (`claude_code_executable_path` / `codex_executable_path`): en el origen se removieron a propósito; un override no-vacío hace aparecer una advertencia estática que se confunde con error.
- Conductor elige su propio modelo Claude (`opus-5-1m`), independiente del `model` de Claude Code — es intencional.
- `tool_approvals_enabled = false` sigue la misma filosofía que `bypassPermissions`: decisión consciente, revisar con el owner de la máquina destino.

### 6.6 Skill registry (gentle-ai)

- **R14.** CLI `gentle-ai` instalado y funcional: `gentle-ai skill-registry refresh --force` desde `$HOME` debe generar `~/.atl/skill-registry.md` listando las skills invocables (hoy 10 filas — excluye `sdd-*` y `_shared`, que están marcadas no-invocables — esa exclusión es correcta, no un bug).

---

## 7. Plan de instalación (orden de dependencia)

1. **Binarios:** instalar `claude`, `codex` (brew), `engram` (brew), `gentle-ai`, `jq`. Verificar arquitectura de los tres primeros (`file`).
2. **Login:** `claude` (cuenta Claude Pro propia) y `codex` (cuenta Codex Plus propia).
3. **Copiar artefactos** del manifiesto §5 (ítems 1–6: todo `~/.claude/` salvo `plugins/` y `.claude.json`).
4. **Editar `settings.json`** según notas de R5 (modelo del plan destino; decidir modo de permisos).
5. **Plugins Claude:** instalar `swift-lsp` y `code-simplifier` según R6. Mantener `engram@engram` deshabilitado; Engram funciona mediante el MCP directo único.
6. **MCP codex:** registrar según R7.
7. **Codex:** copiar ítems 7–8 del manifiesto, aplicar R12 (rutas + limpiar projects).
8. **Conductor:** instalar app, aplicar R13.
9. **Registry:** correr `gentle-ai skill-registry refresh --force` (R14).
10. **Verificación:** ejecutar el checklist de §8 completo.

---

## 8. Criterios de aceptación (checklist verificable)

### 8.0 Rutas SDD en Conductor y evidencia actual

| Ruta                              | Contrato                                                                                                                                                                                          | Evidencia 2026-07-31                                                                                                                                                                                                                                                 |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code dentro de Conductor   | `apply_backend: native` por defecto; `codex` invoca una unidad mediante `codex-build` a esfuerzo medium. Solo `sdd-apply` integra/escribe OpenSpec y acepta `gentle-ai.sdd-execution-receipt/v1`. | Workflow instalado idéntico al source, `codexBin` ejecutable, MCP descubierto y harness de receipt aprobado. La invocación real autenticada sigue pendiente porque `claude -p --effort medium` devuelve `Not logged in · Please run /login` antes de ejecutar tools. |
| Codex directo dentro de Conductor | SDD/OpenSpec/Engram nativos; no Claude, no `codex-build`, máximo 2, sin recursión. Conductor aplica medium por defecto y high en review.                                                          | Codex global 0.146.0 y bundled 0.144.1 aceptan strict startup; DB, prompts SDD, política y un único Engram verificados.                                                                                                                                              |

Gate automatizado registrado: **154 PASS / 1 WARN / 0 FAIL**. El warning es el
health-check MCP bajo sandbox/login y no sustituye el smoke autenticado.

Rollback operativo: seleccionar `native`, restaurar los overlays desde el backup
de bootstrap (`/Users/cocoa/.harness-backup-20260731-134831`) y ejecutar
`./verify.sh`. Nunca eliminar OpenSpec ni duplicar Engram para recuperar la ruta.

> **Pendiente 3.3:** después de `/login`, invocar realmente `codex-build` desde
> Claude a esfuerzo medium con un paquete inválido seguro y registrar el rechazo
> estructurado sin mutaciones. No marcar esta aceptación por descubrimiento o
> existencia de archivos solamente.

- [ ] `uname -m` coincide con la arquitectura de `file $(which claude) $(which codex) $(which engram)` — ningún binario emulado.
- [ ] `claude --version` ≥ 2.1.220 · `codex --version` ≥ 0.145.0 · `engram --version` ≥ 1.20.0.
- [ ] Gentle AI valida el plan global para `claude-code,codex`; ambos muestran los mismos comandos SDD y OpenSpec como store por defecto.
- [ ] Engram aparece **una sola vez** como MCP directo en Claude; `engram@engram` está deshabilitado.
- [ ] `claude mcp list` muestra `codex` conectado; una invocación simple a la tool `codex` responde.
- [ ] En Codex standalone: las tools `mem_*` de Engram cargan al iniciar sesión (si no cargan, revisar la ruta de `mcp_servers.engram` — gotcha R3).
- [ ] Los 8 agentes SDD aparecen disponibles para el Agent tool, con los modelos de R9.
- [ ] Las 11 skills invocables aparecen en autocomplete (`/branch-pr`, `/judgment-day`, etc.); las `sdd-*` NO aparecen (correcto).
- [ ] `~/.atl/skill-registry.md` existe, lista 10 skills con paths absolutos válidos, y se regenera al iniciar/limpiar sesión (hook `SessionStart`).
- [ ] Smoke test `dual-review`: en un repo con un commit reciente, invocar el workflow `dual-review` con `spec: "<sha>^..<sha>"` — deben ejecutarse las 5 fases (Scope, Review, CrossCheck, Verify, Synthesize) y el nodo Codex debe correr sin error de binario.
- [ ] Smoke test `codex-build`: invocar con 1 tarea trivial en un repo de prueba — Codex implementa en un worktree bajo `.claude/worktrees/codex-<id>`, Claude audita, y **nada se mergea automáticamente**.
- [ ] Conductor abre un chat nuevo con modelo Claude por defecto y sin advertencias de ejecutable.
- [ ] Statusline visible en Claude Code: directorio + branch git; en un repo Flutter con `lib/main_dev.dart`, muestra el flavor.

---

## 9. Riesgos y gotchas conocidos (todos ocurrieron de verdad en el origen)

| Riesgo                                                                                                                                | Mitigación                                                                                                                                       |
| ------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Binarios de arquitectura equivocada tras migración/copia entre Macs                                                                   | R4: verificar `file` vs `uname -m` ante cualquier error raro.                                                                                    |
| Ruta de Engram incorrecta en Codex → MCP nunca arranca, **sin error visible**                                                         | R3/R12: usar `which engram` y ruta absoluta verificada. Checklist incluye la prueba.                                                             |
| Engram duplicado (plugin + MCP server) en Claude Code                                                                                 | R6: plugin deshabilitado, MCP directo único.                                                                                                     |
| Engram duplicado por plugin + MCP en Codex                                                                                            | Gentle AI conserva el marketplace, pero `plugins."engram@engram".enabled=false`; queda un solo `[mcp_servers.engram]`.                           |
| `claude mcp list` marca Codex caído dentro de un sandbox                                                                              | Codex necesita escribir `~/.codex/state_5.sqlite`; repetir fuera del sandbox. `codex exec` standalone sigue siendo el fallback de los workflows. |
| `codexBin` hardcodeado a `/usr/local/bin` en los workflows                                                                            | R11: editar defaults en Apple Silicon.                                                                                                           |
| Override de ejecutable en Conductor → advertencia que parece error                                                                    | R13: no configurar overrides.                                                                                                                    |
| `effort=ultra` en Codex dispara su multi-agente propio bajo orquestación de Claude                                                    | R12/codex-build: default `low`/`medium`, nunca `ultra` en workflows.                                                                             |
| Config válida en Codex global pero inválida dentro de Conductor                                                                       | Verificar parseo estricto con ambos binarios. No usar escalares en `[agents]`; 0.144.1 los interpreta como roles.                                |
| `bypassPermissions` copiado a ciegas a la máquina de otra persona                                                                     | §6.2: decisión explícita del nuevo owner, no default silencioso.                                                                                 |
| CLI `gentle-ai` ausente → registry nunca se regenera y la delegación pierde inyección de skills (falla silenciosa por el `\|\| true`) | R14 + checklist de regeneración.                                                                                                                 |

---

## 10. Fuera de alcance / trabajo futuro

- ✅ **Hecho (2026-07-27):** automatización de este PRD como repo de dotfiles — `~/harness-dotfiles` (`bootstrap.sh` idempotente + `verify.sh` + `files/` con los artefactos del manifiesto §5).
- ✅ **Hecho (2026-07-27):** primera corrida real de `codex-build.js` — smoke test aprobado: Codex implementó la tarea en un worktree aislado, Claude la auditó (diff, permisos, ejecución verificada de forma independiente) y nada se mergeó automáticamente.
- Plugins por proyecto (`superpowers`, `context7`, `firebase`, etc.): instalarlos al abrir cada repo según necesidad — por diseño, no es un pendiente del harness base.
