---
created: 2025-12-16
modified: 2026-11-14
reviewed: 2026-11-10
name: github-labels
description: "GitHub labels via gh CLI and the build:/area:/needs: taxonomy. Use when labeling a PR or issue, checking which labels a repo has, or creating a label."
user-invocable: false
allowed-tools: Bash(gh label list *), Bash(gh issue view *), Bash(gh issue edit *), Bash(gh pr edit *), Bash(gh pr create *), Bash(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/issue-labels.py *), Read, Grep, Glob
---

# GitHub Labels

Reference for discovering and applying labels to GitHub PRs and issues, and for
the prefix taxonomy a repository may follow.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Listing available labels in a repo | Creating or managing milestones |
| Adding or removing labels on PRs/issues | Managing GitHub Projects boards |
| Choosing a `build:`, `area:`, `core:` or `needs:` label | Bulk-editing many issues at once |
| Inheriting labels from issue to PR | Setting PR reviewers or assignees |
| Provisioning or auditing a repo's label taxonomy | Linking issues by dependency (`git-issue-hierarchy`) |

## Read the Repository's Labels First

The labels a repository has are its vocabulary. Apply those, and read them
before choosing:

1. Read `.github/issue-labels.json` when it exists. It is the repo's taxonomy
   file: its `build:` and `area:` labels, and the paths and title scopes that
   select each one.
2. List every label:

```bash
gh label list --limit 500 --json name,description,color

# Search for specific labels
gh label list --limit 500 --search "bug"
```

`gh label list` returns 30 labels unless `--limit` says otherwise, so on a
larger repo a label that exists reads as missing.

## Prefix Meanings

| Label | Says | Defined in |
|-------|------|------------|
| `bug`, `enhancement`, `chore`, `docs`, `security`, `refactor` | Type: the kind of change. One per issue or PR | The standard set shared by the owner's repos |
| `build:<name>` | The build in a monorepo it belongs to: one firmware, app or package among several | The repo's taxonomy file |
| `area:<name>` | A toolchain or subsystem that cuts across builds | The repo's taxonomy file |
| `core:<name>` | Repo machinery: `core:ci`, `core:quality`, `core:agent`, `core:build`, `core:components`, `core:docs` | The standard set |
| `needs:hardware`, `needs:decision`, `needs:human`, `blocked` | What stops the issue being picked up | The standard set |

An issue carries one type label and at least one routing label (`build:`,
`area:` or `core:`). A repository that does not use these prefixes is labelled
with whatever `gh label list` shows.

To add a `build:` or `area:` label, add an entry to the taxonomy file; the
`provision` subcommand creates it. A label from the standard set is added
wherever the owner manages that set (often infrastructure as code), because a
`gh label create` for one of them drifts from it. Ask before creating any other
label.

## What Stops an Issue: Who Sets and Clears It

| Label | Set by | Cleared by |
|-------|--------|------------|
| `needs:hardware` | An agent or the maintainer, when the next step needs physical hardware: a bench check, a test print, a measurement | The maintainer, or an agent recording the maintainer's result in a comment. Automation leaves it alone |
| `needs:decision` | An agent stopping on a call that is the maintainer's, with a comment giving the options and a recommendation | Whoever records the decision in a comment |
| `needs:human` | An agent, when the work needs a live session, credentials, local data or a scheduled run | The maintainer, or the agent that lands the work |
| `blocked` | Together with a `blocked_by` dependency link when the blocker is an issue; by hand when it is a PR or an upstream change | The `unblock` subcommand for linked issues; by hand otherwise |

The dependency link is the record and `blocked` shows it on the issue list.
Add the link with the `git-issue-hierarchy` skill (`--blocked-by <N>`), then
the label. A `blocked` label with no link behind it is cleared by a person,
since nothing records what it waits for.

The REST write is `POST repos/<owner>/<repo>/issues/<n>/dependencies/blocked_by`
with the blocker's integer `id` (`-F issue_id=<id>`, not its number), as
GitHub's REST reference documents it. The two read endpoints
(`dependencies/blocked_by`, `dependencies/blocking`) were checked against the
live API on 2026-11-10; the write call is pending verification against it.

## The issue-labels Script

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/issue-labels.py" <subcommand> --repo <owner>/<repo>
```

| Subcommand | Does | Writes |
|------------|------|--------|
| `provision` | Creates the taxonomy file's missing `build:` and `area:` labels, updates colour and (when the entry gives one) description, renames through `renamed_from`. Refuses any other name and deletes nothing. `--dry-run` prints the actions | Labels |
| `classify --issue <N>` or `--pr <N>` | Prints the labels the item's title, body and changed files point at, as JSON (`add`). A prefix that already has a label is skipped. It does not set `security` | Nothing |
| `validate --issue <N> --labels-file <file>` | Filters labels a model proposed: type labels and `build:`/`area:`/`core:`/`needs:` names that exist in the repo. A `needs:` label is kept only with a quote found in the issue, and of two type labels only the first | Nothing |
| `unblock --issue <N>` | After issue N closes, removes `blocked` from each open issue it was blocking whose `blocked_by` issues are all closed | Removes `blocked` |
| `audit` | Lists open issues with no type label, no routing label, `blocked` without a link, an open `blocked_by` link without `blocked`, or a `needs:` label older than `--needs-stale-days` (30) | Nothing |

`classify` reads a title in three forms:

| Title | Type | Scope looked up in the taxonomy |
|-------|------|---------------------------------|
| `[Bug] parser: crashes on empty input` | `bug` | `parser` |
| `fix(parser): handle empty input` | `bug` | `parser` |
| `parser: crashes on empty input` | none | `parser` |

An issue whose title scope matches nothing is routed by the repo paths its body
quotes; a PR by its changed files. A body token is a path only when it has a
`/` or a `.`: `docs/` and `./justfile` are paths, the words "docs" and
"justfile" are not. `classify` and `validate` only print labels;
apply them with `gh issue edit <N> --add-label`. `audit` findings come back as
`STATUS=WARN` with exit 0, and a failed read as `STATUS=ERROR` with exit 1.

## Adding Labels to PRs

```bash
# Single label
gh pr create --label "bug"

# Multiple labels (repeat flag)
gh pr create --label "bug" --label "area:parser"

# Comma-separated
gh pr create --label "bug,area:parser"

# Add to existing PR
gh pr edit 123 --add-label "core:ci"
```

## Adding Labels to Issues

```bash
# Create with labels
gh issue create --label "bug,build:firmware"

# Add to existing issue
gh issue edit 123 --add-label "needs:decision"

# Remove label
gh issue edit 123 --remove-label "needs:decision"
```

## Label Inheritance Pattern

When creating a PR from an issue:
1. Read issue labels via `gh issue view N --json labels`
2. Apply the type and routing labels to the PR: `gh pr create --label "label1,label2"`

The `needs:` and `blocked` labels describe the issue's state and stay on the
issue.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List all labels (machine-readable) | `gh label list --limit 500 --json name,description,color` |
| Get label names only | `gh label list --limit 500 --json name -q '.[].name'` |
| Derive labels for an issue | `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/issue-labels.py" classify --repo $REPO --issue $ISSUE` |
| Sweep open issues for label gaps | `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/issue-labels.py" audit --repo $REPO` |
| Add label to PR silently | `gh pr edit $PR --add-label "label"` |
| Check current issue labels | `gh issue view $ISSUE --json labels -q '.labels[].name'` |
