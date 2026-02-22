---
model: sonnet
created: 2026-02-22
modified: 2026-02-22
reviewed: 2026-02-22
description: "Derive test regression plans from git history by identifying fix and feature commits lacking corresponding tests. Use when you need to find untested bug fixes, coverage gaps, or generate a test backlog from commit analysis."
args: "[--since DATE] [--quick] [--scope AREA]"
argument-hint: "--since 2024-06-01 for date range, --quick for last 50, --scope auth for specific area"
allowed-tools: Read, Write, Glob, Grep, Bash, AskUserQuestion, Task
name: blueprint-derive-tests
---

# /blueprint:derive-tests

Analyze git history to identify fix and feature commits lacking corresponding test changes, then generate a structured Test Regression Plan (TRP) document as a prioritized test backlog.

**Use case**: Systematically close test coverage gaps by mining commit history for bug fixes and features that shipped without regression tests.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|-------------------------|
| Bug fixes ship without regression tests | You need to run existing tests (`/test:run`) |
| Want a prioritized test backlog from history | Writing tests for a specific feature (manual TDD) |
| Onboarding a project and assessing test health | Checking current test coverage metrics |
| Need to find which fixes lack test coverage | Designing a test strategy from scratch (`/test:architecture`) |

## Context

- Git repository: !`git rev-parse --git-dir 2>/dev/null`
- Blueprint initialized: !`test -f docs/blueprint/manifest.json 2>/dev/null`
- Total commits: !`git rev-list --count HEAD 2>/dev/null`
- Test framework: !`find . -maxdepth 3 \( -name 'vitest.config.*' -o -name 'jest.config.*' -o -name 'pytest.ini' -o -name 'pyproject.toml' -o -name 'Cargo.toml' -o -name 'go.mod' \) -type f -print -quit 2>/dev/null`
- Test files: !`find . -maxdepth 4 -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*' -o -name '*_test.*' \) -print 2>/dev/null`
- Conventional commits sample: !`git log --format="%s" -n 10 2>/dev/null`

## Parameters

Parse these from `$ARGUMENTS`:

- `--quick`: Fast scan (last 50 commits only)
- `--since DATE`: Analyze commits from specific date (e.g., `--since 2024-06-01`)
- `--scope AREA`: Filter to commits touching a specific area/scope (e.g., `--scope auth`)

Default behavior without flags: Analyze last 200 commits.

For detailed templates, severity matrix, and test mapping rules, see [REFERENCE.md](REFERENCE.md).

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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Fix commits only | `git log --format="%H %s" \| grep -E "^[a-f0-9]+ fix"` |
| Check test in commit | `git diff-tree --no-commit-id --name-only -r {SHA} \| grep -E "test\|spec"` |
| Files changed | `git diff-tree --no-commit-id --name-only -r {SHA}` |
| Fast scan | Use `--quick` for last 50 commits |
| Scope filter | Use `--scope auth` to limit to specific area |

---

For detailed templates, severity classification matrix, test mapping rules, and error handling, see [REFERENCE.md](REFERENCE.md).
