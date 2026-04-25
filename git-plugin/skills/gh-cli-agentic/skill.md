---
name: gh-cli-agentic
description: |
  GitHub CLI commands optimized for AI agent workflows with JSON output and
  deterministic execution patterns. Use when the user asks to query PRs,
  issues, workflow runs, or repo metadata with gh, inspect PR checks or
  mergeable status, fetch failed CI logs, work with sub-issues, or resolve
  a github.com URL into an API call.
user-invocable: false
allowed-tools: Bash(gh pr *), Bash(gh run *), Bash(gh issue *), Bash(gh repo *), Bash(gh workflow *), Bash(gh api *), Read
created: 2025-01-16
modified: 2026-04-25
reviewed: 2026-04-25
---

# GitHub CLI Agentic Patterns

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Querying PRs, issues, runs, or repo metadata with `gh` and need JSON output | Use `git-cli-agentic` for porcelain-mode local git queries (status, diff, log) |
| Inspecting PR checks, mergeable status, or fetching failed CI logs | Use `gh-workflow-monitoring` to actively watch a run until it completes |
| Resolving a github.com URL into an `gh api` call or working with sub-issues | Use `git-issue-hierarchy` for sub-issue add/remove/dependency-graph operations |
| Looking up label, repo, or workflow metadata via `gh` JSON commands | Use `github-labels` to actually apply or create labels on issues/PRs |

Optimized `gh` commands for AI agent consumption using JSON output and structured field selection.

## Core Principle

Always use `--json <fields>` for machine-readable output. The `--jq` filter is built-in (no jq installation required).

## Pull Request Operations

### Check Status

```bash
# Get all check statuses
gh pr checks $PR_NUMBER --json name,state,conclusion,detailsUrl

# Filter to failed only
gh pr checks $PR_NUMBER --json name,state,conclusion --jq '.[] | select(.conclusion == "FAILURE")'
```

**Fields**: `name`, `state`, `conclusion`, `detailsUrl`, `startedAt`, `completedAt`

### PR Details

```bash
# Essential PR info
gh pr view $PR_NUMBER --json number,title,state,mergeable,statusCheckRollup

# Full context
gh pr view $PR_NUMBER --json number,title,body,state,author,labels,assignees,reviewDecision,mergeable,statusCheckRollup
```

**Key Fields**:

| Field | Description |
|-------|-------------|
| `mergeable` | `MERGEABLE`, `CONFLICTING`, `UNKNOWN` |
| `reviewDecision` | `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED` |
| `statusCheckRollup` | Array of check statuses |

### List PRs

```bash
# Open PRs
gh pr list --json number,title,author,labels

# PRs by author
gh pr list --author @me --json number,title,state

# PRs needing review
gh pr list --search "review-requested:@me" --json number,title
```

## Workflow Run Operations

### Run Details

```bash
# Get run status with jobs
gh run view $RUN_ID --json conclusion,status,jobs,createdAt,updatedAt

# List recent runs
gh run list --json databaseId,status,conclusion,name,createdAt -L 10
```

**Status Values**: `queued`, `in_progress`, `completed`
**Conclusion Values**: `success`, `failure`, `cancelled`, `skipped`, `neutral`

### Watch Run Until Completion

```bash
# Watch and wait for run to complete (blocking, no timeout needed)
gh run watch $RUN_ID --compact --exit-status

# Find and watch latest run
RUN_ID=$(gh run list -L 1 --json databaseId --jq '.[0].databaseId')
gh run watch $RUN_ID --compact --exit-status
```

See **gh-workflow-monitoring** skill for comprehensive workflow watching patterns.

### Failed Logs

```bash
# Get only failed step logs (most useful for debugging)
gh run view $RUN_ID --log-failed

# Full logs (verbose)
gh run view $RUN_ID --log
```

### Workflow Triggers

```bash
# Trigger workflow manually
gh workflow run $WORKFLOW_NAME

# Trigger with inputs
gh workflow run $WORKFLOW_NAME -f param1=value1 -f param2=value2

# List workflows
gh workflow list --json name,state,path
```

## Issue Operations

### Issue Details

```bash
# Full issue context
gh issue view $ISSUE_NUMBER --json number,title,body,state,labels,assignees,comments

# Minimal
gh issue view $ISSUE_NUMBER --json number,title,state,labels

# With sub-issue progress
gh issue view $ISSUE_NUMBER --json number,title,state,subIssuesSummary
```

### List Issues

```bash
# Open issues
gh issue list --json number,title,labels,assignees

# By label
gh issue list --label "bug" --json number,title

# Assigned to me
gh issue list --assignee @me --json number,title,state
```

### Issue Types

```bash
# Create issue with type (requires repo/org with issue types configured)
gh issue create --title "..." --body "..." --type "Bug"
gh issue create --title "..." --body "..." --type "Feature"
gh issue create --title "..." --body "..." --type "Task"
```

### Sub-Issues

```bash
# List sub-issues of a parent
gh api repos/{owner}/{repo}/issues/{parent}/sub_issues --jq '.[].number'

# Add existing issue as sub-issue
gh api repos/{owner}/{repo}/issues/{parent}/sub_issues -f sub_issue_id={child_id}

# Remove sub-issue
gh api repos/{owner}/{repo}/issues/{parent}/sub_issues/{sub_issue_id} -X DELETE

# Reprioritize sub-issue (move after another sub-issue)
gh api repos/{owner}/{repo}/issues/{parent}/sub_issues -X PATCH \
  -f sub_issue_id={id} -f after_id={after_id}

# Get sub-issue summary via issue view
gh issue view {N} --json title,subIssuesSummary
# Returns: {"total": 5, "completed": 3, "percentCompleted": 60}
```

### Custom Issue Fields

```bash
# List available fields for an org
gh api orgs/{org}/issue-fields --jq '.[].name'

# Get field values for an issue
gh api repos/{owner}/{repo}/issues/{N}/issue-field-values

# Set field value
gh api repos/{owner}/{repo}/issues/{N}/issue-field-values \
  -X POST -f field_id={id} -f value='{value}'
```

### Issue Management

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

## Repository Operations

```bash
# Get repo info
gh repo view --json nameWithOwner,defaultBranchRef,description

# Just owner/name
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

## API Direct Access

For operations not covered by subcommands:

```bash
# Get specific data
gh api repos/{owner}/{repo}/actions/runs --jq '.workflow_runs[:5]'

# With pagination
gh api repos/{owner}/{repo}/issues --paginate --jq '.[].number'
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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| CI diagnosis | `gh pr checks $N --json name,state,conclusion,detailsUrl` |
| Get failure logs | `gh run view $ID --log-failed` |
| PR merge status | `gh pr view $N --json mergeable,reviewDecision,statusCheckRollup` |
| Quick issue list | `gh issue list --json number,title,labels -L 10` |
| Sub-issue progress | `gh issue view $N --json title,subIssuesSummary` |
| List sub-issues | `gh api repos/{o}/{r}/issues/{N}/sub_issues --jq '.[].number'` |
| Add sub-issue | `gh api repos/{o}/{r}/issues/{N}/sub_issues -f sub_issue_id=M` |
| Transfer issue | `gh issue transfer N target-repo` |
| Create dev branch | `gh issue develop N --checkout` |
| Workflow trigger | `gh workflow run $NAME` |

## Error Handling in Context

Use `2>/dev/null` to suppress errors in context expressions (do NOT use `||` fallbacks - blocked by Claude Code 2.1.7+):

```markdown
- PR checks: !`gh pr checks $PR --json name,state,conclusion`
- Run status: !`gh run view $ID --json status,conclusion`
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
