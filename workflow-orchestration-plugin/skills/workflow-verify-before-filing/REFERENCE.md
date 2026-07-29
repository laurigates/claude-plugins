# workflow-verify-before-filing — Worked Example

Complete operational scaffolding from the run that motivated the skill
(FVH → SIMPL-Open on a GitLab instance, 2026-06-11: 17 candidates → 5 filed,
12 dispositioned). Adapt names/hosts; the shapes are the deliverable.

## Data flow

```
wave2-candidates.json ──► Workflow script (per candidate):
                            parallel[ verify-agent, search-agent ]
                            └─ gate ─► draft-agent ─► coldread(haiku) ─► revise
                          ◄── result JSON: {id, disposition, draftPath, ...}
result JSON ──► file-wave.sh (paced) ──► filed-urls.txt
filed-urls.txt + dispositions ──► source-doc annotations, tracking-issue
                                  comment, follow-up tasks
```

## Phase 1+2 — Workflow script skeleton

Run with the `Workflow` tool. Candidates embedded or parsed from args
(`const CANDIDATES = (typeof args === 'string') ? JSON.parse(args) : args` —
args can arrive stringified).

```javascript
export const meta = {
  name: 'verify-before-filing',
  description: 'Verify candidates at upstream HEAD, dedup, draft + cold-read gate',
  phases: [
    { title: 'Verify' }, { title: 'Search' }, { title: 'Draft' },
    { title: 'ColdRead', model: 'haiku' }, { title: 'Revise' },
  ],
}

const DIR = '/abs/path/to/drafts'

const GLAB = `Tooling (READ-ONLY — GET requests only, never create/edit/comment upstream):
- GITLAB_HOST=<instance> glab api "projects/<id-or-urlencoded-path>" (.default_branch)
- ... "projects/<id>/repository/files/<URL-ENCODED-PATH>/raw?ref=<ref>" (slashes as %2F)
- ... "projects/<id>/repository/tags?per_page=20"
- ... "groups/<urlencoded-group>/search?scope=issues&search=<term>"
- ... "projects/<id>/packages?per_page=100&sort=desc" (chart/package versions)
Known project IDs: <paste your map>. When a candidate says "locate project",
resolve via groups/<g>/projects?include_subgroups=true&search=<name>.`

const VERIFY_SCHEMA = { type: 'object', properties: {
  verdict: { type: 'string', enum: ['still-present', 'partially-fixed',
    'fixed-upstream', 'obsolete-version', 'claim-invalid', 'could-not-verify'] },
  targetProject: { type: 'string' },
  evidence: { type: 'string', description: 'quoted current content with paths + refs' },
  checkedRefs: { type: 'string' }, notes: { type: 'string' } },
  required: ['verdict', 'targetProject', 'evidence', 'checkedRefs', 'notes'] }

const SEARCH_SCHEMA = { type: 'object', properties: {
  duplicateFound: { type: 'string', enum: ['yes', 'possibly', 'no'] },
  hits: { type: 'array', items: { type: 'object', properties: {
    url: { type: 'string' }, title: { type: 'string' },
    state: { type: 'string' }, relevance: { type: 'string' } },
    required: ['url', 'title', 'state', 'relevance'] } },
  wave1Overlap: { type: 'string', description: 'overlap with OUR prior reports incl. by-catches, or "none"' },
  searchedTerms: { type: 'string' } },
  required: ['duplicateFound', 'hits', 'wave1Overlap', 'searchedTerms'] }

const PRIOR = `Our prior filed reports (fetch bodies via glab api
"projects/<id>/issues/<iid>" and check overlap INCLUDING by-catch findings):
- <project> issues <iids> (<one-line topic each>)`

const results = await pipeline(CANDIDATES, async (item) => {
  const [verify, search] = await parallel([
    () => agent(
      `You verify a candidate upstream bug. ${GLAB}\n\nBaseline: observed at
"${item.observed_version}". Is the flaw STILL PRESENT at default-branch HEAD
and the latest tag? Quote exact current content. Superseded line =>
obsolete-version. Claim wrong on inspection => claim-invalid.\n\n## ${item.id}
(${item.slug})\nTargets: ${item.targets.join(' ; ')}\n\n${item.claim}\n\nRaw
data for a machine.`,
      { label: `verify:${item.id}`, phase: 'Verify', schema: VERIFY_SCHEMA }),
    () => agent(
      `You check whether a bug was ALREADY reported. ${GLAB}\n\n${PRIOR}\n\n
Search target project(s) + group-wide (issues+MRs, state=all, several
phrasings incl. exact error strings), then judge overlap with our prior
reports.\n\n## ${item.id}\nBug: ${item.claim}\n\nRaw data for a machine.`,
      { label: `search:${item.id}`, phase: 'Search', schema: SEARCH_SCHEMA }),
  ])
  if (!verify || !search) return { id: item.id, disposition: 'agent-error' }

  // Gate precedence: duplicate kills regardless of verdict; could-not-verify never files.
  const passes = ['still-present', 'partially-fixed'].includes(verify.verdict)
    && search.duplicateFound === 'no'
  if (!passes) {
    const why = search.duplicateFound !== 'no'
      ? `duplicate: ${search.wave1Overlap}` : verify.verdict
    log(`${item.id} gated out: ${why}`)
    return { id: item.id, slug: item.slug, disposition: why, verify, search }
  }

  const draft = await agent(
    `Draft an upstream issue per the house template (read 1-2 prior examples
in ${DIR}). Target: ${verify.targetProject}. Claim: ${item.claim}\nVerified
evidence (pin blob links to these refs):\n${verify.evidence}\nChecked:
${verify.checkedRefs}\nNotes: ${verify.notes}\nMine real error output from
PRs ${JSON.stringify(item.evidence_prs)} via gh pr view <n> --json body.
Write to ${DIR}/${item.id}-${item.slug}.md.`,
    { label: `draft:${item.id}`, phase: 'Draft',
      schema: { type: 'object', properties: { path: { type: 'string' },
        title: { type: 'string' }, targetProject: { type: 'string' } },
        required: ['path', 'title', 'targetProject'] } })
  if (!draft) return { id: item.id, disposition: 'draft-failed', verify, search }

  // Cold-read gate (see agent-patterns-plugin:cold-read-gate)
  let cold = await agent(
    `You are an upstream maintainer triaging a newly filed issue. NO context
beyond the text. Read ONLY ${draft.path}. QUESTIONS / HESITATIONS / verdict.
Ignore the top HTML comments (stripped before filing); the issue is filed on
the target project's own tracker.`,
    { label: `coldread:${item.id}`, phase: 'ColdRead', model: 'haiku',
      schema: { type: 'object', properties: {
        verdict: { type: 'string', enum: ['clear', 'needs-revision'] },
        critique: { type: 'string' } }, required: ['verdict', 'critique'] } })
  if (cold?.verdict === 'needs-revision') {
    await agent(
      `Revise ${draft.path} in place per this critique. Apply only GENUINE
gaps (links, jargon, evidence, single-fix); ignore test artifacts (HTML
comments, implicit repo).\n\n${cold.critique}`,
      { label: `revise:${item.id}`, phase: 'Revise',
        schema: { type: 'object', properties: { summaryOfChanges:
          { type: 'string' } }, required: ['summaryOfChanges'] } })
    cold = await agent(/* one re-read, same coldread prompt */)
  }
  return { id: item.id, slug: item.slug, disposition: 'file',
    draftPath: draft.path, title: draft.title,
    targetProject: draft.targetProject, verify, search }
})
return results.filter(Boolean)
```

## Phase 3 — Paced filing: why the numbers are what they are

The loop itself is **not** here. It lives in
[`scripts/file-wave.sh`](scripts/file-wave.sh) and the skill invokes it — Phase 3
is purely mechanical, so retyping it out of this file each run would re-derive it
slightly differently every time
(`.claude/rules/offload-to-deterministic-substrate.md`). What stays here is the
*rationale*, which is the part a future run actually has to re-decide.

| Default | Value | Why |
|---|---|---|
| `--pace-seconds` | 70 | Observed: a GitLab instance returned **429 after a single create**. 70 s cleared it with margin. Treat as a starting point, not a spec — raise it if a wave still 429s. |
| `--backoff-seconds` | 130 | Roughly 2× the pace: a 429 means the window is already exhausted, so a retry needs more than the steady-state gap. |
| `--max-attempts` | 4 | Attempts *including* the first (so 3 retries). Beyond this a create is failing for a reason pacing won't fix — bad project path, revoked token — and burning 130 s per attempt buys nothing. |

Three behaviours are load-bearing and non-obvious, so they are pinned by
[`scripts/tests/test-file-wave.sh`](scripts/tests/test-file-wave.sh):

- **A failure never aborts the batch.** The run continues to the next draft and
  reports every failure at the end. A half-filed wave with no record is the worst
  outcome — you cannot tell which issues exist.
- **Every outcome is appended to `filed-urls.txt`**, success (`draft -> URL`) and
  failure (`draft -> FAILED`) alike. That manifest is what Phase 4 dispositions
  and the cross-link pass read.
- **Pacing sits *between* writes**, not after each one, so a wave never pays a
  trailing wait it cannot use.

Invocation and the forge dispatch (`gh` vs `glab`) are documented in the script's
own header — run `bash scripts/file-wave.sh --help`. Use `--dry-run` to see the
resolved title/target for every draft without creating anything.

Created GitLab issues may surface as `/-/work_items/<n>` URLs; the issues API
addresses them by the same iid (`projects/<id>/issues/<iid>`). Cross-link
related issues afterwards via
`glab api -X POST "projects/<id>/issues/<iid>/notes" -f body="..."` (paced).

## Phase 4 — Bookkeeping targets

Generic shapes; adapt to the project's systems:

- **Source docs**: append the disposition to each originating claim
  (filed URL / "fixed upstream in vX" / "claim invalid: <what was true>"),
  in the same repo, via a normal docs PR.
- **Tracking issue**: post the disposition table as a comment on whatever
  issue tracks "file these upstream"; close it when nothing known remains.
- **Follow-up tasks**: fixed-upstream discoveries become tasks in the
  project's task system (taskwarrior, GitHub issues, …): retire the fork,
  advance the pin, delete the workaround.

## Observed gotchas

- `Workflow` args may arrive as a JSON **string** — parse defensively.
- Verify agents must check both HEAD **and** the latest tag: HEAD-only
  misses "fixed on main, broken in every release" and vice versa.
- The search agent must fetch your prior reports' **full bodies** — by-catch
  findings buried inside them are the duplicates you'll miss otherwise.
- Expect framing corrections from verification (the bug is real but your
  mechanism was wrong) — let the draft cite the *corrected* mechanism.
