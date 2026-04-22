---
name: git-triage
description: |
  Triage open GitHub issues and PRs in one sweep. Scans the codebase and merged PRs for
  evidence of issue completion, evaluates PR CI state, merge readiness, and review
  decision, flags stale items, and cross-links issues to the PRs that resolve them.
  Recommends actions by default; only closes or merges with explicit --auto-close or
  --auto-merge flags. Use for periodic backlog grooming, pre-release cleanup, post-burst
  queue reduction, or when the user asks to "triage issues", "triage PRs", "groom the
  backlog", or "check what's open on this repo".
args: "[--type issues|prs|both] [--batch N] [--repo owner/name] [--days-stale-issue N] [--days-stale-pr N] [--auto-close] [--auto-merge] [--oldest-first]"
argument-hint: "--type both --batch 10 (defaults: days-stale-issue=90, days-stale-pr=30, current repo)"
allowed-tools: Bash(gh issue *), Bash(gh pr *), Bash(gh api *), Bash(gh repo *), Bash(git log *), Bash(rg *), Read, Grep, Glob, AskUserQuestion, TodoWrite
created: 2026-04-22
modified: 2026-04-22
reviewed: 2026-04-22
---

# /git:triage

Unified issue and PR triage: scan, categorize, cross-link, and optionally act.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|------------------------------------|
| Grooming the backlog periodically (weekly/monthly) | Addressing one specific issue → `/git:issue` |
| Cutting a release and want to merge anything green | Fixing a single failing PR → `/git:fix-pr` |
| Cleaning up after a busy week of PRs and issues | Applying review feedback on one PR → `/git:pr-feedback` |
| Auditing what's still relevant across the queue | Creating new sub-issue hierarchy → `/git:issue-hierarchy` |
| Deciding which issues are "quick wins" next | Administrative ops on one issue → `/git:issue-manage` |

## Context

- Repo remote: !`git remote get-url origin`
- Repo toplevel: !`git rev-parse --show-toplevel`
- Current branch: !`git branch --show-current`
- Recent merged PRs: !`git log --merges --format='%h %s' --max-count=15`

## Parameters

Parse these from `$ARGUMENTS` (all optional):

| Flag | Default | Description |
|------|---------|-------------|
| `--type issues\|prs\|both` | `both` | What to triage |
| `--batch N` | `10` | Items per batch |
| `--repo owner/name` | current repo (from `origin`) | Target repository |
| `--days-stale-issue N` | `90` | Age threshold for stale issues |
| `--days-stale-pr N` | `30` | Age threshold for stale PRs |
| `--auto-close` | off | Close implemented / stale issues (asks confirmation first) |
| `--auto-merge` | off | Merge ready-to-merge PRs (asks confirmation first) |
| `--oldest-first` | on | Process chronologically by `updatedAt` |

Writes are **disabled by default**. `--auto-close` and `--auto-merge` still require a per-batch `AskUserQuestion` confirmation before any `gh issue close` or `gh pr merge`.

## Execution

Execute this triage workflow:

### Step 1: Resolve target repo and fetch batches

1. If `--repo` was not provided, parse `owner/name` from the git remote URL (context).
2. Fetch issues (unless `--type prs`):
   ```bash
   gh issue list --repo $REPO --state open --limit $BATCH \
     --json number,title,body,labels,createdAt,updatedAt,comments,assignees,author
   ```
3. Fetch PRs (unless `--type issues`):
   ```bash
   gh pr list --repo $REPO --state open --limit $BATCH \
     --json number,title,createdAt,updatedAt,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft,baseRefName,headRefName,author,labels,body
   ```
4. Sort each set by `updatedAt` ascending if `--oldest-first` (default). Build a TodoWrite list with one entry per item.

### Step 2: Investigate each issue (skip if `--type prs`)

For each open issue in parallel (batch reads), gather evidence:

1. Extract referenced PR numbers from title, body, and comments (regex `#(\d+)`).
2. Check status of each referenced PR:
   ```bash
   gh pr view <n> --repo $REPO --json number,state,mergedAt,title
   ```
3. Search the codebase for concrete nouns in the issue (file paths, function names, resource names, command names) using Grep. Evidence that described artefacts exist (or no longer exist) feeds the categorization.
4. Compute age in days from `updatedAt`.

### Step 3: Categorize each issue

| Category | Criteria |
|----------|----------|
| `implemented` | A referenced PR is merged AND codebase shows the promised artefacts |
| `outdated` | Referenced files/resources no longer exist; issue predates current structure |
| `stale` | `age > --days-stale-issue` AND no recent comments AND not `implemented` |
| `still-valid` | None of the above — work remains |

Record the winning PR number (if any) with each `implemented` entry.

### Step 4: Evaluate each PR (skip if `--type issues`)

For each open PR, read the already-fetched JSON fields. If `statusCheckRollup` is empty or looks stale, optionally re-fetch:
```bash
gh pr checks <n> --repo $REPO --json name,state,conclusion,bucket
```

Decision inputs:
- `isDraft` — draft PRs never qualify as `ready-to-merge`
- `mergeable` — `MERGEABLE` / `CONFLICTING` / `UNKNOWN`
- `mergeStateStatus` — `CLEAN` / `BEHIND` / `DIRTY` / `BLOCKED` / `HAS_HOOKS` / `UNSTABLE` / `UNKNOWN`
- `reviewDecision` — `APPROVED` / `CHANGES_REQUESTED` / `REVIEW_REQUIRED` / null
- `statusCheckRollup[].conclusion` — `SUCCESS` / `FAILURE` / `CANCELLED` / null
- Age from `updatedAt`

If `mergeStateStatus` is `UNKNOWN` and `mergeable` is `UNKNOWN`, trigger a fresh view:
```bash
gh pr view <n> --repo $REPO --json mergeable,mergeStateStatus
```

### Step 5: Categorize each PR

Apply the first matching rule (top to bottom):

| Category | Criteria |
|----------|----------|
| `draft` | `isDraft` is true |
| `needs-fix` | Any check in `statusCheckRollup` has `conclusion: FAILURE` |
| `needs-rebase` | `mergeStateStatus` in `BEHIND`, `DIRTY`; OR `mergeable` is `CONFLICTING` |
| `awaiting-review` | `reviewDecision` is `REVIEW_REQUIRED` or null AND checks are SUCCESS/none |
| `changes-requested` | `reviewDecision` is `CHANGES_REQUESTED` |
| `ready-to-merge` | `mergeable: MERGEABLE` AND `mergeStateStatus: CLEAN` (or `HAS_HOOKS`/`UNSTABLE` with all checks green) AND `reviewDecision: APPROVED` AND not draft |
| `stale` | `age > --days-stale-pr` AND none of the above trigger |

### Step 6: Cross-link issues and PRs

- For each `implemented` issue, attach the merged PR number.
- For each `ready-to-merge` PR, extract closing keywords from body (`closes #N`, `fixes #N`, `resolves #N`) and attach those issue numbers.
- For each `needs-fix` / `needs-rebase` / `changes-requested` PR, note the referenced issues so the report can suggest which issues remain blocked.

### Step 7: Present the prioritized queue

Ordering: quick wins first. Use AskUserQuestion only when the user will need to pick what to act on next.

Print a status table (one row per item) grouped by category:

```
## Issues (N open, triaged)

| # | Age | Title | Category | Cross-link |
|---|-----|-------|----------|------------|
| 42 | 120d | Remove legacy X | implemented | PR #99 (merged) |
| 17 | 210d | Deprecated docs | stale | — |
| 13 | 14d  | Add retry logic | still-valid | — |

## PRs (N open, triaged)

| # | Age | Title | Category | Cross-link |
|---|-----|-------|----------|------------|
| 101 | 2d  | feat(api): X | ready-to-merge | closes #55 |
| 102 | 18d | fix(auth): Y | needs-fix | — |
| 103 | 45d | refactor(ui) | stale | — |
```

### Step 8: Optional writes (guarded)

If `--auto-close` was set and any issue is `implemented` or `stale`, ask before acting:

```
AskUserQuestion("Close N issues?", options=[
  "Yes — close all implemented + stale",
  "Implemented only",
  "Stale only",
  "No, report only"
])
```

For each selected issue:
```bash
gh issue close <n> --repo $REPO --comment "Closing as <category>.

Evidence: <short summary + cross-link PR>

Triaged by /git:triage on <date>."
```

If `--auto-merge` was set and any PR is `ready-to-merge`, ask similarly. Merge with:
```bash
gh pr merge <n> --repo $REPO --squash --auto
```
(`--squash` is the repo default for this project; for other repos, read `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` and pick the first allowed strategy.)

### Step 9: Synthesize the backlog report

After per-item actions, emit a structured summary:

1. **Actions taken** — count of issues closed, PRs merged, with numbers.
2. **Quick wins** — `still-valid` issues whose body suggests <30 min of work (single file, doc edit, config tweak).
3. **Blockers** — `changes-requested` PRs and issues blocked on external factors.
4. **Decisions needed** — `still-valid` issues whose body ends in a question or "how should we…".
5. **Handoff recommendations** per category:

| Category | Recommended next skill |
|----------|------------------------|
| `needs-fix` | `/git:fix-pr <n>` |
| `changes-requested` | `/git:pr-feedback <n>` |
| `needs-rebase` | `/git:conflicts <n>` or `gh pr merge --update-branch` |
| `still-valid` (actionable) | `/git:issue <n>` |
| `still-valid` (admin only) | `/git:issue-manage` |
| `implemented` (not auto-closed) | manual `gh issue close <n>` |

## Post-actions

- Print a one-line summary: `Triaged N issues (X closed), M PRs (Y merged). See report above.`
- If any writes were gated behind confirmation that the user declined, leave the items open and note "no writes — report only".
- Remind the user they can re-run with `--type prs` or `--type issues` to focus the sweep.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Minimal issue list | `gh issue list --repo $REPO --state open --limit $BATCH --json number,title,updatedAt,labels` |
| Full PR status | `gh pr list --repo $REPO --state open --limit $BATCH --json number,title,updatedAt,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,isDraft` |
| PR check bucket summary | `gh pr checks <n> --repo $REPO --json name,state,conclusion,bucket` |
| Single PR merge state | `gh pr view <n> --repo $REPO --json mergeable,mergeStateStatus` |
| Close with evidence | `gh issue close <n> --repo $REPO --comment "<reason + PR ref>"` |
| Squash-merge when green | `gh pr merge <n> --repo $REPO --squash --auto` |

## See Also

- `/git:fix-pr` — fix `needs-fix` PRs
- `/git:pr-feedback` — address `changes-requested` PRs
- `/git:issue` — work on a `still-valid` issue
- `/git:issue-manage` — admin ops on issues
- `/git:issue-hierarchy` — sub-issue relationships
- `/git:conflicts` — resolve `needs-rebase` PRs
