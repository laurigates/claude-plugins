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

## Phase 3 — Paced filing script

Generated from the result JSON's `disposition: 'file'` entries; run with
Bash `run_in_background: true`.

```bash
#!/usr/bin/env bash
set -uo pipefail
export GITLAB_HOST=<instance>
DIR="$(cd "$(dirname "$0")" && pwd)"

declare -A TARGETS=(
  [<draft-file>.md]="<group/project>"
  # ... one line per gate-passing draft
)

for f in <draft files in order>; do
  repo="${TARGETS[$f]}"
  title="$(sed -n 's/^# //p;/^# /q' "$DIR/$f" | head -1)"   # first heading
  body="$(sed '1d' "$DIR/$f" | grep -v '^<!--')"            # strip title + HTML comments
  echo "==> $f -> $repo"
  ok=""
  for attempt in 1 2 3 4; do
    if url="$(glab issue create -R "$repo" -t "$title" -d "$body" -y 2>&1 | tail -1)" \
       && [[ "$url" == https://* ]]; then
      echo "    filed: $url"; echo "$f -> $url" >> "$DIR/filed-urls.txt"; ok=1; break
    fi
    echo "    attempt $attempt failed, backing off 130s: $url"; sleep 130
  done
  [ -z "$ok" ] && echo "$f -> FAILED" >> "$DIR/filed-urls.txt"   # continue, don't abort
  sleep 70
done
```

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
