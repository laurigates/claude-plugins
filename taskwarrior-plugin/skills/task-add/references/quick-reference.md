# task-add — Tags, Fields, and Command Quick Reference

Open this when choosing tags or fields for `task add`, naming a new tag, or
looking up the agent-friendly command forms, or checking why the bpid duplicate
check matches exactly.

## Tag naming gotcha

> **Tag naming gotcha — hyphens silently break tags.** Taskwarrior parses
> `-` mid-token as exclude-filter syntax, even inside a `+tag` argument.
> `+blocked-on-merge` is parsed as `+blocked` AND `-on-merge`, so the tag
> never lands and the literal `+blocked-on-merge` string ends up appended
> to the description as plain text (urgency does not tick up). Single-
> quoting (`'+blocked-on-merge'`) does **not** help — this is a taskwarrior
> parser quirk, not a shell issue. Use underscores or camelCase instead:
> `+blocked_on_merge` or `+blockedOnMerge`. The same applies to any tag
> name containing a hyphen.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Capture stable UUID after add | `task +LATEST uuids` |
| Duplicate check by bpid (exact bpid and project, per Step 3) | `task bpid:WO-012 export \| jq --arg p myrepo --arg b WO-012 '.[] \| select(.bpid == $b and (.project // "") == $p) \| {id, uuid, status}'` |
| Pre-fill from issue | `gh issue view 145 --json number,title,body,labels` |
| Next ready (unblocked + scheduled-due) | `task status:pending +READY export \| jq '.[:3]'` |
| Skip empty filter exit | Always use `export \| jq`, never `list` |

## Exact matching in the bpid duplicate check

SKILL.md Step 3 runs the duplicate check by bpid with `task bpid:"$BPID" export`
piped to a `jq` filter on the resolved project (`$PROJECT`), so a matching
`bpid` in another repo's queue is not surfaced as a false-positive duplicate.

- **Both values are matched exactly in `jq`** because taskwarrior's `attr:value`
  filters are prefix matches: `project:myrepo` also returns tasks in
  `myrepo-docs` and `myrepo.sub`, and `bpid:WO-012` also returns `WO-0123` —
  see [project-slug-verification.md](project-slug-verification.md).
- **`--no-project`**: `$PROJECT` is empty, so only project-less tasks match.
- **Report the `uuid`** with any match, so a later update addresses the task by
  it (`.claude/rules/task-id-stability.md`).
- **`export`, never `list`**: `task bpid:"$BPID" list` exits 1 on an empty result
  and cancels sibling tool calls in parallel batches
  (`.claude/rules/parallel-safe-queries.md`).

## Quick Reference

| Flag / field | Purpose |
|--------------|---------|
| `project:` | Project (defaults to repo basename) |
| `--no-project` | File without a project (cross-cutting) |
| `bpid:` | Blueprint ID link |
| `bpdoc:` | Blueprint doc path |
| `bpms:` | Milestone |
| `ghid:` | GitHub issue number |
| `ghpr:` | GitHub PR number |
| `due:` | Deadline — feeds urgency, surfaces `+DUE`/`+OVERDUE` |
| `scheduled:` | Earliest start — gates `+READY` |
| `wait:` | Hide until date (auto-unhides) — prefer over `+blocked_on_merge` |
| `recur:` | Repeat frequency (needs `due:`) |
| `until:` | Auto-delete date |
| `+wo` | Work order |
| `+prp` | PRP |
| `+fr` | Feature request |
| `+re` | Research |
| `+gh` | Linked to GitHub |
| `+pr_ready` | Open PR waiting |
| `+blocked_on_merge` | Waiting on another PR |
