---
created: 2026-03-19
modified: 2026-08-15
reviewed: 2026-04-25
name: git-issue-hierarchy
description: "GitHub sub-issues and blocked_by/blocking links. Use when breaking an issue into sub-tasks, checking parent progress, or viewing a dependency graph."
args: "<parent-issue (number | #N | URL)> [--add <N...>] [--remove <N...>] [--create \"title\"] [--status] [--deps] [--blocking] [--block <N>] [--blocked-by <N>] [--unblock <N>]"
argument-hint: "<parent-issue (number|#N|URL)> [--add N] [--status] [--deps] [--blocked-by N]"
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

- Repo: !`git remote -v`
- Parent issue: (parsed from arguments)

## Parameters

Parse these parameters from the command:

Every issue argument — `<parent-issue>` and each `<N>` flag value below — is
accepted as a bare number, `#N`, or a full GitHub issue URL, and normalized to a
`(number, repo)` pair in Step 0.

| Parameter | Description |
|-----------|-------------|
| `<parent-issue>` | Parent issue as a bare number, `#N`, or full GitHub issue URL (`https://github.com/<owner>/<repo>/issues/<N>`) — see Step 0 |
| `--add <N...>` | Add existing issues as sub-issues (each `N` as number, `#N`, or URL) |
| `--create "<title>"` | Create a new issue and add it as sub-issue |
| `--remove <N...>` | Remove sub-issues from parent (each `N` as number, `#N`, or URL) |
| `--status` | Show sub-issue completion progress |
| `--list` | List all sub-issues of the parent |
| `--deps` | Show dependency graph (blocked_by + blocking + sub-issues) for the issue |
| `--blocking` | List issues the parent is blocking |
| `--block <N>` | Mark issue N as blocked by the parent (parent blocks N); `N` as number, `#N`, or URL |
| `--blocked-by <N>` | Mark the parent as blocked by issue N; `N` as number, `#N`, or URL |
| `--unblock <N>` | Remove blocking relationship with issue N in either direction; `N` as number, `#N`, or URL |

Sub-issues express composition ("is part of"); `blocked_by` dependencies express ordering ("must happen before"). When unsure which link fits, see [references/relationship-types.md](references/relationship-types.md).

## Execution

Execute the requested issue hierarchy operation.

### Step 0: Normalize issue references

Before any API call, normalize `<parent-issue>` **and every issue value passed
to a flag** (`--add`, `--remove`, `--block`, `--blocked-by`, `--unblock`) into a
`(number, repo)` pair. Accept these forms:

| Input form | Extract |
|------------|---------|
| `123` | number `123`, repo = current remote |
| `#123` | number `123`, repo = current remote |
| `https://github.com/<owner>/<repo>/issues/123` | number `123`, repo = `<owner>/<repo>` |
| `.../issues/123#issuecomment-...` | number `123` (drop the `#...` fragment), repo = `<owner>/<repo>` |

Rules:

1. Strip a leading `#`; strip a URL `#...` fragment after the number. A token is
   an issue ref only if, after stripping, it is all digits **or** matches the
   `/issues/<digits>` URL shape (require trailing digits — a `/pull/<N>`,
   `/discussions/<N>`, or bare `/issues` list URL is **not** a ref).
2. For the plural flags (`--add`/`--remove`, which take `<N...>`), normalize
   each space-separated value independently; never split a single URL into two
   refs.
3. For a URL whose `<owner>/<repo>` differs from the current remote (Step 1
   `REPO`), record it as **cross-repo** and carry `-R <owner>/<repo>` on every
   `gh issue` call and target `repos/<owner>/<repo>/…` on every `gh api` call
   for that issue. Sub-issue and dependency links require both endpoints to live
   in the **same** repo — if a normalized ref points at a different repo than
   the parent, surface that rather than issuing a mismatched cross-repo link.

Downstream steps use the normalized `$PARENT`, `$N`, and `$CHILD` **numbers**;
where a ref was cross-repo, substitute its `<owner>/<repo>` for `$OWNER`/`$REPO_NAME`
and add `-R <owner>/<repo>` to the corresponding `gh issue` call.

### Step 1: Resolve Repository Context

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
OWNER=$(echo "$REPO" | cut -d/ -f1)
REPO_NAME=$(echo "$REPO" | cut -d/ -f2)
```

If Step 0 normalized `<parent-issue>` to a **cross-repo** URL, use that URL's
`<owner>/<repo>` as `$OWNER`/`$REPO_NAME` (and pass `-R <owner>/<repo>` to the
`gh issue view` below) instead of the current remote.

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

For `--blocked-by`, `--block`, `--unblock`, `--blocking`, and `--deps`, run the calls in [references/dependencies.md](references/dependencies.md). Both dependency endpoints take the target issue's node id (`.id`), not its number, and the `--deps` view reads the native API rather than issue bodies.

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

On a 404 or 422 from the sub-issue or dependency endpoints, see [references/commands.md](references/commands.md) for the cause and what to report.

## See Also

- **github-issue-writing** skill for creating standalone issues
- **git:issue** skill for implementing/processing issues
- **gh-cli-agentic** skill for raw API patterns
