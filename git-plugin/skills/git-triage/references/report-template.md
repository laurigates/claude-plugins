# Prioritized Queue Template

Moved verbatim from `SKILL.md` Steps 6 and 8. The status-table shape for the report, and the next skill to recommend per category.

### Step 6: Present the prioritized queue

Ordering: quick wins first. Use AskUserQuestion only when the user will need to pick what to act on next.

Print a status table (one row per item) grouped by category:

```
## Issues (N of M open, triaged)

| # | Age | Title | Category | Cross-link |
|---|-----|-------|----------|------------|
| 42 | 120d | Remove legacy X | implemented | PR #99 (merged) |
| 17 | 210d | Deprecated docs | stale | — |
| 13 | 14d  | Add retry logic | still-valid | — |

## PRs (N of M open, triaged)

| # | Age | Title | Category | Cross-link |
|---|-----|-------|----------|------------|
| 101 | 2d  | feat(api): X | ready-to-merge | closes #55 |
| 102 | 18d | fix(auth): Y | needs-fix | — |
| 103 | 45d | refactor(ui) | stale | — |
```

## Handoff recommendations (Step 8)

| Category | Recommended next skill |
|----------|------------------------|
| `needs-fix` | `/git:fix-pr <n>` |
| `changes-requested` | recommend the user run `/git:pr-feedback <n>` (gated by `disable-model-invocation`, so surface it rather than invoking it) |
| `needs-rebase` | `/git:conflicts <n>` or `gh pr merge --update-branch` |
| `still-valid` (actionable) | recommend the user run `/git:issue <n>` (gated by `disable-model-invocation`, so surface it rather than invoking it) |
| `still-valid` (admin only) | `/git:issue-manage` |
| `implemented` (not auto-closed) | manual `gh issue close <n>` |
| `tripwire-candidate` | `testing-plugin:test-tripwire` — a test that fails when the condition comes true, then close the issue linking it |
