---
name: git-conflicts
description: "Resolve merge conflicts file-by-file. Use when a merge/rebase has conflicts, a PR can't merge, \"fix conflicts\" is requested, or branches have diverged."
allowed-tools: Bash(git status *), Bash(git diff *), Bash(git log *), Bash(git show *), Bash(git add *), Bash(git commit *), Bash(git push *), Bash(git merge *), Bash(git checkout *), Bash(git rebase *), Bash(git restore *), Bash(git config *), Bash(git rerere *), Bash(gh pr *), Read, Edit, Grep, Glob, TodoWrite
args: "[file-or-pr] [--ours] [--theirs] [--push]"
argument-hint: file path, PR number, --ours, --theirs, or --push
disable-model-invocation: true
created: 2026-03-01
modified: 2026-06-18
reviewed: 2026-05-23
---

# /git:conflicts

Resolve merge conflicts using modern git features.

## When to Use This Skill

| Use this skill when... | Use git-ops agent instead when... |
|------------------------|-----------------------------------|
| Merge or rebase produced conflicts | Complex multi-branch cherry-pick across many commits |
| PR shows "can't merge" / "fix conflicts" | Conflicts require deep business logic understanding |
| Config files (JSON, YAML, lockfiles) diverged | Interactive rebase with squash/fixup needed |
| Need to accept one side wholesale (`--ours`/`--theirs`) | Architectural redesign spanning many files |

## Context

- Current branch: !`git branch --show-current`
- Git status: !`git status --porcelain=v2 --branch`
- Merge state: !`find .git -maxdepth 1 -name 'MERGE_HEAD' -o -name 'REBASE_HEAD' -o -name 'rebase-merge' -o -name 'rebase-apply'`
- Conflicted files: !`git diff --name-only --diff-filter=U`
- Conflict style: !`git config --default '' merge.conflictStyle`
- Rerere enabled: !`git config --default '' rerere.enabled`
- Git version: !`git version`

## Parameters

Parse these from `$ARGUMENTS`:

- `$1`: File path (resolve single file) OR PR number (fetch and merge base branch)
- `--ours`: Accept current branch version for all conflicts
- `--theirs`: Accept incoming branch version for all conflicts
- `--push`: Push after resolution is committed

## Execution

Execute this conflict resolution workflow:

### Step 1: Assess the situation

1. Check context for existing merge/rebase state (`MERGE_HEAD`, `REBASE_HEAD`, `rebase-merge`, `rebase-apply`)
2. If PR number provided and no active merge state:
   - Get PR details: `gh pr view <number> --json headRefName,baseRefName,mergeable`
   - Fetch base: `git fetch origin <base-branch>`
   - Start merge: `git merge origin/<base-branch> --no-ff`
   - If merge succeeds cleanly, report "No conflicts" and exit
3. If no PR number and no active merge state, detect from current branch:
   - `gh pr list --head $(git branch --show-current) --json number,baseRefName,mergeable`
   - Use the detected PR number and base branch; proceed as above
3. List conflicted files: `git diff --name-only --diff-filter=U`
4. If no conflicted files found, report current status and exit

### Step 2: Configure zdiff3 (if not set)

Check the conflict style from context. If `merge.conflictStyle` is not `zdiff3`:

1. Set for this repo: `git config merge.conflictStyle zdiff3`
2. Re-checkout conflicted files with zdiff3 markers: `git checkout --conflict=zdiff3 -- <file>` for each conflicted file
3. Enable rerere if not already: `git config rerere.enabled true`
4. Enable rerere autoupdate: `git config rerere.autoupdate true` (auto-stages files resolved by rerere)

This gives three-way conflict markers with the common ancestor, compacted by removing shared lines at conflict boundaries. Much easier to resolve than the default two-way markers.

### Step 3: Resolve conflicts

**If `--ours` flag**: Accept current branch for all conflicted files:
```
git restore --ours -- <file>    # for each file
git add <file>
```

**If `--theirs` flag**: Accept incoming branch for all conflicted files:
```
git restore --theirs -- <file>  # for each file
git add <file>
```

**Otherwise, resolve each file intelligently:**

For each file from `git diff --name-only --diff-filter=U`:

1. Read the file — with zdiff3, conflict markers look like:
   ```
   <<<<<<< HEAD
   (current branch changes)
   ||||||| (common ancestor)
   (what the code looked like before both changes)
   =======
   (incoming changes)
   >>>>>>> branch-name
   ```
2. The `|||||||` section (common ancestor) shows what both sides started from — use it to understand intent
3. Apply resolution strategy by file type:

| File Type | Strategy |
|-----------|----------|
| `package.json`, `plugin.json` | Merge objects/arrays, take higher versions |
| YAML config | Merge keys from both sides |
| `CHANGELOG.md` | Include entries from both sides in chronological order |
| `README.md`, docs | Include content from both sides |
| Source code | Integrate both changes preserving logic of each |
| Lock files (`bun.lock`, `package-lock.json`) | Delete and regenerate after resolving other files |
| `.release-please-manifest.json` | Take higher version numbers |

4. Edit the file to remove ALL conflict markers (`<<<<<<<`, `|||||||`, `=======`, `>>>>>>>`) and combine changes
5. Stage: `git add <file>`

**Important ours/theirs note for rebases:** During `git rebase`, the meaning of ours/theirs is swapped — `--ours` refers to the branch being rebased onto (usually main), `--theirs` refers to your feature branch commits.

### Step 4: Verify and complete

1. Check no conflict markers remain: search all resolved files for `<<<<<<<`
2. Check `git diff --name-only --diff-filter=U` returns empty (no remaining unmerged paths)
3. Check if rerere recorded anything: `git rerere status`
4. Complete the operation:
   - If merging: `git commit --no-edit`
   - If rebasing: `git rebase --continue`
5. If `--push` flag: `git push origin $(git branch --show-current)`

### Step 5: Report results

Summarize what was resolved:
- List each file and how it was resolved (merged both sides, accepted ours/theirs, regenerated)
- Note if rerere recorded new resolutions for future reuse
- If PR number was provided (or detected from branch), comment on the PR:
  ```
  gh pr comment <number> --body "Merge conflicts with <base-branch> resolved automatically.

  Resolved files:
  - file1.json (merged entries from both sides)
  - file2.md (combined changelog entries)
  "
  ```

## Conflict Resolution Patterns

### JSON Files

- Merge array entries from both sides, deduplicate
- For version fields, take the higher version
- For object properties, include properties from both sides
- Validate JSON after resolution

### Markdown Files

- Include content from both sides
- Maintain chronological order for changelogs
- Include table rows from both sides

### Source Code

- Use the common ancestor (zdiff3 `|||||||` section) to understand what both sides changed
- Integrate both modifications preserving the intent of each
- If same line changed incompatibly, prefer the PR branch change and note in commit message

### Squash Merge Pitfall

If the same conflicts keep recurring, the likely cause is squash merges. Squash-merging breaks the common ancestry chain, so stacked or sibling branches lose their merge base. Rerere mitigates this by replaying recorded resolutions, but the root fix is to avoid squash merges on branches with dependents. When a squashed base leaves a dependent carrying the now-collapsed commits, recover with `git rebase --onto origin/main <old-base-tip> <dependent>` (see the git-pr skill's Stacked PRs section).

### When to Abort

Abort with `git merge --abort` or `git rebase --abort` if:
- Conflicts span many files with incompatible architectural changes
- Resolution requires understanding business requirements you don't have context for
- Lock files are the only conflicts (delete, regenerate, commit)

## Pre-Merge Trial Integration (landing a wave of PRs)

When several branches will land together — a wave of parallel feature branches,
a PR stack, or sibling fixes touching overlapping files — surface and resolve
the conflicts **once, on a throwaway branch, before touching `main`**. This also
catches the *silent* failure a plain auto-merge can't: when two branches each add
the **same** helper/import in non-adjacent spots, git merges both copies with no
conflict, producing a tree that does not compile. The merge *message* is not
proof of correctness — only compiling the merged tree is.

```bash
# rerere on, so the resolution you do here is recorded for the real merges
git config rerere.enabled true
git config rerere.autoupdate true

git switch -c trial/integration origin/main
for b in <branch-1> <branch-2> <branch-3>; do
  git merge --no-ff --no-edit "origin/$b" || git commit --no-edit   # resolve, then commit
done

<build + test command>          # e.g. just check / cargo test / npm test — the real gate
```

If the merged tree builds and tests green, the resolution is validated **and
rerere has cached it**. Discard the trial branch and do the real merges/rebases
in order — rerere auto-replays the same resolution on the actual base merge and
on each dependent's `--onto` rebase (see git-pr Stacked PRs), so you never
re-resolve by hand:

```bash
git switch main && git branch -D trial/integration   # the rerere cache persists
```

Payoff: conflicts surface before `main` is touched (not mid-merge under
pressure); one resolution is replayed everywhere via rerere; and compiling the
merged tree catches silent duplicate-addition merges a green merge message hides.

## Quick Reference

| Task | Command |
|------|---------|
| List conflicted files | `git diff --name-only --diff-filter=U` |
| Re-checkout with zdiff3 | `git checkout --conflict=zdiff3 -- <file>` |
| Accept current branch | `git restore --ours -- <file>` |
| Accept incoming branch | `git restore --theirs -- <file>` |
| Recreate conflict markers | `git checkout -m -- <file>` |
| Check rerere status | `git rerere status` |
| View rerere diff | `git rerere diff` |
| Forget bad resolution | `git rerere forget <file>` |
| Abort merge | `git merge --abort` |
| Abort rebase | `git rebase --abort` |
| Continue rebase | `git rebase --continue` |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| List conflicts | `git diff --name-only --diff-filter=U` |
| Conflict count | `git diff --name-only --diff-filter=U \| wc -l` |
| Full conflict diff | `git diff --diff-filter=U` |
| PR mergeable state | `gh pr view N --json mergeable` |
| Check markers remain | `grep -rn '<<<<<<<' <files>` |
| Porcelain status | `git status --porcelain=v2` |
| Detect merge/rebase state | `test -f .git/MERGE_HEAD && echo merge \|\| test -d .git/rebase-merge && echo rebase` |
