/**
 * repair-round.workflow.js — close a known finding set on branches that
 * already exist: fix, verify with a fresh agent, repair at most once more, then
 * push sequentially.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: per-unit pipeline, then one sequential finalise agent.
 *   Fan-out unit  — one fixer per branch, a fresh verifier per fixed branch,
 *                   and on `fix-needed` one more repair plus re-verify.
 *   Loop bound    — `args.units`, each carrying its findings. The harness never
 *                   invents findings; a run that needs new ones is a review
 *                   (agent-patterns-plugin:adversarial-review), not a repair.
 *                   Capped at MAX_UNITS; above it the run aborts.
 *   Barrier       — Finalise only (push order on one remote).
 *
 * Later rounds are separate runs fed this run's FIX_NEEDED rows — the in-run
 * bound is a constant, and a JS counter would reset on resume.
 *
 * Push and every GitHub mutation happen ONLY in the Finalise agent, never
 * inside a fanned-out agent.
 *
 * The region between the `shared:` markers is byte-identical with
 * implement-verify.workflow.js; `scripts/tests/test-templates.sh` enforces it.
 */

export const meta = {
  name: 'repair-round',
  description:
    'Close given findings on existing branches: fix, verify with a fresh agent, repair at most once more, push sequentially.',
  phases: [{ title: 'Fix' }, { title: 'Verify' }, { title: 'Repair' }, { title: 'Finalise' }],
}

const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the numbers, PRESERVE the shape.
const FLOOR = 1 // a single branch still benefits from the independent verifier
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
const LAND = INPUT.land === 'local' ? 'local' : 'push'
const REPAIR_ROUNDS = INPUT.repairRounds === 0 ? 0 : 1

// Each unit: an existing branch and the findings to close. `findings` rows
// accept a verifier's new_defects shape ({severity, where, problem, fix}) or a
// review's ({id, severity, text}); an implement-verify FIX_NEEDED row can be
// passed through as { id, branch, findings: verdict.new_defects }.
const UNITS = (INPUT.units ?? []).map((u, i) => ({
  id: String(u.id ?? u.unit ?? `unit-${i + 1}`),
  branch: u.branch,
  base: u.base ?? CTX.base,
  issues: u.issues ?? [],
  brief: u.brief ?? '',
  gates: u.gates ?? [],
  findings: (u.findings ?? []).map((f, j) => ({ id: f.id ?? `F${j + 1}`, ...f, text: f.text ?? f.problem ?? '' })),
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

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort.
// ---------------------------------------------------------------------------

if (UNITS.length < FLOOR) {
  log('no units — nothing to repair; abort')
  return { abort: true, reason: 'no-units' }
}
if (UNITS.length > MAX_UNITS) {
  log(`${UNITS.length} units (> ${MAX_UNITS}) — split into several runs; abort without truncating`)
  return { abort: true, reason: 'over-cap', units: UNITS.map((u) => u.id) }
}
const bad = UNITS.filter((u) => !u.branch || !u.findings.length)
if (bad.length) {
  log(`units without a branch or findings: ${bad.map((u) => u.id).join(', ')} — abort`)
  return { abort: true, reason: 'incomplete-units', units: bad.map((u) => u.id) }
}

// ---------------------------------------------------------------------------
// Fix → Verify → Repair → Re-verify, per unit, no barrier between stages.
// ---------------------------------------------------------------------------

phase('Fix')
log(`${UNITS.length} branches, repair rounds ${REPAIR_ROUNDS}, land ${LAND}`)

const ctxFor = (u) => ({ ...CTX, base: u.base })
const hasCommitsOrRejections = (fix) => Boolean(fix && fix.head_sha)
const fixStage = (u) =>
  agent(FIX_PROMPT(ctxFor(u), u, u.findings), {
    label: `fix:${u.id}`,
    phase: 'Fix',
    schema: FIX_SCHEMA,
    model: 'opus',
    effort: 'high',
    isolation: 'worktree',
  })

const got = await pipeline(
  // PRESERVE the literal bound in the fan-out: the scale guard counts it.
  UNITS.slice(0, 5),
  (u) => fixStage(u),
  async (fix, u) => {
    if (!hasCommitsOrRejections(fix)) return { u, fix, verdict: null }
    return { u, fix, verdict: await verifyStage(ctxFor(u), 'Verify')(u, fix, `verify:${u.id}`) }
  },
  async (r) => {
    const { u, fix, verdict } = r
    if (!REPAIR_ROUNDS || verdict?.verdict !== 'fix-needed') return { ...r, repaired: null, final: verdict }
    const repaired = await repairStage(ctxFor(u))(u, verdict)
    if (!repaired) return { ...r, repaired: null, final: null }
    const final = await verifyStage(ctxFor(u), 'Repair')(u, { ...fix, ...repaired }, `reverify:${u.id}`)
    return { ...r, repaired, final }
  },
)

const rows = got.map((r, j) => {
  const u = UNITS[j]
  if (!r) return { unit: u.id, branch: u.branch, status: 'FAILED', fix: null, verdicts: [] }
  const fix = r.repaired ? { ...r.fix, ...r.repaired, items: [...r.fix.items, ...r.repaired.items] } : r.fix
  return {
    unit: u.id,
    branch: u.branch,
    status: rowStatus(r.repaired ?? r.fix, r.final, Boolean(r.repaired)),
    fix,
    verdicts: [r.verdict, r.repaired ? r.final : null].filter(Boolean),
  }
})

const landable = rows.filter((r) => r.status === 'PASS' || r.status === 'REPAIRED_PASS')
const finalisePlan = landable.map((r) => ({ unit: r.unit, branch: r.branch, head_sha: r.fix.head_sha, pr_body_note: r.fix.pr_body ?? '' }))
const notLanded = rows.filter((r) => !landable.includes(r))
if (notLanded.length) log(`not landable: ${notLanded.map((r) => `${r.unit}=${r.status}`).join(', ')}`)

// ---------------------------------------------------------------------------
// Finalise — BARRIER. One sequential agent; the only stage that pushes.
// ---------------------------------------------------------------------------

if (LAND === 'local' || !finalisePlan.length) return { rows, finalisePlan, pushed: [] }

phase('Finalise')
const PUSH_SCHEMA = {
  type: 'object',
  required: ['pushed'],
  additionalProperties: false,
  properties: {
    pushed: {
      type: 'array',
      items: {
        type: 'object',
        required: ['unit', 'branch', 'status', 'detail'],
        additionalProperties: false,
        properties: {
          unit: { type: 'string' },
          branch: { type: 'string' },
          status: { type: 'string', enum: ['pushed', 'skipped', 'failed'] },
          detail: { type: 'string' },
        },
      },
    },
  },
}
const finalised = await agent(
  `You push verified repair commits to their existing branches, one at a time, in the order given.
Repository ${CTX.repo}; run git from ${CTX.root} without changing its branch or files.

${JSON.stringify(finalisePlan, null, 1)}

For each entry, in order:
1. gh pr list --head <branch> --state all --json number,state. A MERGED or CLOSED PR → "skipped" (a merged branch cannot take new commits).
2. git fetch origin <branch>; git log --oneline origin/<branch>..<head_sha> must list only new commits on top of the remote tip. If the remote moved or the history diverged, record "skipped" with the reason; do not rebase or force.
3. git push origin <head_sha>:refs/heads/<branch>.
4. If pr_body_note is non-empty, append it to the PR body (gh pr edit --body-file).
Do not merge or approve. Stop at the first failed push and mark the rest "skipped".`,
  { label: 'finalise', phase: 'Finalise', schema: PUSH_SCHEMA, model: 'opus', effort: 'medium' },
)
if (!finalised) log('finalise agent returned null — check each branch tip against origin before re-running it')
return { rows, finalisePlan, pushed: finalised?.pushed ?? null }
