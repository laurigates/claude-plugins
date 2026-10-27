// Run issue-triage.workflow.js against a stub runtime and assert on its plan.
// Usage: node run-issue-triage.mjs <issue-triage.workflow.js>
// Each scenario scripts agent() returns by label prefix (assess:<batch>, slice).
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))

async function run(argsIn, script) {
  const calls = []
  const prompts = {}
  const agent = async (prompt, opts) => {
    calls.push(opts.label)
    prompts[opts.label] = prompt
    const [kind, unit] = opts.label.split(':')
    const r = script(kind, unit, prompt)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, async () => [], () => {}, () => {}, argsIn)
  return { result, calls, prompts }
}

// One assessment row; `files` drives the overlap serialisation.
const row = (number, cls = 'autonomous', files = [`src/f${number}.js`], extra = {}) => ({
  number, title: `issue ${number}`, class: cls, reason: 'r', still_true_at_head: 'true', evidence: 'e',
  size: 'S', files, scope: cls === 'autonomous' ? `scope ${number}` : '', doable_part: '', blockers: '',
  overlap_prs: [], ...extra,
})
const assessed = (key, rows) => ({ batch: key, issues: rows })
const slice = (name, issues, files = [], depends_on = [], brief = `brief ${name}`) => ({ name, issues, files, depends_on, brief })

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}
// Every input issue is in exactly one slice or in deferred — the partition invariant.
const placements = (r) => {
  const seen = new Map()
  for (const s of r.result.slices ?? []) for (const n of s.issues) seen.set(n, (seen.get(n) ?? 0) + 1)
  for (const d of r.result.deferred ?? []) seen.set(d.issue, (seen.get(d.issue) ?? 0) + 1)
  return seen
}
const partitioned = (r, input) => {
  const seen = placements(r)
  return input.every((n) => seen.get(n) === 1) && seen.size === input.length
}
const reasonOf = (r, n) => (r.result.deferred ?? []).find((d) => d.issue === n)?.reason
const waveOf = (r, id) => (r.result.waves ?? []).findIndex((w) => w.some((u) => u.id === id))

const BATCHES = { batches: [{ key: 'a', issues: [1, 2, 3] }, { key: 'b', issues: [4, 5] }] }

// 1. Non-autonomous classes are deferred under their class; the rest are sliced; partition holds.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess'
      ? u === 'a' ? assessed('a', [row(1), row(2, 'needs_human'), row(3, 'already_done')])
                  : assessed('b', [row(4), row(5, 'needs_env')])
      : { slices: [slice('one', [1]), slice('four', [4])], deferred: [] })
  check('partition: every issue in exactly one slice or deferred', partitioned(r, [1, 2, 3, 4, 5]), r.result)
  check('class wins: needs_human/already_done/needs_env deferred under their class',
    reasonOf(r, 2) === 'needs_human' && reasonOf(r, 3) === 'already_done' && reasonOf(r, 5) === 'needs_env', r.result.deferred)
  check('one assess agent per batch + one slice agent', r.calls.filter((c) => c.startsWith('assess:')).length === 2 && r.calls.filter((c) => c === 'slice').length === 1, r.calls)
}
// 2. Assessment that invents an issue / omits one: invented discarded, omitted → unassessed.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess'
      ? u === 'a' ? assessed('a', [row(1), row(2), row(99)]) : assessed('b', [row(4), row(5)])
      : { slices: [slice('s1', [1, 2]), slice('s4', [4]), slice('s5', [5])], deferred: [] })
  check('omitted by assessor → deferred unassessed', reasonOf(r, 3) === 'unassessed', r.result.deferred)
  check('invented by assessor → discarded everywhere', !placements(r).has(99) && !r.result.assessments.some((a) => a.number === 99), r.result)
  check('partition holds after assessor errors', partitioned(r, [1, 2, 3, 4, 5]), r.result)
}
// 3. A dead assess agent defers its whole batch as unassessed, and Slice still runs on the rest.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess' ? (u === 'a' ? null : assessed('b', [row(4), row(5)]))
      : { slices: [slice('s', [4, 5])], deferred: [] })
  check('dead batch → its issues unassessed', [1, 2, 3].every((n) => reasonOf(r, n) === 'unassessed'), r.result.deferred)
  check('dead batch → slice still runs', r.calls.includes('slice') && r.result.slices.length === 1, r.calls)
}
// 4. Slicer errors: non-autonomous in a slice removed, invented discarded, duplicate keeps first,
//    omitted autonomous recovered as a standalone slice.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess'
      ? u === 'a' ? assessed('a', [row(1), row(2), row(3, 'stale')]) : assessed('b', [row(4), row(5)])
      : { slices: [slice('x', [1, 3, 77]), slice('y', [1, 2])], deferred: [] })
  const sx = r.result.slices.find((s) => s.name === 'x')
  const sy = r.result.slices.find((s) => s.name === 'y')
  check('stale issue removed from slice, deferred as stale', !sx.issues.includes(3) && reasonOf(r, 3) === 'stale', r.result)
  check('invented 77 discarded from slice', !placements(r).has(77), sx)
  check('duplicate keeps first placement', sx.issues.includes(1) && !sy.issues.includes(1), r.result.slices)
  check('omitted autonomous 4 and 5 recovered standalone',
    r.result.slices.some((s) => s.issues.length === 1 && s.issues[0] === 4) && r.result.slices.some((s) => s.issues.length === 1 && s.issues[0] === 5), r.result.slices)
  check('partition holds after slicer errors', partitioned(r, [1, 2, 3, 4, 5]), r.result)
}
// 5. Cross-batch file overlap the slicer missed: the two slices are serialised into different waves.
//    This is the defect of per-batch slicing — each batch's slicer cannot see the other batch's files.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess'
      ? u === 'a' ? assessed('a', [row(1, 'autonomous', ['src/shared.js']), row(2), row(3)])
                  : assessed('b', [row(4, 'autonomous', ['src/shared.js']), row(5)])
      : { slices: [slice('alpha', [1]), slice('beta', [4]), slice('gamma', [2, 3, 5])], deferred: [] })
  const a = r.result.slices.find((s) => s.name === 'alpha')
  const b = r.result.slices.find((s) => s.name === 'beta')
  check('overlapping slices land in different waves', waveOf(r, a.id) !== waveOf(r, b.id) && waveOf(r, a.id) >= 0 && waveOf(r, b.id) >= 0, r.result.waves)
  check('serialisation adds a depends_on edge', b.depends_on.includes(a.id), b)
  check('assessment files are unioned into slice files', a.files.includes('src/shared.js'), a)
  // No wave holds two units that own the same file.
  const clash = (r.result.waves ?? []).some((w) => {
    const owned = w.flatMap((u) => u.owns)
    return new Set(owned).size !== owned.length
  })
  check('no wave has two units owning one file', !clash, r.result.waves)
}
// 6. A dependency cycle is deferred, never dispatched; an unknown dependency is dropped.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess'
      ? u === 'a' ? assessed('a', [row(1), row(2), row(3)]) : assessed('b', [row(4), row(5)])
      : { slices: [slice('p', [1], [], ['q']), slice('q', [2], [], ['p']), slice('r', [3, 4, 5], [], ['nope'])], deferred: [] })
  check('cycle members deferred as dependency-cycle', reasonOf(r, 1) === 'dependency-cycle' && reasonOf(r, 2) === 'dependency-cycle', r.result.deferred)
  const rr = r.result.slices.find((s) => s.name === 'r')
  check('unknown dependency dropped', rr && rr.depends_on.length === 0 && waveOf(r, rr.id) === 0, rr)
  check('partition holds with a cycle', partitioned(r, [1, 2, 3, 4, 5]), r.result)
}
// 7. Waves are implement-verify units, chunked at its MAX_UNITS of 5.
{
  const batches = { batches: [{ key: 'a', issues: [1, 2, 3, 4] }, { key: 'b', issues: [5, 6, 7] }] }
  const r = await run(batches, (k, u) =>
    k === 'assess'
      ? u === 'a' ? assessed('a', [1, 2, 3, 4].map((n) => row(n))) : assessed('b', [5, 6, 7].map((n) => row(n)))
      : { slices: [1, 2, 3, 4, 5, 6, 7].map((n) => slice(`Slice ${n}!`, [n])), deferred: [] })
  const u = r.result.waves[0][0]
  check('unit shape: id, issues, branch fix/<id>, brief, owns', u.id === 'slice-1' && u.branch === 'fix/slice-1' && u.issues[0] === 1 && u.brief && Array.isArray(u.owns), u)
  check('7 independent slices → waves of 5 and 2', r.result.waves.length === 2 && r.result.waves[0].length === 5 && r.result.waves[1].length === 2, r.result.waves.map((w) => w.length))
}
// 8. Below the floor and empty input abort before any agent runs.
{
  const one = await run({ batches: [{ key: 'a', issues: [1, 2] }] }, () => assessed('a', [row(1), row(2)]))
  check('one batch aborts below floor, zero agents', one.result.reason === 'below-floor' && one.calls.length === 0, one.result)
  const none = await run({ batches: [] }, () => undefined)
  check('no issues aborts, zero agents', none.result.reason === 'no-issues' && none.calls.length === 0, none.result)
}
// 9. Zero or one autonomous issue: no slicing agent; one autonomous becomes a standalone slice.
{
  const zero = await run(BATCHES, (k, u) =>
    u === 'a' ? assessed('a', [row(1, 'needs_human'), row(2, 'too_large'), row(3, 'stale')])
              : assessed('b', [row(4, 'decision_needed'), row(5, 'needs_env')]))
  check('zero autonomous → no slice agent, all deferred', !zero.calls.includes('slice') && zero.result.deferred.length === 5 && zero.result.slices.length === 0, zero.result)
  const oneA = await run(BATCHES, (k, u) =>
    u === 'a' ? assessed('a', [row(1), row(2, 'needs_human'), row(3, 'stale')])
              : assessed('b', [row(4, 'decision_needed'), row(5, 'needs_env')]))
  check('one autonomous → standalone slice, no slice agent', !oneA.calls.includes('slice') && oneA.result.slices.length === 1 && oneA.result.waves[0][0].issues[0] === 1, oneA.result)
}
// 10. A dead slicer is an abort that still hands back the assessments — never an unpartitioned plan.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess' ? (u === 'a' ? assessed('a', [row(1), row(2), row(3)]) : assessed('b', [row(4), row(5)])) : null)
  check('dead slicer → abort slicing-failed with assessments', r.result.abort === true && r.result.reason === 'slicing-failed' && r.result.assessments.length === 5, r.result)
}
// 11. Stringified args, bare-array batches, an issue repeated across batches assessed once,
//     and git-triage.sh progress keys reach the right assessor's brief.
{
  const progress = 'ISSUE_COUNT=5\nISSUE_3_MERGED_PRS=o/r#9*\nISSUE_3_CLOSE_CANDIDATE=true\nISSUE_4_MERGED_PRS=none\n'
  const r = await run(JSON.stringify({ batches: [[1, 2, 3], [3, 4, 5]], progress }), (k, u) =>
    k === 'assess'
      ? u === 'batch-1' ? assessed('batch-1', [row(1), row(2), row(3, 'already_done')]) : assessed('batch-2', [row(4), row(5)])
      : { slices: [slice('s', [1, 2]), slice('t', [4, 5])], deferred: [] })
  check('bare-array batches get batch-<i> keys', r.calls.includes('assess:batch-1') && r.calls.includes('assess:batch-2'), r.calls)
  check('issue in two batches assessed once (first batch)', !/\b3\b/.test(r.prompts['assess:batch-2'].split('Issues to assess:')[1].split('\n')[0]), r.prompts['assess:batch-2'].split('\n').find((l) => l.startsWith('Issues to assess')))
  check('progress keys reach the assessor brief', r.prompts['assess:batch-1'].includes('ISSUE_3_MERGED_PRS=o/r#9*') && r.prompts['assess:batch-1'].includes('ISSUE_3_CLOSE_CANDIDATE=true'), r.prompts['assess:batch-1'])
  check('partition holds with stringified args', partitioned(r, [1, 2, 3, 4, 5]), r.result)
}
// 12. Slicer-deferred issues keep the slicer's closed reason.
{
  const r = await run(BATCHES, (k, u) =>
    k === 'assess' ? (u === 'a' ? assessed('a', [row(1), row(2), row(3)]) : assessed('b', [row(4), row(5)]))
      : { slices: [slice('s', [1, 2, 3])], deferred: [{ issue: 4, reason: 'overlaps-open-pr', detail: '#12' }, { issue: 5, reason: 'blocked', detail: '#6' }] })
  check('slicer deferrals kept', reasonOf(r, 4) === 'overlaps-open-pr' && reasonOf(r, 5) === 'blocked', r.result.deferred)
}

process.exit(failed ? 1 : 0)
