---
name: cold-read-gate
description: Gate outward-bound text (upstream issues, docs, PR bodies) through isolated haiku fresh-reader critique before publishing. Use when an artifact must survive a reader with zero project context.
allowed-tools: Agent, Read, Write, Edit, TodoWrite
model: opus
created: 2026-06-11
modified: 2026-07-17
reviewed: 2026-06-11
---

# Cold-Read Gate

Text written inside a long session inherits the session's context — codenames,
version baselines, internal PR numbers, "the obvious fix" — and the author can
no longer see which parts won't survive contact with a reader who has none of
it. Before publishing an outward-bound artifact, **dispatch an isolated,
cheap, context-free agent to read it cold and interrogate it**. What confuses
the cold reader is what will cost you a round-trip question (or a silent
deprioritization) from the real audience.

The reader is deliberately **haiku, isolated, and shown only the artifact**.
This is a measured exception to the "always Opus for subagents" rule: the
subagent here is not doing delegated work — it *is* the measurement
instrument. The test is "can a low-context reader act on this text alone?",
and a stronger model (or one with session context) would answer a different,
easier question. If haiku can act on it, a busy maintainer can.

## When to Use This Skill

"Outward-bound" means any audience that lacks your session context — external
maintainers *and* future teammates reading internal docs cold both qualify.

| Use this skill when... | Skip when... |
|---|---|
| Filing issues/MRs on an upstream tracker (external maintainers) | Internal scratch notes, commit messages, chat replies |
| Publishing docs a new team member will land on cold | The artifact is throwaway or has a captive expert audience |
| PR descriptions for reviewers outside the work's context | The text is one paragraph — just reread it yourself |
| Emails / announcements leaving the team | The same artifact already passed a gate and only typos changed |
| Batch-producing N artifacts (one reader per artifact, parallel) | |

## The Gate Protocol

### Step 1: Artifact on disk

The artifact must be a file. The reader gets a path, not pasted text — paste
invites the orchestrator to "helpfully" add context, which defeats the test.

### Step 2: Dispatch the cold reader — synchronously

One `Agent` per artifact, all in a single message when batching. Run each
reader **synchronously** (`run_in_background: false`, the default) — the
reader's entire job is a one-shot critique, and a synchronous run returns
that critique directly as the `Agent` tool result. There is nothing to
gain from backgrounding it.

If a reader *was* spawned with `run_in_background: true`, read its critique
from the **task-completion result** the harness returns when the task ends —
never by `SendMessage`. A completed background agent only emits
`idle_notification`s on the message channel, so asking it there for its
output loops forever without ever returning the analysis (issue #2063).

Template:

```
subagent_type: general-purpose
model: haiku
run_in_background: false
prompt: |
  You are <persona — see table>. You have NO context beyond the text itself.
  Read ONLY this file (no other files, no repository exploration, no web):
  <absolute path>

  Produce:
  1. QUESTIONS — anything unclear, ambiguous, undefined (jargon, acronyms,
     unexplained references), or missing that you'd have to ask the author
     before acting. Quote the exact phrase that confused you.
  2. HESITATIONS — claims you can't verify from the text alone, confusing
     structure, anything that would make you deprioritize it.
  3. Verdict: exactly one of `clear` | `needs-revision`.

  Ignore: <known artifacts of the test — see Step 3. Example:
  "Ignore the HTML comments at the top (they are stripped by the filing
  script before publishing) and do not ask which repository this is —
  the issue is filed on the target project's own tracker.">
  Concise bullets. Your final message is the deliverable.
```

| Audience | Persona |
|---|---|
| Upstream bug report | "an open-source maintainer triaging a newly filed issue" |
| Team documentation | "a new team member reading this doc with no project context" |
| PR description | "a reviewer seeing this change for the first time" |

### Step 3: Triage the critique — genuine gaps vs test artifacts

The cold reader cannot know the publishing context, so some complaints are
artifacts of the test, not defects. Triage before revising:

| Genuine gap — fix it | Test artifact — ignore it |
|---|---|
| Bare file paths instead of clickable links pinned to a ref | "Which repo is this?" when the artifact is filed *on* that repo's tracker |
| Unexplained acronym/jargon on first use | Complaints about metadata the publish step strips (HTML comments, frontmatter) |
| Symptom asserted without the actual error output | Demands for repro environments beyond what quoted source code shows |
| Three suggested fixes with no preference | Critique of pre-existing scope the current change didn't touch |
| Internal references (PR #s, ticket IDs) leaking into external text | Requests to restructure a document section you didn't write |
| Internal arithmetic that doesn't add up ("12 across two waves" — which 12?) | |

### Step 4: Revise once, re-read only on failure

Apply the genuine gaps with a revise pass (the orchestrator or a revise
agent). Re-dispatch a fresh cold reader **only if the first verdict was
`needs-revision`**; a `clear` verdict with minor notes means apply the
genuine ones and publish without a second opinion. Do not loop more than twice — a third round means the artifact has a
structural problem the gate can't fix.

**Fallback when the reader can't deliver.** If the critique cannot be
retrieved (reader died, harness hiccup, background-spawn confusion), do not
block publication on the gate: perform the deterministic portion inline —
scan the artifact yourself for internal references (PR/ticket numbers,
codenames), unexplained jargon, and self-containment — and publish on that
basis. The cold read is the better instrument, but a hand scan beats an
abandoned gate.

## Workflow-Script Integration

Inside a `Workflow` script the gate is one schema-enforced stage per item:

```javascript
const cold = await agent(
  `You are an upstream maintainer triaging a newly filed issue. NO context
   beyond the text. Read ONLY ${draft.path}. QUESTIONS / HESITATIONS /
   verdict. Ignore the top HTML comments (stripped before filing).`,
  { label: `coldread:${item.id}`, phase: 'ColdRead', model: 'haiku',
    schema: { type: 'object', properties: {
      verdict: { type: 'string', enum: ['clear', 'needs-revision'] },
      critique: { type: 'string' } },
      required: ['verdict', 'critique'] } },
)
if (cold?.verdict === 'needs-revision') { /* revise agent, then one re-read */ }
```

## Evidence

First production run (FVH infrastructure, 2026-06-11, 7 upstream issue
drafts + 5 docs): the gate surfaced a timeline whose headline number didn't
reconcile with its own breakdown, an undefined role name (`NOTARY`) at the
moment of its dramatic payoff, a Spring Boot issue that never named Spring
Boot, a fix section offering three options with no recommendation, and two
drafts judged "not actionable as written" that were revised before filing.
All 12 issues filed after the gate drew zero clarification round-trips.

## Common Mistakes

| Mistake | Correct approach |
|---|---|
| Using opus/sonnet as the reader "for better critique" | The weak reader is the point — it measures, not advises |
| Spawning the reader with `run_in_background: true` | Run synchronously — the critique **is** the tool result of a synchronous run |
| Polling a completed background reader via `SendMessage` | It only emits `idle_notification`s there; read the task-completion result instead (#2063) |
| Pasting the artifact into the prompt | Give a path; pasted text tempts context smuggling |
| Letting the reader explore the repo | "Read ONLY this file" — exploration restores the context the test removes |
| Acting on every complaint | Triage first (Step 3); artifacts of the test produce busywork |
| Looping until the reader is silent | One revise round; persistent confusion = structural problem |
| Gating drafts but not the docs that reference them | Anything a cold audience lands on qualifies |

## Related

- [`verify-before-plan`](../verify-before-plan/SKILL.md) — verifies premises
  before work; this skill verifies legibility after
- `workflow-orchestration-plugin:workflow-verify-before-filing` — the filing
  pipeline this gate slots into as the pre-publish stage
- [`parallel-agent-dispatch`](../parallel-agent-dispatch/SKILL.md) — batching
  N readers follows its single-message dispatch contract
