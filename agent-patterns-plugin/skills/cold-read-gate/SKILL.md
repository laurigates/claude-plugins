---
name: cold-read-gate
description: Gate outward-bound text (upstream issues, docs, PR bodies) through isolated haiku fresh-reader critique before publishing. Use when an artifact must survive a reader with zero project context.
allowed-tools: Agent, Read, Write, Edit, TodoWrite
model: opus
created: 2026-06-11
modified: 2026-10-07
compatibility: claude-code
reviewed: 2026-09-02
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
reader **synchronously** (`run_in_background: false` — set it explicitly; as
of Claude Code 2.1.232 non-teammate spawns run in the background by default)
— the reader's entire job is a one-shot critique, and a synchronous run
returns that critique directly as the `Agent` tool result. There is nothing to
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
  1. THE ASK — state in ONE sentence what this text wants you to DO. If you
     cannot state it, say so plainly: that is the most important finding.
  2. QUESTIONS — anything unclear, ambiguous, undefined (jargon, acronyms,
     unexplained references), or missing that you'd have to ask the author
     before acting. Quote the exact phrase that confused you.
  3. HESITATIONS — claims you can't verify from the text alone, confusing
     structure, anything that would make you deprioritize it.
  4. Verdict: exactly one of `clear` | `needs-revision`.

  Ignore: <known artifacts of the test — see Step 3. Plus anything the
  surrounding UI renders for the real reader — see
  references/rendered-context.md. Example:
  "Ignore the HTML comments at the top (they are stripped by the filing
  script before publishing) and do not ask which repository this is —
  the issue is filed on the target project's own tracker. The reader can
  see the merge box, the check names, the review state and both branch
  names; do not ask about those.">
  Concise bullets. Your final message is the deliverable.
```

Item 1 is load-bearing: QUESTIONS and HESITATIONS surface *local* defects, but
an artifact can be locally clear and still ask for something incoherent. A
reader that cannot state the ask has found a structural flaw the author cannot
see, because each half of the argument is individually true.

| Audience | Persona |
|---|---|
| Upstream bug report | "an open-source maintainer triaging a newly filed issue" |
| Team documentation | "a new team member reading this doc with no project context" |
| PR description | "a reviewer seeing this change for the first time" |

When the artifact is published into a surface that renders state around it (a
PR or issue comment, review thread, dashboard, chat preview), the cold reader
asks for what the page already shows. For what to put in the `Ignore:` list and
how to read a verdict there, see
[references/rendered-context.md](references/rendered-context.md).

**When one artifact serves two channels, give each reader its real audience.**
An issue-triage persona and a busy-chat-skimmer persona on the same argument
returned non-overlapping findings — coherence and exception-shopping from the
first, skimmability and cross-section consistency from the second. Two personas
cover two axes; the same persona twice covers one.

### Step 3: Triage the critique — gaps, measurements, test artifacts

The cold reader cannot know the publishing context, so some complaints are
artifacts of the test, not defects. A third class is neither: an objection the
text cannot settle but a **command** can. Triage into three buckets before
revising:

| Genuine gap — fix it | Answerable with evidence — measure it | Test artifact — ignore it |
|---|---|---|
| Bare file paths instead of clickable links pinned to a ref | "Impact is environment-specific" — a result quoted on one machine/config only | "Which repo is this?" when the artifact is filed *on* that repo's tracker |
| Unexplained acronym/jargon on first use | "I can't verify this claim" about something a single run would settle | Complaints about metadata the publish step strips (HTML comments, frontmatter) |
| Symptom asserted without the actual error output | A benchmark with no baseline, or a ratio with no absolute numbers | Demands for repro environments beyond what quoted source code shows |
| Three suggested fixes with no preference | | Critique of pre-existing scope the current change didn't touch |
| Internal references (PR #s, ticket IDs) leaking into external text | | Requests to restructure a document section you didn't write |
| Internal arithmetic that doesn't add up ("12 across two waves" — which 12?) | | |

**Test the objection before softening the sentence.** A hedge ("results may
vary") answers nothing; the measurement often *inverts* the objection. Capping
`RAYON_NUM_THREADS` at 1/2/4/8/24 to answer "the 8.7x is on 24 cores, which is
uncommon" cost one command and showed the win saturates near 4 threads — an
ordinary laptop gets nearly all of it (tracel-ai/burn#5332). Route here, not to
a rewrite, whenever a bounded run can produce the number.

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

Inside a `Workflow` script the gate is one schema-enforced stage per item: [references/workflow-script.md](references/workflow-script.md).

## Evidence and common mistakes

Production runs: [references/evidence.md](references/evidence.md). Mistakes to check before dispatching or acting on a critique: [references/common-mistakes.md](references/common-mistakes.md).

## Related

- [`verify-before-plan`](../verify-before-plan/SKILL.md) — verifies premises
  before work; this skill verifies legibility after
- `workflow-orchestration-plugin:workflow-verify-before-filing` — the filing
  pipeline this gate slots into as the pre-publish stage
- [`parallel-agent-dispatch`](../parallel-agent-dispatch/SKILL.md) — batching
  N readers follows its single-message dispatch contract
