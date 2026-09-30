#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKFLOW="$ROOT/files/claude/workflows/codex-build.js"
SCENARIO=${1:-workflow}

if [[ "$SCENARIO" == apply ]]; then
  # 2026-09-03: el snapshot files/claude/{skills,agents} (que llevaba el contrato
  # `apply_backend: native|codex` del sdd-apply) fue retirado: bootstrap nunca lo
  # instalaba y gentle-ai regenera esos archivos. El routing a Codex vive hoy en
  # el hook route-code-to-codex.sh (opt-in) y en el parche "Code routing" de
  # files/claude/patches/agents. Solo queda verificable el límite del workflow.
  if grep -Eq 'tasks\.md.*\[x\]|apply-progress.*(write|update)' "$ROOT/files/claude/workflows/codex-build.js"; then
    printf 'workflow must not own OpenSpec progress\n' >&2
    exit 1
  fi
  grep -q 'Code routing' "$ROOT/files/claude/patches/agents/code-routing.md" \
    || { printf 'missing apply contract: code-routing patch\n' >&2; exit 1; }
  printf 'codex SDD apply contract fixtures: 2 passed (snapshot contract superseded by hook + patch)\n'
  exit 0
fi

if [[ "$SCENARIO" == docs ]]; then
  README="$ROOT/README.md"
  PRD="$ROOT/docs/PRD.md"
  require_doc() {
    local pattern=$1 file=$2 label=$3
    grep -Eiq -- "$pattern" "$file" || { printf 'missing docs contract: %s\n' "$label" >&2; exit 1; }
  }
  require_doc 'apply_backend.*native.*codex' "$README" 'explicit routing'
  require_doc 'Claude.*Conductor.*codex-build' "$README" 'Claude Conductor path'
  require_doc 'Codex.*direct.*Conductor' "$README" 'direct Codex path'
  require_doc 'Not logged in|/login.*pending|pending.*/login' "$README" 'authenticated Claude blocker'
  require_doc 'rollback|restore.*backup' "$README" 'rollback path'
  require_doc 'gentle-ai.sdd-execution-receipt/v1' "$PRD" 'receipt contract'
  require_doc '154 PASS.*1 WARN.*0 FAIL' "$PRD" 'recorded automated gate'
  require_doc '3\.3|authenticated Claude.*pending|pending.*Claude' "$PRD" 'pending acceptance item'
  require_doc '0\.144\.1.*strict|strict.*0\.144\.1' "$PRD" 'bundled strict startup'
  printf 'codex SDD documentation fixtures: 9 passed\n'
  exit 0
fi

[[ "$SCENARIO" == workflow ]] || {
  printf 'unknown scenario: %s\n' "$SCENARIO" >&2
  exit 2
}

node --input-type=module - "$WORKFLOW" <<'NODE'
import fs from 'node:fs'
import assert from 'node:assert/strict'

const source = fs.readFileSync(process.argv[2], 'utf8')
  .replace('export const meta =', 'const meta =')
const runWorkflow = new Function(
  'args', 'agent', 'pipeline', 'log',
  `return (async () => { ${source}\n })()`,
)

const sha = (char) => char.repeat(64)
const basePacket = () => ({
  schema: 'gentle-ai.sdd-execution-packet/v1',
  lineage_id: 'integrate-codex-sdd-executor/unit-1/generation-1',
  generation: 1,
  unit: {
    id: 'unit-1',
    requirements: ['Audited Receipt and Commit'],
    scenarios: ['Receipt names another tree'],
    criteria: ['one conventional commit', 'RED GREEN REFACTOR evidence'],
    constraints: ['workflow must not write openspec'],
  },
  repo: '/tmp/fake-codex-repo',
  git_cwd: '/tmp/fake-codex-repo',
  base_sha: sha('a'),
  base_tree: sha('b'),
  writer_head: sha('a'),
  artifact_identities: { spec: sha('c'), design: sha('d'), tasks: sha('e') },
  current_artifact_identities: { spec: sha('c'), design: sha('d'), tasks: sha('e') },
  allowed_paths: ['src/feature.js', 'tests/feature.test.js'],
  dirty_paths: [],
  strict_tdd: true,
  commands: {
    red: 'bash tests/feature.test.sh red',
    green: 'bash tests/feature.test.sh green',
    refactor: 'bash tests/feature.test.sh refactor',
    runtime: 'bash tests/feature.test.sh runtime',
  },
  payload_hash: sha('f'),
})

const pipeline = async (items, execute, audit) => Promise.all(items.map(async (item) => audit(await execute(item), item)))
const quiet = () => {}

async function rejected(mutator, pattern) {
  const packet = basePacket()
  mutator(packet)
  let calls = 0
  const result = await runWorkflow({ mode: 'sdd', packet }, async () => { calls++; return {} }, pipeline, quiet)
  assert.equal(result.status, 'rejected')
  assert.match(result.reason, pattern)
  assert.equal(calls, 0, 'invalid packet must be rejected before agent execution')
}

await rejected((p) => { p.repo = '../escape' }, /repo/i)
await rejected((p) => { p.repo = '/tmp/fake-codex-repo/../wrong-repo' }, /repo/i)
await rejected((p) => { p.git_cwd = '/tmp/another-repo' }, /repo|git.*cwd/i)
await rejected((p) => { p.writer_head = sha('9') }, /base|head/i)
await rejected((p) => { p.allowed_paths = ['../escape'] }, /allowed/i)
await rejected((p) => { p.dirty_paths = ['src/feature.js'] }, /dirty|overlap/i)
await rejected((p) => { p.artifact_identities.spec = sha('0') }, /identit/i)
await rejected((p) => { p.unit.criteria = [] }, /criteria|spec-gap/i)

const packet = basePacket()
let phase = 0
const accepted = await runWorkflow({ mode: 'sdd', packet }, async (_prompt, options) => {
  phase++
  if (options.phase === 'Execute') {
    return {
      status: 'candidate', lineage_id: packet.lineage_id, base_sha: packet.base_sha,
      commit_sha: sha('1'), parent_sha: packet.base_sha, tree_sha: sha('2'), diff_hash: sha('3'),
      touched_paths: packet.allowed_paths, conventional_subject: 'feat(workflow): add transaction',
      worktree: '/tmp/fake-codex-repo/.claude/worktrees/sdd-unit-1',
      tdd: [
        { phase: 'RED', command: packet.commands.red, exit_code: 1, revision: packet.base_sha },
        { phase: 'GREEN', command: packet.commands.green, exit_code: 0, revision: sha('1') },
        { phase: 'REFACTOR', command: packet.commands.refactor, exit_code: 0, revision: sha('1') },
      ],
      issues: [],
    }
  }
  return {
    verdict: 'accepted', lineage_id: packet.lineage_id, packet_hash: packet.payload_hash,
    base_sha: packet.base_sha, commit_sha: sha('1'), parent_sha: packet.base_sha,
    tree_sha: sha('2'), diff_hash: sha('3'), touched_paths: packet.allowed_paths,
    conventional_subject: 'feat(workflow): add transaction', audit_issues: [],
    receipt_hash: sha('4'),
  }
}, pipeline, quiet)
assert.equal(phase, 2)
assert.equal(accepted.status, 'accepted')
assert.equal(accepted.receipt.schema, 'gentle-ai.sdd-execution-receipt/v1')
assert.equal(accepted.receipt.commit_sha, sha('1'))

for (const mutation of ['tampered receipt', 'wrong tree', 'path leakage']) {
  let calls = 0
  const candidate = {
    status: 'candidate', lineage_id: packet.lineage_id, base_sha: packet.base_sha,
    commit_sha: sha('1'), parent_sha: packet.base_sha, tree_sha: sha('2'), diff_hash: sha('3'),
    touched_paths: packet.allowed_paths, conventional_subject: 'feat(workflow): add transaction',
    worktree: '/tmp/fake-codex-repo/.claude/worktrees/sdd-unit-1', issues: [],
    tdd: [
      { phase: 'RED', command: packet.commands.red, exit_code: 1, revision: packet.base_sha },
      { phase: 'GREEN', command: packet.commands.green, exit_code: 0, revision: sha('1') },
      { phase: 'REFACTOR', command: packet.commands.refactor, exit_code: 0, revision: sha('1') },
    ],
  }
  const result = await runWorkflow({ mode: 'sdd', packet }, async (_prompt, options) => {
    calls++
    if (options.phase === 'Execute') return candidate
    const audit = {
      verdict: 'accepted', lineage_id: packet.lineage_id, packet_hash: packet.payload_hash,
      base_sha: packet.base_sha, commit_sha: candidate.commit_sha, parent_sha: packet.base_sha,
      tree_sha: candidate.tree_sha, diff_hash: candidate.diff_hash,
      touched_paths: candidate.touched_paths, conventional_subject: candidate.conventional_subject,
      audit_issues: [], receipt_hash: sha('4'),
    }
    if (mutation === 'tampered receipt') audit.receipt_hash = 'bad'
    if (mutation === 'wrong tree') audit.tree_sha = sha('8')
    if (mutation === 'path leakage') audit.touched_paths = ['outside.txt']
    return audit
  }, pipeline, quiet)
  assert.equal(result.status, 'rejected', mutation)
  assert.equal(calls, 2, mutation)
}

for (const mutation of ['pre-staged leakage', 'commit -a leakage', 'empty commit', 'changed identities', 'tampered receipt', 'wrong tree']) {
  let calls = 0
  const result = await runWorkflow({ mode: 'sdd', packet: basePacket() }, async (_prompt, options) => {
    calls++
    if (options.phase === 'Execute') return { status: 'rejected', issues: [mutation] }
    throw new Error('audit must not run for rejected execution')
  }, pipeline, quiet)
  assert.equal(result.status, 'rejected', mutation)
  assert.equal(calls, 1, mutation)
}

let specGapCalls = 0
const specGap = await runWorkflow({ mode: 'sdd', packet: basePacket() }, async () => {
  specGapCalls++
  return { status: 'spec-gap', commit_sha: '', issues: ['criteria conflict'] }
}, pipeline, quiet)
assert.equal(specGap.status, 'spec-gap')
assert.equal(specGapCalls, 1)
assert.equal(specGap.receipt.commit_sha, null)

const standalone = await runWorkflow({ repo: '/tmp/repo', tasks: [
  { id: 'one', description: 'first' }, { id: 'two', description: 'second' },
] }, async (_prompt, options) => options.phase === 'Execute'
  ? 'diff'
  : { verified: true, approved: true, summary: 'ok', issues: [] }, pipeline, quiet)
assert.equal(standalone.verdict, 'todo-aprobado')
assert.equal(standalone.approved.length, 2)

console.log('codex SDD workflow fixtures: 20 passed')
NODE
