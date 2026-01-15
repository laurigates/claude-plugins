---
created: 2025-12-16
modified: 2026-01-15
reviewed: 2026-01-15
allowed-tools: Bash, Edit, Read, Glob, Grep, TodoWrite, mcp__github__create_pull_request, mcp__github__list_issues, mcp__github__get_issue
argument-hint: [remote-branch] [--push] [--direct] [--pr] [--draft] [--issue <num>] [--no-commit] [--range <start>..<end>] [--skip-issue-detection]
description: Complete workflow from changes to PR - auto-detect related issues, create logical commits with proper issue linkage, push to remote feature branch, and optionally create pull request
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
- Available labels: !`gh label list --json name,description --limit 50 2>/dev/null || echo "(no remote configured)"`
- Open issues: !`gh issue list --state open --json number,title,labels --limit 30 2>/dev/null || echo "(no remote configured)"`

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
- `--labels <label1,label2>`: Apply labels to the created PR (requires --pr)
- `--skip-issue-detection`: Skip automatic issue detection (use when --issue is provided or for trivial changes)

## Your task

Execute this commit workflow using the **main-branch development pattern**:

### Step 1: Verify State

1. **Check branch**: If `--direct`, any branch is valid. Otherwise, verify on main branch (warn if not).
2. **Check for changes**: Confirm there are staged or unstaged changes to commit (unless --no-commit)

### Step 2: Auto-Detect Related Issues (unless --skip-issue-detection or --issue provided)

**Purpose**: Automatically identify open GitHub issues that the staged changes may fix or close.

1. **Analyze staged changes**:
   - Get list of changed files: `git diff --cached --name-only`
   - Extract modified directories, file names, and content patterns
   - Identify error messages, function names, or keywords in the diff

2. **Match against open issues**:
   - Review the open issues from context (or fetch with `gh issue list --state open`)
   - Score each issue based on:
     - **High confidence**: File path mentioned in issue body, error message match
     - **Medium confidence**: Directory/component match, keyword overlap
     - **Low confidence**: Label matches changed area (e.g., `bug` label + fix changes)

3. **Report detected issues**:
   ```
   Detected potentially related issues:

   HIGH CONFIDENCE:
   - #123 "Login fails with invalid token" → Fixes #123
     Match: Changes to src/auth/token.ts, issue mentions token validation

   MEDIUM CONFIDENCE:
   - #456 "Improve error messages" → Refs #456
     Match: Error handling changes in src/auth/

   Suggested closing keywords for commit message:
   Fixes #123
   Refs #456
   ```

4. **Determine appropriate keywords**:
   - Use `Fixes #N` for bug fixes that fully resolve the issue
   - Use `Closes #N` for features that complete the issue
   - Use `Refs #N` for partial progress or related changes
   - See **github-issue-autodetect** skill for decision tree

5. **Confirm with user** (if uncertain):
   - For high-confidence matches, include automatically
   - For medium-confidence, suggest and confirm
   - For low-confidence, mention but let user decide

### Step 3: Create Commits (unless --no-commit)

1. **Analyze changes** and detect if splitting into multiple PRs is appropriate
2. **Group related changes** into logical commits on main
3. **Stage changes**: Use `git add -u` for modified files, `git add <file>` for new files
4. **Run pre-commit hooks** if configured: `pre-commit run`
5. **Handle pre-commit modifications**: Stage any files modified by hooks with `git add -u`
6. **Create commit** with conventional commit message format
7. **Include detected issue references** from Step 2 in the commit message footer:
   - Add high-confidence matches automatically
   - Include medium-confidence matches if confirmed
8. **ALWAYS include GitHub issue references** in commit messages:
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

### Step 4: Push to Remote (if --push or --pr)

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

### Step 5: Create PR (if --pr)

Use `mcp__github__create_pull_request` with:
- `head`: The remote branch name (e.g., `feat/auth-oauth2`)
- `base`: `main`
- `title`: Derived from commit message
- `body`: Include summary and issue link if --issue provided
- `draft`: true if --draft flag set

If `--labels` provided, add labels after PR creation:
```bash
gh pr edit <pr-number> --add-label "label1,label2"
```

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

- **github-issue-autodetect** skill for issue detection algorithm and keyword selection
- **git-branch-pr-workflow** skill for detailed patterns
- **git-commit-workflow** skill for commit message conventions
