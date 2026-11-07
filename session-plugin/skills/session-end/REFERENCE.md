# session-end - Reference

Edge-case detail for the end-of-session orchestrator: remediating an unqueried
GitHub half of the survey digest, and the Blueprint auto-drain gate.

## Remediating `GH_READY=false`

`GH_READY=false` always ships with `GH_FAIL_REASON=`, which says *why* GitHub
went unqueried — the seven causes in this section's table want different responses, so act on the
reason rather than treating every `false` alike:

| `GH_FAIL_REASON` | What happened | Do this |
|---|---|---|
| `timeout` | The per-call watchdog killed the query (also `GH_TIMEOUT=true`) | Re-run the collector with a bigger `SESSION_SURVEY_GH_TIMEOUT` (default 8s) |
| `api-error` | GitHub answered with a 5xx / network failure — see `GH_FAIL_DETAIL` | Re-run once; it usually clears. If it persists, proceed and say GitHub was unreachable |
| `unknown` | `gh` failed with nothing quotable — `GH_FAIL_DETAIL` carries the first stderr line when there is one | Re-run once, then treat as `api-error` |
| `auth` | The token is missing, expired, or lacks a scope | Tell the user to run `gh auth login`; re-running is futile. Fall back to the GitHub MCP tools if available |
| `cloud-restricted` | A Claude Code cloud session: its GitHub proxy refuses the GraphQL the `gh` list calls use, while REST works. `PRS_SOURCE=rest-search` means the PR rows came from REST search and are real | Read PR and issue state from the GitHub MCP tools (`mcp__github__list_pull_requests`, `mcp__github__list_issues`). Never re-run or suggest `gh auth login` |
| `no-cli` | No `gh` on PATH (Claude Code on the web) | Fall back to the GitHub MCP tools, or state GitHub was not queried. Re-running is futile |
| `no-remote` | The repo has no GitHub remote | Nothing to do — there is genuinely nothing to query. Skip the GitHub half silently |

Never re-run for `auth`, `cloud-restricted`, `no-cli`, or `no-remote`: re-running
cannot change any of them. In every case the
GitHub-derived counts stay **unqueried**, not zero — so the taskwarrior-sync
redundancy test in Step 4 must not use them as evidence a follow-up is
untracked.

## Blueprint auto-drain (ADR-0020 level 1)

When the qualifying repo's `docs/blueprint/manifest.json` has
`automation.autonomy_level` ≥ 1 **and**
`task_registry["feature-tracker-sync"].enabled == true` **and**
`task_registry["feature-tracker-sync"].auto_run == true`, the Blueprint
tracker-sync pass is **auto-confirmed**: leave it out of the Step 3 question,
run it in Step 4 order without asking, and report a one-line receipt in Step 5
(`Blueprint tracker-sync: drained N WO(s) automatically (auto_run)`). All other
passes still go through the Step 3 confirmation. The gate requires all three —
a task the owner disabled (`enabled: false`) must never auto-run unattended
even when `auto_run: true` and `autonomy_level >= 1` (issue #2358). The
`enabled` check uses `== true`, not `!= false`: a manifest that omits the
`enabled` key entirely reads as disabled (the safe default), consistent with
how `// 0` already defaults a missing `autonomy_level`. Check the gate with:

```sh
jq -r 'if ((.automation.autonomy_level // 0) >= 1) and (.task_registry["feature-tracker-sync"].enabled == true) and (.task_registry["feature-tracker-sync"].auto_run == true) then "auto" else "ask" end' docs/blueprint/manifest.json 2>/dev/null
```
