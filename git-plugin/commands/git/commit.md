---
allowed-tools: Bash, Edit, Read, Glob, Grep, TodoWrite, mcp__github__create_pull_request
argument-hint: [remote-branch] [--push] [--direct] [--pr] [--draft] [--issue <num>] [--no-commit] [--range <start>..<end>]
description: Complete workflow from changes to PR - analyze changes, create logical commits, push to remote feature branch, and optionally create pull request
---

## Context

- Pre-commit config: !`find . -maxdepth 1 -name ".pre-commit-config.yaml"`
- Current branch: !`git branch --show-current`
- Git status: !`git status --short`
- Unstaged changes: !`git diff --stat`
- Staged changes: !`git diff --cached --stat`
- Recent commits: !`git log --oneline -10`
- Remote status: !`git remote -v | head -1`
- Upstream status: !`git status -sb | head -1`

## Parameters

Parse these parameters from the command (all optional):

- `$1`: Remote branch name to push to (e.g., `feat/auth-oauth2`). If not provided, auto-generate from first commit type. Ignored with `--direct`.
- `--push`: Automatically push after commits
- `--direct`: Push current branch directly to same-named remote (e.g., `git push origin main`). Mutually exclusive with `--pr`.
- `--pr` / `--pull-request`: Create pull request after pushing (implies --push, uses feature branch pattern)
- `--draft`: Create as draft PR (requires --pr)
- `--issue <num>`: Link to specific issue number (requires --pr)
- `--no-commit`: Skip commit creation (assume commits already exist)
- `--range <start>..<end>`: Push specific commit range instead of all commits on main

## Your task

Execute this commit workflow using the **main-branch development pattern**:

### Step 1: Verify State

1. **Check branch**: If `--direct`, any branch is valid. Otherwise, verify on main branch (warn if not).
2. **Check for changes**: Confirm there are staged or unstaged changes to commit (unless --no-commit)

### Step 2: Create Commits (unless --no-commit)

1. **Analyze changes** and detect if splitting into multiple PRs is appropriate
2. **Group related changes** into logical commits on main
3. **Stage changes**: Use `git add -u` for modified files, `git add <file>` for new files
4. **Run pre-commit hooks** if configured: `pre-commit run`
5. **Handle pre-commit modifications**: Stage any files modified by hooks with `git add -u`
6. **Create commit** with conventional commit message format
7. **ALWAYS include GitHub issue references** in commit messages:
   - **Closing keywords** (auto-close when merged to default branch):
     - `Fixes #N` - for bug fixes that resolve an issue
     - `Closes #N` - for features that complete an issue
     - `Resolves #N` - alternative closing keyword
   - **Reference without closing** (for related context):
     - `Refs #N` - references issue without closing
     - `Related to #N` - indicates relationship
   - **Cross-repository references**:
     - `Fixes owner/repo#N` - closes issue in different repo
   - **Multiple issues**: `Fixes #1, fixes #2, fixes #3`
   - Keywords are case-insensitive and work with optional colon: `Fixes: #123`

### Step 3: Push to Remote (if --push or --pr)

**If `--direct`**: Push current branch to same-named remote:

```bash
# Direct push to current branch
git push origin HEAD
```

**Otherwise** (feature branch pattern for PRs):

```bash
# Push main to remote feature branch
git push origin main:<remote-branch>

# Or push commit range for multi-PR workflow
git push origin <start>^..<end>:<remote-branch>
```

### Step 4: Create PR (if --pr)

Use `mcp__github__create_pull_request` with:
- `head`: The remote branch name (e.g., `feat/auth-oauth2`)
- `base`: `main`
- `title`: Derived from commit message
- `body`: Include summary and issue link if --issue provided
- `draft`: true if --draft flag set

## Workflow Guidance

- After running pre-commit hooks, stage files modified by hooks using `git add -u`
- Unstaged changes after pre-commit are expected formatter output - stage them and continue
- **Direct mode** (`--direct`): Use `git push origin HEAD` to push current branch directly
- **Feature branch mode** (default): Use `git push origin main:<remote-branch>` for PR workflow
- For multi-PR workflow, use `git push origin <start>^..<end>:<remote-branch>` for commit ranges
- When encountering unexpected state, report findings and ask user how to proceed
- Include all pre-commit automatic fixes in commits
- **GitHub issue references (REQUIRED)**: Every commit should reference related issues:
  - **Closing keywords** (`Fixes`, `Closes`, `Resolves`) auto-close issues when merged to default branch
  - **Reference keywords** (`Refs`, `Related to`, `See`) link without closing - use for partial work
  - Format examples: `Fixes #123`, `Fixes: #123`, `fixes org/repo#123`
  - Multiple issues: `Fixes #1, fixes #2, fixes #3` (repeat keyword for each)
  - When `--issue <num>` provided, use `Fixes #<num>` or `Closes #<num>` in commit body
  - If no specific issue exists, consider creating one first for traceability

## See Also

- **git-branch-pr-workflow** skill for detailed patterns
- **git-commit-workflow** skill for commit message conventions
