---
created: 2026-11-01
modified: 2026-11-01
reviewed: 2026-11-01
---

# Issue Grouping

Unscoped on purpose: filing or picking up an issue is a `gh` command, not an
edit to a file of known shape, so no `paths:` glob can reach it.

Related issues in this repo are grouped, so that an agent implements them
together. Issues worked one at a time produce separate PRs that have to be
reconciled whenever their implementations are not cleanly compatible.

| Rule | How |
|------|-----|
| Group related issues under an `epic` tracking issue, or a milestone | Attach as a native sub-issue (`git-plugin:git-issue-hierarchy`); record ordering with `blocked_by` |
| File new issues into an existing group | Before `gh issue create`, list open epics (`gh api 'repos/{o}/{r}/issues?labels=epic&state=open'`) and attach the new issue to the one that fits; name a new epic only for three or more related issues |
| Implement a group together | One agent and one PR per group's actionable members, one commit per issue; blocked siblings are named, not worked around |
| Recurring machine-filed and feedback issues are exempt | They stand alone by design; the list is `scripts/issue-grouping-exempt.txt` (lifecycle: #3346) |

`scripts/check-issue-grouping.sh` lists open issues with no parent epic and no
milestone (advisory, `STATUS=WARN`). The daily issue-resolving Routine runs it,
works an ungrouped issue only when its fix touches a single file, and reports
the rest under `UNGROUPED` (`docs/routines/resolve-claude-plugins-issues.md`).
