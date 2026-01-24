# Code Quality Plugin

Code review, refactoring, linting, anti-pattern detection, and static analysis for Claude Code.

## Overview

This plugin provides comprehensive code quality tools including automated code review, refactoring assistance, linting, and anti-pattern detection using ast-grep for structural analysis.

## Commands

| Command | Description |
|---------|-------------|
| `/code:review` | Comprehensive code review with automated fixes |
| `/code:refactor` | Refactor code following SOLID principles and best practices |
| `/code:antipatterns` | Analyze codebase for anti-patterns and code smells using ast-grep |
| `/lint:check` | Universal linter - auto-detects and runs appropriate linting tools |
| `/refactor` | Refactor selected code for quality improvements |
| `/docs:quality-check` | Analyze documentation quality - PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ |

## Skills

| Skill | Description |
|-------|-------------|
| `code-antipatterns-analysis` | Detect anti-patterns and code smells using ast-grep structural matching |
| `ast-grep-search` | AST-based code search for structural pattern matching |
| `documentation-quality` | Analyze and validate documentation quality for PRDs, ADRs, PRPs, CLAUDE.md, and .claude/rules/ |

## Agents

| Agent | Description |
|-------|-------------|
| `code-review` | Code quality, architecture, and performance analysis |
| `code-refactoring` | Quality improvements and SOLID principles |
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

Refactors code following:
- SOLID principles
- Design patterns
- Clean code practices

### Universal Linting

```bash
/lint:check --fix
```

Auto-detects project type and runs appropriate linters:
- Biome/ESLint for JavaScript/TypeScript
- Ruff for Python
- Clippy for Rust

### Documentation Quality Check

```bash
/docs:quality-check
```

Analyzes documentation quality and standards:
- CLAUDE.md structure and completeness
- .claude/rules/ organization
- ADRs (Architecture Decision Records)
- PRDs (Product Requirements Documents)
- PRPs (Product Requirement Prompts)
- Freshness and git history alignment
- Generates comprehensive quality report with actionable recommendations

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

## Companion Plugins

Works well with:
- **testing-plugin** - For test coverage analysis
- **git-plugin** - For pre-commit quality checks
- **python-plugin** / **typescript-plugin** - Language-specific linting

## Installation

```bash
/plugin install code-quality-plugin@laurigates-plugins
```

## License

MIT
