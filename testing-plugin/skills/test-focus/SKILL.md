---
created: 2026-01-19
modified: 2026-04-25
reviewed: 2026-04-25
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
args: "<file-path> [--serial] [--debug]"
argument-hint: "<file-path> [--serial] [--debug]"
description: |
  Run a single test file in fail-fast mode for rapid TDD iteration across
  Playwright, Vitest, Jest, pytest, cargo, or go test. Use when the user
  asks to rerun one test file, iterate quickly on a failing spec, stop at
  the first failure, run a test in headed/debug mode, or force serial
  execution for WebGL or database tests.
name: test-focus
---

## When to Use This Skill

| Use this skill when... | Use test-run instead when... |
|---|---|
| Iterating on a single failing spec with fail-fast feedback | Running the full test suite for a project |
| Forcing serial execution for WebGL or shared-state tests | Running tests in watch mode across many files (use test-quick) |
| Running one test file in headed/debug mode | Triaging a directory of test results (use test-analyze) |
| Sub-30s feedback on a known-broken file | Choosing which tier to run (use test-tier-selection) |

## Context

- Project files: !`find . -maxdepth 1 \( -name 'pyproject.toml' -o -name 'package.json' -o -name 'Cargo.toml' -o -name 'go.mod' \)`
- Playwright config: !`find . -maxdepth 1 -name 'playwright.config.*'`
- Vitest config: !`find . -maxdepth 1 \( -name 'vitest.config.*' -o -name 'vite.config.*' \)`
- Jest config: !`find . -maxdepth 1 -name 'jest.config.*'`
- Pytest config: !`find . -maxdepth 1 \( -name pyproject.toml -o -name setup.cfg \) -exec grep -l 'pytest' {} +`
- Package.json exists: !`find . -maxdepth 1 -name 'package.json' -type f`

## Parameters

- `$1` (required): Test file path or pattern (e.g., `login.spec.ts`, `tests/e2e/auth.spec.ts`)
- `--serial`: Force sequential execution with single worker (useful for WebGL, database tests)
- `--debug`: Run in debug/headed mode for visual debugging

## Your task

Run a single test file in **fail-fast mode** for rapid development iteration. Stop immediately on first failure to minimize feedback time.

### 1. Detect test framework and construct command

**Playwright** (if `playwright.config.*` exists):
```bash
# Standard fail-fast
bunx playwright test "$FILE" --max-failures=1 --reporter=line

# With --serial (WebGL, shared state)
bunx playwright test "$FILE" --max-failures=1 --workers=1 --reporter=line

# With --debug
bunx playwright test "$FILE" --max-failures=1 --headed --debug
```

**Vitest** (if `vitest.config.*` or `vite.config.*` exists):
```bash
# Standard fail-fast
bunx vitest run "$FILE" --bail=1 --reporter=dot

# With --serial
bunx vitest run "$FILE" --bail=1 --pool=forks --poolOptions.threads.singleThread --reporter=dot

# With --debug
bunx vitest run "$FILE" --bail=1 --inspect-brk
```

**Jest** (if `jest.config.*` exists):
```bash
# Standard fail-fast
bunx jest "$FILE" --bail --silent

# With --serial
bunx jest "$FILE" --bail --runInBand --silent

# With --debug
bunx jest "$FILE" --bail --runInBand
```

**pytest** (Python projects):
```bash
# Standard fail-fast
python -m pytest "$FILE" -x -v --tb=short

# With --serial (already serial by default)
python -m pytest "$FILE" -x -v --tb=short

# With --debug
python -m pytest "$FILE" -x -v --tb=long -s
```

**Cargo test** (Rust projects):
```bash
# Standard fail-fast
cargo test --test "$FILE" -- --test-threads=1

# With --debug
cargo test --test "$FILE" -- --test-threads=1 --nocapture
```

**Go test**:
```bash
# Standard fail-fast
go test -v -failfast "$FILE"

# With --debug
go test -v -failfast "$FILE" -count=1
```

### 2. Execute the test

Run the constructed command. Capture and display output.

### 3. Analyze results

If the test **passes**:
```
[FILE]: PASSED
Duration: Xs

Ready for next iteration or file.
```

If the test **fails**:
```
[FILE]: FAILED (stopped at first failure)
Duration: Xs

First failure:
  Test: [test name]
  Error: [brief error message]
  Location: [file:line]

Quick actions:
- Fix the issue and re-run: /test:focus [same file]
- Debug visually: /test:focus [file] --debug
- See full output: /test:run [file]
```

### 4. Provide rerun command

Always show the exact command to rerun:
```
Rerun: /test:focus $FILE
```

## Time savings context

Focused testing dramatically reduces feedback time:

| Approach | Typical Duration | Use Case |
|----------|------------------|----------|
| `/test:focus` | 2-30 seconds | Iterating on single file |
| `/test:quick` | 30 seconds | Unit tests after changes |
| `/test:full` | 5-30 minutes | Before commit/PR |

## Agentic optimizations

| Context | Flags |
|---------|-------|
| Playwright fast | `--max-failures=1 --reporter=line` |
| Playwright WebGL | `--max-failures=1 --workers=1 --reporter=line` |
| Vitest fast | `--bail=1 --reporter=dot` |
| Jest fast | `--bail --silent` |
| pytest fast | `-x -v --tb=short` |

## Error handling

- If file not found: List similar test files with `glob` and suggest corrections
- If framework not detected: Show available package.json scripts containing "test"
- If test times out: Suggest `--serial` flag or increasing timeout
