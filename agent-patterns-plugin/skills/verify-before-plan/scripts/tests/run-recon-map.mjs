// Run recon-map.workflow.js against a stub runtime and assert on its result.
// Usage: node run-recon-map.mjs <recon-map.workflow.js>
// Each scenario scripts agent() returns by label prefix and checks the result,
// the agents that ran, and the prompts they were given.
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))

async function run(argsIn, script) {
  const calls = []
  const logs = []
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, opts, prompt })
    const [kind, unit] = opts.label.split(':')
    const r = script(kind, unit, prompt, opts)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, async () => [], () => {}, (m) => logs.push(m), argsIn)
  return { result, calls, labels: calls.map((c) => c.label), logs, prompt: (l) => calls.find((c) => c.label === l)?.prompt ?? '' }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}

const BASE = { root: '/clean/checkout', scratch: '/scratch/recon', context: 'ctx' }
const unitsOf = (keys, extra = {}) => keys.map((key) => ({ key, brief: `map ${key}`, ...extra }))
const item = (claim, status = 'holds', verified = true, evidence = 'src/a.js:1') => ({ claim, status, evidence, implication: '', verified })
const claims = (unit, items) => ({ unit, summary: '', items, risks: [], open_questions: [], gaps: [] })
const noTail = { critic: false, verify: 'none', synth: false }
const synthOut = { summary: 's', current_state: '', baselines: [], work_items: [], merge_order: [], decisions_for_user: [], open_questions: [] }
const ids = (r) => (r.result.verification?.selected ?? []).map((x) => x.id)

// 1. Stringified args; the default tail is critic → verify(non-holding) → synth, no gap-fill when the critic finds none.
{
  const r = await run(JSON.stringify({ ...BASE, units: unitsOf(['a', 'b']) }), (k, u) =>
    k === 'map' ? claims(u, [item(`${u} holds`)]) : k === 'critic' ? { coverage_status: 'complete', gaps: [], contradictions: [] }
      : k === 'verify' ? { verdicts: [] } : k === 'synth' ? synthOut : undefined)
  check('stringified args run the default tail', JSON.stringify(r.labels) === JSON.stringify(['map:a', 'map:b', 'critic', 'synth']), r.labels)
  check('synth result returned', r.result.synthesis?.summary === 's', r.result)
  check('synth told to write recon.json under scratch', r.prompt('synth').includes('/scratch/recon/recon.json'), '')
}
// 2. Over the cap of 10: map only the first 10 and log + return the dropped keys.
{
  const keys = Array.from({ length: 12 }, (_, i) => `u${i + 1}`)
  const r = await run({ ...BASE, units: unitsOf(keys), tail: noTail }, (k, u) => (k === 'map' ? claims(u, [item('x')]) : undefined))
  check('12 units → 10 map agents', r.labels.filter((l) => l.startsWith('map:')).length === 10, r.labels)
  check('dropped units returned', JSON.stringify(r.result.dropped_units) === '["u11","u12"]', r.result.dropped_units)
  check('dropped units logged', r.logs.some((m) => m.includes('u11') && m.includes('u12')), r.logs)
  // Without the cut at MAX_UNITS, u11 and u12 would come back as 'failed' units.
  check('10 unit rows, every one ok', r.result.units.length === 10 && r.result.units.every((x) => x.status === 'ok'), r.result.units)
  check('no unit reported as a dead mapper', !r.logs.some((m) => m.includes('mappers that returned nothing')), r.logs)
}
// 3. Guards abort before any agent runs.
for (const [name, a, reason] of [
  ['no units', { ...BASE, units: [] }, 'no-units'],
  ['duplicate unit keys', { ...BASE, units: unitsOf(['a', 'a']) }, 'duplicate-unit-key'],
  ['unknown unit_kind', { ...BASE, units: unitsOf(['a']), unit_kind: 'free' }, 'bad-unit-kind'],
  ['haiku unit without inputs', { ...BASE, units: [{ key: 'a', brief: 'b', model: 'haiku' }] }, 'haiku-without-inputs'],
  ['missing root', { scratch: '/s', units: unitsOf(['a']) }, 'missing-root'],
  ['missing scratch', { root: '/r', units: unitsOf(['a']) }, 'missing-scratch'],
  ['unknown verify mode', { ...BASE, units: unitsOf(['a']), tail: { verify: 'some' } }, 'bad-verify-mode'],
  ['unknown unit model', { ...BASE, units: [{ key: 'a', brief: 'b', model: 'fable' }] }, 'bad-unit-model'],
]) {
  const r = await run(a, () => claims('x', []))
  check(`${name} → abort ${reason}, zero agents`, r.result.abort === true && r.result.reason === reason && r.calls.length === 0, r.result)
}
// 4. Gap-fill is capped at 3 by a literal slice; the rest are returned unfilled.
{
  const gaps = Array.from({ length: 5 }, (_, i) => ({ units: ['a'], what: `gap ${i + 1}` }))
  const script = (k, u) => (k === 'map' ? claims(u, [item('x')]) : k === 'critic' ? { coverage_status: 'gaps', gaps, contradictions: [] } : k === 'gapfill' ? claims(`gapfill-${u}`, [item(`new ${u}`)]) : undefined)
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: true, verify: 'none', synth: false } }, script)
  check('5 gaps → 3 gap-fillers', r.labels.filter((l) => l.startsWith('gapfill:')).length === 3, r.labels)
  check('2 gaps unfilled and returned', r.result.unfilled_gaps?.length === 2, r.result.unfilled_gaps)
  const one = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: true, gapfill_cap: 1, verify: 'none', synth: false } }, script)
  check('gapfill_cap 1 → 1 gap-filler', one.labels.filter((l) => l.startsWith('gapfill:')).length === 1 && one.result.unfilled_gaps.length === 4, one.labels)
  const zero = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: true, gapfill_cap: 0, verify: 'none', synth: false } }, script)
  check('gapfill_cap 0 → no gap-filler', !zero.labels.some((l) => l.startsWith('gapfill:')), zero.labels)
  check('gapfill_cap 0 → critic told no follow-up agents run', zero.prompt('critic').includes('No follow-up agents') && !/at most \d+ follow-up/.test(zero.prompt('critic')), zero.prompt('critic').slice(-600))
  check('gapfill_cap 1 → critic told at most 1 follow-up agent', one.prompt('critic').includes('at most 1 follow-up agents'), '')
  check('gap-fill items join the item set', r.result.items.some((x) => x.unit === 'gapfill-1'), r.result.items.map((x) => x.unit))
}
// 5. critic:false → no critic and no gap-fill.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: noTail }, (k, u) => (k === 'map' ? claims(u, [item('x')]) : undefined))
  check('critic off → map only', r.labels.every((l) => l.startsWith('map:')), r.labels)
}
// 6. Verify selection by mode.
{
  const script = (k, u) => (k === 'map' ? claims(u, u === 'a' ? [item('a holds'), item('a drifted', 'drifted'), item('a unchecked', 'holds', false)] : [item('b holds')])
    : k === 'verify' ? { verdicts: [] } : undefined)
  const nh = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: false, verify: 'non-holding', synth: false } }, script)
  check('non-holding selects drifted + unverified only', JSON.stringify(ids(nh)) === '["a#2","a#3"]', ids(nh))
  const all = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: false, verify: 'all', synth: false } }, script)
  check('all selects every cited item', ids(all).length === 4, ids(all))
  const none = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: noTail }, script)
  check('none → no verifier', !none.labels.includes('verify'), none.labels)
  const holding = await run({ ...BASE, units: unitsOf(['b', 'c']), tail: { critic: false, verify: 'non-holding', synth: false } }, script)
  check('nothing non-holding → no verifier', !holding.labels.includes('verify'), holding.labels)
}
// 7. A haiku unit runs as the lean reader, and its items are always verified, even with verify:none.
{
  const r = await run({ ...BASE, units: [{ key: 'h', brief: 'read dumps', model: 'haiku', inputs: ['/scratch/dump.txt'] }, { key: 'o', brief: 'x' }], tail: noTail },
    (k, u) => (k === 'map' ? claims(u, [item(`${u} holds`)]) : k === 'verify' ? { verdicts: [] } : undefined))
  const h = r.calls.find((c) => c.label === 'map:h')
  check('haiku unit → lean-reader + haiku + effort', h?.opts.model === 'haiku' && h?.opts.agentType === 'agents-plugin:lean-reader' && Boolean(h?.opts.effort), h?.opts)
  check('haiku brief names its pre-dumped inputs', h?.prompt.includes('/scratch/dump.txt'), '')
  // The lean reader gets no COMMON block: these are its only read-only and evidence clauses.
  check('haiku prompt carries READ-ONLY and file:line', h?.prompt.includes('READ-ONLY') && h?.prompt.includes('file:line'), h?.prompt)
  check('haiku items verified under verify:none', r.labels.includes('verify') && JSON.stringify(ids(r)) === '["h#1"]', ids(r))
}
// 8. A dead verifier confirms nothing.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: false, verify: 'all', synth: true } },
    (k, u) => (k === 'map' ? claims(u, [item(`${u} claim`, 'drifted')]) : k === 'verify' ? null : k === 'synth' ? synthOut : undefined))
  const v = r.result.verification
  check('dead verifier → failed, every selected item unverifiable', v.failed === true && v.selected.every((x) => x.verdict === 'unverifiable'), v)
  check('dead verifier → synth still runs', r.labels.includes('synth'), r.labels)
  check('synth told verification failed', r.prompt('synth').includes('VERIFIER RETURNED NOTHING'), '')
}
// 9. Rejected items never reach the synthesizer; corrections do; an omitted verdict is unverifiable.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: false, verify: 'all', synth: true } }, (k, u) =>
    k === 'map' ? claims(u, u === 'a' ? [item('REFUTED-CLAIM', 'drifted'), item('ADJUSTED-CLAIM', 'drifted'), item('SKIPPED-CLAIM', 'drifted')] : [item('b ok')])
      : k === 'verify' ? { verdicts: [
        { id: 'a#1', claim: 'REFUTED-CLAIM', verdict: 'rejected', correction: '', evidence: 'src/a.js:9 says otherwise' },
        { id: 'a#2', claim: 'ADJUSTED-CLAIM', verdict: 'adjusted', correction: 'THE-CORRECTION', evidence: 'src/a.js:4' },
        { id: 'b#1', claim: 'b ok', verdict: 'confirmed', correction: '', evidence: 'src/b.js:1' },
      ] } : k === 'synth' ? synthOut : undefined)
  const sp = r.prompt('synth')
  check('rejected claim absent from synth input', !sp.includes('REFUTED-CLAIM'), '')
  check('adjusted claim carries its correction', sp.includes('THE-CORRECTION'), '')
  check('rejected claim listed in result', r.result.rejected.some((x) => x.id === 'a#1'), r.result.rejected)
  check('omitted verdict → unverifiable', r.result.verification.selected.find((x) => x.id === 'a#3')?.verdict === 'unverifiable', r.result.verification)
}
// 10. An item with no evidence is dropped before verify and synth, and reported.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: false, verify: 'all', synth: true } }, (k, u) =>
    k === 'map' ? claims(u, u === 'a' ? [item('UNCITED-CLAIM', 'drifted', true, ''), item('cited', 'drifted')] : [item('b')])
      : k === 'verify' ? { verdicts: [] } : k === 'synth' ? synthOut : undefined)
  check('uncited item not sent to the verifier', !ids(r).includes('a#1') && ids(r).includes('a#2'), ids(r))
  check('uncited item not sent to synth', !r.prompt('synth').includes('UNCITED-CLAIM'), '')
  check('uncited item reported', r.result.uncited.some((x) => x.id === 'a#1'), r.result.uncited)
}
// 11. A dead mapper is a failed unit the critic is told about; the run continues.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: true, verify: 'none', synth: true } }, (k, u) =>
    k === 'map' ? (u === 'a' ? null : claims(u, [item('x')])) : k === 'critic' ? { coverage_status: 'ok', gaps: [], contradictions: [] } : k === 'synth' ? synthOut : undefined)
  check('dead mapper → unit failed', r.result.units.find((x) => x.key === 'a')?.status === 'failed', r.result.units)
  check('critic told which unit failed', /returned nothing[^\n]*\ba\b/.test(r.prompt('critic')), r.prompt('critic').slice(0, 400))
  check('synth still runs', r.labels.includes('synth'), r.labels)
}
// 12. Every mapper dead → abort before any tail agent.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']) }, (k) => (k === 'map' ? null : synthOut))
  check('no reports → abort no-reports, no tail', r.result.reason === 'no-reports' && r.labels.every((l) => l.startsWith('map:')), r.labels)
}
// 13. ac kind: satisfied with refs holds; partial and a missing AC that cites its search are
// selected and reach synth; a row with no refs is uncited, and synth is still told its id.
{
  const ac = (index, status, headRefs, summary = `ac${index}`) => ({ index, summary, status, headRefs, notes: '', remainingWork: status === 'missing' ? 'build it' : '' })
  const search = ["rg -n 'exportCsv' src/ → (no output; control rg -n 'exportJson' src/ → src/x.ts:4)", 'src/x.ts:4']
  const r = await run({ ...BASE, unit_kind: 'ac', units: unitsOf(['s1', 's2']), tail: { critic: false, verify: 'non-holding', synth: true } }, (k, u) =>
    k === 'map' ? { unit: u, story: u, acs: [ac(1, 'satisfied', ['a.ts:1']), ac(2, 'partial', ['a.ts:2']), ac(3, 'missing', [], 'UNCITED-AC'), ac(4, 'missing', search, 'MISSING-AC')], keyApis: [], staleRefs: [], risks: [], openQuestions: [] }
      : k === 'verify' ? { verdicts: [] } : k === 'synth' ? synthOut : undefined)
  const sp = r.prompt('synth')
  check('ac: partial selected, satisfied not', ids(r).includes('s1#2') && !ids(r).includes('s1#1'), ids(r))
  check('ac: no headRefs → uncited', r.result.uncited.some((x) => x.id === 's1#3'), r.result.uncited)
  check('ac: map prompt tells a missing AC to cite its search', r.prompt('map:s1').includes('A missing AC still cites its negative evidence'), '')
  check('ac: missing AC with a cited search is verified and reaches synth', ids(r).includes('s1#4') && sp.includes('MISSING-AC'), ids(r))
  // A missing AC is never silently invisible to synth: either its row or its dropped id is there.
  check('ac: uncited AC text kept out of synth, its id listed as dropped', !sp.includes('UNCITED-AC') && /citing no evidence[^\n]*s1#3/.test(sp), sp.slice(0, 200))
}
// 14. findings kind: findings are non-holding; reviewed_ok joins only under verify:all.
{
  const f = (u) => ({ unit: u, area: u, findings: [{ id: `${u}-f1`, kind: 'failing', severity: 'high', evidence: 'gh run view 1: exit 1', root_cause: 'r', fix: 'f', fix_location: 'repo', confidence: 'high', existing_pr_or_issue: '' }], reviewed_ok: [{ item: 'ci.yml', why: 'green, gh run list shows success' }], notes: '' })
  const script = (k, u) => (k === 'map' ? f(u) : k === 'verify' ? { verdicts: [] } : undefined)
  const nh = await run({ ...BASE, unit_kind: 'findings', units: unitsOf(['x', 'y']), tail: { critic: false, verify: 'non-holding', synth: false } }, script)
  check('findings: non-holding = findings only', JSON.stringify(ids(nh)) === '["x#1","y#1"]', ids(nh))
  const all = await run({ ...BASE, unit_kind: 'findings', units: unitsOf(['x', 'y']), tail: { critic: false, verify: 'all', synth: false } }, script)
  check('findings: all adds reviewed_ok', ids(all).length === 4, ids(all))
}
// 15. coverage_cmd: the critic writes the unit reports to disk, then runs the command.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), coverage_cmd: 'python3 /scratch/recon/coverage.py', tail: { critic: true, verify: 'none', synth: false } },
    (k, u) => (k === 'map' ? claims(u, [item('x')]) : k === 'critic' ? { coverage_status: 'ok', gaps: [], contradictions: [] } : undefined))
  const cp = r.prompt('critic')
  check('critic writes units/<key>.json and runs coverage_cmd', cp.includes('/scratch/recon/units/') && cp.includes('python3 /scratch/recon/coverage.py'), cp.slice(0, 300))
  // Without coverage_cmd the critic writes nothing, so the synthesizer must write the unit reports.
  const script = (k, u) => (k === 'map' ? claims(u, [item('x')]) : k === 'critic' ? { coverage_status: 'ok', gaps: [], contradictions: [] } : k === 'synth' ? synthOut : undefined)
  const noCov = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: true, verify: 'none', synth: true } }, script)
  check('critic without coverage_cmd → synth writes units/', noCov.prompt('synth').includes('/scratch/recon/units/'), '')
  const cov = await run({ ...BASE, units: unitsOf(['a', 'b']), coverage_cmd: 'python3 c.py', tail: { critic: true, verify: 'none', synth: true } }, script)
  check('critic ran coverage_cmd → synth does not rewrite units/', !cov.prompt('synth').includes('/scratch/recon/units/'), '')
}
// 16. Every prompt carries the read-only + evidence clauses; no agent is given a worktree.
{
  const r = await run({ ...BASE, units: unitsOf(['a', 'b']), tail: { critic: true, verify: 'all', synth: true } }, (k, u) =>
    k === 'map' ? claims(u, [item('x', 'drifted')]) : k === 'critic' ? { coverage_status: 'ok', gaps: [], contradictions: [] } : k === 'verify' ? { verdicts: [] } : synthOut)
  const opusCalls = r.calls.filter((c) => c.opts.model !== 'haiku')
  check('read-only clause in every prompt', opusCalls.every((c) => c.prompt.includes('READ-ONLY')), r.labels)
  check('file:line clause in every prompt', opusCalls.every((c) => c.prompt.includes('file:line')), r.labels)
  check('no worktree isolation anywhere', r.calls.every((c) => c.opts.isolation === undefined), r.calls.map((c) => c.opts.isolation))
}
// 17. Verifier cap: 45 selected items → 40 to the verifier; the other 5 stay unverifiable even
// when the verifier (wrongly) returns a verdict for them.
{
  const many = Array.from({ length: 45 }, (_, i) => item(`claim ${i + 1}`, 'drifted'))
  const allConfirmed = { verdicts: many.map((_, i) => ({ id: `a#${i + 1}`, claim: '', verdict: 'confirmed', correction: '', evidence: 'x' })) }
  const r = await run({ ...BASE, units: unitsOf(['a']), tail: { critic: false, verify: 'non-holding', synth: false } }, (k, u) =>
    k === 'map' ? claims(u, many) : k === 'verify' ? allConfirmed : undefined)
  const v = r.result.verification
  const over = ['a#41', 'a#42', 'a#43', 'a#44', 'a#45']
  check('over cap → over_cap holds the overflow ids', JSON.stringify(v.over_cap) === JSON.stringify(over), v.over_cap)
  check('over cap → overflow verdicts unverifiable', over.every((id) => v.selected.find((x) => x.id === id)?.verdict === 'unverifiable'), v.selected.slice(-5))
  check('over cap → in-cap verdicts applied', v.selected.find((x) => x.id === 'a#40')?.verdict === 'confirmed', v.selected[39])
  const sent = (r.prompt('verify').match(/"id": "a#\d+"/g) ?? []).length
  check('verifier prompt carries at most 40 items', sent === 40, sent)
  check('over cap logged', r.logs.some((m) => m.includes('verifier cap 40')), r.logs)
}
// 18. Under verify:none every item reaches synth as "not-checked", and synth is told what that means.
{
  const r = await run({ ...BASE, units: unitsOf(['a']), tail: { critic: false, verify: 'none', synth: true } }, (k, u) =>
    k === 'map' ? claims(u, [item('NOT-CHECKED-CLAIM', 'drifted')]) : k === 'synth' ? synthOut : undefined)
  const sp = r.prompt('synth')
  check('verify:none → item verdict not-checked', r.result.items.every((x) => x.verification.verdict === 'not-checked'), r.result.items)
  check('synth defines not-checked', sp.includes('A "not-checked" item') && sp.includes('NOT-CHECKED-CLAIM'), '')
}
// 19. A unit's own effort is ignored and logged; the tier's effort is used.
{
  const r = await run({ ...BASE, units: [{ key: 'a', brief: 'b', model: 'sonnet', effort: 'low' }], tail: noTail }, (k, u) => (k === 'map' ? claims(u, [item('x')]) : undefined))
  const a = r.calls.find((c) => c.label === 'map:a')
  check('unit effort ignored → tier effort, logged', a?.opts.model === 'sonnet' && a?.opts.effort === 'high' && r.logs.some((m) => m.includes('effort is ignored')), { opts: a?.opts, logs: r.logs })
}

process.exit(failed ? 1 : 0)
