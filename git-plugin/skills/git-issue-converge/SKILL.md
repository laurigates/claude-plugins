---
name: git-issue-converge
description: "Shrink a growing issue backlog and keep it shrinking — measure inflow, close/fold, batch fixes, one rollup per PR. Use when open issues keep growing or follow-ups outpace closes."
args: "[--repo owner/name] [--days N] [--label-cap N] [--label-pattern ERE] [--phase measure|plan|consolidate|fix|decide|all]"
argument-hint: "--days 28 --label-cap 20 --label-pattern '^(build|area):' (defaults: current repo, --phase all)"
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/issue-flow.sh *), Bash(gh issue *), Bash(gh pr *), Read, Write, Grep, Glob, Skill, AskUserQuestion
created: 2026-11-26
modified: 2026-11-26
reviewed: 2026-11-26
---

# /git:issue-converge

Bring an issue backlog down and keep it down. Triage closes issues, but the
fix sessions that follow usually file more follow-ups than they close, so the
count regrows. This skill pairs one-off consolidation with rules that cap
inflow, then works the remaining code in batches.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|---|---|
| Open issues grow week over week although issues close fast | A report-only sweep with close/merge recommendations → `git-plugin:git-triage` |
| Each PR leaves several follow-up or verification issues behind | Working one or a few known issues to a PR → recommend the user run `/git:issue` |
| Plans, epics or reviews were split into one issue per idea | Grouping new issues under an epic → `git-plugin:git-issue-hierarchy` |
| | Merging an existing PR queue → `git-plugin:git-pr-sweep` |

## Parameters

Parse from `$ARGUMENTS`; all optional:

| Flag | Default | Meaning |
|---|---|---|
| `--repo owner/name` | `origin` remote | Target repository |
| `--days N` | `28` | Window for the inflow/outflow counts |
| `--label-cap N` | `20` | Open issues per label beyond which new work goes to a rollup |
| `--label-pattern ERE` | all labels | Labels the cap applies to, such as `'^(build|area):'` |
| `--phase` | `all` | Run one step only: `measure` (1), `plan` (2–3), `consolidate` (4), `fix` (5–6), `decide` (7) |

## Execution

Execute this convergence workflow. Steps 4 and 5 change the tracker and the
repository, so they run only after the go-ahead in Step 3.

### Step 1: Measure the flow

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/issue-flow.sh" --repo "$REPO" --days "$DAYS" --label-cap "$CAP" --label-pattern "$PATTERN"
```

Read `OPEN_TOTAL`, `OPENED_WINDOW`, `CLOSED_WINDOW`, `NET_WINDOW` and the
`LABEL_*` rows. Then find where the inflow comes from: group the window's
opened issues by title prefix, label, author and the PR that spawned them.
The usual sources are one verification issue per PR, a plan split into one
issue per idea, and review findings filed one issue each. Name the dominant
sources with counts; they decide which inflow rules Step 3 proposes.

### Step 2: Classify every open issue

Run `git-plugin:git-triage` over the whole backlog (`--batch` set to
`OPEN_TOTAL`), then put each issue in one bucket:

| Bucket | Action |
|---|---|
| Fixed on the default branch | Close as completed with the commit or PR |
| Plan item nobody has started | A line on the plan's checklist (epic, PRD or ADR) |
| Needs only a check on hardware or by hand | A line on a standing verification-queue issue |
| Follow-up chain of a merged PR | A line on one rollup issue for that subsystem |
| Parked area, no activity | Close as not planned; the idea stays in the project docs |
| Actionable code | A fix batch for its subsystem (Step 5) |
| Needs a person | Step 7, split into a decision, a hands-on task (a file only on someone's machine, a capture, a credential) or an outside dependency |

### Step 3: Write the plan and ask once

Write the plan where the user reads documents: the numbers, the inflow
sources, the proposed inflow rules, Batch 0 (closures), Batch 1 (the
checklist issues and what folds into each), and one code batch per
subsystem. Ask one `AskUserQuestion` with these options: rules and first batch
(recommended), rules only, closures only, revise the plan. Recommend doing
both, because folding issues without the rules lets the count grow back.

The inflow rules go in the repository's own rules (for example
`.claude/rules/issue-hygiene.md`) and name its queue issues and label
prefixes. Where the user already has portfolio or global rules for issue
inflow, the repository file holds only those repository-specific names.

### Step 4: Consolidate

1. Reuse an open epic, rollup or queue before creating one.
2. Create each checklist issue first. Each line carries the folded issue's
   title and number.
3. Close each folded issue as not planned with a comment linking its
   checklist, so its history stays findable. Close fixed-on-main issues as
   completed. Set `state_reason` every time.
4. Pin the queue issues if the API allows it; otherwise list pinning as a
   manual step in the report.

```bash
gh issue create --repo "$REPO" --title "<subsystem>: follow-ups" --body-file checklist.md
gh issue close <n> --repo "$REPO" --reason "not planned" --comment "Folded into #<checklist>."
gh issue close <n> --repo "$REPO" --reason completed --comment "Fixed on main by <sha or #PR>."
```

### Step 5: Fix in batches

- One batch per subsystem. Implement with TDD; for several batches use a
  workflow with an implementer, a separate adversarial verifier and a repair
  pass per batch, each in its own worktree. Agents commit locally, push
  nothing and file no issues: they return their follow-ups.
- Trial-merge every batch branch onto the default branch together and run the
  shared suites on the merged tree before anything is pushed.
- Ship the batches as one PR with one commit per issue, each commit typed for
  the paths it touches, unless the user asked for separate PRs. Merge by the
  repository's merge-method rule (`git-plugin:git-merge-hazards`). If the
  method turns to squash because two commits edit the same lines, fold those
  two into one commit and re-check. Read the method from the PR:
  `gh pr view <n> --repo "$REPO" --json labels,commits`.
- Issues the batches find already fixed close when the PR merges.

### Step 6: Route follow-ups once

Check each returned follow-up once against the default branch and drop the
ones already handled or wrong. Fold small ones (a file the PR touches, or
under about 30 lines) into the PR as their own commits. Verification steps
become lines on the queue issue. Everything else becomes one rollup checklist
issue for the PR, never one issue per finding.

### Step 7: Ask the remaining decisions

Collect every item that needs a person and ask them together: one question
per item, two to four options each with its consequence, one option
recommended with a one-line reason. Give a hands-on task the options do it
now, defer or drop. Keep working on recommended options that can be undone
while answers arrive, act on each answer as it comes, and record each decision
where later sessions find it (ADR, issue comment or project memory).

### Step 8: Report

State the open count before and after, issues closed by kind (completed, not
planned, folded), issues opened and why, and what waits on whom. A run that
opened more issues than it closed says why.

## Post-actions

- Print: `Open issues: B → A (closed C, folded F, opened O). Net window: N.`
- Re-run Step 1 after a few weeks; `NET_WINDOW` above zero again means the
  inflow rules are not being followed or miss a source.

## Measured example

One tracker went from 183 to 128 open issues through consolidation alone
(3 closed as fixed, 10 parked, 49 folded into 8 checklists), then to 100
through one 26-commit PR that closed 21 issues. The agents' 36 follow-ups
became one rollup issue, and nine open questions went out as nine decision
questions with recommendations.
