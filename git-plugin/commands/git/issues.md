---
allowed-tools: Bash, Edit, Read, Glob, Grep, Write, TodoWrite, mcp__github__create_pull_request, mcp__github__list_issues
description: Process multiple GitHub issues in sequence
argument-hint: [--filter <label>] [--limit <n>]
---

## Context

- Repo: !`gh repo view --json nameWithOwner`
- Open issues: !`gh issue list --state open --json number,title,labels`
- Open PRs: !`gh pr list --state open --json number,title,state`
- Current branch: !`git branch --show-current`

## Parameters

Parse these parameters from the command (all optional):
- `--filter <label>`: Filter issues by label
- `--limit <n>`: Maximum number of issues to process

## Your task

Process multiple GitHub issues in sequence using the **main-branch development pattern**.

### Step 1: Prepare

1. **Check for unmerged PRs** and prompt user if found
2. **Filter issues** based on --filter label if provided
3. **Limit issue count** based on --limit if provided
4. **Create todo list** with all issues to process

### Step 2: For Each Issue

Repeat for each open issue:

1. **Pull latest main**: `git pull origin main`
2. **Analyze issue requirements** from issue details
3. **Write failing tests** (RED phase)
4. **Implement fix** until tests pass (GREEN phase)
5. **Run pre-commit checks** if configured
6. **Commit on main** with `Fixes #<number>` in message
7. **Push to remote issue branch**: `git push origin main:fix/issue-<number>`
8. **Create PR** via mcp__github__create_pull_request:
   - `head`: `fix/issue-<number>`
   - `base`: `main`
   - `body`: Include `Fixes #<number>`
9. **Continue on main** for next issue

### Step 3: Summary

Report:
- Issues processed
- PRs created
- Any issues that couldn't be resolved

## Main-Branch Development Pattern

```bash
# All work stays on main - each issue gets its own remote branch
git pull origin main
# ... fix issue, commit on main ...
git push origin main:fix/issue-123    # Push to remote feature branch
# Create PR: head=fix/issue-123, base=main
# Continue on main for next issue
```

## See Also

- **/git:issue** for single issue processing
- **git-branch-pr-workflow** skill for workflow patterns
