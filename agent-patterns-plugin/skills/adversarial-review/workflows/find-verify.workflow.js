/**
 * find-verify.workflow.js — hunt for defects in ONE existing change along named
 * lenses, then try to refute each finding with a fresh verifier.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: lens finders → dedup + severity rank (plain JS) → capped verifiers.
 *   Fan-out unit  — one finder per `args.lenses` entry (≤ 3; a lens may be a
 *                   fresh agent or an external model through PAL), then one
 *                   verifier per ranked finding up to the verify cap.
 *   Loop bound    — the caller's lens list (an over-cap list aborts, it is never
 *                   truncated) and VERIFY_CAP. Findings past the cap come back
 *                   as `unverified`, never dropped.
 *   Barrier       — Rank. Dedup and the severity order need every lens's
 *                   findings before the cap can pick which ones to verify.
 *   Stop judge    — the verifier, which did not find the defect and defaults to
 *                   `refuted` (`.claude/rules/loop-integrity.md` Pillar 1).
 *
 * Read-only end to end: no agent edits tracked files, commits, pushes or
 * touches GitHub. Fixes are handed back in the result.
 *
 * Verify-only re-run: pass a previous run's `unverified` list as `args.claims`.
 * Find is skipped and the claims go straight to Rank and Verify.
 *
 * `args.target.ref` is required: every agent reads the change from that ref, and
 * an isolated verifier detaches its own worktree at the commit it resolves to.
 */

export const meta = {
  name: 'find-verify',
  description:
    'Adversarial review of one change: lens finders, cross-lens dedup and severity rank, capped refute-by-default verifiers.',
  phases: [{ title: 'Find' }, { title: 'Rank' }, { title: 'Verify' }],
}

// `args` may arrive stringified — parse defensively.
const INPUT = typeof args === 'string' ? JSON.parse(args) : (args ?? {})

// ADAPT the numbers, PRESERVE the shape. One lens is the skill's inline path
// (SKILL.md Step 3): a single Agent call costs the same without a harness.
const MIN_LENSES = 2
const MAX_LENSES = 3
// Verifier ceiling. 3 of 4 ad-hoc runs hit a cap of 4–6 and returned an
// unverified remainder; raise only with evidence.
const MAX_VERIFY = 6
const MAX_CONTROL = 2
// Verifiers run in waves of this size (verify-before-filing's pacing), so a full
// cap plus control sample never starts 8 opus agents at once.
const WAVE = 5

const T = INPUT.target ?? {}
const CTX = {
  repo: T.repo ?? '<absolute path of the repo under review>',
  // No default: 'HEAD' inside an isolated verifier's worktree names that
  // worktree's commit, not the one under review. The guard below aborts.
  ref: T.ref ?? '',
  base: T.base ?? 'origin/main',
  pr: T.pr ?? '',
  files: T.files ?? [],
  context: INPUT.context ?? '',
  decided: INPUT.decided ?? [],
  measured: INPUT.measured ?? [],
  constraints: INPUT.constraints ?? [],
  verifierRunHint: INPUT.verifierRunHint ?? '',
}
// null and '' mean "use the default" (Number(null) is the integer 0).
const clampInt = (v, lo, hi, dflt) => {
  const n = v == null || v === '' ? dflt : Number.isInteger(Number(v)) ? Number(v) : dflt
  return Math.max(lo, Math.min(hi, n))
}
const VERIFY_CAP = clampInt(INPUT.verifyCap, 0, MAX_VERIFY, MAX_VERIFY)
const CONTROL = clampInt(INPUT.controlSample, 0, MAX_CONTROL, 0)
const ISOLATE = INPUT.verifyIsolation !== 'none'

const LENSES = (INPUT.lenses ?? []).map((l, i) => ({
  key: String(l.key ?? `lens-${i + 1}`),
  prompt: l.prompt ?? '',
  skills: l.skills ?? [],
  pal: l.finder && typeof l.finder === 'object' ? { model: l.finder.pal, tool: l.finder.tool ?? 'codereview' } : null,
}))

// ---------------------------------------------------------------------------
// Claims: one shape in, the same shape out.
// ---------------------------------------------------------------------------

// PRESERVE one severity enum. External models say critical/blocker; reviews say
// major/minor/nit. Ranking only works on one scale.
const SEVERITY = { high: 0, medium: 1, low: 2 }
const normSeverity = (s) => {
  const v = String(s ?? '').toLowerCase()
  if (['critical', 'blocker', 'high'].includes(v)) return 'high'
  if (['low', 'minor', 'nit', 'trivial'].includes(v)) return 'low'
  return 'medium'
}
// The part of a claim dedup folds into a kept entry's `also`.
const brief = (c) => ({
  lens: c.lens,
  raised_by: c.raised_by,
  title: c.title,
  severity: c.severity,
  claim: c.claim,
  failure_scenario: c.failure_scenario,
  suggested_fix: c.suggested_fix,
})
const normClaim = (f, lens) => ({
  title: String(f.title ?? f.summary ?? '').trim(),
  file: String(f.file ?? '').replace(/^\.\//, ''),
  line: Number.isInteger(Number(f.line)) ? Number(f.line) : 0,
  severity: normSeverity(f.severity),
  claim: String(f.claim ?? f.detail ?? ''),
  failure_scenario: String(f.failure_scenario ?? ''),
  suggested_fix: String(f.suggested_fix ?? f.proposed_fix ?? ''),
  lens: f.lens ?? lens ?? 'claims',
  raised_by: [...new Set([...(f.raised_by ?? []), f.lens ?? lens ?? 'claims'])],
  also: Array.isArray(f.also) ? f.also.map((a) => brief(normClaim(a, a.lens))) : [],
})
const keyOf = (f) => (f.line > 0 ? `${f.file}:${f.line}` : `${f.file}#${f.title.toLowerCase()}`)

// Merge duplicates instead of dropping them: a finding several lenses (or
// several external models) raised is the agreement signal
// agent-patterns-plugin:multi-model-delegation cares about. The merged entry
// keeps the most severe wording, and every other claim at that location rides
// along in `also`: two different defects can share a file:line, so the verifier
// rules on each one and a distinct one comes back `unverified`, never vanishes.
const dedup = (claims) => {
  const byKey = new Map()
  for (const c of claims) {
    const k = keyOf(c)
    const prev = byKey.get(k)
    if (!prev) {
      byKey.set(k, { ...c, also: [...c.also] })
      continue
    }
    const raised = [...new Set([...prev.raised_by, ...c.raised_by])]
    const [keep, drop] = SEVERITY[c.severity] < SEVERITY[prev.severity] ? [c, prev] : [prev, c]
    byKey.set(k, { ...keep, raised_by: raised, also: [...prev.also, ...c.also, brief(drop)] })
  }
  return [...byKey.values()]
}
// Severity first, then cross-lens agreement, then input order (stable sort).
const rank = (claims) =>
  claims
    .map((c, i) => ({ c, i }))
    .sort((a, b) => SEVERITY[a.c.severity] - SEVERITY[b.c.severity] || b.c.raised_by.length - a.c.raised_by.length || a.i - b.i)
    .map((x) => x.c)

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums.
// ---------------------------------------------------------------------------

const FINDINGS_SCHEMA = {
  type: 'object',
  required: ['findings'],
  additionalProperties: false,
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        required: ['title', 'file', 'line', 'severity', 'claim', 'failure_scenario', 'suggested_fix'],
        additionalProperties: false,
        properties: {
          title: { type: 'string' },
          file: { type: 'string', description: 'repo-relative path' },
          line: { type: 'integer', description: 'line at the ref; 0 when the defect has no single line' },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          claim: { type: 'string' },
          failure_scenario: { type: 'string', description: 'concrete input/state → observable wrong outcome' },
          suggested_fix: { type: 'string' },
        },
      },
    },
  },
}

// `could-not-verify` is deliberately absent: refute-by-default is the point.
// A refutation for lack of a reproduction says so in `evidence`.
const VERDICT_SCHEMA = {
  type: 'object',
  required: ['verdict', 'evidence', 'corrected_claim', 'fix_recommendation', 'severity', 'distinct_also'],
  additionalProperties: false,
  properties: {
    verdict: { type: 'string', enum: ['confirmed', 'partially', 'refuted'] },
    evidence: { type: 'string', description: 'what you read or ran, with outputs; "could not reproduce: …" when that is why' },
    reproduction: { type: 'string', description: 'for confirmed/partially: the input/state and the wrong outcome you observed' },
    corrected_claim: { type: 'string' },
    fix_recommendation: { type: 'string' },
    severity: { type: 'string', enum: ['high', 'medium', 'low'], description: 'your re-rating' },
    distinct_also: {
      type: 'array',
      items: { type: 'integer' },
      description: 'indexes of the "also reported" entries that describe a DIFFERENT defect; [] when none',
    },
  },
}

// ---------------------------------------------------------------------------
// Prompts — ADAPT the wording, keep the clauses.
// ---------------------------------------------------------------------------

const listOr = (xs, none) => (xs.length ? xs.map((x) => `  - ${x}`).join('\n') : `  ${none}`)
const target = () => `Under review: ${CTX.ref} in ${CTX.repo}${CTX.pr ? ` (PR ${CTX.pr})` : ''}, against ${CTX.base}.
Read the change from refs, never from a checkout someone may be editing:
  git -C ${CTX.repo} diff ${CTX.base}...${CTX.ref}      (three dots)
  git -C ${CTX.repo} show ${CTX.ref}:<path>
${CTX.files.length ? `Main files:\n${listOr(CTX.files, '')}\n` : ''}${CTX.context ? `\nContext:\n${CTX.context}\n` : ''}
Decided by the owner — NOT findings, do not report them:
${listOr(CTX.decided, '(none)')}
Measured by the author — verify them if you doubt them:
${listOr(CTX.measured, '(none)')}
${CTX.constraints.length ? `Constraints:\n${listOr(CTX.constraints, '')}\n` : ''}`

const FIND_BAR = `Report only defects you can tie to a concrete input or state and an observable wrong outcome
(wrong output, wrong cache hit, misleading error, a doc claim the code contradicts). No style nits.
Cite file:line at ${CTX.ref}. Read-only: do not edit tracked files, stage, commit, push, or comment anywhere.
An empty list is a valid answer when you looked and found nothing.`

const FIND_PROMPT = (l) =>
  l.pal
    ? `${target()}
You run an external-model code review through PAL with model "${l.pal.model}".
Load the tool with ToolSearch("select:mcp__pal__${l.pal.tool}"), then call mcp__pal__${l.pal.tool} with
model "${l.pal.model}", review_type "full", and relevant_files = absolute paths of the changed files
(${CTX.files.length ? CTX.files.map((f) => `${CTX.repo}/${f}`).join(', ') : `from git -C ${CTX.repo} diff --name-only ${CTX.base}...${CTX.ref}`}).
Follow its multi-step protocol until the expert analysis returns. Do not pass temperature for kimi models.
${l.prompt ? `Focus for this lens: ${l.prompt}\n` : ''}
Return every issue the external model and you found, in substance even when you doubt it — a later stage
verifies each one. ${FIND_BAR}`
    : `${target()}
You are an adversarial reviewer. Your only objective is to find ways this change is WRONG; do not confirm
that it works. Lens "${l.key}":
${l.prompt}
${l.skills.length ? `Invoke ${l.skills.join(', ')} with the Skill tool for this lens's checklist.\n` : ''}
${FIND_BAR}`

const VERIFY_PROMPT = (f) => `${target()}
You are an adversarial verifier (agent-patterns-plugin:adversarial-review). You did not find this defect and
have no stake in it being real. Try to REFUTE it. Default to "refuted" unless you can construct a concrete
reproduction: an input or state, and the wrong outcome it produces.

Before confirming, check: is the code path reachable in production (callers, routes, flags, schedules)? Does
an upstream caller or schema normalise the input away? Is the behaviour documented as intended? Does a test
assert it on purpose?

${ISOLATE ? `You are in your own worktree. Detach it at the reviewed commit before building or running anything:
  SHA=$(git -C ${CTX.repo} rev-parse --verify '${CTX.ref}^{commit}')
  git -C <your worktree> switch --detach "$SHA"     (git -C <your worktree> fetch -q origin first if the object is missing)
Never detach at a symbolic ref such as HEAD from inside your worktree: it names your worktree's commit, not the reviewed one.
` : ''}You may write and run a scratch test or script — in your own worktree or under ${CTX.repo}/tmp/ (git-ignored),
deleted afterwards. Do not edit tracked source, stage, commit or push.${CTX.verifierRunHint ? `\nRun tests with: ${CTX.verifierRunHint}` : ''}

Finding (${f.raised_by.join(' + ')}, ${f.severity}): ${f.title}
Location: ${f.file}${f.line ? `:${f.line}` : ''}
Claim: ${f.claim}
Failure scenario: ${f.failure_scenario}
Suggested fix: ${f.suggested_fix}
${f.also.length ? `
Also reported at this location (merged here because it cites the same place):
${f.also.map((a, j) => `  [${j}] ${a.raised_by.join(' + ')}, ${a.severity}: ${a.title} — ${a.claim} Failure: ${a.failure_scenario}`).join('\n')}
Your verdict covers the finding above. Put in distinct_also the index of every entry that describes a DIFFERENT
defect; each comes back unverified for its own verifier.
` : ''}
If confirmed or partially confirmed, give the reproduction — a verdict without one counts as a failed verifier —
and re-rate the severity. If you refute it because you could not reproduce it, start evidence with
"could not reproduce:". Return distinct_also as [] when nothing else is listed or all of it is this defect.`

// PRESERVE: one literal call site per option set, so every model and effort is checkable.
const verify = (f, i, control) => {
  const opts = { label: `${control ? 'control' : 'verify'}:${i + 1}:${f.raised_by[0]}`, phase: 'Verify', schema: VERDICT_SCHEMA }
  if (ISOLATE) return agent(VERIFY_PROMPT(f), { ...opts, model: 'opus', effort: 'high', isolation: 'worktree' })
  return agent(VERIFY_PROMPT(f), { ...opts, model: 'opus', effort: 'high' })
}

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort.
// ---------------------------------------------------------------------------

const CLAIMS_IN = Array.isArray(INPUT.claims) ? INPUT.claims : null

if (CLAIMS_IN && !CLAIMS_IN.length) {
  log('args.claims is empty — nothing to verify; abort')
  return { abort: true, reason: 'no-claims' }
}
if (!CLAIMS_IN && LENSES.length < MIN_LENSES) {
  log(`${LENSES.length} lens(es) (< ${MIN_LENSES}) — dispatch one reviewer inline (SKILL.md Step 3); abort`)
  return { abort: true, reason: 'below-floor', lenses: LENSES.length }
}
if (!CLAIMS_IN && LENSES.length > MAX_LENSES) {
  log(`${LENSES.length} lenses (> ${MAX_LENSES}) — merge lenses or split the run; abort without truncating`)
  return { abort: true, reason: 'over-cap', lenses: LENSES.map((l) => l.key) }
}
const dupKeys = LENSES.map((l) => l.key).filter((k, i, a) => a.indexOf(k) !== i)
if (dupKeys.length) {
  log(`duplicate lens keys (${dupKeys.join(', ')}) — raised_by would conflate them; abort`)
  return { abort: true, reason: 'duplicate-lens', lenses: dupKeys }
}
if (!CTX.ref) {
  log('args.target.ref is required — pass the branch, tag or SHA under review; abort')
  return { abort: true, reason: 'no-ref' }
}

// ---------------------------------------------------------------------------
// Find — one finder per lens, skipped on a verify-only run.
// ---------------------------------------------------------------------------

let claims = []
const lensesFailed = []
if (CLAIMS_IN) {
  claims = CLAIMS_IN.map((c) => normClaim(c, c.lens))
  log(`verify-only run: ${claims.length} claim(s) from args`)
} else {
  phase('Find')
  // PRESERVE the literal bound in the fan-out, with agent() inline: the scale
  // guard counts it. A PAL lens is the same opus agent with a different brief.
  const found = await parallel(
    LENSES.slice(0, 3).map((l) => () =>
      agent(FIND_PROMPT(l), { label: `find:${l.key}`, phase: 'Find', schema: FINDINGS_SCHEMA, model: 'opus', effort: 'high' }),
    ),
  )
  found.forEach((r, j) => {
    const l = LENSES[j]
    // A dead finder is a coverage gap, not "no findings".
    if (!r || !Array.isArray(r.findings)) return lensesFailed.push(l.key)
    claims.push(...r.findings.map((f) => normClaim(f, l.key)))
  })
  if (lensesFailed.length) log(`finder(s) returned nothing: ${lensesFailed.join(', ')} — that lens is unreviewed`)
}

// ---------------------------------------------------------------------------
// Rank — BARRIER. Dedup and order across every lens, then cap.
// ---------------------------------------------------------------------------

phase('Rank')
const ranked = rank(dedup(claims))
const toVerify = ranked.slice(0, VERIFY_CAP)
const remainder = ranked.slice(VERIFY_CAP)
// Control sample: the k lowest-ranked findings the cap cut. If they confirm at
// the same rate as the verified ones, the cap is discarding real defects.
const controls = CONTROL ? remainder.slice(-CONTROL) : []
const rest = remainder.slice(0, remainder.length - controls.length)
log(`${claims.length} finding(s), ${ranked.length} after dedup; verifying ${toVerify.length} + ${controls.length} control, ${rest.length} left unverified`)

// ---------------------------------------------------------------------------
// Verify — one fresh verifier per selected finding.
// ---------------------------------------------------------------------------

phase('Verify')
const picked = [...toVerify.map((f) => ({ f, control: false })), ...controls.map((f) => ({ f, control: true }))]
const verdicts = []
for (let w = 0; w < picked.length; w += WAVE) {
  const wave = picked.slice(w, w + WAVE)
  verdicts.push(...(await parallel(wave.map((p, j) => () => verify(p.f, w + j, p.control)))))
}

const out = { confirmed: [], partially: [], refuted: [], unverified: [...rest] }
const verifierFailed = []
const control = { sampled: controls.length, confirmed: 0, partially: 0, refuted: 0, failed: 0 }
// Indexes of the `also` entries the verifier called a different defect; null
// when it did not rule on them.
const distinctOf = (f, v) => {
  if (!f.also.length) return []
  if (!Array.isArray(v.distinct_also)) return null
  return [...new Set(v.distinct_also)].filter((j) => Number.isInteger(j) && j >= 0 && j < f.also.length)
}
picked.forEach((p, i) => {
  const v = verdicts[i]
  const onEnum = v && ['confirmed', 'partially', 'refuted'].includes(v.verdict)
  // Refute-by-default is enforced here, not only in the prompt: a confirmation
  // with no reproduction is not evidence.
  const reproduced = onEnum && (v.verdict === 'refuted' || String(v.reproduction ?? '').trim() !== '')
  const distinct = onEnum ? distinctOf(p.f, v) : null
  // A null, off-enum, unreproduced or incomplete verdict is a dead verifier: the
  // finding goes back to `unverified` so a verify-only re-run can pick it up. It
  // is never dropped and never counted as refuted.
  if (!onEnum || !reproduced || distinct === null) {
    verifierFailed.push(keyOf(p.f))
    out.unverified.push(p.f)
    if (p.control) control.failed++
    return
  }
  const split = p.f.also.filter((_, j) => distinct.includes(j))
  const same = p.f.also.filter((_, j) => !distinct.includes(j))
  // A lens that raised only a split-off claim no longer agrees with this one.
  const onlySplit = (l) => l !== p.f.lens && split.some((a) => a.raised_by.includes(l)) && !same.some((a) => a.raised_by.includes(l))
  out[v.verdict].push({ ...p.f, raised_by: p.f.raised_by.filter((l) => !onlySplit(l)), also: same, control: p.control, verdict: v })
  out.unverified.push(...split.map((a) => normClaim({ ...a, file: p.f.file, line: p.f.line }, a.lens)))
  if (p.control) control[v.verdict]++
})
if (verifierFailed.length) log(`verifier(s) returned nothing for: ${verifierFailed.join(', ')} — returned as unverified`)

// Empty buckets after every finder died are a coverage gap, not a clean change.
const status = !CLAIMS_IN && lensesFailed.length === LENSES.length ? 'unreviewed' : lensesFailed.length ? 'partial' : 'reviewed'

return {
  status,
  ...out,
  control,
  lensesFailed,
  verifierFailed,
  stats: { findings: claims.length, deduped: ranked.length, verified: picked.length - verifierFailed.length, verifyCap: VERIFY_CAP },
}
