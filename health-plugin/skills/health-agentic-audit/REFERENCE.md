# Agentic Audit Reference

## Bare CLI Command Patterns

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

## Report Template

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

## Skeleton Agentic Optimizations Table

Use this template when adding tables to flagged skills via `--fix`:

```markdown
## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `TODO: add compact command` |
| CI mode | `TODO: add CI-friendly command` |
| Errors only | `TODO: add errors-only command` |
```

## Code Block Detection

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

## Frontmatter Extraction

Use the standard extraction pattern:
```bash
head -20 "$file" | grep -m1 "^modified:" | sed 's/^[^:]*:[[:space:]]*//'
```
