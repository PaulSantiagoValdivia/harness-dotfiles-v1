export const meta = {
  name: 'dual-review',
  description: 'Revisa un diff en diamante: fan-out por lentes con Claude, contra-lente independiente con Codex, verificación adversarial y síntesis',
  whenToUse: 'Antes de abrir un PR, o cuando querés dos motores distintos juzgando el mismo cambio sin contaminarse entre sí',
  phases: [
    { title: 'Scope', detail: 'leer el diff y acotar el alcance' },
    { title: 'Review', detail: 'un agente por lente, en paralelo' },
    { title: 'CrossCheck', detail: 'Codex revisa el mismo diff, ciego a lo que encontró Claude' },
    { title: 'Verify', detail: 'escépticos independientes intentan refutar cada hallazgo' },
    { title: 'Synthesize', detail: 'merge final de lo que sobrevivió' },
  ],
}

// --- Configuración de nodos -------------------------------------------------
// args opcional: { codexBin, base }
// Path estable de brew, NO el de Conductor: ese lo gestiona otra app y puede
// moverse sin avisar. /usr/local/bin es la primera entrada de /etc/paths.
// args puede llegar como objeto O como string JSON — el invocador se equivoca
// fácil y el síntoma es silencioso: args.repo queda undefined, todo cae a los
// defaults, y el grafo revisa el directorio equivocado sin quejarse. Normalizar.
const A = (() => {
  if (!args) return {}
  if (typeof args === 'string') {
    try { return JSON.parse(args) } catch { return {} }
  }
  return args
})()

// codex-run: sin el shim de cmux, stdin por archivo, timeout duro (incidente
// 2026-08-30: dos codex colgados; ademas el hook route-code-to-codex ahora
// BLOQUEA codex directo, este workflow se romperia en runtime sin esto).
const CODEX_BIN = A.codexBin || `${process.env.HOME}/.claude/bin/codex-run`

// El grafo NO asume que corre dentro del repo. Conductor trabaja en worktrees
// separados, y el cwd de la sesión puede no ser un repo en absoluto.
const REPO = A.repo || '.'
// Lo que se le pasa a `git diff`. Ejemplos: 'HEAD' (working tree),
// 'origin/master...HEAD' (rama), '9bb8473^..9bb8473' (un commit).
const SPEC = A.spec || 'HEAD'
const DIFF = `git -C "${REPO}" diff ${SPEC}`

log(`Objetivo: ${REPO} · spec: ${SPEC}`)

// Paso 03 del artículo: cada nodo tiene contrato. Estos son los esquemas.
const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          file: { type: 'string' },
          line: { type: 'number' },
          severity: { type: 'string', enum: ['critical', 'major', 'minor'] },
          claim: { type: 'string', description: 'el defecto en una oración' },
          failure: { type: 'string', description: 'input concreto -> resultado incorrecto' },
        },
        required: ['file', 'claim', 'failure', 'severity'],
      },
    },
  },
  required: ['findings'],
}

const VERDICT = {
  type: 'object',
  properties: {
    refuted: { type: 'boolean' },
    reason: { type: 'string' },
  },
  required: ['refuted', 'reason'],
}

// --- Cost cap (paso 12 + 13) -------------------------------------------------
// El costo real del grafo es Verify: 3 escépticos POR HALLAZGO, sin techo.
// Con 10 hallazgos deduplicados eso es 30 agentes ahí solo — medido en corridas
// reales: 36 y 18 agentes totales (2M y 856k tokens) para 10 y 4 hallazgos.
// Dos palancas, no una:
//   1. Tier de esfuerzo por severidad: un hallazgo minor no necesita el mismo
//      escrutinio que uno critical. 3 votos para critical/major, 1 para minor.
//   2. Techo duro de hallazgos que entran a Verify. Los que exceden el techo
//      NO se descartan en silencio (paso 13) — vuelven marcados `unverified`
//      en el resultado, y se loggea cuántos y por qué, para que el usuario
//      decida si sube el techo en vez de enterarse por un número que no cuadra.
const MAX_VERIFY = A.maxFindings ?? 4
const VOTES_BY_SEVERITY = { critical: 2, major: 2, minor: 1 }
const SEVERITY_RANK = { critical: 3, major: 2, minor: 1 }
// Cuota compartida: el workflow conserva todos los lentes/votos, pero nunca
// mantiene más de dos requests de modelo activas. Valores mayores se recortan.
const MAX_PARALLEL = Math.min(2, Math.max(1, Number(A.maxParallel) || 2))
const runBatched = async (thunks) => {
  const out = []
  for (let i = 0; i < thunks.length; i += MAX_PARALLEL) {
    out.push(...await parallel(thunks.slice(i, i + MAX_PARALLEL)))
  }
  return out
}

// Paso 01: las lentes son nodos independientes. No hay arista entre ellas,
// porque ninguna consume la salida de otra. Por eso van en paralelo.
const LENSES = [
  { key: 'correctness', prompt: 'lógica incorrecta, off-by-one, casos borde no cubiertos, estado mutado sin querer' },
  { key: 'security', prompt: 'validación de input faltante, secretos filtrados, authz ausente, inyección' },
  { key: 'regression', prompt: 'contratos rotos hacia consumidores existentes, cambios de firma, side effects nuevos' },
]

// --- Scope ------------------------------------------------------------------
phase('Scope')
const scope = await agent(
  `Ejecutá \`${DIFF} --stat\` y luego \`${DIFF}\`. Devolvé un resumen del cambio: ` +
    `archivos tocados, qué hace el cambio, y qué NO toca. Sé breve y factual.\n\n` +
    `IMPORTANTE: si el diff está vacío, o si TODO lo que cambió son archivos ` +
    `autogenerados (lockfiles, .plist de Pods, caches, registries con header ` +
    `"Auto-generated"), decilo EXPLÍCITAMENTE al principio de tu respuesta con ` +
    `la frase "SIN CONTENIDO REVISABLE". No hay valor en revisar artefactos generados.`,
  { label: 'scope', effort: 'low' },
)

// Paso 08: router. Si no hay nada que revisar, el grafo no se abre.
// Gastar 4 lentes para confirmar lo obvio es exactamente lo que NO queremos.
if (/SIN CONTENIDO REVISABLE/i.test(scope)) {
  log('Sin contenido revisable — el grafo no se abre.')
  return { verdict: 'sin-contenido', confirmed: [], note: scope }
}
log(`Alcance acotado. ${LENSES.length} lentes de Claude + 1 de Codex, máximo ${MAX_PARALLEL} simultáneos.`)

// --- Review + CrossCheck (fan-out, paso 05) --------------------------------
// Los cuatro nodos arrancan a la vez. Codex va ciego a propósito: si lee lo que
// encontró Claude, deja de ser una perspectiva independiente y se vuelve un eco.
//
// Tier de esfuerzo (paso 12): sin `effort` explícito, un nodo hereda el de la
// sesión — hoy CLAUDE_EFFORT=high. Este fan-out es de tamaño FIJO (4, siempre,
// tenga o no hallazgos el diff), a diferencia de Verify que escala con lo que
// aparece. Dejarlo en 'high' por omisión es pagar el tier más caro en el único
// nodo que corre completo en TODA invocación. 'medium' alcanza: es lectura +
// pattern-matching sobre un diff acotado, no el juicio de síntesis final.
const REVIEW_EFFORT = A.reviewEffort || 'medium'

const reviewThunks = LENSES.map((lens) => () =>
  agent(
    `Sos revisor de código con UNA sola lente: ${lens.key}.\n` +
      `Buscá exclusivamente: ${lens.prompt}.\n\n` +
      `Contexto del cambio:\n${scope}\n\n` +
      `Corré \`${DIFF}\` y revisá SOLO lo que cambió. ` +
      `Los archivos fuente viven bajo "${REPO}". ` +
      `Reportá únicamente defectos con un modo de falla concreto. ` +
      `Si no encontrás nada real, devolvé findings vacío — no inventes ruido.`,
    { label: `lens:${lens.key}`, phase: 'Review', schema: FINDINGS, effort: REVIEW_EFFORT },
  ),
)

const codexThunk = () =>
  agent(
    `Usá el Bash tool para pedirle a Codex una revisión independiente del diff.\n\n` +
      `Comando (el diff viaja por CODEX_RUN_STDIN — un archivo con EOF garantizado; ` +
      `NUNCA lo pipees directo: codex-run cierra stdin por default):\n` +
      // -c model_reasoning_effort=medium fijado a propósito: Codex 0.145+ tiene
      // su PROPIO modo multi-agente (feature "multi_agent", stable/on), que se
      // dispara con effort "ultra" — fan-out interno de Codex, invisible para
      // este grafo. Sin pin, un default futuro en "ultra" podría hacer que este
      // único nodo abra su propio abanico de subagentes sin que Claude se entere.
      `  cd "${REPO}" && ${DIFF} > /tmp/dual-review-diff.txt && CODEX_RUN_STDIN=/tmp/dual-review-diff.txt "${CODEX_BIN}" --ask-for-approval never exec --skip-git-repo-check --sandbox danger-full-access -c model_reasoning_effort=medium "Revisá este diff y listá SOLO defectos reales. ` +
      `Para cada uno: archivo, severidad (critical|major|minor), el defecto en una oración, ` +
      `y un caso de falla concreto (input -> resultado incorrecto). Si no hay defectos, decí 'sin hallazgos'."\n\n` +
      `Si el binario de Codex no existe o el comando falla, devolvé findings vacío ` +
      `y NO inventes hallazgos. Traducí la salida de Codex al schema pedido, sin agregar nada tuyo.`,
    { label: 'lens:codex', phase: 'CrossCheck', schema: FINDINGS, effort: REVIEW_EFFORT },
  )

const raw = await runBatched([...reviewThunks, codexThunk])

// --- Fan-in (paso 06): acá SÍ se justifica la barrera ----------------------
// Necesito el conjunto completo para deduplicar entre motores: Claude y Codex
// suelen encontrar el mismo bug con palabras distintas. Eso es cross-item,
// y por eso no puede vivir dentro de un pipeline.
// Paso 04: la arista es código. Deduplicar no gasta un solo token de modelo.
const all = raw.filter(Boolean).flatMap((r) => r.findings || [])

// La clave de dedup NO puede incluir texto libre: cada agente redacta distinto
// y ninguna clave coincide jamás. Tampoco la ruta cruda: unos devuelven absoluta
// y otros relativa. Se normaliza a basename:line y se FUSIONAN los claims, para
// no perder el ángulo de cada lente. Dos lentes viendo el mismo file:line casi
// siempre miran el mismo defecto — fusionarlos refuerza la señal en vez de
// pagar 3 escépticos por cada copia.
const bucket = new Map()
for (const f of all) {
  const key = `${(f.file || '').split('/').pop()}:${f.line ?? '?'}`
  const prev = bucket.get(key)
  if (!prev) {
    bucket.set(key, { ...f, claims: [f.claim], failures: [f.failure] })
    continue
  }
  prev.claims.push(f.claim)
  prev.failures.push(f.failure)
  // Se conserva la severidad más alta de todas las lentes que lo vieron.
  const rank = { critical: 3, major: 2, minor: 1 }
  if ((rank[f.severity] || 0) > (rank[prev.severity] || 0)) prev.severity = f.severity
}
const deduped = [...bucket.values()].map((f) => ({
  ...f,
  claim: f.claims.join(' | '),
  failure: f.failures[0],
  lenses: f.claims.length,
}))

log(`${all.length} hallazgos crudos -> ${deduped.length} tras deduplicar.`)

if (deduped.length === 0) {
  return { verdict: 'limpio', confirmed: [], note: 'Ningún motor encontró defectos reales.' }
}

// Techo: severidad primero, después cuántas lentes lo vieron (más corroboración
// independiente = prioridad). Lo que no entra queda `unverified`, NUNCA se pierde.
const ranked = [...deduped].sort((a, b) => {
  const bySeverity = (SEVERITY_RANK[b.severity] || 0) - (SEVERITY_RANK[a.severity] || 0)
  return bySeverity !== 0 ? bySeverity : (b.lenses || 1) - (a.lenses || 1)
})
const toVerify = ranked.slice(0, MAX_VERIFY)
const skipped = ranked.slice(MAX_VERIFY)
if (skipped.length > 0) {
  log(
    `Techo de ${MAX_VERIFY} alcanzado: ${skipped.length} hallazgo(s) quedan ` +
      `SIN verificar (no descartados): ${skipped.map((f) => `${f.file}:${f.line ?? '?'}`).join(', ')}`,
  )
}

// --- Verify (paso 09): el verificador vive SOBRE la arista -----------------
// Escépticos prompteados para MATAR el hallazgo, no para confirmarlo.
// Votos tierizados por severidad (paso 12): minor no paga el mismo precio que
// critical/major. Sobrevive solo si la mayoría no logra refutarlo.
phase('Verify')
const judged = []
for (const f of toVerify) {
  const nVotes = VOTES_BY_SEVERITY[f.severity] ?? 2
  const votes = await runBatched(
    Array.from({ length: nVotes }, (_, i) => () =>
      agent(
        `Intentá REFUTAR este hallazgo de code review. Tu trabajo es matarlo, no validarlo.\n\n` +
          `Archivo: ${f.file}${f.line ? `:${f.line}` : ''}\n` +
          `Afirmación: ${f.claim}\n` +
          `Modo de falla alegado: ${f.failure}\n\n` +
          `Leé el código real. Si el modo de falla no se reproduce, si hay una guarda ` +
          `que lo previene, o si el path es inalcanzable -> refuted: true. ` +
          `Ante la duda, refuted: true. Intento #${i + 1}.`,
        { label: `refute:${f.file}#${i + 1}`, phase: 'Verify', schema: VERDICT, effort: 'low' },
      ),
    ),
  )
  const v = votes.filter(Boolean)
  const survivors = v.filter((x) => !x.refuted).length
  const need = Math.ceil((v.length || 1) / 2)
  judged.push({ ...f, survived: survivors >= need, votes: v.length, survivors })
}

const confirmed = judged.filter(Boolean).filter((f) => f.survived)
log(`${confirmed.length}/${toVerify.length} hallazgos sobrevivieron a la refutación.`)

const unverified = skipped.map((f) => ({ ...f, survived: null }))

if (confirmed.length === 0 && unverified.length === 0) {
  return { verdict: 'limpio', confirmed: [], note: 'Todos los hallazgos fueron refutados.' }
}

// --- Synthesize -------------------------------------------------------------
phase('Synthesize')
const report = await agent(
  `Escribí el reporte final de review.\n\n` +
    `CONFIRMADOS (sobrevivieron a escépticos independientes, tratalos como reales):\n` +
    `${JSON.stringify(confirmed, null, 2)}\n\n` +
    `SIN VERIFICAR (techo de ${MAX_VERIFY} alcanzado, no se refutaron ni confirmaron — ` +
    `decilo así de claro, no los mezcles con los confirmados):\n` +
    `${JSON.stringify(unverified, null, 2)}\n\n` +
    `Ordená por severidad dentro de cada grupo. Para cada uno: qué está mal, por qué ` +
    `importa, y el arreglo concreto. Sin relleno, sin felicitaciones.`,
  { label: 'synthesize', effort: 'high' },
)

return { verdict: confirmed.length > 0 ? 'hallazgos' : 'sin-verificar', confirmed, unverified, report }
