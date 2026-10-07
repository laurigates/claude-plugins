# session-wrap — Acting on `GH_FAIL_REASON` (Step 1)

The `GH_FAIL_REASON=` beside it says whether that is worth
fixing before you file: re-run once for `timeout` / `api-error` /
`unknown`; for `auth` / `no-cli` the dedup set is simply unavailable this
session, so keep the bar for adding a task high; for `no-remote` there is
no PR/issue to duplicate and the caveat does not apply.
