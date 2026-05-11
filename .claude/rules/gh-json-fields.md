# `gh --json` Field Names

The GitHub CLI's `--json` flag accepts a comma-separated list of field
names. Invalid names exit 1 and dump the available field list — but
that's a *runtime* failure, not a syntax check. Get the field name
right the first time.

## The `merged` mistake

The single most-common mistake (6 of 10 `Unknown JSON field` errors in
the W20 window, across 6 distinct sessions) is asking for a field
called `merged`:

```
# Wrong — there is no `merged` field on the PR JSON object
gh pr view 42 --json number,merged --jq '.merged'
# → Exit 1: Unknown JSON field: "merged"
```

PR merge state lives on the `state` field (a string enum) or the
`mergedAt` field (an ISO 8601 timestamp, or `null` when not merged).

## PR state reference

| Want to know | Correct field | Value when merged | Value when open | Value when closed-without-merge |
|---|---|---|---|---|
| State enum | `state` | `"MERGED"` | `"OPEN"` | `"CLOSED"` |
| When merged (or null) | `mergedAt` | ISO 8601 string | `null` | `null` |
| When closed (or null) | `closedAt` | ISO 8601 string | `null` | ISO 8601 string |
| Merge commit SHA | `mergeCommit.oid` | full SHA | `null` | `null` |
| Mergeable now? | `mergeable` | n/a | `MERGEABLE` / `CONFLICTING` / `UNKNOWN` | n/a |
| Auto-merge enabled? | `autoMergeRequest` | n/a | object or `null` | n/a |

Common idioms:

```bash
# Is the PR merged?
gh pr view 42 --json state --jq '.state == "MERGED"'

# When was it merged (or null)?
gh pr view 42 --json mergedAt --jq '.mergedAt'

# Find merged PRs in last month
gh pr list --state merged --limit 100 --json number,title,mergedAt
```

## How to discover field names

If you don't know the field name, **don't guess**. Two reliable ways
to find it:

1. **Run with one valid field, then read the error if any new field
   is rejected.** The error message lists every available field:

   ```bash
   gh pr view 42 --json number,merged
   # → Unknown JSON field: "merged"
   # → Available fields: additions, assignees, author, autoMergeRequest,
   #   baseRefName, baseRefOid, body, changedFiles, closed, closedAt, ...
   ```

   That list is authoritative. Pick the right field from it.

2. **Use the help output:**

   ```bash
   gh pr view --help     # lists --json flag + field discovery hint
   gh pr list --help
   gh issue view --help
   ```

## Other commonly-mistaken field names

| Want | You might try | Correct field |
|---|---|---|
| Is the issue closed? | `closed` (boolean) | `state` (`"OPEN"` / `"CLOSED"`) |
| When was the issue closed? | `closed_at` (snake_case) | `closedAt` (camelCase) |
| Is the repo archived? | `archived` on PR/issue object | Query repo separately: `gh repo view --json isArchived` |
| Issue type | `issueType` | `issueType.name` (object, not string) |
| Has Pages enabled? | `hasPages` on PR/issue | Query repo: `gh repo view --json hasPagesEnabled` |
| Base repository | `baseRepository` on a PR | `baseRefRepositoryNameWithOwner` or query separately |

These were all observed in the W20 window. The unifying theme: GitHub's
GraphQL schema uses **camelCase**, not snake_case, and PR/issue
objects don't carry every property of their parent repository.

## Edge case: `--jq` on a null field

`mergedAt` is `null` for unmerged PRs. Plain `--jq '.mergedAt'` prints
`null` (literally the string `null`). For a boolean test:

```bash
# Right - explicit null check
gh pr view 42 --json mergedAt --jq '.mergedAt != null'

# Wrong - test "the string null"
gh pr view 42 --json mergedAt --jq '.mergedAt | length > 0'
```

## Related

- `.claude/rules/friction/2026-W20-frictions.md` — measured impact
  (10 events across 10 distinct sessions in the W20 window)
- `.claude/rules/github-metadata-hygiene.md` (parent
  `laurigates/CLAUDE.md`) — when to query PR metadata at all
- `gh pr help json-fields` — official field reference (when available)
