/**
 * implement-verify.workflow.js — implement a known set of units, verify each
 * with a fresh agent, repair at most once, then land sequentially.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: per-unit pipeline, then one sequential finalise agent.
 *   Fan-out unit  — one implementer per unit in its own worktree; a fresh
 *                   verifier per implemented unit; on `fix-needed`, one repair
 *                   agent and one re-verifier.
 *   Loop bound    — `args.units` (or `args.issues`, one unit per issue), capped
 *                   at MAX_UNITS. Above the cap the run aborts; it never
 *                   truncates.
 *   Barrier       — Finalise only. Push order over one remote needs every
 *                   unit's final verdict. Implement → Verify → Repair is a
 *                   pipeline: a verifier starts as soon as its own implementer
 *                   returns.
 *   Stop judge    — the verifier, never the implementer
 *                   (`.claude/rules/loop-integrity.md` Pillar 1).
 *
 * Push, PR creation and every GitHub mutation happen ONLY in the Finalise
 * agent, which runs once, after every pipeline has finished. Implementers,
 * verifiers and repairers are commit-local.
 *
 * The Verify/Repair half is shared byte-for-byte with repair-round.workflow.js
 * (the region between the `shared:` markers). A repair-round run can take this
 * run's rows unchanged. `scripts/tests/test-templates.sh` fails when the two
 * copies drift.
 */

export const meta = {
  name: 'implement-verify',
  description:
    'Implement caller-supplied units in worktrees, verify each with a fresh agent, repair at most once, and open PRs sequentially.',
  phases: [
    { title: 'Implement' },
    { title: 'Verify' },
    { title: 'Repair' },
    { title: 'Finalise' },
  ],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the numbers, PRESERVE the shape. One unit is the linear path: an
// implementer and a verifier dispatched by hand cost the same without a harness.
const FLOOR = 2
// Worst case is 4 agents per unit + 1 finalise, so 5 units is 21 agents.
// Split a larger set into several runs; never truncate silently.
const MAX_UNITS = 5

const CTX = {
  repo: INPUT.repo ?? '<owner>/<repo>',
  root: INPUT.root ?? '<absolute path of the main checkout>',
  base: INPUT.base ?? 'origin/main',
  gates: INPUT.gates ?? [],
  setup: INPUT.setup ?? [],
  skills: INPUT.skills ?? [],
  decisions: INPUT.decisions ?? [],
  contract: INPUT.contract ?? '',
  trailer: INPUT.trailer ?? '',
}
const LAND = INPUT.land === 'local' ? 'local' : 'pr'
const REPAIR_ROUNDS = INPUT.repairRounds === 0 ? 0 : 1
const PR = { assignee: INPUT.pr?.assignee ?? '@me', labels: INPUT.pr?.labels ?? [], footer: INPUT.pr?.footer ?? '' }

// Units come from the caller. `issues: [n, …]` is shorthand for one standalone
// unit per issue; grouping overlapping issues is the caller's job (or
// git-plugin:git-issue's issue-group-wave).
const UNITS = (INPUT.units ?? (INPUT.issues ?? []).map((n) => ({ id: `issue-${n}`, issues: [Number(n)] })))
  .map((u, i) => ({
    id: String(u.id ?? `unit-${i + 1}`),
    issues: u.issues ?? [],
    branch: u.branch ?? `fix/${u.id ?? `unit-${i + 1}`}`,
    brief: u.brief ?? '',
    owns: u.owns ?? [],
    gates: u.gates ?? [],
    tier: ['sonnet', 'haiku'].includes(u.tier) ? u.tier : 'opus',
    labels: u.labels ?? [],
  }))

// <shared:begin> — keep byte-identical with repair-round.workflow.js

// PRESERVE the closed enums. `reject` means "wrong approach": it never triggers
// an automatic repair, it goes to a human.
const VERDICT_SCHEMA = {
  type: 'object',
  required: ['unit', 'verdict', 'gates_reproduced', 'claims_not_reproduced', 'mutant_replays', 'new_defects', 'summary'],
  additionalProperties: false,
  properties: {
    unit: { type: 'string' },
    verdict: { type: 'string', enum: ['pass', 'fix-needed', 'reject'] },
    head_sha: { type: 'string', description: 'the commit you verified' },
    gates_reproduced: {
      type: 'array',
      items: {
        type: 'object',
        required: ['command', 'exit_code', 'matches_claim'],
        additionalProperties: false,
        properties: { command: { type: 'string' }, exit_code: { type: 'integer' }, matches_claim: { type: 'boolean' } },
      },
    },
    claims_not_reproduced: { type: 'array', items: { type: 'string' } },
    items_not_closed: { type: 'array', items: { type: 'string' }, description: 'findings or criteria the change does not close' },
    mutant_replays: {
      type: 'array',
      items: {
        type: 'object',
        required: ['mutant', 'killed'],
        additionalProperties: false,
        properties: { finding: { type: 'string' }, mutant: { type: 'string' }, killed: { type: 'boolean' } },
      },
    },
    new_defects: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severity', 'where', 'problem', 'fix'],
        additionalProperties: false,
        properties: {
          severity: { type: 'string', enum: ['blocker', 'major', 'minor'] },
          where: { type: 'string', description: 'file:line' },
          problem: { type: 'string' },
          fix: { type: 'string' },
          evidence: { type: 'string', description: 'the command you ran or the line you read' },
        },
      },
    },
    sweep_gaps: { type: 'array', items: { type: 'string' }, description: 'other sites of the same defect class left unfixed' },
    summary: { type: 'string' },
  },
}

const FIX_SCHEMA = {
  type: 'object',
  required: ['unit', 'branch', 'status', 'head_sha', 'commits', 'items', 'gates'],
  additionalProperties: false,
  properties: {
    unit: { type: 'string' },
    branch: { type: 'string' },
    // `no-change`: already correct at the base, with evidence. Distinct from
    // `blocked`; conflating them makes a stale issue read as a failure.
    status: { type: 'string', enum: ['done', 'partial', 'no-change', 'blocked'] },
    head_sha: { type: 'string', description: 'branch tip after your work (the existing tip if you added no commit), or "" if no branch exists' },
    commits: { type: 'array', items: { type: 'string' }, description: '<sha> <subject>' },
    items: {
      type: 'array',
      description: 'one row per issue, criterion or finding you were given',
      items: {
        type: 'object',
        required: ['id', 'action', 'evidence'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          action: { type: 'string', enum: ['fixed', 'rejected', 'deferred', 'not-applicable'] },
          evidence: { type: 'string', description: 'for rejected: why the finding is wrong, with the line or command' },
          pinned_by: { type: 'string', description: 'test or check that fails without this fix' },
        },
      },
    },
    gates: {
      type: 'array',
      items: {
        type: 'object',
        required: ['command', 'exit_code'],
        additionalProperties: false,
        properties: { command: { type: 'string' }, exit_code: { type: 'integer' }, summary: { type: 'string' } },
      },
    },
    fixes_issues: { type: 'array', items: { type: 'integer' }, description: 'fully resolved → Fixes #n' },
    refs_issues: { type: 'array', items: { type: 'integer' }, description: 'partially addressed → Refs #n' },
    pr_title: { type: 'string', description: 'conventional-commit title' },
    pr_body: { type: 'string' },
    followups: { type: 'array', items: { type: 'string' }, description: 'pre-existing problems noticed, not fixed' },
    decisions_for_user: {
      type: 'array',
      items: {
        type: 'object',
        required: ['question', 'recommendation'],
        additionalProperties: false,
        properties: { question: { type: 'string' }, recommendation: { type: 'string' } },
      },
    },
    blockers: { type: 'array', items: { type: 'string' } },
  },
}

const listOr = (xs, none) => (xs.length ? xs.map((x) => `  - ${x}`).join('\n') : `  ${none}`)
const common = (ctx) => `Repository: ${ctx.repo}. Main checkout: ${ctx.root} — never edit it or change its branch.
${ctx.decisions.length ? `Decisions the user made for this run (relay as given):\n${listOr(ctx.decisions, '')}\n` : ''}${
  ctx.contract ? `Binding design/contract: ${ctx.contract}\n` : ''
}${ctx.skills.length ? `Skills to use: ${ctx.skills.join(', ')}\n` : ''}Report every gate as the exact command and its exit code; never claim a gate you did not run.
Do not ask questions. Anything that is the user's call goes in decisions_for_user with a recommendation.`

const VERIFY_PROMPT = (ctx, u, claims) => `You are a FRESH, ADVERSARIAL VERIFIER of unit ${u.id} on branch \`${u.branch}\`.
You did not write this change and have no stake in it passing.

${common(ctx)}

Work in your own worktree. Establish the change from refs, never from any checkout:
  git fetch origin -q; git switch --detach ${u.branch}
  git log --oneline ${ctx.base}..${u.branch}; git diff ${ctx.base}...${u.branch}
Do not commit, push, or touch GitHub, the branch, or any other worktree.
${ctx.setup.length ? `Bootstrap the worktree first:\n${listOr(ctx.setup, '')}\n` : ''}
What the change must achieve:
${u.brief || '(see the issues)'}${u.issues.length ? `\nIssues: ${u.issues.map((n) => `#${n}`).join(', ')} — read each with its comments (gh issue view <n> --comments).` : ''}
${u.findings?.length ? `Findings that were to be closed:\n${listOr(u.findings.map((f) => `${f.id}: ${f.text}`), '')}\n` : ''}
The author's report — claims, not evidence:
${JSON.stringify(claims ?? {}, null, 1)}

Required checks:
1. Re-run every gate the author reported, plus: ${[...ctx.gates, ...u.gates].join('; ') || 'the project gates'}. Record each in gates_reproduced.
2. For each new or changed test, prove it bites: cp-snapshot the fixed file, revert the fix, run the test, restore from the snapshot (never git checkout --). Record in mutant_replays.
3. Check the change fixes the cause the brief describes, not a symptom, and look for other sites of the same defect (sweep_gaps).
4. Look for wrong logic, missed call sites, negative controls that can never fail, and docs that now contradict the code.

Verdict: "pass" only when every claimed gate reproduces and no blocker/major defect remains.
"fix-needed" when it is repairable on this branch. "reject" when the approach is wrong.
A claim that does not reproduce ranks above any code defect, and on its own means "fix-needed".`

const FIX_PROMPT = (ctx, u, findings) => `You repair unit ${u.id} on the EXISTING branch \`${u.branch}\`.

${common(ctx)}

Work in your own worktree:
  git fetch origin -q; git switch ${u.branch}
${ctx.setup.length ? `Bootstrap:\n${listOr(ctx.setup, '')}\n` : ''}
Findings to close (from an independent verifier or review — verify each against the code before acting;
reviewers can be wrong, so reject a wrong finding with evidence instead of "fixing" it):
${listOr(findings.map((f, i) => `${f.id ?? `F${i + 1}`} [${f.severity ?? '?'}] ${f.where ?? ''} ${f.problem ?? f.text ?? ''}${f.fix ? ` — suggested: ${f.fix}` : ''}`), '(none)')}

Pin each fix with a test that fails without it. Add NEW commits only: never amend, rebase or force.
Stage explicit paths. Run the gates: ${[...ctx.gates, ...u.gates].join('; ') || 'the project gates'}.
${ctx.trailer ? `End every commit message with exactly these lines:\n${ctx.trailer}\n` : ''}Do not push or touch GitHub — a later sequential stage does that.
Finally run \`git switch --detach\` so this worktree no longer holds the branch.
Return one items[] row per finding.`

const hasCommits = (fix) => Boolean(fix && fix.head_sha && !['no-change', 'blocked'].includes(fix.status))

// A null verdict is a dead verifier, never an approval.
const rowStatus = (fix, verdict, repaired) => {
  if (!fix) return 'FAILED'
  if (fix.status === 'no-change') return 'NO_CHANGE'
  if (!hasCommits(fix)) return 'BLOCKED'
  if (!verdict) return 'UNVERIFIED'
  if (verdict.verdict === 'reject') return 'REJECTED'
  if (verdict.verdict === 'fix-needed') return 'FIX_NEEDED'
  return repaired ? 'REPAIRED_PASS' : 'PASS'
}

const verifyStage = (ctx, phase) => (u, claims, label) =>
  agent(VERIFY_PROMPT(ctx, u, claims), {
    label,
    phase,
    schema: VERDICT_SCHEMA,
    model: 'opus',
    effort: 'high',
    isolation: 'worktree',
  })

const repairStage = (ctx) => (u, verdict) => {
  const findings = [
    ...verdict.new_defects,
    ...verdict.claims_not_reproduced.map((c) => ({ severity: 'major', problem: `claim did not reproduce: ${c}` })),
    ...(verdict.items_not_closed ?? []).map((c) => ({ severity: 'major', problem: `not closed: ${c}` })),
  ]
  return agent(FIX_PROMPT(ctx, u, findings), {
    label: `repair:${u.id}`,
    phase: 'Repair',
    schema: FIX_SCHEMA,
    model: 'opus',
    effort: 'high',
    isolation: 'worktree',
  })
}

// <shared:end>

const IMPL_PROMPT = (u) => `You implement ONE unit of work in a fresh git worktree, test-first.

${common(CTX)}

Unit ${u.id}${u.issues.length ? ` — issues ${u.issues.map((n) => `#${n}`).join(', ')}` : ''}
${u.brief}
${u.issues.length ? 'Read each issue with its full comment thread (gh issue view <n> --comments) and re-verify cited file:line at HEAD, per git-plugin:git-issue-scoping.' : ''}
${u.owns.length ? `You own these paths; do not edit outside them without saying why: ${u.owns.join(', ')}` : ''}

1. git fetch origin -q && git switch -c ${u.branch} ${CTX.base}
${CTX.setup.length ? `   then bootstrap:\n${listOr(CTX.setup, '')}` : ''}
2. Write the failing test, run it red, implement, run it green.
3. Run the gates: ${[...CTX.gates, ...u.gates].join('; ') || 'the project gates'}.
4. Commit (conventional subject, body says why; Fixes #n only when fully resolved, otherwise Refs #n).
${CTX.trailer ? `   End every commit message with exactly these lines:\n${CTX.trailer}\n` : ''}5. git log --oneline ${CTX.base}..HEAD must list only your commits.
6. Run \`git switch --detach\` so a verifier can check the branch out next.

Do not push, open PRs, or comment on issues — a later sequential stage does that.
Change only what the unit needs; put pre-existing problems in followups, not the diff.
If it is already fixed at the base, return status "no-change" with evidence and commit nothing.
Draft pr_title and pr_body for the finalise stage.`

const IMPL_OPTS = (u) => ({ label: `implement:${u.id}`, phase: 'Implement', schema: FIX_SCHEMA, isolation: 'worktree' })
// PRESERVE: one literal call site per tier so every model and effort is checkable.
// A cheaper implementer is only acceptable because an opus verifier follows.
const implement = (u) => {
  if (u.tier === 'haiku') return agent(IMPL_PROMPT(u), { ...IMPL_OPTS(u), model: 'haiku', effort: 'medium' })
  if (u.tier === 'sonnet') return agent(IMPL_PROMPT(u), { ...IMPL_OPTS(u), model: 'sonnet', effort: 'high' })
  return agent(IMPL_PROMPT(u), { ...IMPL_OPTS(u), model: 'opus', effort: 'high' })
}

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort.
// ---------------------------------------------------------------------------

if (UNITS.length < FLOOR) {
  log(`${UNITS.length} unit(s) (< ${FLOOR}) — implement and verify by hand; abort`)
  return { abort: true, reason: 'below-floor', units: UNITS.length }
}
if (UNITS.length > MAX_UNITS) {
  log(`${UNITS.length} units (> ${MAX_UNITS}) — split into several runs; abort without truncating`)
  return { abort: true, reason: 'over-cap', units: UNITS.map((u) => u.id) }
}
const dupBranches = UNITS.map((u) => u.branch).filter((b, i, a) => a.indexOf(b) !== i)
if (dupBranches.length) {
  log(`two units share a branch (${dupBranches.join(', ')}) — make them one unit; abort`)
  return { abort: true, reason: 'shared-branch', branches: dupBranches }
}

// ---------------------------------------------------------------------------
// Implement → Verify → Repair → Re-verify, per unit, no barrier between stages.
// ---------------------------------------------------------------------------

phase('Implement')
log(`${UNITS.length} units, repair rounds ${REPAIR_ROUNDS}, land ${LAND}`)

const verify = verifyStage(CTX, 'Verify')
const reverify = verifyStage(CTX, 'Repair')
const repair = repairStage(CTX)

const rows = []
{
  // PRESERVE the literal bound in the fan-out: the scale guard counts it.
  const got = await pipeline(
    UNITS.slice(0, 5),
    (u) => implement(u),
    async (fix, u) => {
      if (!hasCommits(fix)) return { u, fix, verdict: null }
      return { u, fix, verdict: await verify(u, fix, `verify:${u.id}`) }
    },
    async (r) => {
      const { u, fix, verdict } = r
      if (!REPAIR_ROUNDS || verdict?.verdict !== 'fix-needed') return { ...r, repaired: null, final: verdict }
      const repaired = await repair(u, verdict)
      if (!repaired) return { ...r, repaired: null, final: null }
      const final = await reverify(u, { ...fix, ...repaired }, `reverify:${u.id}`)
      return { ...r, repaired, final }
    },
  )
  got.forEach((r, j) => {
    const u = UNITS[j]
    if (!r) return rows.push({ unit: u.id, branch: u.branch, status: 'FAILED', fix: null, verdicts: [] })
    const fix = r.repaired ? { ...r.fix, ...r.repaired, items: [...r.fix.items, ...r.repaired.items] } : r.fix
    rows.push({
      unit: u.id,
      branch: u.branch,
      labels: u.labels,
      status: rowStatus(r.repaired ?? r.fix, r.final, Boolean(r.repaired)),
      fix,
      verdicts: [r.verdict, r.repaired ? r.final : null].filter(Boolean),
    })
  })
}

const landable = rows.filter((r) => r.status === 'PASS' || r.status === 'REPAIRED_PASS')
const finalisePlan = landable.map((r) => ({
  unit: r.unit,
  branch: r.branch,
  head_sha: r.fix.head_sha,
  labels: r.labels,
  fixes: r.fix.fixes_issues ?? [],
  refs: r.fix.refs_issues ?? [],
  pr_title: r.fix.pr_title ?? '',
  pr_body: r.fix.pr_body ?? '',
}))
const notLanded = rows.filter((r) => !landable.includes(r))
if (notLanded.length) log(`not landable: ${notLanded.map((r) => `${r.unit}=${r.status}`).join(', ')}`)

// ---------------------------------------------------------------------------
// Finalise — BARRIER. One sequential agent; the only stage that pushes.
// ---------------------------------------------------------------------------

if (LAND === 'local' || !finalisePlan.length) return { rows, finalisePlan, prs: [] }

phase('Finalise')
const FINALISE_SCHEMA = {
  type: 'object',
  required: ['prs'],
  additionalProperties: false,
  properties: {
    prs: {
      type: 'array',
      items: {
        type: 'object',
        required: ['unit', 'branch', 'status', 'detail'],
        additionalProperties: false,
        properties: {
          unit: { type: 'string' },
          branch: { type: 'string' },
          status: { type: 'string', enum: ['opened', 'updated', 'skipped', 'failed'] },
          pr_url: { type: 'string' },
          detail: { type: 'string' },
        },
      },
    },
  },
}
const finalised = await agent(
  `You land verified branches one at a time, in the order given. Repository ${CTX.repo}; run git from ${CTX.root} without changing its branch or files.

${JSON.stringify(finalisePlan, null, 1)}

For each entry, in order:
1. git log --oneline ${CTX.base}..<branch> must show only that unit's commits, and its tip must equal head_sha. If not, record "skipped" with the reason; do not repair it.
2. gh pr list --head <branch> --state all --json number,state. MERGED → "skipped". OPEN → push and record "updated".
3. git push -u origin <head_sha>:refs/heads/<branch> (never force).
4. If no PR exists: gh pr create --base ${CTX.base.replace(/^origin\//, '')} --head <branch> --title <pr_title> --body-file <tmp file> -a ${PR.assignee}${PR.labels.length ? ` -l ${PR.labels.join(',')}` : ''} plus the entry's labels. The body is pr_body, then "Fixes #n" / "Refs #n" lines from fixes/refs${PR.footer ? `, then:\n${PR.footer}` : ''}.
Do not merge, approve, or request review from the PR author. Stop at the first push that fails and mark the rest "skipped".`,
  { label: 'finalise', phase: 'Finalise', schema: FINALISE_SCHEMA, model: 'opus', effort: 'medium' },
)
if (!finalised) log('finalise agent returned null — check `gh pr list` per branch before re-running it')
return { rows, finalisePlan, prs: finalised?.prs ?? null }
