/**
 * issue-triage.workflow.js — a read-only verdict per open issue, across one or
 * more repositories, for the backlog sweep in `git-plugin:git-triage`.
 *
 * TEMPLATE, not a script to run verbatim. See the `## Workflow harness
 * (template)` section of the sibling SKILL.md for what may be rewritten and
 * what must survive any adaptation.
 *
 * Shape: one fan-out, no barrier.
 *   Fan-out unit  — one read-only agent per issue. It reads the whole thread,
 *                   looks for an open PR, re-verifies the cited evidence at the
 *                   base ref in a local clone, and returns one verdict.
 *   Loop bound    — `args.issues`, the caller's list, cut by
 *                   `ISSUES.slice(0, MAX_ISSUES)` in the fan-out after an
 *                   explicit over-cap abort. It never truncates silently.
 *   Barrier       — none. Each verdict depends only on its own issue, so the
 *                   caller (or a human) groups them afterwards using
 *                   `group_with`. A stage that needs every verdict at once, such
 *                   as slicing into implementation units, is
 *                   `git-plugin:git-issue`'s issue-triage template.
 *
 * Landing: none. No agent edits a file, comments, labels, closes, pushes or
 * creates anything. The rows return to the caller, who decides what to close,
 * what to ask the user, and what to hand to an implementer.
 *
 * args: {
 *   repos:  [{ repo: 'owner/name', root: '/absolute/clone/path', alias?: 'short' }],
 *   issues: [{ repo, number }] | ['owner/name#12', 'short#34'] | 'owner/name#12 short#34',
 *   base?:    'origin/main',                       // ref the evidence is re-verified at
 *   classes?: { <verdict>: '<what it means here>' }, // replaces a verdict's definition
 *   limits?:  '<what an agent in this environment can and cannot do>',
 * }
 * Every issue's repository needs a `repos` entry with a clone: the agent reads
 * files at the base ref from that clone. A missing clone is an explicit abort.
 *
 * Returns { triaged, missing }. `missing` lists every input issue that has no
 * verdict (its agent died or returned nothing), as 'owner/name#N'.
 */

export const meta = {
  name: 'issue-triage-sweep',
  description:
    'Give each caller-listed issue, across one or more repositories, a read-only verdict: actionable, needs_decision, blocked_on_event, or close_candidate, with evidence.',
  phases: [{ title: 'Triage', detail: 'one read-only agent per issue' }],
}

// `args` may arrive stringified JSON, or as a bare list of issue references.
const RAW = typeof args === 'string' && !args.trim().startsWith('{') ? { issues: args } : args
const INPUT = typeof RAW === 'string' ? JSON.parse(RAW) : (RAW ?? {})
const BASE = INPUT.base ?? 'origin/main'

// ADAPT the numbers, PRESERVE the shape. One issue is a linear read, not a fan-out.
const FLOOR = 2
// Every agent is read-only, but each one is an opus run. Above the cap, split the
// list into several runs, or raise the cap AND the literal in the fan-out together.
const MAX_ISSUES = 40

// ---------------------------------------------------------------------------
// Verdicts — ADAPT the definitions, PRESERVE the closed set. The schema fields
// question_for_user, waiting_on and scope belong to needs_decision,
// blocked_on_event and actionable; renaming a verdict means renaming its field.
// ---------------------------------------------------------------------------

const CLASSES = {
  actionable:
    'an agent in this environment could implement it now, with no decision from the user and no outside event. Choose it only when the scope is concrete enough to write an acceptance check.',
  needs_decision:
    "a design, scope or policy choice that is the user's to make: the issue asks a question, offers options the thread never settled, or needs taste. Write the exact question.",
  blocked_on_event:
    'it waits on something outside this environment: a secret being set, a live run, a release, a manual task on a machine the agent cannot reach, or another open issue or PR. Name it.',
  close_candidate: `already fixed or obsolete at ${BASE}. Cite the commit, file or PR that shows it.`,
}
const CLASSES_BAD = INPUT.classes != null && (Array.isArray(INPUT.classes) || typeof INPUT.classes !== 'object')
const unknownClasses = CLASSES_BAD ? [] : Object.keys(INPUT.classes ?? {}).filter((k) => !(k in CLASSES))
if (!CLASSES_BAD) for (const [k, v] of Object.entries(INPUT.classes ?? {})) if (k in CLASSES) CLASSES[k] = String(v)
const VERDICTS = Object.keys(CLASSES)

// ADAPT: what an agent can do where this runs. The default is deliberately
// generic; replace it with the real limits (API endpoints that fail, machines
// the agent cannot reach, repositories it may push to).
const LIMITS =
  INPUT.limits ??
  'An agent in this environment can read and edit files, run the repositories\' tests, and push branches and open PRs in the repositories listed in this run. It cannot reach the user\'s own machines, set secrets, or act in any other repository.'

// ---------------------------------------------------------------------------
// Inputs — repositories and issues both come from args; nothing is hardcoded.
// ---------------------------------------------------------------------------

const REPOS = new Map()
const ALIASES = new Map()
for (const r of Array.isArray(INPUT.repos) ? INPUT.repos : []) {
  if (!r?.repo) continue
  REPOS.set(String(r.repo), { repo: String(r.repo), root: r.root ? String(r.root) : '' })
  if (r.alias) ALIASES.set(String(r.alias), String(r.repo))
}

const rawIssues = typeof INPUT.issues === 'string' ? INPUT.issues.split(/[\s,]+/).filter(Boolean) : (INPUT.issues ?? [])
const unparsed = []
const seen = new Set()
const ISSUES = []
for (const x of rawIssues) {
  let repo
  let number
  if (typeof x === 'string') {
    const m = x.match(/^([^#\s]+)#(\d+)$/)
    if (m) [repo, number] = [ALIASES.get(m[1]) ?? m[1], Number(m[2])]
  } else if (x && typeof x === 'object') {
    ;[repo, number] = [ALIASES.get(String(x.repo)) ?? String(x.repo ?? ''), Number(x.number)]
  }
  if (!repo || !repo.includes('/') || !Number.isInteger(number) || number < 1) {
    unparsed.push(typeof x === 'string' ? x : JSON.stringify(x))
    continue
  }
  const ref = `${repo}#${number}`
  if (seen.has(ref)) continue
  seen.add(ref)
  ISSUES.push({ repo, number, ref })
}

// ---------------------------------------------------------------------------
// Schema — PRESERVE the closed verdict enum and the required list. Every field
// is required so a verdict cannot arrive without its evidence; fields that do
// not apply to the chosen verdict are "".
// ---------------------------------------------------------------------------

const SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['repo', 'number', 'title', 'verdict', 'reason', 'question_for_user', 'waiting_on', 'open_pr', 'scope', 'size', 'group_with'],
  properties: {
    repo: { type: 'string' },
    number: { type: 'integer' },
    title: { type: 'string' },
    verdict: { type: 'string', enum: VERDICTS },
    reason: { type: 'string', description: 'one or two sentences citing what you read: a comment, a file at the base ref, a PR state' },
    question_for_user: { type: 'string', description: 'needs_decision only: the exact decision, answerable in one line; else ""' },
    waiting_on: { type: 'string', description: 'blocked_on_event only: the concrete event; else ""' },
    open_pr: { type: 'string', description: 'an open PR already addressing it, or ""' },
    scope: { type: 'string', description: 'actionable only: files or areas to change and the acceptance check; else ""' },
    size: { type: 'string', enum: ['small', 'medium', 'large', 'n/a'] },
    group_with: { type: 'string', description: 'other issues in this run to implement together, as owner/name#N, or ""' },
  },
}

// ---------------------------------------------------------------------------
// Prompt — ADAPT the reading commands and context. Keep the read-only clause,
// the read-from-the-ref clause, the never-switch-branches clause, and the
// whole-thread clause.
// ---------------------------------------------------------------------------

const others = (it) => ISSUES.filter((o) => o !== it).map((o) => o.ref)
const PROMPT = (it) => {
  const root = REPOS.get(it.repo).root
  return `Triage GitHub issue ${it.ref}. READ-ONLY: do not edit files, comment, label, close, push, or create anything.

How to read:
- Read the issue AND every comment (gh issue view ${it.number} -R ${it.repo} --comments, or the GitHub MCP issue_read tool with methods get and get_comments). Read the whole thread: a later comment often narrows, reverses or settles the scope (git-plugin:git-issue-scoping).
- Look for an open PR addressing it: gh pr list -R ${it.repo} --state open --search "${it.number}" --json number,title,headRefName, and check titles, bodies and branch names for the issue number.
- Re-verify cited evidence at ${BASE} in the local clone ${root}: git -C ${root} fetch -q origin, then git -C ${root} show ${BASE}:<path> or git -C ${root} grep <pattern> ${BASE}. Never check out or switch branches in that clone; other sessions use it.

Environment: ${LIMITS}

Classify as exactly one of:
${VERDICTS.map((k) => `- ${k}: ${CLASSES[k]}`).join('\n')}

Other issues in this run (for group_with): ${others(it).slice(0, 60).join(' ') || 'none'}
Cite evidence; do not guess. Keep every field short, and return "" for fields that do not apply to your verdict.
If the schema rejects your answer, shorten or restructure it; an identical retry fails the same way.`
}

// ---------------------------------------------------------------------------
// Guards — each an explicit, named abort before any agent runs.
// ---------------------------------------------------------------------------

if (CLASSES_BAD) {
  log(`args.classes must be an object { <verdict>: '<definition>' } keyed by ${VERDICTS.join('|')}; abort`)
  return { abort: true, reason: 'bad-classes' }
}
if (unknownClasses.length) {
  log(`args.classes names verdicts outside the closed set (${unknownClasses.join(', ')}); edit the template to add a verdict; abort`)
  return { abort: true, reason: 'unknown-classes', classes: unknownClasses }
}
if (unparsed.length) {
  log(`unparseable issue references: ${unparsed.join(' ')} — use owner/name#N, alias#N, or { repo, number }; abort`)
  return { abort: true, reason: 'bad-issues', issues: unparsed }
}
const noClone = [...new Set(ISSUES.filter((it) => !REPOS.get(it.repo)?.root).map((it) => it.repo))]
if (noClone.length) {
  log(`no clone path in args.repos for: ${noClone.join(', ')} — evidence is read from a local clone; abort`)
  return { abort: true, reason: 'no-clone', repos: noClone }
}
if (ISSUES.length < FLOOR) {
  log(`${ISSUES.length} issue(s) (< ${FLOOR}) — triage it in the main session; abort`)
  return { abort: true, reason: 'below-floor', issues: ISSUES.map((it) => it.ref) }
}
if (ISSUES.length > MAX_ISSUES) {
  log(`${ISSUES.length} issues (> ${MAX_ISSUES}) — split into several runs; abort without truncating`)
  return { abort: true, reason: 'over-cap', issues: ISSUES.length, cap: MAX_ISSUES }
}

// ---------------------------------------------------------------------------
// Triage — fan out, one read-only agent per issue.
// ---------------------------------------------------------------------------

phase('Triage')
log(`${ISSUES.length} issues across ${new Set(ISSUES.map((it) => it.repo)).size} repositories`)

// PRESERVE the literal bound in the fan-out: the scale guard counts it.
const results = await parallel(
  ISSUES.slice(0, 40).map((it) => () =>
    agent(PROMPT(it), { label: `triage:${it.ref}`, phase: 'Triage', schema: SCHEMA, model: 'opus', effort: 'medium' }),
  ),
)

// PRESERVE: a row is keyed by its input issue, never by what the agent echoed
// back, and a null result is `missing`, never a verdict.
const triaged = []
const missing = []
ISSUES.forEach((it, i) => {
  const r = results[i]
  if (!r || !VERDICTS.includes(r.verdict)) return missing.push(it.ref)
  if (r.repo !== it.repo || Number(r.number) !== it.number) log(`triage:${it.ref} echoed ${r.repo}#${r.number}; kept under ${it.ref}`)
  triaged.push({ ...r, repo: it.repo, number: it.number })
})

const counts = Object.fromEntries(VERDICTS.map((k) => [k, triaged.filter((r) => r.verdict === k).length]))
log(`${triaged.length}/${ISSUES.length} triaged: ${VERDICTS.map((k) => `${k} ${counts[k]}`).join(', ')}`)
if (missing.length) log(`not triaged: ${missing.join(' ')}`)
return { triaged, missing }
