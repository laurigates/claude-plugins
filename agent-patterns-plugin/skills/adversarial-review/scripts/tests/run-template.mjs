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
  let inflight = 0
  let peak = 0
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt, opts })
    // Yield once so agents started together overlap and `peak` measures concurrency.
    peak = Math.max(peak, ++inflight)
    await new Promise((res) => setTimeout(res, 0))
    inflight--
    const r = script(opts.label, prompt)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, argsIn)
  return { result, calls, labels: calls.map((c) => c.label), peak }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}

const finding = (file, line, severity, title = `${file}:${line}`) => ({
  title, file, line, severity, claim: `claim ${title}`, failure_scenario: `fails ${title}`, suggested_fix: `fix ${title}`,
})
const verdict = (v, severity = 'medium', extra = {}) => ({
  verdict: v, evidence: 'ran it', ...(v === 'refuted' ? {} : { reproduction: 'input x → wrong y' }),
  corrected_claim: '', fix_recommendation: '', severity, distinct_also: [], ...extra,
})
const CLAIM_KEYS = ['title', 'file', 'line', 'severity', 'claim', 'failure_scenario', 'suggested_fix']
const isClaimShaped = (c) => CLAIM_KEYS.every((k) => k in c) && Array.isArray(c.raised_by) && !('verdict' in c)

if (basename(file).startsWith('find-verify')) {
  const TARGET = { repo: '/r', ref: 'feat/x' }
  const lenses = (n) => ({ target: TARGET, lenses: Array.from({ length: n }, (_, i) => ({ key: `l${i + 1}`, prompt: 'p' })) })

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
    const second = await run({ target: TARGET, claims, verifyCap: 6 }, (label) => (label.startsWith('verify:') ? verdict('partially') : undefined))
    check('verify-only spawns no finder', !second.labels.some((l) => l.startsWith('find:')), second.labels)
    check('verify-only verifies every claim', second.labels.filter((l) => l.startsWith('verify:')).length === claims.length, second.labels)
    const back = second.result.partially.map(({ control, verdict: _v, ...c }) => c)
    check('claims round-trip unchanged', JSON.stringify(back) === JSON.stringify(claims), { back, claims })
    check('raised_by survives the round trip', back[0]?.raised_by.join() === 'l1,l2', back)
    const empty = await run({ target: TARGET, claims: [] }, () => verdict('confirmed'))
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
    const pal = await run({ target: TARGET, lenses: [{ key: 'pal:m1', finder: { pal: 'm1', tool: 'codereview' } }, { key: 'l2', prompt: 'p' }] }, script)
    const p = pal.calls.find((c) => c.label === 'find:pal:m1')?.prompt ?? ''
    check('PAL lens brief loads the PAL tool with the model', p.includes('mcp__pal__codereview') && p.includes('"m1"'), p.slice(0, 200))
    const str = await run(JSON.stringify({ ...lenses(2), verifyCap: '1' }), script)
    check('stringified args parse and verifyCap "1" holds', str.result.stats?.verifyCap === 1, str.result)
    check('every agent pins opus + effort high', [...iso.calls, ...none.calls, ...pal.calls].every((c) => c.opts.model === 'opus' && c.opts.effort === 'high'), iso.calls.map((c) => c.opts))
  }

  // 9. Two different defects at one file:line: the merged-away claim rides in
  //    `also`, the verifier sees it, and one it calls distinct comes back
  //    unverified instead of vanishing (review F1).
  {
    const script = (distinct) => (label) => {
      if (label === 'find:l1') return { findings: [finding('a.js', 7, 'low', 'off-by-one'), finding('a.js', 7, 'low', 'null deref')] }
      if (label === 'find:l2') return { findings: [finding('a.js', 7, 'high', 'race')] }
      if (label.startsWith('verify:')) return distinct === undefined ? verdict('confirmed', 'high', { distinct_also: undefined }) : verdict('confirmed', 'high', { distinct_also: distinct })
    }
    // also = [null deref, off-by-one]: the race kept, the earlier entries folded in order.
    const r = await run(lenses(2), script([0]))
    const vp = r.calls.find((c) => c.label.startsWith('verify:'))?.prompt ?? ''
    check('same file:line → one verifier', r.labels.filter((l) => l.startsWith('verify:')).length === 1, r.labels)
    check('verifier prompt lists the merged-away claims', vp.includes('off-by-one') && vp.includes('null deref') && vp.includes('distinct_also'), vp.slice(-600))
    const kept = r.result.confirmed[0]
    check('kept entry is the most severe claim', kept?.title === 'race', kept)
    check('same-defect claim stays on the kept entry', kept?.also?.length === 1 && kept.also[0].title === 'off-by-one', kept?.also)
    const split = r.result.unverified
    check('distinct claim → unverified, claim-shaped, at the same location', split.length === 1 && split[0].title === 'null deref' && split[0].file === 'a.js' && split[0].line === 7 && isClaimShaped(split[0]), split)
    const silent = await run(lenses(2), script(undefined))
    check('verifier silent on `also` → failed verifier, claim unverified', silent.result.verifierFailed.join() === 'a.js:7' && silent.result.unverified?.[0]?.also?.length === 2, silent.result)
    const allSplit = await run(lenses(2), script([0, 1]))
    check('a lens whose only claim split off leaves raised_by', allSplit.result.confirmed[0]?.raised_by.join() === 'l2', allSplit.result.confirmed[0])
  }

  // 10. verifyCap / controlSample null or '' mean the default, not 0 (review F2).
  {
    const script = (label) => (label.startsWith('find:') ? { findings: [finding('a.js', 1, 'high')] } : verdict('refuted'))
    for (const v of [null, '']) {
      const r = await run({ ...lenses(2), verifyCap: v, controlSample: v }, script)
      check(`verifyCap ${JSON.stringify(v)} → default 6, verifies`, r.result.stats.verifyCap === 6 && r.result.refuted.length === 1, r.result.stats)
    }
  }

  // 11. A missing ref aborts before any agent; an isolated verifier detaches at
  //     the SHA the ref resolves to in the reviewed repo, never at its own HEAD (review F3).
  {
    const r = await run({ lenses: lenses(2).lenses, target: { repo: '/r' } }, () => ({ findings: [] }))
    check('no target.ref → no-ref abort, zero agents', r.result.reason === 'no-ref' && r.calls.length === 0, r.result)
    const iso = await run(lenses(2), (label) => (label.startsWith('find:') ? { findings: [finding('a.js', 1, 'high')] } : verdict('refuted')))
    const vp = iso.calls.find((c) => c.label.startsWith('verify:'))?.prompt ?? ''
    check('verifier resolves the ref in the reviewed repo', vp.includes("git -C /r rev-parse --verify 'feat/x^{commit}'") && vp.includes('switch --detach "$SHA"'), vp)
  }

  // 12. Status names a coverage gap: every finder dead → unreviewed (review F4).
  {
    const dead = await run(lenses(2), () => undefined)
    check('every finder dead → status unreviewed', dead.result.status === 'unreviewed', dead.result)
    const one = await run(lenses(2), (label) => (label === 'find:l1' ? { findings: [] } : undefined))
    check('one finder dead → status partial', one.result.status === 'partial', one.result)
    const ok = await run(lenses(2), () => ({ findings: [] }))
    check('every finder answered → status reviewed', ok.result.status === 'reviewed', ok.result)
  }

  // 13. Verifiers run in waves of ≤ 5, and every picked finding still gets one (review F5).
  {
    const fs = Array.from({ length: 8 }, (_, i) => finding(`f${i}.js`, 1, 'high'))
    const r = await run({ ...lenses(2), verifyCap: 6, controlSample: 2 }, (label) =>
      label === 'find:l1' ? { findings: fs } : label === 'find:l2' ? { findings: [] } : verdict('refuted'))
    const v = r.labels.filter((l) => /^(verify|control):/.test(l))
    check('8 verifiers all run', v.length === 8 && r.result.refuted.length === 8, r.labels)
    check('no more than 5 verifiers in flight', r.peak <= 5, r.peak)
  }

  // 14. Refute-by-default in code: confirmed/partially without a reproduction is
  //     a failed verifier, not a confirmation (review F10).
  {
    const r = await run(lenses(2), (label) => {
      if (label === 'find:l1') return { findings: [finding('a.js', 1, 'high'), finding('b.js', 1, 'high')] }
      if (label === 'find:l2') return { findings: [] }
      if (label === 'verify:1:l1') return verdict('confirmed', 'high', { reproduction: '' })
      if (label === 'verify:2:l1') return verdict('partially', 'high', { reproduction: undefined })
    })
    check('unreproduced confirmations → unverified', r.result.confirmed.length === 0 && r.result.partially.length === 0 && r.result.unverified.length === 2, r.result)
    check('unreproduced confirmations → verifierFailed', r.result.verifierFailed.length === 2, r.result.verifierFailed)
  }
} else {
  const base = {
    spec_path: '/tmp/x/spec.md',
    lenses: [{ key: 'format', attack: 'a' }, { key: 'ripple', attack: 'b' }],
  }
  const design = (extra = {}) => ({ spec_path: '/tmp/x/spec.md', summary: 's', changes: [], done_criteria: [], risks: [], experiments: [], decisions_for_user: [], ...extra })
  const review = (n, verdict = n ? 'sound-with-fixes' : 'sound') => ({ verdict, issues: Array.from({ length: n }, (_, i) => ({ target: `§${i}`, problem: `p${i}`, evidence: 'e', severity: 'major', fix: 'f' })), checked: ['x'] })
  const rows = (lens, n) => Array.from({ length: n }, (_, i) => ({ lens, issue: `p${i}`, decision: 'accepted', evidence: 'e' }))

  // 1. Draft → both reviews → one revise that sees every review.
  {
    const r = await run(base, (label) =>
      label === 'architect:draft' ? design() : label === 'review:format' ? review(1) : label === 'review:ripple' ? review(2)
        : design({ resolution: [...rows('format', 1), ...rows('ripple', 2)] }))
    check('happy path → revised', r.result.status === 'revised', r.result.status)
    check('order: draft, reviews, revise', r.labels.join() === 'architect:draft,review:format,review:ripple,architect:revise', r.labels)
    const rp = r.calls.find((c) => c.label === 'architect:revise').prompt
    check('revise reads every review (barrier)', rp.includes('REVIEW: format') && rp.includes('REVIEW: ripple'), rp.slice(-300))
    check('draft is xhigh, others high', r.calls.every((c) => c.opts.model === 'opus' && c.opts.effort === (c.label === 'architect:draft' ? 'xhigh' : 'high')), r.calls.map((c) => c.opts))
    const opts = (l) => r.calls.find((c) => c.label === l).opts
    check('revise schema requires resolution', opts('architect:revise').schema.required.includes('resolution'), opts('architect:revise').schema.required)
    check('draft schema carries optional metrics', 'metrics' in opts('architect:draft').schema.properties && !opts('architect:draft').schema.required.includes('metrics'), opts('architect:draft').schema.required)
    // review F12: the shared preamble must not forbid the architect's spec write.
    const rv = r.calls.find((c) => c.label === 'review:format').prompt
    check('preamble carves out the spec for the architect', rv.includes('only the\nARCHITECT writes it') && !rv.includes('do not edit, stage'), rv.slice(0, 400))
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
      label === 'architect:draft' ? design() : label === 'review:format' ? undefined : label === 'review:ripple' ? review(1) : design({ resolution: rows('ripple', 1) }))
    check('dead reviewer → reviewsFailed, revise runs', r.result.reviewsFailed.join() === 'format' && r.result.status === 'revised', r.result)
  }
  // 7. A dead lens plus zero issues from the rest is not clean (review F4/F8);
  //    neither is an `unsound` verdict with no issue to act on.
  {
    const partial = await run(base, (label) => (label === 'architect:draft' ? design() : label === 'review:format' ? undefined : review(0)))
    check('one dead reviewer + zero issues → partial, no revise', partial.result.status === 'partial' && !partial.labels.includes('architect:revise'), partial.result)
    const odd = await run(base, (label) => (label === 'architect:draft' ? design() : label === 'review:format' ? review(0, 'unsound') : review(0)))
    check('unsound with no issues → inconsistent', odd.result.status === 'inconsistent' && odd.result.notSound.join() === 'format', odd.result)
  }
  // 8. A revise that skips resolution rows is not "revised" (review F9).
  {
    const script = (res) => (label) =>
      label === 'architect:draft' ? design() : label === 'review:format' ? review(1) : label === 'review:ripple' ? review(2) : design(res)
    const none = await run(base, script({}))
    check('revise without resolution → revised-incomplete', none.result.status === 'revised-incomplete' && none.result.unresolved.length === 2, none.result)
    const short = await run(base, script({ resolution: [...rows('format', 1), ...rows('ripple', 1)] }))
    check('one lens short a row → revised-incomplete naming it', short.result.status === 'revised-incomplete' && short.result.unresolved.map((u) => u.lens).join() === 'ripple', short.result.unresolved)
  }
}

process.exit(failed ? 1 : 0)
