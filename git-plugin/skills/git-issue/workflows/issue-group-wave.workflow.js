/**
 * issue-group-wave.workflow.js — the `--parallel` path of `git-plugin:git-issue`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: composite — one grouping agent, a barrier, then a fan-out.
 *   Fan-out unit  — one `isolation: 'worktree'` agent per conflict-free GROUP.
 *                   Inside a group the issues run sequentially: that is what a
 *                   group means.
 *   Loop bound    — `args.issues`, the refs Step 0 normalised from bare
 *                   numbers / #N / issue URLs. The grouping agent PARTITIONS
 *                   that set; it can never extend it, and the partition is
 *                   validated below rather than trusted.
 *   Barrier       — Group. Conflict detection is pairwise over the whole set
 *                   (file overlap, opposing requirements, blocked_by chains,
 *                   sub-issue ordering), so no group can be dispatched until
 *                   every issue has been read. A file overlap with an issue
 *                   nobody has looked at yet is invisible.
 *
 * Two clauses this template carries. Both are unconditional here — every
 * fanned-out agent runs in a worktree, and this skill's deliverable is a PR.
 *
 *   Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents —
 *   a resume re-runs agents that already succeeded and opens duplicate PRs
 *   (#1868; `.claude/rules/agent-coworker-detection.md` § "`Workflow` resume
 *   re-runs already-succeeded worktree agents"). Re-dispatch the failed units
 *   fresh and sequentially, after checking
 *   `gh pr list --head <branch> --state all --json number,state`.
 *
 *   Push and PR creation happen ONLY in the single sequential finalise stage,
 *   which runs OUTSIDE this harness, never inside a fanned-out agent. Every
 *   agent below is commit-local: it branches from `origin/main`, implements,
 *   and commits in its own worktree.
 *
 * Three things this deliberately does NOT do:
 *   1. No fan-out over the grouping. You cannot partition work by a partition
 *      the work itself discovers — the groups do not exist until Stage 1 has
 *      run, so the capability lane is always ONE agent.
 *   2. No synthesis agent. The finalise plan here is a pure projection of the
 *      group results (one branch per issue, in dispatch order) — an agent asked
 *      to reproduce that would launder a sort into a decision.
 *   3. No `AskUserQuestion`. The skill's low-confidence and blocked-issue
 *      prompts cannot run inside a workflow, so those issues are DEFERRED with
 *      a named reason and handed back for the caller to adjudicate — never
 *      silently attempted and never silently dropped.
 */

export const meta = {
  name: 'issue-group-wave',
  description:
    'Partition an issue set into conflict-free groups, implement each group in its own worktree, and return a sequential finalise plan.',
  phases: [{ title: 'Group' }, { title: 'Implement' }],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})
// A bare array of issue numbers is accepted as well as `{ issues: [...] }`.
const RAW_ISSUES = Array.isArray(INPUT) ? INPUT : (INPUT.issues ?? [])
const REPO = INPUT.repo ?? '<owner>/<repo>'

// PRESERVE: the loop bound is this set, normalised to integers and deduped.
// Everything downstream is checked against it.
const ISSUES = [...new Set(RAW_ISSUES.map((n) => Number(typeof n === 'object' ? n.number : n)))]
  .filter((n) => Number.isInteger(n) && n > 0)

// ADAPT the numbers, PRESERVE the shape. One issue is the modal case and is the
// prose linear path; grouping a set of one is a pure cost.
const FLOOR = 2

// Concurrency ceiling. Each unit is a full TDD implementation in its own
// worktree, so a wide wave buys little and risks the burst rate-limit.
const WAVE = Number(INPUT.parallel) > 0 ? Number(INPUT.parallel) : 3

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums and the partition shape. Every input
// issue lands in exactly one group OR in `deferred` with a named reason; there
// is no third outcome an agent can narrate its way into.
// ---------------------------------------------------------------------------

const GROUP_SCHEMA = {
  type: 'object',
  required: ['groups', 'deferred'],
  additionalProperties: false,
  properties: {
    groups: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'issues', 'reason'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          issues: { type: 'array', items: { type: 'integer' } },
          reason: {
            type: 'string',
            description: 'why these issues must run together, or "standalone"',
          },
        },
      },
    },
    deferred: {
      type: 'array',
      items: {
        type: 'object',
        required: ['issue', 'reason', 'detail'],
        additionalProperties: false,
        properties: {
          issue: { type: 'integer' },
          // Closed. "Skipped it" is not expressible; each exclusion names which
          // documented gate it failed, so the caller can adjudicate it.
          reason: {
            type: 'string',
            enum: ['blocked', 'low-confidence', 'cross-repo', 'not-open'],
          },
          detail: { type: 'string' },
        },
      },
    },
  },
}

const IMPL_SCHEMA = {
  type: 'object',
  required: ['group', 'issues', 'status'],
  additionalProperties: false,
  properties: {
    group: { type: 'string' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['issue', 'outcome', 'branch', 'commits', 'summary'],
        additionalProperties: false,
        properties: {
          issue: { type: 'integer' },
          // Closed. `no-change` is a real outcome (the issue was already fixed
          // at HEAD) and is distinct from `failed`; conflating them is how a
          // stale issue silently reads as a broken implementation.
          outcome: {
            type: 'string',
            enum: ['implemented', 'no-change', 'failed'],
          },
          branch: { type: 'string', description: 'fix/issue-<n>, or "" when nothing was cut' },
          commits: { type: 'array', items: { type: 'string' } },
          summary: { type: 'string' },
        },
      },
    },
    status: { type: 'string', enum: ['COMPLETE', 'PARTIAL', 'FAILED'] },
    blockers: { type: 'array', items: { type: 'string' } },
  },
}

// ---------------------------------------------------------------------------
// Prompts — ADAPT ALL OF THESE. Keep the grouping brief's "partition, do not
// extend" instruction and the implementation brief's no-push constraint.
// ---------------------------------------------------------------------------

const GROUP_PROMPT = (issues) => `You are the grouping stage of a parallel issue run against
${REPO}. Partition the issue set below into groups that can be worked SIMULTANEOUSLY without
colliding. You see every issue at once because conflict detection is pairwise — an overlap with
an issue you have not read is invisible.

Issues: ${issues.join(', ')}

For each issue, read the body AND the full comment thread
(gh issue view <n> --json title,body,state,labels,comments): the body is the opening position,
not the decision. A later comment may have narrowed, reversed, or already resolved the ask. The
protocol is git-plugin:git-issue-scoping.

Also query the native dependency API per issue:
  gh api repos/${REPO}/issues/<n>/dependencies/blocked_by --jq '.[] | select(.state == "open") | .number'

Partition rules:
  - Two issues belong to the SAME group when they cannot run at once: overlapping files or
    components, opposing requirements (add vs remove), one blocked_by the other, or a
    parent/sub-issue ordering. Within a group they will be worked sequentially, in the order
    you list them.
  - An independent issue is its own single-issue group with reason "standalone".
  - DEFER an issue instead of grouping it when it is blocked by an OPEN issue outside this set
    ("blocked"), its requirements are too unclear to implement (below the skill's 70% confidence
    bar — "low-confidence"), it belongs to another repository ("cross-repo"), or it is not open
    ("not-open"). A deferred issue is handed back for a human to decide; it is not a failure.

Partition, do not extend: every number you return must come from the list above, each must
appear exactly once across groups and deferred, and you must not introduce any other issue.`

const IMPL_PROMPT = (group) => `You implement ONE conflict-free group of GitHub issues inside a
fresh git worktree, using TDD.

Repository: ${REPO}
Group: ${group.id} (${group.reason})
Issues, in this order: ${group.issues.join(', ')}

Constraints — the finalise stage handles these instead, do NOT do them yourself:
- Do NOT git push.
- Do NOT create or edit pull requests.
- Do NOT close or comment on issues.

For EACH issue in the listed order:

1. Read the issue body AND its full comment thread
   (gh issue view <n> --json title,body,state,labels,comments) and scope from the latest
   deciding comment, per git-plugin:git-issue-scoping. Capture its labels — the finalise stage
   applies them to the PR.
2. Cut the branch from the remote, never from local main:
     git fetch origin
     git switch -c fix/issue-<n> origin/main
3. RED: write the failing test that defines the expected behaviour, and run it to see it fail.
   GREEN: write the minimal implementation and run the test to see it pass.
   REFACTOR: clean up, re-run.
4. Commit on that branch with the issue reference in the FOOTER:
     <type>: <description>

     Fixes #<n>
5. Verify the branch carries only this issue's commits:
     git log --oneline origin/main..HEAD
6. Stop. Do not push.

If the issue turns out to be already fixed at HEAD, record outcome "no-change" with the
evidence in summary and cut no branch — that is a real answer, not a failure. If you cannot
implement it, record "failed" with the reason and leave the branch in whatever state you
reached; say so in blockers[] so the caller can recover it rather than assume it never ran.`

// ---------------------------------------------------------------------------
// Guards. Each returns an explicit, named abort — never a silent no-op.
// ---------------------------------------------------------------------------

if (!ISSUES.length) {
  log('no issue refs after Step 0 normalisation — nothing to partition; abort')
  return { abort: true, reason: 'no-issues' }
}

if (ISSUES.length < FLOOR) {
  log(`${ISSUES.length} issue(s) (< ${FLOOR}) — the linear single-issue path is cheaper; abort`)
  return { abort: true, reason: 'below-floor', issues: ISSUES.length }
}

// ---------------------------------------------------------------------------
// Group — BARRIER. One agent; the partition does not exist until it has run.
// ---------------------------------------------------------------------------

phase(`Group — BARRIER: ${ISSUES.length} issues partitioned pairwise, one agent`)

const grouping = await agent(GROUP_PROMPT(ISSUES), {
  label: 'group',
  phase: 'Group',
  schema: GROUP_SCHEMA,
  model: 'opus',
  effort: 'medium',
})

if (!grouping) {
  log('grouping returned null — refusing to dispatch an unpartitioned set; abort')
  return { abort: true, reason: 'grouping-failed', issues: ISSUES }
}

// PRESERVE: validate the partition against the loop bound. The agent decides the
// SHAPE of the split, never its EXTENT — the fan-out width can only shrink
// relative to `args.issues`, never grow. Every correction is logged; nothing is
// dropped silently.
const inputSet = new Set(ISSUES)
const placement = new Map()
const record = (n, where) => placement.set(n, [...(placement.get(n) ?? []), where])

for (const g of grouping.groups) for (const n of g.issues) record(n, g.id)
for (const d of grouping.deferred) record(d.issue, 'deferred')

const invented = [...placement.keys()].filter((n) => !inputSet.has(n))
if (invented.length) log(`grouping invented issues not in args.issues, discarded: ${invented.join(', ')}`)

const duplicated = [...placement.entries()].filter(([n, at]) => inputSet.has(n) && at.length > 1)
if (duplicated.length) {
  log(
    `issues placed more than once, keeping the first placement: ${duplicated
      .map(([n, at]) => `${n} (${at.join(', ')})`)
      .join('; ')}`,
  )
}

const groups = grouping.groups
  .map((g) => ({
    ...g,
    issues: g.issues.filter(
      (n, i, arr) => inputSet.has(n) && arr.indexOf(n) === i && placement.get(n)[0] === g.id,
    ),
  }))
  .filter((g) => g.issues.length)

const deferred = grouping.deferred.filter((d) => inputSet.has(d.issue))
const placedSet = new Set([...groups.flatMap((g) => g.issues), ...deferred.map((d) => d.issue)])
const dropped = ISSUES.filter((n) => !placedSet.has(n))

// A dropped issue becomes its own group rather than disappearing. A silent cap
// is the one thing a partition must never do.
if (dropped.length) {
  log(`grouping omitted ${dropped.length} issue(s); dispatching each standalone: ${dropped.join(', ')}`)
  for (const n of dropped) {
    groups.push({ id: `recovered-${n}`, issues: [n], reason: 'omitted by grouping; standalone' })
  }
}

if (!groups.length) {
  log(`every issue was deferred (${deferred.length}) — nothing to implement; abort`)
  return { abort: true, reason: 'all-deferred', deferred }
}

if (groups.length === 1) {
  // Every issue conflicts with every other, so the "parallel" run is one
  // sequential lane. Hand the partition back rather than paying a worktree for
  // work the linear path does identically.
  log('grouping produced a single group — the linear path is equivalent; abort with the partition')
  return { abort: true, reason: 'single-group', groups, deferred }
}

// ---------------------------------------------------------------------------
// Implement — fan out, <=WAVE worktree agents in flight. Commit-local only.
// ---------------------------------------------------------------------------

phase(`Implement — ${groups.length} conflict-free groups, one worktree each, <=${WAVE} in flight`)

const implemented = []

for (let i = 0; i < groups.length; i += WAVE) {
  const wave = groups.slice(i, i + WAVE)
  const got = await parallel(
    wave.map((g) => () =>
      agent(IMPL_PROMPT(g), {
        label: `group:${g.id}`,
        phase: 'Implement',
        schema: IMPL_SCHEMA,
        model: 'opus',
        effort: 'high',
        // PRESERVE. Groups branch and commit concurrently; without a worktree
        // each they would fight over one checkout. See
        // `.claude/rules/agent-coworker-detection.md`.
        isolation: 'worktree',
      }),
    ),
  )
  // A null return is a missing verdict, not a finished group. Convert it into an
  // explicit FAILED row so it reaches the caller instead of vanishing.
  implemented.push(
    ...got.map((r, j) =>
      r ?? {
        group: wave[j].id,
        issues: wave[j].issues.map((n) => ({
          issue: n,
          outcome: 'failed',
          branch: '',
          commits: [],
          summary: 'agent returned null',
        })),
        status: 'FAILED',
        blockers: ['agent returned null; re-dispatch this group fresh and sequentially'],
      },
    ),
  )
}

// ---------------------------------------------------------------------------
// The finalise plan is a PROJECTION, not a judgement: one entry per branch that
// actually carries commits, in dispatch order. The caller pushes and opens the
// PRs sequentially, OUTSIDE this harness.
// ---------------------------------------------------------------------------

const finalisePlan = implemented.flatMap((g) =>
  (g.issues ?? [])
    .filter((row) => row.outcome === 'implemented' && row.branch && row.commits.length)
    .map((row) => ({ group: g.group, issue: row.issue, branch: row.branch, summary: row.summary })),
)

const failed = implemented.filter((g) => g.status !== 'COMPLETE')
if (failed.length) log(`${failed.length} group(s) did not complete — see status/blockers before finalising`)

return { groups, deferred, implemented, finalisePlan }
