---
name: session-end
description: End-of-session orchestrator. Runs reversible wrap/distill/taskwarrior work at once, asks once for outward filings. Use when winding down a session.
allowed-tools: Bash(bash *), Bash(task *), Bash(git *), Bash(gh *), Read, Skill, AskUserQuestion, TodoWrite
created: 2026-06-10
modified: 2026-11-02
reviewed: 2026-06-24
---

# session-end

One survey, then the reversible work runs immediately and the
outward-facing work waits for **one** question at the end — so a user who
starts `/session-end` and walks away comes back to finished work and at
most one question. This is the orchestrator
over the five end-of-session passes, which otherwise compete for the wind-down
moment (design decisions D3/D4, `docs/archive/session-plugin-workflow.md`).

The five passes — Wrap, Distill, Feedback, Taskwarrior sync, Blueprint
tracker-sync — and what each captures are listed in
[references/passes.md](references/passes.md).

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| User winds down ("wrap up", "done for today") and more than one pass may apply | Only loose threads to capture → `session-plugin:session-wrap` directly |
| The Stop-hook nudge offered this skill and the user confirmed | Only learnings to codify → `session-plugin:session-distill` directly |
| User invokes `/session-end` | Mid-session single-task close → `taskwarrior-plugin:task-done` |

## Execution

Execute this orchestration. **Not fully automatic by design**: filing
GitHub issues, opening cross-repo PRs and writing a journal are not
`git restore`-able, so those wait for the Step 4 question. Everything that
can be undone runs first, without asking.

### Step 1: Survey once

One shared decision pass — do not let each sub-skill re-survey. Run the
shared collector (the same one the wrap/spinup skills and the nudge hook
use); it emits detection, git state, PRs, taskwarrior tasks **with stable
UUIDs**, and recent commits in one parallel-safe pass. Its `TASKWARRIOR`
section carries scoping keys (`TASK_SCOPE`, `PROJECT_CONFIDENCE`,
`PROJECT_AMBIGUOUS`, `PROJECT_PREFIX_SIBLINGS`, `PROJECT_EXACT_TASKS`) that say
whether a task count can be trusted — their meanings are in
[references/survey-digest.md](references/survey-digest.md).

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-blueprint --with-dedup
```

Pass `--project <name>` to override the detected project. Hand the digest
to the passes in Steps 3–4 so they don't re-survey. `--with-dedup`
is what populates the `GITHUB_DRIFT` section that Step 3's taskwarrior-sync
redundancy test reads — without it the section is always empty and the
guard silently runs against nothing. That section also carries `GH_READY`:
`false` means it is present but **unqueried**, the same "not clean, just
not asked" signal as `PROJECT_CONFIDENCE=low` above — don't treat an empty
`GITHUB_DRIFT` under `GH_READY=false` as evidence there's nothing to dedup
against. Plus the conversation: what finished, what's hanging, what was
learned, what plugin/skill friction or wins occurred.

**Remediating `GH_READY=false`.** Act on its `GH_FAIL_REASON=` — the
per-reason table, and which reasons must never be re-run, are in
[REFERENCE.md](REFERENCE.md).

For the **Distill** qualify gate (Step 2), also run the distill collector's
coarse summary — the mechanical half of the Distill signal (recipe candidates,
hot files, process groupings). It degrades to `TRANSCRIPT_AVAILABLE=false` when
no transcript is reachable, so treat a SKIP as "no mechanical signal, judge
conceptually only":

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/distill-survey.sh" --session-id "${CLAUDE_SESSION_ID}" --summary
```

### Step 2: Qualify each pass and sort its items into two lanes

Apply each skill's own signal filter strictly; **silently skip passes
that don't qualify** — offering an empty pass is the drown-in-signals
failure mode.

| Pass | Qualifies when |
|---|---|
| Wrap | ≥1 genuine loose thread per session-wrap's LOG IT filter |
| Distill | A durable, generalizable learning emerged AND the repo has a distillable surface (`.claude/rules/` or a justfile). Corroborate the mechanical half with the distill collector's `--summary` (Step 1): `RECIPE_CANDIDATE_COUNT` / `HOT_FILE_COUNT` / `PROCESS_SIGNAL` > 0 means recipes/hot-files/process are worth a pass even if no conceptual rule emerged |
| Feedback | A plugin/skill behaved notably well or badly — bug, enhancement, or positive worth filing |
| Taskwarrior sync | `TASK_AVAILABLE=true`, `TASK_STORE_REACHABLE=true`, AND ≥1 **session-linked task**: one this session worked on, created, or made closeable (its `TASK_n_GHID` PR/issue merged or closed, or the conversation shows it done). Open tasks the session never touched — the project backlog, `RECENT_TASK_*` rows from other projects — never qualify the pass; see [Backlog is reported, never walked](#backlog-is-reported-never-walked) |
| Blueprint tracker-sync | `UNDRAINED_COUNT` ≥ 1 in the Step 1 digest's `BLUEPRINT` section. Non-blueprint / tracker-missing repos auto-disqualify (count is 0) → silent skip. If `blueprint-plugin` isn't installed, note it and skip (as with Feedback) |

**Taskwarrior scope keys.** When `TASK_AVAILABLE=true` and `TASK_STORE_REACHABLE=false`, the
store was never read — **unqueried**, exactly like `GH_READY=false`, never an
empty queue: state `taskwarrior: not queried (<TASK_FAIL_REASON>)` in the
Step 5 report, quoting `TASK_FAIL_DETAIL` (remedies per reason:
[references/survey-digest.md](references/survey-digest.md)). With
`TASK_AVAILABLE=false` (`TASK_FAIL_REASON=no-cli`) skip silently. Before
adding a task, confirm the slug: when `PROJECT_CONFIDENCE=low`,
`PROJECT_AMBIGUOUS` is set (it fires even at `high`), or
`PROJECT_PREFIX_SIBLINGS` is present, a new task could land in a sibling
project nobody reads — move that add to the Ask lane and name the slugs
(`0 here, N under <slug>`).

**Sort every qualifying item into one of two lanes.** The lane decides
whether it runs now or waits for the one question in Step 4:

| Lane | Items | Why |
|---|---|---|
| **Act** — run in Step 3, no question | Taskwarrior annotate / modify / add on session-linked tasks; close a task **with evidence** (merged PR, closed issue, commit on the default branch); Wrap's taskwarrior writes; Distill `[UPDATE]` / `[NEW]` edits in the current repo; Blueprint tracker-sync drain | Undoable: `task undo` or `task <uuid> modify status:pending`, and `git restore` for repo files |
| **Ask** — confirmed once in Step 4 | Feedback issues; Wrap's GitHub follow-up issues, journal writes and upstream candidates; Distill `[PROMOTE]` PRs and `[REDUNDANT]` removals; a task add whose project slug is in doubt; closing a task without evidence | Outward-facing, destructive, or a guess — not `git restore`-able |

A task close without evidence is a guess, so it goes in the Ask lane or
becomes an annotation.

**Blueprint auto-drain (ADR-0020 level 1):** the Blueprint drain sits in the Act
lane only when the qualifying repo's `docs/blueprint/manifest.json` enables and
opts the feature-tracker-sync task into auto-running at autonomy level ≥ 1;
otherwise it goes in the Ask lane. The gate requires all three fields (issue
#2358) — run it as written, `auto` ⇒ Act lane, anything else ⇒ Ask lane:

```sh
jq -r 'if ((.automation.autonomy_level // 0) >= 1) and (.task_registry["feature-tracker-sync"].enabled == true) and (.task_registry["feature-tracker-sync"].auto_run == true) then "auto" else "ask" end' docs/blueprint/manifest.json 2>/dev/null
```

For why all three are required and the safe default for a missing `enabled`
key, see [REFERENCE.md](REFERENCE.md).

If **nothing** qualifies, say so in one line and end — no question.

#### Backlog is reported, never walked

Do not offer to walk open tasks the session did not touch, one by one or
in bulk. In 62 recorded runs that offer was declined 20 of 29 times, and
when it was accepted the usual per-task answer was "leave". Put one line
in the Step 5 report instead —
`taskwarrior: N other open tasks under project:<slug> untouched — /taskwarrior:task-status to review` —
and stop there.

### Step 3: Run the Act lane now

Run the Act-lane work immediately, before asking anything. It needs the
warm prompt cache and the full conversation: Distill reads the session's
reasoning, and a session left idle for about an hour can be compacted into
a summary. Run in this order, each via the Skill tool, or — where there is
no Skill tool — read that skill's SKILL.md and follow it (inline for
taskwarrior sync), passing the Step 1 survey so it doesn't re-survey:

1. **Taskwarrior sync** — inline, before Wrap, so Wrap sees the updated
   queue. Address tasks by stable UUID (`task +LATEST uuids` after
   creation; `task <uuid> done` / `task <uuid> modify` for existing ones);
   never use volatile numeric IDs. Annotate before closing. Any follow-up
   obeys Wrap's redundancy test: an open PR or assigned issue in the Step 1
   digest's `PRS` / `GITHUB_DRIFT` sections is already its own tracker —
   annotate, never mirror it into a task.
2. `session-plugin:session-wrap` with `--orchestrated` — Wrap applies its
   taskwarrior items without its own preview/confirm, and returns its
   journal, GitHub-issue and upstream items as `DEFERRED:` lines instead of
   asking.
3. **Blueprint tracker-sync** (Act lane only) — after passes 1–2, because
   both mutate the queue. Re-derive the wave inline right before delegating
   (never reuse the survey's `UNDRAINED_WOS` as the drain list); the
   command is in [references/blueprint-drain.md](references/blueprint-drain.md).
   Then invoke `/blueprint:blueprint-feature-tracker-sync --drain-wave <list>`
   with **no** evidence flags — the sync skill sources evidence from
   taskwarrior annotations itself (its priority order: files → inline →
   annotation → ask). If the re-derived list is empty, report "already
   drained". If `blueprint-plugin` isn't installed, note it and skip.
4. `session-plugin:session-distill` with `--orchestrated` — applies
   `[UPDATE]` / `[NEW]` in the current repo and returns `[PROMOTE]` and
   `[REDUNDANT]` proposals as `DEFERRED:` lines.

Feedback has no Act-lane work; its findings were collected in Step 1 and go
straight to Step 4.

### Step 4: One question for the Ask lane

Gather the Ask-lane items: Feedback findings, every `DEFERRED:` line from
Step 3, a Blueprint drain that did not pass the auto gate, and any
low-confidence task add. If there are none, skip to Step 5 — no question.

Otherwise print a short receipt of what Step 3 already did (so the user can
undo it), then ask **one AskUserQuestion** call: up to 4 questions grouped
by destination (feedback issues, other GitHub filings, `[PROMOTE]` PRs,
journal / removals), each `multiSelect`, each option one concrete item. The
user picks any subset; "Other" covers adjustments. Never ask a second
round — the sub-skills already received their decisions.

Then run the approved items:

- **Feedback** — `feedback-plugin:feedback-session --confirmed "<approved findings>"`.
  `--confirmed` satisfies its own review step for exactly that set; it
  re-asks only if dedup changes the set. If the feedback plugin isn't
  installed, note it and skip.
- **Wrap upstream candidates** — a *File now* candidate always routes
  through `workflow-orchestration-plugin:workflow-verify-before-filing` →
  `agent-patterns-plugin:cold-read-gate` → file; never blind. *Track for
  later* is a `+upstream` taskwarrior task.
- **Distill `[PROMOTE]`** — the throwaway-clone PR hand-off in session-distill.
- **Everything else** — apply as described by its owning skill.

Never end the turn on a freeform "y/n" text question — ending the turn
fires Stop hooks mid-confirmation (the race that motivated this
orchestrator). AskUserQuestion keeps the turn open. Where `AskUserQuestion`
is unavailable (a harness without the tool), ask in plain text and end the
turn.

### Step 5: Report

One short block: what each pass wrote (tasks touched / closed with UUIDs,
files edited, issues and PRs filed), which passes were skipped as not
qualifying, the backlog line, and any `not queried` line.

## Seam: distill vs feedback

"Discovered a better flag / a skill suggested something subtly wrong" →
**feedback** (issue on claude-plugins). "Found a reusable project
pattern, rule, or recipe" → **distill** (artifact in this repo). When
both apply, both run — they write to different places.

## Auto-surfacing

How the Stop-hook nudge offers this skill (and how to pre-silence it) is in
[references/auto-surfacing.md](references/auto-surfacing.md).

## Agentic Optimizations

Command forms for the survey, the scope/confidence keys (`TASK_SCOPE`,
`GIT_CONFIDENCE`), the distill signal, the drain wave, and UUID-safe task edits
are in [references/commands.md](references/commands.md).

For the `GH_FAIL_REASON` remediation table and the Blueprint auto-drain gate
details, see [REFERENCE.md](REFERENCE.md).
