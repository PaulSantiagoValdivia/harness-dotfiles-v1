# Consolidador de memoria de archivos (`~/.claude/memory`)

## Objetivo

Mantener la memoria de archivos chica y vigente con un proceso en background
(idea tomada de Instinct: el agente no mantiene su memoria, la mantiene un
proceso aparte), SIN romper nada de lo que hoy funciona. Engram no se toca.

## Problema (medido 2026-09-29)

- `MEMORY.md`: 155 líneas, 18.433 bytes (~5k tokens) inyectados en CADA sesión.
- 157 archivos; 7 entradas del índice ya dicen RESUELTO/cerrada/archivada.
- Duplicados semánticos (ej. "Codex escribe, Claude audita" vs "Claude organiza,
  Codex codea") que nadie fusiona: las memorias se escriben a mano y solo crecen.
- `~/.claude/memory` NO está en git: hoy ningún cambio es reversible.

## Restricción del usuario (2026-09-29, no reabrir)

"No debe fallar nada; la idea es mejorar, no romper lo que ya tenemos."
Traducido a invariantes duros:

1. Git local antes que cualquier escritura automática. Nunca push (la memoria
   es personal: `docs/PRD.md:119`).
2. Nunca se borra un archivo ni se edita el CUERPO de una memoria.
3. Lo que sale del índice va a `ARCHIVE.md` (no se carga, pero se encuentra):
   reversible y buscable.
4. Todo cambio pasa por `memory-lint`; si falla, se descarta entero.
5. El proceso nocturno solo PROPONE (rama `proposal/<fecha>`). Aplicar es
   manual hasta que el usuario decida otra cosa con datos del piloto.
6. Aplicar hace compare-and-swap: si `main` cambió desde la propuesta
   (una sesión viva escribió memoria), no aplica.
7. El `claude -p` headless no recibe tools y no dispara hooks del usuario.

## Hallazgos de diseño

- `claude --bare` saltea hooks pero exige `ANTHROPIC_API_KEY` (no lee OAuth):
  NO sirve con la suscripción. Hay que probar otro mecanismo para aislar hooks
  (`--settings` / `--setting-sources`) y demostrarlo con un test.
- Sin precedente de `claude -p` en el repo; `codex-run` es el único wrapper headless.
- Convenciones: `cp` (no symlink), plist con `__HOME__` + guard
  `[ "$HOME" = "$REAL_HOME" ]` antes de `launchctl load`, tests bash en
  `tests/*_test.sh` registrados en `tests/ci_verify.sh`, checks en `verify.sh`.
- VERIFICADO (T0, binario Claude Code 2.1.284, función `TMt`): `MEMORY.md` se
  trunca a 200 líneas (`GM=200`) o 25.000 bytes (`n3=25000`), con aviso
  "N of M lines were cut". Hoy 155 líneas / 18.433 bytes: quedan ~45 líneas.
  Sin consolidar, las memorias NUEVAS (van al final) dejan de cargarse.
- VERIFICADO (T0, canario): `claude -p --setting-sources "" --tools ""` no
  dispara hooks (0 canarios; control con `project` = 2) y autentica por OAuth.
  PERO igual carga el CLAUDE.md global (~20k tokens de cache): el prompt del
  consolidador debe pedir SOLO JSON y el aplicador ignorar todo lo que no valide.
- macOS no trae `timeout`: el wrapper necesita watchdog propio (patrón `codex-run`).

## Tareas

- [x] T0 Verificar límite de carga de `MEMORY.md` y mecanismo para aislar hooks
      en `claude -p` con OAuth. Ruta: inline (lectura/doc).
- [x] T1 `memory-snapshot`: `git init` idempotente en `~/.claude/memory`, commit
      si hay cambios, nunca push, nunca borra. Se engancha antes de toda
      propuesta. Script + test + bootstrap + verify + ci. Ruta: Codex `sol`.
- [x] T2 `memory-lint` (read-only, determinista): índice → archivos existentes,
      archivos → indexados en `MEMORY.md` o `ARCHIVE.md`, frontmatter
      `name/description/metadata.type`. `[[links]]` colgantes = aviso, no error
      (son válidos por diseño). Test con fixtures. Ruta: Codex `sol`.
- [x] T3 `memory-consolidate propose`: snapshot → `claude -p` sin tools ni hooks
      devuelve JSON con operaciones cerradas (`archive_index_entry`,
      `add_aliases`, `reword_index_line`, `merge_suggestion` solo informativa)
      → aplicador determinista en rama `proposal/<fecha>` → lint → si falla,
      borra la rama. Ruta: Codex `astra`.
- [x] T4 `memory-consolidate review|apply|discard` con compare-and-swap sobre
      `main`. Ruta: Codex `sol`.
- [x] T5 launchd nocturno (`StartCalendarInterval`, solo `propose`), plist en
      `files/shared/launchd/`, guard de HOME, checks en verify. Ruta: Codex `sol`.
- [ ] T6 Piloto: 7 propuestas revisadas a mano. Auto-apply = decisión del usuario.

## Aceptación

- Con el consolidador instalado y sin aplicar nada, ninguna sesión cambia de
  comportamiento (`MEMORY.md` byte-idéntico).
- `verify.sh` y `tests/ci_verify.sh` en verde.
- Revertir cualquier propuesta aplicada = `git -C ~/.claude/memory revert <sha>`.

## TDD

Off (no hay config de TDD en el repo); checks funcionales: tests bash por
script + `./verify.sh` + `tests/ci_verify.sh`.

## Progreso

- 2026-09-29: T5 implementado sin marcar checkbox: job launchd 03:30 sólo `propose --if-idle`, guarda global por HOME de prueba, prompt en español con aliases activos y cobertura de instalación/verificación; cambios sin commit por sandbox `.git` read-only.

- 2026-09-29: auditoría independiente corregida: aislamiento MCP/Git, aliases YAML seguros, índices LF-only, cleanup ante `BaseException`, procesos descendientes, lock pre-snapshot y apply con baseline + rollback `--keep`; 51 fixtures del consolidador OK, sin commit por sandbox `.git` read-only.

- 2026-09-29: T3/T4 implementadas inline: `memory-consolidate` propose/review/apply/discard/status, schema cerrado, worktree aislado, baseline, CAS y rollback; 37 fixtures OK con snapshot/lint reales y Claude stub, registro bootstrap/verify/CI, sin launchd ni uso de memoria real; cambios sin commit por restricción explícita.

- 2026-09-29: exploración hecha, documento creado.
- 2026-09-29: T0 cerrado (límite 200/25k confirmado; aislamiento de hooks probado). Próximo: T1.
- 2026-09-29: T1 cerrado. Commit `b175c44` (Codex sol escribió; su sandbox no podía
  commitear, commit hecho tras auditar el diff). Evidencia: `tests/memory_snapshot_test.sh`
  9 casos PASS; `tests/ci_verify.sh` rc=0; instalado en `~/.local/bin` y corrido sobre la
  memoria real: commit `b08cac8` (157 archivos), shasum antes/después idéntico, 0 `.md`
  dentro de `.git`, sin remote, 2da corrida no-op. `./verify.sh` rc=1 por 2 FAIL
  PREEXISTENTES y ajenos (plugin Engram de Codex no `enabled=false` en
  `~/.codex/config.toml`; CLAUDE.md instalado ≠ source+override); el check nuevo PASS.
  Próximo: T2.
- 2026-09-29: T2 cerrado. Commit `5401319`. Codex sol (1ª corrida colgada esperando un
  sub-agente: dejó solo el script; 2ª corrida completó test+registro+fix). Auditoría:
  fix de baseline por clave estable `(code, file, target)` (antes comparaba mensajes con
  número de línea → falso positivo al mover entradas). Evidencia: `tests/memory_lint_test.py`
  12 tests OK (todos los códigos cubiertos); `tests/ci_verify.sh` rc=0; memoria real:
  0 errores, 13 DANGLING_LINK, 1 UNREFERENCED_FILE (`cocoa-button-loading-desenfoca.md`
  no está en el índice = hoy no se carga). Instalado en `~/.local/bin`. Próximo: T3+T4.
- Hallazgo: `claude --json-schema` existe → salida estructurada validada en origen.
- 2026-09-29: T3+T4 cerrados. Codex astra implementó; auditoría independiente (sonnet)
  halló 4 majors (sin `--strict-mcp-config`; rollback `reset --hard` podía pisar escrituras
  vivas → `--keep` + lock antes del snapshot; `apply` sin `--baseline`; aliases no seguros
  para YAML) y 6 minors; UNA corrección acotada (Codex sol) los resolvió con test cada uno.
  Evidencia (re-corrida por Claude): consolidate 51 tests OK, lint 12 OK, snapshot 9 OK,
  `tests/ci_verify.sh` rc=0; memoria real intacta en `main`, 0 ramas `proposal/*`.
  Próximo: smoke real `memory-consolidate propose` (solo propone) + revisión con el usuario; luego T5.
- 2026-09-29: smoke real `memory-consolidate propose` OK (rc=0, ~20 s). Memoria viva
  byte-idéntica y en `main`. Rama `proposal/2026-09-29`: archiva 4 entradas cerradas
  (branding points card, descuentos L1/L2, guard Firebase, seed organigrama), 0 aliases,
  0 reword; 4 sugerencias de fusión (reservas ×4, Codex/Claude escritor ×5,
  diagnóstico ×3, organigrama ×3). MEMORY.md 155→151 líneas. Lint 0 errores.
  Observaciones: el modelo fue muy conservador (no propuso aliases); el resumen sale en
  inglés. Pendiente: decisión del usuario apply/discard; luego T5.
- 2026-09-29: usuario aprobó; `memory-consolidate apply 2026-09-29` rc=0 → commit vivo
  `d34dd0e` (revertir: `git -C ~/.claude/memory revert d34dd0e`). MEMORY.md 151 líneas /
  17.980 bytes; ARCHIVE.md creado con 4 entradas; `memory-lint` 0 errores; rama borrada.
  Próximo: T5 (launchd, solo propose; ajustar prompt: resumen en español y aliases más
  activos) y T6 piloto. Luego commitear odd/tasks/pm-agent.md en rama propia.
- 2026-09-29: T5 cerrado. Commit cd54090 (plist `com.cocoa.memory-consolidate`, 03:30,
  `propose --if-idle`; prompt en español + aliases activos). Auditado por Claude: 55 tests OK,
  `tests/ci_verify.sh` rc=0, `plutil -lint` OK. Instalado y cargado en launchd real
  (`launchctl print` ok); PATH de launchd resuelve claude/memory-snapshot/memory-lint/python3.
  Próximo: T6 piloto (7 propuestas nocturnas revisadas a mano con `memory-consolidate review`).
