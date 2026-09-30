# gentle-ai v3 + ODD en el harness

## Objetivo

Alinear el harness con gentle-ai 3.7.0: ODD es el flujo default, SDD queda
opcional explícito, review automático (RDD) apagado, Codex sigue siendo el
único escritor de código.

## Problema

El harness estaba atado a gentle-ai 2.2.2 y a SDD como flujo default. Tras
`brew upgrade` + `gentle-ai sync` (2026-09-26):

- `apply-agent-patches.sh` duplica los tools de Engram: 3.7 renderiza el prefijo
  plugin y el directo, y el `sed` plugin→directo los repite.
- Los overlays completos de `sdd-archive` y `sdd-tasks` están guardados por hash
  del template 2.2.2 y ya no se aplican.
- Los comandos pasaron a `gentle-sdd-*`; CLAUDE.md, AGENTS.md, verify.sh y tests
  nombran `/sdd-*`.
- La delegación obligatoria de ODD (writer ≥2 archivos no triviales) no dice
  que el writer es Codex; el runtime-budget dice "Default: no sub-agent".
- `route-code-to-codex.sh` bloquea escrituras de referencia en el scratchpad.

## Decisiones del usuario (2026-09-26, no reabrir)

1. RDD apagado global (`gentle-ai review mode disable`) — un solo carril de review.
2. ODD es el default en todo, incluida cada rama de una triangulación. El
   contrato ENTRE repos (API/shape/errores) sigue en OpenSpec canónico del backend.
3. El writer delegado de ODD es siempre Codex (`codex-run` / `codex-build`).
4. Modelo de trabajo (2026-09-26, sujeto al piloto): ODD para todo; OpenSpec
   queda SOLO como capa de contrato entre repos (`openspec/changes/<slug>/contract/`
   en el backend canónico de una triangulación); SDD completo solo por pedido
   explícito.

## Línea base medida (2026-09-26) — contra esto se juzga el piloto

- cocoa-core-backend: 42 cambios SDD, 22 archivados (52%); de 20 activos, 13
  sin tocar >10 días, 3 completos sin archivar, 5 sin tareas.
- Peso de planificación: SDD backend 150–5.300 líneas/cambio (mediana ≈1.500);
  ODD en el repo de gentle-ai 16–295 (mediana ≈85).
- Fronteras: `session-permission-refresh` tuvo spec+design+verify-report y aun
  así 4 fallas panel/app; lo frenaron `shared-doc-wire` + `assertPlainSerializable`.
- Valor demostrado de SDD entre repos: 21 carpetas `contract/`.
- gentle-ai upstream: 17 features ODD vs 0 SDD desde el 2026-09-16.

## Piloto (próximos 2 cambios reales)

1. Cambio de un solo repo con ODD puro.
2. Próxima triangulación: ODD por repo + `contract/` en OpenSpec.

Métricas: líneas de planificación, tiempo hasta el merge, documento cerrado
(sí/no), drift de contrato detectado antes del merge, bugs de frontera
post-deploy. Si ODD empeora cierre o fronteras frente a la línea base, se
revisa la decisión 4.

## Alcance

- `files/claude/bin/apply-agent-patches.sh` + tests.
- `files/claude/patches/skills/{sdd-archive,sdd-tasks}` rebasados a 3.7.
- `files/claude/CLAUDE.md`, `files/claude/patches/claude-md-codex-override.md`,
  `files/shared/runtime-budget.md`, `files/codex/AGENTS.md`.
- `verify.sh`, `files/claude/hooks/route-code-to-codex.sh` + tests.

Fuera de alcance: upgrade de Engram 1.20 → 2.2.1 (requiere cerrar las 5
sesiones con `engram mcp` 1.20 vivas; Engram 2 migra el SQLite).

## Tareas

- [x] T1 `apply-agent-patches.sh`: deduplicar tools de Engram tras el `sed`; test. Verificado con fixture 3.7.0 e idempotencia.
- [x] T2 Rebasar el overlay `sdd-tasks` al template 3.7 y actualizar `FRESH_SDD_TASKS_SHA`; eliminar el overlay intencionalmente borrado de `sdd-archive` y conservar su Archive Gate de agent.
- [x] T3 Instrucciones (CLAUDE.md, override, runtime-budget, AGENTS.md): ODD default, writer = Codex, triangulación ODD + contrato OpenSpec, `gentle-sdd-*`, RDD off.
- [x] T4 `verify.sh`: gentle-ai ≥ 3, review mode off, bloque ODD presente, sin tools duplicados; también valida `install --help --dry-run`.
- [x] T5 `route-code-to-codex.sh`: no bloquear el scratchpad de Claude tras `cd` literal; variables sin expandir siguen bloqueadas; test.
- [x] T6 Tests/verify y referencias de layout actualizadas para `gentle-sdd-*`; los slash commands de Claude ya están renombrados y se preservan los nombres `sdd-*` de agents/skills. Los meta-comandos `/sdd-new`, `/sdd-ff` y `/sdd-continue` de Codex permanecen intencionalmente así en 3.7.
- [x] T7 Instrucciones de la decisión 4: CLAUDE.md, AGENTS.md y skill
      triangulation-orchestrator dicen "ODD por repo + OpenSpec solo `contract/`".
      Después de que Codex cierre T1–T6 (un solo escritor).

- [x] T8 Reparación post-sync persistente en `apply-agent-patches.sh` (corre en SessionStart): skill-registry fuera de UserPromptSubmit, context7 stdio, `[agents]` sin `max_threads`/`max_depth`, `~/.codex/AGENTS.md` restaurado desde `~/.claude/patches/codex/AGENTS.md` (bootstrap lo instala). Checks de sobredelegación reemplazados por checks del contrato ODD.

## Criterios de aceptación

- `apply-agent-patches.sh --check` sin drift y sin AVISO sobre 3.7.
- Ningún agent con tools repetidos.
- `./verify.sh` 0 FAIL; suites de `tests/` y `hooks/tests` verdes.

## Evidencia

- Commits en `feat/gentle-ai-v3-odd` (apilada sobre `fix/evidence-bound-closure`): f095f45 (T1/T2), f2a0bc8 (T5), f818495 (T4), cd15fd5 (T3/T6/T7) y el commit de T8.
- `tests/agent_patches_test.sh` rc=0; `files/claude/hooks/tests/route-hook-tests.sh` rc=0 (48 casos); `apply-agent-patches.sh --check` rc=0 sin drift en la máquina.
- `gentle-ai sync` 3.7 reintrodujo 5 regresiones (verificado contra su snapshot `~/.gentle-ai/backups/20260926121127*`): context7 url, skill-registry por prompt, `[agents] max_threads=4/max_depth=2`, `~/.codex/AGENTS.md` reemplazado, línea OpenSpec ACTIVE DEFAULT. Reparadas en la máquina y cubiertas por T8.
- `verify.sh` previo a las reparaciones: 792 PASS / 42 WARN / 12 FAIL. Preexistentes (fallan también en la base): `conductor_runtime_parity` (codexBin de Conductor), paridad CLAUDE.md fuente↔instalado (~900 líneas de divergencia previa), plugin Engram de Codex ausente, config estricto con shim de cmux.

## Progreso / siguiente paso

Implementación cerrada e integrada (2026-09-29):

- Cadena #4–#39 mergeada a `main`; árbol `origin/main` == `c9075ace0ecac853342a1c34dc282fea5c76c41d`.
- `verify.sh` sobre la máquina reparada: 802 PASS / 42 WARN / 2 FAIL (preexistentes:
  plugin Engram de Codex ausente; paridad CLAUDE.md fuente↔instalado).
- Engram 1.20 → 2.2.1 (backup `~/.engram/backup-pre-v2-*`, 3.252 observaciones migradas).
- Worktree `gentle-ai-v3-odd` eliminado; checkout principal en `main`.

Siguiente: piloto ODD con los dos próximos cambios reales (sección Piloto).
Engram doctor (2026-09-29, decidido con delegación del usuario): el `mcp.json` de
VS Code se reparó (`{"servers":{}}`) y el registro MCP de antigravity-cli se
reapuntó con `engram setup antigravity-cli`. Los 3 hallazgos restantes
(`sync_target_closed_space`, `sync_mutation_required_fields`,
`invalid_session_identity`) solo afectan la replicación cloud, que no está
configurada (`engram cloud status`: not configured). Se dejan sin reparar para no
borrar registros del store sin beneficio. `engram mcp` 2.2.1 responde el handshake
con 19 tools.
