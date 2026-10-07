# Prioritized Queue Template

Moved verbatim from `SKILL.md` Step 6. The status-table shape for the report.

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
