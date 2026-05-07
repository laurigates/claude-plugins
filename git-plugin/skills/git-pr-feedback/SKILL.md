---
created: 2026-01-30
modified: 2026-05-06
reviewed: 2026-05-06
allowed-tools: Bash(gh pr checks *), Bash(gh pr view *), Bash(gh pr diff *), Bash(gh run view *), Bash(gh run list *), Bash(gh api *), Bash(gh repo view *), Bash(gh issue create *), Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git switch *), Bash(git pull *), Bash(git fetch *), Bash(pre-commit *), Bash(npm run *), Bash(uv run *), Bash(bash *), Read, Edit, Write, Grep, Glob, TodoWrite, Task, mcp__github__pull_request_read, mcp__github__add_reply_to_pull_request_comment, mcp__github__resolve_review_thread, mcp__github__pull_request_review_write, mcp__github__issue_write
args: "[pr-number] [--commit] [--push] [--all] [--dry-run] [--limit N]"
argument-hint: "[pr-number | --all] [--commit] [--push] [--dry-run] [--limit N]"
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
| `$1` | PR number (if omitted, use PR of current branch; if no such PR, list actionable PRs). Mutually exclusive with `--all`. |
| `--commit` | Create commit(s) after addressing feedback. |
| `--push` | Push changes after committing (implies `--commit`). |
| `--all` | Address feedback on every actionable open PR. Dispatches one subagent per PR in an isolated worktree; the orchestrator pushes, replies, and resolves. Implies `--commit --push` unless `--dry-run` is set. Mutually exclusive with `$1`. |
| `--dry-run` | With `--all`, print the dispatch plan and stop — no subagents spawned, no commits, no pushes. Ignored without `--all`. |
| `--limit N` | Maximum concurrent subagents under `--all` (default `3`). Use a small number to stay under GitHub rate limits and avoid `[1m]`-model concurrency cascades (see [`skill-fork-context.md`](../../../.claude/rules/skill-fork-context.md)). |

**Mode selection**:

| Mode | Triggered when | Flow |
|------|----------------|------|
| Single-PR | No `--all` | Steps 1–7 below operate on one PR. |
| Multi-PR | `--all` is passed | **Step 1A** dispatches subagents; the orchestrator finalises (push, reply, resolve, re-request) and writes a combined summary. Skip Steps 1–6. |

If both `$1` and `--all` are given, error and stop with: `--all is mutually exclusive with a PR number argument.`

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

> If `--all` is set, **skip this step** and jump to **Step 1A: Multi-PR Mode** below.

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

### Step 1A: Multi-PR Mode (--all)

Reached only when `--all` is passed. The orchestrator dispatches one subagent per actionable PR; subagents commit inside isolated worktrees but never push. The orchestrator handles all GitHub-side mutations.

1. **Parse owner/repo** from the git remote URL.

2. **List actionable PRs** with the bundled selector:
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>
   ```
   The script returns a JSON array of open, non-draft PRs with unresolved review threads, failing/errored CI, or `CHANGES_REQUESTED`. If the array is empty, report `No PRs need attention.` and stop.

3. **Print a compact dispatch table** (number, author, ci, unresolved, reviewDecision, head, title) so the user can see what is about to be processed.

4. **`--dry-run` short-circuit**: if `--dry-run` was also passed, additionally print the per-PR subagent prompt that *would* be dispatched (one per row, using the template in [REFERENCE.md](REFERENCE.md) "Multi-PR Subagent Prompt"), then stop. No subagents spawn, no commits, no pushes.

5. **Dispatch subagents**, capped at `--limit N` concurrent (default `3`). For each PR call the `Task` tool with:
   - `subagent_type: "general-purpose"`
   - `isolation: "worktree"` — each subagent gets its own git worktree
   - `description`: `Address review feedback for PR #<n>`
   - `prompt`: see [REFERENCE.md](REFERENCE.md) "Multi-PR Subagent Prompt" for the canonical template. The prompt must instruct the subagent to switch its worktree to the PR's `headRefName`, run the single-PR feedback flow with `--commit` (not `--push`), and return a structured JSON summary.

   Dispatch one batch of `N` `Task` calls in a single message (per the parallel-dispatch contract). When all return, dispatch the next batch until the queue is empty.

6. **Collect subagent results**. Each subagent returns JSON with: `pr`, `branch`, `worktree_path`, `commits[]`, `addressed[]` (each with `thread_id`, `database_id`, `action`, `reply`, `resolve`), `deferred_issues[]`, `co_authors[]`, `blockers[]`. Treat any subagent that fails to return parseable JSON as blocked — record its raw output and continue with the rest of the batch.

7. **Orchestrator finalisation** — for each PR with successful commits, run sequentially (push and the GitHub mutation tools share the same rate-limit pool):
   1. `git push origin <branch>` from the **main checkout** — worktrees share the underlying `.git/`, so commits made by the subagent are already visible by branch name. No `cd` into the subagent's worktree is required.
   2. Capture the resolving SHA (`git rev-parse origin/<branch>` after the push).
   3. For each `addressed[]` entry, post the reply via `mcp__github__add_reply_to_pull_request_comment`, substituting the resolving SHA into any `{{SHA}}` placeholder the subagent left in the reply text.
   4. Resolve threads via `mcp__github__resolve_review_thread` per Step 6's rules (only when `resolve: true` AND the resolution criteria in [REFERENCE.md](REFERENCE.md) hold).
   5. Re-request review per Step 5a's rules.

8. **Skip Steps 2–6**. Go directly to **Step 7** with a combined summary that includes a per-PR section plus a top-level rollup: dispatched, succeeded, blocked, total threads resolved, total commits pushed.

#### Failure handling

| Subagent state | Orchestrator action |
|----------------|---------------------|
| Returned valid JSON, has commits, no blockers | Push + reply + resolve as above |
| Returned valid JSON, no commits (only questions / declined nitpicks) | Skip push; still post replies and resolve declined nitpick threads |
| Returned valid JSON, has `blockers[]` | Surface in the summary; do **not** push partial work — let the user decide |
| Failed to return parseable JSON | Surface its raw output in the summary as `blocked: parse-error`; do nothing further for that PR |
| Reported a merge conflict on `git pull --ff-only` | Surface in the summary as `blocked: branch-out-of-sync`; user resolves manually |

A blocked subagent does not abort the whole batch; the orchestrator continues with the others.

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
| Contains a ` ```suggestion ` block, fix is correct | **Accept the suggestion**: apply the suggestion's exact replacement to the file (see [REFERENCE.md](REFERENCE.md) "Accepting Suggestions"). Record the comment author's `login` and `name`/`email` for co-author attribution in Step 4. |
| Contains a ` ```suggestion ` block, fix needs adjustment | Implement an improved variant; explain the deviation in the reply. Record the suggester for co-author attribution. |
| Inline code comment without suggestion | Read context, implement fix, verify no regressions |
| Question / clarification | Skip code change; draft an inline reply for Step 4 |
| Blocking review (`REQUEST_CHANGES`) | Address every concern before resolving any thread |
| Failed CI check | Identify failure type (lint/type/test/build), fix locally, run to verify |
| Out-of-scope feedback | Do not implement in this PR. Open a follow-up issue (see Step 3a) and reference its number in the reply. |

Mark each todo `in_progress` while working it and `completed` once the file change (if any) lands locally. Do **not** resolve threads yet — replies and resolution happen after the commit so reviewers see the linked SHA.

### Step 3a: File follow-up issues for out-of-scope feedback

For any thread categorised as out-of-scope (or where the user opts to defer rather than implement now):

1. Draft a one-line title and short body that quotes the reviewer comment and links the PR thread URL.
2. Use `mcp__github__issue_write` (action `create`) or `gh issue create -R <owner>/<repo> --title "<title>" --body "<body>"` to file the issue.
3. Capture the returned issue number — Step 6's reply uses it (`Deferred to #<n> — <reason>.`).

Skip this step if the user has explicitly said not to file follow-ups. When ambiguous, ask via `AskUserQuestion` before creating an issue.

---

### Step 4: Commit Changes (if --commit or --push)

Group related fixes into logical commits — one commit per logical group of accepted suggestions, not one per suggestion. See [REFERENCE.md](REFERENCE.md) for commit message format.

For any commit that contains an **accepted (or adapted) suggestion**, append a `Co-authored-by:` trailer for each unique suggester. This mirrors GitHub's "Commit suggestion" / "Add suggestion to batch" behaviour, which credits the suggester as co-author. See [REFERENCE.md](REFERENCE.md) "Co-author Attribution" for how to construct the trailer line and resolve the suggester's email.

Run pre-commit hooks if configured, then stage any formatter changes.

### Step 5: Push Changes (if --push)

```bash
git push origin HEAD
```

### Step 5a: Re-request Review (if --push)

After a successful push that addresses substantive feedback, re-request review from any reviewer whose threads were resolved or who left a `CHANGES_REQUESTED` review. Skip this step when only nitpicks or questions were addressed.

Determine reviewers to re-request from the GraphQL response captured in Step 1:

- `latestReviews` entries with `state == "CHANGES_REQUESTED"`
- Authors of any review thread you resolved in Step 6

Then call:

```bash
gh api -X POST \
  /repos/<owner>/<repo>/pulls/<pr>/requested_reviewers \
  -f 'reviewers[]=<login1>' \
  -f 'reviewers[]=<login2>'
```

If `gh api` returns 422 ("Reviews may only be requested from collaborators"), the reviewer cannot be re-requested via the API — note it in the Step 7 summary and continue.

### Step 6: Reply and Resolve Threads

For every actionable thread tracked in Step 2, post a reply and resolve when appropriate. Owner/repo/PR are the same values used in Step 1.

1. **Reply** with `mcp__github__add_reply_to_pull_request_comment` using the top-level comment's `databaseId` (a number, not the GraphQL node ID). Keep replies short — see [REFERENCE.md](REFERENCE.md) "Reply Templates".
   - Code change made → reference the commit SHA: `Fixed in <sha> by <one-line summary>.`
   - Suggestion accepted verbatim → `Accepted suggestion in <sha>.`
   - Suggestion adapted → explain the deviation: `Applied a variant in <sha>: <reason>.`
   - Deferred / out of scope → reference the follow-up issue filed in Step 3a: `Deferred to #<issue> — <reason>.`
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
| Actionable PRs (selector / `--all` source) | `bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>` |
| Dispatch a per-PR subagent (`--all`) | `Task({subagent_type: "general-purpose", isolation: "worktree", prompt: <REFERENCE.md template>})` |
| Failed check logs | `gh run view $ID --log-failed` |
| Quick check status (fallback) | `gh pr checks $PR --json name,state,conclusion` |
| Reply to a review comment | `mcp__github__add_reply_to_pull_request_comment` (commentId = `databaseId`) |
| Resolve a review thread | `mcp__github__resolve_review_thread` (threadId = `PRRT_…` node ID) |
| Re-request review after push | `gh api -X POST /repos/<owner>/<repo>/pulls/<pr>/requested_reviewers -f 'reviewers[]=<login>'` |
| File follow-up issue for deferred feedback | `mcp__github__issue_write` (action `create`) or `gh issue create -R <owner>/<repo> --title <t> --body <b>` |

## See Also

- **/git:fix-pr** - Focus on CI failures specifically
- **gh-cli-agentic** skill - Optimized GitHub CLI patterns
- **git-branch-pr-workflow** skill - PR workflow patterns
