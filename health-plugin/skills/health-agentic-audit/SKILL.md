---
created: 2026-02-05
modified: 2026-11-10
compatibility: claude-code
reviewed: 2026-11-10
user-invocable: false
description: "Audit skills, commands, and agents for bare CLI commands lacking compact, fail-fast, or JSON flags, and stale reviews. Use when batch-checking skill documentation quality."
allowed-tools: Bash(find *), Bash(head *), Read, Grep, Glob, TodoWrite
args: "[--fix] [--verbose]"
argument-hint: "[--fix] [--verbose]"
name: health-agentic-audit
---

# health-agentic-audit

The user-facing entry point is `/health:check --scope=agentic`, with `--fix` to apply changes; this skill is model-invoked only (`user-invocable: false`).

Scan all plugin skills, commands, and agents for CLI commands that would flood an agent's context: commands documented without compact, fail-fast, or machine-readable flags. Also reports skills whose `reviewed` date is stale.

Standards reference: `.claude/rules/agentic-optimization.md`, `.claude/rules/skill-quality.md`, and `.claude/rules/context-engineering.md` § Supersedes. The "Agentic Optimizations" table is **optional** under those rules: keep it only where the commands are the payload (CLI-wrapper skills). This audit never asks for one elsewhere and never inserts one.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Finding bare CLI commands in skill docs | Plugin relevance to the project stack (`/health:check --scope=stack`) |
| Finding skills whose `reviewed` date is stale | Comprehensive environment check (use `/health:check`) |
| Quality-checking skill documentation in batch | Plugin registry issues (`/health:check --scope=registry`) |
| | Skill overlap or split pressure (use `/health:skill-audit`) |

## Context

- Plugin root: !`pwd`
- Skill files: !`find . -path ./.claude/worktrees -prune -o \( -name 'SKILL.md' -o -name 'skill.md' \) -print`
- Agent files: !`find . -path ./.claude/worktrees -prune -o -path '*/agents/*.md' -not -name 'README.md' -print`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Apply the single replacement flag that [REFERENCE.md](REFERENCE.md) names for a bare CLI command, after confirmation, and update `modified` on each edited file. Never inserts tables or placeholder rows |
| `--verbose` | Show all scanned files and detailed pattern matching results |

## Execution

Execute this agentic output audit:

### Step 1: Discover all plugin content files

Use the Context file lists (worktrees are pruned; each agent worktree is a full repo clone). Classify each file by type (skill, command, agent) for the report.

### Step 2: Scan for bare CLI commands missing compact flags

This is the audit's primary finding. Read the execution and context sections of every file and match the commands against the Bare CLI Command Patterns table in [REFERENCE.md](REFERENCE.md). A command is a finding when it lacks the compact, fail-fast, or machine-readable flag its row names.

Match only commands the reader is told to run: fenced shell blocks and `` !`…` `` context commands. Prose that quotes a command as an anti-pattern is not a finding. Context commands that read a whole file (`cat <file>`) go in the Context Section Issues list.

### Step 3: Note CLI-wrapper skills without an Agentic Optimizations table (INFO)

A missing table is at most an **INFO** note, and only for a CLI-wrapper skill: one whose commands are the payload, meaning at least half of its fenced shell commands start with the same tool and that tool is named in the skill's `name` or `description`. Every other skill without a table passes this step silently. INFO notes never count towards the issue total and `--fix` never acts on them.

### Step 4: Check `reviewed` dates for staleness

For each skill, read the `reviewed` field from the YAML frontmatter, using the extraction pattern in [REFERENCE.md](REFERENCE.md). `reviewed` records when the content was last verified against current docs; `modified` records the last edit and says nothing about review.

1. Flag `reviewed` older than 90 days as a stale review
2. Flag a missing `reviewed` field as never reviewed
3. Leave `modified` out of this check

### Step 5: Generate the audit report

Output the report template from [REFERENCE.md](REFERENCE.md):

1. **Bare CLI Commands**: file, line, command, and suggested fix
2. **Context Section Issues**: context commands using `cat` or verbose output
3. **Stale Reviews (>90 days)**: files with an old or missing `reviewed` date
4. **CLI-Wrapper Skills Without an Agentic Optimizations Table (INFO)**: Step 3's notes, if any
5. **Summary**: counts of skills/commands/agents scanned and issues found (INFO notes listed separately)

If `--verbose`: also list all scanned files with their status (pass/fail per check).

### Step 6: Apply fixes (if --fix)

When `--fix` is passed:

1. Collect the Bare CLI Commands findings whose REFERENCE.md row gives a replacement in its `--fix applies` column and whose command is the last stage of its pipeline (no `|` after it, so a downstream parser still gets the format it expects). Every other finding stays report-only.
2. Show the planned edits (file, line, old command, new command) and confirm them with `AskUserQuestion` before writing.
3. Apply the confirmed edits and set `modified` to today's date in each edited file. Leave `reviewed` unchanged: a flag edit is not a review.
4. Report which files changed and list the report-only findings for manual follow-up.

`--fix` changes no other content: no Agentic Optimizations tables, no placeholder rows, no date-only edits on files it did not otherwise change.

## See Also

- `/health:check` - Full diagnostic scan
- `health-plugin:health-audit` - Plugin relevance audit (user path: `/health:check --scope=stack`)
- `.claude/rules/agentic-optimization.md` - Optimization standards
- `.claude/rules/context-engineering.md` - Why the Agentic Optimizations table is optional
