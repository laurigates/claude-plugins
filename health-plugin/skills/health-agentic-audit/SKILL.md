---
model: opus
created: 2026-02-05
modified: 2026-02-10
reviewed: 2026-02-08
description: Audit skills and agents for agentic output optimization (missing compact/JSON flags, missing Agentic Optimizations tables)
allowed-tools: Bash(find *), Bash(head *), Read, Grep, Glob, TodoWrite
argument-hint: "[--fix] [--verbose]"
name: health-agentic-audit
---

# /health:agentic-audit

Scan all plugin skills, commands, and agents for CLI output optimization opportunities. Checks for missing Agentic Optimizations tables, bare CLI commands without compact flags, and stale review dates.

Standards reference: `.claude/rules/agentic-optimization.md` and `.claude/rules/skill-quality.md`.

## Context

- Plugin root: !`pwd`
- Skill files: !`find . -name 'SKILL.md' -o -name 'skill.md' 2>/dev/null`
- Skill files (all): !`find . \( -name 'SKILL.md' -o -name 'skill.md' \) 2>/dev/null`
- Agent files: !`find . -path '*/agents/*.md' -not -name 'README.md' 2>/dev/null`

## Parameters

| Parameter | Description |
|-----------|-------------|
| `--fix` | Add skeleton Agentic Optimizations tables to flagged skills and update `modified` dates |
| `--verbose` | Show all scanned files and detailed pattern matching results |

## Execution

Execute this agentic output audit:

### Step 1: Discover all plugin content files

Find all skills, commands, and agents in the codebase:

1. Scan for skills: `find . -name 'SKILL.md' -o -name 'skill.md'`
2. Scan for all skill variants: `find . \( -name 'SKILL.md' -o -name 'skill.md' \)`
3. Scan for agents: `find . -path '*/agents/*.md' -not -name 'README.md'`

Classify each file by type (skill, command, agent) for the report.

### Step 2: Check each skill for Agentic Optimizations tables

For each **skill** file:

1. Search for a heading matching `## Agentic Optimization` (with or without trailing "s")
2. Search for bash/shell code blocks (`` ```bash `` or `` ```sh ``)
3. Flag skills that have bash code blocks but lack the Agentic Optimizations table

Skip skills without any bash code blocks (informational skills). Note them in verbose mode.

### Step 3: Scan for bare CLI commands missing compact flags

Read execution and context sections of all files. Match commands against the bare CLI patterns in [REFERENCE.md](REFERENCE.md).

Search for these patterns inside fenced code blocks and backtick context commands (`!` backtick syntax).

### Step 4: Check frontmatter dates for staleness

For each file, extract the `modified` date from YAML frontmatter:

1. Parse `modified: YYYY-MM-DD` from the first 20 lines
2. Calculate days since modification
3. Flag files where `modified` is older than 90 days as stale

### Step 5: Generate the audit report

Output a structured markdown report with these sections:

1. **Missing Agentic Optimizations Tables** — list skills with bash blocks but no table
2. **Bare CLI Commands** — list commands missing optimization flags with file, line, command, and suggested fix
3. **Context Section Issues** — context commands using cat or verbose output
4. **Stale Reviews (>90 days)** — files with outdated `modified` dates
5. **Summary** — total counts for skills/commands/agents scanned and issues found

If `--verbose`: also list all scanned files with their status (pass/fail per check).

### Step 6: Apply fixes (if --fix)

When `--fix` is passed:

1. Add skeleton Agentic Optimizations tables to flagged skills (insert before the last heading or at end of file). Use the skeleton template from [REFERENCE.md](REFERENCE.md). Leave TODO entries for the user to fill in.
2. Update `modified` date in frontmatter of each modified file to today's date
3. Report which files were modified and what was added

Prompt the user to fill in the TODO entries with actual optimized commands.

## Pattern Detection Details

### Code Block Detection

Match fenced code blocks to identify CLI tools:

```
```bash
<command>
```
```

And inline backtick commands in context sections:

```
- Label: !`<command>`
```

### Frontmatter Extraction

Use the standard extraction pattern:
```bash
head -20 "$file" | grep -m1 "^modified:" | sed 's/^[^:]*:[[:space:]]*//'
```

## See Also

- `/health:check` - Full diagnostic scan
- `/health:audit` - Plugin relevance audit
- `.claude/rules/agentic-optimization.md` - Optimization standards
- `.claude/rules/skill-quality.md` - Required skill sections
