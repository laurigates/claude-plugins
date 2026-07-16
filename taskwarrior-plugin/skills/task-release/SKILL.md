---
name: task-release
description: Release a taskwarrior task without closing it — stops +ACTIVE clock and annotates state for handoff. Use when pausing mid-task, handing off to another agent, or aborting cleanly.
args: "<task-id> [<state-message>] [--clear-identity] [--no-coworker-marker]"
allowed-tools: Bash(task *), Bash(git rev-parse *), Bash(git branch *), Bash(jq *), Bash(bash *), Read, TodoWrite
argument-hint: task id (required) and optional state message
created: 2026-05-09
modified: 2026-05-22
reviewed: 2026-05-22
---

# /taskwarrior:task-release

Release an active claim without closing the task. Pairs with `/taskwarrior:task-claim`: claim picks the task up, release puts it back down.

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Pausing a task mid-flight (lunch break, context switch, end of session) | The work has landed in a commit — use `/taskwarrior:task-done` |
| Handing off to another agent — leaving an annotation describing where you stopped | Starting work on a fresh task — use `/taskwarrior:task-claim` |
| Aborting a started task because scope was wrong | Filing a brand-new task to capture the work — use `/taskwarrior:task-add` |

## Context

- Task CLI available: !`task --version`
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`

Git probes (`git rev-parse --show-toplevel`, `git branch --show-current`)
write to stderr in a no-git cwd, and stderr from a Context backtick
aborts the skill before its body runs. Git toplevel and current-branch
resolution are done in the body via the Bash tool (where `2>/dev/null`
and exit-code handling are tolerated).

## Parameters

Parse `$ARGUMENTS`:

- `$0` — task ID (required).
- Remaining positional words — concatenate as the freeform state message for the handoff annotation. If empty, prompt for one before annotating (an empty handoff annotation defeats the purpose).
- `--clear-identity` — clear `agent` / `host` / `branch` / `worktree` UDAs in addition to `pid`. Use when the next agent should not inherit any context (e.g. cross-host handoff). Default behaviour preserves these so the queue still shows who last touched the task.
- `--no-coworker-marker` — skip the `/git:coworker-check --release` step. By default, releasing the task also drops the git-side session marker so destructive ops in this clone are no longer guarded.

## Execution

Execute this release workflow:

### Step 1: Load the task

```bash
task "$TASKID" export | jq '.[0] | {id, uuid, description, status, start, agent, pid, host, branch, worktree, annotations}'
```

Use `export | jq` — never `info` / `list`. Capture the `uuid` field as
`$TASK_UUID` — every mutating call from Step 3 onward addresses the task by
`$TASK_UUID`, never `$TASKID`. Step 2's `AskUserQuestion` pause is a real gap
during which another agent's concurrent `task done` can renumber `$TASKID`
(see `.claude/rules/task-id-stability.md`). Decide:

| Condition | Action |
|---|---|
| `status` is not `pending` | Abort. Released tasks must be pending; if it is already closed, the release is a no-op. |
| `start` is unset (not `+ACTIVE`) | Warn but proceed — annotation + UDA drain still useful as a "I looked at this" signal. |
| `start` is set | Standard path. Continue. |

### Step 2: Resolve state message

If the user did not pass a message, ask them for one with a single `AskUserQuestion`. The annotation is the handoff payload — without it the next agent has only timestamps. Keep the prompt focused: "Where did you stop? (one sentence)".

### Step 3: Annotate the handoff

Annotate **before** stopping — if the stop fails (e.g. concurrent modify), the annotation is still captured:

```bash
task "$TASK_UUID" annotate "released by $AGENT — state: $MESSAGE"
```

`$AGENT` is read from the task's existing `agent` UDA (the claim stamped it); fall back to `claude-${CLAUDE_SESSION_ID:0:8}` if unset.

### Step 4: Stop the active state

```bash
task "$TASK_UUID" stop
```

This clears the built-in `start` attribute and removes the `+ACTIVE` virtual tag. The task is back in the dispatch pool for `/taskwarrior:task-coordinate`.

### Step 5: Drain identity UDAs

Always clear `pid` (the process is going away):

```bash
task "$TASK_UUID" modify pid:
```

When `--clear-identity` is passed, also clear the rest:

```bash
task "$TASK_UUID" modify agent: host: branch: worktree:
```

The empty-value `field:` syntax removes a UDA in taskwarrior. Default behaviour keeps `agent` / `host` / `branch` / `worktree` so `task-status` "Recently touched" can attribute the work.

### Step 6: Drop the coworker-check marker

Unless `--no-coworker-marker` was passed:

```
Use SlashCommand to invoke `/git:coworker-check --release`.
```

Fallback if SlashCommand is unavailable:

```bash
bash "$(git rev-parse --show-toplevel)/git-plugin/skills/git-coworker-check/scripts/release-session.sh" --project-dir "$(pwd)"
```

### Step 7: Report

Print:

- Task ID, description, current status (still pending)
- Time spent active (from `start` timestamp to now — read before stopping)
- Annotation appended
- Identity drain: `pid` only / full drain
- Coworker-check status: marker released / skipped
- Suggested next step:
  - `/taskwarrior:task-coordinate` to dispatch the now-unclaimed work onto the next wave
  - `/taskwarrior:task-claim <id>` to re-claim later

## Agentic Optimizations

| Context | Command |
|---|---|
| Read existing claim before release | `task _get "$TASKID".agent` (single-field, exit 0 even when unset) |
| Time-spent computation | `task "$TASKID" export \| jq '.[0].start'` then compute against `now` |
| Bulk release of stale claims | Pair with `task +ACTIVE start.before:now-4h export \| jq '.[].id'` |
| Skip empty-result failures | Always `export \| jq`, never `task active list` |

## Quick Reference

| Step | Command |
|---|---|
| Annotate | `task UUID annotate "released by AGENT — state: MSG"` |
| Stop active | `task UUID stop` |
| Clear pid | `task UUID modify pid:` |
| Full identity drain | `task UUID modify agent: host: branch: worktree: pid:` |
| Drop git marker | `/git:coworker-check --release` |

## Related

- `/taskwarrior:task-claim` — pair: pick up an unclaimed task
- `/taskwarrior:task-done` — close after landing (also auto-stops + drains identity)
- `/taskwarrior:task-coordinate` — finds the next dispatch candidate
- `/git:coworker-check` — sister marker that this skill drops on `--release`
- `.claude/rules/agent-coworker-detection.md` — combined-signal rationale
- `.claude/rules/task-id-stability.md` — why this skill resolves `$TASK_UUID` once and mutates by UUID
