# git-issue - Reference

Analysis heuristics, commit-message formats, branch-from-remote rationale, and the
summary report shape for `/git:issue`. The execution flow itself lives in
[SKILL.md](SKILL.md).

## Issue Analysis Engine

Before processing multiple issues, analyze for:

### Blocker Check (run first)

Before sequencing or scoring, ask GitHub which issues are blocked by other
open work via the native dependencies API:

```bash
gh api repos/$OWNER/$REPO/issues/$N/dependencies/blocked_by \
  --jq '.[] | select(.state == "open") | .number'
```

If the list is non-empty:

1. Report the open blockers inline: `#N is blocked by #X, #Y`.
2. Use AskUserQuestion to offer: work on a blocker first, skip this issue,
   or proceed anyway (only appropriate if the blocker is stale or
   mis-linked).
3. Never silently work on a blocked issue — the "Blocked" badge exists so
   humans don't ship work out of order.

Also fetch `dependencies/blocking` to understand downstream impact —
finishing an issue that blocks others may be higher leverage than finishing
an independent issue of the same size.

### Conflict Detection

Identify issues that cannot be worked on simultaneously:

| Conflict Type | Detection Method |
|---------------|------------------|
| File overlap | Issues referencing same files/components |
| Logical conflicts | Opposing requirements (add vs remove) |
| Dependency chains | `dependencies/blocked_by` returns an open issue |
| Sub-issue ordering | Parent's `sub_issues` not yet complete |

### Confidence Scoring

Score each issue's implementability:

| Factor | Weight | Criteria |
|--------|--------|----------|
| Clear requirements | 30% | Has acceptance criteria, specific details |
| Scope definition | 25% | Bounded scope, identifiable files |
| No conflicts | 20% | No overlapping work with other issues |
| Test strategy clear | 15% | TDD approach is obvious |
| Labels/priority | 10% | Has priority labels, milestone |

**Threshold: 70%**

If confidence < 70%, prompt user:

```yaml
questions:
  - header: "Low confidence"
    question: "Issue #N has unclear requirements. How should I proceed?"
    options:
      - label: "Attempt anyway"
        description: "Make best-effort attempt based on available info"
      - label: "Ask for clarification"
        description: "Request more details on the issue"
      - label: "Skip this issue"
        description: "Move to next issue in queue"
```

### Parallel Work Detection

Identify issues that can be worked simultaneously:

**Parallelizable when:**
- Different files/components
- Neither issue appears in the other's `dependencies/blocked_by`
- Neither is a sub-issue of the other
- Independent test suites
- No logical conflicts

**Output format:**
```
Parallel Groups:
  Group 1: #123, #125 (both touch auth module - sequential)
  Group 2: #124 (standalone - can run in parallel)
  Group 3: #126, #127 (both touch UI - sequential)

Recommended: Run Groups 1, 2, 3 in parallel (3 agents)
```

## Commit Message Format

**Issue reference at BOTTOM:**

```
<type>: <description>

<optional body explaining the change>

Fixes #123
```

**Multiple issues in single commit:**

```
fix: resolve authentication and session handling

- Add token refresh logic
- Fix session timeout detection

Fixes #123
Fixes #125
```

## Branch-From-Remote Pattern

Cut every issue branch from `origin/main`, never from local `main`:

```bash
git fetch origin
git switch -c fix/issue-$N origin/main

# ... make changes, commit on the branch ...

git log --oneline origin/main..HEAD    # verify: only your commit(s)
git push -u origin fix/issue-$N

# Create PR: head=fix/issue-$N, base=main
# Next issue: git fetch origin && git switch -c fix/issue-$M origin/main
```

**Why not commit on local `main`:** unpushed commits on local `main` ride into
the next branch cut from it and land in an unrelated PR — visible only in the
file list once squashed. Basing on `origin/main` makes the local `main` state
irrelevant. This matches `git-branch-pr-workflow` § "Branch Comparison: Always
Use origin/main" (rule 3: *base PRs on `origin/main` when creating branches*)
and `~/.claude/rules/git-hazards.md` #2.

## Summary Report

After processing, report:

| Metric | Details |
|--------|---------|
| Issues processed | List of issue numbers |
| PRs created | PR numbers with links |
| Conflicts detected | Issues that were sequentialized |
| Issues skipped | Low confidence or user choice |
