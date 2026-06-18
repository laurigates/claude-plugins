---
name: git-triage
description: "Triage GitHub issues and PRs — cross-link, flag stale items, recommend actions. Use when grooming the backlog, pre-release cleanup, or asked to triage issues/PRs."
args: "[--type issues|prs|both] [--batch N] [--repo owner/name] [--days-stale-issue N] [--days-stale-pr N] [--auto-close] [--auto-merge] [--oldest-first]"
argument-hint: "--type both --batch 10 (defaults: days-stale-issue=90, days-stale-pr=30, current repo)"
allowed-tools: Bash(bash *), Bash(gh issue *), Bash(gh pr *), Bash(gh api *), Bash(gh repo *), Bash(git log *), Bash(rg *), Read, Grep, Glob, AskUserQuestion, TodoWrite
created: 2026-04-22
modified: 2026-06-18
reviewed: 2026-06-14
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

- Repo remote: !`git remote -v`
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

### Step 1: Resolve target repo and gather batches

Run the data-gathering script. It fetches issue/PR batches, computes age in days
per item, categorizes each PR via the pure first-match table (over `isDraft`,
`mergeable`, `mergeStateStatus`, `reviewDecision`, and `statusCheckRollup[].conclusion`),
flags stale-candidate issues, and extracts each PR's closing keywords:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/git-triage.sh" --home-dir "$HOME" --project-dir "$(pwd)" --type "$TYPE" --batch "$BATCH" --days-stale-issue "$STALE_ISSUE" --days-stale-pr "$STALE_PR"
```

Parse `STATUS=` and `ISSUES:` from the output. Per item it emits
`ISSUE_<n>_AGE_DAYS` / `ISSUE_<n>_REFS` / `ISSUE_<n>_STALE_CANDIDATE` and
`PR_<n>_CATEGORY` / `PR_<n>_AGE_DAYS` / `PR_<n>_CLOSES` (plus the underlying
enum fields). It also rolls up `SYSTEMATIC_FAILURE_*` groups (see Step 4).
If `--repo` was provided, pass it through; the script reads the
current repo from `origin` otherwise. Sort each set by age (oldest first if
`--oldest-first`) and build a TodoWrite list with one entry per item.

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

### Step 4: Read each PR's category (skip if `--type issues`)

The script already categorized every PR in Step 1 — read `PR_<n>_CATEGORY`
straight from its output. The category is a **pure first-match** over the enum
fields (the script owns this deterministic table, top to bottom):

| Category | Criteria |
|----------|----------|
| `draft` | `isDraft` is true |
| `needs-fix` | Any check in `statusCheckRollup` has `conclusion: FAILURE` |
| `needs-rebase` | `mergeStateStatus` in `BEHIND`, `DIRTY`; OR `mergeable` is `CONFLICTING` |
| `changes-requested` | `reviewDecision` is `CHANGES_REQUESTED` |
| `ready-to-merge` | `mergeable: MERGEABLE` AND `mergeStateStatus` in `CLEAN`/`HAS_HOOKS`/`UNSTABLE` AND `reviewDecision: APPROVED` AND not draft |
| `awaiting-review` | `reviewDecision` is `REVIEW_REQUIRED` or null AND no failing check |
| `stale` | `age > --days-stale-pr` AND none of the above trigger |

If a PR comes back as `uncategorized` (e.g. `mergeStateStatus`/`mergeable`
both `UNKNOWN`), trigger a fresh view and re-run the script, or inspect:
```bash
gh pr view <n> --repo $REPO --json mergeable,mergeStateStatus
```

**Systematic failures.** When ≥2 bot-authored `needs-fix` PRs share an
identical failing-check signature, the script groups them under
`SYSTEMATIC_FAILURE_<k>_SIGNATURE` (the sorted `|`-joined failed check names)
and `SYSTEMATIC_FAILURE_<k>_PRS` (the PR list); `SYSTEMATIC_FAILURE_COUNT`
holds the number of groups. These almost always have **one** shared root
cause — e.g. Dependabot can't update `bun.lock`, so every npm-bump PR fails
the `bun install --frozen-lockfile` step *before* lint/typecheck/tests run, and
"Lint FAILURE / Type Check FAILURE" is misleading (nothing was linted). For
each group, read the install step's log once before assuming code defects:
```bash
gh pr checks <n> --repo $REPO --json name,state,conclusion,detailsUrl
gh run view <run-id> --repo $REPO --log-failed
```
Diagnose the shared cause once and present a single grouped row (Step 6) /
blocker (Step 8) instead of N independent `needs-fix` PRs.

### Step 5: Cross-link issues and PRs

- For each `implemented` issue (from Step 3's judgment), attach the merged PR number.
- For each `ready-to-merge` PR, read the closing keywords the script extracted
  in `PR_<n>_CLOSES` and attach those issue numbers.
- For each `needs-fix` / `needs-rebase` / `changes-requested` PR, note the referenced issues so the report can suggest which issues remain blocked.

### Step 6: Present the prioritized queue

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

### Step 7: Optional writes (guarded)

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

### Step 8: Synthesize the backlog report

After per-item actions, emit a structured summary:

1. **Actions taken** — count of issues closed, PRs merged, with numbers.
2. **Quick wins** — `still-valid` issues whose body suggests <30 min of work (single file, doc edit, config tweak).
3. **Blockers** — `changes-requested` PRs and issues blocked on external factors. For each `SYSTEMATIC_FAILURE_*` group, emit one "systematic failure — likely shared root cause" line naming the PRs and the shared check signature, rather than N independent `needs-fix` entries.
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
