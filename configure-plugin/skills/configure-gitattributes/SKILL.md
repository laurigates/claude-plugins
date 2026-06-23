---
name: configure-gitattributes
description: "Configure .gitattributes: union-merge for append-only tables, linguist-generated for build output, LF normalization. Use when setting up .gitattributes or taming append-only merge conflicts."
args: "[--check-only] [--fix]"
argument-hint: "[--check-only] [--fix]"
allowed-tools: Glob, Grep, Read, Write, Edit, Bash(git add *), Bash(git status *), Bash(git diff *), Bash(git check-attr *), Bash(find *), Bash(test *), AskUserQuestion, TodoWrite
created: 2026-06-22
modified: 2026-06-22
reviewed: 2026-06-22
---

# /configure:gitattributes

Audit or create a repo's `.gitattributes`, applying the three high-value
attributes — `merge=union` for append-only tables, `linguist-generated` for
build output, and LF normalization — while never applying `merge=union` to a
file it would corrupt. See `.claude/rules/gitattributes.md` for the convention.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| A repo has no `.gitattributes` and wants the standard baseline | Changing a single setting in an existing file — edit it directly |
| Parallel PRs keep conflicting on an append-only table/changelog | The conflict is semantic (same line edited) — that needs a real merge |
| Onboarding a repo (also reachable via `/configure:repo`) | Configuring Claude Code settings — use `/configure:repo` |
| Build output (changelogs, lockfiles, generated trees) clutters PR diffs | — |

## Context

- Existing attributes: !`find . -maxdepth 1 -name .gitattributes -type f`
- Shell scripts present: !`find . -name '*.sh' -not -path '*/.git/*' -path '*/scripts/*'`
- Changelogs: !`find . -name 'CHANGELOG.md' -not -path '*/.git/*'`
- Generated trees: !`find . -type d -name generated -not -path '*/.git/*'`
- Rendered diagrams: !`find . -path '*/docs/diagrams/*' -name '*.svg'`
- Lockfiles: !`find . -maxdepth 3 \( -name 'uv.lock' -o -name 'bun.lock' -o -name 'package-lock.json' -o -name 'pnpm-lock.yaml' \)`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--check-only` | Report the proposed additions without writing any file |
| `--fix` | Apply the safe (zero-risk) additions without prompting |

Default (no flag): propose the additions, write them, and `git add` the file (staged, not committed).

## Execution

Execute this `.gitattributes` configuration workflow:

### Step 1: Read existing state

If a `.gitattributes` exists (from Context), Read it and record which paths are
already covered. Otherwise plan to create one with a header comment.

### Step 2: Classify candidates into the three buckets

Build the proposed line set from the Context detections, skipping any path
already covered:

1. **LF normalization** — if any `*.sh` is present, add `* text=auto eol=lf`
   and `*.sh text eol=lf`. (No-op on an all-LF tree; protects shell shebangs.)
2. **`linguist-generated`** (always safe — display-only, no merge effect) — add
   one line per present group: `**/CHANGELOG.md`, `.release-please-manifest.json`
   (if present), each `*/generated/**` tree, `docs/diagrams/*.svg`, and each
   lockfile found.
3. **`merge=union`** (the risky one) — do **NOT** auto-apply. Identify
   candidate **one-line-per-entry, append-only** files (e.g. a Markdown table
   every PR appends a single row to). Run the one-line test from
   `.claude/rules/gitattributes.md`. Exclude changelogs (multi-line entries),
   JSON, and code.

### Step 3: Decide union marks interactively

For each `merge=union` candidate, confirm with `AskUserQuestion` ("Mark
`<path>` as `merge=union`? It must be append-only with one logical entry per
line."). Apply only confirmed paths. Under `--fix`, skip union entirely (apply
only the zero-risk buckets) and list the candidates as recommendations.

### Step 4: Write or report

- `--check-only`: print the proposed additions as a diff-style block; write nothing.
- Otherwise: append the missing lines to the existing `.gitattributes` (or
  create it with a header), each non-obvious line carrying a `#` comment for
  *why* it qualifies. Then `git add .gitattributes`.

### Step 5: Verify any new union mark

For each newly added `merge=union` line, confirm it took effect:
`git check-attr merge -- <path>` should report `merge: union`. Recommend a
sandbox check (`git merge --no-ff` of two divergent single-row appends → zero
conflict markers, both rows present) before relying on it.

### Step 6: Report

Print a summary: lines added per bucket, union candidates deferred, and the
`git diff --cached` hint. If `--check-only`, prefix with "DRY RUN — no files modified".

## Important Notes

- **`merge=union` only for one-line-per-entry append-only files.** It keeps
  both sides of a conflicted hunk, so on an *edited* line it duplicates content,
  and on JSON it breaks syntax. When unsure, leave it off — the
  `resolve-additive-conflicts.py` pre-pass (in repos that have it) union-merges
  additive conflicts generically without the mark.
- **`linguist-generated` is always safe** — it only changes GitHub's diff
  display and language stats, never merge behavior.
- **LF normalization is a no-op on an all-LF tree** but prevents a future CRLF
  commit from breaking a shell shebang.
- Never auto-commit; stage and let the user review with `git diff --cached`.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Propose + apply safe attributes | `/configure:gitattributes` |
| Dry-run, no file changes | `/configure:gitattributes --check-only` |
| Apply zero-risk set headless (skip union prompts) | `/configure:gitattributes --fix` |
| Confirm a union mark took effect | `git check-attr merge -- <path>` |
| Review staged change | `git diff --cached` |

## See Also

- `.claude/rules/gitattributes.md` — the convention this skill applies
- `/configure:repo` — full repo onboarding (offers this skill)
- `scripts/resolve-additive-conflicts.py` (claude-plugins) — the deterministic union pre-pass for additive conflicts
