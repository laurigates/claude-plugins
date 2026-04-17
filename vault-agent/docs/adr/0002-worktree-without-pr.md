# ADR-0002: Isolate writes in a git worktree; skip PR creation

- Status: Accepted
- Date: 2026-04-17

## Context

The target vault (LakuVault) is an Obsidian vault that the user actively edits in the Obsidian desktop app. The vault IS a git repository, but there is no remote. We still want:

- Diff visibility when the agent mass-edits hundreds of files
- Cheap rollback if the agent misbehaves
- No file conflicts with the live Obsidian session

git-repo-agent solves this with a worktree + `git push` + `gh pr create`. We can't use the PR step.

## Decision

Every write mode:

1. Creates a worktree at `.claude/worktrees/vault-agent-<timestamp>/` on branch `vault-agent/<timestamp>`.
2. Runs fixers inside the worktree; commits are conventional-commits format, one per fix category.
3. Leaves the branch on disk — no push, no PR.
4. Prints a review banner with the exact `git diff` and `git merge --ff-only` commands.

The user reviews with their normal tooling (lazygit, delta, VS Code) and merges manually when satisfied.

## Consequences

- Obsidian can keep running on `main` — the worktree checkout is a separate directory, so open files don't change under Obsidian's feet.
- No dependency on `gh` CLI, no GitHub auth to maintain.
- The ADR would be a 5-minute change if the user later pushes the vault to a remote — add a flag, call `gh pr create`. All existing code paths stay the same.
- Branch accumulation: if the user forgets to merge or delete branches, they pile up. Documented in the README; not automated (deletion is destructive).

## Related

- git-repo-agent ADR-004: worktree isolation with PR.
