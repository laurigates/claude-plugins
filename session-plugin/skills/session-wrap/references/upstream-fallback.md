# session-wrap — Upstream Filing Fallback (Step 4)

**Graceful degradation**: if `workflow-orchestration-plugin` is not
installed (mirrors the `feedback-plugin` / `blueprint-plugin`
cross-plugin fallback in `session-end`), fall back to
`git-plugin:github-issue-writing` + an explicit manual upstream-HEAD
verification, or route to *Track for later* instead — **never file
unverified**.
