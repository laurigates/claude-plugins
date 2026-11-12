# GitHub CLI Agentic Patterns - Reference

Custom issue fields, issue management commands, GitHub URL resolution, and complete JSON field lists.

## Custom Issue Fields

```bash
# List available fields for an org
gh api orgs/{org}/issue-fields --jq '.[].name'

# Get field values for an issue
gh api repos/{owner}/{repo}/issues/{N}/issue-field-values

# Set field value
gh api repos/{owner}/{repo}/issues/{N}/issue-field-values \
  -X POST -f field_id={id} -f value='{value}'
```

## Issue Management

```bash
# Transfer issue to another repo
gh issue transfer {N} {target-repo}

# Pin/unpin issue
gh issue pin {N}
gh issue unpin {N}

# Lock/unlock issue thread
gh issue lock {N} --reason resolved
gh issue unlock {N}

# Create development branch from issue
gh issue develop {N} --checkout
gh issue develop {N} --name {branch-name}
```

## Bot Authors

The account that opens an issue or PR with `GITHUB_TOKEN` is spelled
differently depending on the command that reports it:

| Command | Author spelling |
|---|---|
| `gh issue list --json author` / `gh pr list --json author` | `{"is_bot": true, "login": "app/github-actions"}` |
| `gh search issues` | `github-actions[bot]` |
| `gh issue list --author "app/github-actions"` | Returned `[]` in a repository that had such issues |

So do not filter on `--author` to find what a workflow opened. Try gh's own
app-author filter first. `gh issue list`, `gh pr list` and `gh search issues`
each list `--app string  Filter by GitHub App author` in `--help` (gh 2.89.0).
When gh filters by author, `--limit` counts only matching items, so a busy
repository cannot push the bot's issues past the cap:

```bash
gh issue list --app github-actions --state open --limit 100 --json number,title,author
```

This form is unverified: it was read from `--help` and not run against a
repository. gh may build it into the same `app/github-actions` author filter
that returned `[]`. If it returns nothing in a repository that has such issues,
fall back to fetching the list and filtering on `.author.login` with jq, which
matches the JSON spelling:

```bash
gh issue list --state open --limit 100 --json number,title,author \
  --jq '[.[] | select(.author.is_bot and .author.login == "app/github-actions")]'
```

The fallback sees only the `--limit` items gh fetches, so on a busy repository
it silently drops the bot's issues past that cap. Raise `--limit` above the
repository's open-issue count.

Observed 2026-11-10 by an agent writing a workflow lookup; the three commands
were not re-run when this section was written, and the spellings may differ
across gh versions. Check `--json author` output once before relying on the
exact string.

## GitHub URL Resolution

Translate GitHub URLs into `gh` API commands for programmatic access.

### URL → Command Mapping

| URL Pattern | Command |
|-------------|---------|
| `github.com/{owner}/{repo}/pull/{n}` | `gh pr view {n} --repo {owner}/{repo} --json number,title,body,state` |
| `github.com/{owner}/{repo}/issues/{n}` | `gh issue view {n} --repo {owner}/{repo} --json number,title,body,state` |
| `github.com/{owner}/{repo}/commit/{sha}` | `gh api repos/{owner}/{repo}/commits/{sha}` |
| `github.com/{owner}/{repo}/blob/{ref}/{path}` | `gh api repos/{owner}/{repo}/contents/{path}?ref={ref}` |

### File Contents by Ref

```bash
# Get decoded file content at a specific ref (branch, tag, or SHA)
gh api repos/{owner}/{repo}/contents/{path}?ref={ref} --jq '.content' | base64 -d

# Get raw file content directly (no JSON wrapper)
gh api repos/{owner}/{repo}/contents/{path}?ref={ref} -H "Accept: application/vnd.github.raw+json"
```

### Diff and Patch via API

Use Accept headers to get raw diff or patch output from PRs and commits:

```bash
# PR diff
gh api repos/{owner}/{repo}/pulls/{n} -H "Accept: application/vnd.github.diff"

# PR patch
gh api repos/{owner}/{repo}/pulls/{n} -H "Accept: application/vnd.github.patch"

# Commit diff
gh api repos/{owner}/{repo}/commits/{sha} -H "Accept: application/vnd.github.diff"

# Commit patch
gh api repos/{owner}/{repo}/commits/{sha} -H "Accept: application/vnd.github.patch"
```

## Field Reference

### PR Fields

`number`, `title`, `body`, `state`, `author`, `labels`, `assignees`, `reviewDecision`, `mergeable`, `statusCheckRollup`, `headRefName`, `baseRefName`, `isDraft`, `url`, `createdAt`, `updatedAt`

### Issue Fields

`number`, `title`, `body`, `state`, `author`, `labels`, `assignees`, `comments`, `milestone`, `url`, `createdAt`, `updatedAt`, `closedAt`, `subIssuesSummary`, `type`

### Run Fields

`databaseId`, `name`, `status`, `conclusion`, `jobs`, `createdAt`, `updatedAt`, `url`, `headBranch`, `headSha`, `event`

### Job Fields (within runs)

`name`, `status`, `conclusion`, `startedAt`, `completedAt`, `steps`
