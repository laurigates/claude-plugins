---
model: opus
name: workflow-parallel-issues
description: |
  Process multiple GitHub issues in parallel using worktree-isolated agents.
  Use when you have a batch of independent issues to implement simultaneously,
  need to avoid sandbox permission blocks on git push by delegating push/PR
  creation to the orchestrator, or want to maximize throughput on issue backlogs.
  Builds on git-worktree-agent-workflow with push delegation and error recovery.
args: "[issue-numbers|--all-open|--label=NAME]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, TodoWrite
argument-hint: issue numbers (space-separated), --all-open, or --label=bug
created: 2026-02-08
modified: 2026-02-08
reviewed: 2026-02-08
---

# /workflow:parallel-issues

Process multiple GitHub issues in parallel with worktree isolation and centralized push/PR management.

## When to Use This Skill

| Use this skill when... | Use git-worktree-agent-workflow instead when... |
|------------------------|-------------------------------------------------|
| Batch-processing multiple open issues | Recovering from branch contamination |
| Need orchestrated push after agent work | Already have worktrees set up |
| Want automatic issue selection (labels, all open) | Manually selecting specific commits to redistribute |
| Sub-agents get blocked by sandbox on push | Have push permissions in all contexts |

## Context

- Repo: !`gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null`
- Default branch: !`gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null`
- Open issues: !`gh issue list --state open --json number,title --limit 20 2>/dev/null`
- Current branch: !`git branch --show-current 2>/dev/null`
- Existing worktrees: !`git worktree list 2>/dev/null`

## Parameters

- **Issue numbers**: Space-separated list (e.g., `12 15 23`)
- **`--all-open`**: Process all open issues
- **`--label=NAME`**: Process issues with specific label (e.g., `--label=bug`)

## Execution

### Phase 1: Issue Selection and Validation

```bash
# Fetch issues based on parameters
# --all-open:
gh issue list --state open --json number,title,body,labels --limit 50

# --label=NAME:
gh issue list --state open --label "$LABEL" --json number,title,body,labels

# Specific numbers:
for N in $ISSUE_NUMBERS; do
  gh issue view $N --json number,title,body,labels
done
```

**Validation checks**:
- Skip issues that already have an open PR
- Skip issues assigned to someone else (unless forced)
- Group issues by affected files to detect potential conflicts

### Phase 2: Dependency Analysis

Before parallelizing, check for conflicts:

| Conflict Type | Detection | Resolution |
|---------------|-----------|------------|
| Same file modified | Grep issue descriptions for file paths | Process sequentially |
| Dependent issues | Check for "depends on #N" in body | Order accordingly |
| Independent issues | No overlap in affected files | Safe to parallelize |

Create a TodoWrite plan showing which issues run in parallel vs. sequentially.

### Phase 3: Create Worktrees

```bash
# Fetch latest
git fetch origin

# Get default branch name
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

# Create worktree per issue
for N in $ISSUE_NUMBERS; do
  git worktree add /tmp/worktree-issue-$N -b wt/issue-$N origin/$DEFAULT_BRANCH
done
```

### Phase 4: Spawn Parallel Agents

Launch one Task sub-agent per issue with these instructions:

**Agent prompt template**:
```
You are working in an isolated worktree at: /tmp/worktree-issue-{N}

Issue #{N}: {title}

{issue body}

Your tasks:
1. Read the issue requirements thoroughly
2. Implement the fix/feature in the worktree
3. Run tests if a test runner is available
4. Stage all changes: git -C /tmp/worktree-issue-{N} add -A
5. Create a single commit:
   git -C /tmp/worktree-issue-{N} commit -m "{type}: {description}

   Fixes #{N}

   Co-Authored-By: Claude <noreply@anthropic.com>"

IMPORTANT:
- Work ONLY in /tmp/worktree-issue-{N}
- Use absolute paths for all git commands
- Do NOT push - the orchestrator handles pushing
- Do NOT create PRs - the orchestrator handles PR creation
- If you encounter errors, commit what works and report the issue
```

**Parallelization rules**:
- Independent issues: Launch all agents simultaneously via parallel Task calls
- Dependent issues: Launch sequentially, passing results between agents
- Max parallel agents: 10 (practical limit for worktree management)

### Phase 5: Verify Agent Results

After all agents complete:

```bash
for N in $ISSUE_NUMBERS; do
  echo "=== Issue #$N ==="
  git -C /tmp/worktree-issue-$N log --oneline -1
  git -C /tmp/worktree-issue-$N diff --stat origin/$DEFAULT_BRANCH
  # Run tests if available
  cd /tmp/worktree-issue-$N && npm test 2>/dev/null || true
done
```

### Phase 6: Sequential Push and PR Creation

Push branches and create PRs one at a time to avoid TLS errors and branch conflicts.

```bash
for N in $ISSUE_NUMBERS; do
  # Push
  git -C /tmp/worktree-issue-$N push -u origin wt/issue-$N

  # Create PR with body-file to avoid heredoc escaping issues
  TITLE=$(git -C /tmp/worktree-issue-$N log --format='%s' -1)
  BODY=$(printf "## Summary\n\nFixes #%d\n\n## Changes\n\n%s" "$N" \
    "$(git -C /tmp/worktree-issue-$N diff --stat origin/$DEFAULT_BRANCH)")

  echo "$BODY" > /tmp/pr-body-$N.md
  gh pr create \
    --head wt/issue-$N \
    --base $DEFAULT_BRANCH \
    --title "$TITLE" \
    --body-file /tmp/pr-body-$N.md

  # Brief pause between PRs
  sleep 1
done
```

### Phase 7: Cleanup

```bash
for N in $ISSUE_NUMBERS; do
  git worktree remove /tmp/worktree-issue-$N 2>/dev/null || true
  rm -f /tmp/pr-body-$N.md
done
git worktree prune
```

### Error Recovery

| Error | Recovery |
|-------|----------|
| Agent fails on an issue | Skip that issue, continue with others, report at end |
| Push fails (TLS/network) | Retry with exponential backoff: 2s, 4s, 8s, 16s |
| Push fails (permission) | Report to user, provide manual push command |
| PR creation fails | Provide `gh pr create` command for manual execution |
| Worktree conflict | Remove and recreate from clean base |

## Output Format

After completion, provide a summary table:

| Issue | Branch | Status | PR | Files Changed |
|-------|--------|--------|----|---------------|
| #12 | wt/issue-12 | merged | #45 | 3 |
| #15 | wt/issue-15 | created | #46 | 5 |
| #23 | wt/issue-23 | failed | - | - |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List open issues | `gh issue list --state open --json number,title --limit 50` |
| Issues by label | `gh issue list --label bug --json number,title` |
| Check existing PRs | `gh pr list --search "fixes #N" --json number,state` |
| Create worktree | `git worktree add /tmp/worktree-issue-N -b wt/issue-N origin/main` |
| Check worktree result | `git -C /tmp/worktree-issue-N log --oneline -1` |
| Push worktree branch | `git -C /tmp/worktree-issue-N push -u origin wt/issue-N` |
| PR with body-file | `gh pr create --head wt/issue-N --body-file /tmp/pr-body.md` |
| Remove worktree | `git worktree remove /tmp/worktree-issue-N` |

## Related Skills

- [git-worktree-agent-workflow](../../../git-plugin/skills/git-worktree-agent-workflow/SKILL.md) - Lower-level worktree patterns
- [git-issue](../../../git-plugin/skills/git-issue/SKILL.md) - Single issue processing
- [git-commit-push-pr](../../../git-plugin/skills/git-commit-push-pr/SKILL.md) - Single commit-to-PR workflow
