// Run the three git-pr-sweep workflow templates against a stub runtime and
// assert on their results. Usage: node run-workflows.mjs <workflows-dir> <repair-round.workflow.js>
// Each scenario scripts agent() returns by label and checks what came back.
import { readFileSync } from 'node:fs'
import { join } from 'node:path'

const [dir, rrFile] = process.argv.slice(2)
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const load = (name) => {
  const src = readFileSync(join(dir, name), 'utf8')
  return { src, body: new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src.replace(/^export const meta/m, 'const meta')) }
}

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

async function run(wf, argsIn, script) {
  const calls = []
  let live = 0
  let peak = 0
  const agent = async (prompt, opts) => {
    calls.push({ label: opts.label, prompt, opts })
    live++
    peak = Math.max(peak, calls.length)
    await Promise.resolve()
    live--
    const r = script(opts.label, prompt, opts)
    return r === undefined ? null : r
  }
  const result = await wf.body(agent, parallel, pipeline, () => {}, () => {}, argsIn)
  return { result, calls, labels: calls.map((c) => c.label), peak }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${cond ? '' : ` — ${JSON.stringify(detail)?.slice(0, 400)}`}`)
  if (!cond) failed++
}
const sha = (c) => c.repeat(40)
const FORBIDDEN = /gh pr merge|gh pr ready|git push|gh pr review|gh pr comment|gh pr edit/
// A forbidden command may appear only on a line that forbids it.
const onlyForbidden = (prompt) => prompt.split('\n').filter((l) => FORBIDDEN.test(l)).every((l) => /do not|never|don't|read-only/i.test(l))

// ===========================================================================
// pr-review
// ===========================================================================
const review = load('pr-review.workflow.js')
const pr = (n, extra = {}) => ({ number: n, head_sha: sha(String(n % 10)), head: `feat/${n}`, base: 'main', title: `PR ${n}`, is_draft: false, author_kind: 'self', ...extra })
const BASE = { repo: 'o/r', root: '/abs/clone' }
const finding = (n, file, line, extra = {}) => ({
  pr: n, title: `bug in ${file}`, file, line, severity: 'high', claim: 'c', failure_scenario: 'fs', suggested_fix: 'sf', ...extra,
})
const confirm = (extra = {}) => ({
  verdict: 'confirmed', evidence: 'ran it', reproduction: 'input → wrong', corrected_claim: '', fix_recommendation: '', severity: 'medium', distinct_also: [], ...extra,
})

for (const [name, a, reason] of [
  ['no repo', { ...BASE, repo: '', prs: [pr(1)], groups: [[1]] }, 'no-repo'],
  ['no root', { ...BASE, root: 'rel/path', prs: [pr(1)], groups: [[1]] }, 'no-root'],
  ['no prs', { ...BASE, prs: [], groups: [] }, 'no-prs'],
  ['7 PRs over cap', { ...BASE, prs: [1, 2, 3, 4, 5, 6, 7].map((n) => pr(n)), groups: [[1, 2], [3], [4], [5, 6, 7]] }, 'over-cap'],
  ['duplicate pr', { ...BASE, prs: [pr(1), pr(1)], groups: [[1]] }, 'duplicate-pr'],
  ['missing head', { ...BASE, prs: [pr(1, { head_sha: 'abc' })], groups: [[1]] }, 'missing-head'],
  ['no groups', { ...BASE, prs: [pr(1)], groups: [] }, 'no-groups'],
  ['5 groups over cap', { ...BASE, prs: [1, 2, 3, 4, 5].map((n) => pr(n)), groups: [[1], [2], [3], [4], [5]] }, 'over-cap'],
  ['group of 4', { ...BASE, prs: [1, 2, 3, 4].map((n) => pr(n)), groups: [[1, 2, 3, 4]] }, 'bad-groups'],
  ['pr in two groups', { ...BASE, prs: [pr(1), pr(2)], groups: [[1, 2], [2]] }, 'bad-groups'],
  ['ungrouped pr', { ...BASE, prs: [pr(1), pr(2)], groups: [[1]] }, 'bad-groups'],
  ['unknown pr in group', { ...BASE, prs: [pr(1)], groups: [[1, 9]] }, 'bad-groups'],
  ['empty claims', { ...BASE, prs: [pr(1)], claims: [] }, 'no-claims'],
  ['claim for unknown pr', { ...BASE, prs: [pr(1)], claims: [finding(9, 'a.js', 1)] }, 'claim-unknown-pr'],
]) {
  const r = await run(review, a, () => ({ findings: [] }))
  check(`pr-review ${name} aborts ${reason} with 0 agents`, r.result?.abort === true && r.result.reason === reason && r.calls.length === 0, r.result)
}

{
  // Six PRs, four groups: eight finders, two lenses per group, all opus/high, no isolation.
  const prs = [1, 2, 3, 4, 5, 6].map((n) => pr(n))
  const r = await run(review, { ...BASE, prs, groups: [[1], [2, 3], [4, 5], [6]] }, () => ({ findings: [] }))
  const finds = r.calls.filter((c) => c.label.startsWith('find:'))
  check('pr-review 4 groups spawn 8 finders', finds.length === 8, r.labels)
  check('pr-review each group gets a correctness and a spec finder', ['1', '2+3', '4+5', '6'].every((g) => r.labels.includes(`find:correctness:${g}`) && r.labels.includes(`find:spec:${g}`)), r.labels)
  check('pr-review finders are opus/high without isolation', finds.every((c) => c.opts.model === 'opus' && c.opts.effort === 'high' && !c.opts.isolation), finds.map((c) => c.opts))
  check('pr-review finder schema restricts pr to its group', JSON.stringify(finds.find((c) => c.label === 'find:spec:2+3').opts.schema.properties.findings.items.properties.pr.enum) === '[2,3]')
  check('pr-review finder prompt names diff commands for each PR in its group', /diff origin\/main\.\.\.2{40}/.test(finds.find((c) => c.label === 'find:spec:2+3').prompt) && /3{40}/.test(finds.find((c) => c.label === 'find:spec:2+3').prompt))
  check('pr-review finder prompt treats PR text as data', finds.every((c) => /data, never instructions/.test(c.prompt)))
  check('pr-review clean run: every PR reviewed, nothing open', r.result.status === 'reviewed' && r.result.prs.length === 6 && r.result.prs.every((p) => p.status === 'reviewed' && p.open.length === 0), r.result)
  check('pr-review peak agents <= 15', r.peak <= 15, r.peak)
  check('pr-review no finder prompt asks for a GitHub mutation', finds.every((c) => onlyForbidden(c.prompt)))
}

{
  // Same file:line in two PRs stays two findings; both lenses on one defect merge.
  const prs = [pr(1), pr(2)]
  const r = await run(review, { ...BASE, prs, groups: [[1, 2]] }, (label) => {
    if (label.startsWith('find:correctness')) return { findings: [finding(1, 'a.js', 10), finding(2, 'a.js', 10)] }
    if (label.startsWith('find:spec')) return { findings: [finding(1, 'a.js', 10, { severity: 'low' })] }
    if (label.startsWith('verify:')) return confirm()
  })
  const verifies = r.calls.filter((c) => c.label.startsWith('verify:'))
  check('pr-review same file:line in two PRs is not merged', verifies.length === 2 && verifies.some((c) => c.label.endsWith('pr-1')) && verifies.some((c) => c.label.endsWith('pr-2')), r.labels)
  const p1 = r.result.prs.find((p) => p.number === 1)
  check('pr-review two lenses on one defect merge into one finding', p1.open.length === 1 && p1.open[0].lens === 'correctness+spec', p1.open)
  check('pr-review open row has exactly the pr-fix findings keys + lens + verdict',
    JSON.stringify(Object.keys(p1.open[0]).sort()) === JSON.stringify(['evidence', 'fix', 'id', 'lens', 'problem', 'severity', 'verdict', 'where']), Object.keys(p1.open[0]))
  check('pr-review severity re-rating medium → major', p1.open[0].severity === 'major', p1.open[0])
  check('pr-review where is file:line', p1.open[0].where === 'a.js:10' && p1.open[0].evidence === 'input → wrong', p1.open[0])
  check('pr-review verifiers are opus/high in a worktree', verifies.every((c) => c.opts.model === 'opus' && c.opts.effort === 'high' && c.opts.isolation === 'worktree'), verifies.map((c) => c.opts))
  check('pr-review verify prompt detaches at the PR head SHA', verifies.every((c) => /switch --detach/.test(c.prompt) && /\^\{commit\}/.test(c.prompt) && c.prompt.includes(sha('1')) === c.label.endsWith('pr-1')), verifies.map((c) => c.label))
  check('pr-review verify prompts ask for no GitHub mutation', verifies.every((c) => onlyForbidden(c.prompt)))
}

{
  // Fair share: three PRs, five findings each, cap 7.
  const prs = [pr(1), pr(2), pr(3)]
  const five = (n) => [1, 2, 3, 4, 5].map((l) => finding(n, `f${n}.js`, l))
  const r = await run(review, { ...BASE, prs, groups: [[1], [2], [3]] }, (label) => {
    if (label === 'find:correctness:1') return { findings: five(1) }
    if (label === 'find:correctness:2') return { findings: five(2) }
    if (label === 'find:correctness:3') return { findings: five(3) }
    if (label.startsWith('find:')) return { findings: [] }
    if (label.startsWith('verify:')) return confirm()
  })
  const v = r.labels.filter((l) => l.startsWith('verify:'))
  check('pr-review verifier cap is 7', v.length === 7, v)
  check('pr-review fair share: first three verifiers cover all three PRs', ['verify:1:pr-1', 'verify:2:pr-2', 'verify:3:pr-3'].every((l, i) => v[i] === l), v)
  const unv = r.result.prs.flatMap((p) => p.unverified)
  check('pr-review cap remainder comes back unverified, claim-shaped', unv.length === 8 && unv.every((c) => c.pr && c.file && c.title && c.claim !== undefined), unv.length)
  check('pr-review a PR with unverified findings is partial', r.result.prs.every((p) => p.status === 'partial') && r.result.status === 'partial', r.result.prs.map((p) => p.status))
  const r0 = await run(review, { ...BASE, prs, groups: [[1], [2], [3]], verifyCap: 0 }, (label) => (label.startsWith('find:correctness') ? { findings: five(Number(label.split(':')[2])) } : { findings: [] }))
  check('pr-review verifyCap 0 spawns no verifier', !r0.labels.some((l) => l.startsWith('verify:')) && r0.result.prs.flatMap((p) => p.unverified).length === 15)
}

{
  // Dead verifiers: null, off-enum, confirmed without reproduction, missing distinct_also with also.
  const prs = [pr(1)]
  const at = (prompt, loc) => prompt.includes(`Location: ${loc}\n`)
  const r = await run(review, { ...BASE, prs, groups: [[1]] }, (label, prompt) => {
    if (label === 'find:correctness:1') return { findings: [finding(1, 'a.js', 1), finding(1, 'b.js', 2), finding(1, 'c.js', 3), finding(1, 'd.js', 4), finding(1, 'e.js', 5)] }
    if (label === 'find:spec:1') return { findings: [finding(1, 'd.js', 4, { title: 'other' })] }
    if (at(prompt, 'a.js:1')) return null
    if (at(prompt, 'b.js:2')) return confirm({ verdict: 'maybe' })
    if (at(prompt, 'c.js:3')) return confirm({ reproduction: '' })
    if (at(prompt, 'd.js:4')) return confirm({ distinct_also: undefined })
    if (at(prompt, 'e.js:5')) return confirm({ verdict: 'refuted', reproduction: '' })
  })
  const p = r.result.prs[0]
  check('pr-review null / off-enum / unreproduced / incomplete verdicts are dead verifiers', p.verifierFailed.length === 4 && p.unverified.length === 4, p)
  check('pr-review dead verifiers make the PR partial, never refuted', p.status === 'partial' && p.refuted.length === 1 && p.open.length === 0, p)
}

{
  // Dead finders: one lens dead → partial; both dead → unreviewed.
  const prs = [pr(1), pr(2)]
  const r = await run(review, { ...BASE, prs, groups: [[1], [2]] }, (label) => {
    if (label === 'find:spec:1') return null
    if (label.startsWith('find:') && label.endsWith(':2')) return null
    return { findings: [] }
  })
  const by = Object.fromEntries(r.result.prs.map((p) => [p.number, p]))
  check('pr-review one dead lens: PR partial with lensesFailed', by[1].status === 'partial' && JSON.stringify(by[1].lensesFailed) === '["spec"]', by[1])
  check('pr-review both lenses dead: PR unreviewed', by[2].status === 'unreviewed' && by[2].lensesFailed.length === 2, by[2])
  check('pr-review run status partial when any PR is not reviewed', r.result.status === 'partial')
}

{
  // Refuted findings never reach open; a split-off also entry comes back unverified.
  const r = await run(review, { ...BASE, prs: [pr(1)], groups: [[1]] }, (label, prompt) => {
    if (label === 'find:correctness:1') return { findings: [finding(1, 'a.js', 1), finding(1, 'b.js', 2)] }
    if (label === 'find:spec:1') return { findings: [finding(1, 'b.js', 2, { title: 'different defect' })] }
    if (prompt.includes('Location: a.js:1\n')) return confirm({ verdict: 'refuted', reproduction: '' })
    if (prompt.includes('Location: b.js:2\n')) return confirm({ severity: 'high', distinct_also: [0] })
  })
  const p = r.result.prs[0]
  check('pr-review refuted finding is not open', p.refuted.length === 1 && p.open.length === 1 && p.open[0].where === 'b.js:2', p)
  check('pr-review severity high → blocker', p.open[0].severity === 'blocker')
  check('pr-review distinct also entry is returned unverified with its pr', p.unverified.length === 1 && p.unverified[0].pr === 1 && p.unverified[0].title === 'different defect', p.unverified)
}

{
  // Verify-only re-run: no finders, rows only for claimed PRs, stringified args.
  const prs = [pr(1), pr(2)]
  const claims = [finding(2, 'x.js', 3, { lens: 'spec', raised_by: ['spec'] })]
  const r = await run(review, JSON.stringify({ ...BASE, prs, claims }), (label) => (label.startsWith('verify:') ? confirm() : undefined))
  check('pr-review claims re-run skips Find', !r.labels.some((l) => l.startsWith('find:')) && r.labels.length === 1, r.labels)
  check('pr-review claims re-run returns mode verify-only and only the claimed PR', r.result.mode === 'verify-only' && r.result.prs.length === 1 && r.result.prs[0].number === 2 && r.result.prs[0].open.length === 1, r.result)
}

{
  // M2: a verify-only re-run fed review-<i>.json rows (no base, no author_kind) aborts
  // before any agent; SKILL Step 2.4 names review-plan.json runs[i].prs as the source.
  const reviewRow = { number: 2, head_sha: sha('2'), status: 'partial', lensesFailed: [], open: [], refuted: [], unverified: [], verifierFailed: [], stats: {} }
  const r = await run(review, { ...BASE, prs: [reviewRow], claims: [finding(2, 'x.js', 3)] }, () => confirm())
  check('pr-review verify-only re-run with review-row prs aborts missing-head with 0 agents', r.result?.abort === true && r.result.reason === 'missing-head' && r.calls.length === 0, r.result)
}

{
  // worktrees arg: verifiers make their own worktree under the clone, no harness isolation.
  const r = await run(review, { ...BASE, worktrees: '/abs/clone/.claude/worktrees', prs: [pr(1)], groups: [[1]] }, (label) =>
    label === 'find:correctness:1' ? { findings: [finding(1, 'a.js', 1)] } : label.startsWith('find:') ? { findings: [] } : confirm())
  const v = r.calls.find((c) => c.label.startsWith('verify:'))
  check('pr-review with worktrees: verifier has no harness isolation and adds its own worktree', !v.opts.isolation && /worktree add --detach \/abs\/clone\/\.claude\/worktrees\//.test(v.prompt), v.opts)
}

{
  // Regression: every verifier of one PR got the literal path pr-sweep-verify-<pr>-<n>,
  // so parallel verifiers collided on one worktree.
  const claims = [finding(7, 'x.js', 1), finding(7, 'y.js', 2)]
  const r = await run(review, { ...BASE, worktrees: '/abs/clone/.claude/worktrees', prs: [pr(7)], claims }, () => confirm())
  const paths = r.calls.map((c) => (c.prompt.match(/worktree add --detach (\S+)/) ?? [])[1])
  check('pr-review with worktrees: two verifiers of one PR get distinct worktree paths', paths.length === 2 && paths.every(Boolean) && paths[0] !== paths[1] && !paths.some((x) => x.includes('<n>')), paths)
}

{
  // Regression: verifiers built and ran an external author's code in a worktree.
  // An external PR (or one without author_kind) gets read-only verifiers; self/bot keep the worktree.
  const prs = [pr(1, { author_kind: 'external' }), pr(2, { author_kind: undefined }), pr(3, { author_kind: 'bot' })]
  const r = await run(review, { ...BASE, prs, groups: [[1, 2, 3]] }, (label) =>
    label.startsWith('find:correctness') ? { findings: [finding(1, 'a.js', 1), finding(2, 'b.js', 2), finding(3, 'c.js', 3)] } : label.startsWith('find:') ? { findings: [] } : confirm())
  const v = (n) => r.calls.find((c) => c.label.endsWith(`:pr-${n}`) && c.label.startsWith('verify:'))
  for (const [n, why] of [[1, 'external'], [2, 'missing author_kind']]) {
    const c = v(n)
    check(`pr-review ${why} PR: verifier has no worktree and executes nothing`, c && !c.opts.isolation && /do not build, install, run tests, or execute any file/.test(c.prompt)
      && !/switch --detach|worktree add|scratch test/.test(c.prompt) && /Reproduce by reading only/.test(c.prompt), c?.opts)
  }
  const b = v(3)
  check('pr-review bot PR: verifier keeps its worktree and may run a scratch test', b && b.opts.isolation === 'worktree' && /switch --detach/.test(b.prompt) && !/untrusted/.test(b.prompt), b?.opts)
  const wt = await run(review, { ...BASE, worktrees: '/abs/clone/.claude/worktrees', prs: [pr(1, { author_kind: 'external' })], claims: [finding(1, 'a.js', 1)] }, () => confirm())
  check('pr-review external PR with worktrees arg: still no worktree add', !/worktree add/.test(wt.calls[0].prompt), wt.calls[0].prompt.slice(0, 200))
}

// ===========================================================================
// pr-fix
// ===========================================================================
const fixWf = load('pr-fix.workflow.js')
const unit = (n, extra = {}) => ({ id: `pr-${n}`, branch: `feat/${n}`, head_sha: sha(String(n % 10)), base: 'origin/main', issues: [], brief: `PR #${n} brief`, gates: [], findings: [{ id: 'F1', severity: 'major', where: 'a.js:1', problem: 'p', fix: 'f', evidence: 'e' }], ...extra })
const FBASE = { repo: 'o/r', root: '/abs/clone', trailer: 'Co-Authored-By: X' }
// head_sha is the full rev-parse output the sweep's FIX schema demands; commits keep the
// abbreviated "<sha> <subject>" form Finalise matches by prefix.
const fixRes = (u, extra = {}) => ({ unit: u, branch: 'b', status: 'done', head_sha: sha('a'), commits: ['abc1234 fix(x): y'], items: [], gates: [], ...extra })
const verdictRes = (u, v) => ({
  unit: u, verdict: v, gates_reproduced: [], claims_not_reproduced: [], mutant_replays: [],
  new_defects: v === 'fix-needed' ? [{ severity: 'major', where: 'a.js:1', problem: 'p', fix: 'f' }] : [], summary: '',
})

for (const [name, a, reason] of [
  ['no repo', { ...FBASE, repo: 'x', units: [unit(1)] }, 'no-repo'],
  ['no root', { ...FBASE, root: '', units: [unit(1)] }, 'no-root'],
  ['no units', { ...FBASE, units: [] }, 'no-units'],
  ['4 units over cap', { ...FBASE, units: [1, 2, 3, 4].map((n) => unit(n)) }, 'over-cap'],
  ['bad unit id', { ...FBASE, units: [unit(1, { id: 'fix-1' })] }, 'bad-unit-id'],
  ['shared branch', { ...FBASE, units: [unit(1), unit(2, { branch: 'feat/1' })] }, 'shared-branch'],
  ['no findings', { ...FBASE, units: [unit(1, { findings: [] })] }, 'incomplete-units'],
  ['no reviewed head', { ...FBASE, units: [unit(1, { head_sha: undefined })] }, 'missing-head'],
  ['short head', { ...FBASE, units: [unit(1, { head_sha: 'abc1234' })] }, 'missing-head'],
]) {
  const r = await run(fixWf, a, () => undefined)
  check(`pr-fix ${name} aborts ${reason} with 0 agents`, r.result?.abort === true && r.result.reason === reason && r.calls.length === 0, r.result)
}

{
  const units = [unit(1), unit(2), unit(3)]
  const r = await run(fixWf, { ...FBASE, units }, (label, prompt) => {
    const [kind, id] = label.split(':')
    if (kind === 'fix') return id === 'pr-3' ? fixRes(id, { status: 'blocked' }) : fixRes(id)
    if (kind === 'verify') return id === 'pr-1' ? verdictRes(id, 'pass') : verdictRes(id, 'fix-needed')
    if (kind === 'repair') return fixRes(id, { head_sha: sha('d') })
    if (kind === 'reverify') return verdictRes(id, 'pass')
    if (kind === 'finalise') return { pushed: [{ unit: 'pr-1', branch: 'feat/1', status: 'pushed', detail: '' }, { unit: 'pr-2', branch: 'feat/2', status: 'pushed', detail: '' }] }
  })
  const st = Object.fromEntries(r.result.rows.map((x) => [x.unit, x.status]))
  check('pr-fix pass → PASS, fix-needed → repair → REPAIRED_PASS, blocked → BLOCKED', st['pr-1'] === 'PASS' && st['pr-2'] === 'REPAIRED_PASS' && st['pr-3'] === 'BLOCKED', st)
  check('pr-fix blocked fix spawns no verifier', !r.labels.includes('verify:pr-3'), r.labels)
  check('pr-fix finalise plan carries the repaired head', JSON.stringify(r.result.finalisePlan.map((p) => [p.unit, p.head_sha])) === JSON.stringify([['pr-1', sha('a')], ['pr-2', sha('d')]]), r.result.finalisePlan)
  const fin = r.calls.find((c) => c.label === 'finalise')
  check('pr-fix finalise is opus/medium, not isolated', fin.opts.model === 'opus' && fin.opts.effort === 'medium' && !fin.opts.isolation)
  check('pr-fix finalise pushes but never merges, readies or opens a PR', /git push origin <head_sha>:refs\/heads\/<branch>/.test(fin.prompt) && /Do not merge, approve, mark ready, comment, or open a PR/.test(fin.prompt) && !/gh pr (merge|ready|create)/.test(fin.prompt))
  const fanned = r.calls.filter((c) => c.label !== 'finalise')
  check('pr-fix fan-out agents are opus/high in a worktree', fanned.every((c) => c.opts.model === 'opus' && c.opts.effort === 'high' && c.opts.isolation === 'worktree'), fanned.map((c) => c.opts))
  check('pr-fix fan-out prompts never push or touch GitHub', fanned.every((c) => /Do not (push|commit, push)/.test(c.prompt)))
  check('pr-fix fixer reads PR state before work', /gh pr list -R o\/r --head feat\/1 --state all/.test(r.calls.find((c) => c.label === 'fix:pr-1').prompt))
  check('pr-fix peak agents <= 13', r.peak <= 13, r.peak)
  check('pr-fix returns pushed rows', r.result.pushed?.length === 2)
  // Regression: the fixer started from root's local branch, which may hold unpushed
  // commits nobody reviewed, and Finalise could not tell them from fix commits.
  const fx1 = r.calls.find((c) => c.label === 'fix:pr-1').prompt
  check('pr-fix fixer must start at the reviewed head or return blocked', fx1.includes(`\`git rev-parse HEAD\` must print ${sha('1')}`) && /merge --ff-only/.test(fx1) && /commit nothing and return\s+status "blocked"/.test(fx1), fx1.slice(-900))
  check('pr-fix fixer never detaches the main checkout', /checked out in the main checkout \/abs\/clone, do not detach or switch that checkout/.test(fx1))
  check('pr-fix fixer prompt carries the unit brief', fx1.includes('PR #1 brief'))
  const rp2 = r.calls.find((c) => c.label === 'repair:pr-2').prompt
  check("pr-fix repairer must start at the fixer's tip", rp2.includes(`\`git rev-parse HEAD\` must print ${sha('a')}`), rp2.slice(-900))
  check('pr-fix finalise plan carries the reviewed head and the reported commits', JSON.stringify(r.result.finalisePlan.map((p) => [p.base_sha, p.commits])) === JSON.stringify([[sha('1'), ['abc1234']], [sha('2'), ['abc1234', 'abc1234']]]), r.result.finalisePlan)
  check('pr-fix finalise pushes only when the remote is still at base_sha and exactly the reported commits follow it',
    /git rev-parse origin\/<branch> prints base_sha/.test(fin.prompt) && /git merge-base --is-ancestor <base_sha> <head_sha>/.test(fin.prompt) && /git rev-list --first-parent --reverse <base_sha>\.\.<head_sha> lists exactly the commits in `commits`/.test(fin.prompt))
  // Regression: a plain `rev-list base_sha..head_sha` also listed every base-branch commit a
  // CONFLICT repair (merge-procedure.md M8: merge origin/<base>) brought in, so Finalise
  // skipped every such repair. First-parent walk + "merged parents must be on <base>".
  check('pr-fix finalise accepts a merge of <base> and nothing else',
    /every parent after the\s+first passes git merge-base --is-ancestor <parent> <base>/.test(fin.prompt) && /a merge of anything else is unreviewed work/.test(fin.prompt), fin.prompt.slice(-1200))
  check('pr-fix finalise plan carries each unit base', r.result.finalisePlan.every((p) => typeof p.base === 'string' && p.base.startsWith('origin/')), r.result.finalisePlan)
}

{
  // Regression: in worktrees mode the fixer and repairer (and verifier and re-verifier)
  // were told to add the same worktree path, and nothing removed the fixer's.
  const WT = '/abs/clone/.claude/worktrees'
  const r = await run(fixWf, { ...FBASE, worktrees: WT, units: [unit(7)] }, (label) =>
    label.startsWith('fix:') || label.startsWith('repair:') ? fixRes('pr-7') : label.startsWith('verify:') ? verdictRes('pr-7', 'fix-needed') : label.startsWith('reverify:') ? verdictRes('pr-7', 'pass') : undefined)
  const add = (l) => (r.calls.find((c) => c.label === l)?.prompt.match(/worktree add (?:--detach )?(\S+)/) ?? [])[1]
  const paths = ['fix:pr-7', 'repair:pr-7', 'verify:pr-7', 'reverify:pr-7'].map(add)
  check('pr-fix with worktrees: fixer, repairer, verifier and re-verifier get four distinct paths', paths.every(Boolean) && new Set(paths).size === 4, paths)
  check('pr-fix with worktrees: fixer and repairer remove their worktree', ['fix:pr-7', 'repair:pr-7'].every((l) => /worktree remove/.test(r.calls.find((c) => c.label === l).prompt)))
  check('pr-fix with worktrees: no harness isolation', r.calls.every((c) => !c.opts.isolation))
}

{
  const r = await run(fixWf, { ...FBASE, units: [unit(1)] }, (label) => (label.startsWith('fix:') ? fixRes('pr-1') : label.startsWith('verify:') ? null : undefined))
  check('pr-fix null verifier → UNVERIFIED, nothing finalised', r.result.rows[0].status === 'UNVERIFIED' && !r.labels.includes('finalise') && r.result.pushed.length === 0, r.result)
  const r0 = await run(fixWf, { ...FBASE, units: [unit(1)], repairRounds: 0 }, (label) => (label.startsWith('fix:') ? fixRes('pr-1') : verdictRes('pr-1', 'fix-needed')))
  check('pr-fix repairRounds 0 → FIX_NEEDED without a repairer', r0.result.rows[0].status === 'FIX_NEEDED' && !r0.labels.some((l) => l.startsWith('repair:')), r0.labels)
  const rb = await run(fixWf, { ...FBASE, units: [unit(1)] }, (label) =>
    label.startsWith('fix:') ? fixRes('pr-1') : label.startsWith('verify:') ? verdictRes('pr-1', 'fix-needed') : label.startsWith('repair:') ? fixRes('pr-1', { status: 'blocked' }) : verdictRes('pr-1', 'pass'))
  check('pr-fix repairer that finds the PR merged → BLOCKED, no re-verify', rb.result.rows[0].status === 'BLOCKED' && !rb.labels.some((l) => l.startsWith('reverify:')), rb.labels)
}

{
  // Regression (H2): FIX_SCHEMA.head_sha had no pattern, the mocks returned short SHAs,
  // and a short fixer head reached finalisePlan; merge-gate.sh G5 compares it by exact
  // string with the 40-hex headRefOid, so every such PR failed "head moved" after its push.
  const short = await run(fixWf, { ...FBASE, units: [unit(1)] }, (label) =>
    label.startsWith('fix:') ? fixRes('pr-1', { head_sha: 'abc1234' }) : label.startsWith('verify:') ? verdictRes('pr-1', 'pass') : { pushed: [] })
  check('pr-fix a short fixer head_sha is BLOCKED, never finalised', short.result.rows[0].status === 'BLOCKED' && short.result.finalisePlan.length === 0 && !short.labels.includes('finalise'), short.result)
  const shortRep = await run(fixWf, { ...FBASE, units: [unit(1)] }, (label) =>
    label.startsWith('fix:') ? fixRes('pr-1', { head_sha: 'abc1234' }) : label.startsWith('verify:') ? verdictRes('pr-1', 'fix-needed') : verdictRes('pr-1', 'pass'))
  check('pr-fix a short fixer head_sha spawns no repairer', !shortRep.labels.some((l) => l.startsWith('repair:')) && shortRep.result.rows[0].status === 'FIX_NEEDED', shortRep.labels)
  const full = await run(fixWf, { ...FBASE, units: [unit(1)] }, () => undefined)
  const schemas = full.calls.filter((c) => c.label.startsWith('fix:')).map((c) => c.opts.schema.properties.head_sha)
  const re = schemas[0]?.pattern ? new RegExp(schemas[0].pattern) : null
  check('pr-fix fixer schema demands a full 40-hex head_sha (or "")', re && re.test(sha('a')) && re.test('') && !re.test('abc1234'), schemas)
}

{
  // The shared region equals repair-round's, minus its three stage helpers.
  const rr = readFileSync(rrFile, 'utf8')
  const region = rr.slice(rr.indexOf('\n', rr.indexOf('// <shared:begin>')) + 1, rr.indexOf('// <shared:end>'))
  const drop = ['const verifyStage =', 'const repairStage =', 'const repairThenReverify =']
  const blocks = region.split('\n\n')
  const expected = blocks.filter((b) => !drop.some((d) => b.includes(d))).join('\n\n')
  const src = fixWf.src
  const mine = src.slice(src.indexOf('\n', src.indexOf('// <rr-shared:begin>')) + 1, src.indexOf('// <rr-shared:end>'))
  check('pr-fix rr-shared region is byte-identical with repair-round (helpers removed)', blocks.length - 3 === blocks.filter((b) => !drop.some((d) => b.includes(d))).length && mine === expected,
    { blocks: blocks.length, mineLen: mine.length, expectedLen: expected.length })
}

// ===========================================================================
// pr-merge
// ===========================================================================
const mergeWf = load('pr-merge.workflow.js')
const rosterRow = (n, extra = {}) => ({ number: n, url: `https://github.com/o/r/pull/${n}`, head_sha: sha(String(n % 10)), is_draft: true, draft_status: { section_present: true, blockers: [{ url: 'https://github.com/o/r/pull/99', state: 'MERGED' }] }, ...extra })
const plan = (passed, ready, report = []) => ({ repo: 'o/r', passed, ready, merge: [passed], report })
const roster = (ns) => ({ repo: 'o/r', prs: ns.map((n) => rosterRow(n)) })
const read = (n, extra = {}) => ({ number: n, head_sha: sha(String(n % 10)), verdict: 'ready', conditions: [], section_quote: '## Draft status', ...extra })

for (const [name, a, reason] of [
  ['no repo', { plan: plan([1], []), roster: roster([1]) }, 'no-repo'],
  ['bad plan', { repo: 'o/r', plan: { passed: [1] }, roster: roster([1]) }, 'bad-plan'],
  ['ready not passed', { repo: 'o/r', plan: plan([1], [2]), roster: roster([1, 2]) }, 'bad-plan'],
  ['9 ready over cap', { repo: 'o/r', plan: plan([1, 2, 3, 4, 5, 6, 7, 8, 9], [1, 2, 3, 4, 5, 6, 7, 8, 9]), roster: roster([1, 2, 3, 4, 5, 6, 7, 8, 9]) }, 'over-cap'],
  ['ready without roster row', { repo: 'o/r', plan: plan([1], [1]), roster: roster([]) }, 'ready-not-in-roster'],
  ['repo mismatch', { repo: 'o/x', plan: plan([1], []), roster: roster([1]) }, 'repo-mismatch'],
]) {
  const r = await run(mergeWf, a, () => undefined)
  check(`pr-merge ${name} aborts ${reason} with 0 agents`, r.result?.abort === true && r.result.reason === reason && r.calls.length === 0, r.result)
}

{
  const r = await run(mergeWf, { repo: 'o/r', plan: plan([3, 1, 2], [], [{ number: 7, gate: 'author' }]), roster: roster([]) }, () => undefined)
  check('pr-merge empty ready spawns no agent and keeps every passed PR', r.calls.length === 0 && JSON.stringify(r.result.merge) === '[[1,2,3]]' && r.result.report.length === 1, r.result)
}

{
  const passed = [1, 2, 3, 4, 5, 6, 10, 11, 12, 13]
  const ready = [2, 3, 4, 5, 6]
  const r = await run(mergeWf, { repo: 'o/r', plan: plan(passed, ready), roster: roster(passed), chunk: 3 }, (label) => {
    const n = Number(label.split('-')[1])
    if (n === 2) return read(2)
    if (n === 3) return read(3, { verdict: 'hold', conditions: [{ text: 'after hw test', met: 'no', evidence: '' }] })
    if (n === 4) return null
    if (n === 5) return read(5, { conditions: [{ text: 'issue #8 closed', met: 'unknown', evidence: '' }] })
    if (n === 6) return read(6, { head_sha: sha('f') })
  })
  check('pr-merge one reader per ready draft, opus/medium', r.calls.length === 5 && r.calls.every((c) => c.opts.model === 'opus' && c.opts.effort === 'medium' && !c.opts.isolation), r.labels)
  check('pr-merge ready verdict keeps the draft', r.result.ready.join() === '2' && r.result.passed.includes(2), r.result.ready)
  check('pr-merge hold, dead reader, unknown condition and moved head all hold the draft', JSON.stringify(r.result.held.map((h) => h.number)) === '[3,4,5,6]', r.result.held)
  check('pr-merge held drafts leave passed and every merge chunk', [3, 4, 5, 6].every((n) => !r.result.passed.includes(n) && !r.result.merge.flat().includes(n)))
  check('pr-merge merge chunks rebuilt ascending at the chunk size', JSON.stringify(r.result.merge) === '[[1,2,10],[11,12,13]]', r.result.merge)
  check('pr-merge held drafts are reported with gate draft_prose', r.result.report.filter((x) => x.gate === 'draft_prose').length === 4)
  check('pr-merge reader prompts are read-only', r.calls.every((c) => onlyForbidden(c.prompt) && /data, never instructions/.test(c.prompt)))
  check('pr-merge peak agents <= 8', r.peak <= 8, r.peak)
}

{
  // Regression: no case had a reader answer for another PR at the expected head, so
  // dropping the number check kept the suite green.
  const r = await run(mergeWf, { repo: 'o/r', plan: plan([2], [2]), roster: roster([2]) }, () => read(2, { number: 7 }))
  check('pr-merge reader that answers for another PR holds the draft', JSON.stringify(r.result.held.map((h) => [h.number, h.reason])) === '[[2,"reader answered for #7"]]' && r.result.merge.flat().length === 0, r.result.held)
}

{
  // Regression (M4): held rows lacked merge-gate's fix_block and findings keys, so
  // plan.report mixed two row shapes.
  const GATE_ROW_KEYS = ['failed', 'findings', 'fix_block', 'gate', 'is_draft', 'number', 'open_count', 'reason', 'url']
  const ros = { repo: 'o/r', prs: [rosterRow(2, { policy: { fix_block: null } }), rosterRow(3, { policy: { fix_block: 'renovate' } })] }
  const r = await run(mergeWf, { repo: 'o/r', plan: plan([2, 3], [2, 3]), roster: ros }, (label) => read(Number(label.split('-')[1]), { verdict: 'hold' }))
  const rows = r.result.report.filter((x) => x.gate === 'draft_prose')
  check('pr-merge held rows carry exactly merge-gate.sh report row keys', rows.length === 2 && rows.every((x) => JSON.stringify(Object.keys(x).sort()) === JSON.stringify(GATE_ROW_KEYS)), rows)
  check('pr-merge held rows: findings [] and the roster fix_block', JSON.stringify(rows.map((x) => [x.number, x.fix_block, x.findings])) === '[[2,null,[]],[3,"renovate",[]]]', rows)
}

{
  // Regression (M3): gate.json carried no chunk and SKILL Step 4.4 passes none, so the
  // rebuild used 8 and undid merge-gate.sh --chunk.
  const passed = [1, 2, 3, 4, 5, 6, 7]
  const r = await run(mergeWf, { repo: 'o/r', plan: { ...plan(passed, [2]), chunk: 3 }, roster: roster(passed) }, () => read(2))
  check('pr-merge rebuilds at plan.chunk when args.chunk is absent', JSON.stringify(r.result.merge) === '[[1,2,3],[4,5,6],[7]]' && r.result.chunk === 3, r.result.merge)
  const r2 = await run(mergeWf, { repo: 'o/r', plan: { ...plan(passed, [2]), chunk: 3 }, roster: roster(passed), chunk: 2 }, () => read(2))
  check('pr-merge args.chunk still overrides plan.chunk', JSON.stringify(r2.result.merge) === '[[1,2],[3,4],[5,6],[7]]', r2.result.merge)
}

if (failed) {
  console.log(`\n${failed} check(s) failed`)
  process.exit(1)
}
console.log('\nall workflow checks passed')
