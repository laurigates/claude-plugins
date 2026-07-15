---
name: task-status
description: Read-only taskwarrior queue report — pending, blocked, ready tasks and drift vs linked PRs. Use when auditing queue health, orienting before a wave, or for standup summaries.
args: "[--mine] [--blocked] [--stale=N] [--project=<name>] [--all]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh pr *), Bash(jq *), Read, TodoWrite
argument-hint: optional filters
created: 2026-04-24
modified: 2026-05-22
reviewed: 2026-05-22
---

# /taskwarrior:task-status

Read-only status report on the coordination queue. Strictly uses `export | jq` — never `list` — so parallel Bash batches from downstream skills stay safe.

## When to Use This Skill

| Use this skill when... | Use `task-coordinate` / `task-add` / `task-done` instead when... |
|---|---|
| Auditing pending / blocked / stale tasks across the project queue | Picking the top-N candidates for a wave dispatch — use `task-coordinate` |
| Detecting drift between tasks and their linked GitHub issues / PRs | Filing a new task surfaced by drift detection — use `task-add` |
| Folding `gh pr status` rollups into a standup-ready report | Closing a PR-ready task with a landed commit — use `task-done` |

## Context

- Task CLI available: !`task --version`
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`
- GH auth: !`gh auth status`
- Known projects: !`task _projects`

Git probes (`git rev-parse --show-toplevel`, `git remote`) write to stderr
in a no-git cwd, and stderr from a Context backtick aborts the skill
before its body runs. Project resolution is done in the body (Step 1
below), where `2>/dev/null` and exit-code handling are available.

## Parameters

Parse `$ARGUMENTS`:

- `--mine` — limit to tasks where the `agent` UDA matches `claude-${CLAUDE_SESSION_ID:0:8}` (the value `/taskwarrior:task-claim` writes). Useful for "what am I currently holding?" reports.
- `--blocked` — only tasks with `+blocked` / `+blocked_on_merge` or active `depends:`
- `--active` — only `+ACTIVE` tasks (claimed and in flight)
- `--stale=N` — highlight tasks modified > N days ago
- `--stale-claim-after=N` — threshold (hours) for flagging a `+ACTIVE` claim as stale in the "Stale claims" section. Default 4. Reports only — never auto-stops.
- `--project=<name>` — override the auto-detected project filter
- `--all` — opt out of project filtering and report across every project
- No flags — full report **scoped to the current project**

### Project resolution

Default behaviour is project-scoped — surfacing tasks from other repos as
"queue noise" is the most common waste of agent context. Resolve the
project identifier in this order:

1. `--project=<name>` if provided.
2. `--all` → no project filter.
3. Basename of `git rev-parse --show-toplevel 2>/dev/null`, run via the
   Bash tool (where stderr suppression and non-zero exits are tolerated).
4. If no git repo (Step 3 returned empty), basename of the cwd.

Cross-check the resolved name against `Known projects`. If it is not in
the list, note it (likely a fresh project or no tasks filed yet) but
still apply the filter — `task export` returns `[]` cleanly when the
project has no matching tasks.

## Execution

Execute this workflow:

### Step 1: Snapshot the queue

Pull full state as JSON in a single call, scoped to the resolved project
(omit `project:$PROJECT` only when `--all` is set). `task export` emits
`[]` on an empty store — valid and exit 0. Substitute the literal
project name into the filter — do **not** use `$()` command substitution
in the inline command (shell-operator protections will reject it).

```bash
task project:myrepo status:pending export | jq '.[] | {id, uuid, description, urgency, tags, bpid, bpdoc, ghid, ghpr, agent, pid, host, branch, worktree, start, modified, depends, due, scheduled, wait}'
```

For completeness also pull recently-completed in the same project:

```bash
task project:myrepo status:completed end.after:now-7d export | jq '.[] | {id, description, bpid, ghid, end}'
```

In parallel, pull the in-flight set so the "In flight" and "Stale
claims" sections in Step 5 have data to render:

```bash
task project:myrepo +ACTIVE export | jq '.[] | {id, uuid, description, agent, pid, host, branch, worktree, start, urgency}'
task project:myrepo +ACTIVE start.before:now-4h export | jq '.[] | {id, uuid, agent, host, branch, start}'
```

These three reads are independent and parallel-safe — `export` returns
exit 0 on empty.

### Step 2: Sort and group

By urgency descending, then by milestone (`bpms`), then by blueprint kind
(`+wo` / `+prp` / `+fr` / `+re`). Use jq to partition:

```bash
task project:myrepo status:pending export \
  | jq 'group_by(.bpms) | map({milestone: .[0].bpms, tasks: sort_by(-.urgency)})'
```

### Step 3: Drift detection

For each task with `bpdoc`: check the file exists and is readable. Flag
missing or unreadable `bpdoc` as drift.

For each task with `ghid` in GitHub mode:

```bash
gh issue view "$GHID" --json number,state | jq
```

Flag:

- Task open, issue closed — `drift: stale-open`
- Task `+pr_ready` but PR not in `OPEN` — `drift: pr-state-mismatch`

### Step 4: PR status fold-in (GitHub mode)

```bash
gh pr status --json number,title,state,statusCheckRollup | jq
```

Join by `ghpr` UDA. Annotate each matched task with its PR's check
rollup (`SUCCESS` / `FAILURE` / `PENDING`). Tasks tagged `+pr_ready`
with a green PR are the highest-value drain candidates.

### Step 5: Render

Lead the report with the resolved project scope so the reader knows
whether they're seeing a single-project view or `--all`:

```
Project: myrepo (auto-detected from git toplevel)
Pass --all for cross-project view, --project=<name> to override.
```

Output these sections, in order:

1. **Summary**: pending count, in-flight count, ready count (`+READY` + unclaimed), blocked count, overdue count, stale count, stale-claim count
2. **In flight**: `+ACTIVE` tasks with `agent` / `branch` / `host` / `worktree` and time since `start`. Sorted by `start` ascending (oldest first). Section header notes `--mine` / `--all` scope.
3. **Stale claims** (>4h or `--stale-claim-after`): subset of "In flight" with `start.before:now-Nh`. Recommend `/taskwarrior:task-release <id>` per row — the report never auto-stops.
4. **Ready for dispatch**: top 5 by urgency from `+READY -ACTIVE` (taskwarrior's native ready set — unblocked, not waiting, scheduled-due). These are what `/taskwarrior:task-coordinate` would emit. Flag any `+OVERDUE` rows (past `due:`) at the top.
5. **By milestone**: table of pending tasks per `bpms`
6. **Blocked**: tasks waiting on dependencies or external factors
7. **PR-ready** (GitHub mode): tasks with green PRs ready to close
8. **Drift**: tasks with stale links (issue closed, missing bpdoc, etc.)

Each row cites the command to act on it (`/taskwarrior:task-done 7`,
`/taskwarrior:task-release 4`, `/taskwarrior:task-claim 11`), plus the task's
short UUID (`.uuid[0:8]`) as a copy-pasteable immutable form — convenience
only, not the safety mechanism (`/taskwarrior:task-claim` /
`task-release` / `task-done` resolve and mutate by UUID internally
regardless of which form is pasted; see `.claude/rules/task-id-stability.md`).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Project queue JSON | `task project:myrepo status:pending export \| jq` |
| Cross-project queue (`--all`) | `task status:pending export \| jq` |
| Ready-for-dispatch (excludes claimed) | `task project:myrepo status:pending +READY -ACTIVE export \| jq 'sort_by(-.urgency) \| .[:5]'` |
| Overdue tasks | `task project:myrepo status:pending +OVERDUE export \| jq 'sort_by(-.urgency)'` |
| In flight | `task project:myrepo +ACTIVE export \| jq '.[] \| {id, agent, branch, host, start}'` |
| Stale claims (>4h) | `task project:myrepo +ACTIVE start.before:now-4h export \| jq` |
| Mine (claimed by this agent) | `task project:myrepo +ACTIVE agent:claude-${CLAUDE_SESSION_ID:0:8} export \| jq` |
| PR status | `gh pr status --json number,state,statusCheckRollup` |
| Drift check | `gh issue view "$GHID" --json state` |
| Never use | `task list`, `task next`, `task report` — exit 1 on empty |

## Quick Reference

| Filter | Expands to |
|--------|-----------|
| `project:<name>` | Single project (default scope) |
| `status:pending` | Open tasks |
| `+READY` | Native ready set: unblocked, not waiting, scheduled-due |
| `-BLOCKED` | Exclude `depends:`-blocked (subsumed by `+READY`) |
| `+DUE` / `+OVERDUE` | Due within 7 days / past `due:` |
| `+ACTIVE` / `-ACTIVE` | Tasks with `task start` time set / not set |
| `start.before:now-4h` | Stale claims |
| `agent:claude-<sid>` | Mine (UDA-based) |
| `urgency.above:5` | High-urgency only |
| `modified.before:now-30d` | Stale |
| `bpms:M6` | Single milestone |

## Related

- `/taskwarrior:task-coordinate` — next-N candidates for dispatch
- `/taskwarrior:task-claim` — pick up a "Ready" candidate from this report
- `/taskwarrior:task-release` — release a "Stale claim" surfaced by this report
- `/taskwarrior:task-add` — file something surfaced by drift detection
- `/taskwarrior:task-done` — close PR-ready tasks
- `.claude/rules/parallel-safe-queries.md` — `export | jq` idiom
- `.claude/rules/task-id-stability.md` — why the report's UUID column is convenience, not the safety mechanism
