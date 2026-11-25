---
created: 2026-03-19
modified: 2026-11-25
reviewed: 2026-06-15
name: git-issue-manage
description: "Transfer, pin, lock, or open a dev branch from a GitHub issue. Use when moving an issue between repos, pinning or locking it, or bulk-editing custom fields."
args: "<operation> <issue-numbers...> [options]"
argument-hint: <transfer|pin|lock|develop|bulk|fields> <issue-numbers...>
user-invocable: true
allowed-tools: Bash(gh issue *), Bash(gh api *), Bash(git switch *), Bash(git remote *), Read, Grep, Glob, TodoWrite, AskUserQuestion
---

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|---|---|
| Transferring, pinning, locking, or bulk-editing GitHub issues | Use `github-issue-writing` to compose a single issue body well |
| Creating a development branch from an issue (`gh issue develop`) | Use `git-branch-pr-workflow` for general branch + PR design |
| Updating custom issue fields (priority, severity, custom selects) in bulk | Use `github-labels` for label-only operations on issues and PRs |
| Performing bulk operations across many issue numbers in one command | Use `git-triage` to evaluate issues and PRs by completion evidence and CI state |

## Context

- Git remotes: !`git remote -v`

Open issues are fetched during execution (requires a configured git remote).

## Parameters

Parse `$ARGUMENTS[0]` as the operation, remaining args as issue numbers and options.

Issue references accept bare numbers, `#N`, or full GitHub issue URLs
(`https://github.com/<owner>/<repo>/issues/<N>`): strip a leading `#`, and for a
URL extract the trailing `/issues/<N>` number (require trailing digits — a
`/pull/<N>` is not an issue). When a URL's `<owner>/<repo>` differs from the
current remote, pass `-R <owner>/<repo>` to the `gh` calls for that issue.

| Operation | Syntax | Description |
|-----------|--------|-------------|
| `transfer` | `transfer <N> <target-repo>` | Transfer issue to another repository |
| `pin` | `pin <N...>` | Pin issues to repository (max 3) |
| `unpin` | `unpin <N...>` | Unpin issues |
| `lock` | `lock <N...> [--reason <reason>]` | Lock issue discussions |
| `unlock` | `unlock <N...>` | Unlock issue discussions |
| `develop` | `develop <N> [--branch <name>] [--checkout]` | Create branch from issue |
| `bulk` | `bulk <sub-op> <N...> [options]` | Bulk operations on multiple issues |
| `fields` | `fields <N> [--set <field>=<value>] [--list]` | List or set issue field values (org or personal-account fields) |

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

Manage issue fields. Fields are defined on the repository owner: an organization (`orgs/$OWNER/issue-fields`) or, for a personal account, the authenticated user (`user/issue-fields`; there is no `users/{name}` route). Endpoints, value formats, and limits: [REFERENCE.md](REFERENCE.md#custom-issue-fields-api).

**Resolve the owner's field list:**
```bash
gh api repos/$OWNER/$REPO --jq '.owner.type + " " + .owner.login'
```

List with `gh api orgs/$OWNER/issue-fields` when the type is `Organization`, or `gh api user/issue-fields` when it is `User` and the owner is the authenticated user. Show `id`, `name`, `data_type`:
```bash
gh api orgs/$OWNER/issue-fields --jq '.[] | "\(.id): \(.name) (\(.data_type))"'
```

**`--list` — get field values for an issue:**
```bash
gh api repos/$OWNER/$REPO/issues/$N/issue-field-values \
  --jq '.[] | "\(.issue_field_name): \(.single_select_option.name // .value)"'
```

**`--set <field>=<value>` — set a value (write path unverified):**

1. Look up the integer field id by name: `gh api orgs/$OWNER/issue-fields | jq --arg name "$FIELD_NAME" '.[] | select(.name == $name) | .id'`.
2. Write the body `{"issue_field_values":[{"field_id":<id>,"value":<value>}]}` to a file with the Write tool. A single-select value is the option **name**; a number is a JSON number; a date is ISO 8601.
3. Send it: `gh api repos/$OWNER/$REPO/issues/$N/issue-field-values -X POST --input <file>` (POST adds; PUT replaces all values).
4. Re-read the values with the `--list` command and report what the issue now holds. Report the write as unconfirmed if the re-read does not show the value; the write contract comes from the API schema and has not been exercised.

If the owner has no fields defined, the list is empty: report "No issue fields are defined for $OWNER."

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
| 404 on `orgs/{org}/issue-fields` | Owner is a user account, or no access to the org | Retry with `user/issue-fields` for the authenticated user's own repos; otherwise report the access gap |
| Empty list from `issue-fields` | Owner has defined no fields | Report: "No issue fields are defined for this owner" |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Transfer issue | `gh issue transfer N target-repo` |
| Pin issue | `gh issue pin N` |
| Lock issue | `gh issue lock N --reason resolved` |
| Create dev branch | `gh issue develop N --checkout` |
| Bulk close | Loop: `gh issue close N` for each N |
| List issue fields | `gh api orgs/{org}/issue-fields --jq '.[] \| {id, name, data_type}'` (personal: `user/issue-fields`) |
| Get field values | `gh api repos/{o}/{r}/issues/N/issue-field-values` |

## See Also

- **git:issue-hierarchy** skill for sub-issues and dependencies
- **github-issue-writing** skill for creating new issues
- **git:issue** skill for implementing/processing issues
- **gh-cli-agentic** skill for raw API command patterns
- [REFERENCE.md](REFERENCE.md) for issue-field endpoints, value formats, and limits
