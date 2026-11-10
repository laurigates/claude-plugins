# Agentic Audit Reference

## Bare CLI Command Patterns

`--fix applies` names the one replacement `--fix` may write, and only when the flagged command is the last stage of its pipeline. A row marked "report only" has no single safe replacement (several options, a value to choose, or a format change that would flood the output), so `--fix` lists it for manual follow-up.

| Pattern | Issue | Suggested Fix | `--fix` applies |
|---------|-------|---------------|-----------------|
| `kubectl get` without `-o` flag | Verbose default table output | Add `-o wide` or `-o json` | report only |
| `kubectl describe` without `-o` | Verbose narrative output | Consider `-o json` or targeted `get` | report only |
| `helm list` without `-o json` | Text table output | Add `-o json` or `--output json` | `-o json` |
| `helm history` without `-o json` | Text table output | Add `-o json` | `-o json` |
| `helm status` without `-o json` | Text output | Add `-o json` | `-o json` |
| `cargo clippy` without `--message-format` | Verbose default output | Add `--message-format=short` | `--message-format=short` |
| `cargo test` without `--format` | Verbose default output | Add `-- --format terse` or use `cargo-nextest` | report only |
| `ruff check` without `--output-format` | Default verbose output | Add `--output-format=concise` or `github` | `--output-format=concise` |
| `docker ps` without `--format` | Verbose default table | Add `--format` with Go template | report only |
| `docker images` without `--format` | Verbose default table | Add `--format` with Go template | report only |
| `cat <file>` in context sections | Reads entire file | Use `head -N <file>` or targeted extraction | report only |
| Test commands without `--bail`/`-x` | No fail-fast | Add `--bail=1`, `-x`, or `--bail` | report only |
| `eslint` without `--format` | Verbose default output | Add `--format=unix` or `--format=stylish` | report only |
| `biome check` without `--reporter` | Verbose default output | Add `--reporter=github` | `--reporter=github` |

## Report Template

```
## Agentic Output Audit Report

### Bare CLI Commands (no compact flags)
| File | Line | Command | Suggested Fix |
|------|------|---------|---------------|
(List commands missing optimization flags)

### Context Section Issues
| File | Line | Issue | Fix |
|------|------|-------|-----|
(Context commands using cat or verbose output)

### Stale Reviews (>90 days)
| File | Last Reviewed | Days Since Review |
|------|---------------|-------------------|
(A missing `reviewed` field is listed as "never")

### CLI-Wrapper Skills Without an Agentic Optimizations Table (INFO)
| File | Dominant Tool |
|------|---------------|
(Omit this section when empty; INFO notes are not issues)

### Summary
- X skills scanned, Y commands scanned, Z agents scanned
- M bare CLI commands found
- P context section issues
- Q stale reviews
- I INFO notes (not counted as issues)
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

Read the review date with the standard extraction pattern (`.claude/rules/shell-scripting.md`):

```bash
head -50 "$file" | grep -m1 "^reviewed:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
```

An empty result means the file has no `reviewed` field.
