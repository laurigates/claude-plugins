/**
 * survivor-triage.workflow.js — Stages 1 and 2 of
 * `references/triaging-large-survivor-sets.md` as a harness: read-only triage
 * of a Stryker scan by unasserted behaviour, then refute-by-default skeptics on
 * the highest-severity claimed source bugs.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: fan-out → barrier → capped fan-out.
 *   Fan-out unit  — one read-only triage agent per caller cluster (3–10 related
 *                   files), then one skeptic per ranked claim up to the cap.
 *   Loop bound    — `args.clusters`, cut at MAX_CLUSTERS after an explicit
 *                   over-cap abort (never a silent truncation); the skeptics
 *                   are cut at VERIFY_MAX, a literal in the fan-out.
 *   Barrier       — Rank. Every cluster's claims are collected and sorted by
 *                   severity BEFORE any skeptic starts. Pipelining triage into
 *                   verify with a shared slot counter hands the cap to
 *                   whichever cluster finishes first; with the barrier it goes
 *                   to the worst claims in the whole scan.
 *   Hand-back     — claims past the cap, and claims whose skeptic died, return
 *                   in `unverified` with the claim shape, so the same template
 *                   re-runs on them with `{ worktree, claims: <unverified> }`.
 *
 * Read-only throughout: no agent edits source or tests, stages, commits,
 * pushes, or comments. Test writing is Stage 3 of the reference, not this run.
 */

export const meta = {
  name: 'survivor-triage',
  description:
    'Triage a Stryker scan by unasserted behaviour per file cluster, rank claimed source bugs by severity across clusters, verify the top ones with refute-by-default skeptics.',
  phases: [{ title: 'Triage' }, { title: 'Rank' }, { title: 'Verify' }],
}

// `args` may arrive stringified — parse defensively (claims too).
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})
const parseList = (v) => (typeof v === 'string' ? JSON.parse(v) : v)

// ADAPT the numbers, PRESERVE the shape. One cluster is a linear pass: read the
// report and the tests yourself. 8 triage agents + 6 skeptics = 14, under the
// platform's medium workflow-size guideline (<15). A scan with more clusters is
// merged into larger clusters or split into runs; the runs' `unverified` lists
// then go back through ONE verify-only run, which ranks them together.
const FLOOR = 2
const MAX_CLUSTERS = 8
const VERIFY_MAX = 6
const SEVERITY = ['high', 'medium', 'low']
const KINDS = ['test-gap', 'source-bug', 'untested-function', 'dead-code']

const CTX = {
  json: INPUT.json,
  worktree: INPUT.worktree,
  project: INPUT.project ?? '<project: stack, test runner, how the database is mocked>',
  staticMinTests: Number.isInteger(INPUT.staticMinTests) ? INPUT.staticMinTests : 5,
  integrationGlob: INPUT.integrationGlob ?? '',
  severityRubric:
    INPUT.severityRubric ??
    'high = data loss or corruption, authorization, wrong data shown to users, messages sent to the wrong people; medium = wrong ordering/filtering/counts, silent failures; low = logging, cosmetic',
  noise: INPUT.noise ?? [
    'select/projection booleans under a mocked ORM client',
    'log and error-message strings',
    'equivalent mutants',
  ],
  verifyKinds: INPUT.verifyKinds ?? ['source-bug'],
}
const requestedCap = Number.isInteger(INPUT.verifyCap) ? INPUT.verifyCap : 4
const CAP = Math.max(0, Math.min(requestedCap, VERIFY_MAX))
if (CAP !== requestedCap) log(`verifyCap ${requestedCap} clamped to ${CAP} (VERIFY_MAX ${VERIFY_MAX})`)

const abort = (reason, detail) => {
  log(`abort: ${reason} — ${detail}`)
  return { abort: true, reason, detail }
}

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums: they force each finding into one class
// and each skeptic into one verdict instead of a paragraph to interpret.
// ---------------------------------------------------------------------------

const FINDING = {
  type: 'object',
  properties: {
    kind: { type: 'string', enum: KINDS },
    severity: { type: 'string', enum: SEVERITY },
    file: { type: 'string' },
    lines: { type: 'string' },
    summary: { type: 'string' },
    evidence: { type: 'string', description: 'which mutants survive and which covering tests miss them' },
    suggested_test: { type: 'string' },
  },
  required: ['kind', 'severity', 'file', 'lines', 'summary', 'evidence'],
}

const TRIAGE_SCHEMA = {
  type: 'object',
  properties: {
    cluster: { type: 'string' },
    findings: { type: 'array', items: FINDING },
    noise: { type: 'string', description: 'what was dismissed as noise, with rough counts' },
    integration_covered: { type: 'string', description: 'NoCoverage code exercised by suites that skip in a unit run; name the suite' },
  },
  required: ['cluster', 'findings', 'noise'],
}

// held / downgraded / refuted are the reference's Stage 2 verdicts.
const VERDICT_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['held', 'downgraded', 'refuted'] },
    severity: { type: 'string', enum: SEVERITY, description: 're-rated severity' },
    reasoning: { type: 'string', description: 'say "could not reproduce" when that is why it is refuted' },
    reproduction: { type: 'string', description: 'concrete input/state → observed output vs expected output' },
    reachable_in_production: { type: 'boolean' },
  },
  required: ['verdict', 'severity', 'reasoning', 'reproduction', 'reachable_in_production'],
}

// ---------------------------------------------------------------------------
// Prompts — ADAPT freely. They name skills instead of restating them.
// ---------------------------------------------------------------------------

const triagePrompt = (c) => `Triage Stryker mutation-testing survivors for one file cluster. Project: ${CTX.project}.
READ-ONLY: do not edit, stage, commit, push or comment. Source and tests: ${CTX.worktree}.
Follow Stage 1 of \`testing-plugin:mutation-testing\` references/triaging-large-survivor-sets.md.

Cluster "${c.key}": ${c.files.join(', ')}

Survivors come from the Stryker JSON report ${CTX.json}:
jq --arg f '<file>' '.files[$f].mutants[] | select((.status=="Survived" or .status=="NoCoverage") and ((.static|not) or .testsCompleted > ${CTX.staticMinTests})) | {id, mutatorName, replacement, status, line: .location.start.line, coveredBy}' ${CTX.json}
The static filter is deliberate: a static mutant that ran against ${CTX.staticMinTests} or fewer tests ran only against whichever test imported the module first, so its Survived status is not evidence (the skill's "Static survivors under the Vitest runner" section). A static survivor that ran against many tests IS real.

Read each file and the tests that cover it, then report ONE finding per behaviour left unasserted, not one per mutant, as one of: ${KINDS.join(' | ')}.
A source-bug must be statable as a concrete input → wrong output; be strict, it goes to a skeptic.
${CTX.integrationGlob ? `Before calling anything untested-function, check ${CTX.integrationGlob} (suites that skip in a unit run) and report what they cover under integration_covered.` : 'Before calling anything untested-function, check integration/e2e suites that skip in a unit run and report what they cover under integration_covered.'}
Severity: ${CTX.severityRubric}.
Dismiss as noise, with rough counts in \`noise\`: ${CTX.noise.join('; ')}.
Line numbers must be real. At most ~15 findings, highest severity first. Set \`cluster\` to "${c.key}".`

const verifyPrompt = (f) => `A triage agent that is not you claims a ${f.kind} in ${CTX.project}. Try to refute it; the triage agent had a stake in finding something, you do not.
READ-ONLY: do not edit source or real test files, stage, commit, push or comment. Source: ${CTX.worktree}.
Use \`agent-patterns-plugin:adversarial-review\` for the skeptic stance.

Claim: ${f.file}:${f.lines} (${f.severity}) — ${f.summary}
Evidence given: ${f.evidence}

Default to refuted unless you can produce a concrete reproduction: an input or state, the observed output, and the expected output. Check reachability in production (callers, routes, flags, scheduled jobs), upstream normalisation (schemas, callers), whether the behaviour is documented as intended, and whether a test asserts it on purpose.
You may run a throwaway script or test under ${CTX.worktree}/tmp/ (git-ignored); delete it afterwards.
Verdict: held (reproduced as claimed), downgraded (real but lower impact, or a test gap rather than a bug), or refuted. Re-rate severity (${CTX.severityRubric}). A held verdict without a reproduction is recorded as refuted.`

// ---------------------------------------------------------------------------
// Entry: verify-only when `claims` is given (the hand-back of an earlier run),
// otherwise triage the caller's clusters.
// ---------------------------------------------------------------------------

const CLAIMS = INPUT.claims == null ? null : parseList(INPUT.claims)
const MODE = CLAIMS ? 'verify-only' : 'triage'

if (!CTX.worktree) return abort('missing-args', '`worktree` (the checkout the report was produced from) is required')

const clusters = []
const failedClusters = []
let candidates = []

if (MODE === 'verify-only') {
  const ok = Array.isArray(CLAIMS) && CLAIMS.every((f) => f && f.file && f.lines && f.summary && SEVERITY.includes(f.severity))
  if (!ok) return abort('bad-claims', 'each claim needs file, lines, summary and a high|medium|low severity (the `unverified` item shape)')
  candidates = CLAIMS.map((f) => ({ kind: 'source-bug', evidence: '', ...f }))
} else {
  if (!CTX.json) return abort('missing-args', '`json` (the Stryker mutation.json path) is required')
  // Validate shapes before building prompts: a non-array `clusters` or a string
  // `files` would otherwise throw inside the fan-out instead of aborting here.
  const RAW = parseList(INPUT.clusters ?? [])
  if (!Array.isArray(RAW) || RAW.some((c) => !c || typeof c !== 'object')) {
    return abort('bad-clusters', '`clusters` must be an array of { key, files } objects')
  }
  const CLUSTERS = RAW.map((c) => ({ key: String(c.key ?? ''), files: c.files ?? [] }))
  const keys = new Set(CLUSTERS.map((c) => c.key))
  if (CLUSTERS.some((c) => !c.key || !Array.isArray(c.files) || !c.files.length) || keys.size !== CLUSTERS.length) {
    return abort('bad-clusters', 'every cluster needs a unique key and a non-empty `files` array')
  }
  if (CLUSTERS.length < FLOOR) return abort('below-floor', `${CLUSTERS.length} cluster(s): triage inline, the harness is overhead`)
  if (CLUSTERS.length > MAX_CLUSTERS) {
    return abort('over-cap', `${CLUSTERS.length} clusters > ${MAX_CLUSTERS}: merge clusters or split the scan into runs, then verify the runs' unverified lists together`)
  }

  phase('Triage')
  const triaged = await parallel(
    CLUSTERS.slice(0, 8).map((c) => () =>
      agent(triagePrompt(c), { label: `triage:${c.key}`, phase: 'Triage', schema: TRIAGE_SCHEMA, model: 'opus', effort: 'medium' }),
    ),
  )
  // One disposition per input cluster: a dead agent is a failed cluster, never an empty one.
  CLUSTERS.forEach((c, i) => {
    const t = triaged[i]
    if (!t || !Array.isArray(t.findings)) {
      failedClusters.push(c.key)
      return
    }
    clusters.push({ ...t, cluster: c.key })
    t.findings.forEach((f) => {
      if (CTX.verifyKinds.includes(f.kind)) candidates.push({ ...f, cluster: c.key })
    })
  })
  if (failedClusters.length) log(`triage failed for: ${failedClusters.join(', ')} — re-run those clusters`)
}

// ---------------------------------------------------------------------------
// Rank — the barrier. PRESERVE: sort every claim by severity before the cap.
// Array.prototype.sort is stable, so ties keep cluster order, then finding order.
// ---------------------------------------------------------------------------

phase('Rank')
const ranked = [...candidates].sort((a, b) => SEVERITY.indexOf(a.severity) - SEVERITY.indexOf(b.severity))
const toVerify = ranked.slice(0, CAP)
const unverified = ranked.slice(CAP)
if (unverified.length) log(`${unverified.length} claim(s) past the cap of ${CAP} returned in \`unverified\``)

phase('Verify')
const verdicts = await parallel(
  toVerify.slice(0, 6).map((f, i) => () =>
    agent(verifyPrompt(f), { label: `verify:${i + 1}`, phase: 'Verify', schema: VERDICT_SCHEMA, model: 'opus', effort: 'high' }),
  ),
)

const verified = []
toVerify.forEach((f, i) => {
  const v = verdicts[i]
  // A dead skeptic is not a verdict: the claim goes back for a re-run, never to held.
  if (!v || !v.verdict) {
    unverified.push(f)
    return
  }
  // Refute-by-default, enforced here rather than trusted to the prompt.
  const noRepro = v.verdict === 'held' && !(v.reproduction ?? '').trim()
  verified.push({ claim: f, verdict: noRepro ? { ...v, verdict: 'refuted', reasoning: `held without a reproduction; ${v.reasoning ?? ''}` } : v })
})
const byVerdict = (name) => verified.filter((x) => x.verdict.verdict === name)

return {
  mode: MODE,
  clusters,
  failedClusters,
  verified,
  held: byVerdict('held'),
  downgraded: byVerdict('downgraded'),
  refuted: byVerdict('refuted'),
  // Valid `args.claims` as-is: re-run with { worktree, project, claims: unverified }.
  unverified,
}
