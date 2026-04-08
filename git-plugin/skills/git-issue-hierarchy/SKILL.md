---
created: 2026-03-19
modified: 2026-03-19
reviewed: 2026-03-19
name: git-issue-hierarchy
description: |
  Manage sub-issues and dependency relationships between GitHub issues. Use when
  breaking issues into sub-tasks, checking sub-issue completion progress, or
  marking blocking/blocked-by dependencies between issues.
args: "<parent-issue> [--add <N...>] [--remove <N...>] [--create \"title\"] [--status] [--deps] [--block <N>] [--blocked-by <N>] [--unblock <N>]"
argument-hint: <parent-issue> [--add N] [--status] [--deps] [--block N]
user-invocable: true
allowed-tools: Bash(gh api *), Bash(gh issue *), Bash(git remote *), Read, Grep, Glob, TodoWrite
---

## Context

- Repo: !`git remote get-url origin`
- Parent issue: (parsed from arguments)

## Parameters

Parse these parameters from the command:

| Parameter | Description |
|-----------|-------------|
| `<parent-issue>` | Issue number to manage as parent |
| `--add <N...>` | Add existing issues as sub-issues |
| `--create "<title>"` | Create a new issue and add it as sub-issue |
| `--remove <N...>` | Remove sub-issues from parent |
| `--status` | Show sub-issue completion progress |
| `--list` | List all sub-issues of the parent |
| `--deps` | Show dependency graph for the issue |
| `--block <N>` | Mark parent issue as blocking issue N |
| `--blocked-by <N>` | Mark parent issue as blocked by issue N |
| `--unblock <N>` | Remove blocking relationship with issue N |

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Breaking issues into sub-tasks | Creating standalone issues (`github-issue-writing`) |
| Checking sub-issue completion progress | Implementing/processing issues (`git:issue`) |
| Adding dependency relationships | Auto-detecting related issues (`github-issue-autodetect`) |
| Viewing dependency graph | Searching for OSS solutions (`github-issue-search`) |

## Execution

Execute the requested issue hierarchy operation.

### Step 1: Resolve Repository Context

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)
```

Verify the parent issue exists:

```bash
gh issue view $PARENT --json number,title,state,subIssuesSummary
```

### Step 2: Branch on Operation Mode

Determine which operation to perform based on parsed parameters.

**If `--status` (or no flags):**
Display sub-issue summary and list.

**If `--add`:**
Add existing issues as sub-issues.

**If `--create`:**
Create new issue, then add as sub-issue.

**If `--remove`:**
Remove specified sub-issues.

**If `--list`:**
List all sub-issues with their states.

**If `--deps`, `--block`, `--blocked-by`, `--unblock`:**
Manage dependency relationships.

### Step 3: Execute API Calls

#### Sub-Issue Status

```bash
# Get summary
gh issue view $PARENT --json title,state,subIssuesSummary

# List all sub-issues with details
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'
```

Report format:
```
Issue #42: Refactor authentication system
Sub-issues: 3/5 completed (60%)

  #43 ✓ Extract token validation
  #44 ✓ Add refresh token support
  #45 ✓ Update OAuth provider
  #46 ○ Migrate session storage
  #47 ○ Update API documentation
```

#### Add Sub-Issues

For each issue number in `--add`:

```bash
# Get the issue's node ID (required for sub_issue_id)
CHILD_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$CHILD --jq '.id')

# Add as sub-issue
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues \
  -f sub_issue_id=$CHILD_ID
```

Verify each was added successfully. Report any errors (e.g., issue not found, already a sub-issue, sub-issues not enabled).

#### Create and Add Sub-Issue

```bash
# Create the new issue
NEW_ISSUE=$(gh issue create --title "$TITLE" --body "Parent: #$PARENT" --json number --jq '.number')

# Get its ID
NEW_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$NEW_ISSUE --jq '.id')

# Add as sub-issue
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues \
  -f sub_issue_id=$NEW_ID
```

#### Remove Sub-Issues

For each issue number in `--remove`:

```bash
# Get the sub-issue ID from the sub-issues list
SUB_ISSUE_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues \
  --jq ".[] | select(.number == $CHILD) | .id")

# Remove it
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues/$SUB_ISSUE_ID -X DELETE
```

#### Dependency Management

Dependencies use issue body text conventions that GitHub renders as tracked relationships.

**Add "blocks" relationship (`--block <N>`):**

1. Read current body of issue N: `gh issue view $N --json body --jq '.body'`
2. Append `Blocked by #$PARENT` to a `## Dependencies` section in issue N's body
3. Update: `gh issue edit $N --body "$UPDATED_BODY"`

**Add "blocked by" relationship (`--blocked-by <N>`):**

1. Read current body of parent issue: `gh issue view $PARENT --json body --jq '.body'`
2. Append `Blocked by #$N` to a `## Dependencies` section
3. Update: `gh issue edit $PARENT --body "$UPDATED_BODY"`

**Remove relationship (`--unblock <N>`):**

1. Read both issue bodies
2. Remove `Blocked by #$PARENT` from issue N and `Blocked by #$N` from parent
3. Update both issues

**Show dependency graph (`--deps`):**

1. Read issue body for dependency keywords: `Blocked by #N`, `Blocks #N`
2. Recursively scan referenced issues
3. Build and display dependency tree

```
#42 Refactor authentication
├── Blocked by: #40 Database migration (✓ closed)
├── Blocks: #45 Deploy auth v2
└── Sub-issues:
    ├── #43 ✓ Extract token validation
    └── #44 ○ Add refresh token support
```

### Step 4: Report Results

Report what was done:

| Operation | Report Format |
|-----------|---------------|
| `--status` | Summary with completion percentage and sub-issue list |
| `--add` | Confirmation of each added sub-issue |
| `--create` | New issue number + confirmation added as sub-issue |
| `--remove` | Confirmation of each removed sub-issue |
| `--deps` | Dependency tree visualization |
| `--block/--blocked-by` | Confirmation of relationship added |

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| 404 on sub_issues endpoint | Sub-issues not enabled for repo | Report: "Sub-issues are not available for this repository. Enable them in repository settings." |
| 422 on add sub-issue | Issue already a sub-issue or circular reference | Report the specific error |
| Issue not found | Invalid issue number | Report which issue number was not found |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick sub-issue status | `gh issue view N --json title,subIssuesSummary` |
| List sub-issues | `gh api repos/{o}/{r}/issues/{N}/sub_issues --jq '.[].number'` |
| Add sub-issue | `gh api repos/{o}/{r}/issues/{N}/sub_issues -f sub_issue_id=M` |
| Remove sub-issue | `gh api repos/{o}/{r}/issues/{N}/sub_issues/M -X DELETE` |
| Check dependencies | `gh issue view N --json body --jq '.body'` then parse for "Blocked by" |

## See Also

- **github-issue-writing** skill for creating standalone issues
- **git:issue** skill for implementing/processing issues
- **gh-cli-agentic** skill for raw API patterns
