// Run compete-and-judge.workflow.js against a stub runtime and assert on its result.
// Usage: node run-template.mjs <compete-and-judge.workflow.js>
// Each scenario scripts agent() returns by label (`setup:k`, `enter:k`, `judge:k`, `refine`).
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)

// The real runtime resolves a failed thunk to null; the stub does the same.
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))

async function run(argsIn, script) {
  const calls = []
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt, opts })
    const [kind, key] = opts.label.split(':')
    const r = script(kind, key, prompt)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, null, () => {}, () => {}, argsIn)
  return { result, calls, labels: calls.map((c) => c.label) }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}

const ENTRY = (key, extra = {}) => ({
  key, dir: `/out/${key}`, summary: `entry ${key}`, self_assessment: '', files: [], iterations: 2, ...extra,
})
const score = (key, s) => ({ key, score: s, strengths: '', weaknesses: '', fixes: `fix ${key}` })
// A judge verdict. `scores` defaults to 5 for everyone so Borda alone decides.
const VERDICT = (ranking, scores, extra = {}) => ({
  scores: scores ?? ranking.map((k) => score(k, 5)),
  ranking,
  grafts: [],
  ...extra,
})
const entries = (keys) => keys.map((key) => ({ key, angle: `angle ${key}` }))
const judges = (keys) => keys.map((key) => ({ key, lens: `lens ${key}` }))
const base = (eKeys, jKeys, extra = {}) => ({
  context: 'brief', out: '/out', entries: entries(eKeys), judges: judges(jKeys), ...extra,
})
const borda = (r) => Object.fromEntries((r.result.standings ?? []).map((s) => [s.key, s.borda]))

// 1. The winner is the Borda count, not anything a judge writes in prose.
{
  const rankings = { j1: ['b', 'a', 'c'], j2: ['b', 'c', 'a'], j3: ['a', 'b', 'c'] }
  const r = await run(base(['a', 'b', 'c'], ['j1', 'j2', 'j3']), (k, key) =>
    k === 'enter' ? ENTRY(key)
      : k === 'judge' ? VERDICT(rankings[key], undefined, { winner: 'c', overall: 'c is clearly best' })
      : k === 'refine' ? { dir: '/out/final', changes: '', grafted: [], files: [], remaining_concerns: '' } : undefined)
  check('Borda winner', r.result.winner === 'b', r.result)
  check('Borda points are K-1-position', JSON.stringify(borda(r)) === JSON.stringify({ b: 5, a: 3, c: 1 }), borda(r))
  const refine = r.calls.find((c) => c.label === 'refine')
  check('refine runs once, on the computed winner', r.labels.filter((l) => l === 'refine').length === 1 && /winner is `b`/.test(refine.prompt), refine?.prompt?.slice(0, 200))
  check('no agent between Judge and Refine', r.labels.indexOf('refine') === r.labels.length - 1 && r.labels.slice(-2)[0].startsWith('judge:'), r.labels)
  check('every agent() pins model and effort', r.calls.every((c) => c.opts.model && c.opts.effort), r.calls.map((c) => c.opts))
  const judgeCalls = r.calls.filter((c) => c.label.startsWith('judge:'))
  check('every judge sees every surviving entry',
    judgeCalls.length === 3 && judgeCalls.every((c) => ['a', 'b', 'c'].every((k) => c.prompt.includes(`${k}: /out/${k}`))),
    judgeCalls.map((c) => c.prompt.slice(0, 300)))
}
// 2. An exact tie breaks on caller order, whatever order the verdicts arrive in.
{
  const tie = (eKeys, jKeys) =>
    run(base(eKeys, jKeys, { finish: 'none' }), (k, key) =>
      k === 'enter' ? ENTRY(key) : k === 'judge' ? VERDICT(key === 'j1' ? ['a', 'b'] : ['b', 'a']) : undefined)
  const r1 = await tie(['a', 'b'], ['j1', 'j2'])
  const r2 = await tie(['a', 'b'], ['j2', 'j1'])
  const r3 = await tie(['b', 'a'], ['j1', 'j2'])
  check('exact tie → first entry in args.entries', r1.result.winner === 'a' && r2.result.winner === 'a', [r1.result.winner, r2.result.winner])
  check('exact tie follows caller order, not key order', r3.result.winner === 'b', r3.result.winner)
  check('tie is reported, not hidden', r1.result.tie === true && JSON.stringify(r1.result.tied_with) === '["b"]', r1.result)
  const again = await tie(['a', 'b'], ['j1', 'j2'])
  check('same inputs → same standings', JSON.stringify(again.result.standings) === JSON.stringify(r1.result.standings), again.result.standings)
}
// 3. A Borda tie breaks on mean score before caller order.
{
  const r = await run(base(['a', 'b'], ['j1', 'j2'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? ENTRY(key)
      : k === 'judge' ? VERDICT(key === 'j1' ? ['a', 'b'] : ['b', 'a'], [score('a', 4), score('b', 8)]) : undefined)
  check('Borda tie → higher mean score wins', r.result.winner === 'b' && r.result.tie === false, r.result)
}
// 4. A dead judge panel never crowns the first entry (the ad-hoc runs did: all-zero Borda, stable sort).
{
  const r = await run(base(['a', 'b', 'c'], ['j1', 'j2', 'j3']), (k, key) => (k === 'enter' ? ENTRY(key) : undefined))
  check('no verdicts → no winner', r.result.winner === null && r.result.reason === 'no-quorum', r.result)
  check('no verdicts → no refine', !r.labels.includes('refine'), r.labels)
  const one = await run(base(['a', 'b', 'c'], ['j1', 'j2', 'j3']), (k, key) =>
    k === 'enter' ? ENTRY(key) : k === 'judge' && key === 'j1' ? VERDICT(['c', 'b', 'a']) : undefined)
  check('1 of 3 verdicts is below quorum', one.result.winner === null && one.result.reason === 'no-quorum', one.result)
}
// 5. Partial, duplicated and unknown ranking entries: points depend on K, each key counts once.
{
  const rankings = { j1: ['c'], j2: ['a', 'a', 'zz', 'b', 'c'], j3: ['b', 'c', 'a'] }
  const r = await run(base(['a', 'b', 'c'], ['j1', 'j2', 'j3'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? ENTRY(key) : k === 'judge' ? VERDICT(rankings[key], [score('a', 5), score('b', 5), score('c', 5)]) : undefined)
  check('partial ranking scores on K, duplicates once, unknown ignored', JSON.stringify(borda(r)) === JSON.stringify({ b: 3, c: 3, a: 2 }), borda(r))
  check('incomplete rankings are reported', JSON.stringify(r.result.ranking_gaps) === JSON.stringify([{ judge: 'j1', missing: ['a', 'b'] }]), r.result.ranking_gaps)
}
// 6. Metric mode: acceptance first, then each metric key in order; self-reported numbers and judge rankings are ignored.
{
  const meas = (key, ok, crossings, length) => ({
    key, meets_acceptance: ok, values: [{ name: 'crossings', value: crossings }, { name: 'length', value: length }],
  })
  const args = base(['a', 'b', 'c'], ['m1', 'm2'], {
    finish: 'none',
    aggregation: 'metric',
    metric: { command: 'python3 measure.py <dir>', keys: [{ name: 'crossings', better: 'lower' }, { name: 'length', better: 'lower' }] },
  })
  const r = await run(args, (k, key) =>
    k === 'enter' ? ENTRY(key, { metrics: [{ name: 'crossings', value: 0 }], meets_acceptance: true })
      : k === 'judge' ? VERDICT(['a', 'b', 'c'], undefined, {
        measurements: key === 'm1'
          ? [meas('a', false, 0, 1), meas('b', true, 3, 12), meas('c', true, 3, 10)]
          : [meas('a', true, 0, 1), meas('b', true, 3, 12), meas('c', true, 3, 11)],
      }) : undefined)
  check('metric: acceptance, then crossings, then length', r.result.winner === 'c', r.result.standings)
  check('metric: one failed acceptance excludes the entry from the top', r.result.standings.at(-1).key === 'a', r.result.standings)
  const noKeys = await run({ ...args, metric: { command: 'x', keys: [] } }, () => ENTRY('a'))
  check('metric mode without keys aborts before any agent', noKeys.result.reason === 'no-metric' && noKeys.calls.length === 0, noKeys.result)
}
// 7. Bounds and inputs: abort before spawning, never truncate.
{
  const over = await run(base(['a', 'b', 'c', 'd', 'e', 'f'], ['j1']), () => ENTRY('x'))
  check('6 entries abort over cap', over.result.reason === 'over-cap' && over.calls.length === 0, over.result)
  const under = await run(base(['a'], ['j1']), () => ENTRY('x'))
  check('1 entry aborts below floor', under.result.reason === 'below-floor' && under.calls.length === 0, under.result)
  const manyJ = await run(base(['a', 'b'], ['j1', 'j2', 'j3', 'j4']), () => ENTRY('x'))
  check('4 judges abort', manyJ.result.reason === 'judges-out-of-range' && manyJ.calls.length === 0, manyJ.result)
  const dup = await run(base(['a', 'a'], ['j1']), () => ENTRY('x'))
  check('duplicate entry keys abort', dup.result.reason === 'duplicate-key' && dup.calls.length === 0, dup.result)
  const bad = await run(base(['a', '../b'], ['j1']), () => ENTRY('x'))
  check('path-like key aborts', bad.result.reason === 'bad-key' && bad.calls.length === 0, bad.result)
  const str = await run(JSON.stringify(base(['a', 'b'], ['j1'], { finish: 'none' })), (k, key) =>
    k === 'enter' ? ENTRY(key) : k === 'judge' ? VERDICT(['b', 'a']) : undefined)
  check('stringified args parse', str.result.winner === 'b', str.result)
}
// 8. Dead entrants drop out; fewer than two survivors means no tournament.
{
  const r = await run(base(['a', 'b', 'c'], ['j1'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? (key === 'c' ? null : ENTRY(key)) : k === 'judge' ? VERDICT(['c', 'b', 'a']) : undefined)
  check('dead entrant is not ranked', r.result.winner === 'b' && !r.result.standings.some((s) => s.key === 'c'), r.result.standings)
  const jp = r.calls.find((c) => c.label === 'judge:j1').prompt
  check('judge sees the survivors and not the dead entrant', jp.includes('a: /out/a') && jp.includes('b: /out/b') && !jp.includes('c: /out/c'), jp.slice(0, 300))
  const solo = await run(base(['a', 'b'], ['j1']), (k, key) => (k === 'enter' && key === 'a' ? ENTRY(key) : undefined))
  check('one survivor → no judges', solo.result.reason === 'too-few-entries' && !solo.labels.some((l) => l.startsWith('judge:')), solo.labels)
}
// 9. Setup is a barrier: every setup agent finishes before an entrant starts; a dead one aborts.
{
  const order = []
  const r = await run(base(['a', 'b'], ['j1'], { finish: 'none', setup: [{ key: 'harness', brief: 'build it' }] }), (k, key) => {
    order.push(k)
    return k === 'setup' ? { key, summary: 'harness at /out/harness', files: [] } : k === 'enter' ? ENTRY(key) : VERDICT(['a', 'b'])
  })
  check('setup runs before compete', order[0] === 'setup' && r.result.winner === 'a', order)
  const enterPrompt = r.calls.find((c) => c.label === 'enter:a').prompt
  check('entrants see the setup output', enterPrompt.includes('harness at /out/harness'), enterPrompt.slice(0, 300))
  const dead = await run(base(['a', 'b'], ['j1'], { setup: [{ key: 'harness', brief: 'b' }] }), () => undefined)
  check('dead setup aborts before compete', dead.result.reason === 'setup-failed' && !dead.labels.some((l) => l.startsWith('enter:')), dead.labels)
}
// 10. finish: none spawns no refine agent.
{
  const r = await run(base(['a', 'b'], ['j1'], { finish: 'none' }), (k, key) => (k === 'enter' ? ENTRY(key) : VERDICT(['a', 'b'])))
  check('finish none → no refine', !r.labels.includes('refine') && r.result.refined === null, r.labels)
}
const METRIC_ARGS = (eKeys, jKeys, extra = {}) => base(eKeys, jKeys, {
  aggregation: 'metric',
  metric: { command: 'python3 measure.py <dir>', keys: [{ name: 'crossings', better: 'lower' }, { name: 'length', better: 'lower' }] },
  ...extra,
})
const REFINED = { dir: '/out/final', changes: '', grafted: [], files: [], remaining_concerns: '' }
// 11. Metric judges that measured nothing are not a quorum: an empty or unknown-name `values`
//     row would otherwise make every median null, every entry "meet acceptance", and crown entry 0.
{
  const empty = (vals) => (k, key) =>
    k === 'enter' ? ENTRY(key)
      : k === 'judge' ? VERDICT(['c', 'b', 'a'], undefined, { measurements: ['a', 'b', 'c'].map((e) => ({ key: e, values: vals, meets_acceptance: true })) })
      : k === 'refine' ? REFINED : undefined
  const r = await run(METRIC_ARGS(['a', 'b', 'c'], ['m1', 'm2']), empty([]))
  check('metric: judges with empty values → no-quorum', r.result.winner === null && r.result.reason === 'no-quorum', r.result)
  check('metric: judges with empty values → no refine', !r.labels.includes('refine'), r.labels)
  const unknown = await run(METRIC_ARGS(['a', 'b', 'c'], ['m1', 'm2']), empty([{ name: 'speed', value: 1 }]))
  check('metric: values naming no metric key → no-quorum', unknown.result.winner === null && unknown.result.reason === 'no-quorum', unknown.result)
}
// 12. Metric mode: an entry with no finite value for a key sorts after every measured entry,
//     and a judge that omitted an entry's row is reported in ranking_gaps.
{
  const r = await run(METRIC_ARGS(['c', 'a', 'b'], ['m1', 'm2'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? ENTRY(key)
      : k === 'judge' ? VERDICT(['c', 'a', 'b'], undefined, {
        measurements: [
          { key: 'a', meets_acceptance: true, values: [{ name: 'crossings', value: 5 }, { name: 'length', value: 1 }] },
          { key: 'b', meets_acceptance: true, values: [{ name: 'crossings', value: 2 }, { name: 'length', value: 1 }] },
          // m1 measured only c's length; m2 left c out entirely.
          ...(key === 'm1' ? [{ key: 'c', meets_acceptance: true, values: [{ name: 'length', value: 1 }] }] : []),
        ],
      }) : undefined)
  check('metric: a missing value sorts last, even for lower-is-better', JSON.stringify(r.result.standings.map((s) => s.key)) === '["b","a","c"]', r.result.standings)
  check('metric: the missing value stays null, not 0', r.result.standings.at(-1).values.crossings === null, r.result.standings.at(-1))
  check('metric: an omitted measurement row is a ranking gap', JSON.stringify(r.result.ranking_gaps) === JSON.stringify([{ judge: 'm2', missing: ['c'] }]), r.result.ranking_gaps)
}
// 13. One score row per judge per entry: a duplicated row is not an extra vote in the mean-score tiebreak.
{
  const r = await run(base(['a', 'b'], ['j1', 'j2'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? ENTRY(key)
      : k === 'judge' ? VERDICT(key === 'j1' ? ['a', 'b'] : ['b', 'a'],
        key === 'j1' ? [score('a', 9), score('b', 1)] : [score('a', 1), score('b', 8), score('b', 8), score('b', 8)])
      : undefined)
  // Counted once: a = (9+1)/2 = 5, b = (1+8)/2 = 4.5 → a. Counted three times, b = 25/4 = 6.25 → b.
  const means = Object.fromEntries(r.result.standings.map((s) => [s.key, s.mean]))
  check('duplicated score row counts once in the mean', means.a === 5 && means.b === 4.5, means)
  check('duplicated score rows cannot flip the tiebreak', r.result.winner === 'a', r.result.standings)
}
// 14. Every verdict a judge returned is in the result, with the unusable ones named, quorum or not.
{
  const unusable = VERDICT(['zz', 'yy'])
  const r = await run(base(['a', 'b'], ['j1', 'j2', 'j3'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? ENTRY(key) : k === 'judge' ? (key === 'j3' ? unusable : VERDICT(['b', 'a'])) : undefined)
  check('quorum: unusable verdict kept in result.verdicts', r.result.winner === 'b' && JSON.stringify(r.result.verdicts.map((v) => v.judge)) === '["j1","j2","j3"]', r.result.verdicts)
  check('quorum: unusable judge named in excluded_judges', JSON.stringify(r.result.excluded_judges) === '["j3"]', r.result.excluded_judges)
  const nq = await run(base(['a', 'b'], ['j1', 'j2', 'j3']), (k, key) =>
    k === 'enter' ? ENTRY(key) : k === 'judge' ? (key === 'j1' ? VERDICT(['b', 'a']) : key === 'j2' ? unusable : undefined) : undefined)
  check('no-quorum: unusable verdict kept in result.verdicts', nq.result.reason === 'no-quorum' && JSON.stringify(nq.result.verdicts.map((v) => v.judge)) === '["j1","j2"]', nq.result)
  check('no-quorum: unusable judge named in excluded_judges', JSON.stringify(nq.result.excluded_judges) === '["j2"]', nq.result.excluded_judges)
}
// 15. Metric mode: one measurement row per judge per entry, one value per metric name in it.
//     A judge that repeats a row (or a value) must not outvote the other judge in the median.
{
  const row = (key, crossings, extra = {}) => ({ key, meets_acceptance: true, values: [{ name: 'crossings', value: crossings }, { name: 'length', value: 1 }], ...extra })
  const judge = (m1) => (k, key) =>
    k === 'enter' ? ENTRY(key)
      : k === 'judge' ? VERDICT(['a', 'b'], undefined, { measurements: key === 'm1' ? m1 : [row('a', 9), row('b', 2)] })
      : undefined
  // Once each: a = median(1, 9) = 5, b = median(5, 2) = 3.5 → b (lower is better).
  // Counting m1's three `a` rows: a = median(1, 1, 1, 9) = 1 → a.
  const r = await run(METRIC_ARGS(['a', 'b'], ['m1', 'm2'], { finish: 'none' }), judge([row('a', 1), row('a', 1), row('a', 1), row('b', 5)]))
  const a = r.result.standings.find((s) => s.key === 'a')
  check('metric: a duplicated measurement row counts once', a.measured_by === 2 && a.values.crossings === 5, a)
  check('metric: duplicated rows cannot flip the winner', r.result.winner === 'b', r.result.standings)
  const v = await run(METRIC_ARGS(['a', 'b'], ['m1', 'm2'], { finish: 'none' }),
    judge([row('a', 1, { values: [{ name: 'crossings', value: 1 }, { name: 'crossings', value: 1 }, { name: 'crossings', value: 1 }, { name: 'length', value: 1 }] }), row('b', 5)]))
  check('metric: a repeated value inside one row counts once', v.result.winner === 'b' && v.result.standings.find((s) => s.key === 'a').values.crossings === 5, v.result.standings)
  const acc = await run(METRIC_ARGS(['a', 'b'], ['m1', 'm2'], { finish: 'none' }), judge([row('a', 1), row('a', 1, { meets_acceptance: false }), row('b', 5)]))
  check('metric: only a judge\'s first row for an entry votes on acceptance', acc.result.standings.find((s) => s.key === 'a').meets_acceptance === true, acc.result.standings)
}
// 16. Judge scratch lives under ${out}/_judges/, which no key can name, so an entry keyed
//     like the old `judge-<key>` scratch dir is never written by a judge.
{
  const r = await run(base(['judge-j1', 'b'], ['j1'], { finish: 'none' }), (k, key) =>
    k === 'enter' ? ENTRY(key) : k === 'judge' ? VERDICT(['b', 'judge-j1']) : undefined)
  const jp = r.calls.find((c) => c.label === 'judge:j1').prompt
  const scratch = jp.match(/scratch only under (\S+?)\/?\./)?.[1]
  check('judge scratch is under _judges/', scratch === '/out/_judges/j1', scratch)
  check('judge scratch is no entry directory', r.result.entries.every((e) => e.dir !== scratch && !scratch.startsWith(`${e.dir}/`)), [scratch, r.result.entries.map((e) => e.dir)])
  const under = await run(base(['_judges', 'b'], ['j1']), () => ENTRY('x'))
  check('a key cannot name the judges\' scratch dir', under.result.reason === 'bad-key' && under.calls.length === 0, under.result)
}

process.exit(failed ? 1 : 0)
