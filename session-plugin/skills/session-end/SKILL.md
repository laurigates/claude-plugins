---
name: session-end
description: End-of-session orchestrator. Previews which of wrap/distill/feedback/taskwarrior-sync qualify, single confirm, then sequence. Use when winding down a session.
allowed-tools: Bash(bash *), Bash(task *), Bash(git *), Bash(gh *), Read, Skill, AskUserQuestion, TodoWrite
created: 2026-06-10
modified: 2026-07-12
reviewed: 2026-06-24
---

# session-end

One survey, one preview, one confirmation — then run only the
end-of-session passes that actually qualify. This is the orchestrator
over three capture skills that used to compete for the wind-down moment
(design decisions D3/D4, `docs/archive/session-plugin-workflow.md`):

| Pass | Skill | Captures |
|---|---|---|
| Wrap | `session-plugin:session-wrap` | Loose threads → taskwarrior, optional journal, GitHub issues, upstream issue/PR candidates |
| Distill | `session-plugin:session-distill` | Durable learnings → rules, skill updates, justfile recipes |
| Feedback | `feedback-plugin:feedback-session` | Notable plugin/skill interactions → GitHub issues on claude-plugins |
| Taskwarrior sync | (inline, no sub-skill) | Close done tasks, update statuses, add follow-ups; uses stable UUIDs |
| Blueprint tracker-sync | `blueprint-plugin:blueprint-feature-tracker-sync` | Drain closed WO-linked tasks from tracker `tasks.pending` → `tasks.completed` (`--drain-wave`) |

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

One shared decision pass — do not let each sub-skill re-survey. Run the
shared collector (the same one the wrap/spinup skills and the nudge hook
use); it emits detection, git state, PRs, taskwarrior tasks **with stable
UUIDs**, and recent commits in one parallel-safe pass:

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-blueprint
```

Pass `--project <name>` to override the detected project. Hand the digest
to the confirmed passes in Step 4 so they don't re-survey. Plus the
conversation: what finished, what's hanging, what was learned, what
plugin/skill friction or wins occurred.

### Step 2: Qualify each pass

Apply each skill's own signal filter strictly; **silently skip passes
that don't qualify** — offering an empty pass is the drown-in-signals
failure mode.

| Pass | Qualifies when |
|---|---|
| Wrap | ≥1 genuine loose thread per session-wrap's LOG IT filter |
| Distill | A durable, generalizable learning emerged AND the repo has a distillable surface (`.claude/rules/` or a justfile) |
| Feedback | A plugin/skill behaved notably well or badly — bug, enhancement, or positive worth filing |
| Taskwarrior sync | `TASK_AVAILABLE=true` AND `OPEN_TASKS` ≥ 1 in the Step 1 digest |
| Blueprint tracker-sync | `UNDRAINED_COUNT` ≥ 1 in the Step 1 digest's `BLUEPRINT` section. Non-blueprint / tracker-missing repos auto-disqualify (count is 0) → silent skip. If `blueprint-plugin` isn't installed, note it and skip (as with Feedback) |

**Blueprint auto-drain (ADR-0020 level 1):** when the qualifying repo's
`docs/blueprint/manifest.json` has `automation.autonomy_level` ≥ 1 **and**
`task_registry["feature-tracker-sync"].auto_run == true`, the Blueprint
tracker-sync pass is **auto-confirmed**: leave it out of the Step 3 question,
run it in Step 4 order without asking, and report a one-line receipt in Step 5
(`Blueprint tracker-sync: drained N WO(s) automatically (auto_run)`). All other
passes still go through the Step 3 confirmation. Check the gate with:

```sh
jq -r 'if ((.automation.autonomy_level // 0) >= 1) and (.task_registry["feature-tracker-sync"].auto_run == true) then "auto" else "ask" end' docs/blueprint/manifest.json 2>/dev/null
```

If **nothing** qualifies, say so in one line and end — no preview, no
question.

### Step 3: One preview, one confirmation

Present a single compact preview: each qualifying pass with a one-line
reason and its concrete payload (the wrap items; the distill proposal
sketch; the feedback finding; the open taskwarrior items with their UUIDs;
for blueprint: `Blueprint tracker-sync — N closed WO task(s) not drained
from the feature tracker: WO-…`).
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
   tasks by stable UUID (`task +LATEST uuids` after creation;
   `task <uuid> done` / `task <uuid> modify` for existing tasks). Never
   use volatile numeric IDs — they shift when other tasks complete.
2. `session-plugin:session-wrap` — closes/annotates/adds tasks so later
   passes see the final queue state. Any **upstream issue/PR candidates**
   it surfaces appear in the Step 3 preview and route per-candidate in
   Wrap's own Step 4 (track-for-later vs verify-then-file) under this
   mandatory confirmation gate — filing an upstream issue is not
   `git restore`-able, exactly what the gate exists for. A *File now*
   candidate always routes through
   `workflow-orchestration-plugin:workflow-verify-before-filing` →
   `agent-patterns-plugin:cold-read-gate` → file; never blind
3. **Blueprint tracker-sync** (if confirmed) — runs after passes 1–2
   because both mutate the taskwarrior queue and may close more WO-linked
   tasks after the Step 1 survey. Re-derive the wave inline right before
   delegating (never reuse the survey's `UNDRAINED_WOS` as the drain list):

   ```sh
   task bpid.any: status:completed export 2>/dev/null | jq -r --slurpfile t docs/blueprint/feature-tracker.json '([.[] | .bpid // empty] | unique) as $closed | (($t[0].tasks.pending // []) | map(.id)) as $pending | [$closed[] | select(. as $w | $pending | index($w))] | join(",")'
   ```

   Then invoke `/blueprint:blueprint-feature-tracker-sync --drain-wave <list>`
   with **no** evidence flags — the sync skill sources evidence from
   taskwarrior annotations itself (its priority order: files → inline →
   annotation → ask). If the re-derived list is empty, report "already
   drained" and move on. Cross-plugin: if `blueprint-plugin` isn't
   installed, note it and skip
4. `session-plugin:session-distill` — apply mode per its own flow; the
   user already confirmed the pass, so skip a second blanket prompt but
   keep distill's per-category destructive-change prompts
5. `feedback-plugin:feedback-session` — cross-plugin; if the feedback
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
| One-pass survey (detection + git + PRs + tasks-with-UUIDs + commits + blueprint tracker state) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-blueprint` |
| Re-derive the drain wave before delegating | `task bpid.any: status:completed export \| jq …` intersected with tracker `tasks.pending` (Step 4.3) |
| Stable UUID for latest task | `task +LATEST uuids` |
| Mark task done by UUID | `task <uuid> done` |
| Distillable surface check | `find . -maxdepth 2 -path '*/.claude/rules' -o -maxdepth 1 -name 'justfile' -o -maxdepth 1 -name 'Justfile'` |
