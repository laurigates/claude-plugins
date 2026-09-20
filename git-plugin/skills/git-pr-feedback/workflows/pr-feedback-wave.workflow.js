/**
 * pr-feedback-wave.workflow.js — the `--all` path of `git-plugin:git-pr-feedback`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation; the per-PR return contract it enforces is
 * REFERENCE.md "Multi-PR Subagent Prompt".
 *
 * Shape: fan-out-and-synthesize.
 *   Fan-out unit  — one `isolation: 'worktree'` agent per actionable PR. It
 *                   edits and commits inside its own worktree and pushes
 *                   NOTHING.
 *   Loop bound    — `scripts/list-actionable-prs.sh`'s JSON array, passed in as
 *                   `args.prs`. Never a prose "for each open PR": the
 *                   actionable/automation-authored filtering already happened
 *                   in that script, before dispatch.
 *   Barrier       — Finalise plan. Push, reply, resolve and re-request all hit
 *                   ONE shared GitHub rate-limit pool on ONE remote, and Step 7
 *                   owes a combined rollup, so neither the order nor the report
 *                   exists until every PR has landed its commits.
 *
 * Two clauses this template carries. Both are unconditional here — every
 * fanned-out agent runs in a worktree, and this skill's entire output is a
 * forge mutation.
 *
 *   Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents —
 *   a resume re-runs agents that already succeeded and opens duplicate PRs
 *   (#1868; `.claude/rules/agent-coworker-detection.md` § "`Workflow` resume
 *   re-runs already-succeeded worktree agents"). Re-dispatch the failed units
 *   fresh and sequentially, after checking
 *   `gh pr list --head <branch> --state all --json number,state`.
 *
 *   Push, PR creation, replies and thread resolution happen ONLY in the single
 *   sequential finalise stage — SKILL.md Step 1A.7, which runs OUTSIDE this
 *   harness — never inside a fanned-out agent. Every agent below is
 *   commit-local: it may write files and commit in its own worktree, and may
 *   reach GitHub for READS only.
 *
 * Three things this deliberately does NOT do:
 *   1. No classify agent. Whether a PR is actionable is decided by
 *      `list-actionable-prs.sh` before dispatch, and the four-way outcome
 *      classification below is a pure function of the returned contract
 *      (null / `blockers[]` / `commits[]`) — REFERENCE.md "Orchestrator
 *      handling of subagent output" — not a judgement an agent re-derives.
 *   2. No pushing, replying, resolving, or re-requesting. Those share a rate
 *      limit and must be strictly sequential; the harness returns an ordered
 *      `finalisePlan` for the SKILL to apply outside, one PR at a time.
 *   3. No exit code. A workflow returns a value, not a process status — the
 *      skill turns `report.overall` into its Step 7 summary.
 */

export const meta = {
  name: 'pr-feedback-wave',
  description:
    'Address review feedback on every actionable PR in parallel worktrees, then plan one sequential finalise.',
  phases: [{ title: 'Address' }, { title: 'Finalise plan' }],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})
// A bare roster array is accepted as well as `{ prs: [...] }`.
const PRS = Array.isArray(INPUT) ? INPUT : (INPUT.prs ?? [])
const REPO = INPUT.repo ?? '<owner>/<repo>'

// ADAPT the numbers, PRESERVE the shape. The floor is as load-bearing as the
// ceiling: one actionable PR is the modal case and is the prose single-PR path
// (Steps 1-7), where the harness would spend a worktree to save nothing.
const FLOOR = 2

// The concurrency ceiling is the user's `--limit N` (default 3), not a constant
// this file picks. Widening it past what the caller asked for is how a batch
// walks into the burst rate-limit the flag exists to avoid.
const WAVE = Number(INPUT.limit) > 0 ? Number(INPUT.limit) : 3

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the field names and the closed enum. The per-PR schema is
// REFERENCE.md's "Multi-PR Subagent Prompt" contract verbatim: the harness makes
// that contract ENFORCED rather than requested, so "the subagent returned prose"
// stops being a parse problem the orchestrator has to recover from.
// ---------------------------------------------------------------------------

const PR_RESULT_SCHEMA = {
  type: 'object',
  required: [
    'pr',
    'branch',
    'worktree_path',
    'commits',
    'co_authors',
    'addressed',
    'deferred_issues',
    'blockers',
  ],
  additionalProperties: false,
  properties: {
    pr: { type: 'integer' },
    branch: { type: 'string' },
    worktree_path: { type: 'string' },
    commits: {
      type: 'array',
      items: {
        type: 'object',
        required: ['sha', 'summary'],
        additionalProperties: false,
        properties: { sha: { type: 'string' }, summary: { type: 'string' } },
      },
    },
    co_authors: { type: 'array', items: { type: 'string' } },
    addressed: {
      type: 'array',
      items: {
        type: 'object',
        required: ['thread_id', 'database_id', 'action', 'reply', 'resolve'],
        additionalProperties: false,
        properties: {
          thread_id: { type: 'string', description: 'PRRT_… GraphQL node id' },
          database_id: { type: 'integer', description: 'top-level comment databaseId' },
          // Closed by design. A vague "handled it" is structurally impossible,
          // and `decline` / `defer` are first-class outcomes rather than silence.
          action: {
            type: 'string',
            enum: ['fix', 'accept', 'adapt', 'defer', 'answer', 'decline'],
          },
          reply: { type: 'string', description: 'reply text; may contain the {{SHA}} placeholder' },
          resolve: { type: 'boolean' },
        },
      },
    },
    deferred_issues: { type: 'array', items: { type: 'integer' } },
    blockers: { type: 'array', items: { type: 'string' } },
  },
}

const REPORT_SCHEMA = {
  type: 'object',
  required: ['overall', 'counts', 'rows', 'finalisePlan'],
  additionalProperties: false,
  properties: {
    overall: { type: 'string', enum: ['CLEAN', 'PARTIAL', 'BLOCKED'] },
    counts: {
      type: 'object',
      required: ['dispatched', 'ready', 'no_commits', 'blocked', 'parse_error'],
      additionalProperties: false,
      properties: {
        dispatched: { type: 'integer' },
        ready: { type: 'integer' },
        no_commits: { type: 'integer' },
        blocked: { type: 'integer' },
        parse_error: { type: 'integer' },
      },
    },
    rows: {
      type: 'array',
      items: {
        type: 'object',
        required: ['pr', 'status', 'summary'],
        additionalProperties: false,
        properties: {
          pr: { type: 'integer' },
          status: {
            type: 'string',
            enum: ['READY', 'NO_COMMITS', 'BLOCKED', 'PARSE_ERROR'],
          },
          summary: { type: 'string' },
        },
      },
    },
    // Ordered. The SKILL applies these one at a time, outside the harness.
    finalisePlan: {
      type: 'array',
      items: {
        type: 'object',
        required: ['pr', 'branch', 'push', 'replies', 'resolves', 'reason'],
        additionalProperties: false,
        properties: {
          pr: { type: 'integer' },
          branch: { type: 'string' },
          push: { type: 'boolean' },
          replies: { type: 'integer' },
          resolves: { type: 'integer' },
          reason: { type: 'string' },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// Prompts — ADAPT ALL OF THESE. The per-PR brief is REFERENCE.md's template;
// keep its four "the orchestrator handles these instead" constraints intact,
// because they are what make the finalise stage the only mutation site.
// ---------------------------------------------------------------------------

const PR_PROMPT = (row) => `You are addressing review feedback for ONE pull request inside a
fresh git worktree.

Repository: ${REPO}
PR number: #${row.number}
PR head branch: ${row.head}

Constraints — the orchestrator handles these instead, do NOT do them yourself:
- Do NOT git push.
- Do NOT post replies.
- Do NOT resolve review threads.
- Do NOT re-request reviewers.

Steps:

1. Switch this worktree to the PR branch:
     git fetch origin ${row.head}
     git switch ${row.head}
     git pull --ff-only origin ${row.head}
   If --ff-only fails (the branch diverged), stop and report it as a blocker
   reading "branch-out-of-sync"; commit nothing.

2. Follow Steps 1-4 of the sibling SKILL.md for this one PR:
   - gather PR data with scripts/fetch-pr-data.sh;
   - categorise each unresolved, non-outdated thread (Blocking / Substantive /
     Suggestion / Question / Nitpick);
   - VERIFY every claim before accepting it — automated reviewers are
     frequently confidently wrong; a claim that fails verification is refuted,
     the code does not change, and the refutation carries its evidence;
   - make the edits and commit them in THIS worktree, grouping related fixes;
   - record a Co-authored-by trailer per unique suggester for accepted or
     adapted suggestion blocks;
   - file a follow-up issue for out-of-scope feedback and capture its number.

3. Draft, but do NOT post, one reply per actionable thread. Where the reply
   references the resolving commit, write the literal placeholder {{SHA}} — the
   finalise stage substitutes the pushed SHA.

4. Stop. Do not push, reply, or resolve.

Return the contract fields. An empty addressed[] and commits[] is a clean
result, not an error. Default resolve to true; set it false only for a thread
you asked a follow-up question on, a partial fix, or one the reviewer asked to
keep open — and put any open question in blockers[] so it reaches the summary.`

const SYNTH_PROMPT = (results, skipped) => `You are the synthesis stage of a multi-PR review-
feedback run against ${REPO}. Every per-PR agent has already finished; below is the full set,
each row pre-classified from its returned contract. Produce ONE report.

Results (JSON):
${JSON.stringify(results, null, 2)}

Not dispatched (JSON):
${JSON.stringify(skipped, null, 2)}

Required of the report:
  - rows        — one per dispatched PR, carrying its pre-computed status and a
                  one-line summary. Do not re-classify: the status is given.
  - counts      — the roll-up. dispatched is the number of rows.
  - overall     — BLOCKED if every PR is BLOCKED or PARSE_ERROR, else PARTIAL if
                  any is, else CLEAN.
  - finalisePlan— an ORDERED plan the caller applies STRICTLY SEQUENTIALLY, one
                  entry per dispatched PR. This is why you see every PR at once:
                  push, reply, resolve and re-request all draw on one GitHub
                  rate-limit pool, so the order is a cross-PR fact no single
                  agent could know. Rules that are not yours to override:
                    * BLOCKED  -> push:false, and the reason names the blocker.
                                  Never push partial work; the user decides.
                    * PARSE_ERROR -> push:false, reason "parse-error".
                    * NO_COMMITS -> push:false, but replies/resolves still count
                                  (questions answered, nitpicks declined).
                    * READY    -> push:true; replies/resolves are the counts of
                                  addressed[] entries and of those with
                                  resolve:true.
                  Put the heaviest PRs (most replies + resolves) last, so an
                  early rate-limit trip costs the fewest completed PRs.

Apply nothing. You are producing a plan, not executing it.`

// ---------------------------------------------------------------------------
// Guards. Each returns an explicit, named abort — never a silent no-op.
// ---------------------------------------------------------------------------

if (!PRS.length) {
  log('empty roster — list-actionable-prs.sh reported no actionable PRs; abort')
  return { abort: true, reason: 'no-actionable-prs' }
}

if (INPUT.dryRun) {
  // Step 1A.4's short-circuit. --dry-run prints the dispatch table and stops;
  // spending worktree agents to discover that would defeat the flag.
  log(`--dry-run: ${PRS.length} PR(s) would be dispatched, <=${WAVE} in flight; abort`)
  return { abort: true, reason: 'dry-run', prs: PRS.length }
}

if (PRS.length < FLOOR) {
  log(`${PRS.length} actionable PR(s) (< ${FLOOR}) — the single-PR path is cheaper; abort`)
  return { abort: true, reason: 'below-floor', prs: PRS.length }
}

// ---------------------------------------------------------------------------
// Address — fan out, <=WAVE worktree agents in flight. Commit-local only.
// ---------------------------------------------------------------------------

phase(`Address — ${PRS.length} PRs, one worktree each, <=${WAVE} in flight`)

// PRESERVE: a pure function of the returned contract, not a judgement. The
// precedence matters — a returned blocker outranks a returned commit, because
// pushing half of a blocked PR is the outcome this ordering exists to prevent.
const classify = (result) => {
  if (!result) return 'PARSE_ERROR'
  if (result.blockers?.length) return 'BLOCKED'
  if (result.commits?.length) return 'READY'
  return 'NO_COMMITS'
}

const results = []

for (let i = 0; i < PRS.length; i += WAVE) {
  const wave = PRS.slice(i, i + WAVE)
  const got = await parallel(
    wave.map((row) => () =>
      agent(PR_PROMPT(row), {
        label: `pr:${row.number}`,
        phase: 'Address',
        schema: PR_RESULT_SCHEMA,
        model: 'opus',
        effort: 'high',
        // PRESERVE. Several PRs are edited at once; without a worktree each they
        // would fight over one checkout. See
        // `.claude/rules/agent-coworker-detection.md`.
        isolation: 'worktree',
      }),
    ),
  )
  // A null return is a missing verdict, not a clean PR. Convert it into an
  // explicit PARSE_ERROR row so it reaches the report instead of vanishing.
  results.push(
    ...got.map((result, j) => ({
      pr: wave[j].number,
      branch: wave[j].head,
      status: classify(result),
      result: result ?? null,
    })),
  )
}

// ---------------------------------------------------------------------------
// Finalise plan — BARRIER: the order and the rollup are cross-PR facts.
// ---------------------------------------------------------------------------

phase('Finalise plan — BARRIER: one rate-limit pool, so the order needs every PR')

const report = await agent(SYNTH_PROMPT(results, INPUT.skipped ?? []), {
  label: 'finalise-plan',
  phase: 'Finalise plan',
  schema: REPORT_SCHEMA,
  model: 'opus',
  effort: 'medium',
})

if (!report) {
  log('synthesis returned null — surfacing raw per-PR results so the run is not silently empty')
  return { report: null, results, finalisePlan: [] }
}

// The finalise stage runs OUTSIDE this harness, sequentially. The harness hands
// back data; SKILL.md Step 1A.7 does the pushing, replying and resolving.
return { report, finalisePlan: report.finalisePlan, results }
