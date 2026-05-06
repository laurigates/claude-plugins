---
name: task-add
description: |
  File a new taskwarrior task with blueprint linkage (bpid/bpdoc/bpms) and,
  when a GitHub remote is present, optional issue linkage via ghid. Checks
  for duplicates by bpid, offers to pre-fill from an existing GitHub issue,
  or offers to create a new issue. Use when adding a coordination task for
  multi-agent work, linking a blueprint WO to an actionable queue entry,
  or mirroring a GitHub issue into the local task queue.
args: "[description] [project:<name>] [--no-project]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh issue *), Bash(gh api *), Read, TodoWrite
argument-hint: short task description
created: 2026-04-24
modified: 2026-05-06
reviewed: 2026-05-06
---

# /taskwarrior:task-add

File a coordination task. When a GitHub remote is present, offer optional linkage so GitHub stays the system of record and taskwarrior stays the parallel-safe query layer.

## When to Use This Skill

| Use this skill when... | Use `task-status` / `task-coordinate` / `task-done` instead when... |
|---|---|
| Filing a brand-new coordination task with `bpid:` / `bpdoc:` linkage | Auditing existing queue health — use `task-status` |
| Mirroring a GitHub issue into the local queue via `ghid:` | Picking the next-N candidates for a parallel wave — use `task-coordinate` |
| Pre-filling a task body from `gh issue view` output | Closing an in-flight task and draining its tracker — use `task-done` |

## Context

- Task CLI available: !`task --version`
- Git toplevel: !`git rev-parse --show-toplevel`
- Git remote: !`git remote`
- GH auth: !`gh auth status`
- Existing UDAs: !`task _udas`
- Known projects: !`task _projects`

## Parameters

Parse `$ARGUMENTS`:

- Freeform short description (required).
- Optional inline `project:<name>` to override the auto-detected project.
- Optional `--no-project` to file the task without any project (cross-cutting work).
- Optional inline `bpid:WO-012` / `bpdoc:docs/wo/012.md` / `bpms:M6` / `ghid:145` / `ghpr:99` fields.
- Optional tags: `+wo`, `+prp`, `+fr`, `+re`, `+gh`, `+pr_ready`, `+needs_review`, `+blocked_on_merge`, `+blocked`. Use underscores or camelCase — hyphens silently break tag parsing (see "Tag naming gotcha" below).

### Project resolution

By default every task is filed under the current repo's project so
`/taskwarrior:task-status` and `/taskwarrior:task-coordinate` only see
tasks relevant to where the agent is working. Resolve the project in
this order:

1. Explicit `project:<name>` in `$ARGUMENTS`.
2. `--no-project` → file with no project (rare; cross-cutting work).
3. Basename of the path reported as `Git toplevel` in Context.
4. If no git repo, basename of cwd.

Cross-check the resolved name against `Known projects` and reuse the
exact spelling when it matches (case-insensitive) — taskwarrior treats
`MyRepo` and `myrepo` as different projects.

### Tag naming gotcha

**Hyphens silently break tags.** `+blocked-on-merge` is parsed as `+blocked` AND `-on-merge` (the `-` prefix is taskwarrior's exclude-filter syntax, even mid-token), so the tag never lands and the literal `+blocked-on-merge` token ends up appended to the description as plain text. The `tags` array stays null and urgency does not tick up. **Quoting (`'+blocked-on-merge'`) does not help** — this is a taskwarrior parser quirk, not a shell issue.

Use underscores or camelCase: `+blocked_on_merge`, `+blockedOnMerge`. When composing the `task add` command in Step 5, normalise any user-supplied hyphenated tags to the underscore form before invoking taskwarrior, and prefer the underscore form in any tag suggestions surfaced to the user.

| Tag form | Result |
|---|---|
| `+blocked` | tag applied |
| `+blocked_on_merge` | tag applied |
| `+blockedOnMerge` | tag applied |
| `+blocked-on-merge` | tag swallowed; literal token leaks into description |
| `'+blocked-on-merge'` | tag swallowed; literal token leaks into description |

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

If `bpid:` was given, run parallel-safe and constrain to the resolved
project so a matching `bpid` in another repo's queue is not surfaced as
a false-positive duplicate:

```bash
task project:myrepo bpid:"$BPID" export | jq '.[] | {id, description, status}'
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

Compose the taskwarrior add command from the collected inputs. Always
include `project:` (the resolved project from Parameters) unless the
user passed `--no-project`. Quote every field; tags use the `+tag` form:

```bash
task add "$DESCRIPTION" \
  project:myrepo \
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
- Project (auto-detected / overridden / `--no-project`)
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
| `project:` | Project (defaults to repo basename) |
| `--no-project` | File without a project (cross-cutting) |
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
| `+pr_ready` | Open PR waiting |
| `+blocked_on_merge` | Waiting on another PR |

## Related

- `/taskwarrior:task-status` — see current queue
- `/taskwarrior:task-done` — close an open task
- `/taskwarrior:task-coordinate` — next-agent candidates for a wave
- `.claude/rules/parallel-safe-queries.md` — why `export | jq`, never `list`
- `blueprint-plugin:feature-tracking` — FR/WO IDs that `bpid` points at
