// model-suitability-audit — which skills, agents, workflow harnesses and GitHub
// workflows could run on a cheaper model, judged by that model and checked by Opus.
//
// Repo-internal (not a plugin skill). It generalises the run behind
// docs/audits/haiku-5.5-reevaluation-2026-10-10.md so the re-run that
// .claude/rules/agent-development.md § Model Selection for Agents schedules (#3116)
// starts from a fixed harness instead of a hand-edited one-off.
//
// SHAPE
//   Classify  one candidate-model agent per batch of files. Each returns exactly
//             one closed-enum verdict per file; JS checks the count by path.
//   barrier   every batch must land before the control sample is drawn, because
//             the sample is taken across ALL keep verdicts, not per batch.
//   Verify    Opus agents re-read the file behind every non-keep verdict plus a
//             deterministic control sample of keeps. The 2026-10-10 run: Opus
//             confirmed 93 of 204 non-keep verdicts and all 49 control keeps held,
//             so the classifier is cheap, readable, and not trusted alone.
//
// ARGS (an object, or the same as a JSON string)
//   repo            absolute path the relative entries in `files` resolve against
//   files           paths to classify, relative to `repo` or absolute. The script
//                   has no filesystem, so the caller expands its globs, e.g.
//                   `git ls-files '*/skills/*/SKILL.md' '*-plugin/agents/*.md'
//                   '*/skills/*/workflows/*.workflow.js' '.github/workflows/*.yml'`.
//                   Kind comes from the path: SKILL.md, agents/*.md, *.workflow.js,
//                   .github/workflows/*.yml|yaml. Anything else aborts.
//   globs           the globs `files` was expanded from (recorded in the artifact)
//   model           candidate alias or id: haiku | sonnet | claude-haiku-… | claude-sonnet-…
//   effort          candidate effort (default 'medium')
//   verifyEffort    Opus verifier effort (default 'high')
//   batchSize       files per classifier (default 34)
//   verifyBatchSize entries per verifier (default 40)
//   controlSample   keep verdicts sent to Opus as a control (default ceil(keeps/7),
//                   at least 3); 0 disables it
//   lean            true runs classifiers as agentType 'agents-plugin:lean-reader'
//                   (~3k-token first request instead of ~124k; see
//                   .claude/rules/agent-development.md § Lean subagents). Default
//                   false keeps the 2026-10-10 setup, so the two runs compare.
//   modelFacts      the candidate's facts with sources (price, effort, benchmarks)
//   history         prior moves to re-judge on the model's merits (PRs, lints)
//   artifact | date where the findings go: `artifact` is a path, or `date`
//                   (YYYY-MM-DD) names docs/audits/<model>-model-suitability-<date>.md
//
// RETURNS { artifactPath, markdown, summary, rows, invented, verifierNotes }.
// The workflow cannot write files: the caller writes `markdown` to
// `artifactPath`, then fills its Adjudication section (applying one rule across
// verifiers that disagree was the orchestrating session's job last time too).
//
// AGENT BUDGET: at most 18 classifiers + 8 verifiers. Both fan-outs iterate a
// literal .slice(0, N), so the scale guard counts 26 and asks before the run.
// Keep the slices in step with MAX_CLASSIFIERS / MAX_VERIFIERS below.
//
// RUNNABLE BY NAME: this file sits in the project workflow directory, so a
// session in this checkout can start it by name. Every argument check returns
// { abort: true } before the first agent(), so a call with empty args costs nothing.

export const meta = {
  name: 'model-suitability-audit',
  description:
    'Classify skills, agents, workflow harnesses and GitHub workflows for a cheaper model; Opus re-reads every non-keep verdict plus a control sample of keeps',
  phases: [
    { title: 'Classify', detail: 'candidate-model classifiers, one per batch of files' },
    { title: 'Verify', detail: 'Opus re-reads every non-keep verdict and a deterministic control sample of keeps' },
  ],
}

const MAX_CLASSIFIERS = 18
const MAX_VERIFIERS = 8
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
const VERDICTS = ['switch', 'switch-stage', 'needs-test', 'keep']
const KIND_ORDER = ['skill', 'agent', 'harness', 'gh-workflow']

const abort = (reason, detail) => ({ abort: true, reason, detail })

let A
try {
  A = typeof args === 'string' ? JSON.parse(args || '{}') : args || {}
} catch {
  return abort('bad-args', 'args is a string that is not JSON')
}
// JSON.parse('null') is null; A.repo on it would throw instead of aborting.
if (A === null || typeof A !== 'object' || Array.isArray(A)) return abort('bad-args', 'args must be an object or a JSON object string')

const kindOf = (p) =>
  /(^|\/)SKILL\.md$/.test(p) ? 'skill'
    : /(^|\/)agents\/[^/]+\.md$/.test(p) ? 'agent'
      : /\.workflow\.js$/.test(p) ? 'harness'
        : /(^|\/)\.github\/workflows\/[^/]+\.ya?ml$/.test(p) ? 'gh-workflow'
          : null
const intIn = (v, dflt, lo, hi) => (v === undefined || v === null ? dflt : Number.isInteger(Number(v)) && Number(v) >= lo && Number(v) <= hi ? Number(v) : NaN)

const REPO = typeof A.repo === 'string' ? A.repo.replace(/\/+$/, '') : ''
if (!REPO) return abort('missing-repo', 'args.repo: absolute path the relative files resolve against')
const files = Array.isArray(A.files) ? A.files.filter((f) => typeof f === 'string' && f.trim()).map((f) => f.trim().replace(/^\.\//, '')) : []
if (!files.length) return abort('no-files', 'args.files is empty; expand the globs with git ls-files and pass the list')
const dupes = files.filter((f, i) => files.indexOf(f) !== i)
if (dupes.length) return abort('duplicate-files', dupes)
const unknown = files.filter((f) => !kindOf(f))
if (unknown.length) return abort('unknown-kind', unknown)

const MODEL = String(A.model || '')
if (!/^(haiku|sonnet)$|^claude-(haiku|sonnet)-[a-z0-9-]+$/.test(MODEL)) {
  return abort('bad-model', 'args.model: a haiku or sonnet alias or id; the verifier is Opus, so auditing Opus against itself measures nothing')
}
const EFFORT = A.effort === undefined ? 'medium' : A.effort
const VERIFY_EFFORT = A.verifyEffort === undefined ? 'high' : A.verifyEffort
if (!EFFORTS.includes(EFFORT) || !EFFORTS.includes(VERIFY_EFFORT)) return abort('bad-effort', `effort and verifyEffort take one of ${EFFORTS.join('|')}`)
const BATCH = intIn(A.batchSize, 34, 1, 80)
const VBATCH = intIn(A.verifyBatchSize, 40, 1, 120)
if (Number.isNaN(BATCH) || Number.isNaN(VBATCH)) return abort('bad-batch-size', 'batchSize 1..80, verifyBatchSize 1..120')
const CONTROL = intIn(A.controlSample, null, 0, 100000)
if (Number.isNaN(CONTROL)) return abort('bad-control-sample', 'controlSample: a non-negative integer')
const LEAN = A.lean === true || A.lean === 'true'

const slug = MODEL.replace(/^claude-/, '').replace(/[^a-z0-9.-]/g, '-')
const artifactPath =
  typeof A.artifact === 'string' && A.artifact.trim() ? A.artifact.trim()
    : typeof A.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(A.date) ? `docs/audits/${slug}-model-suitability-${A.date}.md`
      : null
if (!artifactPath) return abort('no-artifact-path', 'pass args.artifact, or args.date (YYYY-MM-DD) for the default docs/audits/ name')

const ordered = [...files].sort((a, b) => KIND_ORDER.indexOf(kindOf(a)) - KIND_ORDER.indexOf(kindOf(b)) || (a < b ? -1 : a > b ? 1 : 0))
const batches = []
for (let i = 0; i < ordered.length; i += BATCH) {
  batches.push({ label: `b${String(batches.length).padStart(2, '0')}`, paths: ordered.slice(i, i + BATCH) })
}
if (batches.length > MAX_CLASSIFIERS) {
  return abort('over-cap', `${files.length} files at batchSize ${BATCH} need ${batches.length} classifiers (cap ${MAX_CLASSIFIERS}); raise batchSize to ${Math.ceil(files.length / MAX_CLASSIFIERS)} or split the run`)
}

// ---------------------------------------------------------------- briefs

const RUBRIC = `
## Verdicts (closed enum)
- "switch": the whole artefact can run on ${MODEL}. Needs ALL of: a bounded, well-specified, repetitive task; low judgement; and output that a deterministic gate checks (tests, lint, a parser, an exit code) or that is low-stakes and easy to eyeball (a listing, a status report, a format conversion, a single-file lookup, classification against a fixed rubric).
- "switch-stage": the artefact needs a stronger model, but a named internal stage (a mechanical fan-out reader, a classifier, a summariser) could run on ${MODEL}. Name the stage.
- "needs-test": a plausible candidate with a specific unmeasured risk (AskUserQuestion use, long tool loops sensitive to turn budgets, moderately complex edits). Name the risk.
- "keep": stays on Opus or Sonnet. Use it for open-ended review or audit, security analysis, multi-file edits and agentic coding, adversarial verification, design judgement, outward-facing prose, orchestrators, and any output the main loop builds on with no independent check.
- Default to "keep" when unsure. A false "switch" is the expensive error. If a risk you list is one of the "keep" reasons above, the verdict cannot be "switch".
- For every non-keep verdict, suggest an effort: low for pure mechanical work, medium otherwise.

## What a model pin does, per kind
- skill: a SKILL.md \`model:\` overrides the model for the REST OF THE CURRENT TURN, not just the skill's own steps (with \`context: fork\` it sets the forked subagent's model instead). So "switch" fits only a report, a listing, or a user-driven task that ends the turn. A \`user-invocable: false\` skill (the model loads it mid-task), an edit-loop step, or a skill invoked just before an orchestration step is at most "needs-test". Frontmatter cannot split by flag or by step, so do not propose that.
- agent: an agents/*.md \`model:\` sets that subagent's model. A cheap model on an agent file is admitted only in the lean read-only shape (omitClaudeMd, tools limited to Read/Grep/Glob, explicit effort); an agent that edits or runs commands is at most "needs-test".
- harness: a *.workflow.js \`agent(prompt, {model})\` sets one stage's model. Judge per agent() stage: "switch-stage" naming the stage label(s), or "keep". A stage whose dropped items never reach a later stage (an extraction lane, a filter that discards) stays on a stronger model, because nothing downstream can see what it left out.
- gh-workflow: a GitHub workflow passes \`--model\`/\`--effort\` to the Claude CLI or claude-code-action. If the file invokes no Claude at all, return "keep", invokes_model false, rationale "no Claude invocation". Otherwise judge the Claude job: what it asks, its current --model/--effort/--max-turns, and whether --max-turns would need raising.
- Sanctioned cheap readers (the cold-read-gate and evaluate-legibility readers) are "keep" with rationale "already sanctioned measurement instrument".`

const CONTEXT = `
## Why this audit exists
This sweep asks which skills, agents, workflow harnesses and GitHub workflows could run on ${MODEL} (effort ${EFFORT}) instead of Opus or Sonnet. The previous sweep is docs/audits/haiku-5.5-reevaluation-2026-10-10.md.
${A.modelFacts ? `\n## Facts about ${MODEL}\n${A.modelFacts}\n` : ''}${A.history ? `\n## History to re-judge on the model's merits, not on the old pin\n${A.history}\n` : ''}${RUBRIC}`

const ITEM = {
  type: 'object',
  properties: {
    path: { type: 'string', description: 'exactly as given in FILES' },
    current_model: { type: 'string', description: 'current model pin, or "unset"' },
    verdict: { type: 'string', enum: VERDICTS },
    target: { type: 'string', description: 'the concrete change, e.g. "model: haiku + effort: low", "stage parse -> haiku", "--model haiku --effort low"; "" for keep' },
    effort: { type: 'string', enum: ['low', 'medium', 'high', 'n/a'] },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    invokes_model: { type: 'boolean', description: 'false only for a GitHub workflow with no Claude invocation' },
    rationale: { type: 'string', description: '1-2 sentences grounded in what the file instructs' },
    risks: { type: 'array', items: { type: 'string' } },
  },
  required: ['path', 'current_model', 'verdict', 'target', 'effort', 'confidence', 'invokes_model', 'rationale', 'risks'],
}
const CLASSIFY = { type: 'object', properties: { items: { type: 'array', items: ITEM } }, required: ['items'] }

const VITEM = {
  type: 'object',
  properties: {
    path: { type: 'string', description: 'exactly as given in ENTRIES' },
    assessment: { type: 'string', enum: ['confirm', 'adjust', 'reject'] },
    final: { type: 'string', enum: VERDICTS },
    target: { type: 'string' },
    effort: { type: 'string', enum: ['low', 'medium', 'high', 'n/a'] },
    rationale: { type: 'string' },
  },
  required: ['path', 'assessment', 'final', 'target', 'effort', 'rationale'],
}
const VERIFY = {
  type: 'object',
  properties: {
    verdicts: { type: 'array', items: VITEM },
    classifier_quality_notes: { type: 'string', description: 'where the classifier was right or wrong in this set: shallow reading, invented details, rubric misapplied, risks listed but not acted on' },
  },
  required: ['verdicts', 'classifier_quality_notes'],
}

const resolve = (p) => (p.startsWith('/') ? p : `${REPO}/${p}`)

function classifyPrompt(b) {
  return `${CONTEXT}

## Your task
Classify each file below with the rubric. Relative paths resolve against ${REPO}; absolute paths are used as given. Open every file and base the rationale on what it instructs, not on its description. Skim a sibling REFERENCE.md or scripts/ only when the file defers to it, and say so when you did not open one.
Return exactly one item per file — ${b.paths.length} items, the same path strings, none skipped, none added. The count is checked.

FILES=${JSON.stringify(b.paths)}`
}

function verifyPrompt(entries) {
  return `${CONTEXT}

## Your task — independent verification of a ${MODEL} classifier
A ${MODEL} classifier produced the verdicts below. You did not do the classification and have no stake in it; apply agent-patterns-plugin:adversarial-review's refute-first stance to it. For EACH entry, open the file (relative paths resolve against ${REPO}) and decide the correct verdict under the rubric yourself, then set assessment: "confirm" (same verdict, sound target), "adjust" (right direction, wrong tier, target or effort), or "reject" (should be keep, or a keep that is in fact a candidate).
Entries with role "control" are keep verdicts sampled as a control: say so if one is actually a candidate. Be strict about "switch": it is the expensive error. docs/audits/haiku-5.5-reevaluation-2026-10-10.md § Adjudication records the misreadings the last classifier made; check for the same ones.
Return one verdict per entry (${entries.length}), same path strings. In classifier_quality_notes, say concretely how well the classifier did on this set.

ENTRIES=${JSON.stringify(entries)}`
}

// ---------------------------------------------------------------- Classify

const classifierOpts = (b) => ({
  label: `classify:${b.label}`, phase: 'Classify', schema: CLASSIFY, model: MODEL, effort: EFFORT,
  ...(LEAN ? { agentType: 'agents-plugin:lean-reader' } : {}),
})
const classified = await parallel(
  batches.slice(0, 18).map((b) => () => agent(classifyPrompt(b), classifierOpts(b))),
)

const rows = []
const invented = []
let deadClassifiers = 0
batches.forEach((b, i) => {
  const r = classified[i]
  // Batches are never empty, so an empty list is an agent that answered nothing.
  const items = r && Array.isArray(r.items) && r.items.length ? r.items : null
  if (!items) deadClassifiers++
  const byPath = new Map()
  for (const it of items || []) {
    const p = typeof it?.path === 'string' ? it.path.trim().replace(/^\.\//, '') : ''
    if (!b.paths.includes(p)) invented.push({ batch: b.label, path: p })
    else if (!byPath.has(p) && VERDICTS.includes(it.verdict)) byPath.set(p, it)
  }
  for (const p of b.paths) {
    const it = byPath.get(p)
    rows.push({
      path: p, kind: kindOf(p), batch: b.label,
      classifier: it || null,
      disposition: it ? null : 'unclassified',
      reason: it ? null : items ? 'omitted-by-classifier' : 'dead-classifier',
      role: null, verification: null,
    })
  }
})

// ---------------------------------------------------------------- barrier: candidates + control sample

const candidates = rows.filter((r) => r.classifier && r.classifier.verdict !== 'keep')
const eligibleKeeps = rows.filter((r) => r.classifier && r.classifier.verdict === 'keep' && r.classifier.invokes_model !== false)
const autoSample = eligibleKeeps.length ? Math.max(Math.min(3, eligibleKeeps.length), Math.ceil(eligibleKeeps.length / 7)) : 0
const sampleSize = Math.min(CONTROL === null ? autoSample : CONTROL, eligibleKeeps.length)
const sample = []
for (let k = 0; k < sampleSize; k++) sample.push(eligibleKeeps[Math.floor((k * eligibleKeeps.length) / sampleSize)])

candidates.forEach((r) => { r.role = 'candidate' })
sample.forEach((r) => { r.role = 'control' })
rows.forEach((r) => {
  if (r.classifier && !r.role) r.disposition = 'keep-unsampled'
})

const toVerify = [...candidates, ...sample]
const vbatches = []
for (let i = 0; i < toVerify.length; i += VBATCH) {
  vbatches.push({ label: `v${vbatches.length}`, rows: toVerify.slice(i, i + VBATCH) })
}
const entryOf = (r) => ({
  path: r.path, kind: r.kind, role: r.role,
  classifier: { verdict: r.classifier.verdict, current_model: r.classifier.current_model, target: r.classifier.target, effort: r.classifier.effort, rationale: r.classifier.rationale, risks: r.classifier.risks },
})

// ---------------------------------------------------------------- Verify

const verified = await parallel(
  vbatches.slice(0, 8).map((v) => () =>
    agent(verifyPrompt(v.rows.map(entryOf)), {
      label: `verify:${v.label}`, phase: 'Verify', schema: VERIFY, model: 'opus', effort: VERIFY_EFFORT,
    })),
)

const verifierNotes = []
let deadVerifiers = 0
vbatches.forEach((v, i) => {
  const out = i < MAX_VERIFIERS ? verified[i] : undefined
  const list = out && Array.isArray(out.verdicts) && out.verdicts.length ? out.verdicts : null
  if (i < MAX_VERIFIERS && !list) deadVerifiers++
  if (list && out.classifier_quality_notes) verifierNotes.push({ verifier: v.label, notes: out.classifier_quality_notes })
  const byPath = new Map()
  for (const x of list || []) {
    const p = typeof x?.path === 'string' ? x.path.trim().replace(/^\.\//, '') : ''
    if (!byPath.has(p)) byPath.set(p, x)
  }
  for (const r of v.rows) {
    const x = byPath.get(r.path)
    if (x && ['confirm', 'adjust', 'reject'].includes(x.assessment) && VERDICTS.includes(x.final)) {
      r.verification = x
      r.disposition = r.role === 'control' ? 'control-verified' : 'verified'
    } else {
      // A missing answer is never a confirmation.
      r.disposition = 'unverified'
      r.reason = i >= MAX_VERIFIERS ? 'over-verifier-cap' : list ? 'omitted-by-verifier' : 'dead-verifier'
    }
  }
})

// ---------------------------------------------------------------- summary + artifact

const count = (xs, key) => Object.fromEntries(VERDICTS.map((v) => [v, xs.filter((x) => key(x) === v).length]))
const cands = rows.filter((r) => r.role === 'candidate')
const ctrl = rows.filter((r) => r.role === 'control')
const summary = {
  files: rows.length,
  classifiers: { spawned: batches.length, dead: deadClassifiers, model: MODEL, effort: EFFORT, lean: LEAN },
  verifiers: { spawned: Math.min(vbatches.length, MAX_VERIFIERS), dead: deadVerifiers, model: 'opus', effort: VERIFY_EFFORT },
  classifier: { ...count(rows, (r) => r.classifier?.verdict), unclassified: rows.filter((r) => !r.classifier).length },
  candidates: {
    total: cands.length,
    confirm: cands.filter((r) => r.verification?.assessment === 'confirm').length,
    adjust: cands.filter((r) => r.verification?.assessment === 'adjust').length,
    reject: cands.filter((r) => r.verification?.assessment === 'reject').length,
    unverified: cands.filter((r) => !r.verification).length,
  },
  control: {
    sampled: ctrl.length,
    held: ctrl.filter((r) => r.verification?.final === 'keep').length,
    flipped: ctrl.filter((r) => r.verification && r.verification.final !== 'keep').length,
    unverified: ctrl.filter((r) => !r.verification).length,
  },
  final: count(rows.filter((r) => r.verification), (r) => r.verification.final),
  invented: invented.length,
}

const cell = (s) => String(s ?? '').replace(/\|/g, '\\|').replace(/\s*\n\s*/g, ' ')
const pct = (a, b) => (b ? `${Math.round((100 * a) / b)}%` : 'n/a')
const S = summary
const md = [
  `# ${MODEL} model-suitability audit${A.date ? ` — ${A.date}` : ''}`,
  '',
  '## Method',
  '',
  `- **Classify:** ${S.classifiers.spawned} ${MODEL} agents at \`effort: ${EFFORT}\`${LEAN ? ' (lean reader)' : ''}, up to ${BATCH} files each, ${S.files} files${Array.isArray(A.globs) && A.globs.length ? ` from ${A.globs.map((g) => `\`${g}\``).join(', ')}` : ''}.`,
  `- **Verify:** ${S.verifiers.spawned} Opus agents at \`effort: ${VERIFY_EFFORT}\` re-read the ${S.candidates.total} non-\`keep\` verdicts and a control sample of ${S.control.sampled} \`keep\` verdicts.`,
  '- **Adjudicate:** the orchestrating session; see [Adjudication](#adjudication).',
  '',
  '## Results',
  '',
  '| | Classifier | After Opus verification |',
  '|---|---|---|',
  ...VERDICTS.map((v) => `| \`${v}\` | ${S.classifier[v]} | ${S.final[v]} |`),
  `| unclassified | ${S.classifier.unclassified} | — |`,
  '',
  `Opus confirmed ${S.candidates.confirm} of ${S.candidates.total} non-\`keep\` verdicts (${pct(S.candidates.confirm, S.candidates.total)}), adjusted ${S.candidates.adjust} and rejected ${S.candidates.reject}; ${S.candidates.unverified} went unverified. Of ${S.control.sampled} control \`keep\` verdicts, ${S.control.held} held and ${S.control.flipped} flipped.`,
  '',
  '## Verified verdicts',
  '',
  '| Path | Role | Classifier | Assessment | Final | Target | Effort | Rationale |',
  '|---|---|---|---|---|---|---|---|',
  ...rows.filter((r) => r.verification).map((r) =>
    `| \`${cell(r.path)}\` | ${r.role} | ${r.classifier.verdict} | ${r.verification.assessment} | ${r.verification.final} | ${cell(r.verification.target)} | ${r.verification.effort} | ${cell(r.verification.rationale)} |`),
  '',
  '## Not verified',
  '',
  ...(rows.some((r) => r.disposition === 'unclassified' || r.disposition === 'unverified')
    ? rows.filter((r) => r.disposition === 'unclassified' || r.disposition === 'unverified').map((r) => `- \`${r.path}\`: ${r.disposition} (${r.reason})`)
    : ['None.']),
  ...(invented.length ? ['', `Classifier returned ${invented.length} path(s) it was not given; they were dropped.`] : []),
  '',
  '## Classifier quality notes',
  '',
  ...(verifierNotes.length ? verifierNotes.map((n) => `- **${n.verifier}:** ${cell(n.notes)}`) : ['None returned.']),
  '',
  '## Adjudication',
  '',
  '_Written by the orchestrating session: one rule applied across verifiers that disagreed, and what was applied._',
  '',
].join('\n')

return { abort: false, artifactPath, markdown: md, summary, rows, invented, verifierNotes }
