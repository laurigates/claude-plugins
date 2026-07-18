---
name: configure-gitignore
description: "Manage .gitignore's Claude Code block — worktrees, scheduled-task lock, local settings. Use when onboarding a repo or .gitignore lacks Claude entries."
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(git add *), Bash(git status *), Bash(git check-ignore *), Bash(find *), AskUserQuestion, TodoWrite
created: 2026-06-24
modified: 2026-07-18
compatibility: claude-code
reviewed: 2026-06-24
---

# /configure:gitignore

Append a managed **Claude Code runtime-state** block to a repo's `.gitignore` so
the files Claude Code writes during a session — agent worktrees, the
scheduled-task lock, the per-user local settings overlay — never get committed.
The block is added non-destructively: every other line in the repo's
`.gitignore` is left untouched.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Onboarding a repo to Claude Code (also reachable via `/configure:repo`) | Ignoring a project-specific build artifact — edit `.gitignore` directly |
| A repo's `.gitignore` is missing the Claude Code runtime-state entries | Configuring `.gitattributes` — use `/configure:gitattributes` |
| `.claude/worktrees/` or `settings.local.json` keeps showing as untracked | Configuring Claude Code settings — use `/configure:repo` |

## The managed block

```
# Claude Code runtime state (managed by /configure:gitignore)
.claude/worktrees/
/worktrees/
.claude/scheduled_tasks.lock
.claude/settings.local.json
```

| Entry | Why it's ignored |
|-------|------------------|
| `.claude/worktrees/` | Agent worktree checkouts created by `Agent(isolation: "worktree")` and Wave dispatch |
| `/worktrees/` | Repo-root variant some workflows use for the same agent worktrees |
| `.claude/scheduled_tasks.lock` | Scheduled-task lock — pure runtime state |
| `.claude/settings.local.json` | Per-user local settings overlay — personal, not shared |

The block is **additive only** — it never removes or reorders existing lines, and
a project that wants more ignored (e.g. OpenCode export artifacts) keeps those
entries alongside this block.

## Context

- Existing gitignore: !`find . -maxdepth 1 -name .gitignore -type f`
- Claude dir present: !`find . -maxdepth 2 -type d -name .claude`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report which managed entries are missing without writing any file |
| `--fix` | Append the missing entries without prompting |

Default (no flag): report the missing entries, append them, and `git add` the file (staged, not committed).

## Execution

Execute this `.gitignore` configuration workflow:

### Step 1: Read existing state

Parse `$ARGUMENTS` for `--check-only` / `--fix`. If a `.gitignore` exists (from
Context), Read it and record which managed entries are already present —
counting an entry as covered when its exact line appears **or** a broader
existing pattern already ignores it (e.g. a bare `.claude/` covers
`.claude/worktrees/`). Otherwise plan to create `.gitignore`.

### Step 2: Compute the missing entries

From the managed block above, build the set of entries not already covered.
If every entry is present, report "already configured" and stop.

### Step 3: Write or report

- `--check-only`: print the missing entries as a diff-style block; write nothing.
- Otherwise: append the managed-block header comment (only if not already
  present) followed by the missing entries to the end of `.gitignore` (or create
  the file with the block). Preserve all existing content verbatim. Then
  `git add .gitignore`.

### Step 4: Verify

Confirm the block took effect: `git check-ignore -v .claude/worktrees/probe`
should report a match against the new line. (The probe path need not exist —
`git check-ignore` matches patterns, not files.)

### Step 5: Report

Print a summary: entries added vs already-present, the file path, and the
`git diff --cached` hint. If `--check-only`, prefix with "DRY RUN — no files modified".

## Important Notes

- **Additive only.** Never remove, reorder, or rewrite existing `.gitignore`
  lines — append the managed block at the end. This makes the skill safe to
  re-run (idempotent) and safe alongside project-specific ignores.
- **Respect broader existing patterns.** If the repo already ignores a parent
  (`.claude/`), don't add the narrower child — it's redundant.
- **`.claude/worktrees/` is the load-bearing entry.** Agent worktrees are full
  repo clones; committing one is a large accidental diff. This is the entry the
  cross-repo rollout exists to guarantee.
- Never auto-commit; stage and let the user review with `git diff --cached`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Propose + append the managed block | `/configure:gitignore` |
| Dry-run, no file changes | `/configure:gitignore --check-only` |
| Append headless (no prompt) | `/configure:gitignore --fix` |
| Confirm an entry took effect | `git check-ignore -v .claude/worktrees/probe` |
| Review staged change | `git diff --cached` |

## See Also

- `/configure:repo` — full repo onboarding (offers this skill)
- `/configure:gitattributes` — the sibling skill for `.gitattributes`
- `.claude/rules/agent-coworker-detection.md` (claude-plugins) — why `.claude/worktrees/` matters in shared checkouts
