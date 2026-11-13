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
  const sent = {}
  const agent = async (prompt, opts) => {
    calls.push(opts.label)
    sent[opts.label] = { prompt, opts }
    const kind = opts.label.split(':')[0]
    const unit = opts.label.split(':')[1]
    const r = script(kind, unit)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, pipeline, () => {}, () => {}, argsIn)
  return { result, calls, sent }
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
// 14. The repair brief reads the branch's PR state before any other work, and
// a merged or closed PR means stop and report, never a new PR (#3589).
{
  const r = await run({ ...units(['a', 'b']), repo: 'o/r', land: 'local' }, (k, u) =>
    k === first ? fix(u) : k === 'verify' ? verdict(u, 'fix-needed') : k === 'repair' ? fix(u) : verdict(u, 'pass'))
  const p = r.sent['repair:a']?.prompt ?? ''
  const at = p.indexOf('gh pr list -R o/r --head fix/a --state all --json number,state')
  check('repair prompt reads PR state first', at !== -1 && at < p.indexOf('Work in your own worktree'), p)
  check('repair prompt: MERGED or CLOSED → blocked, no new PR', /MERGED or CLOSED[^\n]*commit nothing[^\n]*"blocked"/.test(p) && /do not open a PR/.test(p), p)
  // --state all returns every PR ever opened from the branch name, so a reused
  // name can list an old MERGED PR beside the OPEN one: the OPEN entry wins.
  check('repair prompt: an OPEN entry wins over older MERGED/CLOSED ones',
    /an OPEN entry wins/.test(p) && /no entry is OPEN and one is MERGED or CLOSED → stop/.test(p)
      && !/^MERGED or CLOSED → stop/m.test(p), p)
}
// 15. A repairer that stopped on a merged PR (blocked) is BLOCKED, not re-verified, not landed.
{
  const r = await run(units(['a', 'b']), (k, u) =>
    k === first ? fix(u) : k === 'verify' ? verdict(u, 'fix-needed')
      : k === 'repair' ? fix(u, { status: 'blocked', blockers: ['PR #7 is MERGED'] })
      : k === 'reverify' ? verdict(u, 'pass') : { prs: [], pushed: [] })
  check('blocked repair → BLOCKED', statuses(r).a === 'BLOCKED', statuses(r))
  check('blocked repair → no re-verify', !r.calls.some((c) => c.startsWith('reverify')), r.calls)
  check('blocked repair → not landed', r.result.finalisePlan.length === 0 && !r.calls.includes('finalise'), r.result.finalisePlan)
}
if (isImpl) {
  // 8. no-change is its own outcome and skips the verifier.
  const r = await run(units(['a', 'b']), (k, u) => (k === 'implement' ? fix(u, { status: 'no-change' }) : verdict(u, 'pass')))
  check('no-change → NO_CHANGE, unverified', statuses(r).a === 'NO_CHANGE' && !r.calls.some((c) => c.startsWith('verify')), r.calls)
  check('NO_CHANGE not landed', r.result.finalisePlan.length === 0 && !r.calls.includes('finalise'), r.result.finalisePlan)
  // 9. A single unit is below the floor.
  const one = await run(units(['a']), () => fix('a'))
  check('one unit aborts below floor', one.result.reason === 'below-floor' && one.calls.length === 0, one)
  // The implement brief caps follow-up volume: 7 units returned 52 followups
  // without it, about 12 with it (#3605).
  {
    const capped = await run({ ...units(['a', 'b']), land: 'local' }, (k, u) => (k === 'implement' ? fix(u) : verdict(u, 'pass')))
    const p = capped.sent['implement:a']?.prompt ?? ''
    check('implement prompt caps followups', /put pre-existing problems in followups, not the diff\.[^\n]*Keep followups to defects worth an issue/.test(p), p)
  }
  // 10. Units in two repositories: each unit's repo, root and gates reach its own
  // prompts, a foreign unit's agents make worktrees under its root, and the
  // landing plan names each unit's repository.
  {
    const two = {
      repo: 'run/repo', root: '/clones/run', gates: ['bash run-gate.sh'],
      units: [
        { id: 'a', branch: 'fix/a' },
        { id: 'b', branch: 'fix/a', repo: 'other/repo', root: '/clones/other/', gates: ['bash b-gate.sh'] },
      ],
    }
    const r = await run(two, (k, u) =>
      k === 'implement' ? fix(u) : k === 'verify' ? verdict(u, u === 'b' ? 'fix-needed' : 'pass')
        : k === 'repair' ? fix(u, { head_sha: 'def5678' }) : k === 'reverify' ? verdict(u, 'pass') : { prs: [] })
    const p = (label) => r.sent[label]?.prompt ?? ''
    const iso = (label) => r.sent[label]?.opts.isolation
    check('same branch name in two repos is allowed', statuses(r).a === 'PASS' && statuses(r).b === 'REPAIRED_PASS', statuses(r))
    check('run-repo unit keeps harness isolation and run gates',
      iso('implement:a') === 'worktree' && iso('verify:a') === 'worktree' && p('implement:a').includes('Repository: run/repo. Main checkout: /clones/run')
        && p('implement:a').includes('bash run-gate.sh') && !p('implement:a').includes('worktree add'), r.sent['implement:a'])
    check('foreign unit: own repo, root and gates in its implement prompt',
      p('implement:b').includes('Repository: other/repo. Main checkout: /clones/other/') && p('implement:b').includes('bash b-gate.sh')
        && !p('implement:b').includes('bash run-gate.sh'), p('implement:b'))
    check('foreign unit: implementer worktree under its root',
      p('implement:b').includes('git -C /clones/other/ worktree add -b fix/a /clones/other/.claude/worktrees/b origin/main'), p('implement:b'))
    check('foreign unit: verifier, repairer and re-verifier worktrees under its root',
      p('verify:b').includes('worktree add --detach /clones/other/.claude/worktrees/verify-b fix/a')
        && p('repair:b').includes('worktree add /clones/other/.claude/worktrees/repair-b fix/a')
        && p('reverify:b').includes('/clones/other/.claude/worktrees/verify-b'), [p('verify:b'), p('repair:b')])
    check('foreign unit: no harness isolation on any of its agents',
      ['implement:b', 'verify:b', 'repair:b', 'reverify:b'].every((l) => r.sent[l] && iso(l) === undefined), r.calls)
    const plan = Object.fromEntries((r.result.finalisePlan ?? []).map((e) => [e.unit, e]))
    check('landing plan names each unit\'s repository and clone',
      plan.a?.repo === 'run/repo' && plan.a?.root === '/clones/run' && plan.b?.repo === 'other/repo' && plan.b?.root === '/clones/other/'
        && plan.b?.head_sha === 'def5678', r.result.finalisePlan)
    check('finalise runs git and gh per entry', p('finalise').includes('git -C <root> push') && p('finalise').includes('gh pr create -R <repo>')
      && p('finalise').includes('"repo": "other/repo"'), p('finalise'))
  }
  // 11. A unit naming a repository needs both repo and an absolute root.
  for (const bad of [{ repo: 'other/repo' }, { root: '/clones/other' }, { repo: 'other/repo', root: 'clones/other' }]) {
    const r = await run({ units: [{ id: 'a' }, { id: 'b', ...bad }] }, () => fix('x'))
    check(`incomplete repo ${JSON.stringify(bad)} aborts`, r.result.reason === 'incomplete-repo' && r.calls.length === 0, r.result)
  }
} else {
  // 8. A unit without findings aborts the run.
  const r = await run({ units: [{ id: 'a', branch: 'fix/a', findings: [] }] }, () => fix('a'))
  check('unit without findings aborts', r.result.reason === 'incomplete-units' && r.calls.length === 0, r)
  // 9. A first-stage fixer that found the PR merged (blocked, tip unchanged) gets no verifier (#3589).
  const m = await run(units(['a', 'b']), (k, u) =>
    k === 'fix' ? (u === 'a' ? fix(u, { status: 'blocked', commits: [] }) : fix(u)) : k === 'verify' ? verdict(u, 'pass') : { pushed: [] })
  check('blocked fixer → BLOCKED, unverified', statuses(m).a === 'BLOCKED' && !m.calls.includes('verify:a'), m.calls)
}

process.exit(failed ? 1 : 0)
