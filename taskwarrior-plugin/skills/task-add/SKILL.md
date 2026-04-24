---
name: task-add
description: |
  File a new taskwarrior task with blueprint linkage (bpid/bpdoc/bpms) and,
  when a GitHub remote is present, optional issue linkage via ghid. Checks
  for duplicates by bpid, offers to pre-fill from an existing GitHub issue,
  or offers to create a new issue. Use when adding a coordination task for
  multi-agent work, linking a blueprint WO to an actionable queue entry,
  or mirroring a GitHub issue into the local task queue.
args: "[description]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh issue *), Bash(gh api *), Read, TodoWrite
argument-hint: short task description
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# /taskwarrior:task-add

File a coordination task. When a GitHub remote is present, offer optional linkage so GitHub stays the system of record and taskwarrior stays the parallel-safe query layer.

## Context

- Task CLI available: !`command -v task`
- Git remote: !`git config --get remote.origin.url`
- GH auth: !`gh auth status`
- Existing UDAs: !`task _udas`
- Duplicate check preamble: !`task _projects`

## Parameters

Parse `$ARGUMENTS`:

- Freeform short description (required).
- Optional inline `bpid:WO-012` / `bpdoc:docs/wo/012.md` / `bpms:M6` / `ghid:145` / `ghpr:99` fields.
- Optional tags: `+wo`, `+prp`, `+fr`, `+re`, `+gh`, `+pr-ready`, `+needs-review`, `+blocked-on-merge`, `+blocked`.

## Execution

Execute this workflow:

### Step 1: Ensure UDAs exist

If `task _udas` output lacks `bpid`, `bpdoc`, `bpms`, `ghid`, or `ghpr`, offer to install them:

```bash
task config uda.bpid.type string
task config uda.bpid.label "Blueprint ID"
task config uda.bpdoc.type string
task config uda.bpdoc.label "Blueprint doc"
task config uda.bpms.type string
task config uda.bpms.label "Milestone"
task config uda.ghid.type numeric
task config uda.ghid.label "GH Issue"
task config uda.ghpr.type numeric
task config uda.ghpr.label "GH PR"
```

Install only with user confirmation on first run per host.

### Step 2: Detect GitHub mode

GitHub mode is active when all of:

1. `git config --get remote.origin.url` is non-empty
2. `gh auth status` exits 0

If either fails, skip GitHub-related branches in later steps.

### Step 3: Duplicate check by bpid

If `bpid:` was given, run parallel-safe:

```bash
task bpid:"$BPID" export | jq '.[] | {id, description, status}'
```

Never use `task bpid:"$BPID" list` — it exits 1 on empty result and cancels sibling tool calls in parallel batches (see `.claude/rules/parallel-safe-queries.md`).

If a matching open task exists, report the ID and ask whether to update instead of re-add.

### Step 4: Optionally pre-fill from a GitHub issue

When GitHub mode is active and either `ghid:` is set or the description looks like an issue reference:

```bash
gh issue view "$GHID" --json number,title,body,labels,state
```

Offer to copy title into description, map labels to tags, and capture the issue number into the `ghid` UDA.

If the user wants a new issue created, use:

```bash
gh issue create --title "$TITLE" --body "$BODY"
```

…then capture the returned issue number into `ghid`. Skip this branch entirely in local-only mode.

### Step 5: Create the task

Compose the taskwarrior add command from the collected inputs. Quote every field; tags use the `+tag` form:

```bash
task add "$DESCRIPTION" \
  bpid:"$BPID" \
  bpdoc:"$BPDOC" \
  bpms:"$BPMS" \
  ghid:"$GHID" \
  ghpr:"$GHPR" \
  +wo +gh
```

Run with only the fields that were provided; omit empty UDAs entirely rather than passing `uda:""`.

### Step 6: Report

Print:

- New task ID
- bpid → bpdoc → bpms chain
- ghid/ghpr if linked
- Tags applied
- Suggested next step (`/taskwarrior:task-status` or `/taskwarrior:task-coordinate`)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Duplicate check by bpid | `task bpid:WO-012 export \| jq '.[] \| {id, status}'` |
| Pre-fill from issue | `gh issue view 145 --json number,title,body,labels` |
| Next unblocked | `task status:pending -BLOCKED export \| jq '.[:3]'` |
| Skip empty filter exit | Always use `export \| jq`, never `list` |

## Quick Reference

| Flag / field | Purpose |
|--------------|---------|
| `bpid:` | Blueprint ID link |
| `bpdoc:` | Blueprint doc path |
| `bpms:` | Milestone |
| `ghid:` | GitHub issue number |
| `ghpr:` | GitHub PR number |
| `+wo` | Work order |
| `+prp` | PRP |
| `+fr` | Feature request |
| `+re` | Research |
| `+gh` | Linked to GitHub |
| `+pr-ready` | Open PR waiting |
| `+blocked-on-merge` | Waiting on another PR |

## Related

- `/taskwarrior:task-status` — see current queue
- `/taskwarrior:task-done` — close an open task
- `/taskwarrior:task-coordinate` — next-agent candidates for a wave
- `.claude/rules/parallel-safe-queries.md` — why `export | jq`, never `list`
- `blueprint-plugin:feature-tracking` — FR/WO IDs that `bpid` points at
