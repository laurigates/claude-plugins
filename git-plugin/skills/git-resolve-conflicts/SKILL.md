---
model: haiku
name: git-resolve-conflicts
description: |
  Resolve merge conflicts in pull requests. Use when a PR has merge conflicts
  with its base branch, when rebasing produces conflicts, or when automated
  merges fail due to conflicting changes.
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git merge *), Bash(git checkout *), Bash(git rebase *), Bash(gh pr *), Read, Edit, Grep, Glob, TodoWrite
args: "[pr-number] [--push]"
argument-hint: PR number to resolve conflicts for
created: 2026-02-26
modified: 2026-02-26
reviewed: 2026-02-26
---

# /git:resolve-conflicts

Resolve merge conflicts in pull requests automatically.

## When to Use This Skill

| Use this skill when... | Use git-ops agent instead when... |
|------------------------|-----------------------------------|
| PR has merge conflicts with base branch | Complex multi-branch rebase workflows |
| Automated merge failed due to conflicts | Cherry-pick conflicts across many commits |
| Config files (JSON, YAML) diverged | Conflicts require deep business logic understanding |
| Base branch updates caused conflicts | Interactive rebase with squash/fixup needed |

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`
- Conflicted files: !`git diff --name-only --diff-filter=U`
- Recent commits on current branch: !`git log --format='%h %s' --max-count=5`

## Parameters

Parse these from `$ARGUMENTS`:
- `$1`: PR number (if not provided, detect from current branch)
- `--push`: Push resolved conflicts after committing

## Execution

Execute this conflict resolution workflow:

### Step 1: Identify the PR and conflicts

1. If PR number provided, fetch PR details: `gh pr view <number> --json headRefName,baseRefName,mergeable`
2. If no PR number, detect from current branch: `gh pr list --head $(git branch --show-current) --json number,baseRefName,mergeable`
3. Check if conflicts exist (mergeable == "CONFLICTING")

### Step 2: Set up the merge

1. Fetch latest base branch: `git fetch origin <base-branch>`
2. If not already in a conflicted merge state, start the merge: `git merge origin/<base-branch> --no-ff`
3. If merge succeeds cleanly, report "No conflicts to resolve" and exit

### Step 3: Resolve each conflicted file

For each file listed by `git diff --name-only --diff-filter=U`:

1. Read the file to see conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`)
2. Understand both sides:
   - **HEAD**: Changes from the PR branch (the feature work)
   - **Incoming**: Changes from the base branch (landed since PR opened)
3. Apply resolution strategy based on file type:

| File Type | Strategy |
|-----------|----------|
| JSON config (package.json, plugin.json, marketplace.json) | Merge objects/arrays, take higher versions |
| YAML config | Merge keys from both sides |
| Markdown (CHANGELOG, README) | Include content from both sides |
| Source code | Integrate both changes preserving logic |
| Lock files | Regenerate after resolving other conflicts |

4. Edit the file to remove ALL conflict markers and combine changes
5. Stage: `git add <file>`

### Step 4: Verify and commit

1. Check no conflict markers remain: search resolved files for `<<<<<<<`
2. Check git status is clean (no remaining unmerged paths)
3. Commit: `git commit --no-edit`
4. If `--push` flag provided: `git push origin <branch>`

### Step 5: Report results

Comment on the PR with resolution summary:
```
gh pr comment <number> --body "Merge conflicts with <base-branch> resolved automatically.

Resolved files:
- file1.json (merged entries from both sides)
- file2.md (combined changelog entries)
"
```

## Conflict Resolution Patterns

### JSON Files (marketplace.json, plugin.json, release-please configs)

- Merge array entries from both sides, deduplicate
- For version fields, take the higher version
- For object properties, include properties from both sides

### Markdown Files (CHANGELOG, README)

- Include content from both sides
- For changelogs, maintain chronological order
- For tables, include rows from both sides

### Source Code

- Read surrounding context to understand intent of both changes
- Integrate both modifications, preserving the logic of each
- If changes are to the same line with incompatible intent, prefer the PR branch change and note in the commit

### When to Abort

Abort with `git merge --abort` if:
- Conflicts require understanding business requirements to resolve
- Both sides made fundamentally incompatible architectural changes
- Lock files are the only conflicts (suggest `--push` after regenerating)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List conflicts | `git diff --name-only --diff-filter=U` |
| Conflict details | `git diff --diff-filter=U` |
| PR mergeable state | `gh pr view N --json mergeable` |
| Check markers remain | `grep -rn '<<<<<<<' <files>` |
| Porcelain status | `git status --porcelain=v2` |
