---
created: 2026-06-16
modified: 2026-10-07
compatibility: claude-code
reviewed: 2026-07-08
allowed-tools: Glob, Read, Edit, Write, Bash(git status *), Bash(git diff *), Bash(wc *), Bash(ls *), AskUserQuestion, TodoWrite
model: opus
description: Audit CLAUDE.md and .claude/rules for always-loaded content that should become an on-demand skill. Use when CLAUDE.md feels bloated, trimming context, or promoting a rule into a skill.
args: "[scope-path]"
argument-hint: "[scope-path]"
name: meta-context-diet
---

# meta-context-diet

Audit always-loaded context — `CLAUDE.md` files and `.claude/rules/*.md` — for material that would be cheaper and clearer as an **on-demand skill**, then migrate approved candidates — per-candidate confirmation for lossy edits, batched approval for the safe ones.

The premise: `CLAUDE.md` and unscoped rules are paid for on **every** turn. A skill costs only its `name` + `description` in the listing budget until its intent fires, then loads its body on demand. Anything that is *not* a hard, always-respected invariant is a candidate to move off the always-loaded surface.

## When to Use This Skill

| Use this skill when... | Use a different skill when... |
|---|---|
| `CLAUDE.md` or `.claude/rules/` has grown heavy and you want to find what can move to on-demand skills | You want to move rules/skills *between scopes* (project → user-global) — use `meta-promote` |
| A rule is really a procedure/workflow triggered by intent, not an always-true invariant, and should be a skill | You want to turn a finished session's learnings *into* new rules — use `session-distill` |
| You want a per-item keep / path-scope / promote-to-skill / consolidate decision over the always-loaded surface | You want skill-to-skill overlap and split-pressure analysis — use `health-skill-audit` |
| You suspect rules duplicate plugin skills already loaded for the session | You only want frontmatter/size hygiene on existing skills — use `scripts/plugin-compliance-check.sh` |

## Context

- Current directory: !`pwd`
- CLAUDE.md files in tree: !`find . -maxdepth 3 -name 'CLAUDE.md' -not -path '*/node_modules/*' -not -path '*/.claude/worktrees/*'`
- Local rules: !`find . -path '*/.claude/rules/*' -maxdepth 3 -name '*.md' -not -path '*/.claude/worktrees/*'`
- User-global rules are resolved during execution (Step 1), not here — `$HOME` paths and error redirection are disallowed in Context commands.

## Parameters

Parse `$ARGUMENTS`:

- `scope-path` (optional, default `.`) — the directory whose `CLAUDE.md` and `.claude/rules/` are audited. Use a child path (e.g. `someplugin`) to scope the diet to one area. The user-global `~/.claude/` surface is audited too unless `scope-path` names a non-`.` project.

## Your task

Execute this audit and, on approval, migrate each candidate. **Never make a lossy or destructive edit to an always-loaded file without explicit per-candidate confirmation** — `CLAUDE.md` and rules are shared, every-turn context and a lossy edit degrades every downstream turn. Non-destructive dispositions on a large surface may be batch-approved (Step 4).

### 1. Inventory the always-loaded surface

Build the candidate list from three sources:

| Source | Path | Loaded |
|---|---|---|
| Root memory | `<scope>/CLAUDE.md` (+ nested `CLAUDE.md`) | Every turn, in full |
| Unscoped rules | `<scope>/.claude/rules/*.md` **without** a `paths:` frontmatter glob | Every turn, in full |
| Path-scoped rules | `<scope>/.claude/rules/*.md` **with** a `paths:` glob | Only when editing matching files |

When `scope-path` is `.` (or names the user-global tree), also `Glob(pattern="$HOME/.claude/rules/**/*.md")` and the root `$HOME/.claude/CLAUDE.md` during execution — that surface is the heaviest every-turn cost. The plugin-skill list already loaded for this session is in the session prompt; scan it by name when checking the **Consolidate** disposition.

For each file, record its size (`wc -c`, est. tokens ≈ chars/4 — same proxy as `skill-quality.md`) and, for `CLAUDE.md`, treat each `##` section as a separately-classifiable unit. Path-scoped rules already pay only on matching turns — flag them only if they are *also* intent-shaped (a better skill) or duplicate a loaded plugin skill.

### 2. Classify every unit against the diet rubric

For each rule file or `CLAUDE.md` section, assign exactly one disposition. The deciding question is **"must this be true on every turn regardless of what the user asked?"**

| Disposition | The unit is… | Signal |
|---|---|---|
| **Keep — hard invariant** | An always-respected constraint whose violation is a bug even when unmentioned (security boundaries, "never force-push", commit-format that drives release automation, destructive-op guards) | Imperative, unconditional, cheap to keep; the cost of *missing* it is high |
| **Keep but lean** | A hard invariant wrapped in explanation, examples, or tables that belong in a linked doc/REFERENCE | The invariant is one sentence; the file is 200 lines |
| **Path-scope** | Always-true *only when working on a specific file shape* (a language, a config format, a directory) | Advice keyed to "when editing X"; currently unscoped so it loads on every turn | 
| **Promote to skill** | A **procedure/workflow triggered by intent** — steps you run *when* doing a task, not a constraint you hold *while* doing anything | Reads as "to do X: step 1…step N"; has a clear trigger ("when releasing", "when the build fails"); rarely relevant per-turn but heavy when present |
| **Consolidate** | Duplicates another rule, a loaded plugin skill, or upstream `~/.claude/rules` | The same guidance exists elsewhere already paid for — **and that copy is current**, not a stale twin of the text being cut |
| **Drop** | Stale, obsoleted, or superseded | References removed tooling / closed migrations |

The dominant find is usually **Promote to skill**: a rule that began life as "write down this procedure so I don't forget it" but is really an intent-triggered workflow. The litmus test — *if the user never raises this topic, does the guidance still need to be in context?* If no, it is a skill.

### 3. For each promote-to-skill candidate, design the target skill

Before proposing a promotion, draft its skill home + name, an auto-triggering description, body shape, and residual stub per [references/promote-to-skill-design.md](references/promote-to-skill-design.md). No description that fires on the real intent means it is not skill-shaped.

### 4. Confirm before writing — per candidate, batch only the safe dispositions

For each candidate, present:

1. The file/section and its size (chars + est. tokens).
2. The recommended disposition with a one-sentence justification.
3. For promote-to-skill: the drafted skill home, name, and description.
4. The disposition menu via `AskUserQuestion` (Keep / Lean / Path-scope / Promote-to-skill / Consolidate / Drop / Skip).

Only proceed on explicit approval. Order the prompts by impact (largest always-loaded char count first) so the biggest wins surface early.

The confirmation shape depends on **how lossy the disposition is**, not on convenience:

| Disposition class | Confirmation | Why |
|---|---|---|
| **Non-destructive** — Keep-invariant, Keep-but-lean, Path-scope | Batchable (see below) | The guidance survives in place — leaning trims explanation, path-scoping only narrows *when* it loads. Nothing is removed from the always-loaded surface's meaning. |
| **Destructive / ambiguous** — Drop, Consolidate-that-deletes, Promote-to-skill | **One candidate, one `AskUserQuestion`** | Each removes guidance from an always-loaded file: Drop deletes it, Consolidate-that-deletes replaces it with a pointer, Promote-to-skill moves the body off the every-turn surface. A wrong call degrades every downstream turn, so the user confirms each individually. |

#### Batch-approval mode for large surfaces

At ~15+ candidates, batch only the non-destructive tier, per [references/batch-approval.md](references/batch-approval.md). Drop, Consolidate-that-deletes, and Promote-to-skill are never batched.

### 5. Execute the approved disposition

Apply each approved disposition using the per-disposition mechanics in [references/disposition-mechanics.md](references/disposition-mechanics.md). For Consolidate, **read the destination first and confirm it is current** before pointing at it.

After every write, run `git status` so the user sees exactly what changed before any commit. **Do not commit** — leave a clean tree the user can review and split. When promoting *out of* a `CLAUDE.md` or rule that lives in a chezmoi-managed tree (`~/.claude/`), surface that the source is chezmoi-managed so the edit lands in the source, not the target.

### 6. Report

Emit the final table, net every-turn saving, and next step in the format in [references/report-format.md](references/report-format.md). This skill does **not** commit.

## Anti-patterns and notes

See [references/anti-patterns.md](references/anti-patterns.md) before finalising a disposition.
