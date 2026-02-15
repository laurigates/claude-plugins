---
model: opus
created: 2026-02-02
modified: 2026-02-10
reviewed: 2026-02-10
name: git-worktree-agent-workflow
description: |
  Parallel agent workflows using git worktrees for isolated, concurrent issue work.
  Use when multiple issues get mixed into a single branch (contamination), when you
  need parallel work on independent issues, or when separating mixed commits into
  clean single-purpose PRs. Enables launching subagents with isolated working
  directories that can work simultaneously without conflicts.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, TodoWrite
---

# Git Worktree Agent Workflow

Orchestrate parallel agent workflows using git worktrees for isolated, concurrent issue resolution.

## When to Use This Skill

| Use this skill when... | Use standard workflow instead when... |
|------------------------|--------------------------------------|
| Multiple issues mixed into one branch (contamination) | Single issue, clean branch |
| Need parallel work on independent issues | Issues must be done sequentially |
| Separating mixed commits into clean PRs | Commits already properly separated |
| Complex multi-agent coordination needed | Simple single-agent task |
| Existing partial work needs redistribution | Starting fresh from scratch |

## Core Expertise

- **Issue Isolation**: Create independent working directories for each issue
- **Contamination Recovery**: Preserve mixed work as patches, reset, redistribute
- **Parallel Execution**: Launch multiple agents working simultaneously
- **Atomic PRs**: Each worktree produces exactly one focused commit/PR
- **Clean Integration**: Sequential PR creation maintains proper git history

## Context

- Current branch: !`git branch --show-current 2>/dev/null`
- Worktrees: !`git worktree list --porcelain 2>/dev/null`
- Uncommitted changes: !`git status --porcelain 2>/dev/null`
- Recent commits: !`git log --oneline --max-count=10 2>/dev/null`
- Remote tracking: !`git rev-list --left-right --count HEAD...@{u} 2>/dev/null`

## Execution

Execute this worktree-based parallel agent workflow:

### Step 1: Preserve and reset

Save all in-progress work and reset to a clean baseline.

```bash
# 1. Identify the clean base commit
git log --oneline -20  # Find last clean commit before contamination

# 2. Preserve work as patches
git format-patch <clean-base>..HEAD -o /tmp/patches/

# 3. Save stash if exists
git stash show -p > /tmp/patches/stash.patch 2>/dev/null || true

# 4. Save uncommitted changes
git diff > /tmp/patches/working-tree.patch
git diff --staged > /tmp/patches/staged.patch

# 5. Reset to clean state (requires user confirmation)
git reset --hard <clean-base>
git stash drop 2>/dev/null || true
```

**Patch contents**:
- `0001-*.patch`, `0002-*.patch`, etc. - Individual commits
- `stash.patch` - Stashed changes
- `working-tree.patch` - Uncommitted modifications
- `staged.patch` - Staged but uncommitted changes

### Step 2: Create isolated worktrees

Create independent working directories for each issue inside `./worktrees/`.

```bash
# Ensure worktrees directory exists (gitignored)
mkdir -p worktrees

# Create worktree for each issue
git worktree add ./worktrees/issue-47 -b wt/issue-47 main
git worktree add ./worktrees/issue-49 -b wt/issue-49 main
git worktree add ./worktrees/issue-50 -b wt/issue-50 main

# List all worktrees
git worktree list

# Each worktree:
# - Lives inside ./worktrees/ (within the project directory)
# - Shares the same .git database (efficient)
# - Has an independent branch
# - Can be worked on simultaneously
# - Requires no additional permissions (already in project dir)
```

**Naming convention**: `./worktrees/issue-{N}` with branch `wt/issue-{N}`

**Why `./worktrees/`**: Keeping worktrees inside the project directory means agents already have file permissions — no `additionalDirectories` configuration needed. The `/worktrees/` entry in `.gitignore` prevents git from tracking worktree contents.

### Step 3: Apply existing work

Distribute saved patches to appropriate worktrees.

**For complete patches (single-issue commits)**:
```bash
git -C ./worktrees/issue-47 am /tmp/patches/0001-feat-issue-47-implementation.patch
```

**For mixed patches (multi-issue commits)**:
```bash
# Extract specific files from a mixed commit
git show <commit> -- path/to/file1 path/to/file2 > /tmp/patches/issue-47-files.patch

# Apply to appropriate worktree
git -C ./worktrees/issue-47 apply /tmp/patches/issue-47-files.patch
```

**For partial work (needs agent completion)**:
```bash
git -C ./worktrees/issue-50 apply /tmp/patches/partial-work.patch
# Agent will complete remaining work
```

### Step 4: Launch parallel agents

Launch agents to complete work in their respective worktrees.

**Critical**: Each agent receives the absolute path to its worktree.

**Agent prompt template**:
```
You are working in the worktree at: {repo_root}/worktrees/issue-{N}

**Issue #{N}**: {issue title}

{issue description}

## Already applied changes
{list of files with partial changes}

## Your task
1. {specific tasks}
2. Stage all changes and create a commit with message:
   {commit type}: {description}

   Fixes #{N}

   Co-Authored-By: Claude <noreply@anthropic.com>

DO NOT modify any files outside the worktree at {repo_root}/worktrees/issue-{N}
```

**Parallelization**: Agents run simultaneously because:
- Each has its own isolated directory
- No file conflicts possible
- Independent git histories until merge

### Step 5: Integrate sequentially

Push branches and create PRs in order.

```bash
# From each worktree, push to origin
git -C ./worktrees/issue-47 push origin wt/issue-47:fix/issue-47

# Create PR
gh pr create --head fix/issue-47 --base main \
  --title "fix: {description}" \
  --body "Fixes #47"
```

**Why sequential**: PRs are created one at a time to:
- Allow proper PR numbering
- Enable dependent PRs if needed
- Maintain clean git history

### Step 6: Clean up worktrees

Remove worktrees and temporary branches after PRs are merged.

```bash
# Remove worktrees
git worktree remove ./worktrees/issue-47
git worktree remove ./worktrees/issue-49
git worktree remove ./worktrees/issue-50

# Prune stale worktree references
git worktree prune

# Delete local branches
git branch -D wt/issue-47 wt/issue-49 wt/issue-50

# Clean up patches and empty worktrees directory
rm -rf /tmp/patches/

# Note: rmdir only removes empty directories. If worktrees remain (intentionally
# or due to errors), the directory is preserved. This is correct behavior - manual
# cleanup is needed if worktrees are still in use.
rmdir worktrees 2>/dev/null || true
```

## Orchestrator Responsibilities

The main agent (orchestrator) handles:

1. **Analysis**: Determine which issues are independent vs. interdependent
2. **Patch extraction**: Separate mixed commits into per-issue patches
3. **Worktree creation**: Set up isolated environments
4. **Agent dispatch**: Launch subagents with precise worktree paths
5. **Verification**: Run tests in each worktree before integration
6. **Integration**: Push branches and create PRs
7. **Cleanup**: Remove worktrees and temporary artifacts

## Subagent Responsibilities

Each subagent handles:

1. **Work in assigned worktree only** (critical constraint)
2. Complete the assigned issue
3. Run relevant tests
4. Create a single, focused commit
5. Report completion status

## Decision Matrix

| Scenario | Approach |
|----------|----------|
| Single issue, no contamination | Standard branch workflow |
| Multiple independent issues | Parallel worktrees |
| Issues with dependencies | Sequential worktrees (order matters) |
| Contaminated PR | Preserve -> Reset -> Worktrees -> Reapply |
| Partial work exists | Apply patch -> Agent completes |
| Work from scratch | Create worktree -> Agent implements |

## Verification Checklist

**Before integration**:
- [ ] Each worktree has exactly 1 commit ahead of base
- [ ] Tests pass in each worktree
- [ ] Commits reference correct issue numbers
- [ ] No cross-worktree file modifications

**After integration**:
- [ ] Each PR has clean, single-purpose changes
- [ ] All worktrees removed
- [ ] Local branches cleaned up
- [ ] Main branch unchanged (PRs merge to remote)

## Key Constraints for Agents

1. **Absolute paths only**: Always pass full paths to avoid confusion
2. **No directory changes**: Work should happen via path arguments, not `cd`
3. **Single commit per worktree**: Keep changes atomic and reviewable
4. **Issue reference in commit**: Always include `Fixes #N` for auto-closing
5. **Dependency installation**: Each worktree may need `bun install` / `npm install`

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List worktrees | `git worktree list --porcelain` |
| Create worktrees dir | `mkdir -p worktrees` |
| Create worktree | `git worktree add ./worktrees/issue-N -b wt/issue-N main` |
| Remove worktree | `git worktree remove ./worktrees/issue-N` |
| Preserve commits | `git format-patch <base>..HEAD -o /tmp/patches/` |
| Apply patch (am) | `git -C ./worktrees/issue-N am /tmp/patches/*.patch` |
| Apply patch (apply) | `git -C ./worktrees/issue-N apply /tmp/patches/file.patch` |
| Extract file changes | `git show <commit> -- path/to/file > /tmp/patch.patch` |
| Check worktree status | `git -C ./worktrees/issue-N status --porcelain` |
| Run tests in worktree | `cd ./worktrees/issue-N && npm test` |
| Push worktree branch | `git push origin wt/issue-N:fix/issue-N` |

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
| Format patches | `git format-patch <base>..<head> -o <dir>` |
| Apply patch series | `git am <patches>` |
| Apply single patch | `git apply <patch>` |
| Show commit as patch | `git show <commit> --format=email` |

## Example Coordination Flow

```
Orchestrator (main repo)
    |
    +--- Step 1: Analyze & preserve contaminated work
    |
    +--- Step 2: Create worktrees (mkdir -p worktrees)
    |         +-- ./worktrees/issue-47 (complete patch)
    |         +-- ./worktrees/issue-49 (complete patch)
    |         +-- ./worktrees/issue-50 (partial, needs agent)
    |
    +--- Step 3: Apply patches
    |         +-- git am (complete patches)
    |         +-- git apply (partial patches)
    |
    +--- Step 4: Launch agents IN PARALLEL
    |         |
    |         +---> Agent 1 -> ./worktrees/issue-50
    |         |         +-- Completes work, commits
    |         |
    |         +---> Agent 2 -> ./worktrees/issue-XX
    |                   +-- Implements from scratch, commits
    |
    +--- Step 5: Sequential integration
    |         +-- Verify tests pass in each worktree
    |         +-- Push branches to origin
    |         +-- Create PRs
    |
    +--- Step 6: Cleanup
              +-- Remove worktrees
              +-- Delete local branches
              +-- rmdir worktrees (if empty)
```

## Related Skills

- [git-branch-pr-workflow](../git-branch-pr-workflow/SKILL.md) - Standard branch workflows
- [git-rebase-patterns](../git-rebase-patterns/SKILL.md) - Advanced rebase techniques
- [multi-agent-workflows](../../../agent-patterns-plugin/skills/multi-agent-workflows/SKILL.md) - General agent orchestration
