# Multi-PR Mode (`--all`)

Moved verbatim from `SKILL.md` Step 1A. Read only when `--all` is passed; the single-PR path never needs it.

### Step 1A: Multi-PR Mode (--all)

Reached only when `--all` is passed. The orchestrator dispatches one subagent per actionable PR; subagents commit inside isolated worktrees but never push. The orchestrator handles all GitHub-side mutations.

1. **Parse owner/repo** from the git remote URL.

2. **List actionable PRs** with the bundled selector (append `--include-automation` if that flag was passed):
   ```bash
   bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>
   ```
   The script returns a JSON array of open, non-draft PRs with unresolved review threads, failing/errored CI, or `CHANGES_REQUESTED`. Automation-authored PRs (release-please, dependabot, renovate, `*[bot]`, `*-bot`) are excluded by default — dispatching a subagent on one is almost always wrong (no review threads to act on, protected changelog/version files). Pass `--include-automation` to include them, or set `PR_FEEDBACK_AUTOMATION_AUTHORS` to extend the recognised author list. If the array is empty, report `No PRs need attention.` and stop.

3. **Print a compact dispatch table** (number, author, ci, unresolved, reviewDecision, head, title) so the user can see what is about to be processed.

4. **`--dry-run` short-circuit**: if `--dry-run` was also passed, additionally print the per-PR subagent prompt that *would* be dispatched (one per row, using the template in [REFERENCE.md](../REFERENCE.md) "Multi-PR Subagent Prompt"), then stop. No subagents spawn, no commits, no pushes.

5. **Dispatch subagents**, capped at `--limit N` concurrent (default `3`). For each PR call the `Task` tool with:
   - `subagent_type: "general-purpose"`
   - `isolation: "worktree"` — each subagent gets its own git worktree
   - `description`: `Address review feedback for PR #<n>`
   - `prompt`: see [REFERENCE.md](../REFERENCE.md) "Multi-PR Subagent Prompt" for the canonical template. The prompt must instruct the subagent to switch its worktree to the PR's `headRefName`, run the single-PR feedback flow with `--commit` (not `--push`), and return a structured JSON summary.

   Dispatch one batch of `N` `Task` calls in a single message (per the parallel-dispatch contract). When all return, dispatch the next batch until the queue is empty.

6. **Collect subagent results**. Each subagent returns JSON with: `pr`, `branch`, `worktree_path`, `commits[]`, `addressed[]` (each with `thread_id`, `database_id`, `action`, `reply`, `resolve`), `deferred_issues[]`, `co_authors[]`, `blockers[]`. Treat any subagent that fails to return parseable JSON as blocked — record its raw output and continue with the rest of the batch.

7. **Orchestrator finalisation** — for each PR with successful commits, run sequentially (push and the GitHub mutation tools share the same rate-limit pool):
   1. `git push origin <branch>` from the **main checkout** — worktrees share the underlying `.git/`, so commits made by the subagent are already visible by branch name. No `cd` into the subagent's worktree is required.
   2. Capture the resolving SHA (`git rev-parse origin/<branch>` after the push).
   3. For each `addressed[]` entry, post the reply via `mcp__github__add_reply_to_pull_request_comment`, substituting the resolving SHA into any `{{SHA}}` placeholder the subagent left in the reply text.
   4. Resolve threads via the GraphQL `resolveReviewThread` mutation per Step 6's rules. Resolution is the default after a reply — only skip when the subagent set `resolve: false` for a documented exception (follow-up question, partial fix, reviewer asked to keep open, or a third-party PR without user approval). Treat any `resolve: true` paired with a successful reply as a mandatory call. Use:

      ```bash
      gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id="$THREAD_ID"
      ```
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
