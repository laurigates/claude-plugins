---
created: 2026-01-30
modified: 2026-04-19
reviewed: 2026-02-26
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh run view *), Bash(gh run list *), Bash(gh api *), Bash(gh repo view *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git switch *), Bash(git pull *), Bash(pre-commit *), Bash(npm run *), Bash(uv run *), Bash(bash *), Read, Edit, Write, Grep, Glob, TodoWrite, Task, mcp__github__pull_request_read, mcp__github__add_reply_to_pull_request_comment, mcp__github__resolve_review_thread, mcp__github__pull_request_review_write
args: "[pr-number] [--commit] [--push]"
argument-hint: [pr-number] [--commit] [--push]
disable-model-invocation: true
description: |
  Review PR workflow results and reviewer comments, then address substantive
  feedback and suggestions. Use when the user asks to address PR review
  comments, apply reviewer suggestions, reply to review threads, resolve
  reviewer feedback after CHANGES_REQUESTED, or work through a list of
  unresolved review threads on a pull request.
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
| `$1` | PR number (if omitted, use PR of current branch; if no such PR, list actionable PRs) |
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

1. **Parse owner/repo** from the git remote URL.

2. **Resolve the PR number** in this order:
   1. If `$1` was provided, use it.
   2. Otherwise, try the PR for the current branch:
      ```bash
      gh pr view --json number -q '.number'
      ```
   3. If step 2 fails (no PR for the branch) **or** the command is on a detached/default branch, fall back to listing actionable PRs:
      ```bash
      bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>
      ```
      The script emits a JSON array of open, non-draft PRs that have unresolved review threads, failing/errored CI, or `CHANGES_REQUESTED`. Handle the result as follows:

      | Result | Action |
      |--------|--------|
      | Empty array | Report "No PRs need attention." and stop. |
      | One entry | Use that PR number and continue. |
      | Multiple entries | Print a compact table (number, author, CI, unresolved, reviewDecision, title) ordered as returned, then stop and instruct the user to re-run `/git:pr-feedback <number>`. Do **not** guess which PR they meant. |

3. **Switch to PR branch** if not already on it:
   ```bash
   gh pr view $PR --json headRefName -q '.headRefName'
   git switch <branch-name>
   git pull origin <branch-name>
   ```

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

1. Skip any thread where `isResolved: true` or `isOutdated: true` — already handled.
2. Categorize each remaining comment as Blocking, Substantive, Suggestion, Question, or Nitpick.
3. For each actionable comment, capture: thread `id`, top-level comment `databaseId`, file, line, scope, and whether the body contains a ` ```suggestion ` block.
4. Create a todo list using TodoWrite with one item per actionable thread, including the thread `id` and `databaseId` so Steps 3–5 can reply and resolve.

---

### Step 3: Address Feedback

Work through actionable items systematically. For each thread, decide using the table below — see [REFERENCE.md](REFERENCE.md) for the full decision tree.

| Comment shape | Action |
|---------------|--------|
| Contains a ` ```suggestion ` block, fix is correct | **Accept the suggestion**: apply the suggestion's exact replacement to the file (see [REFERENCE.md](REFERENCE.md) "Accepting Suggestions") |
| Contains a ` ```suggestion ` block, fix needs adjustment | Implement an improved variant; explain the deviation in the reply |
| Inline code comment without suggestion | Read context, implement fix, verify no regressions |
| Question / clarification | Skip code change; draft an inline reply for Step 4 |
| Blocking review (`REQUEST_CHANGES`) | Address every concern before resolving any thread |
| Failed CI check | Identify failure type (lint/type/test/build), fix locally, run to verify |

Mark each todo `in_progress` while working it and `completed` once the file change (if any) lands locally. Do **not** resolve threads yet — replies and resolution happen after the commit so reviewers see the linked SHA.

---

### Step 4: Commit Changes (if --commit or --push)

Group related fixes into logical commits. See [REFERENCE.md](REFERENCE.md) for commit message format.

Run pre-commit hooks if configured, then stage any formatter changes.

### Step 5: Push Changes (if --push)

```bash
git push origin HEAD
```

### Step 6: Reply and Resolve Threads

For every actionable thread tracked in Step 2, post a reply and resolve when appropriate. Owner/repo/PR are the same values used in Step 1.

1. **Reply** with `mcp__github__add_reply_to_pull_request_comment` using the top-level comment's `databaseId` (a number, not the GraphQL node ID). Keep replies short — see [REFERENCE.md](REFERENCE.md) "Reply Templates".
   - Code change made → reference the commit SHA: `Fixed in <sha> by <one-line summary>.`
   - Suggestion accepted verbatim → `Accepted suggestion in <sha>.`
   - Suggestion adapted → explain the deviation: `Applied a variant in <sha>: <reason>.`
   - Deferred / out of scope → state why and link a follow-up issue if one exists.
   - Question → answer it directly.

2. **Resolve** with `mcp__github__resolve_review_thread` using the thread `id` (a `PRRT_…` GraphQL node ID) when **all** of the following hold:
   - The reviewer's concern is fully addressed by the pushed commit, OR the reviewer asked a question that has been answered, OR the comment is a nitpick you've explicitly declined with reasoning.
   - The thread is not part of an unsubmitted `REQUEST_CHANGES` review where other concerns remain open.
   - You authored or own-pushed the resolving change (do not resolve threads on PRs you don't own without explicit user approval).

3. **Do NOT resolve** when:
   - The reply asks the reviewer a follow-up question.
   - The fix is partial or deferred to another PR.
   - The reviewer explicitly asked to keep the thread open.
   - You merely disagree without making a change — leave it for the reviewer.

If `--commit`/`--push` was not passed, still post replies for questions, but skip resolution (no resolving SHA exists yet) — note pending replies in the Step 7 summary instead.

### Step 7: Summary Report

Provide a summary table of feedback addressed, replies posted, threads resolved, and next steps. See [REFERENCE.md](REFERENCE.md) for the report template.

---

## Agentic Optimizations

| Context | Command / Tool |
|---------|----------------|
| All PR data (single query) | `bash ${CLAUDE_SKILL_DIR}/scripts/fetch-pr-data.sh <owner> <repo> <pr>` |
| Actionable PRs (fallback selector) | `bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>` |
| Failed check logs | `gh run view $ID --log-failed` |
| Quick check status (fallback) | `gh pr checks $PR --json name,state,conclusion` |
| Reply to a review comment | `mcp__github__add_reply_to_pull_request_comment` (commentId = `databaseId`) |
| Resolve a review thread | `mcp__github__resolve_review_thread` (threadId = `PRRT_…` node ID) |

## See Also

- **/git:fix-pr** - Focus on CI failures specifically
- **gh-cli-agentic** skill - Optimized GitHub CLI patterns
- **git-branch-pr-workflow** skill - PR workflow patterns
