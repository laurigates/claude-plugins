---
created: 2025-12-16
modified: 2026-09-26
reviewed: 2026-09-02
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git switch *), Bash(git fetch *), Bash(git pull *), Bash(git stash *), Bash(gh issue *), Bash(gh pr *), Bash(gh repo *), Bash(gh label *), Bash(gh api *), Bash(pre-commit *), Read, Edit, Write, Grep, Glob, TodoWrite, AskUserQuestion, Task, mcp__github__create_pull_request, mcp__github__issue_read, mcp__github__list_issues
description: "GitHub issue to PR end-to-end — branch, TDD implementation, PR — one issue or several in parallel. Use when asked to work on an issue, fix issue #N, or batch-process several."
args: "[issues... (number | #N | URL)] [--auto] [--filter <label>] [--limit <n>] [--parallel] [--labels <l1,l2>]"
argument-hint: "[issues... (number | #N | URL)] [--auto] [--filter <label>] [--limit <n>] [--parallel] [--labels <l1,l2>]"
disable-model-invocation: true
name: git-issue
---

## When to Use This Skill

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Implementing a fix for one or more open issues with TDD and PR creation | Performing administrative ops (transfer, pin, lock, bulk edit) on issues (`/git:issue-manage`) |
| Picking issues from the backlog to work on, optionally in parallel | Periodically grooming open issues and PRs to close stale or completed ones (`/git:triage`) |
| Going from an issue number to a merged-ready PR end-to-end | Hierarchical sub-issue planning and tracking (`/git:issue-hierarchy`) |

## Context

- Git remotes: !`git remote -v`
- Current branch: !`git branch --show-current`
- Working tree clean: !`git status --porcelain=v2`

Open issues, open PRs, and available labels are fetched during execution (requires a configured git remote).

## Parameters

Parse these parameters from the command:

| Parameter | Description |
|-----------|-------------|
| `<issues...>` | One or more issues as bare numbers, `#N`, or full GitHub issue URLs (`https://github.com/<owner>/<repo>/issues/<N>`), in any space- or comma-separated mix (see Step 0) |
| `--auto` | Claude selects and prioritizes issues |
| `--filter <label>` | Filter issues by label |
| `--limit <n>` | Maximum number of issues to process |
| `--parallel` | Process parallel groups simultaneously using Task agents |
| `--labels <label1,label2>` | Apply labels to created PRs (defaults to issue's labels) |

## Your Task

Process GitHub issues using a TDD workflow, cutting each issue's branch **from `origin/main`**.

---

## Mode Detection

### Step 0: Normalize issue references

Before counting tokens or detecting mode, normalize every non-flag token in
`$ARGUMENTS` into a `(number, repo)` pair. Accept these forms, in any space- or
comma-separated mix:

| Input form | Extract |
|------------|---------|
| `123` | number `123`, repo = current remote |
| `#123` | number `123`, repo = current remote |
| `https://github.com/<owner>/<repo>/issues/123` | number `123`, repo = `<owner>/<repo>` |
| `.../issues/123#issuecomment-...` | number `123` (drop the `#...` fragment), repo = `<owner>/<repo>` |

Rules:

1. Split on whitespace **and** commas; strip a leading `#`; strip a URL
   `#...` fragment after the number.
2. A token is an issue ref only if, after stripping, it is all digits **or**
   matches the `/issues/<digits>` URL shape (require trailing digits — a
   `/pull/<N>`, `/discussions/<N>`, or bare `/issues` list URL is **not** a
   ref). Leave `--flag` tokens and their values (e.g. `--filter bug,enhancement`)
   untouched — never split a flag's comma-separated value into refs.
3. For a URL whose `<owner>/<repo>` differs from the current remote (Context
   `git remote -v`), record it as **cross-repo** and carry `-R <owner>/<repo>`
   on every `gh` call for that issue (`gh issue view <N> -R …`,
   `gh api repos/<owner>/<repo>/…`, `gh pr edit … -R …`). PR creation for a
   cross-repo issue needs a branch in that repo — if the current checkout is not
   that repo, surface it with `AskUserQuestion` rather than pushing to the wrong
   remote.
4. After normalization, dedupe and count refs: 0 → No-Arguments interactive;
   1 → Single; ≥2 → Multiple.

### No Arguments → Interactive Mode

Use AskUserQuestion to prompt:

```yaml
questions:
  - header: "Issues"
    question: "How would you like to select issues to work on?"
    options:
      - label: "Let me choose specific issues"
        description: "Show issue list for manual selection"
      - label: "Claude decides priority"
        description: "Analyze issues and recommend which to tackle"
      - label: "Filter by label"
        description: "Select issues with a specific label"
```

**For "Let me choose specific issues":**
1. Fetch: `gh issue list --state open --json number,title,labels,assignees`
2. Present checkboxes with `multiSelect: true`

**For "Claude decides priority":**
- Analyze all open issues
- Score by clarity, scope, dependencies
- Present top recommendations

**For "Filter by label":**
- Present label selection from available labels
- Then show matching issues for selection

### Single Issue (`/git:issue 123`)

Process directly with standard TDD workflow.

### Multiple Issues (`/git:issue 123 456 789`)

1. Analyze all issues for conflicts and parallelization
2. Group by dependencies
3. Process sequentially or spawn parallel agents

### Auto Mode (`/git:issue --auto`)

1. Fetch all open issues
2. Score and prioritize
3. Present recommendations for approval
4. Process approved issues

---

## Issue Analysis Engine

Before processing multiple issues, run the blocker check, conflict detection,
confidence scoring, and parallel-work detection described in
[REFERENCE.md](REFERENCE.md). Never silently work on a blocked issue, and
surface a sub-70% confidence score to the user rather than guessing.

---

## Execution Workflow

### Step 1: Prepare Working Directory

1. **Ensure clean working directory** (commit or stash if needed)
2. **Fetch the remote**: `git fetch origin` — never rely on local `main` being current

### Step 2: For Each Issue (or Parallel Group)

#### Standard Flow (Sequential or Single Issue)

1. **Fetch issue details AND the comment thread**:
   `gh issue view $N --json title,body,state,assignees,labels,comments`
   The `comments` field is not optional — the body is the opening position, not the
   decision. Scope from `git-plugin:git-issue-scoping`, which carries the full protocol
   (re-verify cited evidence at HEAD; a later comment may have narrowed, reversed, or
   already resolved the ask).
2. **Capture issue labels** for later PR creation
3. **Identify requirements** and acceptance criteria
4. **Plan the implementation** approach
5. **Cut the branch from `origin/main`**: `git switch -c fix/issue-$N origin/main`

Base the branch on `origin/main`, never on local `main` — local `main` may carry
unpushed commits that would ride into this issue's PR (see
`git-branch-pr-workflow` § "Branch Comparison: Always Use origin/main").

#### TDD Workflow

1. **RED phase**: Write failing tests first
   - Create test file if needed
   - Write tests that define expected behavior
   - Run tests to verify they fail

2. **GREEN phase**: Implement fix
   - Write minimal code to make tests pass
   - Run tests to verify they pass

3. **REFACTOR phase**: Improve code quality
   - Clean up implementation
   - Ensure tests still pass

#### Commit and Push

1. **Stage changes**: `git add -u` and `git add <new-files>`
2. **Run pre-commit** if configured
3. **Commit on the issue branch** with message format:

```
<type>: <description>

<optional body explaining the change>

Fixes #N
```

4. **Verify the branch carries only this issue's commits**: `git log --oneline origin/main..HEAD`
5. **Push the issue branch**: `git push -u origin fix/issue-$N`

#### Create PR

Use `mcp__github__create_pull_request` with:
- `head`: `fix/issue-$N`
- `base`: `main`
- `title`: From issue title with `fix:` prefix
- `body`: Include `Fixes #$N` to auto-link

After PR creation, apply labels:
```bash
gh pr edit <pr-number> --add-label "<labels>"
```

### Step 3: Parallel Execution (--parallel flag)

When `--parallel` is specified:

1. Group issues by dependencies (from analysis)
2. For each parallel group, spawn a Task agent:

```
Agent tool with subagent_type: "general-purpose", prompt: "Process issue #N with TDD workflow.
Cut the branch with `git fetch origin && git switch -c fix/issue-N origin/main` — never from local main..."
```

Give the subagent the issue's title and body verbatim (quoted, not summarised)
and the labels to apply, and instruct it to read the full comment thread itself
— `gh issue view N --json title,body,comments` — before planning, scoping from
the latest deciding comment rather than from your description of it. Do not
restate the scope in your own words: the subagent implements what the thread
decided, not what you paraphrased.

3. Wait for all agents to complete
4. Consolidate results

---

## Workflow harness (template)

`workflows/issue-group-wave.workflow.js` ships beside this skill and covers the
`--parallel` path only.
**It is a TEMPLATE to adapt, not a script to run verbatim.**
Read it, then rewrite it for the work in front of you.

**Adapt freely:** the grouping and implementation agent prompts, the default
wave width, the conflict heuristics, the deferral vocabulary, and the
project-specific test and commit commands.

**Preserve across any adaptation:** (a) the loop bound is `args.issues` — the
refs Step 0 normalised — and the grouping agent **partitions** that set, never
extends it: the template validates the returned partition against the input,
discards invented issues, keeps the first placement of a duplicate, and
re-dispatches an omitted issue standalone rather than dropping it; (b) the
`GROUP_SCHEMA` shape, where every input issue lands in exactly one group **or**
in `deferred` with a closed `blocked|low-confidence|cross-repo|not-open` reason,
plus `IMPL_SCHEMA`'s `implemented|no-change|failed` outcome — so "skipped it" is
not expressible, and an issue already fixed at HEAD stays distinguishable from a
failed one; (c) the Group stage is a real barrier — conflict detection is
pairwise over the whole set (file overlap, opposing requirements, `blocked_by`
chains, sub-issue ordering), so no group can be dispatched until every issue has
been read, and you cannot partition work by a partition the work itself
discovers, which is why the grouping lane is always ONE agent.

**Agent budget:** 1 + groups — one grouping agent plus one implementation agent per
issue group. The wave width bounds concurrency, not the total. The scale guard asks before every run, because the list comes from the
caller at runtime.

**Skip the harness when:** a single issue was supplied — the modal case — or the
partition collapses to one group because every issue conflicts with every other;
that is a linear pass and the harness is pure overhead (the template aborts
below two issues, and returns the partition rather than dispatching when only
one group survives). The steps above remain the authoritative description of
*what* each stage must produce; the harness only fixes *how* the work is split.

One thing the harness changes rather than splits: `AskUserQuestion` cannot run
inside a workflow, so the blocked-issue and sub-70%-confidence prompts above
become **deferrals** the caller adjudicates — the issue is neither silently
attempted nor silently dropped.

Two clauses this template carries. Both are unconditional here — every
fanned-out group runs in its own worktree, and this skill's deliverable is a PR:

> Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents — a
> resume re-runs agents that already succeeded and opens duplicate PRs (#1868).
> Re-dispatch the failed units fresh and sequentially after checking
> `gh pr list --head <branch> --state all --json number,state`.

> Push and PR creation happen **only** in the single sequential finalise stage,
> never inside a fanned-out agent. Under the harness the Execution Workflow's
> "Commit and Push" and "Create PR" steps move there: each agent commits on
> `fix/issue-<n>` inside its own worktree, and the returned `finalisePlan` is
> what the orchestrator pushes and opens PRs from, one at a time.

## Summary Report

After processing, report the issues processed, PRs created, conflicts detected,
and issues skipped — see [REFERENCE.md](REFERENCE.md) for the table shape.

---

## Resuming work on an existing PR branch

When a follow-up request continues an issue whose branch already has a PR, invoke
`/git:pr-sync-check` before adding commits. A `pr_merged` verdict means the PR
already landed — start a fresh branch off the updated default rather than building
on the merged branch; a `behind` verdict means a teammate / agent / CI auto-fix
pushed under you, so reconcile first. See `.claude/rules/pr-branch-sync.md`.

## See Also

- **git-pr-sync-check** skill to confirm a PR branch is live and in sync before building on it
- **git-branch-pr-workflow** skill for workflow patterns
- **test-tier-selection** skill for test strategy
- **git-cli-agentic** skill for optimized git commands
- **gh-cli-agentic** skill for optimized GitHub CLI commands

For the issue-analysis heuristics (blocker check, conflict detection, confidence
scoring, parallel-work detection), commit-message formats, the branch-from-remote
pattern, and the summary-report table, see [REFERENCE.md](REFERENCE.md).
