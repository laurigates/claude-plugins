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
