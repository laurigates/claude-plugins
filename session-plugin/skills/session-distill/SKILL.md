---
name: session-distill
description: "This session's durable learnings, each routed to one home: a rule, recipe, local skill, or plugin PR. Use when a session taught something worth keeping, or asked to distill or codify it."
allowed-tools: Bash(bash *), Bash(mkdir *), Bash(mktemp *), Bash(git diff *), Bash(git log *), Bash(git status *), Bash(git fetch *), Bash(git clone *), Bash(git switch *), Bash(git checkout *), Bash(git add *), Bash(git commit *), Bash(git branch *), Bash(git push *), Bash(just *), Bash(gh pr *), Bash(gh label *), Read, Grep, Glob, Edit, Write, AskUserQuestion, TodoWrite
argument-hint: "--rules | --skills | --recipes | --process | --all | --dry-run"
args: "[--rules] [--skills] [--recipes] [--process] [--all] [--dry-run]"
created: 2026-02-11
modified: 2026-09-23
reviewed: 2026-07-14
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

Reached via the end-of-session flow: [references/auto-surfacing.md](references/auto-surfacing.md).

## Core Principle: Update Over Add

Before proposing any artifact, evaluate: Does it update an existing one? Does an existing one already cover this? Is this genuinely new and reusable? See [REFERENCE.md](REFERENCE.md) for detailed evaluation criteria.

## Context

- Git repo detected: !`find . -maxdepth 1 -name '.git' -type d`
- Justfile: !`find . -maxdepth 1 \( -name 'justfile' -o -name 'Justfile' \) -print -quit`
- Rules directory: !`find . -path '*/.claude/rules/*' -name '*.md' -type f -not -path '*/.claude/worktrees/*'`

Harnesses that don't execute `` !`…` `` context commands show these lines as
text; in that case run the three `find` commands yourself before Step 1.

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--rules` | Only analyze potential rule updates |
| `--skills` | Only analyze potential skill updates |
| `--recipes` | Only analyze potential justfile recipe updates |
| `--process` | Only analyze potential process/methodology captures (script+recipe or project-local `.claude/skills/` skill) |
| `--all` | Analyze all categories (default) |
| `--dry-run` | Show proposals without applying changes |

## Tool Call Efficiency

Minimize LLM round-trips: batch file reads in a single response, combine evaluation and redundancy checking in one pass, complete one category before starting the next.

## Execution

Execute this session distillation workflow:

### Step 1: Run the distill collector, then read conversation for rules

Run the read-only collector — the distill-side analogue of `session-survey.sh`.
It mines this session's transcript (and the cross-session window) for the
mechanical signals, so you don't re-read the whole conversation for
commands/edits or re-run `just --dump` from memory:

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/distill-survey.sh" \
  --session-id "${CLAUDE_SESSION_ID}" --window-sessions 10
```

Consume the digest (`RECIPE_CANDIDATES`, `HOT_FILES`, `COMMIT_INTERVALS` +
`COMMAND_DIGEST`, `RULE_HINTS_FROM_TOOLING`); field meanings and the pi fallback:
[references/collector-digest.md](references/collector-digest.md).

When `TRANSCRIPT_AVAILABLE=false` / `STATUS=SKIP` (fresh clone, remote sandbox,
mid-conversation flush, or no `--session-id`), fall back to reading the
conversation history directly for commands and edits.

**Durable rules live in conversation *reasoning*, not `tool_use` mining.** For
the rules category always read the conversation's decisions, corrections, and
constraints yourself — the collector deliberately does not pre-compute rules
beyond the narrow `RULE_HINTS_FROM_TOOLING` denial signal.

### Step 2: Evaluate and check redundancy (single pass per category)

When `--all`: complete rules -> skills -> recipes/process. Do not interleave.

**Rules** (`.claude/rules/*.md`): from the conversation reasoning (plus any
`RULE_HINTS_FROM_TOOLING` signal), Glob rule files and Read only the *subset*
the learning touches — the `HOT_FILES` paths and the rules adjacent to them —
then evaluate each insight in one pass (update/skip/remove/merge/add). Do not
glob-read every rule when the collector already narrowed the surface.

**Skills**: Glob relevant skill files (target specific plugins from Step 1),
Read in one response, evaluate in one pass.

**Recipes / process**: the collector already ran `just --dump`, so
`RECIPE_CANDIDATES` are already novel (not existing recipes). Route each per the
[destination table](references/routing.md) — a recurring single
command → a `just` recipe; a multi-step workflow → a script or a project-local
skill (see `--process`).

### Step 3: Present proposals

Categorize as: `[UPDATE]`, `[SKIP]`, `[NEW]`, `[REDUNDANT]`, or `[PROMOTE]` with file paths and reasons.

`[PROMOTE]` is the additive, cross-repo category: it targets a marketplace
plugin and is applied as a PR, never an edit to the current repo. When it
applies is in [references/promote.md](references/promote.md#when-to-promote).

### Step 4: Apply changes

If `--dry-run`: skip this step.

Apply per the active permission mode — auto mode applies directly but **retains
`AskUserQuestion` for destructive `[REDUNDANT]` removals**; manual mode confirms
each category with `AskUserQuestion`; plan mode writes the proposals to the plan
file and calls `ExitPlanMode`. The full per-mode rules are in
[references/apply-modes.md](references/apply-modes.md).

For `[PROMOTE]` proposals, do **not** edit the current repo. Apply them via the
cross-repo PR hand-off below — gate it behind `AskUserQuestion` in every mode
(opening a PR against another repo is outward-facing), and never push to that
repo's default branch.

### Step 5: Report summary

Output concise summary of changes made, including any `[PROMOTE]` PRs opened
(with their URLs) so the promotion is traceable.

## Routing a learning to a destination

Each surviving insight goes to exactly one home (rule, `just` recipe, script +
recipe, project-local `.claude/skills/` skill, or `[PROMOTE]` PR); table and
`--process` split: [references/routing.md](references/routing.md).

## Cross-Repo Promotion ([PROMOTE])

### Routing: which plugin/skill should own it

Owner-by-domain table and new-vs-edit rule:
[references/promote.md](references/promote.md#routing-which-pluginskill-should-own-it).

### The PR hand-off (isolated clone — never edit cwd, never push to default)

The plugin source lives in its own repo; open a PR there and match its
conventions — listed in [references/promote.md](references/promote.md#plugin-repo-conventions).

**Do the whole promote in a throwaway clone, never in a long-lived local
checkout of the plugins repo.** A concurrent session can move `HEAD` under a shared
checkout and silently drop the edit (issue #2113 — see
[references/promote.md](references/promote.md#why-a-throwaway-clone-issue-2113)). `git worktree add` is **not** equivalent — it
registers in the shared checkout's `.git` and was itself observed failing
(`already used by worktree`) once `HEAD` had moved.

```bash
WORK=$(mktemp -d); test -n "$WORK" || exit 1
git clone --depth 1 --single-branch --branch main https://github.com/laurigates/claude-plugins.git "$WORK/claude-plugins"
git -C "$WORK/claude-plugins" switch -c <type>/<short-slug>
# ... Write/Edit the SKILL.md + README under "$WORK/claude-plugins" (absolute paths) ...
git -C "$WORK/claude-plugins" add <paths>
git -C "$WORK/claude-plugins" commit -m "<conventional message>"
git -C "$WORK/claude-plugins" log --oneline origin/main..HEAD
git -C "$WORK/claude-plugins" push -u origin <branch>
gh pr create -R laurigates/claude-plugins --base main --head <branch> --title "<conventional title>" --body-file /tmp/promote-body.md -l <plugin>
rm -rf "$WORK"
```

Remove the throwaway (`rm -rf "$WORK"`) only after the PR URL is in hand — it is
the only copy of the work until the push lands.

Cross-references for the shared-checkout hazard this avoids:
`repos/.claude/rules/shared-checkout-branch-isolation.md` (the
`git log --oneline origin/main..HEAD` verification above — a branch must contain
only your own commits before you push), `repos/.claude/rules/concurrent-session-pr-check.md`
(before recreating work that "vanished", check whether a peer session already
opened a PR for it — never pop a shared stash), and `git-plugin:git-coworker-check`
(run it before any operation that genuinely must touch a shared checkout).

Write the PR body per [references/promote.md](references/promote.md#pr-body).

## Agentic Optimizations

Command forms for the collector, git history, and justfile/rule discovery are in
[references/commands.md](references/commands.md).
