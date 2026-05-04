---
name: code-complexity
description: |
  Analyze code complexity metrics — cyclomatic complexity, cognitive complexity,
  function length, and file-level coupling. Use when identifying refactoring
  targets, tracking codebase health over time, or reviewing large changes.
args: "[PATH] [--threshold <number>] [--format <summary|detailed|json>]"
argument-hint: path or directory to analyze for complexity
allowed-tools: Bash(npx *), Bash(radon *), Bash(cargo *), Read, Grep, Glob, TodoWrite
model: opus
created: 2026-04-10
modified: 2026-05-04
reviewed: 2026-04-10
---

# /code:complexity

Measure and report code complexity metrics.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Identifying refactoring targets by complexity | Looking for specific anti-patterns → /code:antipatterns |
| Tracking codebase health trends | Doing full code review → /code:review |
| Reviewing large PRs for complexity hotspots | Finding duplicated code → /code:dry-consolidation |
| Setting complexity budgets for the team | Configuring linting rules → /configure:linting |

## Context

- Source files: !`find . -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.rs" -o -name "*.go" \) -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" -not -path "*/build/*"`
- Package files: !`find . -maxdepth 1 \( -name "package.json" -o -name "pyproject.toml" -o -name "Cargo.toml" -o -name "go.mod" \) -type f`

## Parameters

- `$1`: Path to analyze (defaults to current directory)
- `--threshold`: Complexity threshold for flagging (default: 10)
- `--format`: Output format — `summary` (default), `detailed`, `json`

## Execution

Execute this complexity analysis:

### Step 1: Detect project language and available tools

Check for language-specific complexity tools:
- JavaScript/TypeScript: Check for `eslint` with complexity rule, or use manual AST analysis
- Python: Check for `radon` (cyclomatic + maintainability index)
- Rust: Use `cargo clippy` cognitive complexity warnings
- Go: Use manual function length analysis

### Step 2: Measure function-level complexity

**JavaScript/TypeScript:**

Analyze files for:
- Cyclomatic complexity via ESLint: `npx eslint --rule '{"complexity": ["warn", 1]}' --format json`
- Function length (count lines between function boundaries)
- Nesting depth (count nested blocks)

**Python (Radon):**
```bash
radon cc ${1:-.} -s -a --min B
radon mi ${1:-.} -s
```

**Rust:**
```bash
cargo clippy -- -W clippy::cognitive_complexity
```

**Manual analysis (all languages):**

When dedicated tools are unavailable, scan source files directly:
1. Count function/method definitions
2. Measure lines per function
3. Count control flow branches (if/else/switch/match/for/while)
4. Measure nesting depth

### Step 3: Identify hotspots

Rank files and functions by complexity. Flag items exceeding the threshold:

| Metric | Green | Yellow | Red |
|---|---|---|---|
| Cyclomatic complexity | 1-5 | 6-10 | 11+ |
| Cognitive complexity | 1-8 | 9-15 | 16+ |
| Function length (lines) | 1-25 | 26-50 | 51+ |
| Nesting depth | 1-3 | 4 | 5+ |
| Parameters per function | 1-3 | 4-5 | 6+ |

### Step 4: Calculate file-level metrics

For each source file:
- Total functions/methods
- Average complexity per function
- Maximum complexity function
- Lines of code vs lines of logic
- Import/dependency count (coupling indicator)

### Step 5: Report results

```
Complexity Report
=================
Files analyzed: N
Functions analyzed: N
Average complexity: X.X

Hotspots (complexity > threshold):
  File                          | Function        | CC  | Lines | Depth
  src/auth/handler.ts           | validateToken   | 15  | 82    | 6
  src/api/router.ts             | handleRequest   | 12  | 64    | 5

Distribution:
  Low (1-5):    NN% of functions
  Medium (6-10): NN% of functions
  High (11+):   NN% of functions

Recommendations:
1. [file:function] Extract nested conditions into helper functions
2. [file:function] Split into smaller focused functions
3. [file:function] Replace switch with strategy pattern
```

## Post-Actions

- If many high-complexity functions → suggest `/code:refactor` for the worst offenders
- If complexity tools not installed → suggest `pip install radon` or equivalent
- If setting up complexity budgets → suggest adding ESLint complexity rule via `/configure:linting`

## Agentic Optimizations

| Context | Command |
|---|---|
| Python cyclomatic | `radon cc . -s -a --min B -j` |
| Python maintainability | `radon mi . -s -j` |
| JS/TS complexity | `npx eslint --rule '{"complexity":["warn",1]}' --format json .` |
| Rust cognitive | `cargo clippy -- -W clippy::cognitive_complexity 2>&1` |
| Quick file length scan | Glob for source files, Read and count function lengths |
