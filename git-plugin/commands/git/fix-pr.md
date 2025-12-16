---
allowed-tools: Bash, Edit, Read, Glob, Grep, Write, TodoWrite, mcp__github__pull_request_read
argument-hint: [pr-number] [--auto-fix] [--push]
description: Analyze and fix failing PR checks
---

## Context

- Get repo name with owner: !`gh repo view --json nameWithOwner`
- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Parameters

Parse these parameters from the command (all optional):
- `$1`: PR number (if not provided, detect from current branch)
- `--auto-fix`: Automatically apply fixes for common issues
- `--push`: Push fixes to the branch after committing

## Your task

Analyze and fix failing PR checks.

### Step 1: Determine PR

1. **Get PR number** from argument or detect from current branch
2. **Fetch PR status** using `gh pr checks <pr-number>` or mcp__github__pull_request_read

### Step 2: Analyze Failures

1. **Identify failing checks** from PR status
2. **Research error messages** in workflow logs
3. **Categorize failures**:
   - Linting errors
   - Type errors
   - Test failures
   - Build errors

### Step 3: Reproduce Locally

1. **Run tests locally** to reproduce issues
2. **Run linters** to check for style issues
3. **Run type checker** if applicable

### Step 4: Apply Fixes (if --auto-fix)

Based on failure type:

- **Linting errors**: Run appropriate linters/formatters
  ```bash
  # Python
  uv run ruff check --fix .
  uv run ruff format .

  # JavaScript/TypeScript
  npm run lint -- --fix
  ```

- **Type errors**: Fix type annotations or implementations
- **Test failures**: Fix failing tests or implementation bugs

### Step 5: Commit and Push (if --push)

1. **Stage fixes**: `git add -u`
2. **Commit**: `git commit -m "fix: resolve CI failures"`
3. **Push**: `git push`

### Step 6: Verify

1. **Re-run checks** locally to verify fixes
2. **Monitor PR checks** after push

## Common Fix Patterns

| Check Type | Common Fixes |
|------------|--------------|
| Linting | Run formatter, fix import order |
| Types | Add type annotations, fix mismatches |
| Tests | Fix assertions, update snapshots |
| Build | Fix imports, resolve dependencies |

## See Also

- **github-actions-inspection** skill for workflow analysis
- **git-branch-pr-workflow** skill for PR patterns
