---
created: 2026-01-30
modified: 2026-03-24
reviewed: 2026-02-26
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh run view *), Bash(gh run list *), Bash(gh api *), Bash(gh repo view *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git switch *), Bash(git pull *), Bash(pre-commit *), Bash(npm run *), Bash(uv run *), Bash(bash *), Read, Edit, Write, Grep, Glob, TodoWrite, Task, mcp__github__pull_request_read
args: "[pr-number] [--commit] [--push]"
argument-hint: [pr-number] [--commit] [--push]
disable-model-invocation: true
description: Review PR workflow results and comments, then address substantive feedback and suggestions from reviewers
name: git-pr-feedback
agent: general-purpose
---

## Context

- Repo: !`git remote -v`
- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`

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
| A PR has reviewer comments to address | CI checks are failing with no review comments -> use `git-fix-pr` |
| You need to systematically work through review feedback | You're creating a new PR -> use `git-commit-push-pr` |
| A reviewer has requested changes | You want to understand PR workflow patterns -> use `git-branch-pr-workflow` |

## Your Task

Review PR workflow results and reviewer comments, then address substantive feedback.

For feedback categorization, decision trees, commit format, and report templates, see [REFERENCE.md](REFERENCE.md).

---

### Step 1: Determine PR and Gather All Data

1. **Get PR number** from argument or detect from current branch:
   ```bash
   gh pr view --json number -q '.number'
   ```

2. **Switch to PR branch** if not already on it:
   ```bash
   gh pr view $PR --json headRefName -q '.headRefName'
   git switch <branch-name>
   git pull origin <branch-name>
   ```

3. **Parse owner/repo** from the git remote URL.

4. **Fetch ALL PR data** using the bundled script (single GraphQL query):
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/fetch-pr-data.sh <owner> <repo> <pr-number>
   ```

5. **For failed checks only**, fetch detailed logs:
   ```bash
   gh run view $RUN_ID --log-failed
   ```

| Check Status | Action |
|--------------|--------|
| All passing | Skip to Step 2 |
| Failed CI | Get logs with `gh run view`, may need fixes |
| Pending | Note status, focus on comments |

If the GraphQL query fails with a rate limit error, wait 60 seconds and retry once.

---

### Step 2: Analyze Feedback

Categorize all comments from the GraphQL response (see [REFERENCE.md](REFERENCE.md) for category definitions):

1. Categorize each comment as Blocking, Substantive, Suggestion, Question, Nitpick, or Resolved
2. For each actionable comment, note file, line, scope, and dependencies
3. Create a todo list using TodoWrite with all actionable items

---

### Step 3: Address Feedback

Work through actionable items systematically:

**Code review comments:** Read relevant code, understand context, implement fix, verify no breakage.

**Failed CI checks:** Identify failure type (lint/type/test/build), fix locally, run to verify.

**Questions/clarifications:** Note for PR reply; consider adding code comments for future readers.

---

### Step 4: Commit Changes (if --commit or --push)

Group related fixes into logical commits. See [REFERENCE.md](REFERENCE.md) for commit message format.

Run pre-commit hooks if configured, then stage any formatter changes.

### Step 5: Push Changes (if --push)

```bash
git push origin HEAD
```

### Step 6: Summary Report

Provide a summary table of feedback addressed, changes made, and next steps. See [REFERENCE.md](REFERENCE.md) for report template.

---

## Agentic Optimizations

| Context | Command |
|---------|---------|
| All PR data (single query) | `bash ${CLAUDE_SKILL_DIR}/scripts/fetch-pr-data.sh <owner> <repo> <pr>` |
| Failed check logs | `gh run view $ID --log-failed` |
| Quick check status (fallback) | `gh pr checks $PR --json name,state,conclusion` |

## See Also

- **/git:fix-pr** - Focus on CI failures specifically
- **gh-cli-agentic** skill - Optimized GitHub CLI patterns
- **git-branch-pr-workflow** skill - PR workflow patterns
