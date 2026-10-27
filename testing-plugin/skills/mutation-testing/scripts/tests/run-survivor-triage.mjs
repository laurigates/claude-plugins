// Run survivor-triage.workflow.js against a stub runtime and assert on its result.
// Usage: node run-survivor-triage.mjs <survivor-triage.workflow.js>
// Each scenario scripts agent() returns by label kind (`triage` | `verify`) and unit.
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)

const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))
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
const sleep = (ms) => new Promise((res) => setTimeout(res, ms))

// script(kind, unit, prompt) → value | undefined (undefined = the agent died → null)
// delay(kind, unit) → ms before the agent "returns", to model finishing order.
async function run(argsIn, script, delay = () => 0) {
  const calls = []
  const prompts = {}
  const agent = async (prompt, opts) => {
    const [kind, ...rest] = opts.label.split(':')
    const unit = rest.join(':')
    calls.push({ kind, unit, model: opts.model, effort: opts.effort })
    prompts[opts.label] = prompt
    await sleep(delay(kind, unit))
    const r = script(kind, unit, prompt)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, argsIn)
  return { result, calls, prompts }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}

const finding = (file, lines, severity, kind = 'source-bug') => ({
  kind, severity, file, lines, summary: `${kind} at ${file}:${lines}`, evidence: 'mutants survive', suggested_test: '',
})
const triage = (cluster, findings) => ({ cluster, findings, noise: 'n', integration_covered: '' })
const verdict = (v, extra = {}) => ({
  verdict: v, severity: 'medium', reasoning: 'r', reproduction: v === 'refuted' ? '' : 'input → wrong output',
  reachable_in_production: v !== 'refuted', ...extra,
})
const base = (clusters, extra = {}) => ({
  json: '/abs/reports/mutation/mutation.json',
  worktree: '/abs/checkout',
  clusters: clusters.map((key) => ({ key, files: [`src/${key}.ts`] })),
  ...extra,
})
const verifyUnits = (r) => r.calls.filter((c) => c.kind === 'verify').map((c) => c.unit)
const claimKey = (c) => `${c.file}:${c.lines}`

// Cluster `a` holds only low claims and returns first; `b` (high) and `c` (medium)
// return later. A first-come cap (the shared `slots` counter of the ad-hoc runs)
// would spend the verifiers on `a`'s lows.
const threeClusters = (k, u) =>
  k === 'triage'
    ? u === 'a' ? triage('a', [finding('src/a.ts', '1', 'low'), finding('src/a.ts', '2', 'low'), finding('src/a.ts', '3', 'low')])
      : u === 'b' ? triage('b', [finding('src/b.ts', '10', 'high'), finding('src/b.ts', '11', 'low', 'test-gap')])
        : triage('c', [finding('src/c.ts', '20', 'medium'), finding('src/c.ts', '21', 'medium')])
    : verdict('held')
const lateUnlessA = (k, u) => (k === 'triage' && u !== 'a' ? 20 : 0)

// 1. Severity-ranked cap across clusters, not first-come.
{
  const r = await run(base(['a', 'b', 'c'], { verifyCap: 3 }), threeClusters, lateUnlessA)
  const verified = r.result.verified.map((v) => v.claim.severity)
  check('cap goes to the highest severity across clusters', JSON.stringify(verified) === '["high","medium","medium"]', r.result.verified)
  check('exactly verifyCap skeptics', verifyUnits(r).length === 3, verifyUnits(r))
  check('the lows past the cap are returned unverified', r.result.unverified.length === 3 && r.result.unverified.every((c) => c.severity === 'low'), r.result.unverified)
  check('test-gap findings never reach a skeptic', !r.result.verified.some((v) => v.claim.kind === 'test-gap') && !r.result.unverified.some((c) => c.kind === 'test-gap'), r.result)
  check('every cluster reported', r.result.clusters.length === 3 && r.result.failedClusters.length === 0, r.result.failedClusters)
  check('triage opus/medium, skeptics opus/high', r.calls.every((c) => c.model === 'opus' && c.effort === (c.kind === 'triage' ? 'medium' : 'high')), r.calls)
}

// 2. Ties keep cluster order, then finding order (deterministic, no sort instability).
{
  const r = await run(base(['a', 'b'], { verifyCap: 2 }), (k, u) =>
    k === 'triage' ? triage(u, [finding(`src/${u}.ts`, '1', 'medium'), finding(`src/${u}.ts`, '2', 'medium')]) : verdict('held'),
    (k, u) => (k === 'triage' && u === 'a' ? 20 : 0))
  check('ties broken by cluster order, not finishing order', JSON.stringify(r.result.verified.map((v) => claimKey(v.claim))) === '["src/a.ts:1","src/a.ts:2"]', r.result.verified)
}

// 3. The unverified list is valid `args.claims`: a verify-only re-run needs no new script.
{
  const first = await run(base(['a', 'b', 'c'], { verifyCap: 3 }), threeClusters, lateUnlessA)
  const handBack = first.result.unverified
  const again = await run({ worktree: '/abs/checkout', claims: handBack }, () => verdict('held'))
  check('verify-only run spawns no triage agent', !again.calls.some((c) => c.kind === 'triage'), again.calls)
  check('verify-only run verifies every handed-back claim', verifyUnits(again).length === handBack.length && again.result.unverified.length === 0, again.result)
  check('verify-only mode is reported', again.result.mode === 'verify-only', again.result.mode)
  // Stringified args and a stringified claims array are both accepted.
  const str = await run(JSON.stringify({ worktree: '/abs/checkout', claims: JSON.stringify(handBack) }), () => verdict('held'))
  check('stringified args + claims accepted', verifyUnits(str).length === handBack.length, str.result)
}

// 4. Refute-by-default: held without a reproduction is refuted; a dead skeptic is unverified.
{
  const claims = [finding('src/x.ts', '1', 'high'), finding('src/x.ts', '2', 'high'), finding('src/x.ts', '3', 'medium')]
  const r = await run({ worktree: '/abs/checkout', claims }, (k, u, prompt) =>
    prompt.includes('src/x.ts:1') ? verdict('held', { reproduction: '  ' })
      : prompt.includes('src/x.ts:2') ? undefined
        : verdict('downgraded'))
  const byKey = Object.fromEntries(r.result.verified.map((v) => [claimKey(v.claim), v.verdict.verdict]))
  check('held without reproduction → refuted', byKey['src/x.ts:1'] === 'refuted' && r.result.held.length === 0, r.result.verified)
  check('dead skeptic → unverified, never held', r.result.unverified.some((c) => claimKey(c) === 'src/x.ts:2') && !('src/x.ts:2' in byKey), r.result)
  check('downgraded kept as downgraded', r.result.downgraded.length === 1, r.result.downgraded)
  check('refute-by-default brief in skeptic prompt', Object.values(r.prompts).every((p) => /default to refuted/i.test(p)), Object.values(r.prompts)[0])
}

// 5. A dead triage agent is a failed cluster; its claims never reach the rank.
{
  const r = await run(base(['a', 'b', 'c'], { verifyCap: 4 }), (k, u) => (k === 'triage' && u === 'b' ? undefined : threeClusters(k, u)))
  check('dead triage → failedClusters', JSON.stringify(r.result.failedClusters) === '["b"]', r.result.failedClusters)
  check('no claim from the failed cluster', !r.result.verified.some((v) => v.claim.file === 'src/b.ts'), r.result.verified)
}

// 6. The static-mutant filter reaches every triage brief, with the threshold.
{
  const r = await run(base(['a', 'b']), threeClusters)
  const briefs = Object.entries(r.prompts).filter(([l]) => l.startsWith('triage:')).map(([, p]) => p)
  check('triage briefs carry testsCompleted > 5', briefs.length === 2 && briefs.every((p) => p.includes('.testsCompleted > 5')), briefs[0])
  const r7 = await run(base(['a', 'b'], { staticMinTests: 7 }), threeClusters)
  check('staticMinTests overrides the threshold', Object.values(r7.prompts).some((p) => p.includes('.testsCompleted > 7')), null)
}

// 7. Aborts spend zero agents.
{
  const one = await run(base(['a']), threeClusters)
  check('one cluster is below the floor', one.result.abort === true && one.result.reason === 'below-floor' && one.calls.length === 0, one.result)
  const many = await run(base(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']), threeClusters)
  check('9 clusters is over the cap', many.result.reason === 'over-cap' && many.calls.length === 0, many.result)
  const noJson = await run({ ...base(['a', 'b']), json: undefined }, threeClusters)
  check('missing json aborts', noJson.result.reason === 'missing-args' && noJson.calls.length === 0, noJson.result)
  const dup = await run({ ...base(['a', 'b']), clusters: [{ key: 'a', files: ['x'] }, { key: 'a', files: ['y'] }] }, threeClusters)
  check('duplicate cluster keys abort', dup.result.reason === 'bad-clusters' && dup.calls.length === 0, dup.result)
  const badClaim = await run({ worktree: '/abs/checkout', claims: [{ file: 'a.ts' }] }, () => verdict('held'))
  check('incomplete claim aborts', badClaim.result.reason === 'bad-claims' && badClaim.calls.length === 0, badClaim.result)
}

// 8. Exactly at the cluster cap every cluster runs (a narrower slice would drop one silently).
{
  const keys = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
  const r = await run(base(keys), (k, u) => (k === 'triage' ? triage(u, []) : verdict('held')))
  check('8 clusters → 8 triage agents', r.calls.filter((c) => c.kind === 'triage').length === 8 && r.result.clusters.length === 8, r.calls.length)
}

// 9. verifyCap above the hard ceiling is clamped to it; the rest come back unverified.
{
  const claims = Array.from({ length: 9 }, (_, i) => finding('src/y.ts', String(i + 1), 'medium'))
  const r = await run({ worktree: '/abs/checkout', claims, verifyCap: 20 }, () => verdict('held'))
  check('verifyCap clamps to 6', verifyUnits(r).length === 6 && r.result.unverified.length === 3, { v: verifyUnits(r).length, u: r.result.unverified.length })
}

process.exit(failed ? 1 : 0)
