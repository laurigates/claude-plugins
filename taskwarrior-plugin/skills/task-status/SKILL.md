---
name: task-status
description: |
  Read-only consolidated taskwarrior queue report — pending, blocked,
  ready, and drift detection between the queue and linked trackers / PRs.
  When a GitHub remote is present, folds in gh pr status so "PR #99 green,
  task #7 still pending" surfaces in one view. Use when auditing queue
  health, orienting before a wave dispatch, spotting tasks that lost
  their linked issue or PR, or producing a standup summary.
args: "[--mine] [--blocked] [--stale=N] [--project=<name>] [--all]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh pr *), Bash(jq *), Read, TodoWrite
argument-hint: optional filters
created: 2026-04-24
modified: 2026-04-29
reviewed: 2026-04-29
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
- Git toplevel: !`git rev-parse --show-toplevel`
- Git remote: !`git remote`
- GH auth: !`gh auth status`
- Known projects: !`task _projects`

## Parameters

Parse `$ARGUMENTS`:

- `--mine` — limit to tasks where `assigned:` matches current user / agent
- `--blocked` — only tasks with `+blocked` / `+blocked-on-merge` or active `depends:`
- `--stale=N` — highlight tasks modified > N days ago
- `--project=<name>` — override the auto-detected project filter
- `--all` — opt out of project filtering and report across every project
- No flags — full report **scoped to the current project**

### Project resolution

Default behaviour is project-scoped — surfacing tasks from other repos as
"queue noise" is the most common waste of agent context. Resolve the
project identifier in this order:

1. `--project=<name>` if provided.
2. `--all` → no project filter.
3. Basename of the path reported as `Git toplevel` in Context.
4. If no git repo, basename of the cwd.

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
task project:myrepo status:pending export | jq '.[] | {id, description, urgency, tags, bpid, bpdoc, ghid, ghpr, modified, depends}'
```

For completeness also pull recently-completed in the same project:

```bash
task project:myrepo status:completed end.after:now-7d export | jq '.[] | {id, description, bpid, ghid, end}'
```

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
- Task `+pr-ready` but PR not in `OPEN` — `drift: pr-state-mismatch`

### Step 4: PR status fold-in (GitHub mode)

```bash
gh pr status --json number,title,state,statusCheckRollup | jq
```

Join by `ghpr` UDA. Annotate each matched task with its PR's check
rollup (`SUCCESS` / `FAILURE` / `PENDING`). Tasks tagged `+pr-ready`
with a green PR are the highest-value drain candidates.

### Step 5: Render

Lead the report with the resolved project scope so the reader knows
whether they're seeing a single-project view or `--all`:

```
Project: myrepo (auto-detected from git toplevel)
Pass --all for cross-project view, --project=<name> to override.
```

Output these sections, in order:

1. **Summary**: pending count, ready count (unblocked), blocked count, stale count
2. **By milestone**: table of pending tasks per `bpms`
3. **Ready for dispatch**: top 5 by urgency with no `depends:` and no `+blocked*` tags
4. **Blocked**: tasks waiting on dependencies or external factors
5. **PR-ready** (GitHub mode): tasks with green PRs ready to close
6. **Drift**: tasks with stale links (issue closed, missing bpdoc, etc.)

Each row cites the command to act on it (`/taskwarrior:task-done 7`).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Project queue JSON | `task project:myrepo status:pending export \| jq` |
| Cross-project queue (`--all`) | `task status:pending export \| jq` |
| Ready-for-dispatch | `task project:myrepo status:pending -BLOCKED export \| jq 'sort_by(-.urgency) \| .[:5]'` |
| PR status | `gh pr status --json number,state,statusCheckRollup` |
| Drift check | `gh issue view "$GHID" --json state` |
| Never use | `task list`, `task next`, `task report` — exit 1 on empty |

## Quick Reference

| Filter | Expands to |
|--------|-----------|
| `project:<name>` | Single project (default scope) |
| `status:pending` | Open tasks |
| `-BLOCKED` | Exclude `depends:`-blocked |
| `urgency.above:5` | High-urgency only |
| `modified.before:now-30d` | Stale |
| `bpms:M6` | Single milestone |

## Related

- `/taskwarrior:task-coordinate` — next-N candidates for dispatch
- `/taskwarrior:task-add` — file something surfaced by drift detection
- `/taskwarrior:task-done` — close PR-ready tasks
- `.claude/rules/parallel-safe-queries.md` — `export | jq` idiom
