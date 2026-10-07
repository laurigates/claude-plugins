# Modern Git Commands (2025)

Moved verbatim from `SKILL.md`. Read when choosing `git switch` / `git restore` over a legacy `git checkout` / `git reset` form.

## Modern Git Commands (2025)

### Switch vs Checkout

Modern Git uses specialized commands instead of multi-purpose `git checkout`:

```bash
# Branch switching - NEW WAY (Git 2.23+)
git switch feature-branch          # vs git checkout feature-branch
git switch -c new-feature          # vs git checkout -b new-feature
git switch -                       # vs git checkout -

# Creating branches with tracking
git switch -c feature --track origin/feature
git switch -C force-recreate-branch
```

### Restore vs Reset/Checkout

File restoration is now handled by `git restore`:

```bash
# Unstaging files - NEW WAY
git restore --staged file.txt      # vs git reset HEAD file.txt
git restore --staged .             # vs git reset HEAD .

# Discarding changes - NEW WAY
git restore file.txt               # vs git checkout -- file.txt
git restore .                      # vs git checkout -- .

# Restore from specific commit
git restore --source=HEAD~2 file.txt    # vs git checkout HEAD~2 -- file.txt
git restore --source=main --staged .    # vs git reset main .
```

### Command Migration Guide

| Legacy Command                | Modern Alternative                 | Purpose             |
| ----------------------------- | ---------------------------------- | ------------------- |
| `git checkout branch`         | `git switch branch`                | Switch branches     |
| `git checkout -b new`         | `git switch -c new`                | Create & switch     |
| `git checkout -- file`        | `git restore file`                 | Discard changes     |
| `git reset HEAD file`         | `git restore --staged file`        | Unstage file        |
| `git checkout HEAD~1 -- file` | `git restore --source=HEAD~1 file` | Restore from commit |
