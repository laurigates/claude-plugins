# session-wrap — Acting on `GH_FAIL_REASON` (Step 1)

The `GH_FAIL_REASON=` beside it says whether that is worth
fixing before you file: re-run once for `timeout` / `api-error` /
`unknown`; for `auth` / `no-cli` the dedup set is simply unavailable this
session, so keep the bar for adding a task high; for `no-remote` there is
no PR/issue to duplicate and the caveat does not apply. For `cloud-restricted`
(a cloud session; `gh` auth is not the problem) read open PRs and assigned
issues from the GitHub MCP tools (`mcp__github__list_pull_requests`,
`mcp__github__list_issues`) and dedup against those; `PRS_SOURCE=rest-search`
means the `PRS` rows already came from REST and are real.
