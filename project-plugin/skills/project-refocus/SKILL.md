---
name: refocus
description: "Refresh the plan to focus on the task at hand. Use when context grew, completed steps muddy it, or you want to clear context and continue in auto mode."
args: "[focus directive (optional free text)]"
argument-hint: "[optional: what to focus on, e.g. 'the API layer, ignore docs work']"
allowed-tools: Read, Grep, Glob, Bash(git status *), Bash(git log *), Bash(git diff *), TodoWrite, ExitPlanMode
created: 2026-06-08
modified: 2026-06-15
reviewed: 2026-06-15
---

# /project:refocus

Refresh the plan so it focuses only on the task that remains, then surface it for approval so the user can **clear context and continue in auto mode** from a clean slate.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|------------------------|-----------------------------|
| Context has grown and the completed early steps now muddy it | Resuming after a break with no live context to trim → `/project:continue` |
| You want a tightened, forward-only plan before continuing | Capturing session learnings into rules/recipes → `/project:distill` |
| You want to clear context and continue in auto mode without losing the thread | Entering an unfamiliar codebase needing orientation → `/project:discovery` |
| The user says "refresh the plan", "refocus", "let's focus on what's left", "trim the context" | Picking the next blueprint action → `/blueprint:execute` |

The output is deliberately **self-contained**: it must survive a context clear. Approving it from the `ExitPlanMode` dialog is where Claude Code offers "clear context and continue in auto mode."

## Context

- Current branch: !`git branch --show-current`
- Working tree: !`git status --porcelain=v2 --branch`
- Recent commits: !`git log --format='%h %s' --max-count=8`
- Active todos: review the current TodoWrite list (if any) for done-vs-remaining state

## Parameters

Parse `$ARGUMENTS` as an **optional free-text focus directive** that biases what
counts as Remaining vs Stale and what the Objective emphasizes (e.g. "focus on
the API layer, ignore the docs work").

- **No directive** → behave deterministically from conversation + git as today; do not invent a focus.
- **Directive given** → treat it as *steering*, not *override*. It re-weights the bucketing and phrasing; it does **not** cancel a genuine in-flight boundary the user set earlier ("don't push until I review", "keep the old endpoint"). When a directive appears to contradict a live boundary, keep the boundary and note the tension in the plan rather than silently dropping it.

## Execution

Execute this plan-refresh workflow. Reason over the **live conversation**, not just git — git grounds what landed on disk; the conversation holds the decisions and the remaining intent.

### Step 1: Take stock of the conversation

Scan the session so far and sort everything into three buckets:

1. **Done** — steps completed and verified (committed, tested, or confirmed working).
2. **Remaining** — the task still at hand: what the user actually wants finished.
3. **Stale** — exploration, abandoned approaches, and resolved tangents that now only add noise.

Ground "Done" against `git log` / `git status` from Context so you don't trust a claim that never reached disk.

**If a focus directive was given** (see Parameters): bias the bucketing toward
it. Work the directive names becomes Remaining-weighted; areas it de-emphasizes
("ignore the docs work") become **Stale-eligible** — moved to Stale unless the
conversation shows them as a still-active user boundary or an unfinished
dependency of the focused work. A directive cannot promote to Done something
git/conversation shows unfinished, nor demote to Stale a boundary the user still holds.

### Step 2: Extract the load-bearing decisions

From the Done and Remaining buckets, pull the facts the remaining work depends on — the things that would be **lost on a context clear**:

- Concrete file paths and the functions/sections being changed.
- Decisions already made (library chosen, approach agreed, constraint set by the user).
- Stated boundaries still in force ("don't push until I review", "keep the old endpoint"). These do not survive compaction on their own — restate them explicitly (see `.claude/rules/auto-mode.md` on conversation-stated boundaries).
- Open questions the user already answered, so they are not re-asked.

### Step 3: Draft a self-contained forward plan

Write a plan that reads as a **standalone brief** — assume the reader has none of the current context. Use no "as discussed above" / "the file we edited" references; name everything explicitly.

```markdown
## Objective
<one sentence: the task at hand, restated plainly>

## Already done (do not redo)
- <completed step> → <commit / file proving it landed>

## Constraints & decisions (carry forward)
- <decision or boundary that the remaining work must honor>

## Remaining steps
1. <imperative step naming the exact file/path and what changes>
2. ...

## Verification
- <how we confirm done: test command, behavior to observe>
```

Drop the Stale bucket entirely — that pruning is the point.

When a focus directive was given, the Objective leads with the focused task and
explicitly scopes out the de-emphasized areas, so the cleared-context reader
inherits the narrowing.

### Step 4: Surface it via ExitPlanMode

Call `ExitPlanMode` with the plan from Step 3 as its content. This presents the refreshed plan for approval and surfaces the continuation options — including **clear context and continue in auto mode**. Do not start executing the remaining steps before approval.

If the session is not already in plan mode, present the plan as your response and offer to refocus from there; the self-contained plan text is the deliverable either way.

### Step 5: Hand off to a cleared context

When the user opts to clear context and continue in auto mode, the plan from Step 3 is all that survives — which is exactly why it was written standalone. After the clear, seed a fresh TodoWrite list from the "Remaining steps" and proceed.

Under auto mode, keep the narrow `Bash(<command> *)` permissions this skill already declares — they carry over and skip the classifier round-trip (see `.claude/rules/auto-mode.md`).

## Self-Contained Checklist

Before calling `ExitPlanMode`, confirm the plan:

- [ ] States the objective in one sentence with no back-references
- [ ] Names every file/path explicitly (no "the file above")
- [ ] Restates active user boundaries verbatim (they vanish on clear)
- [ ] Lists what is already done so it is not redone
- [ ] Ends with a concrete verification step
- [ ] Contains nothing from the Stale bucket
- [ ] If a focus directive narrowed scope, the de-emphasized work is in Stale (not silently dropped from an active boundary)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| What landed on disk | `git log --format='%h %s' --max-count=8` |
| Uncommitted surface | `git status --porcelain=v2 --branch` |
| Confirm a "done" claim | `git diff --stat` against the named files |
| Seed remaining work | Rebuild TodoWrite from the plan's "Remaining steps" |
