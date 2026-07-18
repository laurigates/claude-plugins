---
name: configure-worktreeinclude
description: "Generate a .worktreeinclude so Claude Code copies gitignored env/secret/config files into new worktrees. Use when worktrees miss .env or local config."
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(git add *), Bash(git status *), Bash(git check-ignore *), Bash(git ls-files *), Bash(find *), AskUserQuestion, TodoWrite
created: 2026-06-25
modified: 2026-06-25
compatibility: claude-code
reviewed: 2026-06-25
---

# /configure:worktreeinclude

Generate a `.worktreeinclude` file whose patterns tell Claude Code which
**gitignored** files to copy from the main checkout into a newly-created git
worktree. A worktree is a fresh checkout containing only git-tracked files, so
gitignored runtime inputs — `.env`, local secrets, local config — do not come
along by default; this skill builds the include list from the gitignored files
**actually present in this repo**, so the patterns match the project instead of
a generic template.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Worktrees / subagent worktrees start without `.env` or local config | Ignoring a build artifact — use `/configure:gitignore` |
| Onboarding a repo to Claude Code (also reachable via `/configure:repo`) | Copying large regenerable dirs (`node_modules/`) — let the worktree's setup hook reinstall them |
| You want gitignored inputs reproduced per-worktree without committing them | A non-git VCS — a custom `WorktreeCreate` hook must copy files itself; `.worktreeinclude` is git-only |

## What `.worktreeinclude` is

`.worktreeinclude` lives at the repo root, alongside `.gitignore`, and uses
**`.gitignore` glob syntax**. When Claude Code creates a worktree (the
`--worktree` flag, subagent worktree isolation, or parallel desktop sessions),
every file that matches a pattern **and** is gitignored is copied into the new
worktree. The match is constrained two ways by design:

- **Only gitignored files are copied.** A pattern that matches a tracked file is
  a no-op — tracked files are already in the worktree, never duplicated.
- **You choose the inputs, not the bulk.** The right entries are small
  per-environment inputs (env files, local secrets, local config). Large
  regenerable trees (`node_modules/`, `.venv/`, build output) are better
  rebuilt by the worktree's setup than copied — copying is slow and can carry
  platform-specific binaries or absolute paths.

Commit `.worktreeinclude` so the whole team (and every agent worktree) shares
the same include list.

## Context

- Existing worktreeinclude: !`find . -maxdepth 1 -name .worktreeinclude -type f`
- Gitignore present: !`find . -maxdepth 1 -name .gitignore -type f`
- Ignored entries present (collapsed): !`git status --ignored --porcelain=v1`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report the proposed include patterns without writing any file |
| `--fix` | Write the proposed patterns without prompting (headless) |

Default (no flag): propose the patterns, confirm the set with the user via
`AskUserQuestion`, write `.worktreeinclude`, and `git add` it (staged, not
committed).

## Execution

Execute this `.worktreeinclude` configuration workflow:

### Step 1: Read existing state

Parse `$ARGUMENTS` for `--check-only` / `--fix`. From Context, note whether
`.worktreeinclude` already exists (Read it and record its current patterns if
so) and capture the ignored-entry list. If no `.gitignore` exists and no ignored
entries are present, report "nothing gitignored to include" and stop.

### Step 2: Classify the gitignored entries

The ignored list comes from `git status --ignored --porcelain=v1` — lines
prefixed `!!` are ignored paths, with directories collapsed to a single trailing
`/` entry. Sort each entry into one of two buckets:

| Propose to **include** (small per-environment inputs) | **Skip** (regenerable / large / risky) |
|--------------------------------------------------------|-----------------------------------------|
| `.env`, `.env.local`, `.env.*` (not a tracked `.env.example`) | `node_modules/`, `.venv/`, `venv/`, `.direnv/` |
| `*.local` config (`config.local.*`, `settings.local.*`) | `dist/`, `build/`, `out/`, `target/`, `.next/`, `.nuxt/` |
| local secrets / credentials present as files (`secrets.*`, gitignored `*.pem`/`*.key`) | `__pycache__/`, `.pytest_cache/`, `.ruff_cache/`, `.mypy_cache/` |
| gitignored tool config the build needs (`.npmrc`, `.tool-versions`) when present | `coverage/`, `.coverage`, `*.log`, `.DS_Store`, `.git/` |

Only propose patterns for entries that **actually appear** in the ignored list —
the include list must describe this repo. When in doubt about a file (it could
be a needed input or just local cruft), surface it as a candidate rather than
deciding silently.

### Step 3: Confirm the set

- `--check-only`: print the proposed patterns as a diff-style block; write nothing.
- `--fix`: skip confirmation; use the proposed include set as-is.
- Default: present the proposed patterns with `AskUserQuestion`, letting the
  user drop any pattern or add one you skipped (the built-in "Other" option
  covers additions). Keep the question self-contained — list each proposed
  pattern and the file(s) it matches.

### Step 4: Write or report

Write the confirmed patterns to `.worktreeinclude` at the repo root, one pattern
per line, with a short header comment. If the file already exists, **merge
additively** — preserve existing lines verbatim and append only patterns not
already present (idempotent, safe to re-run). Then `git add .worktreeinclude`.

### Step 5: Verify

Confirm each written pattern targets a gitignored file (so it will actually be
copied): `git check-ignore -v <path>` should report a match for a representative
file behind each pattern. A pattern that matches no gitignored file is inert —
flag it so the user knows it does nothing.

### Step 6: Report

Print a summary: patterns added vs already-present, the file path, and the
`git diff --cached` hint. If `--check-only`, prefix with "DRY RUN — no files
modified".

## Important Notes

- **Built from this repo, not a template.** Every proposed pattern must trace to
  a gitignored file present in the working tree — that is what "based on the
  repo in question" means.
- **Additive only.** Never remove or reorder existing `.worktreeinclude` lines;
  append missing patterns so the skill is idempotent.
- **Patterns only match gitignored files.** A pattern over a tracked file is a
  silent no-op — `git check-ignore` in Step 5 catches inert patterns.
- **Prefer rebuild over copy for big trees.** Keep `node_modules/`, virtualenvs,
  and build output out of the include list; let the worktree's setup hook
  regenerate them.
- **Commit the file.** `.worktreeinclude` is shared configuration — stage it and
  let the user commit so every worktree (and teammate) uses the same list.
- Never auto-commit; stage and let the user review with `git diff --cached`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Propose + write the include list | `/configure:worktreeinclude` |
| Dry-run, no file changes | `/configure:worktreeinclude --check-only` |
| Write headless (no prompt) | `/configure:worktreeinclude --fix` |
| List gitignored entries (collapsed) | `git status --ignored --porcelain=v1` |
| Confirm a pattern matches a gitignored file | `git check-ignore -v .env` |
| Review staged change | `git diff --cached` |

## See Also

- `/configure:gitignore` — the sibling skill that keeps Claude Code runtime
  state (incl. `.claude/worktrees/`) out of commits
- `/configure:repo` — full repo onboarding (offers this skill)
- [Claude Code worktrees documentation](https://code.claude.com/docs/en/worktrees#copy-gitignored-files-into-worktrees)
