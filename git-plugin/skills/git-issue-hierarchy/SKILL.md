---
created: 2026-03-19
modified: 2026-04-25
reviewed: 2026-04-25
name: git-issue-hierarchy
description: |
  Manage sub-issues and native GitHub dependency relationships (blocked_by /
  blocking) between issues. Use when breaking issues into sub-tasks, checking
  sub-issue completion progress, marking one issue as blocked by another, or
  viewing a dependency graph before starting work.
args: "<parent-issue> [--add <N...>] [--remove <N...>] [--create \"title\"] [--status] [--deps] [--blocking] [--block <N>] [--blocked-by <N>] [--unblock <N>]"
argument-hint: <parent-issue> [--add N] [--status] [--deps] [--blocked-by N]
user-invocable: true
allowed-tools: Bash(gh api *), Bash(gh issue *), Bash(git remote *), Read, Grep, Glob, TodoWrite
---

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Adding/removing native GitHub sub-issues to a parent issue | Use `git-issue-manage` for transfer, pin, lock, develop-branch operations |
| Marking issue A as `blocked_by` issue B (or unblocking) | Use `github-issue-writing` to create well-structured issue bodies in the first place |
| Viewing a parent issue's sub-issue completion progress and dependency graph | Use `git-issue` to actually start working on issues end-to-end |
| Checking the dependency graph before starting work on a multi-issue feature | Use `gh-cli-agentic` for raw `gh issue --json` queries without hierarchy logic |

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
| `--deps` | Show dependency graph (blocked_by + blocking + sub-issues) for the issue |
| `--blocking` | List issues the parent is blocking |
| `--block <N>` | Mark issue N as blocked by the parent (parent blocks N) |
| `--blocked-by <N>` | Mark the parent as blocked by issue N |
| `--unblock <N>` | Remove blocking relationship with issue N in either direction |

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Breaking issues into sub-tasks | Creating standalone issues (`github-issue-writing`) |
| Checking sub-issue completion progress | Implementing/processing issues (`git:issue`) |
| Recording `blocked_by` / `blocking` dependencies | Auto-detecting related issues (`github-issue-autodetect`) |
| Viewing a blocker graph before picking work | Searching for OSS solutions (`github-issue-search`) |

### Sub-issues vs. dependencies vs. "related to"

GitHub ships three distinct ways to link issues. Pick the right one — they're
not interchangeable:

| Relationship | When to use | API surface |
|--------------|-------------|-------------|
| **Sub-issue** (parent ↔ child) | Child issue is a *part of* the parent's scope. Completing all children fulfils the parent. | `issues/{N}/sub_issues` |
| **Blocked by** (hard dependency) | Parent *cannot start or ship* until the other issue closes. Makes the blocked issue render a "Blocked" badge on boards. | `issues/{N}/dependencies/blocked_by` |
| **Blocking** (read-only inverse) | You want to see everything *this* issue gates. Managed by creating `blocked_by` links on the other side. | `issues/{N}/dependencies/blocking` |
| **"Related to #N" in body** | Soft cross-reference, no lifecycle coupling, no board indicator. | Plain markdown — no API needed |

Sub-issues express **composition** ("is part of"). Dependencies express
**ordering** ("must happen before"). The same two issues should rarely use
both — a sub-issue is implicitly ordered by its parent's scope.

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

**If `--deps`, `--blocking`, `--block`, `--blocked-by`, `--unblock`:**
Manage native GitHub issue dependencies via the `dependencies/blocked_by` and
`dependencies/blocking` API endpoints.

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

Dependencies use GitHub's native `dependencies/blocked_by` and
`dependencies/blocking` endpoints. They appear in the issue sidebar under
"Relationships" and mark the blocked issue with a "Blocked" badge on project
boards. Both endpoints require the target issue's **node id** (`.id` on the
issue payload), not the human-readable issue number.

**Add "blocked by" relationship (`--blocked-by <N>`): parent is blocked by N**

```bash
# Resolve the blocker's node id
BLOCKER_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$N --jq '.id')

# Record the dependency on the parent
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocked_by \
  -f issue_id=$BLOCKER_ID
```

**Add "blocks" relationship (`--block <N>`): parent blocks issue N**

The API is one-directional — write the relationship on the *blocked* side:

```bash
# Resolve the parent's node id
PARENT_ID=$(gh api repos/$OWNER/$REPO_NAME/issues/$PARENT --jq '.id')

# Record on issue N that it is blocked by the parent
gh api repos/$OWNER/$REPO_NAME/issues/$N/dependencies/blocked_by \
  -f issue_id=$PARENT_ID
```

**Remove relationship (`--unblock <N>`):**

Look up which side carries the link, then delete it. The `DELETE` path takes
the stored dependency's `{issue_id}` segment:

```bash
# Is the parent blocked by N?
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocked_by \
  --jq ".[] | select(.number == $N) | .id"

# Or does the parent block N?
gh api repos/$OWNER/$REPO_NAME/issues/$N/dependencies/blocked_by \
  --jq ".[] | select(.number == $PARENT) | .id"

# Delete whichever is present
gh api repos/$OWNER/$REPO_NAME/issues/$ISSUE/dependencies/blocked_by/$DEP_ID \
  -X DELETE
```

**List what the parent blocks (`--blocking`):**

```bash
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocking \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'
```

**Show dependency graph (`--deps`):**

Combine both dependency endpoints with the sub-issues summary. Do not parse
issue bodies — the native API is authoritative:

```bash
# What blocks the parent
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocked_by \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'

# What the parent blocks
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/dependencies/blocking \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'

# Sub-issues (composition, not ordering)
gh api repos/$OWNER/$REPO_NAME/issues/$PARENT/sub_issues \
  --jq '.[] | "#\(.number) \(.state) \(.title)"'
```

Render output as:

```
#42 Refactor authentication
├── Blocked by: #40 Database migration (✓ closed)
├── Blocks:     #45 Deploy auth v2 (○ open)
└── Sub-issues:
    ├── #43 ✓ Extract token validation
    └── #44 ○ Add refresh token support
```

Surface `Blocked by` entries that are still `open` prominently — those are
what prevent the parent from starting.

### Step 4: Report Results

Report what was done:

| Operation | Report Format |
|-----------|---------------|
| `--status` | Summary with completion percentage and sub-issue list |
| `--add` | Confirmation of each added sub-issue |
| `--create` | New issue number + confirmation added as sub-issue |
| `--remove` | Confirmation of each removed sub-issue |
| `--deps` | Dependency tree visualization (blocked_by + blocking + sub-issues) |
| `--blocking` | List of issues the parent blocks |
| `--block/--blocked-by` | Confirmation of relationship added, rendered with direction |
| `--unblock` | Confirmation of relationship removed |

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

## See Also

- **github-issue-writing** skill for creating standalone issues
- **git:issue** skill for implementing/processing issues
- **gh-cli-agentic** skill for raw API patterns
