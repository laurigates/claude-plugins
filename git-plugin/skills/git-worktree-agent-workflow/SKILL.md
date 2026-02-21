---
model: sonnet
created: 2026-02-02
modified: 2026-02-16
reviewed: 2026-02-16
name: git-worktree-agent-workflow
description: |
  Worktree-first implementation workflow for isolated, focused work. Use when
  starting any implementation task — single issue, feature, or multi-issue
  parallel work. Each worktree provides a clean, isolated directory with its
  own branch, preventing cross-contamination and enabling atomic PRs.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, TodoWrite
---

# Git Worktree Agent Workflow

Start every implementation in an isolated worktree. Each task gets its own directory, its own branch, and produces one focused PR.

## When to Use This Skill

| Use this skill when... | Use standard workflow instead when... |
|------------------------|--------------------------------------|
| Starting implementation on any issue | Reading code or researching (no changes) |
| Working on a feature or fix | Quick single-line edit (typo, config value) |
| Processing multiple issues in parallel | Interactive debugging session |
| Delegating work to subagents | Already inside a worktree |

## Core Principles

- **Isolation by default**: Every implementation task starts in a worktree
- **Clean main**: The main working directory stays on `main`, always clean
- **Atomic PRs**: One worktree = one branch = one PR = one purpose
- **Parallel-ready**: Multiple worktrees can be active simultaneously
- **Shared `.git`**: Worktrees share the repository database — no cloning overhead

## Context

- Current branch: !`git branch --show-current 2>/dev/null`
- Worktrees: !`git worktree list --porcelain 2>/dev/null`
- Uncommitted changes: !`git status --porcelain 2>/dev/null`
- Default branch: !`git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null`

## Execution

### Step 1: Ensure clean main

Fetch latest and confirm the main working directory is clean.

```bash
git fetch origin --prune
git status --porcelain
```

If uncommitted changes exist, stash them before proceeding.

### Step 2: Create worktree

Create an isolated working directory for the task.

```bash
# Ensure worktrees directory exists (gitignored)
mkdir -p worktrees

# Single issue
git worktree add ./worktrees/issue-47 -b wt/issue-47 origin/main

# Feature work
git worktree add ./worktrees/feat-auth -b wt/feat-auth origin/main
```

**Naming conventions**:

| Task type | Worktree path | Branch name |
|-----------|---------------|-------------|
| Issue | `./worktrees/issue-{N}` | `wt/issue-{N}` |
| Feature | `./worktrees/feat-{name}` | `wt/feat-{name}` |
| Fix | `./worktrees/fix-{name}` | `wt/fix-{name}` |

**Why `./worktrees/`**: Inside the project directory so agents already have file permissions. The `/worktrees/` entry in `.gitignore` prevents tracking worktree contents.

### Step 3: Implement in the worktree

All work happens inside the worktree directory.

**Single agent** — work directly:
```bash
# Edit files in the worktree
# Run tests in the worktree
cd ./worktrees/issue-47 && npm test
```

**Subagent** — pass the absolute path:
```
You are working in the worktree at: {repo_root}/worktrees/issue-{N}

**Issue #{N}**: {issue title}

{issue description}

## Your task
1. {specific tasks}
2. Run tests to verify changes
3. Stage all changes and create a commit with message:
   {commit type}({scope}): {description}

   Fixes #{N}

Work ONLY within {repo_root}/worktrees/issue-{N}
```

**Multiple issues in parallel** — create one worktree per issue, launch agents simultaneously:
```bash
mkdir -p worktrees
git worktree add ./worktrees/issue-47 -b wt/issue-47 origin/main
git worktree add ./worktrees/issue-49 -b wt/issue-49 origin/main
git worktree add ./worktrees/issue-50 -b wt/issue-50 origin/main
```

Then dispatch agents in parallel — each receives its own worktree path. Agents run simultaneously because each has an isolated directory with no file conflicts.

### Step 4: Verify before integration

```bash
# Check each worktree has a clean, focused commit
git -C ./worktrees/issue-47 log --oneline origin/main..HEAD
git -C ./worktrees/issue-47 diff --stat origin/main

# Run tests in the worktree
cd ./worktrees/issue-47 && npm test
```

**Verification checklist**:
- [ ] Commit references the correct issue number
- [ ] Tests pass in the worktree
- [ ] Changes are focused on the single task
- [ ] No unrelated modifications

### Step 5: Push and create PR

Push the worktree branch and create a PR. Handle PRs sequentially to maintain clean history.

```bash
# Push
git -C ./worktrees/issue-47 push -u origin wt/issue-47

# Create PR
gh pr create --head wt/issue-47 --base main \
  --title "fix(scope): description" \
  --body "Fixes #47"
```

### Step 6: Clean up

Remove worktrees after PRs are created (or merged).

```bash
# Remove worktrees
git worktree remove ./worktrees/issue-47

# Prune stale references
git worktree prune

# Delete local branch (after PR merge)
git branch -D wt/issue-47

# Remove empty worktrees directory
rmdir worktrees 2>/dev/null || true
```

## Orchestrator vs Subagent Roles

### Orchestrator (main agent)

1. Create worktrees for each task
2. Dispatch subagents with worktree paths
3. Verify results in each worktree
4. Push branches and create PRs sequentially
5. Clean up worktrees

### Subagent

1. Work only in the assigned worktree
2. Implement the assigned task
3. Run tests
4. Create a single, focused commit
5. Report completion

## Dependency Installation

Each worktree is a separate directory tree. If the project uses `node_modules`, `vendor`, or similar:

```bash
# Install dependencies in the worktree
cd ./worktrees/issue-47 && npm install
```

Shared lockfiles ensure consistent versions across worktrees.

## Example Flow

```
Orchestrator (main repo, on main branch)
    |
    +--- Step 1: git fetch, confirm clean
    |
    +--- Step 2: Create worktrees
    |         +-- ./worktrees/issue-47
    |         +-- ./worktrees/issue-49
    |
    +--- Step 3: Launch agents IN PARALLEL
    |         |
    |         +---> Agent 1 -> ./worktrees/issue-47
    |         |         +-- Implements, tests, commits
    |         |
    |         +---> Agent 2 -> ./worktrees/issue-49
    |                   +-- Implements, tests, commits
    |
    +--- Step 4: Verify each worktree
    |
    +--- Step 5: Push + create PRs (sequential)
    |
    +--- Step 6: Cleanup
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List worktrees | `git worktree list --porcelain` |
| Create worktree | `git worktree add ./worktrees/issue-N -b wt/issue-N origin/main` |
| Remove worktree | `git worktree remove ./worktrees/issue-N` |
| Check worktree status | `git -C ./worktrees/issue-N status --porcelain` |
| Worktree log | `git -C ./worktrees/issue-N log --oneline origin/main..HEAD` |
| Worktree diff | `git -C ./worktrees/issue-N diff --stat origin/main` |
| Push worktree branch | `git -C ./worktrees/issue-N push -u origin wt/issue-N` |
| Run tests in worktree | `cd ./worktrees/issue-N && npm test` |
| Prune stale | `git worktree prune` |

## Quick Reference

| Operation | Command |
|-----------|---------|
| Add worktree | `git worktree add <path> -b <branch> <start-point>` |
| List worktrees | `git worktree list` |
| Remove worktree | `git worktree remove <path>` |
| Prune stale | `git worktree prune` |
| Lock worktree | `git worktree lock <path>` |
| Unlock worktree | `git worktree unlock <path>` |
| Move worktree | `git worktree move <path> <new-path>` |

## Related Skills

- [git-branch-pr-workflow](../git-branch-pr-workflow/SKILL.md) - Standard branch workflows
- [git-rebase-patterns](../git-rebase-patterns/SKILL.md) - Advanced rebase techniques
- [multi-agent-workflows](../../../agent-patterns-plugin/skills/multi-agent-workflows/SKILL.md) - General agent orchestration
