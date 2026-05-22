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

Capture: `bpid`, `bpdoc`, `ghid`, `ghpr`, `tags`, `description`, plus
identity UDAs `agent`, `pid`, `host`, `branch`, `worktree`, and `start`
(if the task was claimed via `/taskwarrior:task-claim`).

### Step 2: Resolve commit hash

If `$1` is unset, read `git rev-parse --short HEAD`. Confirm the HEAD commit
actually touches work this task covers before annotating — a stale HEAD is
a common footgun.

### Step 3: Annotate and close

```bash
task "$TASKID" annotate "landed: $COMMIT_SHORT $COMMIT_SUBJECT"
task "$TASKID" done
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
task "$TASKID" modify agent: pid: host: branch: worktree:
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
  free to start (query via `task depends:$TASKID export | jq`)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Load task | `task "$TASKID" export \| jq '.[0]'` |
| Annotate + close | Two separate calls (hook-friendly) |
| Blocked children | `task depends:"$TASKID" export \| jq '.[]'` |
| Skip empty-result failures | Always `export \| jq` |

## Quick Reference

| Step | Command |
|------|---------|
| Load | `task ID export \| jq` |
| Annotate | `task ID annotate "msg"` |
| Close | `task ID done` |
| Check unblocked siblings | `task depends:ID export \| jq '.[]'` |
| GitHub close | `gh issue close N --comment "msg"` |
| PR comment | `gh pr comment N --body "msg"` |

## Related

- `/taskwarrior:task-add` — file a task (use `depends:` for sequential WO chains)
- `/taskwarrior:task-claim` — claim a task before working on it (this skill closes a claimed task)
- `/taskwarrior:task-release` — release a claim without closing (handoff)
- `/taskwarrior:task-status` — see what's left
- `/git:coworker-check` — the matching session marker that `--no-coworker-marker` controls
- `blueprint-plugin:feature-tracking` — tracker format that `bpdoc` points at
- `blueprint-plugin:blueprint-docs-currency` — companion discipline for the `bpdoc` update
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` idiom
- `taskwarrior-plugin/docs/task-tracking.md` — full lifecycle: `depends:` + auto-unblock pattern
