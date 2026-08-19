---
name: git-repo-delete-check
description: "Verify a repo's work survives deletion — remote, unpushed commits, stashes — then offer a push or tar backup. Use when asked to rm -rf, delete, or prune a git checkout."
allowed-tools: Bash(git -C *), Bash(git remote *), Bash(git status *), Bash(git log *), Bash(git stash *), Bash(git branch *), Bash(du *), Bash(tar *), Bash(mkdir *), Read, Glob, AskUserQuestion, TodoWrite
created: 2026-08-19
modified: 2026-08-19
reviewed: 2026-08-19
---

# /git:repo-delete-check

Run this before any deletion of a git checkout — `rm -rf`, a cleanup
sweep over old clones, or a disk-space prune.

Before `rm -rf`'ing a git repository, verify that its work is preserved
somewhere else. A local checkout that has no remote is the *only* copy —
deletion is permanent and silently destroys committed history plus all
uncommitted work.

## Preflight check

```
git -C <repo> remote -v
```

| Output | Meaning | Action |
|---|---|---|
| Has `origin <url>` | Pushed work lives on the remote | Local delete is safe; uncommitted work and unpushed commits are still lost — surface them first |
| Empty / no output | **Local-only repo** | Stop. The repo's entire history is in this checkout |

Always run this check before deleting, even when the user has explicitly
said "delete this repo" — they may not realize a particular checkout is
local-only.

## When the repo is local-only

Surface the situation and offer three options, in increasing
destructiveness, before doing anything:

1. **Push to a new GitHub repo first.** Preserves the work on the
   remote, then the local checkout can be deleted safely. Requires
   creating the GitHub repo (or knowing it exists empty).
2. **Tar to a labelled backup.** `tar -czf
   ~/Backups/<name>-$(date -I).tar.gz <repo>`. Preserves the work on
   disk under a date-stamped name; the local checkout can then be
   deleted.
3. **Delete with no backup.** Confirm the user genuinely wants the work
   gone — including any uncommitted files, branches, and stashes.

Default when the user says a generic "go" / "yes" without specifying:
option 2 (tar backup, then delete). It preserves the work without
requiring remote setup or losing anything, and the backup can be
deleted later when confidence builds.

## Also surface before deleting

Even when a remote exists, these conditions warrant a pause:

- **Uncommitted changes.** `git status --porcelain` is non-empty —
  those files are not on any remote.
- **Unpushed commits.** `git log @{u}..HEAD --oneline` is non-empty —
  those commits exist only locally.
- **Stashes.** `git stash list` is non-empty — stashes are pure
  working-copy state.
- **Untracked branches.** `git branch -vv` shows branches without
  upstreams — those branches' commits may be local-only.

If any are present, list them in the same message as the deletion
prompt so the user can decide knowing what disappears.

## Rationale

The general system-prompt rule ("destructive operations need
confirmation") covers the *spirit*. This rule is the *concrete check*
to run before nuking a repo: the failure mode of skipping it is
silent permanent data loss, with no way to recover.

## Related

- `git-plugin:git-coworker-check` — is another agent writing here? (different
  question, same safety-diagnostic shape)
- `git-plugin:git-maintain` — maintenance *inside* a surviving repo
- `git-plugin:deadbranch` — deleting branches, not the checkout
- `macos-plugin:macos-disk-usage` — the likely caller when disk pressure
  prompts a clone cleanup
