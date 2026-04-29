---
name: task-done
description: |
  Close a taskwarrior task, annotate it with the landing commit hash, drain
  the linked blueprint feature-tracker entry, and — when GitHub linkage is
  present — offer to close the linked issue or comment on the linked PR.
  Use when finishing a coordination task, marking a WO as complete, closing
  out research after findings are promoted to docs, or closing a GitHub
  issue linked via ghid.
args: "<task-id> [commit-hash]"
allowed-tools: Bash(task *), Bash(git config *), Bash(git log *), Bash(git rev-parse *), Bash(gh auth *), Bash(gh issue *), Bash(gh pr *), Read, Edit, TodoWrite
argument-hint: task id (required), commit sha (optional — defaults to HEAD)
created: 2026-04-24
modified: 2026-04-29
reviewed: 2026-04-29
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
- Git remote: !`git remote`
- GH auth: !`gh auth status`
- HEAD commit: !`git rev-parse --short HEAD`
- Current branch: !`git branch --show-current`

## Parameters

Parse `$ARGUMENTS`:

- `$0` — task ID (required)
- `$1` — commit hash (optional; defaults to `HEAD`)
- `--no-gh` — skip GitHub close/comment even when remote is present
- `--no-tracker` — skip blueprint tracker drain

## Execution

Execute this workflow:

### Step 1: Load the task

```bash
task "$TASKID" export | jq '.[0]'
```

Never use `task $TASKID info` or `task $TASKID list` — both can exit 1 and
cancel parallel siblings. `export | jq` returns valid JSON even when the
task is already closed (treat empty as "no such open task" and abort).

Capture: `bpid`, `bpdoc`, `ghid`, `ghpr`, `tags`, `description`.

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

- `/taskwarrior:task-add` — file a task
- `/taskwarrior:task-status` — see what's left
- `blueprint-plugin:feature-tracking` — tracker format that `bpdoc` points at
- `blueprint-plugin:blueprint-docs-currency` — companion discipline for the `bpdoc` update
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` idiom
