---
name: git-triage
description: "Backlog sweep over open issues and PRs — staleness, cross-links, close/merge recommendations, no code changes. Use when grooming the backlog, deciding what to close, or pre-release cleanup."
args: "[--type issues|prs|both] [--batch N] [--repo owner/name] [--days-stale-issue N] [--days-stale-pr N] [--auto-close] [--auto-merge] [--oldest-first]"
argument-hint: "--type both --batch 10 (defaults: days-stale-issue=90, days-stale-pr=30, current repo)"
allowed-tools: Bash(bash *), Bash(gh issue *), Bash(gh pr *), Bash(gh api *), Bash(gh repo *), Bash(git log *), Bash(rg *), Read, Grep, Glob, AskUserQuestion
created: 2026-04-22
modified: 2026-10-09
reviewed: 2026-09-23
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
| `--batch N` | `10` | Max items fetched per type — the N most recently created open items |
| `--repo owner/name` | current repo (from `origin`) | Target repository |
| `--days-stale-issue N` | `90` | Age threshold for stale issues |
| `--days-stale-pr N` | `30` | Age threshold for stale PRs |
| `--auto-close` | off | Close implemented / stale issues (asks confirmation first) |
| `--auto-merge` | off | Merge ready-to-merge PRs (asks confirmation first) |
| `--oldest-first` | on | Process the fetched batch chronologically by `updatedAt`; never changes which items were fetched |

Writes are **disabled by default**. `--auto-close` and `--auto-merge` still require a per-batch `AskUserQuestion` confirmation before any `gh issue close` or `gh pr merge`.

## Execution

Execute this triage workflow:

### Step 1: Resolve target repo and gather batches

Run the data-gathering script. It fetches issue/PR batches, computes age in days
per item, categorizes each PR via the pure first-match table (over `isDraft`,
`mergeable`, `mergeStateStatus`, `reviewDecision`, and `statusCheckRollup[].conclusion`),
flags stale-candidate issues, carries each issue's title, reports per-issue
progress, and extracts each PR's closing keywords:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/git-triage.sh" --home-dir "$HOME" --project-dir "$(pwd)" --type "$TYPE" --batch "$BATCH" --days-stale-issue "$STALE_ISSUE" --days-stale-pr "$STALE_PR"
```

Read the coverage keys first:

| Key | Meaning |
|-----|---------|
| `ISSUES_FETCHED` / `PRS_FETCHED` | Items in this batch — the count to report |
| `ISSUES_TOTAL` / `PRS_TOTAL` | Unbounded open count, or `unknown` when it could not be read |
| `ISSUES_TRUNCATED` / `PRS_TRUNCATED` | `true` when the total exceeds the batch |
| `TRUNCATED` | Roll-up over both halves: `true` beats `unknown` beats `false` |

`--batch` caps each fetch, and gh returns the N most recently **created** open
items, so the default batch is the newest slice of the backlog. It therefore
leaves out the oldest items, which are exactly the stale candidates. When
`TRUNCATED=true`, say "triaged N of M" wherever the report states a count, and
re-run with `--batch` set to the `_TOTAL` value for a full sweep. When
`TRUNCATED=unknown`, report the coverage as unverified rather than complete.
`--oldest-first` reorders only the fetched batch.

`STATUS=`, `ISSUE_COUNT=`, and the `ISSUES:` block are the collector's own
diagnostics (for example, a fetch that returned non-JSON), not GitHub issues:
`ISSUE_COUNT=0` beside ten issue blocks means the collector hit no problems.
Read `STATUS=` to decide whether the data can be trusted, and the `ISSUES:`
rows (present only when `ISSUE_COUNT` is above 0) for why.

Per item it emits
`ISSUE_<n>_TITLE` / `ISSUE_<n>_AGE_DAYS` / `ISSUE_<n>_REFS` /
`ISSUE_<n>_COMMENTS` / `ISSUE_<n>_STALE_CANDIDATE`, the Step 2 progress keys, and
`PR_<n>_CATEGORY` / `PR_<n>_AGE_DAYS` / `PR_<n>_CLOSES` (plus the underlying
enum fields). It also rolls up `SYSTEMATIC_FAILURE_*` groups (see Step 4).
If `--repo` was provided, pass it through; the script reads the
current repo from `origin` otherwise. Sort each set by age (oldest first if
`--oldest-first`) and track one entry per item — via `TodoWrite` when the
session has the task tools (see `.claude/rules/agentic-permissions.md` §
Task-tool availability), otherwise as a checklist you keep in the response.

### Step 2: Investigate each issue (skip if `--type prs`)

For each open issue in parallel (batch reads), gather evidence:

1. Read the progress keys first ([REFERENCE.md](REFERENCE.md#per-issue-progress-keys)):
   `ISSUE_<n>_CHECKBOXES` / `_SUBISSUES` (done/total), `_MERGED_PRS` (`*` =
   closes the issue), `_CLOSE_CANDIDATE` (a hint to verify). A merged PR
   **without** `*` is evidence, not a close signal: it may only reference the
   issue, so read what it changed.
2. For PRs those keys miss (`#N` in a comment, `MERGED_PRS=unknown`),
   extract `#(\d+)` from title, body, and comments, and check each:
   ```bash
   gh pr view <n> --repo $REPO --json number,state,mergedAt,title
   ```
3. Search the codebase for concrete nouns in the issue (file paths, functions, resources, commands) using Grep. Evidence that described artefacts exist (or no longer exist) feeds the categorization.

### Step 3: Categorize each issue

| Category | Criteria |
|----------|----------|
| `implemented` | A referenced PR is merged AND codebase shows the promised artefacts |
| `outdated` | Referenced files/resources no longer exist; issue predates current structure |
| `stale` | `age > --days-stale-issue` AND no recent comments AND not `implemented` |
| `tripwire-candidate` | Work remains, but only once a condition visible in the source comes true ("if the list ever grows past…", "when we upgrade to…") |
| `still-valid` | None of the above — work remains |

Record the winning PR number (if any) with each `implemented` entry.

### Step 4: Read each PR's category (skip if `--type issues`)

Read `PR_<n>_CATEGORY` from Step 1's output. For the category table, `uncategorized` PRs, and `SYSTEMATIC_FAILURE_*` groups (one shared root cause, one grouped row), see [references/pr-categories.md](references/pr-categories.md).

### Step 5: Cross-link issues and PRs

- For each `implemented` issue (from Step 3's judgment), attach the merged PR number.
- For each `ready-to-merge` PR, read the closing keywords the script extracted
  in `PR_<n>_CLOSES` and attach those issue numbers.
- For each `needs-fix` / `needs-rebase` / `changes-requested` PR, note the referenced issues so the report can suggest which issues remain blocked.

### Step 6: Present the prioritized queue

Order quick wins first; print one status table per type, grouped by category, as in [references/report-template.md](references/report-template.md). Use AskUserQuestion only when the user must pick what to act on next.

### Step 7: Optional writes (guarded)

Only with `--auto-close` / `--auto-merge`: confirm via `AskUserQuestion` before any `gh issue close` or `gh pr merge`, then act per [references/guarded-writes.md](references/guarded-writes.md).

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
| `changes-requested` | recommend the user run `/git:pr-feedback <n>` (gated by `disable-model-invocation`, so surface it rather than invoking it) |
| `needs-rebase` | `/git:conflicts <n>` or `gh pr merge --update-branch` |
| `still-valid` (actionable) | recommend the user run `/git:issue <n>` (gated by `disable-model-invocation`, so surface it rather than invoking it) |
| `still-valid` (admin only) | `/git:issue-manage` |
| `implemented` (not auto-closed) | manual `gh issue close <n>` |
| `tripwire-candidate` | `testing-plugin:test-tripwire` — a test that fails when the condition comes true, then close the issue linking it |

## Post-actions

- Print a one-line summary: `Triaged N of M open issues (X closed), P of Q open PRs (Y merged). See report above.`
- If any writes were gated behind confirmation that the user declined, leave the items open and note "no writes — report only".
- Remind the user they can re-run with `--type prs` or `--type issues` to focus the sweep.

## Agentic Optimizations

See [references/commands.md](references/commands.md) for compact list, status, merge-state, close, and merge commands, and the related skills per category.
