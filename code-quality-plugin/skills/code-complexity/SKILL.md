---
name: code-complexity
description: Analyze code complexity metrics (cyclomatic, cognitive, function length, coupling). Use when identifying refactoring targets, tracking codebase health, or reviewing large changes.
args: "[PATH] [--threshold <number>] [--format <summary|detailed|json>]"
argument-hint: path or directory to analyze for complexity
allowed-tools: Bash(npx *), Bash(radon *), Bash(cargo *), Bash(lizard *), Read, Grep, Glob, TodoWrite
model: opus
created: 2026-04-10
modified: 2026-07-06
reviewed: 2026-07-06
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

## Metric Computation: Offload, Never Count By Hand

Complexity metrics (cyclomatic complexity, NLOC, parameter count, function
length, nesting depth) are **computed by a tool**, never by eyeballing function
boundaries or counting branches by hand. Hand-counting is token-hungry,
irreproducible run-to-run, and exactly the mechanical work that belongs in a
deterministic substrate.

- **Language-native fast paths** (use when the project already has them
  configured): `radon` for Python, `cargo clippy` for Rust, the ESLint
  `complexity` rule for JS/TS when an ESLint config exists.
- **`lizard` — the uniform fallback for every language.** One tool computes
  cyclomatic complexity (CCN), NLOC, parameter count (PARAM), function length,
  and nesting depth (ND) across JS/TS/Go/Python/Rust/C/C++/Java with
  machine-readable output. It is the deterministic answer wherever a
  language-native tool is absent — always the JS/TS and Go path when ESLint
  complexity isn't configured.

### Install lizard (tool-installation priority)

```bash
uv tool install lizard
```

Alternative: `mise use -g pipx:lizard` (mise `pipx:` backend, runs via uvx).

## Execution

Execute this complexity analysis:

### Step 1: Detect project language and available tools

Check for language-specific complexity tools, falling back to `lizard`:

- **JavaScript/TypeScript**: use the ESLint `complexity` rule when an ESLint
  config is present; otherwise use `lizard`.
- **Python**: use `radon` (cyclomatic + maintainability index); `lizard` is a
  fallback if `radon` is unavailable.
- **Rust**: use `cargo clippy` cognitive-complexity warnings; `lizard` is a
  fallback.
- **Go**: use `lizard`.
- **Any other language / no native tool**: use `lizard`.

Confirm `lizard` is installed (`uv tool install lizard`) before using the
fallback path.

### Step 2: Measure function-level complexity

**JavaScript/TypeScript (ESLint complexity rule, when configured):**

```bash
npx eslint --rule '{"complexity":["warn",1]}' --format json .
```

**JavaScript/TypeScript, Go, or any language without a native tool (lizard):**

```bash
# Warnings only — one line per function exceeding the CCN threshold
lizard -C 10 --warnings_only .

# Full machine-readable metrics for every function (CSV)
lizard --csv .
```

`lizard` emits, per function: NLOC, CCN (cyclomatic complexity), token count,
PARAM (parameter count), length, and ND (nesting depth) — the complete metric
set, so no branch counting or line counting is done by hand. Restrict to a
language when needed with `-l js`, `-l typescript`, `-l go`, etc. The
`--warnings_only` run exits non-zero when any function exceeds the threshold.

**CSV column order** (for `lizard --csv`): `NLOC, CCN, token, PARAM, length,
location, file, function, long_name, start_line, end_line`.

**Python (Radon):**
```bash
radon cc ${1:-.} -s -a --min B
radon mi ${1:-.} -s
```

**Rust:**
```bash
cargo clippy -- -W clippy::cognitive_complexity
```

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

The `lizard` default (non-CSV) run already prints per-file NLOC, average NLOC,
average CCN, average token count, and function count — use it for the file-level
roll-up.

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
- If complexity tools not installed → suggest `uv tool install lizard` (uniform, all languages) or `pip install radon` (Python)
- If setting up complexity budgets → suggest adding ESLint complexity rule via `/configure:linting`

## Agentic Optimizations

| Context | Command |
|---|---|
| Uniform CCN warnings (all languages) | `lizard -C 10 --warnings_only .` |
| Uniform full metrics (machine-readable) | `lizard --csv .` |
| JS/TS only via lizard | `lizard -l javascript -l typescript -C 10 --warnings_only .` |
| Go only via lizard | `lizard -l go -C 10 --warnings_only .` |
| Python cyclomatic | `radon cc . -s -a --min B -j` |
| Python maintainability | `radon mi . -s -j` |
| JS/TS complexity (ESLint, when configured) | `npx eslint --rule '{"complexity":["warn",1]}' --format json .` |
| Rust cognitive | `cargo clippy -- -W clippy::cognitive_complexity 2>&1` |
