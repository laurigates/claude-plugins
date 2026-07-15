---
name: task-done
description: Close a taskwarrior task with landing commit annotation and optional GitHub issue/PR close. Use when finishing a coordination task or marking a work order complete.
args: "<task-id> [commit-hash]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git log *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh issue *), Bash(gh pr *), Read, Edit, TodoWrite
argument-hint: task id (required), commit sha (optional — defaults to HEAD)
created: 2026-04-24
modified: 2026-05-22
reviewed: 2026-05-22
---

# /taskwarrior:task-done

Close a task with full coordination hygiene: annotate with the landing commit, drain the tracker entry, optionally close the GitHub issue.

## When to Use This Skill

| Use this skill when... | Use `task-add` / `task-status` / `task-coordinate` instead when... |
|---|---|
| Closing a task whose work has landed in a commit | Filing a brand-new task — use `task-add` |
| Draining a linked blueprint tracker entry to `done` | Reading current queue state without mutating it — use `task-status` |
| Closing a `ghid`-linked GitHub issue or commenting on a `ghpr` PR | Picking the next dispatch candidate from the queue — use `task-coordinate` |
| Closing many tasks in one pass (queue cleanup, triage sweep) | See **Bulk-close patterns** below — the naive `for id in 1 2 3; do task $id done; done` loop silently closes the wrong tasks |

## Context

- Task CLI available: !`task --version`
- Git repo detected: !`find . -maxdepth 1 -name '.git' -print -quit`
- GH auth: !`gh auth status`

Git probes (`git remote`, `git rev-parse --short HEAD`,
`git branch --show-current`) write to stderr in a no-git cwd, and stderr
from a Context backtick aborts the skill before its body runs. HEAD
commit, current branch, and remote-presence checks happen in the body
(Steps 2 and 5) via the Bash tool where `2>/dev/null` and exit-code
handling are tolerated.

## Parameters

Parse `$ARGUMENTS`:

- `$0` — task ID (required)
- `$1` — commit hash (optional; defaults to `HEAD`)
- `--no-gh` — skip GitHub close/comment even when remote is present
- `--no-tracker` — skip blueprint tracker drain
- `--drain-identity` — also clear `agent` / `pid` / `host` / `branch` / `worktree` UDAs after closing (default keeps them as audit trail)
- `--no-coworker-marker` — skip the `/git:coworker-check --release` step

## Execution

Execute this workflow:

### Step 1: Load the task

```bash
task "$TASKID" export | jq '.[0]'
```

Never use `task $TASKID info` or `task $TASKID list` — both can exit 1 and
cancel parallel siblings. `export | jq` returns valid JSON even when the
task is already closed (treat empty as "no such open task" and abort).

Capture: `uuid`, `bpid`, `bpdoc`, `ghid`, `ghpr`, `tags`, `description`, plus
identity UDAs `agent`, `pid`, `host`, `branch`, `worktree`, and `start`
(if the task was claimed via `/taskwarrior:task-claim`).

Capture `uuid` as `$TASK_UUID` — every mutating call from Step 2 onward
(including the post-close Step 6 query) addresses the task by `$TASK_UUID`,
never `$TASKID` (see `.claude/rules/task-id-stability.md`).

### Step 2: Resolve commit hash

If `$1` is unset, read `git rev-parse --short HEAD`. Confirm the HEAD commit
actually touches work this task covers before annotating — a stale HEAD is
a common footgun.

### Step 3: Annotate and close

```bash
task "$TASK_UUID" annotate "landed: $COMMIT_SHORT $COMMIT_SUBJECT"
task "$TASK_UUID" done
```

Annotation first, then done — if close fails (e.g. dependencies), the
annotation is still captured.

Taskwarrior auto-stops a `+ACTIVE` task on `done`, so an explicit
`task stop` is not needed. The task transition removes `+ACTIVE` and
records the duration. If you want to drain the identity UDAs (so the
closed task does not retain the stamp), do so separately after the
close — see Step 4b below.

### Step 4b: Drain identity UDAs (optional)

After the task is closed, optionally clear the identity stamp left by
the original claim:

```bash
task "$TASK_UUID" modify agent: pid: host: branch: worktree:
```

Default behaviour is to **leave** these set on closed tasks — the audit
trail of "who claimed and landed this" is useful in `task-status`
recently-completed reports. Drain them only when the user explicitly
asks (e.g. compliance / privacy hygiene), or when handing the queue
file off to another team.

### Step 4: Drain the blueprint tracker

If `bpdoc` is set and points to a valid path, read the file and advance
its status marker in place. Typical patterns by tracker format:

- Feature-tracker JSON: `status: in_progress` → `status: done`, append
  evidence entry citing the commit
- Work-order markdown: check off the relevant bullet, add landed-in line
- PRP: flip the "Implementation" status field

Use `Edit` with a narrow `old_string` / `new_string` pair — do not rewrite
the file. When `bpdoc` references a shared tracker (manifest.json, global
feature-tracker), fall back to reporting "manual tracker update required"
rather than concurrent-write the shared file.

### Step 5: Close linked GitHub items (optional)

When GitHub mode is active and `--no-gh` was not passed:

- `ghid` set → offer `gh issue close "$GHID" --comment "Closed by $COMMIT_SHORT (branch $BRANCH)"`
- `ghpr` set → offer `gh pr comment "$GHPR" --body "Linked task closed: $COMMIT_SHORT"`

Always confirm before mutating GitHub state — the user may want to close
the issue as part of the PR merge rather than ahead of time.

### Step 5b: Drop the coworker-check marker

If the task was `+ACTIVE` (claimed via `/taskwarrior:task-claim`), the
matching git-side session marker should be released so destructive ops
in this clone are no longer guarded:

```
Use SlashCommand to invoke `/git:coworker-check --release`.
```

Skip when the user has more work in flight on this branch — releasing
the marker lifts the cross-agent guard.

### Step 6: Report

Print:

- Task closed: id + description + new status
- Commit annotated: `$COMMIT_SHORT`
- Tracker drained: path + diff summary, or "skipped"
- GitHub: "issue #N closed" / "PR #N commented" / "skipped"
- Unblocked siblings: any tasks whose `depends:` pointed at this one now
  free to start (query via `task depends:"$TASK_UUID" export | jq`). Once
  completed, this task's numeric `id` becomes `0` and may be reassigned to
  an unrelated task — a query keyed on the stale `$TASKID` here would check
  dependencies against the wrong task. `depends:` accepts UUIDs, so
  `$TASK_UUID` is the only safe form for this **read**.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Load task | `task "$TASKID" export \| jq '.[0]'` (capture `.uuid` as `$TASK_UUID`) |
| Annotate + close | Two separate calls (hook-friendly), both by `$TASK_UUID` |
| Blocked children | `task depends:"$TASK_UUID" export \| jq '.[]'` |
| Skip empty-result failures | Always `export \| jq` |

## Quick Reference

| Step | Command |
|------|---------|
| Load | `task TASKID export \| jq` (capture `uuid`) |
| Annotate | `task UUID annotate "msg"` |
| Close | `task UUID done` |
| Check unblocked siblings | `task depends:UUID export \| jq '.[]'` |
| GitHub close | `gh issue close N --comment "msg"` |
| PR comment | `gh pr comment N --body "msg"` |

## Bulk-close patterns

Closing many tasks in one pass has two silent foot-guns. The obvious shape — `for id in 1 2 3; do task $id done; done` — reports success while doing the wrong thing.

### Foot-gun 1: numeric IDs renumber after every `task done`

Numeric IDs are a display index over **pending** tasks. The moment one closes, every higher ID shifts down by one. A loop over numeric IDs closes the original first task, then keeps targeting wrong tasks as IDs slide underneath the iterator. No error surfaces.

**Fix: use UUIDs** (immutable). The same applies to any iterated state-changing op — `annotate`, `modify`, `delete`.

```sh
# WRONG — IDs shift mid-loop
for id in 35 36 37 38 39; do task "$id" done; done

# Correct — capture immutable UUIDs first
UUIDS=$(task status:pending project:myrepo export | jq -r '.[].uuid')
for u in $UUIDS; do task "$u" done </dev/null; done    # stdin redirect — see below
```

### Foot-gun 2: `task done` consumes loop stdin

`task done` reads from stdin (for confirmation prompts). In a shell `for` loop, the loop's input is *also* stdin — so `task done` eats subsequent iterations and the loop exits early, usually after one or two passes, with no error.

Symptom: a loop over 15 UUIDs reports "processed 15" but only 1 task closed.

```sh
# Fix A — redirect stdin per inner command
for u in $UUIDS; do
  task "$u" rc.confirmation=no done </dev/null
done

# Fix B — xargs (preferred; each invocation runs in its own subshell with no
# stdin link to the source loop)
echo "$UUIDS" | xargs -I {} sh -c 'task rc.confirmation=no {} done'
```

### Always pass `rc.confirmation=no` for batch closes

Without it, taskwarrior may prompt "this task is blocked by N other tasks, complete anyway? (yes/no)" per task, hanging the loop. `rc.confirmation=no` makes batch closes deterministic.

### Annotate before `done`, not after

Once `completed`, a task's `id` becomes 0 and `task <id>` no longer addresses it — only the UUID does. Annotate first to keep the UUID-or-ID workflow uniform.

### Finding tasks for the bulk close

Use `export | jq` (never `list` — it exits 1 on empty filters and cancels parallel siblings; see `.claude/rules/parallel-safe-queries.md`):

```sh
task status:pending project:myrepo +pr_ready export | jq -r '.[].uuid'

# Tasks with no project (CLI filter quirk — empty value as first filter
# errors; sidestep through jq)
task status:pending export | jq -r '.[] | select(.project == null) | .uuid'

# Substring matches on description (for markers that aren't real tags)
task status:pending export \
  | jq -r '.[] | select(.description | test("\\[triage\\]")) | .uuid'
```

### Canonical pattern

```sh
UUIDS=$(task status:pending project:myrepo +pr_ready export | jq -r '.[].uuid')
echo "$UUIDS" | xargs -I {} sh -c 'task rc.confirmation=no {} done'
```

## Related

- `/taskwarrior:task-add` — file a task (use `depends:` for sequential WO chains)
- `/taskwarrior:task-claim` — claim a task before working on it (this skill closes a claimed task)
- `/taskwarrior:task-release` — release a claim without closing (handoff)
- `/taskwarrior:task-status` — see what's left
- `/git:coworker-check` — the matching session marker that `--no-coworker-marker` controls
- `blueprint-plugin:feature-tracking` — tracker format that `bpdoc` points at
- `blueprint-plugin:blueprint-docs-currency` — companion discipline for the `bpdoc` update
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` idiom
- `.claude/rules/task-id-stability.md` — why this skill resolves `$TASK_UUID` once and mutates by UUID
- `taskwarrior-plugin/docs/task-tracking.md` — full lifecycle: `depends:` + auto-unblock pattern
