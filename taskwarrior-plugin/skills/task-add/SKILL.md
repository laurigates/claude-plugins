---
name: task-add
description: Add a taskwarrior task with blueprint linkage and optional GitHub issue. Use when adding coordination tasks, linking a blueprint WO, or mirroring a GitHub issue locally.
args: "[description] [project:<name>] [--no-project] [due:<date>] [scheduled:<date>] [wait:<date>] [recur:<freq>] [until:<date>]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh issue *), Bash(gh api *), Bash(bash *), Read, TodoWrite
argument-hint: short task description
created: 2026-04-24
modified: 2026-06-20
reviewed: 2026-06-20
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
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`
- GH auth: !`gh auth status`
- Existing UDAs: !`task _udas`
- Known projects: !`task _projects`

Git probes (`git rev-parse --show-toplevel`, `git remote`) write to stderr
in a no-git cwd, and stderr from a Context backtick aborts the skill
before its body runs. Project / remote resolution is done in the body
(Step 2 below), where `2>/dev/null` and exit-code handling are available.

## Parameters

Parse `$ARGUMENTS`:

- Freeform short description (required).
- Optional inline `project:<name>` to override the auto-detected project.
- Optional `--no-project` to file the task without any project (cross-cutting work).
- Optional inline `bpid:WO-012` / `bpdoc:docs/wo/012.md` / `bpms:M6` / `ghid:145` / `ghpr:99` fields.
- Optional native scheduling fields (prefer these over manual `+blocked*` bookkeeping):
  - `due:<date>` — deadline. Feeds urgency and surfaces the task as `+DUE` / `+OVERDUE` in `task-coordinate` / `task-status`.
  - `scheduled:<date>` — earliest start. The task only becomes `+READY` once this date passes, so future work stays out of dispatch candidates.
  - `wait:<date>` — hide the task entirely until the date. Use for "blocked on merge until X" instead of a hand-managed `+blocked_on_merge` tag — taskwarrior auto-unhides it.
  - `recur:<freq>` (e.g. `weekly`, `monthly`) with a `due:` — repeating maintenance chores. Requires `due:`.
  - `until:<date>` — auto-delete the task on that date. Use for short-lived trackers that should expire if not actioned.
  - Dates accept taskwarrior synonyms (`today`, `eow`, `eom`, `monday`, `due-4d`, ISO `2026-07-01`).
- Optional tags: `+wo`, `+prp`, `+fr`, `+re`, `+gh`, `+pr_ready`, `+needs_review`, `+blocked_on_merge`, `+blocked`.

> **Tag naming gotcha — hyphens silently break tags.** Taskwarrior parses
> `-` mid-token as exclude-filter syntax, even inside a `+tag` argument.
> `+blocked-on-merge` is parsed as `+blocked` AND `-on-merge`, so the tag
> never lands and the literal `+blocked-on-merge` string ends up appended
> to the description as plain text (urgency does not tick up). Single-
> quoting (`'+blocked-on-merge'`) does **not** help — this is a taskwarrior
> parser quirk, not a shell issue. Use underscores or camelCase instead:
> `+blocked_on_merge` or `+blockedOnMerge`. The same applies to any tag
> name containing a hyphen.

### Project resolution

By default every task is filed under the current repo's project so
`/taskwarrior:task-status` and `/taskwarrior:task-coordinate` only see
tasks relevant to where the agent is working. Resolve the project in
this order:

1. Explicit `project:<name>` in `$ARGUMENTS`.
2. `--no-project` → file with no project (rare; cross-cutting work).
3. Basename of `git rev-parse --show-toplevel 2>/dev/null`, run via the
   Bash tool (where stderr suppression and non-zero exits are tolerated).
4. If no git repo (Step 3 returned empty), basename of cwd.

Cross-check the resolved name against `Known projects` and reuse the
exact spelling when it matches (case-insensitive) — taskwarrior treats
`MyRepo` and `myrepo` as different projects.

## Execution

Execute this workflow:

### Step 1: Ensure UDAs exist

The canonical 10-UDA set (5 linkage: `bpid` / `bpdoc` / `bpms` / `ghid` /
`ghpr`; 5 identity: `agent` / `pid` / `host` / `branch` / `worktree`) lives in
one place — the shared `ensure-udas.sh` script. Check for missing UDAs:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/ensure-udas.sh" --check
```

If it reports `UDAS_MISSING` greater than 0, confirm with the user (declarations
persist in `~/.taskrc`), then install them on first run per host:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/ensure-udas.sh"
```

Identity UDAs are not set by `task-add` itself — `/taskwarrior:task-claim`
stamps them when an agent picks the task up. The same script backs the
SessionStart drift-probe, so the install logic is single-sourced.

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
  due:"$DUE" \
  scheduled:"$SCHEDULED" \
  wait:"$WAIT" \
  +wo +gh
```

Run with only the fields that were provided; omit empty UDAs and empty date
fields entirely rather than passing `uda:""` / `due:""`. For a recurring chore,
pass `recur:weekly due:monday` (recurrence requires a `due:`); for a
self-expiring tracker, add `until:eom`.

#### Capture the stable UUID

After `task add` succeeds, resolve the new task's **UUID** via the
`+LATEST` virtual tag as a *separate* Bash call — never chain it to
`task add` with `&&`:

```bash
task +LATEST _get uuid
# Created task 141.
# d14a6e5e-1c60-4cfd-9dd0-8a9fe7659b74
```

> **Numeric IDs shift; UUIDs do not.** A numeric ID is a display index over
> *pending* tasks — completing any other task (often in a parallel session)
> shifts every higher ID down by one, so `task 141 annotate ...` run minutes
> after the add can silently hit a *different* task. Capture the immutable
> UUID at create time and address the task by UUID for later annotate /
> modify / done. See the user-global rule `taskwarrior-bulk-operations.md`.

#### Sequential WOs: use `depends:` for ordered chains

For work orders that must land in sequence (e.g., WO-058 → 059 → 060),
set `depends:` on each downstream task pointing to its predecessor's
taskwarrior numeric ID. When the predecessor closes with `task done`,
taskwarrior **automatically unblocks all dependents** — no manual
intervention needed (see `docs/task-tracking.md § Lifecycle`):

```bash
# WO-059 waits for WO-058 (taskwarrior ID 51)
task add "WO-059: ..." bpid:WO-059 +wo project:myrepo depends:51

# WO-060 waits for both
task add "WO-060: ..." bpid:WO-060 +wo project:myrepo depends:51,52
```

### Step 6: Report

Print:

- New task ID **and UUID** (from Step 5; quote the UUID so future agents address the task by it, not the shift-prone numeric ID)
- Project (auto-detected / overridden / `--no-project`)
- bpid → bpdoc → bpms chain
- ghid/ghpr if linked
- Tags applied
- Suggested next step (`/taskwarrior:task-status`, `/taskwarrior:task-coordinate`, or `/taskwarrior:task-claim` if the user is about to start)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Capture stable UUID after add | `task +LATEST _get uuid` |
| Duplicate check by bpid | `task bpid:WO-012 export \| jq '.[] \| {id, status}'` |
| Pre-fill from issue | `gh issue view 145 --json number,title,body,labels` |
| Next ready (unblocked + scheduled-due) | `task status:pending +READY export \| jq '.[:3]'` |
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
| `due:` | Deadline — feeds urgency, surfaces `+DUE`/`+OVERDUE` |
| `scheduled:` | Earliest start — gates `+READY` |
| `wait:` | Hide until date (auto-unhides) — prefer over `+blocked_on_merge` |
| `recur:` | Repeat frequency (needs `due:`) |
| `until:` | Auto-delete date |
| `+wo` | Work order |
| `+prp` | PRP |
| `+fr` | Feature request |
| `+re` | Research |
| `+gh` | Linked to GitHub |
| `+pr_ready` | Open PR waiting |
| `+blocked_on_merge` | Waiting on another PR |

## Related

- `/taskwarrior:task-status` — see current queue
- `/taskwarrior:task-claim` — claim a task and stamp identity UDAs
- `/taskwarrior:task-done` — close an open task (fires auto-unblock for `depends:` chains)
- `/taskwarrior:task-coordinate` — next-agent candidates for a wave
- `.claude/rules/parallel-safe-queries.md` — why `export | jq`, never `list`
- `blueprint-plugin:feature-tracking` — FR/WO IDs that `bpid` points at
- `taskwarrior-plugin/docs/task-tracking.md` — full lifecycle including `depends:` + auto-unblock pattern
