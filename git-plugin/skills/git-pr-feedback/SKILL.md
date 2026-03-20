---
model: sonnet
created: 2026-01-30
modified: 2026-03-20
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

### Step 1: Determine PR and Gather All Data (Single Query)

**CRITICAL: Use a single GraphQL query to fetch PR details, reviews, review comments, and issue comments. This reduces ~7 API calls to 1-2, avoiding rate limits.**

1. **Get PR number** from argument or detect from current branch:
   ```bash
   gh pr view --json number -q '.number'
   ```

2. **Switch to PR branch** if not already on it:
   ```bash
   gh pr view $PR --json headRefName -q '.headRefName'
   # If not on the right branch:
   git switch <branch-name>
   git pull origin <branch-name>
   ```

3. **Fetch ALL PR data in a single GraphQL query** — this is the key to avoiding rate limits:

   ```bash
   gh api graphql -f query='
   query($owner: String!, $repo: String!, $pr: Int!) {
     repository(owner: $owner, name: $repo) {
       pullRequest(number: $pr) {
         number
         headRefName
         state
         reviewDecision
         commits(last: 1) {
           nodes {
             commit {
               statusCheckRollup {
                 state
                 contexts(first: 50) {
                   nodes {
                     ... on CheckRun {
                       name
                       conclusion
                       status
                       detailsUrl
                     }
                   }
                 }
               }
             }
           }
         }
         reviews(first: 50) {
           nodes {
             author { login }
             state
             body
           }
         }
         reviewThreads(first: 100) {
           nodes {
             isResolved
             comments(first: 20) {
               nodes {
                 path
                 line
                 body
                 author { login }
               }
             }
           }
         }
         comments(first: 100) {
           nodes {
             author { login }
             body
             createdAt
           }
         }
       }
     }
   }' -F owner='{owner}' -F repo='{repo}' -F pr=$PR
   ```

   Parse `{owner}` and `{repo}` from the git remote URL.

4. **For failed checks only**, fetch detailed logs (this requires REST):
   ```bash
   gh run view $RUN_ID --log-failed
   ```

**Categorize check results from the GraphQL response:**

| Status | Action |
|--------|--------|
| All passing | Skip to Step 2 (analyze comments) |
| Failed CI | Get logs with `gh run view`, may need fixes |
| Pending | Note status, focus on comments |

**Rate limit handling**: If the GraphQL query fails with a rate limit error, wait 60 seconds and retry once. The single-query approach makes hitting rate limits far less likely.

---

### Step 2: Analyze Feedback

Create a structured analysis of all feedback from the GraphQL response:

#### 2a. Categorize Comments

| Category | Description | Priority |
|----------|-------------|----------|
| **Blocking** | "Request changes" reviews, critical bugs | Must address |
| **Substantive** | Code improvements, logic issues, missing tests | Should address |
| **Suggestions** | Style preferences, optional enhancements | Consider |
| **Questions** | Clarification requests | Respond inline |
| **Nitpicks** | Minor style/formatting | Low priority |
| **Resolved** | Already addressed or outdated | Skip |

#### 2b. Identify Actionable Items

For each comment, determine:

1. **Is it actionable?** (code change vs discussion)
2. **Location**: File and line number (for inline comments)
3. **Scope**: Single line fix vs broader refactor
4. **Dependencies**: Does it affect other changes?

**Create a todo list** using TodoWrite with all actionable items.


### Step 3: Address Feedback

Work through the actionable items systematically:

#### 3a. For Code Review Comments

1. **Read the relevant code** at the specified location
2. **Understand the context** of the reviewer's concern
3. **Implement the fix** following their suggestion or your improved approach
4. **Verify the change** doesn't break existing functionality

#### 3b. For Failed CI Checks

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

#### 3c. For Questions/Clarifications

If a comment requires explanation rather than code change:
- Note that you should reply to the comment after pushing
- Consider if documentation/comments would help future readers

---

### Step 4: Commit Changes (if --commit or --push)

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


### Step 5: Push Changes (if --push)

```bash
git push origin HEAD
```

---

### Step 6: Summary Report

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
| All PR data (single query) | `gh api graphql -f query='...' -F owner -F repo -F pr` (see Step 1.3) |
| Failed check logs | `gh run view $ID --log-failed` |
| Quick check status (fallback) | `gh pr checks $PR --json name,state,conclusion` |


## See Also

- **/git:fix-pr** - Focus on CI failures specifically
- **gh-cli-agentic** skill - Optimized GitHub CLI patterns
- **git-branch-pr-workflow** skill - PR workflow patterns
