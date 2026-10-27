/**
 * issue-triage.workflow.js — the read-only pre-pass of `git-plugin:git-issue`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: fan-out, a barrier, then a pure-JS projection.
 *   Fan-out unit  — one read-only assessor per caller BATCH. It classifies each
 *                   issue by whether an agent can finish it unattended and
 *                   re-verifies the issue's evidence at the base ref.
 *   Loop bound    — `args.batches`, the caller's issue lists. Assessors classify
 *                   that set; nothing downstream can extend it, and every
 *                   return is validated against it rather than trusted.
 *   Barrier       — Slice. ONE agent sees every assessment at once and groups
 *                   the `autonomous` issues into conflict-free implementation
 *                   slices. Two issues in different batches that touch one file
 *                   are invisible to a per-batch slicer — that is the defect of
 *                   slicing inside each assessor, which is why this is a
 *                   separate stage and why it is ONE agent.
 *   Projection    — plain JS, no agent: partition validation, file-overlap
 *                   serialisation, dependency layering, and chunking into waves
 *                   of `workflow-orchestration-plugin:workflow-implement-verify`
 *                   units. A sort is not a judgement; an agent asked to do it
 *                   would launder one into the other.
 *
 * Landing: none. No agent here edits, stages, commits, pushes, comments, or
 * changes an issue. The plan returns to the caller, a human picks, and
 * `issue-group-wave` or `workflow-implement-verify` implements. No agent runs in
 * a worktree, so the resume and finalise clauses of the sibling template do not
 * apply here.
 *
 * Three things this deliberately does NOT do:
 *   1. No slicing inside the assessors. Each assessor sees one batch; a slice
 *      plan built from one batch cannot see another batch's files.
 *   2. No agent re-deriving merged-PR links. Pass `git-triage.sh` output as
 *      `args.progress` and the `ISSUE_<n>_MERGED_PRS` / `_CLOSE_CANDIDATE` keys
 *      go into the brief — re-deriving them in agents is the cost rule run
 *      backwards (`.claude/rules/workflow-vs-skill.md`).
 *   3. No `AskUserQuestion`. Anything the issue needs a person for is a class
 *      (`needs_human`, `decision_needed`, …) in `deferred`, handed back.
 */

export const meta = {
  name: 'issue-triage',
  description:
    'Assess caller-supplied issue batches read-only, then propose conflict-free implementation slices shaped as workflow-implement-verify units.',
  phases: [{ title: 'Assess' }, { title: 'Slice' }],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})
const REPO = INPUT.repo ?? '<owner>/<repo>'
const CHECKOUT = INPUT.checkout ?? '<absolute path of a checkout of the repo>'
const BASE = INPUT.base ?? 'origin/main'
const OVERLAP_PRS = (INPUT.overlapPRs ?? []).map(Number).filter((n) => Number.isInteger(n) && n > 0)

// PRESERVE: the class enum is closed. Per-project environment needs (a GPU box,
// a production database) collapse into `needs_env` plus a reason string; refine
// what a class means for this project through `args.classes`, never add a class.
const CLASSES = ['autonomous', 'needs_human', 'decision_needed', 'needs_env', 'already_done', 'too_large', 'stale']
const SLICER_DEFER = ['blocked', 'overlaps-open-pr', 'low-confidence']
const CLASS_NOTES = Object.entries(INPUT.classes ?? {}).filter(([k]) => CLASSES.includes(k))
const unknownClasses = Object.keys(INPUT.classes ?? {}).filter((k) => !CLASSES.includes(k))
if (unknownClasses.length) log(`args.classes keys outside the closed enum ignored: ${unknownClasses.join(', ')}`)

// ADAPT the numbers, PRESERVE the shape. One batch is the linear path: an agent
// that assesses one batch can slice it in the same pass.
const FLOOR = 2
// Read-only agents, but each runs gh and git against one remote; pace the burst.
const WAVE = Number(INPUT.parallel) > 0 ? Number(INPUT.parallel) : 4
// workflow-implement-verify's MAX_UNITS. A wave wider than this would abort there.
const IMPL_MAX_UNITS = 5

// Batches: `{ key, issues: [n], hint? }`, or a bare array of numbers.
const RAW_BATCHES = Array.isArray(INPUT) ? INPUT : (INPUT.batches ?? [])
const toNum = (n) => Number(typeof n === 'object' && n !== null ? n.number : n)
const seenIssue = new Set()
const BATCHES = RAW_BATCHES.map((b, i) => {
  const raw = Array.isArray(b) ? b : (b.issues ?? [])
  const issues = raw.map(toNum).filter((n) => Number.isInteger(n) && n > 0)
  const repeated = issues.filter((n) => seenIssue.has(n))
  if (repeated.length) log(`batch ${i + 1}: issues already in an earlier batch, assessed there: ${repeated.join(', ')}`)
  const own = [...new Set(issues.filter((n) => !seenIssue.has(n)))]
  for (const n of own) seenIssue.add(n)
  return { key: String((!Array.isArray(b) && b.key) || `batch-${i + 1}`), issues: own, hint: Array.isArray(b) ? '' : (b.hint ?? '') }
}).filter((b) => b.issues.length)
const ISSUES = BATCHES.flatMap((b) => b.issues)

// `git-triage.sh` progress keys, as its raw stdout or as an object keyed by issue.
const PROGRESS = new Map()
if (typeof INPUT.progress === 'string') {
  for (const line of INPUT.progress.split('\n')) {
    const m = line.match(/^ISSUE_(\d+)_(MERGED_PRS|CLOSE_CANDIDATE)=(.*)$/)
    if (m) PROGRESS.set(Number(m[1]), [...(PROGRESS.get(Number(m[1])) ?? []), `${m[0]}`])
  }
} else if (INPUT.progress && typeof INPUT.progress === 'object') {
  for (const [n, v] of Object.entries(INPUT.progress)) {
    PROGRESS.set(Number(n), Object.entries(v).map(([k, val]) => `ISSUE_${n}_${k.toUpperCase()}=${val}`))
  }
}

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums. Every input issue ends in exactly one
// slice or in `deferred` with a named reason; there is no third outcome.
// ---------------------------------------------------------------------------

const ASSESS_SCHEMA = {
  type: 'object',
  required: ['batch', 'issues'],
  additionalProperties: false,
  properties: {
    batch: { type: 'string' },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['number', 'title', 'class', 'reason', 'still_true_at_head', 'evidence', 'size', 'files', 'scope', 'doable_part', 'blockers', 'overlap_prs'],
        additionalProperties: false,
        properties: {
          number: { type: 'integer' },
          title: { type: 'string' },
          class: { type: 'string', enum: CLASSES },
          reason: { type: 'string', description: 'why this class; for needs_env, which environment' },
          still_true_at_head: { type: 'string', enum: ['true', 'partly', 'false', 'no-evidence-cited'] },
          evidence: { type: 'string', description: `file:line at ${BASE}, the PR that fixed it, or the options for decision_needed` },
          size: { type: 'string', enum: ['S', 'M', 'L'] },
          files: { type: 'array', items: { type: 'string' }, description: 'repo-relative paths a fix would touch' },
          scope: { type: 'string', description: 'autonomous only: approach, tests to add, verification commands; else ""' },
          doable_part: { type: 'string', description: 'a mixed issue: the part an agent could do now; else ""' },
          blockers: { type: 'string', description: 'the decision, access or action a person must supply; else ""' },
          overlap_prs: { type: 'array', items: { type: 'integer' }, description: 'open PRs sharing files with a fix' },
        },
      },
    },
  },
}

const SLICE_SCHEMA = {
  type: 'object',
  required: ['slices', 'deferred'],
  additionalProperties: false,
  properties: {
    slices: {
      type: 'array',
      items: {
        type: 'object',
        required: ['name', 'issues', 'files', 'depends_on', 'brief'],
        additionalProperties: false,
        properties: {
          name: { type: 'string', description: 'kebab-case; becomes the unit id and fix/<name> branch' },
          issues: { type: 'array', items: { type: 'integer' } },
          files: { type: 'array', items: { type: 'string' } },
          depends_on: { type: 'array', items: { type: 'string' }, description: 'names of slices that must land first' },
          brief: { type: 'string', description: 'what the implementer needs: approach, files, tests, verification commands' },
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
          reason: { type: 'string', enum: SLICER_DEFER },
          detail: { type: 'string' },
        },
      },
    },
  },
}

// ---------------------------------------------------------------------------
// Prompts — ADAPT the project context. Keep the read-only clause, the
// read-from-the-ref clause, "exactly one item per input", and "partition, do
// not extend".
// ---------------------------------------------------------------------------

const ASSESS_PROMPT = (b) => `You assess GitHub issues in ${REPO} for an unattended coding agent. Run commands
from the checkout at ${CHECKOUT}.
READ-ONLY: do not edit files, create branches, stage, commit, push, comment on, label or close anything.

Issues to assess: ${b.issues.join(', ')}
${b.hint ? `Batch context: ${b.hint}\n` : ''}${OVERLAP_PRS.length ? `Open PRs to check for overlap: ${OVERLAP_PRS.map((n) => `#${n}`).join(', ')}\n` : ''}${
  b.issues.some((n) => PROGRESS.has(n))
    ? `Progress keys from git-triage.sh (a hint to verify, never a verdict):\n${b.issues.flatMap((n) => PROGRESS.get(n) ?? []).join('\n')}\n`
    : ''
}
For each issue:
1. Read the full thread (gh issue view <n> -R ${REPO} --comments) and scope it per
   git-plugin:git-issue-scoping: the body is the opening position, a later comment may have
   narrowed, reversed or resolved it.
2. Re-verify the cited evidence at ${BASE}, never at the checkout's working tree: git fetch origin,
   then git show ${BASE}:<path>. Report still_true_at_head and cite file:line.
3. Check whether it is already fixed at ${BASE} or covered by an open or merged PR
   (gh pr list -R ${REPO} --state all --search "<n>", git log ${BASE} --grep "#<n>"). Name the
   open PRs that share files with a fix in overlap_prs.
4. Classify:
   - autonomous: an agent can finish it in one PR from a fresh worktree, verified by local tests,
     typecheck or lint — no open decision, no production access, no secrets or paid API runs.
   - needs_human: a person must act, watch, listen, or make a taste judgement.
   - decision_needed: two valid designs and the thread does not choose. Put the options and your
     recommendation in evidence.
   - needs_env: verifying or fixing it needs an environment this agent lacks; name it in reason.
   - already_done: fixed at ${BASE} or by a merged PR; the evidence names which.
   - too_large: autonomous in principle but more than one focused PR.
   - stale: superseded or no longer applicable.
${CLASS_NOTES.map(([k, v]) => `   For this project, ${k} also means: ${v}`).join('\n')}
   A mixed issue gets the class of the part that blocks it; describe the doable part in doable_part.
5. Estimate size S/M/L and list the repo-relative files a fix would touch.
6. For autonomous issues, write scope: approach, tests to add, verification commands.

Return exactly one item per issue listed above — no more, no fewer, no other numbers.`

const SLICE_PROMPT = (rows, sliceable) => `You are the slicing stage of a read-only issue triage of ${REPO}. You see every
assessment at once because file overlap is pairwise across the whole set: two issues assessed in
different batches can touch the same file.

Assessments (JSON):
${JSON.stringify(rows, null, 1)}

Slice ONLY these autonomous issues: ${sliceable.join(', ')}
The other assessments are context — an autonomous issue may depend on one of them.

Rules:
- Put issues that touch the same files, or that only make sense together, into one slice. Slices
  are implemented in parallel, each in its own worktree, so two slices must not edit one file
  unless one depends_on the other.
- An independent issue is its own slice.
- depends_on names slices that must land first. Keep it empty unless the order is real.
- brief is what the implementer reads: the approach, the files, the tests to add, the
  verification commands. Build it from the assessments' scope; the implementer has not seen them.
- name is kebab-case and unique; it becomes the branch fix/<name>.
- Defer an issue instead of slicing it when it is blocked by an issue or PR outside the slices
  ("blocked"), it overlaps an open PR that should land first ("overlaps-open-pr"), or the
  assessment is too thin to implement from ("low-confidence").

Partition, do not extend: every listed autonomous issue appears exactly once across slices and
deferred, and no other number appears anywhere.
READ-ONLY: you may read code and run gh/git queries; do not edit, commit, push or comment.`

// ---------------------------------------------------------------------------
// Guards. Each returns an explicit, named abort — never a silent no-op.
// ---------------------------------------------------------------------------

if (!ISSUES.length) {
  log('no issues in args.batches — nothing to assess; abort')
  return { abort: true, reason: 'no-issues' }
}

if (BATCHES.length < FLOOR) {
  log(`${BATCHES.length} batch(es) (< ${FLOOR}) — one agent can assess and slice a single batch in one pass; abort`)
  return { abort: true, reason: 'below-floor', batches: BATCHES.length, issues: ISSUES.length }
}

// ---------------------------------------------------------------------------
// Assess — fan out, one read-only agent per batch, <=WAVE in flight.
// ---------------------------------------------------------------------------

phase(`Assess — ${ISSUES.length} issues in ${BATCHES.length} batches, one read-only agent each, <=${WAVE} in flight`)

const assessments = []
const deferred = []
const placed = new Set()
const defer = (issue, reason, detail) => {
  if (placed.has(issue)) return
  placed.add(issue)
  deferred.push({ issue, reason, detail })
}

for (let i = 0; i < BATCHES.length; i += WAVE) {
  const wave = BATCHES.slice(i, i + WAVE)
  const got = await parallel(
    wave.map((b) => () =>
      agent(ASSESS_PROMPT(b), {
        label: `assess:${b.key}`,
        phase: 'Assess',
        schema: ASSESS_SCHEMA,
        model: 'opus',
        effort: 'medium',
      }),
    ),
  )
  // PRESERVE: validate each return against its own batch. An invented number is
  // discarded, a repeated one keeps its first row, and an omitted one — or a
  // whole batch whose agent died — is deferred as `unassessed`, never dropped.
  got.forEach((r, j) => {
    const b = wave[j]
    const mine = new Set(b.issues)
    const rows = (r?.issues ?? []).map((x) => ({ ...x, number: Number(x.number) }))
    const invented = rows.filter((x) => !mine.has(x.number)).map((x) => x.number)
    if (invented.length) log(`assess:${b.key} returned issues outside its batch, discarded: ${invented.join(', ')}`)
    const kept = new Map()
    for (const x of rows) if (mine.has(x.number) && !kept.has(x.number)) kept.set(x.number, { ...x, batch: b.key })
    for (const n of b.issues) {
      if (kept.has(n)) assessments.push(kept.get(n))
      else defer(n, 'unassessed', r ? `omitted by assess:${b.key}` : `assess:${b.key} returned null`)
    }
  })
}

// PRESERVE: the class decides. Anything but `autonomous` is deferred under its
// own class; the slicer never sees it as sliceable.
for (const a of assessments) {
  if (a.class !== 'autonomous') defer(a.number, CLASSES.includes(a.class) ? a.class : 'needs_human', a.reason ?? '')
}
const byNumber = new Map(assessments.map((a) => [a.number, a]))
const SLICEABLE = assessments.filter((a) => a.class === 'autonomous').map((a) => a.number)

// ---------------------------------------------------------------------------
// Slice — BARRIER. One agent over every assessment. Skipped when there is
// nothing to partition: zero autonomous issues, or one (a standalone slice).
// ---------------------------------------------------------------------------

let proposal = { slices: [], deferred: [] }

if (SLICEABLE.length === 1) {
  const a = byNumber.get(SLICEABLE[0])
  proposal = { slices: [{ name: `issue-${a.number}`, issues: [a.number], files: a.files ?? [], depends_on: [], brief: a.scope ?? '' }], deferred: [] }
} else if (SLICEABLE.length > 1) {
  phase(`Slice — BARRIER: ${SLICEABLE.length} autonomous issues across ${BATCHES.length} batches, one agent`)
  const sliced = await agent(SLICE_PROMPT(assessments, SLICEABLE), {
    label: 'slice',
    phase: 'Slice',
    schema: SLICE_SCHEMA,
    model: 'opus',
    effort: 'high',
  })
  if (!sliced) {
    log('slicing returned null — refusing to return an unpartitioned plan; abort with the assessments')
    return { abort: true, reason: 'slicing-failed', assessments, deferred }
  }
  proposal = sliced
}

// ---------------------------------------------------------------------------
// Projection — plain JS from here. PRESERVE every step: it is what makes the
// plan conflict-free regardless of what the slicer returned.
// ---------------------------------------------------------------------------

// 1. Partition validation: the slicer decides the SHAPE, never the EXTENT.
const inputSet = new Set(ISSUES)
const sliceableSet = new Set(SLICEABLE)
const owner = new Map()
const slices = []
const usedIds = new Set()
const slug = (s, i) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || `slice-${i + 1}`
const uniqueId = (base) => {
  let id = base
  for (let k = 2; usedIds.has(id); k++) id = `${base}-${k}`
  usedIds.add(id)
  return id
}

;(proposal.slices ?? []).forEach((s, i) => {
  const issues = []
  for (const raw of s.issues ?? []) {
    const n = Number(raw)
    if (!inputSet.has(n)) {
      log(`slice "${s.name}" names issue ${n} outside the input, discarded`)
    } else if (!sliceableSet.has(n)) {
      log(`slice "${s.name}" names issue ${n}, classed ${byNumber.get(n)?.class ?? 'unassessed'}; the class wins`)
    } else if (owner.has(n)) {
      log(`issue ${n} placed in more than one slice, keeping "${owner.get(n)}"`)
    } else {
      owner.set(n, s.name)
      issues.push(n)
    }
  }
  if (issues.length) slices.push({ name: s.name, id: uniqueId(slug(s.name, i)), issues, files: s.files ?? [], depends_on: s.depends_on ?? [], brief: s.brief ?? '' })
})

for (const d of proposal.deferred ?? []) {
  const n = Number(d.issue)
  if (sliceableSet.has(n) && !owner.has(n)) defer(n, SLICER_DEFER.includes(d.reason) ? d.reason : 'low-confidence', d.detail ?? '')
}

// An omitted autonomous issue becomes its own slice rather than disappearing.
for (const n of SLICEABLE) {
  if (owner.has(n) || placed.has(n)) continue
  log(`slicing omitted issue ${n}; recovering it as a standalone slice`)
  const a = byNumber.get(n)
  owner.set(n, `recovered-${n}`)
  slices.push({ name: `recovered-${n}`, id: uniqueId(`recovered-${n}`), issues: [n], files: [], depends_on: [], brief: a.scope ?? '' })
}

// 2. A slice owns its own files plus every file its issues' assessments named,
//    so overlap detection never rests on the slicer alone.
for (const s of slices) {
  s.files = [...new Set([...s.files, ...s.issues.flatMap((n) => byNumber.get(n)?.files ?? [])])]
  if (!s.brief) s.brief = s.issues.map((n) => `#${n}: ${byNumber.get(n)?.scope ?? ''}`).join('\n')
}

// 3. Dependencies by id; unknown or self references dropped.
const idOf = new Map()
for (const s of slices) {
  idOf.set(s.name, s.id)
  idOf.set(s.id, s.id)
}
for (const s of slices) {
  const deps = s.depends_on.map((d) => idOf.get(d)).filter((d) => d && d !== s.id)
  const dropped = s.depends_on.filter((d) => !idOf.has(d))
  if (dropped.length) log(`slice ${s.id}: unknown depends_on dropped: ${dropped.join(', ')}`)
  s.depends_on = [...new Set(deps)]
}

// 4. File-overlap serialisation. Two slices sharing a file with no order
//    between them get one: the later depends on the earlier. Exact path match,
//    or a directory entry (ending in '/') that contains the other path.
const byId = new Map(slices.map((s) => [s.id, s]))
const overlaps = (a, b) => a === b || (a.endsWith('/') && b.startsWith(a)) || (b.endsWith('/') && a.startsWith(b))
const reaches = (from, to, seen = new Set()) => {
  if (from === to) return true
  if (seen.has(from)) return false
  seen.add(from)
  return (byId.get(from)?.depends_on ?? []).some((d) => reaches(d, to, seen))
}
for (let i = 0; i < slices.length; i++) {
  for (let j = i + 1; j < slices.length; j++) {
    const [a, b] = [slices[i], slices[j]]
    const shared = a.files.filter((f) => b.files.some((g) => overlaps(f, g)))
    if (shared.length && !reaches(a.id, b.id) && !reaches(b.id, a.id)) {
      b.depends_on.push(a.id)
      log(`slices ${a.id} and ${b.id} share ${shared.join(', ')}; ${b.id} now depends on ${a.id}`)
    }
  }
}

// 5. Layering. A slice joins the first layer after all its dependencies. What
//    never becomes ready is a cycle (or depends on one): deferred, not dispatched.
const layers = []
const done = new Set()
let pending = [...slices]
while (pending.length) {
  const ready = pending.filter((s) => s.depends_on.every((d) => done.has(d)))
  if (!ready.length) break
  layers.push(ready)
  for (const s of ready) done.add(s.id)
  pending = pending.filter((s) => !done.has(s.id))
}
for (const s of pending) {
  log(`slice ${s.id} is in or behind a dependency cycle; deferred`)
  for (const n of s.issues) defer(n, 'dependency-cycle', `slice ${s.id} depends on ${s.depends_on.join(', ')}`)
}
const planned = slices.filter((s) => done.has(s.id))

// 6. Waves: each is a valid `args.units` for workflow-implement-verify — its
//    slices are independent of each other and own disjoint files — chunked at
//    that template's unit cap.
const toUnit = (s) => ({ id: s.id, issues: s.issues, branch: `fix/${s.id}`, brief: s.brief, owns: s.files, labels: [] })
const waves = layers.flatMap((layer) => {
  const out = []
  for (let k = 0; k < layer.length; k += IMPL_MAX_UNITS) out.push(layer.slice(k, k + IMPL_MAX_UNITS).map(toUnit))
  return out
})

const summary = {
  issues: ISSUES.length,
  assessed: assessments.length,
  sliced: planned.reduce((n, s) => n + s.issues.length, 0),
  deferred: deferred.length,
}
log(`plan: ${summary.sliced} issue(s) in ${planned.length} slice(s) over ${waves.length} wave(s); ${summary.deferred} deferred`)

return {
  assessments,
  slices: planned.map(({ name, id, issues, files, depends_on, brief }) => ({ name, id, issues, files, depends_on, brief })),
  deferred,
  waves,
  summary,
}
