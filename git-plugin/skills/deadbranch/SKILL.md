---
name: deadbranch
description: deadbranch CLI for stale-branch cleanup — dry-run preview, TUI or non-interactive delete, protects main/develop/WIP. Use when asked to clean up branches, prune branches, or remove stale branches.
args: "[--days N] [--local] [--remote] [--force] [--interactive] [--dry-run] [--yes] [--stats-only]"
argument-hint: "--days 30 --dry-run (default: survey + dry-run preview, then ask before deleting)"
allowed-tools: Bash(deadbranch *), Bash(git branch *), Bash(git log *), Bash(git remote *), Bash(git rev-parse *), Bash(git merge-tree *), Bash(gh pr list *), AskUserQuestion, TodoWrite
created: 2026-05-07
modified: 2026-06-30
reviewed: 2026-06-30
---

# /git:deadbranch

Survey stale git branches and clean them up safely. Always previews
before deleting; backup system means every deletion is recoverable.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Asked to clean up, prune, or remove stale branches across a repo | Deleting a single known branch — `git branch -d <name>` is simpler |
| You want a survey of branch health (age, merge status, count) first | Doing routine gc / repo maintenance — use `/git:maintain` |
| You want recoverable deletion with a dry-run preview and backups | Pruning remote-tracking refs only — `git remote prune origin` |

## Parameters

Parse from `$ARGUMENTS` (all optional):

| Flag | Default | Description |
|------|---------|-------------|
| `--days N` | `30` | Age threshold — branches older than N days are stale |
| `--local` | off | Target local branches only |
| `--remote` | off | Target remote branches only |
| `--force` | off | Include unmerged branches (dangerous — ask for explicit confirmation) |
| `--interactive` | off | Open full-screen TUI for visual selection |
| `--dry-run` | on | Show what would be deleted without deleting (always on for the preview step) |
| `--yes` | off | Skip confirmation prompts (only use if user explicitly asks for automation) |
| `--stats-only` | off | Run stats + list only, skip the clean step entirely |

When no flags are given, default to the survey-first workflow below.

## Workflow

### Step 1: Survey

Run in parallel:

```bash
deadbranch stats
deadbranch list
```

Report both outputs. The stats command shows total branch count, stale
count, and age distribution. The list shows each stale branch with its
age, merge status, last commit date, and author.

If `--days N` was provided, pass `-d N` to both commands.
If `--local` or `--remote` was provided, pass the flag to `list`.

If no stale branches are found, stop here and report the repo is clean.
If `--stats-only` was provided, stop here after reporting.

### Step 1.5: Reclassify squash-merged branches

`deadbranch` classifies "merged" via **commit ancestry** (`git branch
--merged`-style). On repos that **squash-merge** — the release-please /
conventional-commit default — the squash collapses a branch into a single new
commit on the base with a fresh SHA, so the branch's own commits are never
ancestors and it reads as **unmerged**. The "safe to delete" count is therefore
a **lower bound** on squash-merge repos (in one real cleanup, only 4 of 28
actually-merged branches were flagged safe).

After the survey, reclassify each branch `deadbranch` marked **unmerged** using
two deterministic signals that survive squash-merge **and** later file drift on
the base. A branch matching **either** is safe to delete:

1. **`merge-tree` no-op** — merging the branch into the base changes nothing,
   proving its content is already present (git ≥ 2.38):

   ```bash
   base_tree=$(git rev-parse <base>^{tree})
   merged=$(git merge-tree --write-tree <base> <branch>)
   [ "$merged" = "$base_tree" ] && echo "MERGED (contained in base)"
   ```

   A clean result whose tree equals the base's tree means the branch
   contributes nothing not already in the base. A different tree / non-zero exit
   is **not** proof of "unmerged" — treat it as "review", not "delete".

2. **A MERGED PR for the branch head** — GitHub is authoritative; the squash
   landed the work at merge time regardless of later drift:

   ```bash
   gh pr list --state all --head <branch> --json state --jq '.[0].state'
   ```

   A `MERGED` result means the branch's work landed (read `state` /
   `mergedAt`, never a `merged` field — see `.claude/rules/gh-json-fields.md`).

Report a "squash-merged (reclassified safe)" group alongside `deadbranch`'s own
merged set so the user sees the true safe-to-delete count. Branches matching
neither signal stay in the keep/review group — do **not** sweep them with
`--force`, which also deletes genuinely-unmerged work.

> This reclassification is read-only — it never deletes. Deletion still flows
> through the Step 2 dry-run and Step 3 confirmation below, with the
> squash-merged branches included in the set the user approves.

### Step 2: Dry-run preview

Always run a dry-run before any real deletion:

```bash
deadbranch clean --dry-run [--days N] [--local|--remote] [--force]
```

Report the dry-run output. If nothing would be deleted (e.g. all stale
branches are unmerged and `--force` was not set), explain why and offer
to re-run with `--force` if the user wants to include unmerged branches.

### Step 3: Confirm and clean

After the dry-run, ask the user what to do:

```
AskUserQuestion("Proceed with branch deletion?", options=[
  "Yes — delete all shown branches",
  "Interactive TUI — let me pick",
  "No — survey only, skip deletion"
])
```

- **Yes**: run `deadbranch clean [options]`
- **Interactive**: run `deadbranch clean --interactive [options]`
  (note: the TUI requires a real terminal — warn the user that this
  opens a full-screen interface they must interact with directly via
  `! deadbranch clean --interactive`)
- **No**: print the summary and stop

If the user passed `--interactive` in `$ARGUMENTS`, skip the question
and go straight to TUI mode.
If `--yes` was explicitly passed, skip confirmation and delete directly.

### Step 4: Report

After deletion, confirm with:

```bash
deadbranch backup list
```

Report how many branches were deleted and that their SHAs are backed
up (recoverable via `deadbranch backup restore <branch>`).

## Safety Rules

| Situation | Action |
|-----------|--------|
| `--force` requested | Show extra warning: "This deletes unmerged branches. These are NOT recoverable from the remote." before dry-run |
| `--remote` requested | Note that remote deletion affects everyone on the team |
| Branch is WIP / draft | `deadbranch` skips these automatically; mention it in the report |
| Protected branches (main/master/develop/staging/production) | `deadbranch` skips these automatically |

## Recovery

If the user wants to recover a deleted branch:

```bash
deadbranch backup list              # see what's saved
deadbranch backup restore <branch>  # restore by name
```

Backups store the branch tip SHA. Restoration creates the branch
locally pointing at that SHA.

## Common Invocations

```bash
# Default survey + dry-run + confirm
deadbranch list
deadbranch stats
deadbranch clean --dry-run

# Local branches only, 60-day threshold
deadbranch list --local --days 60
deadbranch clean --local --days 60 --dry-run

# Remote branches — team-visible action, ask twice
deadbranch list --remote
deadbranch clean --remote --dry-run

# Interactive TUI (run by user in their terminal)
! deadbranch clean --interactive

# Non-interactive automation (CI / scripts)
deadbranch clean --yes --merged
```

## Interactive TUI Note

`deadbranch clean --interactive` opens a full-screen TUI with:
- Vim-style navigation (`hjkl`, `/` to fuzzy search)
- Visual range selection
- 6-column sort
- Space to toggle individual branches for deletion

Claude Code cannot operate the TUI — instruct the user to run it
themselves with the `!` prefix: `! deadbranch clean --interactive`.

## Configuration

`deadbranch` reads `~/.deadbranch/config.toml`. View with:

```bash
deadbranch config show
```

Key settings:

| Setting | Default | Description |
|---------|---------|-------------|
| `general.default_days` | 30 | Default age threshold |
| `branches.default_branch` | auto-detect | Default branch name |
| `branches.protected` | main, master, develop, staging, production | Never deleted |
| `branches.exclude_patterns` | wip/*, draft/*, */wip, */draft | Pattern-excluded |

To change a setting:
```bash
deadbranch config set general.default_days 60
```

## Installation (if not present)

Check availability first:
```bash
which deadbranch || echo "not installed"
```

Install via cargo (preferred — already in mise/Rust toolchain):
```bash
cargo install deadbranch
```

Or via Homebrew:
```bash
brew install armgabrielyan/tap/deadbranch
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick health stats | `deadbranch stats` |
| List stale (machine-survey) | `deadbranch list --days 30` |
| Safe preview before delete | `deadbranch clean --dry-run` |
| Non-interactive cleanup | `deadbranch clean --yes --merged` |
| Recover a deleted branch | `deadbranch backup restore <branch>` |
