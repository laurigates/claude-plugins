# Local Feature Branches: Linear History and Daily Upkeep

Moved verbatim from `SKILL.md`. Read when working on a local feature branch instead of main-branch development.

## Linear History Workflow

### Trunk-Based Development

**Preferred: Main-branch development** (see [SKILL.md § Main-Branch Development](../SKILL.md#main-branch-development-preferred)) - no local feature branches needed.

**Alternative: Local feature branches** for complex multi-day work:

```bash
# Feature branch lifecycle (max 2 days)
git switch main
git pull origin main
git switch -c feat/user-auth

# Daily rebase to stay current
git switch main && git pull
git switch feat/user-auth
git rebase main

# Interactive cleanup before PR
git rebase -i main
# Squash, fixup, reword commits for clean history

# Push and create PR
git push -u origin feat/user-auth
```

Use local branches only when:
- Multi-day complex features requiring isolation
- Experimental work that might be abandoned
- Need to switch contexts frequently between unrelated work

### Squash Merge Strategy

Maintain linear main branch history:

```bash
# Manual squash merge
git switch main
git merge --squash feat/user-auth
git commit -m "feat: add user authentication system

- Implement JWT token validation
- Add login/logout endpoints
- Create user session management

Closes #123"
```

### Interactive Rebase Workflow

Clean up commits before sharing:

```bash
# Rebase last 3 commits
git rebase -i HEAD~3

# Common rebase commands:
# pick   = use commit as-is
# squash = combine with previous commit
# fixup  = squash without editing message
# reword = change commit message
# drop   = remove commit entirely

# Example rebase todo list:
pick a1b2c3d feat: add login form
fixup d4e5f6g fix typo in login form
squash g7h8i9j add form validation
reword j1k2l3m implement JWT tokens
```

## Best Practices

### Daily Integration Workflow

```bash
# Start of day: sync with main
git switch main
git pull origin main
git switch feat/current-work
git rebase main

# End of day: push progress
git add . && git commit -m "wip: daily progress checkpoint"
git push origin feat/current-work

# Before PR: clean up history
git rebase -i main
git push --force-with-lease origin feat/current-work
```

### Conflict Resolution with Rebase

```bash
# When rebase conflicts occur
git rebase main
# Fix conflicts in editor
git add resolved-file.txt
git rebase --continue

# If rebase gets messy, abort and merge instead
git rebase --abort
git merge main
```

### Safe Force Pushing

```bash
# Always use --force-with-lease to prevent overwriting others' work
git push --force-with-lease origin feat/branch-name

# Never force push to main/shared branches
# Use this alias for safety:
git config alias.pushf 'push --force-with-lease'
```
