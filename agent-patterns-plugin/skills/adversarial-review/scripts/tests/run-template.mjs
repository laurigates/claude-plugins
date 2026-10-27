// Run an adversarial-review workflow template against a stub runtime and assert on its result.
// Usage: node run-template.mjs <template.workflow.js>
// Each scenario scripts agent() returns by label and checks the result and the calls made.
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)

// The runtime resolves a dead agent to null; mirror that.
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
const pipeline = () => {
  throw new Error('pipeline() not expected in these templates')
}

async function run(argsIn, script) {
  const calls = []
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt, opts })
    const r = script(opts.label, prompt)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, argsIn)
  return { result, calls, labels: calls.map((c) => c.label) }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}

const finding = (file, line, severity, title = `${file}:${line}`) => ({
  title, file, line, severity, claim: `claim ${title}`, failure_scenario: `fails ${title}`, suggested_fix: `fix ${title}`,
})
const verdict = (v, severity = 'medium') => ({ verdict: v, evidence: 'ran it', corrected_claim: '', fix_recommendation: '', severity })
const CLAIM_KEYS = ['title', 'file', 'line', 'severity', 'claim', 'failure_scenario', 'suggested_fix']
const isClaimShaped = (c) => CLAIM_KEYS.every((k) => k in c) && Array.isArray(c.raised_by) && !('verdict' in c)

if (basename(file).startsWith('find-verify')) {
  const lenses = (n) => ({ lenses: Array.from({ length: n }, (_, i) => ({ key: `l${i + 1}`, prompt: 'p' })) })

  // 1. Duplicates across lenses merge (one verifier, raised_by from both), keeping
  //    the more severe wording; "critical" ranks as high.
  {
    const r = await run(lenses(2), (label) => {
      if (label === 'find:l1') return { findings: [finding('a.js', 3, 'medium', 'dup-low'), finding('b.js', 1, 'low')] }
      if (label === 'find:l2') return { findings: [finding('a.js', 3, 'critical', 'dup-high')] }
      if (label.startsWith('verify:')) return verdict('confirmed')
    })
    const verifies = r.labels.filter((l) => l.startsWith('verify:'))
    const dup = r.result.confirmed.find((c) => c.file === 'a.js')
    check('dedup → one verifier per file:line', verifies.length === 2, r.labels)
    check('dedup merges raised_by', dup && dup.raised_by.includes('l1') && dup.raised_by.includes('l2'), dup)
    check('dedup keeps the most severe wording, critical → high', dup?.severity === 'high' && dup?.title === 'dup-high', dup)
    check('severity ranks verify order', r.calls.find((c) => c.label.startsWith('verify:1:'))?.prompt.includes('Location: a.js:3'), r.labels)
  }

  // 2. The cap binds after the rank: highest severity is verified, the rest come
  //    back unverified in the claims shape.
  {
    const fs = [finding('l.js', 1, 'low'), finding('h.js', 1, 'high'), finding('m.js', 1, 'medium'), finding('h2.js', 1, 'high')]
    const r = await run({ ...lenses(2), verifyCap: 2 }, (label) =>
      label === 'find:l1' ? { findings: fs } : label === 'find:l2' ? { findings: [] } : verdict('refuted'))
    const verified = r.result.refuted.map((x) => x.file).sort()
    check('cap 2 → exactly 2 verifiers', r.labels.filter((l) => l.startsWith('verify:')).length === 2, r.labels)
    check('cap verifies the two high findings', JSON.stringify(verified) === JSON.stringify(['h.js', 'h2.js']), verified)
    check('cut findings → unverified, in rank order', r.result.unverified.map((x) => x.file).join() === 'm.js,l.js', r.result.unverified)
    check('unverified is claim-shaped', r.result.unverified.every(isClaimShaped), r.result.unverified)
  }

  // 3. A dead verifier never drops its finding and never counts as refuted.
  //    (The ad-hoc runs filtered `r.verdict && …`, so such a finding vanished
  //    from every bucket.)
  {
    const r = await run(lenses(2), (label) => {
      if (label === 'find:l1') return { findings: [finding('a.js', 1, 'high'), finding('b.js', 2, 'medium')] }
      if (label === 'find:l2') return { findings: [] }
      if (label === 'verify:1:l1') return undefined
      if (label === 'verify:2:l1') return { verdict: 'maybe' }
    })
    const files = r.result.unverified.map((x) => x.file).sort().join()
    check('null and off-enum verdicts → unverified', files === 'a.js,b.js', r.result)
    check('dead verifier not refuted', r.result.refuted.length === 0 && r.result.confirmed.length === 0, r.result)
    check('verifierFailed names both', r.result.verifierFailed.join() === 'a.js:1,b.js:2', r.result.verifierFailed)
  }

  // 4. Verify-only re-run: a previous run's `unverified` is valid `args.claims`;
  //    Find is skipped and the claims round-trip unchanged.
  {
    const first = await run({ ...lenses(2), verifyCap: 1 }, (label) =>
      label === 'find:l1' ? { findings: [finding('a.js', 1, 'high'), finding('b.js', 2, 'low')] }
        : label === 'find:l2' ? { findings: [finding('b.js', 2, 'low')] } : verdict('confirmed'))
    const claims = first.result.unverified
    const second = await run({ claims, verifyCap: 6 }, (label) => (label.startsWith('verify:') ? verdict('partially') : undefined))
    check('verify-only spawns no finder', !second.labels.some((l) => l.startsWith('find:')), second.labels)
    check('verify-only verifies every claim', second.labels.filter((l) => l.startsWith('verify:')).length === claims.length, second.labels)
    const back = second.result.partially.map(({ control, verdict: _v, ...c }) => c)
    check('claims round-trip unchanged', JSON.stringify(back) === JSON.stringify(claims), { back, claims })
    check('raised_by survives the round trip', back[0]?.raised_by.join() === 'l1,l2', back)
    const empty = await run({ claims: [] }, () => verdict('confirmed'))
    check('empty claims abort with zero agents', empty.result.reason === 'no-claims' && empty.calls.length === 0, empty.result)
  }

  // 5. Control sample: the lowest-ranked cut findings get verified too, tagged,
  //    counted, and removed from `unverified`; the switch is clamped.
  {
    const fs = [finding('h.js', 1, 'high'), finding('m.js', 1, 'medium'), finding('l1.js', 1, 'low'), finding('l2.js', 1, 'low')]
    const script = (label) =>
      label === 'find:l1' ? { findings: fs } : label === 'find:l2' ? { findings: [] }
        : label.startsWith('control:') ? verdict('confirmed', 'low') : verdict('refuted')
    const r = await run({ ...lenses(2), verifyCap: 1, controlSample: 1 }, script)
    const ctl = r.labels.filter((l) => l.startsWith('control:'))
    check('controlSample 1 → one control verifier', ctl.length === 1, r.labels)
    check('control picks the lowest-ranked cut finding', r.calls.find((c) => c.label === ctl[0])?.prompt.includes('l2.js'), r.labels)
    check('control result tagged and counted', r.result.confirmed[0]?.control === true && r.result.control.confirmed === 1, r.result)
    check('control removed from unverified', r.result.unverified.map((x) => x.file).join() === 'm.js,l1.js', r.result.unverified)
    const clamped = await run({ ...lenses(2), verifyCap: 0, controlSample: 9 }, script)
    check('controlSample clamped to 2', clamped.labels.filter((l) => l.startsWith('control:')).length === 2, clamped.labels)
    const none = await run({ ...lenses(2), verifyCap: 9 }, script)
    check('verifyCap clamped to 6 and no control by default', none.result.stats.verifyCap === 6 && !none.labels.some((l) => l.startsWith('control:')), none.result.stats)
  }

  // 6. Lens bounds abort before any agent runs; duplicate keys abort.
  {
    for (const [n, reason] of [[1, 'below-floor'], [4, 'over-cap']]) {
      const r = await run(lenses(n), () => ({ findings: [] }))
      check(`${n} lens(es) → ${reason}, zero agents`, r.result.reason === reason && r.calls.length === 0, r.result)
    }
    const r = await run({ lenses: [{ key: 'x' }, { key: 'x' }] }, () => ({ findings: [] }))
    check('duplicate lens keys abort', r.result.reason === 'duplicate-lens' && r.calls.length === 0, r.result)
  }

  // 7. A dead finder is a named coverage gap, not "no findings".
  {
    const r = await run(lenses(3), (label) => (label === 'find:l2' ? undefined : label.startsWith('find:') ? { findings: [] } : undefined))
    check('dead finder → lensesFailed', r.result.lensesFailed.join() === 'l2', r.result)
  }

  // 8. Isolation switch, PAL lens brief, stringified args.
  {
    const script = (label) => (label.startsWith('find:') ? { findings: [finding('a.js', 1, 'high')] } : verdict('confirmed'))
    const iso = await run(lenses(2), script)
    check('default verifier isolation is worktree', iso.calls.find((c) => c.label.startsWith('verify:'))?.opts.isolation === 'worktree', iso.calls.map((c) => c.opts))
    const none = await run({ ...lenses(2), verifyIsolation: 'none' }, script)
    check('verifyIsolation none → no isolation', !('isolation' in none.calls.find((c) => c.label.startsWith('verify:')).opts), none.calls.map((c) => c.opts))
    const pal = await run({ lenses: [{ key: 'pal:m1', finder: { pal: 'm1', tool: 'codereview' } }, { key: 'l2', prompt: 'p' }] }, script)
    const p = pal.calls.find((c) => c.label === 'find:pal:m1')?.prompt ?? ''
    check('PAL lens brief loads the PAL tool with the model', p.includes('mcp__pal__codereview') && p.includes('"m1"'), p.slice(0, 200))
    const str = await run(JSON.stringify({ ...lenses(2), verifyCap: '1' }), script)
    check('stringified args parse and verifyCap "1" holds', str.result.stats?.verifyCap === 1, str.result)
    check('every agent pins opus + effort', [...iso.calls, ...pal.calls].every((c) => c.opts.model === 'opus' && c.opts.effort), iso.calls.map((c) => c.opts))
  }
} else {
  const base = {
    spec_path: '/tmp/x/spec.md',
    lenses: [{ key: 'format', attack: 'a' }, { key: 'ripple', attack: 'b' }],
  }
  const design = (extra = {}) => ({ spec_path: '/tmp/x/spec.md', summary: 's', changes: [], done_criteria: [], risks: [], experiments: [], decisions_for_user: [], ...extra })
  const review = (n) => ({ verdict: n ? 'sound-with-fixes' : 'sound', issues: Array.from({ length: n }, (_, i) => ({ target: `§${i}`, problem: `p${i}`, evidence: 'e', severity: 'major', fix: 'f' })), checked: ['x'] })

  // 1. Draft → both reviews → one revise that sees every review.
  {
    const r = await run(base, (label) =>
      label === 'architect:draft' ? design() : label === 'review:format' ? review(1) : label === 'review:ripple' ? review(2)
        : design({ resolution: [] }))
    check('happy path → revised', r.result.status === 'revised', r.result.status)
    check('order: draft, reviews, revise', r.labels.join() === 'architect:draft,review:format,review:ripple,architect:revise', r.labels)
    const rp = r.calls.find((c) => c.label === 'architect:revise').prompt
    check('revise reads every review (barrier)', rp.includes('REVIEW: format') && rp.includes('REVIEW: ripple'), rp.slice(-300))
    check('draft is xhigh, others high', r.calls.every((c) => c.opts.model === 'opus' && c.opts.effort === (c.label === 'architect:draft' ? 'xhigh' : 'high')), r.calls.map((c) => c.opts))
  }
  // 2. Guards abort before any agent runs.
  {
    const cases = [
      [{ ...base, lenses: base.lenses.slice(0, 1) }, 'below-floor'],
      [{ ...base, lenses: [...base.lenses, { key: 'c' }, { key: 'd' }] }, 'over-cap'],
      [{ ...base, spec_path: 'spec.md' }, 'no-spec-path'],
    ]
    for (const [a, reason] of cases) {
      const r = await run(a, () => design())
      check(`${reason} aborts with zero agents`, r.result.reason === reason && r.calls.length === 0, r.result)
    }
  }
  // 3. A dead drafter stops the run: nothing to review.
  {
    const r = await run(base, (label) => (label === 'architect:draft' ? undefined : review(1)))
    check('dead draft → abort, no reviewers', r.result.reason === 'draft-failed' && r.labels.join() === 'architect:draft', r.labels)
  }
  // 4. No surviving review → unreviewed, never "clean".
  {
    const r = await run(base, (label) => (label === 'architect:draft' ? design() : undefined))
    check('all reviewers dead → unreviewed, no revise', r.result.status === 'unreviewed' && !r.labels.includes('architect:revise'), r.result)
  }
  // 5. Zero issues → clean, no revise; revise:false → reviewed, no revise.
  {
    const clean = await run(base, (label) => (label === 'architect:draft' ? design() : review(0)))
    check('zero issues → clean, no revise', clean.result.status === 'clean' && !clean.labels.includes('architect:revise'), clean.result.status)
    const off = await run({ ...base, revise: false }, (label) => (label === 'architect:draft' ? design() : review(1)))
    check('revise:false → reviewed, no revise', off.result.status === 'reviewed' && !off.labels.includes('architect:revise'), off.result.status)
  }
  // 6. One dead reviewer: the gap is named and revise still runs on the rest.
  {
    const r = await run(base, (label) =>
      label === 'architect:draft' ? design() : label === 'review:format' ? undefined : label === 'review:ripple' ? review(1) : design())
    check('dead reviewer → reviewsFailed, revise runs', r.result.reviewsFailed.join() === 'format' && r.result.status === 'revised', r.result)
  }
}

process.exit(failed ? 1 : 0)
