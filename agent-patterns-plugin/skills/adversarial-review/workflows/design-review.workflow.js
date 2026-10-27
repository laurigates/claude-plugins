/**
 * design-review.workflow.js — an architect drafts an implementation-ready spec,
 * two or three lens reviewers try to break it, and the architect resolves every
 * finding with evidence.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: Draft (1) → Review (one per lens, ≤ 3) → Revise (1).
 *   Fan-out unit  — one reviewer per `args.lenses` entry. An over-cap list
 *                   aborts; it is never truncated.
 *   Barrier       — Revise. It reads every review at once, because two lenses
 *                   can attack the same section from opposite sides and the
 *                   resolution has to weigh both.
 *   Stop judge    — none: one review round, then one revise. A spec that still
 *                   fails after that has a structural problem (SKILL.md Step 5).
 *
 * Recon is an input, not a phase: run it earlier (or by hand) and pass the
 * report paths. A failed design run then does not repeat recon.
 *
 * Read-only for the repository: agents write only the spec file and scratch
 * experiments under `args.scratch`. Nothing commits, pushes or touches GitHub.
 */

export const meta = {
  name: 'design-review',
  description: 'Draft an implementation spec, attack it with 2–3 lens reviewers, then revise it against the findings.',
  phases: [{ title: 'Draft' }, { title: 'Review' }, { title: 'Revise' }],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the numbers, PRESERVE the shape. One lens is a linear pass: draft, ask
// one reviewer inline, revise.
const MIN_LENSES = 2
const MAX_LENSES = 3

const SPEC = String(INPUT.spec_path ?? '')
const CTX = {
  root: INPUT.root ?? '<absolute path of a clean checkout or worktree at base_ref>',
  main: INPUT.main ?? '',
  base: INPUT.base_ref ?? 'origin/main',
  head: INPUT.head ?? '',
  context: INPUT.context ?? '',
  decisions: INPUT.decisions ?? [],
  defaults: INPUT.defaults ?? [],
  recon: INPUT.recon ?? [],
  shape: INPUT.spec_shape ?? [],
  scratch: INPUT.scratch ?? SPEC.replace(/\/[^/]*$/, '') + '/scratch',
}
const REVISE = INPUT.revise !== false
const LENSES = (INPUT.lenses ?? []).map((l, i) => ({
  key: String(l.key ?? `lens-${i + 1}`),
  attack: l.attack ?? l.prompt ?? '',
  skills: l.skills ?? [],
}))

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums.
// ---------------------------------------------------------------------------

const DECISIONS = {
  type: 'array',
  items: {
    type: 'object',
    required: ['question', 'recommendation', 'tasteCall'],
    additionalProperties: false,
    properties: {
      question: { type: 'string' },
      recommendation: { type: 'string' },
      tasteCall: { type: 'boolean', description: 'true only when code, PRD and stories cannot decide it' },
    },
  },
}
const DESIGN_SCHEMA = {
  type: 'object',
  required: ['spec_path', 'summary', 'changes', 'done_criteria', 'risks', 'experiments', 'decisions_for_user'],
  additionalProperties: false,
  properties: {
    spec_path: { type: 'string' },
    summary: { type: 'string', description: '≤ 40 lines' },
    changes: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'what', 'files', 'depends_on', 'size'],
        additionalProperties: false,
        properties: {
          id: { type: 'string' },
          what: { type: 'string' },
          files: { type: 'array', items: { type: 'string' } },
          depends_on: { type: 'array', items: { type: 'string' } },
          size: { type: 'string', enum: ['S', 'M', 'L'] },
        },
      },
    },
    done_criteria: { type: 'array', items: { type: 'string' }, description: 'each with the gate command that proves it' },
    risks: { type: 'array', items: { type: 'string' } },
    experiments: {
      type: 'array',
      items: {
        type: 'object',
        required: ['command', 'result'],
        additionalProperties: false,
        properties: { command: { type: 'string' }, result: { type: 'string' } },
      },
    },
    decisions_for_user: DECISIONS,
    resolution: {
      type: 'array',
      description: 'Revise only: one row per review issue',
      items: {
        type: 'object',
        required: ['lens', 'issue', 'decision', 'evidence'],
        additionalProperties: false,
        properties: {
          lens: { type: 'string' },
          issue: { type: 'string' },
          decision: { type: 'string', enum: ['accepted', 'rejected'] },
          evidence: { type: 'string', description: 'the line read or the command run that decided it' },
        },
      },
    },
  },
}
const REVIEW_SCHEMA = {
  type: 'object',
  required: ['verdict', 'issues', 'checked'],
  additionalProperties: false,
  properties: {
    verdict: { type: 'string', enum: ['sound', 'sound-with-fixes', 'unsound'] },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['target', 'problem', 'evidence', 'severity', 'fix'],
        additionalProperties: false,
        properties: {
          target: { type: 'string', description: 'spec section' },
          problem: { type: 'string' },
          evidence: { type: 'string', description: 'command + output, or file:line' },
          severity: { type: 'string', enum: ['blocking', 'major', 'minor'] },
          fix: { type: 'string' },
        },
      },
    },
    checked: { type: 'array', items: { type: 'string' }, description: 'what you tried to break; required even when issues is empty' },
  },
}

// ---------------------------------------------------------------------------
// Prompts — ADAPT the wording, keep the clauses.
// ---------------------------------------------------------------------------

const listOr = (xs, none) => (xs.length ? xs.map((x) => `  - ${x}`).join('\n') : `  ${none}`)
const common = () => `${CTX.context}

Code to read: ${CTX.root} at ${CTX.base}${CTX.head ? ` (head ${CTX.head})` : ''}; or \`git show ${CTX.base}:<path>\`.
${CTX.main ? `Never touch the main checkout ${CTX.main}: it may hold someone else's uncommitted work.\n` : ''}Read-only for the repository: do not edit, stage, commit, push, comment, or touch the stash.
Scratch experiments go only under ${CTX.scratch} (mkdir -p).
${CTX.recon.length ? `Recon reports — read ALL of them first; they carry verified facts with file:line evidence:\n${listOr(CTX.recon, '')}\n` : ''}
Decisions the user made — binding. Relay them as theirs; do not relitigate or widen them:
${listOr(CTX.decisions, '(none)')}
Defaults chosen by the orchestrator — adjust them when evidence says they are wrong, and say so:
${listOr(CTX.defaults, '(none)')}

Every claim cites file:line, or a command and its observed output. Mark each claim [V] verified this session
or [I] inference. Settle feasibility questions by running an experiment, not by guessing; report what you ran.`

const DRAFT_PROMPT = () => `${common()}

You are the ARCHITECT. Write an implementation-ready spec to ${SPEC} for agents who did not read the recon.
${CTX.shape.length ? `It must contain:\n${CTX.shape.map((s, i) => `${i + 1}. ${s}`).join('\n')}` : 'Cover: interfaces and data shapes, every file touched, the test plan with the gate commands, and an ordered work breakdown.'}
Put a question in decisions_for_user only when code, PRD and stories cannot decide it; give a recommended default.`

const REVIEW_PROMPT = (l) => `${common()}

You are an ADVERSARIAL REVIEWER. Read the spec at ${SPEC}. Try to BREAK it along the "${l.key}" lens:
${l.attack}
${l.skills.length ? `Invoke ${l.skills.join(', ')} with the Skill tool for this lens's checklist.\n` : ''}
Do not restate the parts that are correct. Reproduce each critical claim you attack with a minimal experiment
under ${CTX.scratch}/review-${l.key}/. An empty issues list is valid only when "checked" lists what you tried.`

const REVISE_PROMPT = (reviews) => `${common()}

You are the ARCHITECT again. Your draft is at ${SPEC}. Adversarial reviews follow. Reviews can be wrong:
verify each issue against the source or by experiment before acting on it. Update ${SPEC} in place so it
resolves every accepted issue, and append a "Review resolution" section listing each issue as accepted or
rejected with the evidence. Return one resolution row per issue.

${reviews.map((r) => `===== REVIEW: ${r.lens} (${r.verdict}) =====\n${JSON.stringify(r.issues, null, 1)}`).join('\n\n')}`

// PRESERVE: one literal call site per stage, so every model and effort is checkable.
const draft = () => agent(DRAFT_PROMPT(), { label: 'architect:draft', phase: 'Draft', schema: DESIGN_SCHEMA, model: 'opus', effort: 'xhigh' })
const revise = (reviews) =>
  agent(REVISE_PROMPT(reviews), { label: 'architect:revise', phase: 'Revise', schema: DESIGN_SCHEMA, model: 'opus', effort: 'high' })

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort.
// ---------------------------------------------------------------------------

if (!SPEC.startsWith('/')) {
  log('args.spec_path must be an absolute path — every stage reads and writes it; abort')
  return { abort: true, reason: 'no-spec-path' }
}
if (LENSES.length < MIN_LENSES) {
  log(`${LENSES.length} lens(es) (< ${MIN_LENSES}) — draft, review inline, revise; abort`)
  return { abort: true, reason: 'below-floor', lenses: LENSES.length }
}
if (LENSES.length > MAX_LENSES) {
  log(`${LENSES.length} lenses (> ${MAX_LENSES}) — merge lenses; abort without truncating`)
  return { abort: true, reason: 'over-cap', lenses: LENSES.map((l) => l.key) }
}

// ---------------------------------------------------------------------------
// Draft → Review → (barrier) → Revise
// ---------------------------------------------------------------------------

phase('Draft')
const drafted = await draft()
if (!drafted) {
  log('architect draft returned nothing — no spec to review; abort')
  return { abort: true, reason: 'draft-failed' }
}

phase('Review')
// PRESERVE the literal bound in the fan-out, with agent() inline: the scale guard counts it.
const got = await parallel(
  LENSES.slice(0, 3).map((l) => () =>
    agent(REVIEW_PROMPT(l), { label: `review:${l.key}`, phase: 'Review', schema: REVIEW_SCHEMA, model: 'opus', effort: 'high' }),
  ),
)
const reviews = []
const reviewsFailed = []
got.forEach((r, j) => {
  const l = LENSES[j]
  if (!r || !Array.isArray(r.issues)) return reviewsFailed.push(l.key)
  reviews.push({ lens: l.key, ...r })
})
if (reviewsFailed.length) log(`reviewer(s) returned nothing: ${reviewsFailed.join(', ')} — that lens is unreviewed`)

// A spec no reviewer read is not "clean": say so instead of revising blind.
if (!reviews.length) return { status: 'unreviewed', draft: drafted, reviews, reviewsFailed, final: null }
const issues = reviews.reduce((n, r) => n + r.issues.length, 0)
if (!issues) {
  log('every reviewer returned zero issues — nothing to resolve; skipping Revise')
  return { status: 'clean', draft: drafted, reviews, reviewsFailed, final: null }
}
if (!REVISE) return { status: 'reviewed', draft: drafted, reviews, reviewsFailed, final: null }

phase('Revise')
const final = await revise(reviews)
if (!final) log('architect revise returned nothing — the spec on disk is the unrevised draft')
return { status: final ? 'revised' : 'revise-failed', draft: drafted, reviews, reviewsFailed, final }
