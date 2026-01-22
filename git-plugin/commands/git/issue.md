---
model: haiku
created: 2025-12-16
modified: 2026-01-17
reviewed: 2026-01-17
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git switch:*), Bash(git pull:*), Bash(git stash:*), Bash(gh issue:*), Bash(gh pr:*), Bash(gh repo:*), Bash(gh label:*), Bash(pre-commit:*), Read, Edit, Write, Grep, Glob, TodoWrite, AskUserQuestion, Task, mcp__github__create_pull_request, mcp__github__issue_read, mcp__github__list_issues
description: Process GitHub issues with interactive selection, conflict detection, and parallel work support
argument-hint: [issue-numbers...] [--auto] [--filter <label>] [--limit <n>] [--parallel]
---

## Context

- Repo: !`gh repo view --json nameWithOwner 2>/dev/null || echo "{}"`
- Current branch: !`git branch --show-current`
- Working tree clean: !`git status --porcelain=v2 2>/dev/null`
- Open issues: !`gh issue list --state open --json number,title,labels --limit 10 2>/dev/null || echo "[]"`
- Open PRs: !`gh pr list --state open --json number,title 2>/dev/null || echo "[]"`
- Available labels: !`gh label list --json name --limit 50 2>/dev/null || echo "[]"`

## Parameters

Parse these parameters from the command:

| Parameter | Description |
|-----------|-------------|
| `<issue-numbers...>` | One or more issue numbers to process |
| `--auto` | Claude selects and prioritizes issues |
| `--filter <label>` | Filter issues by label |
| `--limit <n>` | Maximum number of issues to process |
| `--parallel` | Process parallel groups simultaneously using Task agents |
| `--labels <label1,label2>` | Apply labels to created PRs (defaults to issue's labels) |

## Your Task

Process GitHub issues using a TDD workflow with the **main-branch development pattern**.

---

## Mode Detection

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

Before processing multiple issues, analyze for:

### Conflict Detection

Identify issues that cannot be worked on simultaneously:

| Conflict Type | Detection Method |
|---------------|------------------|
| File overlap | Issues referencing same files/components |
| Logical conflicts | Opposing requirements (add vs remove) |
| Dependency chains | Issue B requires Issue A resolved first |

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
- No shared dependencies
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

---

## Execution Workflow

### Step 1: Prepare Working Directory

1. **Ensure clean working directory** (commit or stash if needed)
2. **Switch to main and pull latest**: `git switch main && git pull`

### Step 2: For Each Issue (or Parallel Group)

#### Standard Flow (Sequential or Single Issue)

1. **Fetch issue details**: `gh issue view $N --json title,body,state,assignees,labels`
2. **Capture issue labels** for later PR creation
3. **Identify requirements** and acceptance criteria
4. **Plan the implementation** approach

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
3. **Commit on main** with message format:

```
<type>: <description>

<optional body explaining the change>

Fixes #N
```

4. **Push to remote issue branch**: `git push origin main:fix/issue-$N`

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
Task(subagent_type="general-purpose", prompt="Process issue #N with TDD workflow...")
```

3. Wait for all agents to complete
4. Consolidate results

---

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

---

## Main-Branch Development Pattern

```bash
# All work stays on main
git switch main && git pull

# ... make changes, commit on main ...

git push origin main:fix/issue-$N    # Push to remote feature branch

# Create PR: head=fix/issue-$N, base=main
# Continue on main for next issue
```

---

## Summary Report

After processing, report:

| Metric | Details |
|--------|---------|
| Issues processed | List of issue numbers |
| PRs created | PR numbers with links |
| Conflicts detected | Issues that were sequentialized |
| Issues skipped | Low confidence or user choice |

---

## See Also

- **git-branch-pr-workflow** skill for workflow patterns
- **test-tier-selection** skill for test strategy
- **git-cli-agentic** skill for optimized git commands
- **gh-cli-agentic** skill for optimized GitHub CLI commands
