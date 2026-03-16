---
model: sonnet
created: 2026-01-30
modified: 2026-03-16
reviewed: 2026-02-26
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh run view *), Bash(gh run list *), Bash(gh api *), Bash(gh repo view *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git switch *), Bash(git pull *), Bash(pre-commit *), Bash(npm run *), Bash(uv run *), Read, Edit, Write, Grep, Glob, TodoWrite, Task, mcp__github__pull_request_read
args: "[pr-number] [--commit] [--push]"
argument-hint: [pr-number] [--commit] [--push]
disable-model-invocation: true
description: Review PR workflow results and comments, then address substantive feedback and suggestions from reviewers
name: git-pr-feedback
context: fork
agent: general-purpose
---

## Context

- Repo: !`git remote -v`
- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`
- Staged changes: !`git diff --cached --numstat`
- Unstaged changes: !`git diff --numstat`
- Recent commits: !`git log --format='%h %s' --max-count=5`

## Parameters

Parse these parameters from the command (all optional):

| Parameter | Description |
|-----------|-------------|
| `$1` | PR number (if not provided, detect from current branch) |
| `--commit` | Create commit(s) after addressing feedback |
| `--push` | Push changes after committing (implies --commit) |

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| A PR has reviewer comments to address | CI checks are failing with no review comments → use `git-fix-pr` |
| You need to systematically work through review feedback | You're creating a new PR → use `git-commit-push-pr` |
| A reviewer has requested changes | You want to understand PR workflow patterns → use `git-branch-pr-workflow` |
| You want to address both CI failures and reviewer feedback together | |

## Your Task

Review PR workflow results and reviewer comments, then address substantive feedback.

---

### Step 1: Determine PR

1. **Get PR number** from argument or detect from current branch:
   ```bash
   gh pr view --json number -q '.number'
   ```

2. **Verify branch alignment**: Ensure you're on the correct branch for the PR:
   ```bash
   gh pr view $PR --json headRefName -q '.headRefName'
   ```

3. **Switch to PR branch** if not already on it:
   ```bash
   git switch <branch-name>
   git pull origin <branch-name>
   ```


### Step 2: Gather PR Status

Collect comprehensive information about the PR:

#### 2a. Workflow/Check Results

```bash
# Get check status summary
gh pr checks $PR --json name,state,conclusion,detailsUrl

# For failed checks, get detailed logs
gh run view $RUN_ID --log-failed
```

**Categorize check results:**

| Status | Action |
|--------|--------|
| All passing | Skip to Step 3 (comments) |
| Failed CI | Analyze failures, may need fixes |
| Pending | Note status, focus on comments |

#### 2b. Rate Limit Pre-check

Before making API calls, check remaining rate limit:

```bash
gh api rate_limit --jq '.resources.core | "Remaining: \(.remaining)/\(.limit) | Resets: \(.reset)"'
```

If remaining requests are low (< 10), warn about rate limits and use `--cache` aggressively.

#### 2c. PR Reviews and Comments

Use `--cache 5m` on all `gh api` calls to avoid redundant requests (especially on retries or re-runs). If any `gh api` call fails with a rate limit error, wait 60 seconds and retry (up to 2 retries).

```bash
# Get review comments (inline code comments)
gh api --cache 5m repos/{owner}/{repo}/pulls/$PR/comments --jq '.[] | {path: .path, line: .line, body: .body, user: .user.login, state: .state}'

# Get review summaries (approve/request changes/comment)
gh api --cache 5m repos/{owner}/{repo}/pulls/$PR/reviews --jq '.[] | {user: .user.login, state: .state, body: .body}'

# Get issue-style comments (general discussion)
gh api --cache 5m repos/{owner}/{repo}/issues/$PR/comments --jq '.[] | {user: .user.login, body: .body, created_at: .created_at}'
```

**Rate limit retry pattern** (use for any `gh api` call that fails):
```bash
# If gh api returns "rate limit" error, retry with backoff
for i in 1 2 3; do
  result=$(gh api --cache 5m repos/{owner}/{repo}/pulls/$PR/comments --jq '...' 2>&1) && break
  echo "$result" | grep -qi "rate limit" || break
  echo "Rate limited, waiting $((i * 30))s..."
  sleep $((i * 30))
done
```

---

### Step 3: Analyze Feedback

Create a structured analysis of all feedback:

#### 3a. Categorize Comments

| Category | Description | Priority |
|----------|-------------|----------|
| **Blocking** | "Request changes" reviews, critical bugs | Must address |
| **Substantive** | Code improvements, logic issues, missing tests | Should address |
| **Suggestions** | Style preferences, optional enhancements | Consider |
| **Questions** | Clarification requests | Respond inline |
| **Nitpicks** | Minor style/formatting | Low priority |
| **Resolved** | Already addressed or outdated | Skip |

#### 3b. Identify Actionable Items

For each comment, determine:

1. **Is it actionable?** (code change vs discussion)
2. **Location**: File and line number (for inline comments)
3. **Scope**: Single line fix vs broader refactor
4. **Dependencies**: Does it affect other changes?

**Create a todo list** using TodoWrite with all actionable items.


### Step 4: Address Feedback

Work through the actionable items systematically:

#### 4a. For Code Review Comments

1. **Read the relevant code** at the specified location
2. **Understand the context** of the reviewer's concern
3. **Implement the fix** following their suggestion or your improved approach
4. **Verify the change** doesn't break existing functionality

#### 4b. For Failed CI Checks

1. **Identify the failure type**:
   - Linting errors → Run formatters/linters
   - Type errors → Fix type annotations
   - Test failures → Fix tests or implementation
   - Build errors → Resolve dependency/import issues

2. **Run locally** to verify fix:
   ```bash
   # Examples based on project type
   npm run lint -- --fix
   npm run typecheck
   npm test

   uv run ruff check --fix .
   uv run pytest
   ```

#### 4c. For Questions/Clarifications

If a comment requires explanation rather than code change:
- Note that you should reply to the comment after pushing
- Consider if documentation/comments would help future readers

---

### Step 5: Commit Changes (if --commit or --push)

1. **Group related fixes** into logical commits:
   ```bash
   # Stage specific files for each commit
   git add <files-for-fix-1>
   git commit -m "fix: address review feedback - <specific change>"
   ```

2. **Commit message format**:
   ```
   fix: address PR review feedback

   - <Change 1 description>
   - <Change 2 description>

   Co-authored-by: <reviewer> (if they provided specific code)
   ```

3. **Run pre-commit hooks** if configured:
   ```bash
   pre-commit run --all-files
   git add -u  # Stage any formatter changes
   ```


### Step 6: Push Changes (if --push)

```bash
git push origin HEAD
```

---

### Step 7: Summary Report

Provide a summary of actions taken:

```markdown
## PR Feedback Summary

### Workflow Status
- CI Checks: [PASS/FAIL] - <details>
- Review Status: [Approved/Changes Requested/Pending]

### Feedback Addressed

| Category | Count | Status |
|----------|-------|--------|
| Blocking | N | ✅ Resolved |
| Substantive | N | ✅ Resolved |
| Suggestions | N | ✅/⏭️ Addressed/Deferred |
| Questions | N | 💬 Need response |

### Changes Made
- <File 1>: <description of change>
- <File 2>: <description of change>

### Next Steps
- [ ] Reply to clarification questions on PR
- [ ] Re-request review from <reviewer>
- [ ] Monitor CI for new run
```


## Decision Tree: Handling Different Feedback Types

```
Is it a "Request Changes" review?
├─ Yes → Must address all blocking concerns
└─ No → Is it an inline code comment?
         ├─ Yes → Does it suggest a specific fix?
         │        ├─ Yes → Implement the suggestion (or better alternative)
         │        └─ No → Analyze and determine best fix
         └─ No → Is it a general comment/question?
                  ├─ Yes → Note for PR reply
                  └─ No → Is it a resolved/outdated comment?
                           ├─ Yes → Skip
                           └─ No → Evaluate importance
```

---

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check status | `gh pr checks $PR --json name,state,conclusion` |
| Failed check logs | `gh run view $ID --log-failed` |
| Rate limit check | `gh api rate_limit --jq '.resources.core.remaining'` |
| Review comments | `gh api --cache 5m repos/{owner}/{repo}/pulls/$PR/comments` |
| Review summaries | `gh api --cache 5m repos/{owner}/{repo}/pulls/$PR/reviews` |
| PR discussion | `gh api --cache 5m repos/{owner}/{repo}/issues/$PR/comments` |


## See Also

- **/git:fix-pr** - Focus on CI failures specifically
- **gh-cli-agentic** skill - Optimized GitHub CLI patterns
- **git-branch-pr-workflow** skill - PR workflow patterns
