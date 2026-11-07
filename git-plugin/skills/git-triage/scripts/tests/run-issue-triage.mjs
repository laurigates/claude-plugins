// Run git-triage's issue-triage.workflow.js against a stub runtime and assert on
// its result. Usage: node run-issue-triage.mjs <issue-triage.workflow.js>
import { readFileSync } from 'node:fs'
import { basename } from 'node:path'

const file = process.argv[2]
const src = readFileSync(file, 'utf8').replace(/^export const meta/m, 'const meta')
const AsyncFunction = Object.getPrototypeOf(async () => {}).constructor
const body = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', src)
const parallel = async (thunks) => Promise.all(thunks.map((t) => t().catch(() => null)))

async function run(argsIn, script) {
  const sent = []
  const agent = async (prompt, opts) => {
    sent.push({ prompt, opts })
    const r = script(opts.label.replace(/^triage:/, ''), opts)
    return r === undefined ? null : r
  }
  const result = await body(agent, parallel, async () => [], () => {}, () => {}, argsIn)
  return { result, sent }
}

const row = (ref, verdict = 'actionable', extra = {}) => {
  const [repo, n] = ref.split('#')
  return {
    repo, number: Number(n), title: 't', verdict, reason: 'r', question_for_user: '', waiting_on: '',
    open_pr: '', scope: '', size: 'small', group_with: '', ...extra,
  }
}

let failed = 0
const check = (name, cond, detail) => {
  console.log(`${cond ? 'PASS' : 'FAIL'} ${basename(file)} ${name}${cond ? '' : ` — ${JSON.stringify(detail)}`}`)
  if (!cond) failed++
}

const REPOS = [
  { repo: 'acme/app', root: '/clones/app', alias: 'app' },
  { repo: 'acme/docs', root: '/clones/docs' },
]

// 1. Issues from two repositories: each prompt names its own repo and clone, and
//    the rows come back keyed by input issue.
{
  const r = await run({ repos: REPOS, issues: ['app#3', 'acme/docs#7', { repo: 'acme/app', number: 9 }] }, (ref) => row(ref))
  const p = (ref) => r.sent.find((s) => s.opts.label === `triage:${ref}`)?.prompt ?? ''
  check('one agent per issue', r.sent.length === 3, r.sent.map((s) => s.opts.label))
  check('alias resolves to its repository', p('acme/app#3').includes('gh issue view 3 -R acme/app'), p('acme/app#3'))
  check('each prompt reads its own clone',
    p('acme/app#3').includes('git -C /clones/app show origin/main:') && p('acme/docs#7').includes('git -C /clones/docs grep')
      && !p('acme/docs#7').includes('/clones/app'), [p('acme/app#3'), p('acme/docs#7')])
  check('read-only clause and no-switch clause present', p('acme/docs#7').includes('READ-ONLY') && p('acme/docs#7').includes('Never check out or switch branches'), p('acme/docs#7'))
  check('every agent pins model and effort', r.sent.every((s) => s.opts.model === 'opus' && s.opts.effort === 'medium'), r.sent.map((s) => s.opts))
  check('all triaged, none missing', r.result.triaged.length === 3 && r.result.missing.length === 0, r.result)
}
// 2. A dead agent is `missing`, never a verdict; an echoed wrong number is re-keyed.
{
  const r = await run({ repos: REPOS, issues: 'acme/app#1 acme/app#2 acme/docs#3' }, (ref) =>
    ref === 'acme/app#2' ? null : ref === 'acme/docs#3' ? row('acme/docs#99', 'close_candidate') : row(ref))
  check('null result → missing', r.result.missing.length === 1 && r.result.missing[0] === 'acme/app#2', r.result.missing)
  check('row keyed by input issue', r.result.triaged.some((x) => x.repo === 'acme/docs' && x.number === 3 && x.verdict === 'close_candidate'), r.result.triaged)
}
// 3. The verdict enum is the closed four, and the user question field is named for the user.
{
  const r = await run({ repos: REPOS, issues: ['acme/app#1', 'acme/app#2'] }, (ref) => row(ref))
  const schema = r.sent[0].opts.schema
  check('closed verdict enum', JSON.stringify(schema.properties.verdict.enum) === JSON.stringify(['actionable', 'needs_decision', 'blocked_on_event', 'close_candidate']), schema.properties.verdict)
  check('question field is question_for_user', schema.required.includes('question_for_user') && !Object.keys(schema.properties).some((k) => /lauri/i.test(k)), schema.required)
}
// 4. classes and limits replace the default text.
{
  const r = await run({ repos: REPOS, issues: ['acme/app#1', 'acme/app#2'], classes: { actionable: 'CUSTOM-DEF' }, limits: 'CUSTOM-LIMITS' }, (ref) => row(ref))
  const p = r.sent[0].prompt
  check('classes override a definition', p.includes('- actionable: CUSTOM-DEF') && p.includes('- needs_decision:'), p)
  check('limits replace the default paragraph', p.includes('Environment: CUSTOM-LIMITS'), p)
}
// 5. Guards abort before any agent runs.
const guard = async (name, a, reason) => {
  const r = await run(a, (ref) => row(ref))
  check(name, r.result.abort === true && r.result.reason === reason && r.sent.length === 0, r.result)
}
const many = Array.from({ length: 41 }, (_, i) => `acme/app#${i + 1}`)
await guard('over the cap aborts without truncating', { repos: REPOS, issues: many }, 'over-cap')
await guard('one issue is below the floor', { repos: REPOS, issues: ['acme/app#1'] }, 'below-floor')
await guard('a repository with no clone aborts', { repos: REPOS, issues: ['acme/app#1', 'other/x#2'] }, 'no-clone')
await guard('an unparseable reference aborts', { repos: REPOS, issues: ['acme/app#1', 'nonsense'] }, 'bad-issues')
await guard('an unknown verdict in classes aborts', { repos: REPOS, issues: ['acme/app#1', 'acme/app#2'], classes: { wontfix: 'x' } }, 'unknown-classes')
await guard('classes as an array aborts', { repos: REPOS, issues: ['acme/app#1', 'acme/app#2'], classes: ['x'] }, 'bad-classes')
// 6. Exactly at the cap every issue gets an agent (a narrower slice would drop one silently).
{
  const r = await run({ repos: REPOS, issues: many.slice(0, 40) }, (ref) => row(ref))
  check('40 issues → 40 agents and 40 rows', r.sent.length === 40 && r.result.triaged.length === 40, r.sent.length)
}
// 7. Duplicate references are triaged once.
{
  const r = await run({ repos: REPOS, issues: ['app#1', 'acme/app#1', 'acme/app#2'] }, (ref) => row(ref))
  check('duplicates triaged once', r.sent.length === 2, r.sent.map((s) => s.opts.label))
}

process.exit(failed ? 1 : 0)
