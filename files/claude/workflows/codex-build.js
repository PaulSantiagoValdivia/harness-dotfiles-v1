export const meta = {
  name: 'codex-build',
  description: 'Codex implementa tareas bien acotadas en worktrees aislados; Claude audita cada resultado antes de que decidas mergear',
  whenToUse: 'Tenés una lista de tareas ya enumerable, homogénea e independiente (típicamente la salida de sdd-tasks, o escrita a mano) y querés que Codex las escriba mientras Claude vigila cada una',
  phases: [
    { title: 'Execute', detail: 'Codex implementa cada tarea en su propio worktree' },
    { title: 'Audit', detail: 'Claude revisa cada resultado contra lo pedido' },
  ],
}

// Es el inverso de dual-review: ahí Codex audita lo que Claude escribió.
// Acá Codex escribe y Claude audita. Mismo principio del artículo (paso 12):
// tareas mecánicas y bien acotadas al ejecutor barato, el juicio fino se queda
// arriba. Este workflow NUNCA mergea nada — eso es una decisión humana.

const A = (() => {
  if (!args) return {}
  if (typeof args === 'string') {
    try { return JSON.parse(args) } catch { return {} }
  }
  return args
})()

const REPO = A.repo
// tasks: [{ id: 'slug-corto', description: '...', model: 'sol'|'astra' }]
// model es opcional (default 'astra' — ver DEFAULT_MODEL abajo): viene del tag
// `[codex: sol|astra]` que sdd-tasks ya deja en tasks.md, elegido con spec+design
// cargados. Sin esto, TODO el lote corría en el default de config.toml (astra),
// tarea mecánica o no (regla del usuario 2026-09-10, ahorro de créditos).
const TASKS = Array.isArray(A.tasks) ? A.tasks : []
// codex-run no alias-ea nombres cortos: el slug real (models_cache.json) es
// gpt-5.6-sol / gpt-6-astra. `-m sol` es un modelo inválido y Codex lo rechaza.
const MODEL_SLUG = { sol: 'gpt-5.6-sol', astra: 'gpt-6-astra' }
const DEFAULT_MODEL = 'astra' // ante la duda, no trivial: rehacer con astra cuesta más que el sol ahorrado
const modelSlugFor = (task) => MODEL_SLUG[task.model] || MODEL_SLUG[DEFAULT_MODEL]
// codex-run: binario real sin el shim de cmux + stdin cerrado + timeout duro
// (incidente 2026-08-30: codex colgado 13 min sin techo). Override por args.
const CODEX_BIN = A.codexBin || `${process.env.HOME}/.claude/bin/codex-run`
// Mismo tier para el agente que orquesta y para el -c model_reasoning_effort de
// Codex: 'medium' alcanza para una tarea bien acotada, no hace falta 'high'.
// NUNCA 'ultra': eso dispara el multi-agente propio de Codex, opaco desde acá.
const EXECUTE_EFFORT = A.executeEffort || 'medium'
const MAX_PARALLEL = Math.min(2, Math.max(1, Number(A.maxParallel) || 2))

const SHA256 = /^[a-f0-9]{64}$/
const CONVENTIONAL_COMMIT = /^(build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test)(\([a-z0-9._-]+\))?!?: .+/
const RECEIPT_SCHEMA = 'gentle-ai.sdd-execution-receipt/v1'

const rejectSdd = (reason, issues = [reason]) => ({
  schema: RECEIPT_SCHEMA,
  status: 'rejected',
  reason,
  issues,
  receipt: null,
})

const validRelativePath = (value) =>
  typeof value === 'string' &&
  value.length > 0 &&
  !value.startsWith('/') &&
  !value.split('/').includes('..') &&
  !value.includes('\\')

const sameIdentityMap = (expected, current) => {
  if (!expected || !current) return false
  const keys = Object.keys(expected).sort()
  if (keys.length === 0 || keys.join('\0') !== Object.keys(current).sort().join('\0')) return false
  return keys.every((key) => SHA256.test(expected[key]) && expected[key] === current[key])
}

const validateSddPacket = (packet) => {
  if (!packet || packet.schema !== 'gentle-ai.sdd-execution-packet/v1') return 'invalid packet schema'
  if (typeof packet.repo !== 'string' || !packet.repo.startsWith('/') || packet.repo.split('/').includes('..')) return 'invalid canonical repo'
  if (packet.git_cwd !== packet.repo) return 'git cwd does not match packet repo'
  if (!SHA256.test(packet.base_sha || '') || !SHA256.test(packet.base_tree || '')) return 'invalid base identity'
  if (packet.writer_head !== packet.base_sha) return 'writer HEAD does not match base'
  if (!SHA256.test(packet.payload_hash || '')) return 'invalid packet hash'
  if (!sameIdentityMap(packet.artifact_identities, packet.current_artifact_identities)) return 'artifact identities changed'
  if (!packet.unit || typeof packet.unit.id !== 'string' || !Array.isArray(packet.unit.criteria) || packet.unit.criteria.length === 0) return 'spec-gap: missing unit criteria'
  if (!Array.isArray(packet.allowed_paths) || packet.allowed_paths.length === 0 || !packet.allowed_paths.every(validRelativePath)) return 'invalid allowed paths'
  if (!Array.isArray(packet.dirty_paths)) return 'invalid dirty path inventory'
  const overlap = packet.dirty_paths.filter((path) => packet.allowed_paths.includes(path))
  if (overlap.length > 0) return `dirty overlap: ${overlap.join(', ')}`
  if (packet.strict_tdd !== true) return 'SDD Codex backend requires Strict TDD'
  for (const phase of ['red', 'green', 'refactor']) {
    if (!packet.commands || typeof packet.commands[phase] !== 'string' || !packet.commands[phase]) return `missing ${phase} command`
  }
  return null
}

const SDD_EXECUTION = {
  type: 'object',
  properties: {
    status: { type: 'string', enum: ['candidate', 'rejected', 'spec-gap'] },
    lineage_id: { type: 'string' }, base_sha: { type: 'string' }, commit_sha: { type: 'string' },
    parent_sha: { type: 'string' }, tree_sha: { type: 'string' }, diff_hash: { type: 'string' },
    touched_paths: { type: 'array', items: { type: 'string' } }, conventional_subject: { type: 'string' },
    worktree: { type: 'string' }, tdd: { type: 'array', items: { type: 'object' } },
    issues: { type: 'array', items: { type: 'string' } },
  },
  required: ['status', 'issues'],
}

const SDD_AUDIT = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['accepted', 'rejected'] }, lineage_id: { type: 'string' },
    packet_hash: { type: 'string' }, base_sha: { type: 'string' }, commit_sha: { type: 'string' },
    parent_sha: { type: 'string' }, tree_sha: { type: 'string' }, diff_hash: { type: 'string' },
    touched_paths: { type: 'array', items: { type: 'string' } }, conventional_subject: { type: 'string' },
    audit_issues: { type: 'array', items: { type: 'string' } }, receipt_hash: { type: 'string' },
  },
  required: ['verdict', 'audit_issues'],
}

if (A.mode === 'sdd') {
  const packet = A.packet
  const packetError = validateSddPacket(packet)
  if (packetError) return rejectSdd(packetError)

  const worktreePath = `${packet.repo}/.claude/worktrees/sdd-${packet.unit.id}`
  const execution = await agent(
    `Execute exactly one immutable SDD work unit through Codex. You orchestrate; Codex writes.\n\n` +
      `Packet: ${JSON.stringify(packet)}\n\n` +
      `FAIL CLOSED. First verify: pwd and git -C "${packet.repo}" rev-parse --show-toplevel equal the packet repo; ` +
      `HEAD equals ${packet.base_sha}; tree equals ${packet.base_tree}; every artifact SHA-256 equals the packet identity; ` +
      `the index is empty; and no dirty path overlaps allowed_paths. Never stash, reset, clean, remove an existing ` +
      `worktree, resolve conflicts, use commit -a, or write OpenSpec. On any mismatch return rejected without a commit.\n` +
      `Create a new isolated worktree at "${worktreePath}" from exact base ${packet.base_sha}. Reject if that path ` +
      `or branch already exists. Ask "${CODEX_BIN}" --ask-for-approval never exec --sandbox danger-full-access -c model_reasoning_effort=${EXECUTE_EFFORT} ` +
      `to implement only ${packet.unit.id}. Run RED before production changes, then GREEN and REFACTOR. ` +
      `Stage only explicit allowed paths (${packet.allowed_paths.join(', ')}), require a non-empty diff, and create exactly ` +
      `one conventional commit whose parent is the base. Reject pre-staged files, commit -a leakage, empty commits, ` +
      `changed identities, paths outside scope, or more than one commit. If criteria are missing or contradictory, ` +
      `return spec-gap with no commit. Return Git identities, commands, exit codes, and issues; do not integrate anything.`,
    { label: `sdd-execute:${packet.unit.id}`, phase: 'Execute', schema: SDD_EXECUTION, effort: EXECUTE_EFFORT },
  )

  if (!execution || execution.status === 'rejected') return rejectSdd('Codex execution rejected', execution && execution.issues)
  if (execution.status === 'spec-gap') {
    return {
      schema: RECEIPT_SCHEMA, status: 'spec-gap', reason: 'Codex reported a specification gap',
      issues: execution.issues || [],
      receipt: { schema: RECEIPT_SCHEMA, lineage_id: packet.lineage_id, packet_hash: packet.payload_hash, commit_sha: null },
    }
  }

  const candidateIssues = []
  if (execution.lineage_id !== packet.lineage_id) candidateIssues.push('lineage mismatch')
  if (execution.base_sha !== packet.base_sha || execution.parent_sha !== packet.base_sha) candidateIssues.push('base or parent mismatch')
  for (const field of ['commit_sha', 'tree_sha', 'diff_hash']) if (!SHA256.test(execution[field] || '')) candidateIssues.push(`invalid ${field}`)
  if (!CONVENTIONAL_COMMIT.test(execution.conventional_subject || '')) candidateIssues.push('non-conventional commit subject')
  if (!Array.isArray(execution.touched_paths) || execution.touched_paths.some((path) => !packet.allowed_paths.includes(path))) candidateIssues.push('touched path outside allowed paths')
  const phases = Array.isArray(execution.tdd) ? execution.tdd.map((entry) => entry.phase) : []
  if (!['RED', 'GREEN', 'REFACTOR'].every((phase) => phases.includes(phase))) candidateIssues.push('incomplete RED-GREEN-REFACTOR evidence')
  if (candidateIssues.length > 0) return rejectSdd('candidate validation failed', candidateIssues)

  const audit = await agent(
    `Audit the real candidate in "${execution.worktree}" against this immutable packet: ${JSON.stringify(packet)}\n\n` +
      `Do not trust the executor narrative. Run git -C with exactly the packet repo/worktree; reject any repository ` +
      `mismatch. Recompute packet/artifact/commit/tree/diff SHA-256 identities, verify commit^ equals the base, exactly ` +
      `one non-empty conventional commit exists, the index had no prior content, touched paths are exactly allowed, ` +
      `and RED failed before production changes while GREEN and REFACTOR passed on the recorded revisions. Reject ` +
      `commit -a or pre-staged leakage, empty commits, changed identities, tampering, or a tree mismatch. Compute the ` +
      `canonical receipt hash only after all fields are final. Audit only: never integrate, mutate OpenSpec, or repair.`,
    { label: `sdd-audit:${packet.unit.id}`, phase: 'Audit', schema: SDD_AUDIT, effort: 'medium' },
  )

  const auditIssues = []
  if (!audit || audit.verdict !== 'accepted') auditIssues.push(...((audit && audit.audit_issues) || ['audit rejected']))
  for (const field of ['lineage_id', 'base_sha', 'commit_sha', 'parent_sha', 'tree_sha', 'diff_hash', 'conventional_subject']) {
    const expected = field === 'lineage_id' ? packet.lineage_id : field === 'base_sha' ? packet.base_sha : execution[field]
    if (!audit || audit[field] !== expected) auditIssues.push(`${field} mismatch`)
  }
  if (!audit || audit.packet_hash !== packet.payload_hash) auditIssues.push('packet hash mismatch')
  if (!audit || !SHA256.test(audit.receipt_hash || '')) auditIssues.push('invalid receipt hash')
  if (!audit || JSON.stringify(audit.touched_paths) !== JSON.stringify(execution.touched_paths)) auditIssues.push('touched paths mismatch')
  if (auditIssues.length > 0) return rejectSdd('audit validation failed', auditIssues)

  return {
    schema: RECEIPT_SCHEMA,
    status: 'accepted',
    reason: null,
    issues: [],
    receipt: {
      schema: RECEIPT_SCHEMA, lineage_id: packet.lineage_id, generation: packet.generation,
      unit_id: packet.unit.id, packet_hash: packet.payload_hash, base_sha: packet.base_sha,
      commit_sha: audit.commit_sha, parent_sha: audit.parent_sha, tree_sha: audit.tree_sha,
      diff_hash: audit.diff_hash, touched_paths: audit.touched_paths,
      conventional_subject: audit.conventional_subject, worktree: execution.worktree,
      tdd: execution.tdd, audit_verdict: audit.verdict, audit_issues: audit.audit_issues,
      receipt_hash: audit.receipt_hash,
    },
  }
}

if (!REPO || TASKS.length === 0) {
  return {
    verdict: 'sin-tareas',
    results: [],
    note: 'Faltan repo o tasks. Pasá args: { repo, tasks: [{id, description}, ...] }.',
  }
}

// Piso de tamaño (el mismo que ya está en CLAUDE.md): con 1 sola tarea esto es
// más caro que pedírselo directo a un Agent. El workflow existe para el fan-out.
if (TASKS.length < 2) {
  log('Con 1 sola tarea, el Agent tool directo alcanza — este workflow es para fan-out. Sigo igual.')
}

log(`${TASKS.length} tarea(s) para Codex en ${REPO}; máximo ${MAX_PARALLEL} simultáneas.`)

// `verified` es independiente de `approved`, a propósito: separa "¿pude confirmar
// esto yo mismo en disco?" de "¿el cambio está bien?". Un LLM presionado a opinar
// tiende a aprobar igual aunque no haya podido mirar nada real — pasó en una
// corrida real de este workflow (el workspace de Conductor se archivó a mitad de
// carrera, el worktree desapareció, y el auditor igual devolvió approved:true
// razonando sobre el relato en texto del agente ejecutor en vez de sobre el diff).
// La regla dura vive en el CÓDIGO más abajo (approved = verified && audit.approved),
// no solo en el prompt: un prompt es una sugerencia, un `&&` no.
const AUDIT = {
  type: 'object',
  properties: {
    verified: {
      type: 'boolean',
      description:
        'true SOLO si corriste git diff vos mismo en el worktree y lo leíste. false si el worktree ' +
        'ya no existe, el comando falló, o de cualquier forma no pudiste confirmarlo de forma ' +
        'independiente — en ese caso NO importa qué tan convincente sea el relato del otro agente.',
    },
    approved: { type: 'boolean' },
    summary: { type: 'string', description: 'qué hizo Codex, en 1-2 oraciones' },
    issues: { type: 'array', items: { type: 'string' }, description: 'problemas concretos, vacío si no hay' },
  },
  required: ['verified', 'approved', 'summary', 'issues'],
}

// pipeline, no parallel: cada tarea fluye por Execute→Audit sin esperar a las
// demás. Una tarea lenta en Execute no frena el Audit de otra ya terminada.
const results = []
for (let offset = 0; offset < TASKS.length; offset += MAX_PARALLEL) {
  const batch = TASKS.slice(offset, offset + MAX_PARALLEL)
  results.push(...await pipeline(
    batch,
    (task) => {
    // Construido en código, no parseado del texto del agente: el audit necesita
    // esta ruta exacta para poder verificar de forma independiente, sin depender
    // de que la haya transcripto bien en su respuesta.
    const worktreePath = `${REPO}/.claude/worktrees/codex-${task.id}`
    const modelSlug = modelSlugFor(task)
    return agent(
      `Implementá esta tarea usando CODEX vía Bash — vos NO escribís el código, orquestás.\n\n` +
        `Tarea: ${task.description}\n\n` +
        `Pasos exactos:\n` +
        `1. cd "${REPO}" && git worktree add -b codex-${task.id} "${worktreePath}" HEAD\n` +
        `   If the branch or existing worktree already exists, STOP and report the collision. ` +
        `Preserve all existing work; never remove, reset, clean or recreate it.\n` +
        `2. cd al worktree recién creado.\n` +
        `3. Corré: "${CODEX_BIN}" exec --sandbox workspace-write -m ${modelSlug} ` +
        `-c model_reasoning_effort=${EXECUTE_EFFORT} ` +
        `"${task.description} -- Implementá el cambio directamente en los archivos del repo. ` +
        `No preguntes, no expliques, no pidas confirmación: escribí el código."\n` +
        `4. Corré \`git diff --stat\` y \`git diff\` DENTRO del worktree para capturar qué se hizo.\n\n` +
        `Devolvé: el diff completo (o "SIN CAMBIOS" si Codex no tocó nada).`,
      { label: `execute:${task.id}`, phase: 'Execute', effort: EXECUTE_EFFORT },
    ).then((text) => ({ text, worktreePath }))
    },
    (executeResult, task) =>
      agent(
      `Auditá esta implementación de Codex contra lo que se pidió. Sé estricto.\n\n` +
        `Tarea pedida: ${task.description}\n\n` +
        `Worktree donde DEBERÍA estar el cambio: ${executeResult.worktreePath}\n\n` +
        `Relato del agente que ejecutó (esto es lo que ÉL DICE que pasó, no es verificación — ` +
        `no lo repitas como si fuera un hecho confirmado):\n${executeResult.text}\n\n` +
        `PASO OBLIGATORIO antes de opinar: corré \`git -C "${executeResult.worktreePath}" status\` y ` +
        `\`git -C "${executeResult.worktreePath}" diff\` vos mismo.\n` +
        `- Si el comando falla (worktree removido, archivado, path inexistente, etc.) → ` +
        `verified: false, approved: false. En 'issues' explicá que la verificación no fue posible ` +
        `y por qué — NUNCA apruebes basándote solo en el relato del otro agente.\n` +
        `- Si corriste el diff real y lo leíste → verified: true, y ahí sí evaluá con ESE diff:\n` +
        `  · ¿Hace lo que se pidió, completo?\n` +
        `  · ¿Es sintácticamente válido / compilaría?\n` +
        `  · ¿Toca archivos fuera del alcance de la tarea?\n` +
        `  · ¿Introduce algo obviamente roto (estado no limpiado, guard faltante, etc.)?\n\n` +
        `'approved: true' SOLO si verified es true Y lo aplicarías tal cual, sin cambios. ` +
        `Ante la duda, false y explicá qué falta en 'issues'.`,
      { label: `audit:${task.id}`, phase: 'Audit', schema: AUDIT, effort: 'medium' },
      ),
  ))
}

// Refuerzo en código, no solo en el prompt: si el modelo devolvió verified:false
// pero approved:true de todas formas (que es exactamente el bug que motivó esto),
// el && lo pisa. Un audit no verificado NUNCA cuenta como aprobado.
const withTasks = results.map((audit, i) => ({
  task: TASKS[i],
  audit: audit && { ...audit, approved: !!(audit.verified && audit.approved) },
}))
const approved = withTasks.filter((r) => r.audit && r.audit.approved)
const needsWork = withTasks.filter((r) => r.audit && !r.audit.approved)

log(`${approved.length}/${TASKS.length} aprobadas por la auditoría. ${needsWork.length} necesitan trabajo manual.`)

return {
  verdict: needsWork.length === 0 ? 'todo-aprobado' : 'revision-necesaria',
  approved,
  needsWork,
  note:
    'Cada tarea vive en su propio worktree bajo .claude/worktrees/codex-<id>. ' +
    'NADA se mergeó — esa decisión es tuya. Antes de abrir PR con lo aprobado, ' +
    'corré dual-review sobre la rama final: esta auditoría es un pase único por ' +
    'tarea, no el chequeo adversarial completo.',
}
