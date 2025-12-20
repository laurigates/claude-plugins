---
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
allowed-tools: Bash, Edit, Read, Glob, Grep, Write, TodoWrite, mcp__github__create_pull_request, mcp__github__issue_read
description: Process and fix a single GitHub issue with TDD workflow
argument-hint: <issue-number>
---

## Context

- Repo: !`gh repo view --json nameWithOwner`
- Current branch: !`git branch --show-current`
- Clean working tree: !`git status --porcelain | wc -l`
- Open PRs: !`gh pr list --state open --json number,title`
- Available labels: !`gh label list --json name,description --limit 50`

## Parameters

Parse these parameters from the command (all optional):
- `--labels <label1,label2>`: Apply labels to the created PR (defaults to issue's labels if not specified)

## Your task

Process and fix GitHub issue #$1 using a TDD workflow with the **main-branch development pattern**.

### Step 1: Prepare Working Directory

1. **Ensure clean working directory** (commit or stash if needed)
2. **Switch to main and pull latest**: `git switch main && git pull`

### Step 2: Analyze Issue

1. **Fetch issue details**: Run `gh issue view $1 --json title,body,state,assignees,labels` or use `mcp__github__issue_read` with issue_number=$1
2. **Capture issue labels** for later PR creation (unless `--labels` override provided)
3. **Identify requirements** and acceptance criteria from the issue
4. **Plan the implementation** approach

### Step 3: TDD Workflow

1. **RED phase**: Write failing tests first
   - Create test file if needed
   - Write tests that define expected behavior
   - Run tests to verify they fail

2. **GREEN phase**: Implement fix
   - Write minimal code to make tests pass
   - Run tests to verify they pass

3. **REFACTOR phase**: Improve code quality
   - Clean up implementation
   - Ensure tests still pass

### Step 4: Commit and Push

1. **Stage changes**: `git add -u` and `git add <new-files>`
2. **Run pre-commit** if configured
3. **Commit on main** with message: `fix: <description>\n\nFixes #$1`
4. **Push to remote issue branch**: `git push origin main:fix/issue-$1`

### Step 5: Create PR

Use `mcp__github__create_pull_request` with:
- `head`: `fix/issue-$1`
- `base`: `main`
- `title`: From issue title with `fix:` prefix
- `body`: Include `Fixes #$1` to auto-link

After PR creation, apply labels:
```bash
# Use --labels if provided, otherwise inherit from issue
gh pr edit <pr-number> --add-label "<labels>"
```

## Main-Branch Development Pattern

```bash
# All work stays on main
git switch main && git pull
# ... make changes, commit on main ...
git push origin main:fix/issue-$1    # Push to remote feature branch
# Create PR: head=fix/issue-$1, base=main
```

## See Also

- **git-branch-pr-workflow** skill for workflow patterns
- **test-tier-selection** skill for test strategy
