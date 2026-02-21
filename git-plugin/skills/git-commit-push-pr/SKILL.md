---
model: sonnet
name: git-commit-push-pr
created: 2025-12-16
modified: 2026-02-20
reviewed: 2026-02-20
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git branch *), Bash(git remote *), Bash(gh pr *), Bash(gh label *), Bash(gh repo *), Bash(gh issue *), Bash(pre-commit *), Bash(find *), Read, Edit, Grep, Glob, TodoWrite, mcp__github__create_pull_request, mcp__github__list_issues, mcp__github__get_issue
args: "[remote-branch] [--push] [--direct] [--pr] [--draft] [--issue <num>] [--no-commit] [--range <start>..<end>] [--skip-issue-detection]"
argument-hint: [remote-branch] [--push] [--direct] [--pr] [--draft] [--issue <num>] [--no-commit] [--range <start>..<end>] [--skip-issue-detection]
description: Complete workflow from changes to PR - auto-detect related issues, create logical commits with proper issue linkage, push to remote feature branch, and optionally create pull request
---

## Context

- Pre-commit config: !`find . -maxdepth 1 -name ".pre-commit-config.yaml" 2>/dev/null`
- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch 2>/dev/null`
- Unstaged changes: !`git diff --numstat 2>/dev/null`
- Staged changes: !`git diff --cached --numstat 2>/dev/null`
- Recent commits: !`git log --format='%h %s' -n 10`
- Remote: !`git remote get-url origin 2>/dev/null`
- Available labels: !`gh label list --json name --limit 50 2>/dev/null`
- Open issues: !`gh issue list --state open --json number,title,labels --limit 30 2>/dev/null`

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

**5a. Identify post-merge follow-up actions.**

Before creating the PR, scan commit messages, diff context, and any conversation context for actions that must happen **after** the PR is merged:

| Signal | Examples |
|--------|---------|
| Commit messages | "migration", "run after deploy", "manual step", "update config" |
| File patterns | `*.sql`, migration files, deployment scripts, runbooks |
| Context | User mentioned a deployment step, documentation update, or announcement |

For each post-merge action identified, create a GitHub issue — **not a PR checklist item**. PR descriptions are closed and buried once a PR merges; issues remain open until resolved.

```bash
gh issue create \
  --title "[Chore] DB: Run migration for new schema" \
  --body "Follow-up to <PR-URL>.\n\nRun: rake db:migrate in production after deploy." \
  --label "chore"
# Note the returned issue number for the PR body
```

Common follow-up types: database migrations, production deployments, manual config changes, external documentation updates, customer-facing announcements, dependent follow-on PRs.

**5b. Create the PR**, including follow-up issue links in the body.

Use `mcp__github__create_pull_request` with:
- `head`: The remote branch name (e.g., `feat/auth-oauth2`)
- `base`: `main`
- `title`: Derived from commit message
- `body`: Include summary, issue link if --issue provided, and a **Follow-up Issues** section listing any issues created in 5a
- `draft`: true if --draft flag set

PR body structure when follow-up issues exist:

```markdown
## Summary
...

## Follow-up Issues
<!-- Post-merge actions tracked as issues so they survive PR closure -->
- #456: run database migration for new schema
- #457: update production feature-flag config

## Related Issues
Fixes #123
```

If `--labels` provided, add labels after PR creation:
```bash
gh pr edit <pr-number> --add-label "label1,label2"
```

### Step 6: Watch PR Checks (if --pr)

After PR creation, watch CI checks to confirm the PR is ready for merge:

```bash
gh pr checks <pr-number> --watch --fail-fast --required
```

- `--watch`: Block until all checks complete (polls every 10s)
- `--fail-fast`: Exit immediately on first check failure
- `--required`: Only watch required checks (skip optional/informational)

**On success (exit 0)**:
- Report: "All required checks passed. PR #N is ready for merge."
- Provide merge command: `gh pr merge <pr-number> --squash --delete-branch`

**On failure (exit 1)**:
- Report which check(s) failed with details:
  ```bash
  gh pr checks <pr-number> --required --json name,state,bucket,link --jq '.[] | select(.bucket == "fail")'
  ```
- Suggest: review failed check logs, fix issues, push again

**On pending timeout** (exit 8):
- Report: "Checks still running. Monitor with: `gh pr checks <pr-number> --watch`"

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
