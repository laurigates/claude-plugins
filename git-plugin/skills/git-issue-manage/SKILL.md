---
created: 2026-03-19
modified: 2026-04-23
reviewed: 2026-03-19
name: git-issue-manage
description: |
  Administrative operations on GitHub issues. Use when transferring issues
  between repos, pinning important issues, locking resolved discussions,
  creating development branches from issues, performing bulk operations,
  or managing custom issue fields.
args: "<operation> <issue-numbers...> [options]"
argument-hint: <transfer|pin|lock|develop|bulk|fields> <issue-numbers...>
user-invocable: true
allowed-tools: Bash(gh issue *), Bash(gh api *), Bash(git switch *), Bash(git remote *), Read, Grep, Glob, TodoWrite, AskUserQuestion
---

## Context

- Git remotes: !`git remote -v`

Open issues are fetched during execution (requires a configured git remote).

## Parameters

Parse `$ARGUMENTS[0]` as the operation, remaining args as issue numbers and options.

| Operation | Syntax | Description |
|-----------|--------|-------------|
| `transfer` | `transfer <N> <target-repo>` | Transfer issue to another repository |
| `pin` | `pin <N...>` | Pin issues to repository (max 3) |
| `unpin` | `unpin <N...>` | Unpin issues |
| `lock` | `lock <N...> [--reason <reason>]` | Lock issue discussions |
| `unlock` | `unlock <N...>` | Unlock issue discussions |
| `develop` | `develop <N> [--branch <name>] [--checkout]` | Create branch from issue |
| `bulk` | `bulk <sub-op> <N...> [options]` | Bulk operations on multiple issues |
| `fields` | `fields <N> [--set <field>=<value>] [--list]` | Manage custom issue fields |

Lock reasons: `off-topic`, `too heated`, `resolved`, `spam`

Bulk sub-operations: `label`, `assign`, `close`, `reopen`

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Transferring issues between repos | Creating new issues (`github-issue-writing`) |
| Pinning/unpinning important issues | Implementing issue fixes (`git:issue`) |
| Locking resolved discussions | Managing sub-issues/deps (`git:issue-hierarchy`) |
| Creating dev branches from issues | Searching for issues (`github-issue-search`) |
| Bulk labeling/assigning/closing | Auto-detecting related issues (`github-issue-autodetect`) |
| Setting custom field values | |

## Execution

Execute the requested issue management operation.

### Step 1: Parse Operation and Validate

Parse the operation from `$ARGUMENTS[0]`. Validate that specified issue numbers exist:

```bash
gh issue view $N --json number,title,state 2>/dev/null
```

If any issue is not found, report it and skip that issue.

### Step 2: Execute Operation

#### Transfer

Transfer an issue to another repository within the same organization or owner.

```bash
gh issue transfer $N $TARGET_REPO
```

**Prerequisites:**
- Target repo must exist and you must have write access
- Both repos must be owned by the same user/org (or target accepts transfers)

Report the new issue URL after transfer.

#### Pin / Unpin

Pin important issues to the top of the issues list (maximum 3 pinned per repo).

```bash
# Pin
gh issue pin $N

# Unpin
gh issue unpin $N
```

If pinning would exceed the 3-pin limit, report which issues are currently pinned and ask which to unpin.

#### Lock / Unlock

Lock issue threads to prevent further comments.

```bash
# Lock with reason
gh issue lock $N --reason resolved

# Lock without reason
gh issue lock $N

# Unlock
gh issue unlock $N
```

| Reason | When to use |
|--------|-------------|
| `resolved` | Issue is fixed, no further discussion needed |
| `off-topic` | Discussion has drifted from the issue |
| `too heated` | Discussion has become unproductive |
| `spam` | Issue thread contains spam |

#### Develop

Create a development branch linked to the issue.

```bash
# Create branch and switch to it locally
gh issue develop $N --checkout

# Create branch with custom name
gh issue develop $N --name $BRANCH_NAME --checkout

# Create branch without checkout
gh issue develop $N
```

The branch name defaults to `{issue-number}-{issue-title-slug}`. The branch is automatically linked to the issue on GitHub.

#### Bulk Operations

Apply the same operation to multiple issues at once.

**Bulk label:**
```bash
# Pre-check: create any missing labels before applying
for LABEL in $(echo "$LABELS" | tr ',' '\n'); do
  if ! gh label list --search "$LABEL" --json name | jq -e ".[] | select(.name==\"$LABEL\")" >/dev/null 2>&1; then
    echo "Label '$LABEL' not found — skipping (create it first with: gh label create \"$LABEL\")"
    LABELS=$(echo "$LABELS" | sed "s/,$LABEL//;s/$LABEL,//;s/^$LABEL$//")
  fi
done
for N in $ISSUE_NUMBERS; do
  [ -n "$LABELS" ] && gh issue edit $N --add-label "$LABELS"
done
```

**Bulk assign:**
```bash
for N in $ISSUE_NUMBERS; do
  gh issue edit $N --add-assignee "$USERS"
done
```

**Bulk close:**
```bash
for N in $ISSUE_NUMBERS; do
  gh issue close $N
done
```

**Bulk reopen:**
```bash
for N in $ISSUE_NUMBERS; do
  gh issue reopen $N
done
```

Report success/failure count after bulk operations.

#### Custom Fields

Manage custom issue fields (requires org-level issue field configuration).

**List available fields:**
```bash
# Get org name from repo
ORG=$(gh repo view --json owner --jq '.owner.login')

# List fields
gh api orgs/$ORG/issue-fields --jq '.[] | "\(.id): \(.name) (\(.type))"'
```

**Get field values for an issue:**
```bash
gh api repos/$OWNER/$REPO/issues/$N/issue-field-values \
  --jq '.[] | "\(.field.name): \(.value)"'
```

**Set a field value:**
```bash
FIELD_ID=$(gh api orgs/$ORG/issue-fields --jq '.[] | select(.name == "$FIELD_NAME") | .id')

gh api repos/$OWNER/$REPO/issues/$N/issue-field-values \
  -X POST -f field_id=$FIELD_ID -f value="$VALUE"
```

If the repo is not in an organization, report: "Custom issue fields require an organization-level repository."

### Step 3: Report Results

| Operation | Report |
|-----------|--------|
| `transfer` | New issue URL in target repo |
| `pin/unpin` | Confirmation, current pinned issues list |
| `lock/unlock` | Confirmation with lock reason |
| `develop` | Branch name and URL, checkout status |
| `bulk` | Success/failure count per issue |
| `fields` | Field values table or confirmation of update |

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| `unknown command "develop"` | Older `gh` CLI version | Report: "gh issue develop requires gh CLI 2.30+. Update with: gh upgrade" |
| 403 on transfer | No write access to target | Report permission requirement |
| 422 on pin | Already 3 pinned issues | List current pins, ask which to replace |
| 404 on issue-fields | Org doesn't have custom fields | Report: "Custom fields not configured for this organization" |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Transfer issue | `gh issue transfer N target-repo` |
| Pin issue | `gh issue pin N` |
| Lock issue | `gh issue lock N --reason resolved` |
| Create dev branch | `gh issue develop N --checkout` |
| Bulk close | Loop: `gh issue close N` for each N |
| List custom fields | `gh api orgs/{org}/issue-fields --jq '.[].name'` |
| Get field values | `gh api repos/{o}/{r}/issues/N/issue-field-values` |

## See Also

- **git:issue-hierarchy** skill for sub-issues and dependencies
- **github-issue-writing** skill for creating new issues
- **git:issue** skill for implementing/processing issues
- **gh-cli-agentic** skill for raw API command patterns
- [REFERENCE.md](REFERENCE.md) for custom fields API details
