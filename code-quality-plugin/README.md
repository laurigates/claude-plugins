# Code Quality Plugin

Code review, refactoring, linting, anti-pattern detection, and static analysis for Claude Code.

## Overview

This plugin provides comprehensive code quality tools including automated code review, refactoring assistance, linting, anti-pattern detection, dependency auditing, test quality analysis, and complexity metrics using ast-grep for structural analysis.

## Skills

| Skill | Description |
|-------|-------------|
| `/code:review` | Comprehensive code review with automated fixes |
| `/code:refactor` | Refactor code applying functional programming principles - pure functions, immutability, and composition |
| `/code:antipatterns` | Analyze codebase for anti-patterns and code smells using ast-grep |
| `/code:lint` | Universal linter - auto-detects and runs appropriate linting tools |
| `/code:lint-fix` | Cross-language linter autofix commands and common fix patterns |
| `/code:dry-consolidation` | Find and extract duplicated code into shared, tested abstractions |
| `/code:docs-quality` | Analyze documentation quality - PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ |
| `/code:silent-degradation` | Detect silent degradation patterns where operations succeed with zero results |
| `/code:error-swallowing` | Detect syntactic error swallowing (empty catch, `\|\| true`, `2>/dev/null`, floating promises, ignored Go/Rust errors) with context-aware surfacing recommendations |
| `/code:dead-code` | Detect dead code, unused exports, unreachable branches, and orphaned files |
| `/code:dep-audit` | Audit dependencies for security vulnerabilities, outdated packages, and license compliance |
| `/code:test-quality` | Analyze test suite quality — detect test smells, empty assertions, flaky patterns |
| `/code:complexity` | Analyze code complexity metrics — cyclomatic, cognitive, function length, coupling |
| `code-antipatterns-analysis` | Detect anti-patterns and code smells using ast-grep structural matching |
| `ast-grep-search` | AST-based code search for structural pattern matching |

## Agents

| Agent | Description |
|-------|-------------|
| `code-review` | Code quality, architecture, and performance analysis |
| `code-refactoring` | Functional refactoring - pure functions, immutability, and composition |
| `code-analysis` | Structural code analysis and pattern detection |
| `linter-fixer` | Automatic linting and code formatting |
| `security-audit` | Security analysis and vulnerability assessment |

## Usage Examples

### Code Review

```bash
/code:review src/
```

Performs comprehensive code review including:
- Code quality analysis
- Security assessment
- Performance evaluation
- Maintainability review

### Anti-Pattern Detection

```bash
/code:antipatterns --focus security --severity high
```

Scans for anti-patterns using ast-grep structural matching:
- Code smells
- Security vulnerabilities
- Performance issues
- Maintainability problems

### Refactoring

```bash
/code:refactor src/components/
```

Refactors code applying functional programming principles:
- Pure functions (separate computation from side effects)
- Immutability (transform data, don't mutate it)
- Composition (build from small, focused functions)
- Higher-order functions (map/filter/reduce over loops)
- Explicit effects (push I/O to the boundary)

### DRY Consolidation

```bash
/code:dry-consolidation src/components/
```

Finds and extracts duplicated code into shared abstractions:
- Utility functions (string helpers, formatters, validators)
- UI components (dialogs, pagination, error states)
- Custom hooks (delete confirmation, form state, mutations)
- Runs tests and verification after all extractions

### Universal Linting

```bash
/code:lint --fix
```

Auto-detects project type and runs appropriate linters:
- Biome/ESLint for JavaScript/TypeScript
- Ruff for Python
- Clippy for Rust

### Linter Autofix

```bash
/code:lint-fix
```

Cross-language autofix with detect-and-fix script:
- Biome, ESLint, Prettier for JS/TS
- Ruff for Python
- Clippy, rustfmt for Rust

### Documentation Quality Check

```bash
/code:docs-quality
```

Analyzes documentation quality and standards:
- CLAUDE.md structure and completeness
- .claude/rules/ organization
- ADRs (Architecture Decision Records)
- PRDs (Product Requirements Documents)
- PRPs (Product Requirement Prompts)
- Freshness and git history alignment
- Generates comprehensive quality report with actionable recommendations

### Silent Degradation Scan

```bash
/code:silent-degradation src/
```

Detects patterns where code silently degrades:
- Missing config causing features to skip without warning
- Success banners shown when nothing actually ran
- Multi-step operations that silently skip steps
- Missing precondition validation for data-dependent features
- Degraded mode without user notification

```bash
/code:silent-degradation src/ --fix
```

Applies fixes: adds precondition checks, warning messages, and status indicators.

### Error-Swallowing Scan

```bash
/code:error-swallowing src/ --severity high
```

Detects and classifies syntactic error suppression across shell, JS/TS,
Python, Go, and Rust. Recommends a surfacing channel based on detected
app context (CLI stderr, web toast + `console.error`, structured log,
`Result` propagation) and applies a privacy redaction policy to any
generated user-facing strings. Use `--emit-patch` to produce a
reviewable diff without mutating files.

### Dead Code Detection

```bash
/code:dead-code src/
```

Detects dead code across languages:
- Unused exports and files (Knip for JS/TS)
- Unused functions and variables (Vulture for Python)
- Unused dependencies (cargo-machete for Rust)

### Dependency Audit

```bash
/code:dep-audit --type all
```

Audits dependencies for:
- Known CVEs and security vulnerabilities
- Outdated packages
- License compliance issues

### Test Quality Analysis

```bash
/code:test-quality tests/
```

Analyzes test suite health:
- Empty tests with no assertions
- Weak/tautological assertions
- Flaky patterns (setTimeout, hardcoded ports)
- Missing edge case coverage

### Complexity Analysis

```bash
/code:complexity src/ --threshold 10
```

Measures and reports:
- Cyclomatic and cognitive complexity
- Function length distribution
- Nesting depth hotspots
- File-level coupling indicators

## ast-grep Patterns

The plugin includes ast-grep patterns for common issues:

```bash
# Find console.log statements
ast-grep -p 'console.log($$$)'

# Find empty catch blocks
ast-grep -p 'catch ($ERR) { }'

# Find TODO comments
ast-grep -p '// TODO: $MSG'
```

## Configure Plugin Pairing

This plugin works reactively (analyze and fix). The **configure-plugin** works proactively (set up tooling). They complement each other:

| code-quality-plugin (reactive) | configure-plugin (proactive) |
|---|---|
| `/code:lint` — run linters | `/configure:linting` — set up linters |
| `/code:lint-fix` — autofix lint issues | `/configure:formatting` — set up formatters |
| `/code:dead-code` — find dead code | `/configure:dead-code` — set up detection tools |
| `/code:dep-audit` — audit dependencies | `/configure:security` — set up security scanning |
| `/code:test-quality` — analyze test quality | `/configure:tests` + `/configure:coverage` — set up frameworks |
| `/code:docs-quality` — check doc quality | `/configure:docs` — set up doc generators |

## Companion Plugins

Works well with:
- **configure-plugin** - Proactive tool setup (see pairing table above)
- **testing-plugin** - For test coverage analysis
- **git-plugin** - For pre-commit quality checks
- **python-plugin** / **typescript-plugin** - Language-specific linting

## Installation

```bash
/plugin install code-quality-plugin@laurigates-claude-plugins
```

## License

MIT
