---
name: session-distill
description: "Distill session insights into rules, skill improvements, recipes, and cross-repo promotions to marketplace plugins. Use when capturing learnings, codifying workflow into .claude/rules, or promoting a session-invented pattern into a specific plugin/skill as a PR."
allowed-tools: Bash(git diff *), Bash(git log *), Bash(git status *), Bash(git fetch *), Bash(git switch *), Bash(git checkout *), Bash(git add *), Bash(git commit *), Bash(git branch *), Bash(git push *), Bash(just *), Bash(gh pr *), Bash(gh label *), Read, Grep, Glob, Edit, Write, AskUserQuestion, TodoWrite
argument-hint: "--rules | --skills | --recipes | --all | --dry-run"
args: "[--rules] [--skills] [--recipes] [--all] [--dry-run]"
created: 2026-02-11
modified: 2026-06-18
reviewed: 2026-02-26
---

# session-distill

Distill session insights into reusable project knowledge.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| End of session, want to capture learnings | Full end-of-session pass (wrap + distill + feedback) -> `session-plugin:session-end` |
| Discovered a project pattern worth codifying | Capturing loose threads to taskwarrior -> `session-plugin:session-wrap` |
| Want learnings as rules/recipes in *this* repo | Need to write a blog post -> `/blog:post` |
| Discovered a pattern worth reusing | Need to analyze git history for docs gaps -> `/git:log-documentation` |
| Found a CLI workflow worth saving as a recipe | Need to configure a justfile from scratch -> `/configure:justfile` |
| Want to update rules based on session experience | Need to check project infrastructure -> `/configure:status` |
| Asked to "codify the workflow" or "analyze and promote session patterns to rules" | Need a one-off implementation, not a reusable rule -> implement directly |
| A pattern is reusable **beyond this repo** and belongs in a shared plugin/skill | The learning is project-specific -> keep it in this repo's `.claude/rules` |
| The session **invented a technique** with no home skill yet, or one a named plugin's skill is missing | Reporting friction/errors for triage -> `feedback-plugin:feedback-session` (the error loop) |

May also be reached via the end-of-session flow: the plugin's Stop hook (`hooks/session-end-nudge.sh`) offers `session-plugin:session-end` once per session on user wind-down, and the orchestrator runs this skill when a durable learning qualifies.

## Core Principle: Update Over Add

Before proposing any artifact, evaluate: Does it update an existing one? Does an existing one already cover this? Is this genuinely new and reusable? See [REFERENCE.md](REFERENCE.md) for detailed evaluation criteria.

## Context

- Git repo detected: !`find . -maxdepth 1 -name '.git' -type d`
- Justfile: !`find . -maxdepth 1 \( -name 'justfile' -o -name 'Justfile' \) -print -quit`
- Rules directory: !`find . -path '*/.claude/rules/*' -name '*.md' -type f -not -path '*/.claude/worktrees/*'`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--rules` | Only analyze potential rule updates |
| `--skills` | Only analyze potential skill updates |
| `--recipes` | Only analyze potential justfile recipe updates |
| `--all` | Analyze all three categories (default) |
| `--dry-run` | Show proposals without applying changes |

## Tool Call Efficiency

Minimize LLM round-trips: batch file reads in a single response, combine evaluation and redundancy checking in one pass, complete one category before starting the next.

## Execution

Execute this session distillation workflow:

### Step 1: Analyze session activity

1. Review **conversation history** — tool calls, file edits, commands run, results
2. If in a git repo, run in parallel: `git log --oneline --max-count=20` and `git log --stat --oneline --max-count=10`
3. Identify patterns, catalog tools used, note pain points

### Step 2: Evaluate and check redundancy (single pass per category)

When `--all`: complete rules -> skills -> recipes. Do not interleave.

**Rules** (`.claude/rules/*.md`): Glob all rule files, Read ALL in one response, evaluate each insight against existing rules in one pass (update/skip/remove/merge/add).

**Skills**: Glob relevant skill files (target specific plugins from Step 1), Read in one response, evaluate in one pass.

**Recipes**: Run `just --dump --dump-format json`, evaluate session commands against loaded recipes in one pass.

### Step 3: Present proposals

Categorize as: `[UPDATE]`, `[SKIP]`, `[NEW]`, `[REDUNDANT]`, or `[PROMOTE]` with file paths and reasons.

`[PROMOTE]` is the **additive, cross-repo** category — distinct from the others,
which all write *this* repo's `.claude/`. Use it when the insight is reusable
**beyond this repo** and belongs in a marketplace plugin: either a pattern the
session invented that has **no home skill yet** (→ propose a new skill), or a
capability an **existing named skill is missing** (→ propose an edit to it). A
`[PROMOTE]` does not require anything to have gone wrong — a smooth session that
produced a strong reusable technique is exactly its trigger. Each `[PROMOTE]`
names a target `<plugin>/skills/<skill>` (new or existing) and is applied as a
**PR against the plugin repo**, never an edit to the current repo (see
[Cross-Repo Promotion](#cross-repo-promotion-promote)).

### Step 4: Apply changes

If `--dry-run`: skip this step.

**In auto mode**: apply proposals directly without per-category `AskUserQuestion`. All targets are reversible via `git restore` — rule files, skill files, and justfile recipes are tracked in git, so a wrong edit can be undone with one command. This matches auto mode's "prefer action over planning" directive. **Retain `AskUserQuestion` for destructive operations** (`[REDUNDANT]` proposals that remove a rule or recipe).

**In manual / interactive mode**: use `AskUserQuestion` to confirm each category before applying. The user can multi-select which `[UPDATE]` / `[NEW]` proposals to accept.

**In plan mode**: neither default applies — the harness disallows non-readonly tool calls (including `AskUserQuestion`-then-apply) except writes to the active plan file. Write the proposal set to the active plan file as a single coherent block (Context + per-category `[UPDATE]` / `[NEW]` / `[REDUNDANT]` sections + a brief verification section), then call `ExitPlanMode` to surface for user approval. Do not apply directly. After the user approves the plan, fall back to the auto-mode or manual-mode flow above depending on which is active.

For `[PROMOTE]` proposals, do **not** edit the current repo. Apply them via the
cross-repo PR hand-off below — gate it behind `AskUserQuestion` in every mode
(opening a PR against another repo is outward-facing), and never push to that
repo's default branch.

### Step 5: Report summary

Output concise summary of changes made, including any `[PROMOTE]` PRs opened
(with their URLs) so the promotion is traceable.

## Cross-Repo Promotion ([PROMOTE])

The other categories keep knowledge in *this* repo. `[PROMOTE]` is how a
session-invented pattern reaches the **shared plugin marketplace** so every repo
benefits — the additive complement to `feedback-plugin`'s error loop (which only
fires on friction). A near-zero-friction session can still produce several
`[PROMOTE]` candidates.

### Routing: which plugin/skill should own it

Pick the target by the pattern's domain, most specific first:

| Pattern is about… | Likely owner |
|-------------------|--------------|
| A language/tool's build/test/lint (cargo, uv, biome…) | that language plugin (`rust-plugin`, `python-plugin`, …) |
| Multi-agent orchestration, waves, worktrees, dispatch | `agent-patterns-plugin` / `workflow-orchestration-plugin` |
| Git, PRs, merges, rebases, conflicts | `git-plugin` |
| CI/infra/repo configuration | `configure-plugin` / `github-actions-plugin` |
| Nothing fits, but it's clearly reusable | propose a new skill in the closest plugin and flag the routing choice for review |

Then decide **new skill vs. edit existing**: glob the owner plugin's `skills/`,
read the closest few, and prefer extending an existing skill (a new section +
cross-link) over a new skill unless the pattern is genuinely its own topic
(`Update Over Add` still applies — across repos now).

### The PR hand-off (never edit cwd, never push to default)

The plugin source lives in its own repo (`PLUGINS_REPO` below). Open a PR there;
the human reviews and merges. Match the repo's conventions: skills are
auto-discovered (add `skills/<name>/SKILL.md` with dated frontmatter +
`user-invocable`/`allowed-tools`), update the plugin README's skill catalog,
keep `!`-context commands free of pipes/redirects, use a conventional commit
(`feat(<plugin>):` for a new skill, `docs(<plugin>):` for an edit — release-please
versions from it), and apply the `<plugin>` routing label (create it if missing).

```bash
PLUGINS_REPO="$HOME/repos/laurigates/claude-plugins"     # the plugin source repo
git -C "$PLUGINS_REPO" fetch origin
git -C "$PLUGINS_REPO" switch -c <type>/<short-slug> origin/main
# ... Write/Edit the SKILL.md + README under "$PLUGINS_REPO" (absolute paths) ...
git -C "$PLUGINS_REPO" add <paths>
git -C "$PLUGINS_REPO" commit -m "<conventional message>"
git -C "$PLUGINS_REPO" push -u origin <branch>
gh pr create -R laurigates/claude-plugins --base main --head <branch> \
  --title "<conventional title>" --body-file /tmp/promote-body.md -l <plugin>
```

The PR body should cite the session as evidence (what the pattern is, why it's
reusable, where it was used) — the additive analogue of the friction loop's
evidence summary.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Session diff summary | `git log --stat --oneline --max-count=10` |
| Recent commits | `git log --oneline --max-count=20` |
| List justfile recipes | `just --list` |
| Dump justfile as JSON | `just --dump --dump-format json` |
| Find rules | Glob `.claude/rules/*.md` |
| Batch-read all rules | Glob then Read all results in one response |
