/**
 * recon-map.workflow.js — a read-only map of a repo, issue, PRD slice or
 * portfolio against a base ref: verified facts plus PR-sized work items that a
 * later design or implementation run can consume.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: fan-out, then a sequential tail where each stage needs everything
 * before it.
 *   Map         — one read-only agent per `args.units` entry, cut at 10 by a
 *                 literal slice. The overflow is logged and returned as
 *                 `dropped_units`, never hidden.
 *   Critic      — (optional) 1 agent; needs every unit report and, when
 *                 `coverage_cmd` is given, that script's UNCOVERED rows.
 *   Gap-fill    — (optional) one agent per critic gap group, cut at 3.
 *   Verify      — (optional) 1 agent; re-runs the evidence of the items the
 *                 mode selects, plus every item from a haiku lean-reader unit.
 *   Synthesize  — (optional) 1 agent; reads only cited, non-rejected items.
 *
 * The verdict bookkeeping is plain JS, not a model's reading: an item with no
 * evidence is dropped before Verify and Synthesize, a rejected item never
 * reaches the synthesizer, and a dead verifier confirms nothing.
 *
 * Nothing here commits, pushes, comments or edits a tracked file. The only
 * writes are scratch files under `args.scratch`.
 */

export const meta = {
  name: 'recon-map',
  description:
    'Read-only recon: map caller-supplied units against a base ref, critique coverage, fill up to 3 gaps, verify non-holding claims, and synthesize PR-sized work items.',
  phases: [
    { title: 'Map' },
    { title: 'Critic' },
    { title: 'Gap-fill' },
    { title: 'Verify' },
    { title: 'Synthesize' },
  ],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the numbers, PRESERVE the shape. The two caps are also written as
// literal slices in the fan-outs below, where the scale guard can count them:
// change MAX_UNITS and `UNITS.slice(0, 10)` together, and MAX_GAPFILL and
// `toFill.slice(0, 3)` together (test-recon-map.sh fails when they differ).
const MAX_UNITS = 10
const MAX_GAPFILL = 3
const MAX_VERIFY_ITEMS = 40

const KINDS = ['claims', 'ac', 'findings']
const TIERS = ['opus', 'sonnet', 'haiku']
const MODES = ['none', 'non-holding', 'all']

const CTX = {
  root: INPUT.root ?? '',
  base: INPUT.base_ref ?? 'origin/main',
  head: INPUT.head ?? '',
  scratch: (INPUT.scratch ?? '').replace(/\/+$/, ''),
  main: INPUT.main_checkout ?? '',
  context: INPUT.context ?? '',
  decisions: INPUT.decisions ?? [],
  pregathered: INPUT.pregathered ?? [],
  skills: INPUT.skills ?? [],
  coverage: INPUT.coverage_cmd ?? '',
}
const KIND = INPUT.unit_kind ?? 'claims'
const TAIL_IN = INPUT.tail ?? {}
const TAIL = {
  critic: TAIL_IN.critic !== false,
  gapfill: Number.isInteger(TAIL_IN.gapfill_cap) ? Math.max(0, Math.min(MAX_GAPFILL, TAIL_IN.gapfill_cap)) : MAX_GAPFILL,
  verify: TAIL_IN.verify ?? 'non-holding',
  synth: TAIL_IN.synth !== false,
}

// Units come from the caller. A list some script or file already enumerates
// (story files, issue claims, coverage rows) is preferred over hand-picked
// lenses; `units_source` only labels which one this run used.
// Effort is fixed per tier (see mapUnit), so a unit's own `effort` is not read.
const ALL_UNITS = (INPUT.units ?? []).map((u, i) => ({
  key: String(u.key ?? `unit-${i + 1}`),
  brief: u.brief ?? '',
  model: u.model || 'opus',
  inputs: u.inputs ?? [],
  effort: u.effort,
}))

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort before any agent runs.
// ---------------------------------------------------------------------------

const abort = (reason, detail) => {
  log(`abort: ${reason}${detail ? ` (${detail})` : ''}`)
  return { abort: true, reason, detail: detail ?? '' }
}
if (!CTX.root) return abort('missing-root', 'pass a clean detached checkout as args.root')
if (!CTX.scratch) return abort('missing-scratch', 'pass a scratch directory as args.scratch')
if (!ALL_UNITS.length) return abort('no-units')
if (!KINDS.includes(KIND)) return abort('bad-unit-kind', `${KIND} is not one of ${KINDS.join(', ')}`)
if (!MODES.includes(TAIL.verify)) return abort('bad-verify-mode', `${TAIL.verify} is not one of ${MODES.join(', ')}`)
{
  const dup = ALL_UNITS.map((u) => u.key).filter((k, i, a) => a.indexOf(k) !== i)
  if (dup.length) return abort('duplicate-unit-key', dup.join(', '))
  // An unknown tier aborts instead of silently running as opus.
  const badModel = ALL_UNITS.filter((u) => !TIERS.includes(u.model)).map((u) => `${u.key}=${u.model}`)
  if (badModel.length) return abort('bad-unit-model', `${badModel.join(', ')}; a unit model is one of ${TIERS.join(', ')}`)
  // A lean reader has Read/Grep/Glob and no project context: it may only read
  // artefacts something else already dumped.
  const blind = ALL_UNITS.filter((u) => u.model === 'haiku' && !u.inputs.length).map((u) => u.key)
  if (blind.length) return abort('haiku-without-inputs', blind.join(', '))
}

const UNITS = ALL_UNITS.slice(0, MAX_UNITS)
const DROPPED = ALL_UNITS.slice(MAX_UNITS).map((u) => u.key)
if (DROPPED.length) log(`${ALL_UNITS.length} units > cap ${MAX_UNITS}; dropped: ${DROPPED.join(', ')} — map them in a second run`)
if (ALL_UNITS.some((u) => u.effort !== undefined)) log('units[].effort is ignored: effort is fixed per tier (haiku medium, sonnet high, opus high)')
if (INPUT.units_source === 'hand-picked') log('units are hand-picked lenses; a deterministic unit list is preferred when one exists')

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums; free text cannot be filtered for the verifier.
// ---------------------------------------------------------------------------

const str = { type: 'string' }
const strs = { type: 'array', items: str }
const obj = (props, required = Object.keys(props)) => ({ type: 'object', required, additionalProperties: false, properties: props })

const SCHEMAS = {
  claims: obj({
    unit: str,
    summary: str,
    items: {
      type: 'array',
      items: obj({
        claim: str,
        status: { type: 'string', enum: ['holds', 'drifted', 'resolved', 'new', 'unverified'] },
        evidence: { type: 'string', description: 'file:line read this session, or a command plus the output line it printed' },
        implication: str,
        verified: { type: 'boolean', description: 'true only if you read or ran the evidence yourself this session' },
      }),
    },
    risks: strs,
    open_questions: strs,
    gaps: { ...strs, description: 'what you were asked to map and could not' },
  }),
  ac: obj({
    unit: str,
    story: str,
    acs: {
      type: 'array',
      items: obj({
        index: { type: 'integer' },
        summary: str,
        status: { type: 'string', enum: ['satisfied', 'partial', 'missing', 'contradicted'] },
        headRefs: {
          ...strs,
          description:
            'file:line references read at the base ref; for a missing AC, the search you ran (command plus its empty output, control-tested) and the closest file:line',
        },
        notes: str,
        remainingWork: str,
      }),
    },
    keyApis: { type: 'array', items: obj({ symbol: str, location: { type: 'string', description: 'file:line' }, signature: str }) },
    staleRefs: { type: 'array', items: obj({ cited: str, actual: str }) },
    risks: strs,
    openQuestions: strs,
  }),
  findings: obj({
    unit: str,
    area: str,
    findings: {
      type: 'array',
      items: obj(
        {
          id: str,
          kind: str,
          severity: { type: 'string', enum: ['high', 'medium', 'low'] },
          evidence: { type: 'string', description: 'file:line, URL, or a command plus the output line it printed' },
          root_cause: str,
          fix: str,
          fix_location: str,
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          existing_pr_or_issue: { type: 'string', description: 'URL of an open PR or issue already on it, or ""' },
        },
        ['id', 'kind', 'severity', 'evidence', 'root_cause', 'fix', 'fix_location', 'confidence', 'existing_pr_or_issue'],
      ),
    },
    reviewed_ok: { type: 'array', items: obj({ item: str, why: str }) },
    notes: str,
  }),
}
const UNIT_SCHEMA = SCHEMAS[KIND]

const CRITIC_SCHEMA = obj({
  coverage_status: str,
  gaps: { type: 'array', items: obj({ units: strs, what: str }) },
  contradictions: strs,
})

const VERIFY_SCHEMA = obj({
  verdicts: {
    type: 'array',
    items: obj({
      id: str,
      claim: str,
      verdict: { type: 'string', enum: ['confirmed', 'adjusted', 'rejected', 'unverifiable'] },
      correction: str,
      evidence: { type: 'string', description: 'the file:line you read or the command you ran, with its output' },
    }),
  },
})

const SYNTH_SCHEMA = obj(
  {
    summary: str,
    current_state: str,
    baselines: strs,
    work_items: {
      type: 'array',
      items: obj(
        {
          id: str,
          issues: strs,
          model: { type: 'string', enum: ['opus', 'sonnet', 'haiku'] },
          brief: str,
          files: strs,
          depends_on: strs,
          done_criterion: str,
          evidence: { ...strs, description: 'item ids (unit#n) this work item rests on' },
        },
        ['id', 'brief', 'files', 'depends_on', 'done_criterion', 'evidence'],
      ),
    },
    merge_order: strs,
    decisions_for_user: { type: 'array', items: obj({ question: str, options: strs, recommendation: str }) },
    open_questions: strs,
  },
  ['summary', 'current_state', 'work_items', 'merge_order', 'decisions_for_user', 'open_questions'],
)

// ---------------------------------------------------------------------------
// Prompts — name skills and rules instead of restating them.
// ---------------------------------------------------------------------------

const listOr = (xs, none) => (xs.length ? xs.map((x) => `  - ${x}`).join('\n') : `  ${none}`)

const COMMON = `This is READ-ONLY recon. Do not edit, stage, commit, push, comment, or touch the stash, any branch or any issue/PR.
Read committed state from the clean checkout at ${CTX.root}, or with \`git -C ${CTX.root} show ${CTX.base}:<path>\`.${
  CTX.head ? `\nFirst confirm \`git -C ${CTX.root} rev-parse HEAD\` is ${CTX.head}; if it is not, say so in your risks and map ${CTX.head} via git show.` : ''
}${CTX.main ? `\nNever touch the main checkout at ${CTX.main}: it may hold someone else's uncommitted work.` : ''}
Scratch files go only under ${CTX.scratch} (mkdir -p it).
${CTX.context ? `\nContext:\n${CTX.context}\n` : ''}${CTX.decisions.length ? `\nDecisions the user made for this run (binding; relay as given, do not relitigate):\n${listOr(CTX.decisions, '')}\n` : ''}${
  CTX.pregathered.length ? `\nPre-gathered data (query it instead of re-fetching):\n${listOr(CTX.pregathered, '')}\n` : ''
}${CTX.skills.length ? `\nSkills to load as relevant: ${CTX.skills.join(', ')}\n` : ''}
Evidence discipline:
- Every claim cites a file:line you read, an address, or a command plus the output line it printed. Write "unverified" where you did not check.
- Separate what you read or ran this session from inference (verified:false, or say so in notes).
- Control-test any negative (an empty grep, gh run list or search) against a value you know is present before reporting absence (agent-patterns-plugin:tool-result-traps).
Do not ask questions; put anything that is the user's call in open questions.`

// The output contract per kind. A lean reader gets only this part.
const KIND_RULES = {
  claims: 'Return one items[] row per claim. status is holds | drifted | resolved | new | unverified.',
  ac: `Return one acs[] row per acceptance criterion, in order, index from 1. status is satisfied | partial | missing | contradicted. Record each stale citation in staleRefs with what is true now.
A missing AC still cites its negative evidence: put in headRefs the search you ran (the command or Grep pattern plus its empty result, control-tested against a value you know is present) and the closest file:line. A row with empty headRefs is dropped as uncited and never reaches the plan.`,
  findings: `Return one findings[] row per defect, each with existing_pr_or_issue filled when an open PR or issue already addresses it
(another session may be on it). Put every item you examined and found healthy in reviewed_ok with a one-line reason, so coverage is checkable.`,
}
// How to check, for agents that can run commands and load skills.
const KIND_METHOD = {
  claims: `Reproduce each claim at ${CTX.base} rather than trusting the issue text: issues and stories cite stale file:line (git-plugin:git-issue-scoping).`,
  ac: `Stories cite stale file:line: re-verify each at ${CTX.base} (git-plugin:git-issue-scoping).`,
  findings: 'Search for an existing fix with gh pr list / gh search prs before reporting a finding as open.',
}
const RULES = `${KIND_RULES[KIND]}\n${KIND_METHOD[KIND]}`

const MAP_PROMPT = (u) => `You map ONE unit of a read-only recon. Unit key: ${u.key}

${COMMON}

${u.brief}

${RULES}
Set unit to "${u.key}".`

// A lean reader starts with no CLAUDE.md, no rules and no skills: everything is in the brief.
const LEAN_PROMPT = (u) => `You map ONE unit of a READ-ONLY recon by reading pre-dumped files. Unit key: ${u.key}
Read only these files (Read/Grep/Glob; do not run commands, do not write anything):
${listOr(u.inputs, '')}
${CTX.context ? `\nContext:\n${CTX.context}\n` : ''}
${u.brief}

${KIND_RULES[KIND]}
Every row cites the file:line in the files above that supports it. Quote, do not paraphrase. Where the files do not say, write "unverified".
An independent verifier re-checks every row you return. Set unit to "${u.key}".`

// PRESERVE: one literal call site per tier so every model and effort is checkable.
// A haiku unit is acceptable only because the opus verifier re-checks all of its items.
const mapUnit = (u) => {
  const opts = { label: `map:${u.key}`, phase: 'Map', schema: UNIT_SCHEMA }
  if (u.model === 'haiku') return agent(LEAN_PROMPT(u), { ...opts, agentType: 'agents-plugin:lean-reader', model: 'haiku', effort: 'medium' })
  if (u.model === 'sonnet') return agent(MAP_PROMPT(u), { ...opts, model: 'sonnet', effort: 'high' })
  return agent(MAP_PROMPT(u), { ...opts, model: 'opus', effort: 'high' })
}

// ---------------------------------------------------------------------------
// Item bookkeeping — plain JS, so the verdicts do not depend on a model reading them.
// ---------------------------------------------------------------------------

const ITEM_ARRAYS = { claims: ['items'], ac: ['acs'], findings: ['findings', 'reviewed_ok'] }

const rowsOf = (report) => {
  if (KIND === 'claims')
    return (report.items ?? []).map((x) => ({ text: x.claim, evidence: x.evidence ?? '', holding: x.status === 'holds' && x.verified === true, raw: x }))
  if (KIND === 'ac')
    return (report.acs ?? []).map((x) => ({ text: `AC ${x.index}: ${x.summary} [${x.status}]`, evidence: (x.headRefs ?? []).join(', '), holding: x.status === 'satisfied', raw: x }))
  return [
    ...(report.findings ?? []).map((x) => ({ text: `${x.id}: ${x.root_cause}`, evidence: x.evidence ?? '', holding: false, raw: x })),
    ...(report.reviewed_ok ?? []).map((x) => ({ text: `reviewed ok: ${x.item}`, evidence: x.why ?? '', holding: true, raw: x })),
  ]
}

const itemsOf = (key, report, lean) =>
  rowsOf(report).map((r, i) => ({ id: `${key}#${i + 1}`, unit: key, lean, ...r, cited: String(r.evidence).trim().length > 0 }))

const extrasOf = (report) => Object.fromEntries(Object.entries(report).filter(([k]) => !ITEM_ARRAYS[KIND].includes(k)))

// ---------------------------------------------------------------------------
// Map — one agent per unit, cut by a literal slice the scale guard counts.
// ---------------------------------------------------------------------------

// The literal 10 must equal MAX_UNITS: UNITS is already cut, so a larger cap
// here alone would change nothing, and a smaller one would mark units 'failed'.
phase('Map')
log(`${UNITS.length} units (${KIND}), tail: critic=${TAIL.critic} gapfill<=${TAIL.gapfill} verify=${TAIL.verify} synth=${TAIL.synth}`)
const mapped = await parallel(UNITS.slice(0, 10).map((u) => () => mapUnit(u)))

const reports = []
const unitRows = UNITS.map((u, i) => {
  const r = mapped[i]
  if (r) reports.push({ key: u.key, lean: u.model === 'haiku', report: r })
  return { key: u.key, model: u.model, status: r ? 'ok' : 'failed' }
})
const FAILED = unitRows.filter((r) => r.status === 'failed').map((r) => r.key)
if (FAILED.length) log(`mappers that returned nothing: ${FAILED.join(', ')}`)
if (!reports.length) return { ...abort('no-reports', 'every mapper returned nothing'), units: unitRows, dropped_units: DROPPED }

const unitsDir = `${CTX.scratch}/units`
const reportsJson = (rs) => JSON.stringify(rs.map((r) => ({ key: r.key, report: r.report })), null, 1)

// ---------------------------------------------------------------------------
// Critic — BARRIER: coverage can only be judged against every report.
// ---------------------------------------------------------------------------

let critique = null
if (TAIL.critic) {
  phase('Critic')
  critique = await agent(
    `You are the completeness critic of a read-only recon. You did not write these reports.

${COMMON}

${CTX.coverage ? `1. Write each report below to ${unitsDir}/<key>.json (the report object only), then run \`${CTX.coverage}\` and read its UNCOVERED rows and STATUS line. Each UNCOVERED row is a gap.\n` : ''}${CTX.coverage ? '2' : '1'}. Flag claims whose evidence is not a file:line, address or command with output; high-impact claims marked unverified; and claims that contradict each other or the pre-gathered data. Spot-check up to 5 of the most load-bearing claims yourself.
${CTX.coverage ? '3' : '2'}. Look for a check nobody ran, and for one shared cause reported separately by several units.
Units whose mapper returned nothing: ${FAILED.length ? FAILED.join(', ') : '(none)'} — each is a gap.${DROPPED.length ? `\nUnits dropped over the cap (not a gap for this run): ${DROPPED.join(', ')}` : ''}

${
      TAIL.gapfill
        ? `Group the gaps by unit so at most ${TAIL.gapfill} follow-up agents can fill them.`
        : 'No follow-up agents will run in this run: group the gaps by unit; they are returned unfilled for a later run.'
    } Return an empty gaps array when coverage is complete and the evidence holds.

Reports:
${reportsJson(reports)}`,
    { label: 'critic', phase: 'Critic', schema: CRITIC_SCHEMA, model: 'opus', effort: 'high' },
  )
  if (!critique) log('critic returned nothing; coverage is unjudged')
}

// ---------------------------------------------------------------------------
// Gap-fill — cut at 3 by a literal slice; the rest are returned, not dropped.
// ---------------------------------------------------------------------------

const gapList = critique?.gaps ?? []
const toFill = gapList.filter((_, i) => i < TAIL.gapfill)
const UNFILLED = gapList.slice(Math.min(toFill.length, MAX_GAPFILL))
if (gapList.length) {
  phase('Gap-fill')
  if (UNFILLED.length) log(`critic returned ${gapList.length} gap groups; filling ${gapList.length - UNFILLED.length}, the rest are in unfilled_gaps`)
  const filled = await parallel(
    toFill.slice(0, 3).map((g, i) => () =>
      agent(
        `You close coverage gaps in a read-only recon. Gap group ${i + 1}, units: ${(g.units ?? []).join(', ') || '(any)'}

${COMMON}

${RULES}

A completeness critic found these gaps; close them:
${g.what}
${critique.contradictions?.length ? `\nContradictions the critic noted (address any that concern your units):\n${listOr(critique.contradictions, '')}\n` : ''}
Existing reports for these units — return only NEW or CORRECTED rows; for a correction, name the row it corrects in its text:
${reportsJson(reports.filter((r) => !(g.units ?? []).length || g.units.includes(r.key)))}
Set unit to "gapfill-${i + 1}".`,
        { label: `gapfill:${i + 1}`, phase: 'Gap-fill', schema: UNIT_SCHEMA, model: 'opus', effort: 'high' },
      ),
    ),
  )
  filled.forEach((r, i) => {
    if (r) reports.push({ key: `gapfill-${i + 1}`, lean: false, report: r })
    else log(`gap-filler ${i + 1} returned nothing`)
  })
}

// ---------------------------------------------------------------------------
// Verify — BARRIER: one verifier over every selected item.
// ---------------------------------------------------------------------------

const items = reports.flatMap((r) => itemsOf(r.key, r.report, r.lean))
const UNCITED = items.filter((x) => !x.cited)
if (UNCITED.length) log(`${UNCITED.length} item(s) cite no evidence; dropped before verify and synth`)
const cited = items.filter((x) => x.cited)

// A lean-reader item is always verified: haiku output is never built on unchecked.
const selected = cited.filter((x) => x.lean || TAIL.verify === 'all' || (TAIL.verify === 'non-holding' && !x.holding))
const toVerify = selected.slice(0, MAX_VERIFY_ITEMS)
const overCap = selected.slice(MAX_VERIFY_ITEMS)
if (overCap.length) log(`${selected.length} items selected > verifier cap ${MAX_VERIFY_ITEMS}; ${overCap.length} stay unverifiable`)

const verdictById = {}
let verifyFailed = false
if (toVerify.length) {
  phase('Verify')
  const v = await agent(
    `You are an independent VERIFIER of a read-only recon. You did not write these claims and have no stake in them holding.

${COMMON}

For each item below, re-run its evidence yourself: read the file:line at ${CTX.base}, or run the command. Do not trust the citation.
- confirmed: you reproduced it as stated.
- adjusted: it is partly right; put what is true in correction, with your own evidence.
- rejected: you checked and it is wrong.
- unverifiable: you could not reproduce it. Default to this, never to confirmed.
Return one verdict per item id.

Items:
${JSON.stringify(toVerify.map((x) => ({ id: x.id, unit: x.unit, claim: x.text, evidence: x.evidence })), null, 1)}`,
    { label: 'verify', phase: 'Verify', schema: VERIFY_SCHEMA, model: 'opus', effort: 'high' },
  )
  if (!v) {
    verifyFailed = true
    log('verifier returned nothing; every selected item is unverifiable')
  }
  for (const d of v?.verdicts ?? []) verdictById[d.id] = d
}

// A missing verdict — dead verifier or skipped item — is unverifiable, never confirmed.
const verdictOf = (x) => {
  if (!selected.includes(x)) return { verdict: 'not-checked', correction: '', evidence: '' }
  const d = toVerify.includes(x) ? verdictById[x.id] : null
  return d ? { verdict: d.verdict, correction: d.correction ?? '', evidence: d.evidence ?? '' } : { verdict: 'unverifiable', correction: '', evidence: '' }
}
const annotated = cited.map((x) => ({ ...x, verification: verdictOf(x) }))
const REJECTED = annotated.filter((x) => x.verification.verdict === 'rejected')
const kept = annotated.filter((x) => x.verification.verdict !== 'rejected')

const verification = {
  mode: TAIL.verify,
  failed: verifyFailed,
  selected: annotated.filter((x) => selected.some((s) => s.id === x.id)).map((x) => ({ id: x.id, unit: x.unit, claim: x.text, ...x.verification })),
  over_cap: overCap.map((x) => x.id),
}

const RESULT = {
  units: unitRows,
  dropped_units: DROPPED,
  critique,
  unfilled_gaps: UNFILLED,
  items: annotated.map(({ raw, ...x }) => x),
  uncited: UNCITED.map((x) => ({ id: x.id, unit: x.unit, claim: x.text })),
  rejected: REJECTED.map((x) => ({ id: x.id, unit: x.unit, claim: x.text, why: x.verification.evidence })),
  verification,
  synthesis: null,
}
if (!TAIL.synth) return RESULT

// ---------------------------------------------------------------------------
// Synthesize — BARRIER: work items need the whole verified map.
// ---------------------------------------------------------------------------

phase('Synthesize')
const synthInput = reports.map((r) => ({
  key: r.key,
  ...extrasOf(r.report),
  items: kept.filter((x) => x.unit === r.key).map((x) => ({ id: x.id, ...x.raw, verification: x.verification })),
}))
RESULT.synthesis = await agent(
  `You synthesize a read-only recon into verified facts and PR-sized work items. Landing is none: you write files only under ${CTX.scratch}.

${COMMON}

${verifyFailed ? 'THE VERIFIER RETURNED NOTHING: no item below was independently confirmed. Say so in the summary, and keep work items to what the cited evidence alone supports.\n' : ''}Rules:
- Use only the items below. Items the verifier rejected and items with no evidence were removed before you; do not reintroduce them from memory.
- An "adjusted" item: use its correction, not the original claim.
- An "unverifiable" item is not a fact: list it under open_questions, or re-check it yourself and cite what you ran.
- A "not-checked" item is the mapper's own cited claim; this run's verify mode did not select it. It may support work items, but never call it confirmed or verified.
- Each work item is one PR, names its files, a done criterion a script or test can decide, and the item ids it rests on.
- decisions_for_user holds only calls the code and docs cannot decide, each with a recommendation.
${critique && CTX.coverage ? '' : `- First write each unit's report object to ${unitsDir}/<key>.json, so a later run can read it.\n`}${UNFILLED.length ? `- Gaps the run did not fill: ${JSON.stringify(UNFILLED)}\n` : ''}${DROPPED.length ? `- Units dropped over the cap, not mapped: ${DROPPED.join(', ')}\n` : ''}${FAILED.length ? `- Units whose mapper returned nothing: ${FAILED.join(', ')}\n` : ''}${
  UNCITED.length ? `- Items dropped for citing no evidence (not facts; list them under open_questions as unmapped): ${UNCITED.map((x) => x.id).join(', ')}\n` : ''
}
Write your result as JSON to ${CTX.scratch}/recon.json, then return the same object.

Critic: ${JSON.stringify(critique)}

Reports:
${JSON.stringify(synthInput, null, 1)}`,
  { label: 'synth', phase: 'Synthesize', schema: SYNTH_SCHEMA, model: 'opus', effort: 'high' },
)
if (!RESULT.synthesis) log('synthesizer returned nothing; the verified items are in the result')
return RESULT
