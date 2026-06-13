---
name: session-end
description: End-of-session orchestrator. Previews which of wrap/distill/feedback/taskwarrior-sync qualify, single confirm, then sequence. Use when winding down a session.
allowed-tools: Bash(task *), Bash(git *), Bash(gh *), Read, Skill, AskUserQuestion, TodoWrite
created: 2026-06-10
modified: 2026-06-13
reviewed: 2026-06-13
---

# session-end

One survey, one preview, one confirmation — then run only the
end-of-session passes that actually qualify. This is the orchestrator
over three capture skills that used to compete for the wind-down moment
(design decisions D3/D4, `docs/session-plugin-workflow.md`):

| Pass | Skill | Captures |
|---|---|---|
| Wrap | `session-plugin:session-wrap` | Loose threads → taskwarrior, optional journal, GitHub issues |
| Distill | `session-plugin:session-distill` | Durable learnings → rules, skill updates, justfile recipes |
| Feedback | `feedback-plugin:feedback-session` | Notable plugin/skill interactions → GitHub issues on claude-plugins |
| Taskwarrior sync | (inline, no sub-skill) | Close done tasks, update statuses, add follow-ups; uses stable UUIDs |

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| User winds down ("wrap up", "done for today") and more than one pass may apply | Only loose threads to capture → `session-plugin:session-wrap` directly |
| The Stop-hook nudge offered this skill and the user confirmed | Only learnings to codify → `session-plugin:session-distill` directly |
| User invokes `/session-end` | Mid-session single-task close → `taskwarrior-plugin:task-done` |

## Execution

Execute this orchestration. **Not fully automatic by design**: filing
GitHub issues and writing a journal are not `git restore`-able, so the
single confirmation gate below is mandatory.

### Step 1: Survey once

One shared decision pass — do not let each sub-skill re-survey:

```sh
git log --oneline -20
git status --porcelain
gh pr list --head "$(git branch --show-current)" --json number,title,url,state --jq '.[]'
task project:<name> '(status:pending or +ACTIVE)' export | jq '.[]'
```

Plus the conversation: what finished, what's hanging, what was learned,
what plugin/skill friction or wins occurred.

### Step 2: Qualify each pass

Apply each skill's own signal filter strictly; **silently skip passes
that don't qualify** — offering an empty pass is the drown-in-signals
failure mode.

| Pass | Qualifies when |
|---|---|
| Wrap | ≥1 genuine loose thread per session-wrap's LOG IT filter |
| Distill | A durable, generalizable learning emerged AND the repo has a distillable surface (`.claude/rules/` or a justfile) |
| Feedback | A plugin/skill behaved notably well or badly — bug, enhancement, or positive worth filing |
| Taskwarrior sync | Taskwarrior is on PATH AND ≥1 pending/active task for the project (`task project:<name> '(status:pending or +ACTIVE)' export \| jq 'length'`) |

If **nothing** qualifies, say so in one line and end — no preview, no
question.

### Step 3: One preview, one confirmation

Present a single compact preview: each qualifying pass with a one-line
reason and its concrete payload (the wrap items; the distill proposal
sketch; the feedback finding; the open taskwarrior items with their UUIDs).
Then **one AskUserQuestion** (multiSelect) listing the qualifying passes
as options, qualifying ones described with their reasons. The user picks
any subset; "Other" covers adjustments.

Never end the turn on a freeform "y/n" text question — ending the turn
fires Stop hooks mid-confirmation (the race that motivated this
orchestrator). AskUserQuestion keeps the turn open.

### Step 4: Sequence the confirmed passes

Run in this order, each via the Skill tool (or inline for taskwarrior
sync), passing along the Step 1 survey so they don't re-do it:

1. **Taskwarrior sync** (if confirmed) — run inline before Wrap so Wrap
   sees the updated queue state. For each open/active task: ask the user
   (via AskUserQuestion) whether to mark done, update, or leave. Address
   tasks by stable UUID (`task +LATEST _get uuid` after creation;
   `task <uuid> done` / `task <uuid> modify` for existing tasks). Never
   use volatile numeric IDs — they shift when other tasks complete.
2. `session-plugin:session-wrap` — closes/annotates/adds tasks so later
   passes see the final queue state
3. `session-plugin:session-distill` — apply mode per its own flow; the
   user already confirmed the pass, so skip a second blanket prompt but
   keep distill's per-category destructive-change prompts
4. `feedback-plugin:feedback-session` — cross-plugin; if the feedback
   plugin isn't installed, note it and skip

### Step 5: Report

One short block: what each executed pass wrote (tasks touched / closed,
files edited, issues filed) and which passes were skipped as not qualifying.

## Seam: distill vs feedback

"Discovered a better flag / a skill suggested something subtly wrong" →
**feedback** (issue on claude-plugins). "Found a reusable project
pattern, rule, or recipe" → **distill** (artifact in this repo). When
both apply, both run — they write to different places.

## Auto-surfacing

A Stop hook (`hooks/session-end-nudge.sh`) offers this skill at most
once per session when the user's own messages carry a wind-down phrase.
It is offer-only and stays silent when this skill (or wrap/distill) is
already in the transcript. Pre-silence:
`touch ~/.cache/claude-session-end-nudge/<session_id>`.

## Agentic Optimizations

| Context | Command |
|---|---|
| Queue state (exit-0 on empty) | `task project:<name> '(status:pending or +ACTIVE)' export \| jq '.[]'` |
| Stable UUID for latest task | `task +LATEST _get uuid` |
| Mark task done by UUID | `task <uuid> done` |
| Distillable surface check | `find . -maxdepth 2 -path '*/.claude/rules' -o -maxdepth 1 -name 'justfile' -o -maxdepth 1 -name 'Justfile'` |
| Branch PRs | `gh pr list --head <branch> --json number,title,url,state --jq '.[]'` |
