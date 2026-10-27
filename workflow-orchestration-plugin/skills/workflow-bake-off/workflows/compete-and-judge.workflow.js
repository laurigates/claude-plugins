/**
 * compete-and-judge.workflow.js — K independent attempts at one target, J lens
 * judges scoring every attempt, a winner COMPUTED in JS, then an optional
 * refine of the winner that grafts runner-up ideas.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape:
 *   Setup     — 0–2 agents build what every entrant and judge must share (a
 *               render harness, a measurement script). BARRIER: entrants
 *               start only once all of it exists; a dead setup agent aborts.
 *   Compete   — 2–5 entrants, one per `args.entries` row, each writing only
 *               ${out}/${key}. No barrier inside the stage.
 *   Judge     — 1–3 lens judges. BARRIER: each judge sees every entry.
 *   Aggregate — plain JS, no agent. Borda over the judges' rankings (mean
 *               score, then caller order, break ties), or a lexicographic
 *               rule over judge-measured metrics. A model never reads the
 *               verdicts to pick the winner: that launders a coin-flip into
 *               a decision that looks researched
 *               (`.claude/rules/workflow-vs-skill.md` § The two shapes with no fit here).
 *   Refine    — optional, 1 agent, starts from the computed winner.
 *
 * Everything is artefacts under `out`. No agent commits, pushes or touches
 * GitHub. An adaptation that lets entrants commit in worktrees must add the
 * two worktree clauses from the SKILL.md and land in one sequential finalise
 * agent.
 */

export const meta = {
  name: 'compete-and-judge',
  description:
    'K independent entries, J lens judges, a winner computed by Borda or a metric rule in JS, then an optional refine that grafts runner-up ideas.',
  phases: [
    { title: 'Setup' },
    { title: 'Compete' },
    { title: 'Judge' },
    { title: 'Refine' },
  ],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the numbers, PRESERVE the shape. One entry is not a competition, and
// more than 5 entries x 3 judges costs more reading than the judges can do well.
const FLOOR = 2
const MAX_ENTRIES = 5
const MAX_JUDGES = 3
const MAX_SETUP = 2
// A single surviving judge is one lens's opinion, not a panel. With J = 1 the
// caller chose that, so the quorum is 1.
const QUORUM = (j) => Math.min(2, j)

const OUT = INPUT.out ?? '<absolute output directory>'
const CTX = {
  context: INPUT.context ?? '',
  metricDefs: INPUT.metric_defs ?? '',
  acceptance: INPUT.acceptance ?? [],
  skills: INPUT.skills ?? [],
  decisions: INPUT.decisions ?? [],
}
const AGG = INPUT.aggregation === 'metric' ? 'metric' : 'borda'
const FINISH = INPUT.finish === 'none' ? 'none' : 'refine'
const ITER = { min: INPUT.self_iterate?.min ?? 2, max: INPUT.self_iterate?.max ?? 6 }
const METRIC = {
  command: INPUT.metric?.command ?? '',
  keys: (INPUT.metric?.keys ?? []).map((k) => ({ name: String(k.name), better: k.better === 'higher' ? 'higher' : 'lower' })),
}

const rows = (xs, field) => (xs ?? []).map((x, i) => ({ key: String(x.key ?? `${field}-${i + 1}`), text: x[field] ?? '' }))
const SETUP = rows(INPUT.setup, 'brief')
const ENTRIES = rows(INPUT.entries, 'angle')
const JUDGES = rows(INPUT.judges, 'lens')

// ---------------------------------------------------------------------------
// Aggregation — pure functions. PRESERVE: the winner is standings[0] of one of
// these, never an agent's answer.
// ---------------------------------------------------------------------------

const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null)
const median = (xs) => {
  if (!xs.length) return null
  const s = [...xs].sort((a, b) => a - b)
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}
// Higher first; a missing value sorts after any present one.
const desc = (a, b) => (a === b ? 0 : a === null ? 1 : b === null ? -1 : b - a)

// A ranking counts each surviving key once, at its first position; keys the
// harness does not know are dropped, not scored.
const cleanRanking = (ranking, alive) => [...new Set((ranking ?? []).map(String))].filter((k) => alive.includes(k))

// Borda: an entry at 0-based position i of a judge's ranking earns K-1-i,
// where K is the number of SURVIVING entries, not the length of that judge's
// list. An entry a judge left out earns 0 from that judge and is reported.
const bordaRows = (alive, verdicts) =>
  alive.map((key, order) => {
    const points = verdicts.map((v) => {
      const i = cleanRanking(v.ranking, alive).indexOf(key)
      return i < 0 ? 0 : alive.length - 1 - i
    })
    // One score per judge per entry (its first valid row): a duplicated row is not an extra vote.
    const scores = verdicts
      .map((v) => (v.scores ?? []).find((s) => String(s.key) === key && Number.isFinite(s.score)))
      .filter(Boolean)
      .map((s) => s.score)
    return { key, order, borda: points.reduce((a, b) => a + b, 0), mean: mean(scores) }
  })
const bordaCore = (a, b) => b.borda - a.borda || desc(a.mean, b.mean)

// A measurement row counts only when it carries a finite value for at least
// one METRIC.keys name. A row with `values: []` measured nothing, and must not
// vote on acceptance, fill a quorum, or close a ranking gap.
const measured = (m) => (m.values ?? []).some((x) => METRIC.keys.some((k) => k.name === x.name) && Number.isFinite(x.value))

// Metric: an entry meets acceptance only when every judge that measured it
// says so; each metric is the median of the judges' measurements. Entrants'
// self-reported numbers are never read here.
const metricRows = (alive, verdicts) =>
  alive.map((key, order) => {
    const ms = verdicts.flatMap((v) => (v.measurements ?? []).filter((m) => String(m.key) === key && measured(m)))
    const values = Object.fromEntries(
      METRIC.keys.map((k) => [
        k.name,
        median(ms.flatMap((m) => (m.values ?? []).filter((x) => x.name === k.name && Number.isFinite(x.value)).map((x) => x.value))),
      ]),
    )
    return { key, order, meets_acceptance: ms.length > 0 && ms.every((m) => m.meets_acceptance === true), measured_by: ms.length, values }
  })
const metricCore = (a, b) => {
  if (a.meets_acceptance !== b.meets_acceptance) return a.meets_acceptance ? -1 : 1
  for (const k of METRIC.keys) {
    const sign = k.better === 'higher' ? 1 : -1
    const va = a.values[k.name]
    const vb = b.values[k.name]
    const c = va === null || vb === null ? desc(va, vb) : desc(sign * va, sign * vb)
    if (c) return c
  }
  return 0
}

// The last tiebreak is caller order (`args.entries`), so the same inputs always
// crown the same entry, whatever order the verdicts arrived in. A caller who
// wants an incumbent to keep a tie lists it first.
const aggregate = (alive, verdicts) => {
  const core = AGG === 'metric' ? metricCore : bordaCore
  const standings = (AGG === 'metric' ? metricRows : bordaRows)(alive, verdicts).sort((a, b) => core(a, b) || a.order - b.order)
  const tiedWith = standings.slice(1).filter((s) => core(standings[0], s) === 0).map((s) => s.key)
  const gaps = verdicts
    .map((v) => ({
      judge: v.judge,
      missing: AGG === 'metric'
        ? alive.filter((k) => !(v.measurements ?? []).some((m) => String(m.key) === k && measured(m)))
        : alive.filter((k) => !cleanRanking(v.ranking, alive).includes(k)),
    }))
    .filter((g) => g.missing.length)
  return { standings: standings.map((s, i) => ({ rank: i + 1, ...s })), winner: standings[0].key, tie: tiedWith.length > 0, tiedWith, gaps }
}

// A verdict counts toward quorum only when it carries something the
// aggregation can use.
const usable = (alive) => (v) =>
  AGG === 'metric' ? (v.measurements ?? []).some((m) => alive.includes(String(m.key)) && measured(m)) : cleanRanking(v.ranking, alive).length > 0

// ---------------------------------------------------------------------------
// Schemas and prompts — ADAPT the prompts freely.
// ---------------------------------------------------------------------------

const NAMED_VALUES = {
  type: 'array',
  items: {
    type: 'object',
    required: ['name', 'value'],
    additionalProperties: false,
    properties: { name: { type: 'string' }, value: { type: 'number' } },
  },
}
const SETUP_SCHEMA = {
  type: 'object',
  required: ['key', 'summary', 'files'],
  additionalProperties: false,
  properties: {
    key: { type: 'string' },
    summary: { type: 'string', description: 'what it is, the exact command to use it, and the known-good case it was tested on' },
    files: { type: 'array', items: { type: 'string' } },
  },
}
const ENTRY_SCHEMA = {
  type: 'object',
  required: ['key', 'dir', 'summary', 'self_assessment', 'files', 'iterations'],
  additionalProperties: false,
  properties: {
    key: { type: 'string' },
    dir: { type: 'string' },
    summary: { type: 'string' },
    self_assessment: { type: 'string', description: 'honest weaknesses; judges treat this as a claim' },
    files: { type: 'array', items: { type: 'string' } },
    iterations: { type: 'integer' },
    metrics: { ...NAMED_VALUES, description: 'self-measured; never used to pick the winner' },
    meets_acceptance: { type: 'boolean' },
  },
}
const JUDGE_SCHEMA = {
  type: 'object',
  required: ['scores', 'ranking', 'grafts'],
  additionalProperties: false,
  properties: {
    scores: {
      type: 'array',
      items: {
        type: 'object',
        required: ['key', 'score', 'strengths', 'weaknesses', 'fixes'],
        additionalProperties: false,
        properties: {
          key: { type: 'string' },
          score: { type: 'number', description: '1-10, using the full range' },
          strengths: { type: 'string' },
          weaknesses: { type: 'string' },
          fixes: { type: 'string', description: 'the concrete changes that would most improve this entry' },
        },
      },
    },
    ranking: { type: 'array', items: { type: 'string' }, description: 'every entry key exactly once, best first' },
    grafts: {
      type: 'array',
      items: {
        type: 'object',
        required: ['from', 'idea'],
        additionalProperties: false,
        properties: { from: { type: 'string' }, idea: { type: 'string' } },
      },
    },
    measurements: {
      type: 'array',
      description: 'metric mode: one row per entry, measured by you',
      items: {
        type: 'object',
        required: ['key', 'values', 'meets_acceptance'],
        additionalProperties: false,
        properties: { key: { type: 'string' }, values: NAMED_VALUES, meets_acceptance: { type: 'boolean' }, command: { type: 'string' } },
      },
    },
    disagreements: {
      type: 'array',
      items: {
        type: 'object',
        required: ['question', 'positions'],
        additionalProperties: false,
        properties: { question: { type: 'string' }, positions: { type: 'string' }, adjudication: { type: 'string' } },
      },
    },
  },
}
const REFINE_SCHEMA = {
  type: 'object',
  required: ['dir', 'changes', 'grafted', 'files', 'remaining_concerns'],
  additionalProperties: false,
  properties: {
    dir: { type: 'string' },
    changes: { type: 'string' },
    grafted: {
      type: 'array',
      items: {
        type: 'object',
        required: ['from', 'idea', 'taken'],
        additionalProperties: false,
        properties: { from: { type: 'string' }, idea: { type: 'string' }, taken: { type: 'boolean' }, why: { type: 'string' } },
      },
    },
    rejected_fixes: { type: 'array', items: { type: 'string' }, description: 'judge fixes you checked and declined, with the evidence' },
    files: { type: 'array', items: { type: 'string' } },
    remaining_concerns: { type: 'string' },
  },
}

const list = (xs) => xs.map((x) => `  - ${x}`).join('\n')
const COMMON = `${CTX.context}
${CTX.decisions.length ? `\nDecisions the user made for this run (binding; relay as given, do not relitigate):\n${list(CTX.decisions)}\n` : ''}${
  CTX.skills.length ? `Skills to use: ${CTX.skills.join(', ')}\n` : ''
}${CTX.metricDefs ? `\nShared definitions — every entrant and judge uses exactly these, so results are comparable:\n${CTX.metricDefs}\n` : ''}${
  CTX.acceptance.length ? `\nAcceptance criteria:\n${list(CTX.acceptance)}\n` : ''
}
Do not commit, push, or touch GitHub. Do not ask questions; state assumptions in your output.`

const SETUP_PROMPT = (s) => `${COMMON}

You build a SHARED piece of the bake-off that every entrant and judge will use: ${s.key}.
${s.text}
Write only under ${OUT}/${s.key}/. Test it on a known-good case and report the exact command to run it;
an instrument that cannot tell a good case from a bad one must refuse rather than report.`

const ENTER_PROMPT = (e, setupOut) => `${COMMON}

You are one of several INDEPENDENT entrants attempting the same target. Your assigned angle:
${e.text}

Work only in DIR = ${OUT}/${e.key}/ (create it). Do not read or modify other entrants' directories.
${setupOut.length ? `Shared setup, ready to use:\n${setupOut.map((s) => `  - ${s.key}: ${s.summary}`).join('\n')}\n` : ''}
Self-iterate: produce, render or measure, read your own output, critique it bluntly, revise. Do at least ${ITER.min}
and at most ${ITER.max} rounds; stop early when a round stops improving it. Keep each round's output in DIR so
progress is inspectable. If your angle cannot meet the acceptance criteria, keep your best measured state, say so,
and name the mechanism that blocked it. Judges will re-measure; self-reported numbers are claims.`

const JUDGE_PROMPT = (j, entries) => `${COMMON}

You are a JUDGE. Your lens:
${j.text}

Entries (key, directory, the entrant's own summary — a claim, not evidence):
${entries.map((e) => `  - ${e.key}: ${e.dir}\n    summary: ${e.summary}\n    self-assessment: ${e.self_assessment}`).join('\n')}

Judge only what you see: open the artefacts in each directory and re-measure; never score a self-grade or summary.
A claim that does not reproduce ranks above any other defect. Read-only: write scratch only under ${OUT}/judge-${j.key}/.
Use the full 1-10 range rather than giving everyone the same score; a hard-requirement violation caps an entry at 4.
Return a score row for every entry, a ranking listing every key exactly once (best first), and the ideas from any
entry worth grafting into whichever entry wins.
${AGG === 'metric' ? `Run \`${METRIC.command}\` against every entry yourself and return a measurements row per entry with
values for: ${METRIC.keys.map((k) => `${k.name} (${k.better} is better)`).join(', ')}, and whether it meets acceptance.\n` : ''}
Do not name a winner. The harness computes it from every judge's ${AGG === 'metric' ? 'measurements' : 'ranking'}.`

const REFINE_PROMPT = (agg, entries, verdicts) => {
  const w = entries.find((e) => e.key === agg.winner)
  const fixes = verdicts
    .map((v) => {
      const s = (v.scores ?? []).find((x) => String(x.key) === w.key)
      return `  - ${v.judge}: ${s ? `score ${s.score}; weaknesses: ${s.weaknesses}; fixes: ${s.fixes}` : 'did not score it'}`
    })
    .join('\n')
  const grafts = verdicts.flatMap((v) => (v.grafts ?? []).filter((g) => g.from !== w.key).map((g) => `  - [${v.judge}] from ${g.from}: ${g.idea}`))
  const disputes = verdicts.flatMap((v) => (v.disagreements ?? []).map((d) => `  - ${d.question}: ${d.positions}`))
  return `${COMMON}

The winner is \`${w.key}\` (${w.dir}), computed by ${AGG === 'metric' ? 'the metric rule' : 'Borda count'} over ${verdicts.length} judge verdicts${
    agg.tie ? `; it tied with ${agg.tiedWith.join(', ')} and won on caller order` : ''
  }. Do not reopen the choice or switch to another entry.

Standings:
${agg.standings.map((s) => `  ${s.rank}. ${s.key} ${JSON.stringify(s)}`).join('\n')}

The judges on the winner:
${fixes}

Ideas the judges flagged in other entries:
${grafts.length ? grafts.join('\n') : '  (none)'}
${disputes.length ? `\nWhere the judges disagreed (inputs, not verdicts — settle each against the artefact):\n${disputes.join('\n')}\n` : ''}
Produce the final version in ${OUT}/final/, starting from the winner's files. Check each judge fix against the artefact
before applying it — reviews can be wrong — and record any you decline. Graft an idea only when it strengthens the
winner without diluting it, and record every flagged idea as taken or not. Touch nothing outside ${OUT}/final/.`
}

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort before any agent runs.
// ---------------------------------------------------------------------------

const KEY = /^[A-Za-z0-9][A-Za-z0-9_-]*$/
const allKeys = [...SETUP, ...ENTRIES, ...JUDGES].map((x) => x.key)
if (ENTRIES.length < FLOOR) return { abort: true, reason: 'below-floor', entries: ENTRIES.length }
if (ENTRIES.length > MAX_ENTRIES) return { abort: true, reason: 'over-cap', entries: ENTRIES.map((e) => e.key) }
if (JUDGES.length < 1 || JUDGES.length > MAX_JUDGES) return { abort: true, reason: 'judges-out-of-range', judges: JUDGES.length }
if (SETUP.length > MAX_SETUP) return { abort: true, reason: 'setup-over-cap', setup: SETUP.length }
if (allKeys.some((k) => !KEY.test(k) || k === 'final')) return { abort: true, reason: 'bad-key', keys: allKeys.filter((k) => !KEY.test(k) || k === 'final') }
if (new Set(allKeys).size !== allKeys.length) return { abort: true, reason: 'duplicate-key', keys: allKeys }
if (AGG === 'metric' && (!METRIC.keys.length || !METRIC.command)) return { abort: true, reason: 'no-metric' }

// ---------------------------------------------------------------------------
// Setup — BARRIER: everything shared exists before anyone competes.
// ---------------------------------------------------------------------------

let setupOut = []
if (SETUP.length) {
  phase('Setup')
  // PRESERVE the literal bound in the fan-out: the scale guard counts it.
  setupOut = await parallel(
    SETUP.slice(0, 2).map((s) => () =>
      agent(SETUP_PROMPT(s), { label: `setup:${s.key}`, phase: 'Setup', schema: SETUP_SCHEMA, model: 'opus', effort: 'high' })
        .then((r) => r && { ...r, key: s.key })),
  )
  const dead = SETUP.filter((_, i) => !setupOut[i]).map((s) => s.key)
  if (dead.length) {
    log(`setup failed: ${dead.join(', ')} — entrants would not be comparable; abort`)
    return { abort: true, reason: 'setup-failed', winner: null, dead, setup: setupOut }
  }
}

// ---------------------------------------------------------------------------
// Compete — independent entrants.
// ---------------------------------------------------------------------------

phase('Compete')
log(`${ENTRIES.length} entries, ${JUDGES.length} judges, aggregation ${AGG}, finish ${FINISH}`)
const submitted = await parallel(
  ENTRIES.slice(0, 5).map((e) => () =>
    agent(ENTER_PROMPT(e, setupOut), { label: `enter:${e.key}`, phase: 'Compete', schema: ENTRY_SCHEMA, model: 'opus', effort: 'high' })
      // The harness owns the key and directory; an entrant cannot claim another's.
      .then((r) => r && { ...r, key: e.key, dir: `${OUT}/${e.key}` })),
)
const entries = submitted.filter(Boolean)
const alive = entries.map((e) => e.key)
if (entries.length < ENTRIES.length) log(`${ENTRIES.length - entries.length} entrant(s) returned nothing — judged: ${alive.join(', ')}`)
if (entries.length < FLOOR) return { abort: true, reason: 'too-few-entries', winner: null, entries, setup: setupOut }

// ---------------------------------------------------------------------------
// Judge — BARRIER: every judge sees every surviving entry.
// ---------------------------------------------------------------------------

phase('Judge')
const returned = (
  await parallel(
    JUDGES.slice(0, 3).map((j) => () =>
      agent(JUDGE_PROMPT(j, entries), { label: `judge:${j.key}`, phase: 'Judge', schema: JUDGE_SCHEMA, model: 'opus', effort: 'high' })
        .then((v) => v && { ...v, judge: j.key })),
  )
).filter(Boolean)
const verdicts = returned.filter(usable(alive))
// The result keeps every verdict a judge returned; these judges ran but are not counted.
const excluded = returned.filter((v) => !usable(alive)(v)).map((v) => v.judge)
if (excluded.length) log(`unusable verdict(s), not counted toward quorum: ${excluded.join(', ')}`)

if (verdicts.length < QUORUM(JUDGES.length)) {
  log(`${verdicts.length} usable verdict(s) of ${JUDGES.length} (< quorum ${QUORUM(JUDGES.length)}) — no winner; re-judge rather than refine`)
  return { abort: true, reason: 'no-quorum', winner: null, entries, verdicts: returned, excluded_judges: excluded, setup: setupOut }
}

// ---------------------------------------------------------------------------
// Aggregate — plain JS. PRESERVE: no agent between Judge and Refine.
// ---------------------------------------------------------------------------

const agg = aggregate(alive, verdicts)
log(`standings: ${agg.standings.map((s) => s.key).join(' > ')}${agg.tie ? ` (tie with ${agg.tiedWith.join(', ')}, broken on caller order)` : ''}`)
if (agg.gaps.length) log(`incomplete verdicts: ${agg.gaps.map((g) => `${g.judge} missing ${g.missing.join(', ')}`).join('; ')}`)
const result = {
  aggregation: AGG,
  winner: agg.winner,
  tie: agg.tie,
  tied_with: agg.tiedWith,
  standings: agg.standings,
  ranking_gaps: agg.gaps,
  ...(AGG === 'metric' ? { winner_meets_acceptance: agg.standings[0].meets_acceptance } : {}),
  entries,
  verdicts: returned,
  excluded_judges: excluded,
  setup: setupOut,
}

// ---------------------------------------------------------------------------
// Refine — optional; starts from the computed winner.
// ---------------------------------------------------------------------------

if (FINISH === 'none') return { ...result, refined: null }
phase('Refine')
const refined = await agent(REFINE_PROMPT(agg, entries, verdicts), {
  label: 'refine',
  phase: 'Refine',
  schema: REFINE_SCHEMA,
  model: 'opus',
  effort: 'high',
})
if (!refined) log('refine agent returned nothing — the winner and standings above still stand')
return { ...result, refined }
