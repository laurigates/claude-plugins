// Run .claude/workflows/model-suitability-audit.workflow.js against a stub
// runtime and assert on its result. Driven by test-model-suitability-audit-workflow.sh.
// Usage: node run-workflow.mjs <model-suitability-audit.workflow.js>
//
// Each scenario scripts agent() by label prefix (classify:/verify:). The stub
// reads the FILES= / ENTRIES= line each prompt carries, so it answers for the
// paths the workflow actually sent rather than a copy of its batching logic.
import { readFileSync } from 'node:fs'

const src = readFileSync(process.argv[2], 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
const pipeline = async () => { throw new Error('pipeline() is not used by this workflow') }

async function run(argsIn, script = {}) {
  const calls = []
  const agent = async (prompt, opts) => {
    calls.push(opts)
    const kind = opts.label.split(':')[0]
    if (kind === 'classify') {
      const paths = JSON.parse(prompt.match(/^FILES=(.*)$/m)[1])
      return script.classify ? script.classify(paths, opts) : { items: paths.map((p) => item(p, 'keep')) }
    }
    const entries = JSON.parse(prompt.match(/^ENTRIES=(.*)$/m)[1])
    return script.verify ? script.verify(entries, opts) : { verdicts: entries.map((e) => vitem(e.path, 'confirm', e.classifier.verdict)), classifier_quality_notes: 'ok' }
  }
  // A throw is reported as a result so one scenario cannot take the rest down.
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, argsIn).catch((e) => ({ threw: String(e) }))
  return { result, calls }
}

const item = (path, verdict, extra = {}) => ({
  path, current_model: 'unset', verdict, target: verdict === 'keep' ? '' : 'model: haiku + effort: low',
  effort: verdict === 'keep' ? 'n/a' : 'low', confidence: 'medium', invokes_model: true, rationale: 'r', risks: [], ...extra,
})
const vitem = (path, assessment, final) => ({ path, assessment, final, target: '', effort: 'low', rationale: 'v' })

const skills = (n, prefix = 'p-plugin/skills/s') => Array.from({ length: n }, (_, i) => `${prefix}${String(i).padStart(3, '0')}/SKILL.md`)
const base = (files, extra = {}) => ({ repo: '/repo', files, model: 'haiku', date: '2026-11-01', ...extra })
const byPath = (r) => Object.fromEntries(r.result.rows.map((x) => [x.path, x]))
const ofKind = (r, k) => r.calls.filter((c) => c.label.startsWith(`${k}:`))

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${cond ? '' : ` — ${JSON.stringify(detail)?.slice(0, 600)}`}`)
  if (!cond) failed++
}

// 1. Empty args abort before any agent: the file is runnable by name.
{
  const r = await run({})
  check('empty args → abort, zero agents', r.result.abort === true && r.result.reason === 'missing-repo' && r.calls.length === 0, r)
}
// 2. Stringified args are parsed; a non-JSON string aborts.
{
  const r = await run(JSON.stringify(base(skills(3))))
  check('stringified args run', r.result.abort === false && ofKind(r, 'classify').length === 1, r.result)
  const bad = await run('{not json')
  check('non-JSON string → bad-args', bad.result.reason === 'bad-args' && bad.calls.length === 0, bad.result)
  // JSON.parse('null') is null, and A.repo on null throws instead of aborting.
  for (const s of ['null', '[]', '5']) {
    const r = await run(s)
    check(`args ${s} → bad-args, zero agents`, r.result?.reason === 'bad-args' && r.calls.length === 0, r.result)
  }
}
// 3. Argument guards all abort with zero agents.
{
  const cases = [
    [base([]), 'no-files'],
    [base(['a/SKILL.md', 'a/SKILL.md']), 'duplicate-files'],
    [base(['README.md']), 'unknown-kind'],
    [base(skills(2), { model: 'opus' }), 'bad-model'],
    [base(skills(2), { effort: 'huge' }), 'bad-effort'],
    [base(skills(2), { verifyEffort: 'huge' }), 'bad-effort'],
    [base(skills(2), { batchSize: 0 }), 'bad-batch-size'],
    [base(skills(2), { verifyBatchSize: 0 }), 'bad-batch-size'],
    [base(skills(2), { controlSample: -1 }), 'bad-control-sample'],
    [{ repo: '/repo', files: skills(2), model: 'haiku' }, 'no-artifact-path'],
    [base(skills(19), { batchSize: 1 }), 'over-cap'],
  ]
  for (const [a, reason] of cases) {
    const r = await run(a)
    check(`${reason} → abort, zero agents`, r.result.reason === reason && r.calls.length === 0, r.result)
  }
}
// 4. Exactly at the classifier cap: 18 classifiers, every file gets a row.
{
  const r = await run(base(skills(18), { batchSize: 1 }))
  check('18 batches → 18 classifiers, 18 rows', ofKind(r, 'classify').length === 18 && r.result.rows.length === 18, r.result.summary)
}
// 5. Every agent pins model and effort; classifiers run the candidate, verifiers Opus.
{
  const r = await run(base(skills(4), { model: 'sonnet', effort: 'low' }), { classify: (ps) => ({ items: ps.map((p) => item(p, 'switch')) }) })
  const cl = ofKind(r, 'classify'), vf = ofKind(r, 'verify')
  check('classifier model/effort from args', cl.every((c) => c.model === 'sonnet' && c.effort === 'low' && !c.agentType), cl)
  check('verifier is opus at high effort', vf.length === 1 && vf.every((c) => c.model === 'opus' && c.effort === 'high'), vf)
  // Without a schema the runtime returns prose, not the {items}/{verdicts} object read below.
  const enumOf = (c, list) => c.schema?.properties?.[list]?.items?.properties?.verdict?.enum
    ?? c.schema?.properties?.[list]?.items?.properties?.final?.enum
  const VERDICTS = ['switch', 'switch-stage', 'needs-test', 'keep']
  check('classifier schema requires items over the verdict enum', cl.every((c) => c.schema?.required?.includes('items') && JSON.stringify(enumOf(c, 'items')) === JSON.stringify(VERDICTS)), cl.map((c) => c.schema))
  check('verifier schema requires verdicts over the verdict enum', vf.every((c) => c.schema?.required?.includes('verdicts') && JSON.stringify(enumOf(c, 'verdicts')) === JSON.stringify(VERDICTS)), vf.map((c) => c.schema))
}
// 5b. The verifier sees the classifier's full judgement, not only its verdict:
// the rationale and risks carry the "risks listed but not acted on" signal.
{
  const seen = []
  await run(base(skills(2)), {
    classify: (ps) => ({ items: ps.map((p) => item(p, 'needs-test', { target: 't', effort: 'medium', rationale: `why ${p}`, risks: ['AskUserQuestion'] })) }),
    verify: (es) => { seen.push(...es); return { verdicts: es.map((e) => vitem(e.path, 'confirm', e.classifier.verdict)), classifier_quality_notes: 'n' } },
  })
  const full = (e) => e.role === 'candidate' && e.kind === 'skill' && e.classifier.verdict === 'needs-test' && e.classifier.target === 't'
    && e.classifier.effort === 'medium' && e.classifier.rationale === `why ${e.path}` && JSON.stringify(e.classifier.risks) === '["AskUserQuestion"]'
  check('verify entries carry role, kind and the classifier fields', seen.length === 2 && seen.every(full), seen)
}
// 6. lean puts the lean reader on classifiers only.
{
  const r = await run(base(skills(4), { lean: true }), { classify: (ps) => ({ items: ps.map((p) => item(p, 'switch')) }) })
  check('lean → agentType on classifiers', ofKind(r, 'classify').every((c) => c.agentType === 'agents-plugin:lean-reader'), r.calls)
  check('lean → no agentType on verifiers', ofKind(r, 'verify').every((c) => !c.agentType), r.calls)
}
// 7. A dead classifier leaves its files unclassified, never sampled or verified.
{
  const files = skills(4)
  const r = await run(base(files, { batchSize: 2 }), {
    classify: (ps) => (ps.includes(files[0]) ? null : { items: ps.map((p) => item(p, 'switch')) }),
  })
  const rows = byPath(r)
  check('dead classifier → unclassified', rows[files[0]].disposition === 'unclassified' && rows[files[0]].reason === 'dead-classifier', rows[files[0]])
  check('dead classifier files not verified', ofKind(r, 'verify').length === 1 && rows[files[2]].disposition === 'verified', r.result.summary)
  check('summary counts the dead classifier', r.result.summary.classifiers.dead === 1 && r.result.summary.classifier.unclassified === 2, r.result.summary)
}
// 8. Count is checked by path: an omitted path is unclassified, an invented one dropped.
{
  const files = skills(3)
  const r = await run(base(files), {
    classify: (ps) => ({ items: [item(ps[0], 'switch'), item(ps[1], 'keep'), item('x/invented/SKILL.md', 'switch')] }),
  })
  const rows = byPath(r)
  check('omitted path → unclassified', rows[files[2]].disposition === 'unclassified' && rows[files[2]].reason === 'omitted-by-classifier', rows[files[2]])
  check('invented path dropped and reported', r.result.invented.length === 1 && !rows['x/invented/SKILL.md'], r.result.invented)
}
// 9. A dead verifier never reads as a confirmation.
{
  const r = await run(base(skills(3)), { classify: (ps) => ({ items: ps.map((p) => item(p, 'switch')) }), verify: () => null })
  const s = r.result.summary
  check('dead verifier → unverified', r.result.rows.every((x) => x.disposition === 'unverified' && x.reason === 'dead-verifier'), r.result.rows)
  check('dead verifier → zero confirms', s.candidates.confirm === 0 && s.candidates.unverified === 3 && s.verifiers.dead === 1, s)
}
// 9b. An empty list for a non-empty batch is a dead agent, not a run of omissions.
{
  const files = skills(4)
  const r = await run(base(files, { batchSize: 2 }), {
    classify: (ps) => (ps.includes(files[0]) ? { items: [] } : { items: ps.map((p) => item(p, 'switch')) }),
    verify: () => ({ verdicts: [], classifier_quality_notes: 'nothing' }),
  })
  const rows = byPath(r), s = r.result.summary
  check('empty items → dead-classifier', rows[files[0]].reason === 'dead-classifier' && s.classifiers.dead === 1, [rows[files[0]], s.classifiers])
  check('empty verdicts → dead-verifier', rows[files[2]].reason === 'dead-verifier' && s.verifiers.dead === 1, [rows[files[2]], s.verifiers])
}
// 10. A verifier that omits an entry leaves it unverified.
{
  const files = skills(2)
  const r = await run(base(files), {
    classify: (ps) => ({ items: ps.map((p) => item(p, 'switch')) }),
    verify: (es) => ({ verdicts: [vitem(es[0].path, 'reject', 'keep')], classifier_quality_notes: 'n' }),
  })
  const rows = byPath(r)
  check('omitted entry → unverified', rows[files[1]].disposition === 'unverified' && rows[files[1]].reason === 'omitted-by-verifier', rows[files[1]])
  check('reject counted', r.result.summary.candidates.reject === 1, r.result.summary.candidates)
}
// 11. Control sample: default size, deterministic picks, no-invocation keeps excluded.
{
  const files = skills(21)
  const script = { classify: (ps) => ({ items: ps.map((p, i) => item(p, 'keep', { invokes_model: p !== files[0] })) }) }
  const a = await run(base(files), script)
  const b = await run(base(files), script)
  const pick = (r) => r.result.rows.filter((x) => x.role === 'control').map((x) => x.path)
  check('default control sample = max(3, ceil(20/7))', pick(a).length === 3, pick(a))
  check('control sample is deterministic', JSON.stringify(pick(a)) === JSON.stringify(pick(b)), [pick(a), pick(b)])
  check('no-invocation keep never sampled', !pick(a).includes(files[0]), pick(a))
  check('unsampled keeps recorded', a.result.rows.filter((x) => x.disposition === 'keep-unsampled').length === 18, a.result.summary)
  const zero = await run(base(files, { controlSample: 0 }), script)
  check('controlSample 0 → no verifier', ofKind(zero, 'verify').length === 0 && zero.result.summary.control.sampled === 0, zero.result.summary)
  const two = await run(base(files, { controlSample: 2 }), script)
  check('controlSample 2 → 2 controls', pick(two).length === 2, pick(two))
}
// 12. Control held vs flipped is counted from the verifier's final verdict.
{
  const files = skills(6)
  const r = await run(base(files, { controlSample: 2 }), {
    classify: (ps) => ({ items: ps.map((p) => item(p, 'keep')) }),
    verify: (es) => ({ verdicts: es.map((e, i) => vitem(e.path, i === 0 ? 'reject' : 'confirm', i === 0 ? 'needs-test' : 'keep')), classifier_quality_notes: 'n' }),
  })
  const c = r.result.summary.control
  check('control held 1, flipped 1', c.sampled === 2 && c.held === 1 && c.flipped === 1, c)
}
// 13. Over the verifier cap: 8 verifiers run, the remainder is unverified, not dropped.
{
  const files = skills(10)
  const r = await run(base(files, { verifyBatchSize: 1, controlSample: 0 }), { classify: (ps) => ({ items: ps.map((p) => item(p, 'switch')) }) })
  const over = r.result.rows.filter((x) => x.reason === 'over-verifier-cap')
  check('verifier cap → 8 verifiers', ofKind(r, 'verify').length === 8, ofKind(r, 'verify').length)
  check('over-cap entries unverified, not dropped', over.length === 2 && r.result.rows.length === 10, r.result.summary)
  check('over-cap is not a dead verifier', r.result.summary.verifiers.dead === 0, r.result.summary.verifiers)
}
// 14. Artifact path and markdown.
{
  const r = await run(base(skills(2), { model: 'claude-haiku-5-5' }), { classify: (ps) => ({ items: ps.map((p) => item(p, 'switch')) }) })
  check('date → default artifact path', r.result.artifactPath === 'docs/audits/haiku-5-5-model-suitability-2026-11-01.md', r.result.artifactPath)
  const own = await run({ ...base(skills(2)), artifact: 'tmp/x.md' })
  check('explicit artifact wins', own.result.artifactPath === 'tmp/x.md', own.result.artifactPath)
  const md = r.result.markdown
  check('markdown has results and adjudication', md.includes('## Results') && md.includes('## Adjudication') && md.includes('Opus confirmed 2 of 2'), md.slice(0, 400))
}
// 15. Kinds are inferred from the path and grouped in batches by kind.
{
  const files = ['.github/workflows/a.yml', 'x-plugin/agents/b.md', 'x-plugin/skills/c/workflows/d.workflow.js', 'x-plugin/skills/c/SKILL.md']
  const r = await run(base(files, { batchSize: 1 }))
  const kinds = r.result.rows.map((x) => x.kind)
  check('kinds inferred and ordered', JSON.stringify(kinds) === JSON.stringify(['skill', 'agent', 'harness', 'gh-workflow']), kinds)
}

process.exit(failed ? 1 : 0)
