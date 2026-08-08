/**
 * verify-before-filing.workflow.js — Phases 1+2 of
 * `workflow-orchestration-plugin:workflow-verify-before-filing`.
 *
 * A TEMPLATE to adapt, not a script to run verbatim. The framing that says what
 * may be rewritten and what is structure lives in the sibling SKILL.md
 * § "Workflow harness (template)"; the rationale for the constants lives in
 * REFERENCE.md. Read both before adapting this.
 *
 * SHAPE — composite: fan-out (verify ∥ search per candidate) → generate-and-filter
 * (draft → cold-read → revise) → one batch-dedup barrier.
 *
 * WHY A HARNESS AT ALL (.claude/rules/workflow-vs-skill.md, the three axes):
 *   1. Enumerable N   — the candidate manifest passed in as `args`. The model
 *                       never invents the fan-out width.
 *   2. Load-bearing barriers — `parallel([verify, search])` (the gate reads BOTH),
 *                       and batch-dedup, which must see every survivor at once.
 *   3. Script-decidable bound — `CANDIDATES.length`, sliced into fixed waves.
 *   Agent count is identical to what the prose already ran; what the harness
 *   buys is that the gate stops being a boolean re-derived from prose each run.
 *
 * WHAT THIS HARNESS NEVER DOES
 *   Nothing here files anything. Every agent is READ-ONLY upstream (GET only).
 *   Issue creation is Phase 3 — the single sequential finalise stage, which is
 *   `scripts/file-wave.sh` and owns the pacing, the retries, and the manifest.
 */

export const meta = {
  name: 'verify-before-filing',
  description:
    'Verify upstream bug candidates at HEAD, dedup against the trackers, draft, cold-read gate, batch dedup.',
  phases: [
    { title: 'Verify' },
    { title: 'Search' },
    { title: 'Draft' },
    { title: 'ColdRead' },
    { title: 'Revise' },
    { title: 'BatchDedup' },
  ],
}

// `args` may arrive stringified — parse defensively (observed; see REFERENCE.md).
const INPUT = typeof args === 'string' ? JSON.parse(args) : args
// A bare manifest array is accepted as well as `{ candidates: [...] }`.
const CANDIDATES = Array.isArray(INPUT) ? INPUT : (INPUT.candidates ?? [])

// ADAPT: where the drafting agents write their markdown. Phase 3 reads these
// paths off disk, so they must be absolute (or relative to file-wave.sh's
// --draft-dir). The workflow itself has no filesystem — it never reads them.
const DRAFT_DIR = INPUT.draftDir ?? '/abs/path/to/drafts'

// PRESERVE: reads are paced the way Phase 3 paces writes. The skill calls the
// issue endpoints "aggressively rate-limiting" (429 after a SINGLE create); an
// unbounded fan-out over a 24-candidate manifest would fire 48 concurrent read
// agents at that same instance. Raise only with evidence.
const WAVE = 5

if (!CANDIDATES.length) {
  log('empty candidate manifest — nothing to verify; abort')
  return { results: [], merged: [], dispositions: [] }
}
if (CANDIDATES.length < 3) {
  // The modal small case. Two candidates is a linear pass; the harness would
  // spend agent preambles to save nothing.
  log(`${CANDIDATES.length} candidate(s) — run Phase 1 inline instead; abort`)
  return { abort: true, reason: 'below the harness floor (<3 candidates)' }
}

// ---------------------------------------------------------------------------
// Prompt fragments — ADAPT ALL OF THESE. The forge block below is the GitLab
// worked example from REFERENCE.md; swap it for `gh` (or your forge) wholesale.
// ---------------------------------------------------------------------------

const FORGE_TOOLING = `Tooling (READ-ONLY — GET requests only; never create, edit, or comment upstream):
- GITLAB_HOST=<instance> glab api "projects/<id-or-urlencoded-path>" (.default_branch)
- ... "projects/<id>/repository/files/<URL-ENCODED-PATH>/raw?ref=<ref>" (slashes as %2F)
- ... "projects/<id>/repository/tags?per_page=20"
- ... "groups/<urlencoded-group>/search?scope=issues&search=<term>"
Known project IDs: <paste your map>.`

const PRIOR_REPORTS = `Our own prior filed reports (fetch the FULL bodies and judge overlap
INCLUDING their by-catch findings — self-duplicates are the embarrassing kind):
- <project> issues <iids> (<one-line topic each>)`

const VERIFY_PROMPT = (item) => `You verify one candidate upstream bug. ${FORGE_TOOLING}

Baseline: observed at "${item.observed_version}". Determine whether the flaw is STILL
PRESENT at default-branch HEAD *and* at the latest tag — checking only one misses
"fixed on main, broken in every release" and its inverse. Quote the exact current
content. A superseded line => obsolete-version. A claim wrong on inspection =>
claim-invalid. Evidence unreachable => could-not-verify (never guess).

## ${item.id} (${item.slug})
Targets: ${(item.targets ?? []).join(' ; ')}

${item.claim}

Your output is raw data for a machine.`

const SEARCH_PROMPT = (item) => `You check whether this bug was ALREADY reported. ${FORGE_TOOLING}

${PRIOR_REPORTS}

Search the target project(s) and group-wide — issues AND merge/pull requests, state=all,
several phrasings including the exact error strings — then judge overlap with our prior
reports above.

## ${item.id}
Bug: ${item.claim}

Your output is raw data for a machine.`

const DRAFT_PROMPT = (c) => `Draft one upstream issue per the house template (read 1-2 prior
examples in ${DRAFT_DIR}). Target project: ${c.verify.targetProject}.

Claim: ${c.claim}
Verified evidence — pin every blob link to THESE refs, never to a bare path or to \`main\`:
${c.verify.evidence}
Checked refs: ${c.verify.checkedRefs}
Notes (framing corrections, moved files, drifted versions): ${c.verify.notes}

Mine the real error signature from PRs ${JSON.stringify(c.evidence_prs ?? [])} via
\`gh pr view <n> --json body\`. Never leak internal PR numbers or repo paths into the body.
Recommend EXACTLY ONE fix; alternatives get one trailing sentence.

Write the file to ${DRAFT_DIR}/${c.id}-${c.slug}.md AND return its full body text.`

const COLDREAD_PROMPT = (body) => `You are an upstream maintainer triaging a newly filed issue.
You have NO context beyond the text below. Read only this text.

Report your QUESTIONS and HESITATIONS, then a verdict. Ignore any leading HTML comments
(they are stripped before filing) and the fact that the repo is implicit — the issue is
filed on the target project's own tracker.

---
${body}`

const REVISE_PROMPT = (draft, critique) => `Revise the draft at ${draft.path} IN PLACE per the
critique below, then return the revised body.

Apply only GENUINE gaps (unpinned links, unexplained jargon, missing evidence, more than one
recommended fix). Ignore test artifacts: the HTML target comment, and the implicit repo.

Critique:
${critique}

Draft body:
${draft.body}`

const BATCH_DEDUP_PROMPT = (survivors) => `You are the last gate before ${survivors.length}
issues are filed on the same upstream. Compare the drafts to EACH OTHER — not to the tracker;
that pass already ran per candidate. Two candidates sourced from different audit docs
routinely describe one upstream defect, and filing both is the noise this whole workflow exists
to prevent.

For every merge you decide on: rewrite the SURVIVING draft file in place so it covers both
claims, and return the merged-away id pointing at its survivor. Change nothing else — a draft
you are not merging must be returned byte-identical.

Drafts:
${JSON.stringify(
  survivors.map((c) => ({
    id: c.id,
    slug: c.slug,
    path: c.draft.path,
    title: c.draft.title,
    targetProject: c.draft.targetProject,
    body: c.draft.body,
  })),
  null,
  2,
)}`

// ---------------------------------------------------------------------------
// Schemas — PRESERVE the closed enums. They are what force a determinate verdict
// instead of a paragraph the gate then has to interpret.
// ---------------------------------------------------------------------------

const VERIFY_SCHEMA = {
  type: 'object',
  properties: {
    verdict: {
      type: 'string',
      enum: [
        'still-present',
        'partially-fixed',
        'fixed-upstream',
        'obsolete-version',
        'claim-invalid',
        'could-not-verify',
      ],
    },
    targetProject: { type: 'string' },
    evidence: { type: 'string', description: 'quoted current content with paths + refs' },
    checkedRefs: { type: 'string' },
    notes: { type: 'string' },
  },
  required: ['verdict', 'targetProject', 'evidence', 'checkedRefs', 'notes'],
}

const SEARCH_SCHEMA = {
  type: 'object',
  properties: {
    duplicateFound: { type: 'string', enum: ['yes', 'possibly', 'no'] },
    hits: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          url: { type: 'string' },
          title: { type: 'string' },
          state: { type: 'string' },
          relevance: { type: 'string' },
        },
        required: ['url', 'title', 'state', 'relevance'],
      },
    },
    wave1Overlap: {
      type: 'string',
      description: 'overlap with OUR prior reports incl. their by-catch findings, or "none"',
    },
    searchedTerms: { type: 'string' },
  },
  required: ['duplicateFound', 'hits', 'wave1Overlap', 'searchedTerms'],
}

// PRESERVE: `body` is required, not just `path`. Batch dedup and the cold read
// both run INSIDE this script, which has no filesystem — neither can open a path.
// `path` is still required because Phase 3 (scripts/file-wave.sh) reads the draft
// off disk, so the two must stay in sync: the drafting agent writes the file AND
// returns its text.
const DRAFT_SCHEMA = {
  type: 'object',
  properties: {
    path: { type: 'string', description: 'absolute path the agent wrote the draft to' },
    title: { type: 'string', description: 'symptom-first; becomes the issue title' },
    targetProject: { type: 'string' },
    body: { type: 'string', description: 'the full markdown body, not a path to it' },
  },
  required: ['path', 'title', 'targetProject', 'body'],
}

const COLD_SCHEMA = {
  type: 'object',
  properties: {
    verdict: { type: 'string', enum: ['clear', 'needs-revision'] },
    critique: { type: 'string' },
  },
  required: ['verdict', 'critique'],
}

const BATCH_SCHEMA = {
  type: 'object',
  properties: {
    keep: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          path: { type: 'string' },
          title: { type: 'string' },
          targetProject: { type: 'string' },
        },
        required: ['id', 'path', 'title', 'targetProject'],
      },
    },
    merged: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          into: { type: 'string' },
          why: { type: 'string' },
        },
        required: ['id', 'into', 'why'],
      },
    },
  },
  required: ['keep', 'merged'],
}

// ---------------------------------------------------------------------------
// Phase 1+2 — waves of ≤5 candidates, each wave a fan-out then a filter chain.
// ---------------------------------------------------------------------------

const triaged = []

for (let i = 0; i < CANDIDATES.length; i += WAVE) {
  const slice = CANDIDATES.slice(i, i + WAVE)
  phase(`Verify + dedup — candidates ${i + 1}..${Math.min(i + WAVE, CANDIDATES.length)}`)

  const wave = await pipeline(
    slice,

    // Stage 1 — BARRIER (intra-candidate): the gate needs BOTH results, so the
    // two reads run in parallel and are joined before anything is decided.
    async (item) => {
      const [verify, search] = await parallel([
        () =>
          agent(VERIFY_PROMPT(item), {
            label: `verify:${item.id}`,
            phase: 'Verify',
            model: 'opus',
            effort: 'medium',
            schema: VERIFY_SCHEMA,
          }),
        () =>
          agent(SEARCH_PROMPT(item), {
            label: `search:${item.id}`,
            phase: 'Search',
            model: 'opus',
            effort: 'medium',
            schema: SEARCH_SCHEMA,
          }),
      ])
      if (!verify || !search) return { ...item, disposition: 'agent-error' }

      // PRESERVE — the gate, and its precedence. A duplicate kills the filing
      // REGARDLESS of verdict; `could-not-verify` never files (it becomes a
      // human follow-up task, not a filed issue). Every gated-out candidate
      // keeps a recorded disposition: those records are a Phase 4 deliverable.
      const passes =
        ['still-present', 'partially-fixed'].includes(verify.verdict) &&
        search.duplicateFound === 'no'
      const disposition = passes
        ? 'draft'
        : search.duplicateFound !== 'no'
          ? `duplicate: ${search.wave1Overlap}`
          : verify.verdict
      if (!passes) log(`${item.id} gated out: ${disposition}`)
      return { ...item, verify, search, disposition }
    },

    // Stage 2 — draft the survivors only.
    async (c) => {
      if (c.disposition !== 'draft') return c
      const draft = await agent(DRAFT_PROMPT(c), {
        label: `draft:${c.id}`,
        phase: 'Draft',
        model: 'opus',
        effort: 'medium',
        schema: DRAFT_SCHEMA,
      })
      return draft ? { ...c, draft } : { ...c, disposition: 'draft-failed' }
    },

    // Stage 3 — the cold-read gate. PRESERVE: this agent is NEVER the drafter.
    // Its independence is the whole point (.claude/rules/loop-integrity.md
    // Pillar 1; agent-patterns-plugin:cold-read-gate) — an author asked to judge
    // their own draft optimises for done, not for legible. `model: 'haiku'` is
    // deliberate and sanctioned: this reader is the measurement instrument
    // ("can a low-context reader act on this text alone?"), and a stronger model
    // answers an easier question. Do not "fix" it to opus.
    async (c) => {
      if (!c.draft) return c
      let cold = await agent(COLDREAD_PROMPT(c.draft.body), {
        label: `coldread:${c.id}`,
        phase: 'ColdRead',
        model: 'haiku',
        schema: COLD_SCHEMA,
      })
      if (cold?.verdict === 'needs-revision') {
        const revised = await agent(REVISE_PROMPT(c.draft, cold.critique), {
          label: `revise:${c.id}`,
          phase: 'Revise',
          model: 'opus',
          effort: 'low',
          schema: DRAFT_SCHEMA,
        })
        if (revised) c = { ...c, draft: revised }
        cold = await agent(COLDREAD_PROMPT(c.draft.body), {
          label: `recoldread:${c.id}`,
          phase: 'ColdRead',
          model: 'haiku',
          schema: COLD_SCHEMA,
        })
      }
      // PRESERVE: exactly ONE revise round. This is a fixed gate, not a
      // loop-until-clear — a second reader is not a better judge of the same
      // text, and an unbounded critique loop has no independent stop condition.
      return { ...c, cold, disposition: 'file' }
    },
  )

  triaged.push(...wave)
}

// ---------------------------------------------------------------------------
// BARRIER — batch dedup. PRESERVE: this needs every survivor at once, which is
// exactly what makes it a barrier rather than something the last agent could
// have done inline. The per-candidate search compared each draft to the
// TRACKER; nothing yet compared the drafts to EACH OTHER.
// ---------------------------------------------------------------------------

phase('Batch dedup — survivors compared to EACH OTHER, not just to the tracker')

const filing = triaged.filter((c) => c.disposition === 'file' && c.draft)
let keep = filing
let merged = []

if (filing.length > 1) {
  const batch = await agent(BATCH_DEDUP_PROMPT(filing), {
    label: 'batch-dedup',
    phase: 'BatchDedup',
    model: 'opus',
    effort: 'medium',
    schema: BATCH_SCHEMA,
  })
  if (batch) {
    const kept = new Set(batch.keep.map((k) => k.id))
    merged = batch.merged
    keep = filing.filter((c) => kept.has(c.id))
    for (const m of merged) {
      const target = triaged.find((c) => c.id === m.id)
      if (target) target.disposition = `merged-into: ${m.into}`
    }
  } else {
    // A null batch agent must not silently file the un-deduped set.
    log('batch-dedup returned null — filing set left un-deduped; review before Phase 3')
  }
}

// The return shape IS `scripts/file-wave.sh`'s input contract: it normalises
// `{results: [...]}` (or a bare array) and files only `disposition == "file"`
// entries, reading `id`, `draftPath`, `title`, `targetProject` from each.
// `dispositions` is the Phase 4 deliverable — the gated-out records are what
// stop a stale claim being re-filed next quarter.
return {
  results: keep.map((c) => ({
    id: c.id,
    slug: c.slug,
    disposition: 'file',
    draftPath: c.draft.path,
    title: c.draft.title,
    targetProject: c.draft.targetProject,
  })),
  merged,
  dispositions: triaged.map((c) => ({ id: c.id, slug: c.slug, disposition: c.disposition })),
}
