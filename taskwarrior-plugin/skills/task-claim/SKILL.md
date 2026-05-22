---
name: task-claim
description: Claim a taskwarrior task as in-flight (+ACTIVE) and write a coworker marker. Use when picking up a task from task-coordinate output before starting implementation.
args: "<task-id> [--no-coworker-marker] [--force]"
allowed-tools: Bash(task *), Bash(git rev-parse *), Bash(git branch *), Bash(git config *), Bash(hostname *), Bash(jq *), Bash(bash *), Read, TodoWrite
argument-hint: task id (required)
created: 2026-05-09
modified: 2026-05-22
reviewed: 2026-05-22
---

# /taskwarrior:task-claim

Take ownership of a pending task. Stamps the task with this agent's identity and marks it `+ACTIVE` so concurrent agents see it is in flight and `/taskwarrior:task-coordinate` skips it on the next wave.

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Starting work on a task surfaced by `/taskwarrior:task-coordinate` | Filing a brand-new task — use `/taskwarrior:task-add` |
| Resuming a task after a context break (re-stamps `started` time) | Pausing for handoff without closing — use `/taskwarrior:task-release` |
| Forcing a stale claim onto yourself with `--force` | The task is done and ready to land — use `/taskwarrior:task-done` |

## Context

- Task CLI available: !`task --version`
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`
- Hostname: !`hostname`
- Existing UDAs: !`task _udas`

Git probes (`git rev-parse --show-toplevel`, `git branch --show-current`)
write to stderr in a no-git cwd, and stderr from a Context backtick
aborts the skill before its body runs. Git toplevel and current-branch
resolution are done in the body via the Bash tool (where
`2>/dev/null` and exit-code handling are tolerated).

## Parameters

Parse `$ARGUMENTS`:

- `$0` — task ID (required).
- `--no-coworker-marker` — skip the `/git:coworker-check --claim` step (use when the repo is intentionally shared and another agent will claim its own scope).
- `--force` — claim even when the task is already `+ACTIVE` (the previous claim is overwritten with an annotation noting the takeover).

## Execution

Execute this claim workflow:

### Step 1: Ensure identity UDAs exist

If `task _udas` output lacks `agent`, `pid`, `host`, `branch`, or `worktree`, install them on first run per host:

```bash
task config uda.agent.type string
task config uda.agent.label "Agent ID"
task config uda.pid.type numeric
task config uda.pid.label "Agent PID"
task config uda.host.type string
task config uda.host.label "Host"
task config uda.branch.type string
task config uda.branch.label "Git branch"
task config uda.worktree.type string
task config uda.worktree.label "Worktree path"
```

Confirm with the user before installing — UDA declarations live in `~/.taskrc` and persist across sessions.

### Step 2: Load the task and check active state

```bash
task "$TASKID" export | jq '.[0] | {id, description, status, start, agent, pid, host, branch, worktree}'
```

Use `export | jq` — never `task <id> info` or `task <id> list` (both exit 1 on empty / closed tasks and cancel parallel siblings; see `.claude/rules/parallel-safe-queries.md`).

Read the JSON. Decide:

| Condition | Action |
|---|---|
| `status` is not `pending` | Abort. Tasks must be pending to claim. |
| `start` is set and `--force` not passed | Abort. Report current `agent` / `pid` / `host` / `branch` so the user can either `--force` or pick another task. |
| `start` is set and `--force` passed | Annotate with takeover notice (Step 6) and proceed. |
| `start` is unset | Proceed cleanly. |

### Step 3: Coworker-check claim (default on)

Unless `--no-coworker-marker` was passed, write the session marker so destructive git ops in this clone (stash, reset, checkout --) trigger the cross-agent guard:

```
Use SlashCommand to invoke `/git:coworker-check --claim`.
```

The git-side marker (`<git-dir>/.claude-session-<pid>`) and the taskwarrior `+ACTIVE` claim are independent signals. Together they reinforce: a stash hook can read either one, and either is enough to pause a destructive op.

If the SlashCommand tool is unavailable in the current session, fall back to running the script directly:

```bash
bash "$(git rev-parse --show-toplevel)/git-plugin/skills/git-coworker-check/scripts/claim-session.sh" --project-dir "$(pwd)"
```

### Step 4: Resolve identity values

Capture once and reuse across the next two steps:

| Value | Source |
|---|---|
| `AGENT` | `claude-${CLAUDE_SESSION_ID:0:8}` (short, stable for the session) |
| `PID` | `$$` (the bash subshell PID — sufficient to cross-link with the git marker since both are taken at the same moment) |
| `HOST` | `hostname` |
| `BRANCH` | `git branch --show-current` (may be empty on a detached HEAD — leave the UDA unset rather than writing the literal "HEAD") |
| `WORKTREE` | `git rev-parse --show-toplevel` |

### Step 5: Start the task and stamp identity

Two calls — start first so `+ACTIVE` is set even if the modify step fails:

```bash
task "$TASKID" start
task "$TASKID" modify \
  agent:"$AGENT" \
  pid:"$PID" \
  host:"$HOST" \
  branch:"$BRANCH" \
  worktree:"$WORKTREE"
```

Omit `branch:` when `BRANCH` is empty (detached HEAD). Quote every value — `worktree:` paths frequently contain spaces.

### Step 6: Annotate the claim

```bash
task "$TASKID" annotate "claimed by $AGENT (pid $PID) on $BRANCH from $HOST:$WORKTREE"
```

When `--force` is used over an existing claim, annotate the takeover separately first so the previous owner's identity is preserved in the audit trail:

```bash
task "$TASKID" annotate "force-claim by $AGENT — previous: agent=$PREV_AGENT pid=$PREV_PID host=$PREV_HOST"
```

### Step 7: Report

Print:

- Task ID, description, urgency
- Identity stamp: `agent` / `pid` / `host` / `branch` / `worktree`
- Coworker-check status: claim written / skipped
- Suggested next step:
  - implementation work
  - `/taskwarrior:task-release <id>` to hand off without closing
  - `/taskwarrior:task-done <id>` once the work has landed

## Agentic Optimizations

| Context | Command |
|---|---|
| Active filter (parallel-safe) | `task +ACTIVE export \| jq '.[] \| {id, agent, branch, host}'` |
| Single-field DOM read | `task _get "$TASKID".agent` (exit 0 even when unset) |
| Cross-project active scan | `task status:pending +ACTIVE export \| jq` |
| Stale-claim probe | `task +ACTIVE start.before:now-4h export \| jq` |
| Skip empty-result failures | Always `export \| jq`, never `task active list` |

## Quick Reference

| Field | Type | Source on claim |
|---|---|---|
| `agent` | string | `claude-${CLAUDE_SESSION_ID:0:8}` |
| `pid` | numeric | `$$` at claim time |
| `host` | string | `hostname` |
| `branch` | string | `git branch --show-current` (omit on detached HEAD) |
| `worktree` | string | `git rev-parse --show-toplevel` |
| `start` (built-in) | date | Set automatically by `task start`; cleared by `task stop` |

| Tag (virtual) | Set by | Cleared by |
|---|---|---|
| `+ACTIVE` | `task start` | `task stop` / `task done` |

## Related

- `/taskwarrior:task-coordinate` — surfaces unblocked candidates to claim
- `/taskwarrior:task-release` — release without closing (handoff)
- `/taskwarrior:task-done` — close after landing (auto-releases the claim)
- `/git:coworker-check` — sister signal: process-scan + session marker
- `.claude/rules/agent-coworker-detection.md` — combined-signal rationale
- `.claude/rules/parallel-safe-queries.md` — `export | jq` idiom
