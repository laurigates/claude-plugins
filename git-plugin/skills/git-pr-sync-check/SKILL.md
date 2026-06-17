---
name: git-pr-sync-check
description: "Checks whether the current PR branch is still live and in sync (merged/behind/changes-requested). Use when continuing work on a PR branch before adding commits."
args: "[--project-dir <path>]"
argument-hint: "[--project-dir <path>]"
allowed-tools: Bash(bash *), Bash(git fetch *), Bash(git rev-list *), Bash(git status *), Bash(git branch *), Bash(gh pr view *), Read, TodoWrite
created: 2026-06-17
modified: 2026-06-17
reviewed: 2026-06-17
---

# /git:pr-sync-check

Read-only guard that answers one question before you build further on a PR
branch: **is this branch still live and in sync with the remote?** It fetches
origin, computes ahead/behind, and reads the branch's PR state, then returns a
single `VERDICT`. Read-only — it fetches but never changes branch or working-tree
state.

## When to Use This Skill

| Use this skill when... | Use the alternative when... |
|------------------------|-----------------------------|
| An **additional in-session request** continues work on a branch that already has a PR | Starting brand-new work — just create a branch |
| About to add commits to a branch whose PR may have **merged** while you worked | Use `/git:pr-feedback` to *act on* review threads once you know there are some |
| A push was rejected, or you suspect a teammate / another agent / a CI auto-fix **pushed under you** | Use `/git:coworker-check` for *local-checkout* coworker collisions (uncommitted files) |
| You want CI / review state for the current branch's PR at a glance | Use `/git:triage` to categorize **many** PRs at once |

This is the *remote* sibling of `/git:coworker-check` (which detects local
uncommitted-file collisions). See `.claude/rules/pr-branch-sync.md` for the
rationale and `.claude/rules/agent-coworker-detection.md` for the local case.

## Context

- Current branch: !`git branch --show-current`
- Tracking / ahead-behind: !`git status --porcelain=v2 --branch`

## Parameters

Parse `$ARGUMENTS`:

| Flag | Effect |
|------|--------|
| `--project-dir <path>` | Run against a specific checkout/worktree (default: current dir) |

## Execution

Run this check, then act on the verdict.

### Step 1: Run the detection script

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/check-pr-sync.sh --project-dir "$(pwd)"
```

The script emits a structured block (per
`.claude/rules/structured-script-output.md`) with `BRANCH`, `AHEAD`, `BEHIND`,
`PR_NUMBER`, `PR_STATE`, `MERGED_AT`, `REVIEW_DECISION`, `CI_STATUS`, a single
`STATUS=` and a single `VERDICT=`.

### Step 2: Interpret the verdict

Parse the `VERDICT=` line and act:

| `VERDICT` | Meaning | Action |
|-----------|---------|--------|
| `in_sync` | Branch tracks an open PR and is up to date | Proceed — keep building on this branch |
| `behind` | Local tip is behind `origin/<branch>` | **Reconcile first** — `git pull --rebase` (or resolve the divergence) so you build on the current tip and avoid a rejected push / needless conflict, then continue |
| `pr_merged` | The branch's PR is **MERGED** (`PR_STATE=MERGED`, `MERGED_AT` set) | **Stop adding commits here.** The merged branch is a dead end; create a fresh branch off the updated default (`git fetch && git switch -c <new> origin/<default>`) and put the new work there |
| `pr_closed` | The PR is CLOSED unmerged | Confirm this branch is still where the work belongs before adding commits; if the PR was abandoned, branch off the default instead |
| `changes_requested` | The PR has `CHANGES_REQUESTED` reviews | Address the review via `/git:pr-feedback` **before** piling on unrelated work |
| `no_pr` | On the default branch, or no PR for this branch | No PR-branch staleness to worry about — proceed |
| `no_remote` | Not a git repo, or no `origin` remote | Nothing to check; proceed |

If `CI_STATUS=FAILING` on an otherwise-`in_sync` branch, surface it and consider
`/git:fix-pr` before adding more on top of red CI.

### Step 3: Report

Print the verdict, the ahead/behind counts, the PR number/state, and the
recommended next action. If the verdict is anything other than `in_sync` /
`no_pr` / `no_remote`, **stop and reconcile** (or ask the user) before adding
commits.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| One-line verdict | `bash scripts/check-pr-sync.sh \| awk -F= '/^VERDICT=/{print $2}'` |
| Full structured block | `bash scripts/check-pr-sync.sh --project-dir "$(pwd)"` |
| Behind count only | `bash scripts/check-pr-sync.sh \| awk -F= '/^BEHIND=/{print $2}'` |

## Related Skills

- `/git:coworker-check` — local-checkout sibling (uncommitted-file collisions)
- `/git:pr-feedback` — act on review threads / failing CI once detected
- `/git:pr-watch` — subscribe to a PR and react to reviews/CI as they arrive
- `/git:triage` — categorize many PRs at once (`mergeStateStatus` / `mergedAt`)
- `/git:fix-pr` — fix failing PR checks
