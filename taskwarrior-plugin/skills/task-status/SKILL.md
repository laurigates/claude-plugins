---
name: task-status
description: |
  Read-only consolidated taskwarrior queue report — pending, blocked,
  ready, and drift detection between the queue and linked trackers / PRs.
  When a GitHub remote is present, folds in gh pr status so "PR #99 green,
  task #7 still pending" surfaces in one view. Use when auditing queue
  health, orienting before a wave dispatch, spotting tasks that lost
  their linked issue or PR, or producing a standup summary.
args: "[--mine] [--blocked] [--stale=N]"
allowed-tools: Bash(task *), Bash(git config *), Bash(gh auth *), Bash(gh pr *), Bash(jq *), Read, TodoWrite
argument-hint: optional filters
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# /taskwarrior:task-status

Read-only status report on the coordination queue. Strictly uses `export | jq` — never `list` — so parallel Bash batches from downstream skills stay safe.

## Context

- Task CLI available: !`command -v task`
- Pending count (export/jq): !`task status:pending export`
- Git remote: !`git config --get remote.origin.url`
- GH auth: !`gh auth status`

## Parameters

Parse `$ARGUMENTS`:

- `--mine` — limit to tasks where `assigned:` matches current user / agent
- `--blocked` — only tasks with `+blocked` / `+blocked-on-merge` or active `depends:`
- `--stale=N` — highlight tasks modified > N days ago
- No flags — full report

## Execution

Execute this workflow:

### Step 1: Snapshot the queue

Pull full state as JSON in a single call. `task export` emits `[]` on an
empty store — valid and exit 0.

```bash
task status:pending export | jq '.[] | {id, description, urgency, tags, bpid, bpdoc, ghid, ghpr, modified, depends}'
```

For completeness also pull recently-completed:

```bash
task status:completed end.after:now-7d export | jq '.[] | {id, description, bpid, ghid, end}'
```

### Step 2: Sort and group

By urgency descending, then by milestone (`bpms`), then by blueprint kind
(`+wo` / `+prp` / `+fr` / `+re`). Use jq to partition:

```bash
task status:pending export \
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
| Full queue JSON | `task status:pending export \| jq` |
| Ready-for-dispatch | `task status:pending -BLOCKED export \| jq 'sort_by(-.urgency) \| .[:5]'` |
| PR status | `gh pr status --json number,state,statusCheckRollup` |
| Drift check | `gh issue view "$GHID" --json state` |
| Never use | `task list`, `task next`, `task report` — exit 1 on empty |

## Quick Reference

| Filter | Expands to |
|--------|-----------|
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
