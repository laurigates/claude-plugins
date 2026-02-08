---
model: opus
created: 2026-02-05
modified: 2026-02-05
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

## Workflow

### Phase 1: Discover Files

Find all plugin content files:

1. Skills: `find . -name 'SKILL.md' -o -name 'skill.md'`
2. Skills (all): `find . \( -name 'SKILL.md' -o -name 'skill.md' \)`
3. Agents: `find . -path '*/agents/*.md' -not -name 'README.md'`

Classify each file by type (skill, command, agent) for the report.

### Phase 2: Check for Agentic Optimizations Tables

For each **skill** file:

1. Check if it contains a heading matching `## Agentic Optimization` (with or without trailing "s")
2. Check if it contains bash/shell code blocks (`` ```bash `` or `` ```sh ``)
3. Flag skills that have bash code blocks but lack the Agentic Optimizations table

Skills without any bash code blocks are informational and can be skipped (note them in verbose mode).

### Phase 3: Check for Bare CLI Commands

Scan execution and context sections of all files for commands missing compact/machine-readable flags.

| Pattern | Issue | Suggested Fix |
|---------|-------|---------------|
| `kubectl get` without `-o` flag | Verbose default table output | Add `-o wide` or `-o json` |
| `kubectl describe` without `-o` | Verbose narrative output | Consider `-o json` or targeted `get` |
| `helm list` without `-o json` | Text table output | Add `-o json` or `--output json` |
| `helm history` without `-o json` | Text table output | Add `-o json` |
| `helm status` without `-o json` | Text output | Add `-o json` |
| `cargo clippy` without `--message-format` | Verbose default output | Add `--message-format=short` |
| `cargo test` without `--format` | Verbose default output | Add `-- --format terse` or use `cargo-nextest` |
| `ruff check` without `--output-format` | Default verbose output | Add `--output-format=concise` or `github` |
| `docker ps` without `--format` | Verbose default table | Add `--format` with Go template |
| `docker images` without `--format` | Verbose default table | Add `--format` with Go template |
| `cat <file>` in context sections | Reads entire file | Use `head -N <file>` or targeted extraction |
| Test commands without `--bail`/`-x` | No fail-fast | Add `--bail=1`, `-x`, or `--bail` |
| `eslint` without `--format` | Verbose default output | Add `--format=unix` or `--format=stylish` |
| `biome check` without `--reporter` | Verbose default output | Add `--reporter=github` |

Search for these patterns inside fenced code blocks and backtick context commands (`!` backtick syntax).

### Phase 4: Check Frontmatter Dates

For each file, extract the `modified` date from YAML frontmatter:

1. Parse `modified: YYYY-MM-DD` from the first 20 lines
2. Calculate days since modification
3. Flag files where `modified` is older than 90 days as stale

### Phase 5: Generate Report

Output a structured markdown report:

```
## Agentic Output Audit Report

### Missing Agentic Optimizations Tables
| File | Plugin | CLI Tools Detected |
|------|--------|--------------------|
(List skills with bash blocks but no table)

### Bare CLI Commands (no compact flags)
| File | Line | Command | Suggested Fix |
|------|------|---------|---------------|
(List commands missing optimization flags)

### Context Section Issues
| File | Line | Issue | Fix |
|------|------|-------|-----|
(Context commands using cat or verbose output)

### Stale Reviews (>90 days)
| File | Last Modified | Days Stale |
|------|---------------|------------|

### Summary
- X skills scanned, Y commands scanned, Z agents scanned
- N missing Agentic Optimizations tables
- M bare CLI commands found
- P context section issues
- Q stale reviews
```

If `--verbose`: also list all scanned files with their status (pass/fail per check).

### Phase 6: Apply Fixes (if --fix)

When `--fix` is passed:

1. **Add skeleton Agentic Optimizations tables** to flagged skills:
   - Insert before the last heading or at the end of the file
   - Use this template:
     ```markdown
     ## Agentic Optimizations

     | Context | Command |
     |---------|---------|
     | Quick check | `TODO: add compact command` |
     | CI mode | `TODO: add CI-friendly command` |
     | Errors only | `TODO: add errors-only command` |
     ```
   - Leave TODO entries for the user to fill in

2. **Update `modified` date** in frontmatter of each modified file to today's date

3. **Report changes**: Show which files were modified and what was added

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
