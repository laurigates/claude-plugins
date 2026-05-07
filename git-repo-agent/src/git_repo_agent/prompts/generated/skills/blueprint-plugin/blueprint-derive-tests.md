# /blueprint:derive-tests

Analyze git history to identify fix and feature commits lacking corresponding test changes, then generate a structured Test Regression Plan (TRP) document as a prioritized test backlog.

**Use case**: Systematically close test coverage gaps by mining commit history for bug fixes and features that shipped without regression tests.


## Execution

Execute this test regression plan derivation workflow:


### Step 1: Verify prerequisites

Check context values above:

1. If git repository is empty → Error: "This directory is not a git repository. Run from project root."
2. If total commits = "0" → Error: "Repository has no commit history."
3. If Blueprint initialized is empty → Ask user: "Blueprint not initialized. Initialize now (Recommended) or continue without manifest tracking?"
   - If "Initialize now" → Use Task tool to invoke `/blueprint:init`, then continue
   - If "Continue without" → Skip manifest updates in Step 7


### Step 2: Determine analysis scope

Parse `$ARGUMENTS` for `--quick`, `--since`, and `--scope`:

1. If `--quick` → scope = last 50 commits
2. If `--since DATE` → scope = commits from DATE to now
3. If `--scope AREA` → filter commits to those with scope matching AREA or touching files in AREA directory
4. Otherwise → scope = last 200 commits

Store scope parameters for git log commands in subsequent steps.


### Step 3: Detect test infrastructure

Scan for test framework and conventions:

1. Identify test framework from context (vitest, jest, pytest, cargo test, go test)
2. Detect test file naming convention:
   - `*.test.ts`, `*.spec.ts` (JS/TS)
   - `test_*.py`, `*_test.py` (Python)
   - `*_test.rs`, `tests/` directory (Rust)
   - `*_test.go` (Go)
3. Map source directories to test directories (e.g., `src/` → `tests/`, `src/` → `src/__tests__/`)
4. Record framework, naming pattern, and directory mapping for Step 5

If no test framework detected → Warn user, continue with file-based detection only.


### Step 4: Extract and classify commits

Extract fix and feature commits within scope:

1. **Primary targets** — `fix:` commits (highest priority for regression tests):
   ```bash
   git log --format="%H %s" {scope} | grep -E "^[a-f0-9]+ fix(\(.*\))?:"
   ```

2. **Secondary targets** — `feat:` commits (should have accompanying tests):
   ```bash
   git log --format="%H %s" {scope} | grep -E "^[a-f0-9]+ feat(\(.*\))?:"
   ```

3. **Fallback** — If conventional commit percentage < 20%, use keyword detection:
   ```bash
   git log --format="%H %s" {scope} | grep -iE "(fix|bug|hotfix|patch|resolve|correct)"
   ```

For each commit, record: SHA, subject, date, files changed, scope (if conventional).


### Step 5: Analyze test coverage gaps

For each commit from Step 4, check for corresponding tests:

1. **Inline test changes** — Did the same commit modify test files?
   ```bash
   git diff-tree --no-commit-id --name-only -r {SHA} | grep -E "(test|spec|_test\.|\.test\.)"
   ```

2. **Nearby test commits** — Within 5 commits after the fix, was a test commit added?
   ```bash
   git log --format="%H %s" {SHA}..{SHA~5} | grep -iE "^[a-f0-9]+ test(\(.*\))?:|add.*test|test.*for"
   ```

3. **Test file exists** — For each modified source file, does a corresponding test file exist?
   Use the source-to-test mapping from Step 3 (see [REFERENCE.md](REFERENCE.md#test-to-source-mapping) for rules per language).

Classify each gap using the severity matrix from [REFERENCE.md](REFERENCE.md#severity-classification):

| Severity | Criteria |
|----------|----------|
| Critical | `fix:` commit, no test changes, no test file exists for modified source |
| High | `fix:` commit, no inline test changes but test file exists (test not updated) |
| Medium | `feat:` commit, no test changes, core module affected |
| Low | `feat:` commit, no inline tests but nearby test commit exists |


### Step 6: Generate TRP document

1. Create output directory: `mkdir -p docs/trps`
2. Determine TRP ID:
   - If manifest exists, read `id_registry.last_trp`, increment by 1
   - Otherwise start at `TRP-001`
3. Generate slug from scope or date range (e.g., `regression-gaps-2024-q3`)
4. Write TRP document to `docs/trps/{slug}.md` using template from [REFERENCE.md](REFERENCE.md#trp-document-template)

Include in the document:
- YAML frontmatter with `id`, `status: Active`, `scope`, `date_range`, `commits_analyzed`
- Executive summary with gap counts by severity
- Detailed gap table: commit SHA, subject, severity, affected files, suggested test type
- Recommended test creation order (Critical first, then High, etc.)
- Suggested test type per gap (see [REFERENCE.md](REFERENCE.md#suggested-test-types))


### Step 7: Update manifest

If Blueprint is initialized:

1. Update `id_registry.last_trp` with the new TRP number
2. Register the document in `id_registry.documents`:
   ```json
   {
     "TRP-NNN": {
       "path": "docs/trps/{slug}.md",
       "title": "{TRP title}",
       "status": "Active",
       "created": "{date}"
     }
   }
   ```
3. Update task registry:
   ```bash
   jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --arg sha "$(git rev-parse HEAD 2>/dev/null)" \
     --argjson analyzed "{commits_analyzed}" \
     --argjson gaps "{gaps_found}" \
     '.task_registry["derive-tests"].last_completed_at = $now |
      .task_registry["derive-tests"].last_result = "success" |
      .task_registry["derive-tests"].stats.runs_total = ((.task_registry["derive-tests"].stats.runs_total // 0) + 1) |
      .task_registry["derive-tests"].stats.items_processed = $analyzed |
      .task_registry["derive-tests"].stats.items_created = $gaps |
      .task_registry["derive-tests"].context.commits_analyzed_up_to = $sha' \
     docs/blueprint/manifest.json > tmp.json && mv tmp.json docs/blueprint/manifest.json
   ```


### Step 8: Report results and suggest next actions

Print summary:

```
Test Regression Plan Generated!

**Analysis Summary**
- Commits analyzed: {N} ({date_range})
- Fix commits found: {N}
- Feature commits found: {N}

**Coverage Gaps Found**
- Critical: {N} (fix commits with no tests at all)
- High: {N} (fix commits with stale test files)
- Medium: {N} (feature commits missing tests)
- Low: {N} (feature commits with nearby tests)

**Document**: docs/trps/{slug}.md (TRP-{NNN})

**Top Priority Gaps**
1. {commit subject} — {severity} — {affected file}
2. {commit subject} — {severity} — {affected file}
3. {commit subject} — {severity} — {affected file}
```

Prompt user for next action:

- "Create PRPs for top-priority gaps (Recommended)" — Generate PRP documents for Critical/High gaps
- "Review the TRP document" — Open the generated TRP for manual review
- "Run again with different scope" — Re-run with `--since` or `--scope`
- "Done for now" — Exit with document saved


# blueprint-derive-tests REFERENCE

Reference material for TRP document templates, severity classification, test mapping rules, and error handling.


## TRP Document Template

```markdown
---
id: TRP-{NNN}
created: {date}
modified: {date}
status: Active
scope: "{scope or 'full'}"
date_range: "{start_date} to {end_date}"
commits_analyzed: {count}
test_framework: "{framework}"
relates-to: []
github-issues: []
---


# TRP-{NNN}: {Title}

Test Regression Plan identifying coverage gaps from git history analysis.


## Executive Summary

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | {N} | Fix commits with no tests at all |
| High | {N} | Fix commits with stale/unupdated test files |
| Medium | {N} | Feature commits missing tests in core modules |
| Low | {N} | Feature commits with nearby test commits |
| **Total** | **{N}** | |

**Analysis scope**: {N} commits from {start_date} to {end_date}
**Test framework**: {framework}


## Critical Gaps

Highest priority — bug fixes shipped without any regression test.

| # | Commit | Date | Subject | Affected Files | Suggested Test |
|---|--------|------|---------|----------------|----------------|
| 1 | `{short_sha}` | {date} | {subject} | `{file}` | {test_type} |


### Gap Details

#### Gap 1: {Commit subject}

- **Commit**: {full_sha}
- **Date**: {date}
- **Files changed**: {list}
- **Why critical**: No test file exists for `{source_file}`
- **Suggested test**: Create `{test_file_path}` with regression test verifying the fix behavior
- **Test scenario**: Reproduce the bug condition, assert the fix handles it correctly


## High Gaps

Fix commits where test files exist but were not updated.

| # | Commit | Date | Subject | Test File | Suggested Action |
|---|--------|------|---------|-----------|------------------|
| 1 | `{short_sha}` | {date} | {subject} | `{test_file}` | Add regression case |


## Medium Gaps

Feature commits in core modules without accompanying tests.

| # | Commit | Date | Subject | Module | Suggested Test |
|---|--------|------|---------|--------|----------------|
| 1 | `{short_sha}` | {date} | {subject} | {module} | {test_type} |


## Low Gaps

Feature commits with nearby test coverage (within 5 commits).

| # | Commit | Date | Subject | Nearby Test | Status |
|---|--------|------|---------|-------------|--------|
| 1 | `{short_sha}` | {date} | {subject} | `{nearby_sha}` | Likely covered |


## Recommended Test Creation Order

Priority-ordered list for systematic gap closure:

1. **Critical gaps first** — Each represents a confirmed bug fix with zero test coverage
2. **High gaps second** — Test infrastructure exists, just needs a new test case
3. **Medium gaps** — New test files needed, but lower urgency than bug fixes
4. **Low gaps** — Verify existing nearby tests actually cover the behavior


## Module Coverage Summary

| Module/Scope | Fix Commits | With Tests | Gap % |
|--------------|-------------|------------|-------|
| {scope} | {N} | {N} | {N}% |

---

**Generated by**: /blueprint:derive-tests
**Analysis date**: {date}
**Commits analyzed**: {count}
```


## Test-to-Source Mapping

Rules for mapping source files to expected test file locations, by language.


### TypeScript / JavaScript

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `src/foo.ts` | `src/foo.test.ts` | `src/auth.ts` → `src/auth.test.ts` |
| `src/foo.ts` | `src/foo.spec.ts` | `src/auth.ts` → `src/auth.spec.ts` |
| `src/foo.ts` | `src/__tests__/foo.test.ts` | `src/auth.ts` → `src/__tests__/auth.test.ts` |
| `src/foo.ts` | `tests/foo.test.ts` | `src/auth.ts` → `tests/auth.test.ts` |
| `src/components/Foo.tsx` | `src/components/Foo.test.tsx` | Co-located test |
| `src/components/Foo.tsx` | `src/components/__tests__/Foo.test.tsx` | Nested `__tests__` |

**Detection order**: Check co-located first, then `__tests__/`, then `tests/` at project root.


### Python

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `src/foo.py` | `tests/test_foo.py` | `src/auth.py` → `tests/test_auth.py` |
| `src/foo.py` | `tests/foo_test.py` | `src/auth.py` → `tests/auth_test.py` |
| `src/pkg/foo.py` | `tests/pkg/test_foo.py` | Mirror directory structure |
| `foo.py` | `test_foo.py` | Same directory convention |

**Detection order**: Check `tests/test_{name}.py` first, then `tests/{name}_test.py`, then co-located.


### Rust

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `src/foo.rs` | `src/foo.rs` (inline `#[cfg(test)]`) | Check for `mod tests` block |
| `src/foo.rs` | `tests/foo.rs` | Integration tests |
| `src/lib.rs` | `tests/integration_test.rs` | Library integration tests |

**Detection order**: Check inline `#[cfg(test)]` first, then `tests/` directory.


### Go

| Source Pattern | Test Pattern | Example |
|---------------|-------------|---------|
| `foo.go` | `foo_test.go` | Co-located by convention |
| `pkg/foo.go` | `pkg/foo_test.go` | Same package |

**Detection order**: Always co-located (`{name}_test.go` next to `{name}.go`).


## Severity Classification

Matrix for classifying test coverage gaps.


### Primary Classification (Commit Type)

| Commit Type | Base Severity |
|-------------|---------------|
| `fix:` / bug-related | Critical or High |
| `feat:` / feature | Medium or Low |
| `refactor:` | Low (only if behavior changes) |
| `perf:` | Medium (performance regression risk) |


### Severity Modifiers

| Factor | Raises Severity | Lowers Severity |
|--------|----------------|-----------------|
| No test file exists for source | +1 level | — |
| Test file exists but not updated | — | -1 level |
| Core module (auth, payments, data) | +1 level | — |
| Peripheral module (docs, config) | — | -1 level |
| Recent commit (< 30 days) | +1 level (still fresh) | — |
| Old commit (> 6 months) | — | -1 level (lower urgency) |
| Nearby test commit (< 5 commits) | — | -1 level |
| Multiple files changed | +1 level (larger blast radius) | — |


### Final Severity Rules

| Base + Modifiers | Final Severity |
|------------------|----------------|
| fix + no test file | **Critical** |
| fix + test file exists but not updated | **High** |
| fix + nearby test commit | **Medium** |
| feat + core module + no tests | **Medium** |
| feat + peripheral module | **Low** |
| feat + nearby test commit | **Low** |


## Suggested Test Types

Mapping from gap type to recommended test approach.

| Gap Type | Suggested Test | Description |
|----------|---------------|-------------|
| Bug fix (Critical) | Regression unit test | Reproduce exact bug condition, verify fix |
| Bug fix (High) | Add test case to existing suite | New `it()` / `test()` in existing test file |
| Feature (Medium) | Unit + integration test | Cover new behavior and integration points |
| Feature (Low) | Verify existing coverage | Check if nearby test actually covers behavior |
| Performance fix | Benchmark test | Verify performance characteristic is maintained |
| Security fix | Security regression test | Verify vulnerability is not reintroducible |


### Test Scenario Template

For Critical gaps, suggest test scenarios:

```
Test: {descriptive name matching the fix}
Given: {precondition that triggers the original bug}
When: {action that exposed the bug}
Then: {expected behavior after the fix}
```


## Git Analysis Commands


### Extract fix commits with file changes

```bash

# Fix commits with files changed (compact)
git log --format="%H|%ai|%s" {scope} | \
  grep -E "^\w+\|.*\|fix(\(.*\))?:" | \
  while IFS='|' read sha date subject; do
    files=$(git diff-tree --no-commit-id --name-only -r "$sha" | tr '\n' ',')
    echo "$sha|$date|$subject|$files"
  done
```


### Check if commit includes test changes

```bash

# Returns non-empty if commit touches test files
git diff-tree --no-commit-id --name-only -r {SHA} | \
  grep -E "(test|spec|_test\.|\.test\.)" || true
```


### Find test files for a source file

```bash

# TypeScript/JavaScript
source_name=$(basename "$file" | sed 's/\.\(ts\|tsx\|js\|jsx\)$//')
find . -name "${source_name}.test.*" -o -name "${source_name}.spec.*" 2>/dev/null


# Python
source_name=$(basename "$file" .py)
find . -name "test_${source_name}.py" -o -name "${source_name}_test.py" 2>/dev/null


# Go
source_name=$(basename "$file" .go)
find . -name "${source_name}_test.go" 2>/dev/null
```


### Nearby test commits

```bash

# Check 5 commits after a given SHA for test-related changes
git log --format="%H %s" {SHA}~1..{SHA}~6 2>/dev/null | \
  grep -iE "test(\(.*\))?:|add.*test|test.*for" || true
```


### Scope-filtered analysis

```bash

# Filter commits by scope
git log --format="%H %s" {scope} | grep -E "^\w+ \w+\({AREA}\)"


# Filter commits by file path
git log --format="%H %s" {scope} -- "{AREA}/"
```


## Error Handling

| Condition | Action |
|-----------|--------|
| Not a git repository | Error: "This directory is not a git repository. Run from project root." |
| No commits in scope | Error: "No commits found in the specified range." |
| No test framework detected | Warn, continue with file-based detection only |
| No fix commits found | Report: "No fix commits found. Analyzing feature commits only." |
| No gaps found | Report: "All analyzed commits have corresponding tests. No TRP needed." |
| Very large scope (>1000 commits) | Suggest `--quick` or `--since` to narrow scope |
| Non-conventional commit history | Fall back to keyword detection (`fix`, `bug`, `hotfix`, `patch`) with lower confidence |
| Manifest not initialized | Skip manifest updates, warn user |
| `docs/trps/` already has TRPs | Increment ID, create new TRP (do not overwrite) |