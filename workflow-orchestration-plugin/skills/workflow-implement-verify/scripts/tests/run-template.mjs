// Run a workflow template against a stub runtime and assert on its result.
// Usage: node run-template.mjs <template.workflow.js>
// Each scenario scripts agent() returns by label prefix and checks the rows.
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)

const pipeline = async (items, ...stages) =>
  Promise.all(
    items.map(async (item, i) => {
      let r = item
      for (const [k, s] of stages.entries()) {
        try {
          r = await s(k === 0 ? item : r, item, i)
        } catch {
          return null
        }
      }
      return r
    }),
  )
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))

async function run(argsIn, script) {
  const calls = []
  const agent = async (_prompt, opts) => {
    calls.push(opts.label)
    const kind = opts.label.split(':')[0]
    const unit = opts.label.split(':')[1]
    const r = script(kind, unit)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, argsIn)
  return { result, calls }
}

const fix = (unit, extra = {}) => ({
  unit, branch: `fix/${unit}`, status: 'done', head_sha: 'abc1234', commits: ['abc1234 fix'], items: [], gates: [], ...extra,
})
const verdict = (unit, v) => ({
  unit, verdict: v, gates_reproduced: [], claims_not_reproduced: [], mutant_replays: [],
  new_defects: v === 'fix-needed' ? [{ severity: 'major', where: 'a.js:1', problem: 'p', fix: 'f' }] : [], summary: '',
})

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}
const statuses = (r) => Object.fromEntries((r.result.rows ?? []).map((x) => [x.unit, x.status]))

const isImpl = basename(file).startsWith('implement-verify')
const first = isImpl ? 'implement' : 'fix'
const units = (ids) =>
  isImpl ? { units: ids.map((id) => ({ id, branch: `fix/${id}` })) }
         : { units: ids.map((id) => ({ id, branch: `fix/${id}`, findings: [{ text: 'x' }] })) }

// 1. A dead verifier is UNVERIFIED, never a pass, and is never landed.
{
  const r = await run(units(['a', 'b']), (k, u) =>
    k === first ? fix(u) : k === 'verify' ? (u === 'a' ? null : verdict(u, 'pass')) : k === 'finalise' ? { prs: [], pushed: [] } : undefined)
  check('null verdict → UNVERIFIED', statuses(r).a === 'UNVERIFIED', statuses(r))
  check('null verdict not in finalisePlan', !r.result.finalisePlan.some((p) => p.unit === 'a'), r.result.finalisePlan)
  check('pass verdict → PASS and landed', statuses(r).b === 'PASS' && r.calls.filter((c) => c === 'finalise').length === 1, r.calls)
}
// 2. fix-needed → one repair + re-verify; a dead re-verifier is UNVERIFIED.
{
  const r = await run(units(['a', 'b']), (k, u) =>
    k === first ? fix(u) : k === 'verify' ? verdict(u, 'fix-needed') : k === 'repair' ? fix(u, { head_sha: 'def5678' })
      : k === 'reverify' ? (u === 'a' ? verdict(u, 'pass') : null) : k === 'finalise' ? { prs: [], pushed: [] } : undefined)
  check('repaired + pass → REPAIRED_PASS', statuses(r).a === 'REPAIRED_PASS', statuses(r))
  check('dead re-verifier → UNVERIFIED', statuses(r).b === 'UNVERIFIED', statuses(r))
  check('exactly one repair per unit', r.calls.filter((c) => c.startsWith('repair:')).length === 2, r.calls)
  check('landed head is the repaired tip', r.result.finalisePlan[0]?.head_sha === 'def5678', r.result.finalisePlan)
}
// 3. reject never triggers a repair.
{
  const r = await run(units(['a', 'b']), (k, u) => (k === first ? fix(u) : k === 'verify' ? verdict(u, 'reject') : undefined))
  check('reject → REJECTED, no repair', statuses(r).a === 'REJECTED' && !r.calls.some((c) => c.startsWith('repair')), r.calls)
}
// 4. repairRounds 0 leaves fix-needed as FIX_NEEDED.
{
  const r = await run({ ...units(['a', 'b']), repairRounds: 0 }, (k, u) => (k === first ? fix(u) : k === 'verify' ? verdict(u, 'fix-needed') : undefined))
  check('repairRounds 0 → FIX_NEEDED', statuses(r).a === 'FIX_NEEDED' && !r.calls.some((c) => c.startsWith('repair')), r.calls)
}
// 5. A dead first-stage agent is FAILED and gets no verifier.
{
  const r = await run(units(['a', 'b']), (k, u) => (k === first ? (u === 'a' ? null : fix(u)) : k === 'verify' ? verdict(u, 'pass') : { prs: [], pushed: [] }))
  check('dead author → FAILED, unverified', statuses(r).a === 'FAILED' && !r.calls.includes('verify:a'), r.calls)
}
// 6. Over the cap: abort before any agent runs.
{
  const r = await run(units(['a', 'b', 'c', 'd', 'e', 'f']), () => fix('x'))
  check('over-cap aborts with zero agents', r.result.abort === true && r.result.reason === 'over-cap' && r.calls.length === 0, r)
}
// 7. land local: no finalise agent.
{
  const r = await run({ ...units(['a', 'b']), land: 'local' }, (k, u) => (k === first ? fix(u) : verdict(u, 'pass')))
  check('land local → no finalise', !r.calls.includes('finalise') && r.result.finalisePlan.length === 2, r.calls)
}
// 8. A dead repairer keeps the verifier's answer: FIX_NEEDED, not UNVERIFIED.
{
  const r = await run(units(['a', 'b']), (k, u) =>
    k === first ? fix(u) : k === 'verify' ? verdict(u, 'fix-needed') : k === 'repair' ? null : undefined)
  check('dead repairer → FIX_NEEDED', statuses(r).a === 'FIX_NEEDED' && !r.calls.some((c) => c.startsWith('reverify')), statuses(r))
}
// 9. A repairer that rejects every finding (no-change) and then passes re-verify is landed.
{
  const r = await run(units(['a', 'b']), (k, u) =>
    k === first ? fix(u) : k === 'verify' ? verdict(u, 'fix-needed') : k === 'repair' ? fix(u, { status: 'no-change' })
      : k === 'reverify' ? verdict(u, 'pass') : { prs: [], pushed: [] })
  check('repair no-change + pass → REPAIRED_PASS', statuses(r).a === 'REPAIRED_PASS' && r.result.finalisePlan.length === 2, statuses(r))
}
// 10. The author's PR text and issue links survive a repair that returns empty ones.
{
  const r = await run({ ...units(['a', 'b']), land: 'local' }, (k, u) =>
    k === first ? fix(u, { pr_title: 'fix(a): t', pr_body: 'body', fixes_issues: [42], commits: ['abc1234 fix'] })
      : k === 'verify' ? verdict(u, 'fix-needed')
      : k === 'repair' ? fix(u, { head_sha: 'def5678', pr_title: '', pr_body: '', fixes_issues: [], commits: ['def5678 repair'] })
      : verdict(u, 'pass'))
  const row = r.result.rows.find((x) => x.unit === 'a')
  check('repair keeps pr_title/body and Fixes', row.fix.pr_title === 'fix(a): t' && row.fix.pr_body === 'body' && row.fix.fixes_issues.includes(42), row.fix)
  check('repair accumulates commits', row.fix.commits.length === 2 && row.fix.head_sha === 'def5678', row.fix)
}
// 11. Exactly at the cap: every unit gets a row (a narrower slice would drop one silently).
{
  const ids = ['a', 'b', 'c', 'd', 'e']
  const r = await run({ ...units(ids), land: 'local' }, (k, u) => (k === first ? fix(u) : verdict(u, 'pass')))
  check('5 units → 5 PASS rows', ids.every((id) => statuses(r)[id] === 'PASS') && r.result.rows.length === 5, statuses(r))
}
// 12. Only PASS/REPAIRED_PASS reach the landing plan.
{
  const r = await run(units(['a', 'b']), (k, u) => (k === first ? fix(u) : verdict(u, u === 'a' ? 'reject' : 'pass')))
  check('REJECTED not landed', !r.result.finalisePlan.some((p) => p.unit === 'a') && r.result.finalisePlan.length === 1, r.result.finalisePlan)
}
// 13. Two units on one branch abort before any agent runs.
{
  const base = units(['a', 'b'])
  base.units[1].branch = base.units[0].branch
  const r = await run(base, () => fix('x'))
  check('shared branch aborts', r.result.reason === 'shared-branch' && r.calls.length === 0, r.result)
}
if (isImpl) {
  // 8. no-change is its own outcome and skips the verifier.
  const r = await run(units(['a', 'b']), (k, u) => (k === 'implement' ? fix(u, { status: 'no-change' }) : verdict(u, 'pass')))
  check('no-change → NO_CHANGE, unverified', statuses(r).a === 'NO_CHANGE' && !r.calls.some((c) => c.startsWith('verify')), r.calls)
  check('NO_CHANGE not landed', r.result.finalisePlan.length === 0 && !r.calls.includes('finalise'), r.result.finalisePlan)
  // 9. A single unit is below the floor.
  const one = await run(units(['a']), () => fix('a'))
  check('one unit aborts below floor', one.result.reason === 'below-floor' && one.calls.length === 0, one)
} else {
  // 8. A unit without findings aborts the run.
  const r = await run({ units: [{ id: 'a', branch: 'fix/a', findings: [] }] }, () => fix('a'))
  check('unit without findings aborts', r.result.reason === 'incomplete-units' && r.calls.length === 0, r)
}

process.exit(failed ? 1 : 0)
