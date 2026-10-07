# Commands and Errors

Moved verbatim from `SKILL.md`. Read when an API call fails, or for the compact command per operation.

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| 404 on sub_issues endpoint | Sub-issues not enabled for repo | Report: "Sub-issues are not available for this repository. Enable them in repository settings." |
| 404 on dependencies endpoint | Issue dependencies feature not enabled for repo/org | Report: "Issue dependencies are not available for this repository. Ask an owner to enable them under Repository settings → Features → Issues." |
| 422 on add sub-issue | Issue already a sub-issue or circular reference | Report the specific error |
| 422 on add dependency | Circular dependency, already linked, or self-reference | Report the specific error |
| Issue not found | Invalid issue number | Report which issue number was not found |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick sub-issue status | `gh issue view N --json title,subIssuesSummary` |
| List sub-issues | `gh api repos/{o}/{r}/issues/{N}/sub_issues --jq '.[].number'` |
| Add sub-issue | `gh api repos/{o}/{r}/issues/{N}/sub_issues -f sub_issue_id=M` |
| Remove sub-issue | `gh api repos/{o}/{r}/issues/{N}/sub_issues/M -X DELETE` |
| List blockers | `gh api repos/{o}/{r}/issues/{N}/dependencies/blocked_by --jq '.[].number'` |
| List blocked-by-me | `gh api repos/{o}/{r}/issues/{N}/dependencies/blocking --jq '.[].number'` |
| Add blocker | `gh api repos/{o}/{r}/issues/{N}/dependencies/blocked_by -f issue_id=<node-id>` |
| Remove blocker | `gh api repos/{o}/{r}/issues/{N}/dependencies/blocked_by/{dep_id} -X DELETE` |
| Resolve node id | `gh api repos/{o}/{r}/issues/{N} --jq '.id'` |
