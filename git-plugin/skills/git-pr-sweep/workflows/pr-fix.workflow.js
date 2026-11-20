/**
 * pr-fix.workflow.js — close a PR review's open findings on the PRs' own head
 * branches: fix, verify with a fresh agent, repair at most once more, then push
 * sequentially. Never merges, never opens a PR.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: repair-round's (workflow-orchestration-plugin:workflow-implement-verify),
 * with its stages inlined so the scale guard can count them.
 *   Fan-out unit  — one fixer per PR branch, a fresh verifier per fixed branch,
 *                   and on `fix-needed` one repairer plus a re-verifier.
 *   Loop bound    — `args.units`: one runs[] element of review-to-units.sh
 *                   --chunk 3, which already dropped every PR that must not be
 *                   fixed (drafts that cannot be readied, WIP, Renovate,
 *                   release-please, external authors, a head moved since the
 *                   review). Capped at MAX_UNITS; above it the run aborts.
 *   Barrier       — Finalise only (push order on one remote).
 *
 * Landing: push only, in the single sequential Finalise agent: new commits on
 * top of each PR's head, never force, never a merge, never a new PR. Every
 * other agent works in its own worktree and touches no remote.
 *
 * args (object or JSON string):
 *   repo, root   "owner/name" and the absolute path of its local clone (required)
 *   worktrees    optional: a directory inside root's clone for agent worktrees,
 *                when the session is NOT running inside root's repository
 *   base         default base ref, e.g. "origin/main" (each unit carries its own)
 *   units        [{id: "pr-<n>", branch, head_sha, base, issues: [], brief, gates: [],
 *                 findings: [{id, severity, where, problem, fix, evidence}]}]
 *                head_sha is the reviewed head: the fixer must start from it
 *                (root's local branch of that name may hold unpushed or stale
 *                commits), and Finalise pushes only a tip whose commits after
 *                it are exactly the ones the fixer and repairer reported.
 *   gates, setup, skills, decisions, contract, trailer, issueRead — as repair-round
 *   repairRounds 0 or 1 (default 1)
 *
 * Returns repair-round's shape, which merge-gate.sh reads as fix.json:
 *   { rows: [{unit, branch, status, fix, verdicts}], finalisePlan: [...], pushed: [...] | null }
 *   status ∈ PASS | REPAIRED_PASS | FIX_NEEDED | REJECTED | UNVERIFIED | BLOCKED | NO_CHANGE | FAILED
 *   On a guard: {abort: true, reason}.
 *
 * The region between the `rr-shared:` markers is repair-round's shared region
 * with its three stage helpers removed (they would hide agent() calls from the
 * scale guard); scripts/tests/run-workflows.mjs pins it byte-identical.
 */

export const meta = {
  name: 'pr-fix',
  description:
    'Close reviewed findings on existing PR branches: fix, fresh verifier, at most one repair, push-only sequential finalise; never merges.',
  phases: [{ title: 'Fix' }, { title: 'Verify' }, { title: 'Repair' }, { title: 'Finalise' }],
}

const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the number, PRESERVE the shape: 3 units x 4 agents + 1 finalise = 13,
// and the literal slice in the fan-out below equals it.
const MAX_UNITS = 3

const CTX = {
  repo: String(INPUT.repo ?? ''),
  root: String(INPUT.root ?? ''),
  worktrees: INPUT.worktrees ?? '',
  base: INPUT.base ?? 'origin/main',
  gates: INPUT.gates ?? [],
  setup: INPUT.setup ?? [],
  skills: INPUT.skills ?? ['git-plugin:git-commit-workflow'],
  decisions: INPUT.decisions ?? [],
  contract: INPUT.contract ?? '',
  trailer: INPUT.trailer ?? '',
  issueRead: INPUT.issueRead ?? 'gh issue view <n> --comments',
}
const REPAIR_ROUNDS = INPUT.repairRounds === 0 ? 0 : 1

const UNITS = (INPUT.units ?? []).map((u, i) => ({
  id: String(u.id ?? u.unit ?? `unit-${i + 1}`),
  branch: u.branch,
  // The commit the review saw. The fixer must start from it, never from
  // whatever the local branch of the same name holds in root.
  head_sha: String(u.head_sha ?? ''),
  base: u.base ?? CTX.base,
  issues: u.issues ?? [],
  brief: u.brief ?? '',
  gates: u.gates ?? [],
  findings: (u.findings ?? []).map((f, j) => ({ id: f.id ?? `F${j + 1}`, ...f, text: f.text ?? f.problem ?? '' })),
}))

// <rr-shared:begin> — keep byte-identical with repair-round.workflow.js's shared region, minus its stage helpers

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

// A unit whose clone is not the session's repository sets ctx.worktrees: a
// harness `isolation: 'worktree'` agent would get a worktree of the wrong
// repository, so the agent makes its own under that clone's .claude/worktrees/.
const isolationOf = (ctx) => (ctx.worktrees ? {} : { isolation: 'worktree' })
const worktreeAdd = (ctx, dir, args) => `git -C ${ctx.root} fetch origin -q && git -C ${ctx.root} worktree add ${args.replace('<path>', `${ctx.worktrees}/${dir}`)}`

const listOr = (xs, none) => (xs.length ? xs.map((x) => `  - ${x}`).join('\n') : `  ${none}`)
const common = (ctx) => `Repository: ${ctx.repo}. Main checkout: ${ctx.root} — never edit it or change its branch.
${ctx.decisions.length ? `Decisions the user made for this run (relay as given):\n${listOr(ctx.decisions, '')}\n` : ''}${
  ctx.contract ? `Binding design/contract: ${ctx.contract}\n` : ''
}${ctx.skills.length ? `Skills to use: ${ctx.skills.join(', ')}\n` : ''}Report every gate as the exact command and its exit code; never claim a gate you did not run.
Do not ask questions. Anything that is the user's call goes in decisions_for_user with a recommendation.`

const VERIFY_PROMPT = (ctx, u, claims) => `You are a FRESH, ADVERSARIAL VERIFIER of unit ${u.id} on branch \`${u.branch}\`.
You did not write this change and have no stake in it passing.

${common(ctx)}

${ctx.worktrees ? `Create your own detached worktree, work only inside it, and remove it (never --force) when done:
  ${worktreeAdd(ctx, `verify-${u.id}`, `--detach <path> ${u.branch}`)}
` : 'Work in your own worktree. '}Establish the change from refs, never from any checkout:
  git fetch origin -q; git switch --detach ${u.branch}
  git log --oneline ${ctx.base}..${u.branch}; git diff ${ctx.base}...${u.branch}
Do not commit, push, or touch GitHub, the branch, or any other worktree.
${ctx.setup.length ? `Bootstrap the worktree first:\n${listOr(ctx.setup, '')}\n` : ''}
What the change must achieve:
${u.brief || '(see the issues)'}${u.issues.length ? `\nIssues: ${u.issues.map((n) => `#${n}`).join(', ')} — read each with its comments (${ctx.issueRead}).` : ''}
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

Before any other work, read the branch's PR state (an open PR can merge while its verifier runs, and a reused branch name lists PRs of earlier work):
  gh pr list -R ${ctx.repo} --head ${u.branch} --state all --json number,state,headRefOid
The list holds every PR ever opened from this branch name, so read every entry. An OPEN entry wins → continue.
A MERGED or CLOSED entry counts only when it carries this branch's commits: its headRefOid and the branch tip lie on one line of history.
  First fetch the PR head, which this clone may lack (pushed from another clone, then the branch deleted on merge):
  git -C ${ctx.root} fetch origin -q; git -C ${ctx.root} fetch origin -q pull/<number>/head.
  The entry counts when git -C ${ctx.root} merge-base --is-ancestor <headRefOid> ${u.branch} or git -C ${ctx.root} merge-base --is-ancestor ${u.branch} <headRefOid>
  exits 0, testing origin/${u.branch} when there is no local ${u.branch}. If the fetch fails, the entry counts: a PR head you cannot read is not safe to ignore.
  One that fails the test is earlier work on a reused name: ignore it.
No PR yet, or only ignored entries → continue.
Only when no entry is OPEN and a MERGED or CLOSED entry counts → stop: commit nothing and return status "blocked" with the PR number and state in blockers.
The orchestrator decides whether the findings become a new unit cut from ${ctx.base}; do not open a PR or push.

Work in your own worktree:
  ${ctx.worktrees ? worktreeAdd(ctx, `repair-${u.id}`, `<path> ${u.branch}`) : `git fetch origin -q; git switch ${u.branch}`}
  (If git says the branch is already used by another worktree, a finished agent forgot to detach:
  find it with \`git worktree list\`, run \`git -C <that path> switch --detach\`, and retry.)
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

// Combine an author's report with a repairer's. Arrays accumulate and the PR
// text survives: a repairer that returns an empty pr_title or fixes_issues must
// not erase what the author drafted. The repairer's head_sha and status win.
const mergeRepair = (fix, rep) => ({
  ...fix,
  ...rep,
  items: [...(fix.items ?? []), ...(rep.items ?? [])],
  commits: [...(fix.commits ?? []), ...(rep.commits ?? [])],
  gates: [...(fix.gates ?? []), ...(rep.gates ?? [])],
  fixes_issues: [...new Set([...(fix.fixes_issues ?? []), ...(rep.fixes_issues ?? [])])],
  refs_issues: [...new Set([...(fix.refs_issues ?? []), ...(rep.refs_issues ?? [])])],
  followups: [...(fix.followups ?? []), ...(rep.followups ?? [])],
  decisions_for_user: [...(fix.decisions_for_user ?? []), ...(rep.decisions_for_user ?? [])],
  pr_title: rep.pr_title || fix.pr_title,
  pr_body: rep.pr_body || fix.pr_body,
  // A repairer that rejects every finding adds no commit and may say no-change;
  // the branch still carries the author's work, so it is "done" for landing.
  status: rep.status === 'no-change' ? 'done' : rep.status,
})

// <rr-shared:end>

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort that spawns no agent.
// ---------------------------------------------------------------------------

const abort = (reason, msg, extra = {}) => {
  log(`${msg}; abort`)
  return { abort: true, reason, ...extra }
}
if (!/^[\w.-]+\/[\w.-]+$/.test(CTX.repo)) return abort('no-repo', 'args.repo must be "owner/name"')
if (!/^(\/|[A-Za-z]:[\\/])/.test(CTX.root)) return abort('no-root', 'args.root must be the absolute path of a clone of the repo')
if (!UNITS.length) return abort('no-units', 'no units — nothing to fix')
if (UNITS.length > MAX_UNITS) {
  return abort('over-cap', `${UNITS.length} units (> ${MAX_UNITS}) — run review-to-units.sh --chunk ${MAX_UNITS}, never truncate`, { units: UNITS.map((u) => u.id) })
}
const badIds = UNITS.filter((u) => !/^pr-\d+$/.test(u.id))
if (badIds.length) return abort('bad-unit-id', `unit ids must be "pr-<number>" (merge-gate.sh keys on them): ${badIds.map((u) => u.id).join(', ')}`)
const dupBranches = UNITS.map((u) => u.branch).filter((b, i, a) => b && a.indexOf(b) !== i)
if (dupBranches.length) return abort('shared-branch', `two units share a branch (${dupBranches.join(', ')})`, { branches: dupBranches })
const bad = UNITS.filter((u) => !u.branch || !u.findings.length)
if (bad.length) return abort('incomplete-units', `units without a branch or findings: ${bad.map((u) => u.id).join(', ')}`, { units: bad.map((u) => u.id) })
const noHead = UNITS.filter((u) => !/^[0-9a-f]{40}$/.test(u.head_sha))
if (noHead.length) {
  return abort('missing-head', `units without the reviewed 40-hex head_sha (review-to-units.sh carries it): ${noHead.map((u) => u.id).join(', ')}`, { units: noHead.map((u) => u.id) })
}

// ---------------------------------------------------------------------------
// Sweep additions to the shared prompts, appended outside the shared region.
// FIX_PROMPT switches to the LOCAL branch by name. root is the user's own clone,
// so that branch may carry unpushed commits nobody reviewed, or lag origin; the
// start check pins the fixer to the reviewed head and the repairer to the
// fixer's tip. FIX_PROMPT also never prints the unit brief, so it rides here.
// ---------------------------------------------------------------------------

const sweepRules = (ctx, u, expected, what) => `
PR sweep requirements — they override the generic steps above where they conflict:
- Start point: right after the switch above, \`git rev-parse HEAD\` must print ${expected} (${what}).
  If HEAD is an ancestor of it (the local branch only lags origin), run \`git merge --ff-only ${expected}\` and check again.
  Any other HEAD means the local branch \`${u.branch}\` carries commits the review never saw: commit nothing and return
  status "blocked" with blockers ["local ${u.branch} is at <the sha HEAD printed>, not ${expected}"].
- If git says \`${u.branch}\` is checked out in the main checkout ${ctx.root}, do not detach or switch that checkout:
  return status "blocked" with that reason.
${u.brief ? `- ${u.brief}\n` : ''}${
  ctx.worktrees ? `- When done, after \`git switch --detach\`, remove your worktree (never --force): git -C ${ctx.root} worktree remove <your worktree path>\n` : ''
}`
// The repairer and re-verifier make their own worktrees one level down, so a
// fixer or verifier worktree that was not removed cannot collide with theirs.
const ctxRound2 = (u) => ({ ...ctxFor(u), worktrees: CTX.worktrees ? `${CTX.worktrees}/round2` : '' })

// ---------------------------------------------------------------------------
// Fix → Verify → Repair → Re-verify, per unit, no barrier between stages.
// ---------------------------------------------------------------------------

phase('Fix')
log(`${UNITS.length} PR branch(es), repair rounds ${REPAIR_ROUNDS}`)

const ctxFor = (u) => ({ ...CTX, base: u.base })
// `blocked` (the PR already merged or closed) reports the unchanged tip; there
// is nothing for a verifier to check.
const hasCommitsOrRejections = (fix) => Boolean(fix && fix.head_sha && fix.status !== 'blocked')
const repairFindings = (verdict) => [
  ...verdict.new_defects,
  ...verdict.claims_not_reproduced.map((c) => ({ severity: 'major', problem: `claim did not reproduce: ${c}` })),
  ...(verdict.items_not_closed ?? []).map((c) => ({ severity: 'major', problem: `not closed: ${c}` })),
]

const got = await pipeline(
  // PRESERVE the literal bound in the fan-out and the inline agent() calls: the
  // scale guard counts 3 units x 4 sites.
  UNITS.slice(0, 3),
  (u) =>
    agent(FIX_PROMPT(ctxFor(u), u, u.findings) + sweepRules(ctxFor(u), u, u.head_sha, 'the head the review saw'), {
      label: `fix:${u.id}`, phase: 'Fix', schema: FIX_SCHEMA, model: 'opus', effort: 'high', ...isolationOf(ctxFor(u)),
    }),
  async (fix, u) => {
    if (!hasCommitsOrRejections(fix)) return { u, fix, verdict: null }
    const verdict = await agent(VERIFY_PROMPT(ctxFor(u), u, fix), {
      label: `verify:${u.id}`, phase: 'Verify', schema: VERDICT_SCHEMA, model: 'opus', effort: 'high', ...isolationOf(ctxFor(u)),
    })
    return { u, fix, verdict }
  },
  // A dead repairer keeps the verifier's fix-needed verdict, so the row stays FIX_NEEDED.
  async (r, u) => {
    const { fix, verdict } = r
    if (!REPAIR_ROUNDS || verdict?.verdict !== 'fix-needed') return { ...r, merged: fix, repaired: false, final: verdict }
    const rep = await agent(FIX_PROMPT(ctxRound2(u), u, repairFindings(verdict)) + sweepRules(ctxRound2(u), u, fix.head_sha, "the fixer's last commit"), {
      label: `repair:${u.id}`, phase: 'Repair', schema: FIX_SCHEMA, model: 'opus', effort: 'high', ...isolationOf(ctxRound2(u)),
    })
    if (!rep) return { ...r, merged: fix, repaired: false, final: verdict }
    const merged = mergeRepair(fix, rep)
    if (rep.status === 'blocked') return { ...r, merged, repaired: true, final: null }
    const final = await agent(VERIFY_PROMPT(ctxRound2(u), u, merged), {
      label: `reverify:${u.id}`, phase: 'Repair', schema: VERDICT_SCHEMA, model: 'opus', effort: 'high', ...isolationOf(ctxRound2(u)),
    })
    return { ...r, merged, repaired: true, final }
  },
)

const rows = got.map((r, j) => {
  const u = UNITS[j]
  if (!r) return { unit: u.id, branch: u.branch, status: 'FAILED', fix: null, verdicts: [] }
  return {
    unit: u.id,
    branch: u.branch,
    status: rowStatus(r.merged, r.final, r.repaired),
    fix: r.merged,
    verdicts: [r.verdict, r.repaired ? r.final : null].filter(Boolean),
  }
})

const landable = rows.filter((r) => r.status === 'PASS' || r.status === 'REPAIRED_PASS')
// base_sha is the reviewed head and commits the fixer's and repairer's own
// commits: Finalise pushes a tip only when exactly those commits sit on it.
const shaOf = (c) => String(c ?? '').trim().split(/\s+/)[0]
const finalisePlan = landable.map((r) => ({
  unit: r.unit,
  branch: r.branch,
  head_sha: r.fix.head_sha,
  base_sha: UNITS.find((u) => u.id === r.unit).head_sha,
  commits: (r.fix.commits ?? []).map(shaOf).filter(Boolean),
  pr_body_note: '',
}))
const notLanded = rows.filter((r) => !landable.includes(r))
if (notLanded.length) log(`not landable: ${notLanded.map((r) => `${r.unit}=${r.status}`).join(', ')}`)
if (!finalisePlan.length) return { rows, finalisePlan, pushed: [] }

// ---------------------------------------------------------------------------
// Finalise — BARRIER. One sequential agent; the only stage that pushes.
// ---------------------------------------------------------------------------

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
  `You push verified fix commits to existing PR head branches, one at a time, in the order given.
Repository ${CTX.repo}; run git from ${CTX.root} without changing its branch or files.

${JSON.stringify(finalisePlan, null, 1)}

For each entry, in order:
1. gh pr list -R ${CTX.repo} --head <branch> --state all --json number,state,headRefOid, and read every entry. An OPEN entry wins → continue.
   Otherwise fetch each MERGED or CLOSED entry's head (git fetch origin -q pull/<number>/head). An entry whose headRefOid and head_sha lie on
   one line of history (git merge-base --is-ancestor either way exits 0), or whose head cannot be fetched → "skipped". One that fails the test
   is earlier work on a reused branch name: ignore it.
2. git fetch origin <branch>. All three must hold, else record "skipped" with the reason; do not rebase or force:
   - git rev-parse origin/<branch> prints base_sha (the head the review saw; the remote has not moved);
   - git merge-base --is-ancestor <base_sha> <head_sha> exits 0;
   - git rev-list --reverse <base_sha>..<head_sha> lists exactly the commits in \`commits\` (an abbreviated SHA matches by prefix).
     Any other commit is local work nobody reviewed, and pushing it would publish it.
3. git push origin <head_sha>:refs/heads/<branch> (brace shell variables before the colon).
Do not merge, approve, mark ready, comment, or open a PR. Stop at the first failed push and mark the rest "skipped".
Return {pushed: [{unit, branch, status: pushed|skipped|failed, detail}]}, one row per entry; no other field.`,
  { label: 'finalise', phase: 'Finalise', schema: PUSH_SCHEMA, model: 'opus', effort: 'medium' },
)
if (!finalised) log('finalise agent returned null — check each branch tip against origin before re-running it')
return { rows, finalisePlan, pushed: finalised?.pushed ?? null }
