# Command Index

Moved verbatim from `SKILL.md`. Compact `gh` commands for each triage operation.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Minimal issue list | `gh issue list --repo $REPO --state open --limit $BATCH --json number,title,updatedAt,labels` |
| Full PR status | `gh pr list --repo $REPO --state open --limit $BATCH --json number,title,updatedAt,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft` |
| PR check bucket summary | `gh pr checks <n> --repo $REPO --json name,state,conclusion,bucket` |
| Single PR merge state | `gh pr view <n> --repo $REPO --json mergeable,mergeStateStatus` |
| Close with evidence | `gh issue close <n> --repo $REPO --comment "<reason + PR ref>"` |
| Squash-merge when green | `gh pr merge <n> --repo $REPO --squash --auto` |

## See Also

- `/git:fix-pr` — fix `needs-fix` PRs
- `/git:pr-feedback` — address `changes-requested` PRs
- `/git:issue` — work on a `still-valid` issue
- `/git:issue-manage` — admin ops on issues
- `/git:issue-hierarchy` — sub-issue relationships
- `/git:conflicts` — resolve `needs-rebase` PRs
