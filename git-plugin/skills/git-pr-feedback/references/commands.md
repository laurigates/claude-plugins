# Command Index

Moved verbatim from `SKILL.md`. The compact commands and tools each step uses.

## Agentic Optimizations

| Context | Command / Tool |
|---------|----------------|
| All PR data (single query) | `bash ${CLAUDE_SKILL_DIR}/scripts/fetch-pr-data.sh <owner> <repo> <pr>` |
| Actionable PRs (selector / `--all` source) | `bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh <owner> <repo>` |
| Actionable PRs incl. automation | `bash ${CLAUDE_SKILL_DIR}/scripts/list-actionable-prs.sh --include-automation <owner> <repo>` |
| Dispatch a per-PR subagent (`--all`) | `Task({subagent_type: "general-purpose", isolation: "worktree", prompt: <REFERENCE.md template>})` |
| Failed check logs | `gh run view $ID --log-failed` |
| Quick check status (fallback) | `gh pr checks $PR --json name,state,conclusion` |
| Reply to a review comment | `mcp__github__add_reply_to_pull_request_comment` (commentId = `databaseId`) |
| Resolve a review thread | `gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -F id="$THREAD_ID"` (threadId = `PRRT_…` node ID) |
| Re-request review after push | `gh api -X POST /repos/<owner>/<repo>/pulls/<pr>/requested_reviewers -f 'reviewers[]=<login>'` |
| File follow-up issue for deferred feedback | `mcp__github__issue_write` (action `create`) or `gh issue create -R <owner>/<repo> --title <t> --body <b>` |
