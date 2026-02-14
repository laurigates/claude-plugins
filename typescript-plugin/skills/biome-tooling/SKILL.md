---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: biome-tooling
description: |
  Biome all-in-one formatter and linter for JavaScript, TypeScript, JSX, TSX, JSON, and CSS.
  Zero-config setup, 15-20x faster than ESLint/Prettier. Use when working with modern JavaScript/TypeScript
  projects, setting up formatting/linting, or migrating from ESLint+Prettier to a faster alternative.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Biome Tooling

Biome is a modern, performant toolchain for JavaScript, TypeScript, and related web languages. It combines formatting, linting, and import organization into a single tool that's **15-20x faster** than ESLint/Prettier.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Starting a new JS/TS project | Need specific ESLint plugins (React hooks, a11y) |
| Want zero-config formatting/linting | Have complex custom ESLint rules |
| Need fast CI/CD pipelines | Need framework-specific rules (Next.js, Nuxt) |
| Migrating from ESLint+Prettier | Legacy codebase with heavy ESLint customization |

**Hybrid approach**: Use Biome for formatting, ESLint for specialized linting.

## Core Expertise

**What is Biome?**
- **All-in-one toolchain**: Linter + formatter + import sorter
- **Zero-config**: Works out of the box with sensible defaults
- **Fast**: Written in Rust, processes files in parallel
- **Compatible**: Matches Prettier formatting 97%+
- **Supports**: JavaScript, TypeScript, JSX, TSX, JSON, CSS

## Installation

```bash
# Project-local (recommended)
bun add --dev @biomejs/biome

# Verify installation
bunx biome --version

# Initialize configuration
bunx biome init
```

## Essential Commands

```bash
# Format files
bunx biome format --write src/

# Lint with fixes
bunx biome lint --write src/

# Check everything (format + lint + organize imports)
bunx biome check --write src/

# Check without changes (CI mode)
bunx biome check src/

# CI mode (exits with error on issues)
bunx biome ci src/

# Migrate from ESLint/Prettier
bunx biome migrate eslint --write
bunx biome migrate prettier --write

# Explain a rule
bunx biome explain noUnusedVariables
```

## Configuration (biome.json)

### Minimal Setup (Zero Config)

Biome works without configuration. For basic customization:

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": false,
    "ignore": ["dist", "build", "node_modules", ".next", "coverage"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true
    }
  },
  "organizeImports": {
    "enabled": true
  }
}
```

## Rule Categories

| Category | Purpose | Example Rules |
|----------|---------|---------------|
| `recommended` | Essential rules everyone should enable | Most rules marked "recommended" |
| `correctness` | Prevent bugs and logic errors | `noUnusedVariables`, `noUnreachable` |
| `suspicious` | Detect code that might be wrong | `noExplicitAny`, `noDoubleEquals` |
| `style` | Enforce consistent style | `useConst`, `noVar` |
| `complexity` | Reduce code complexity | `noForEach`, `useFlatMap` |
| `performance` | Optimize performance | `noAccumulatingSpread` |
| `a11y` | Accessibility best practices | `noSvgWithoutTitle`, `useAltText` |
| `security` | Security vulnerabilities | `noDangerouslySetInnerHtml` |

## Common Patterns

### Ignore Files and Directories

**Via biome.json:**
```json
{
  "files": {
    "ignore": [
      "dist",
      "build",
      "node_modules",
      "**/*.config.js",
      "scripts/legacy/**"
    ]
  }
}
```

**Via .gitignore (automatic):**
```json
{
  "vcs": {
    "enabled": true,
    "useIgnoreFile": true
  }
}
```

## Performance Comparison

| Tool | Time (1000 files) | Notes |
|------|-------------------|-------|
| Biome | 0.5s | Rust, parallel processing |
| ESLint | 8-10s | Node.js, single-threaded |
| Prettier | 3-5s | Node.js, formatting only |
| ESLint + Prettier | 11-15s | Sequential execution |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick check | `bunx biome check src/` |
| Fix all | `bunx biome check --write src/` |
| Format only | `bunx biome format --write src/` |
| Lint only | `bunx biome lint --write src/` |
| CI mode | `bunx biome ci src/` |
| Errors only | `bunx biome check --diagnostic-level=error src/` |
| Limited output | `bunx biome check --max-diagnostics=10 src/` |
| GitHub reporter | `bunx biome check --reporter=github src/` |
| JSON output | `bunx biome check --reporter=json src/` |
| Migrate ESLint | `bunx biome migrate eslint --write` |
| Migrate Prettier | `bunx biome migrate prettier --write` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--write` | Apply fixes/formatting |
| `--reporter=github` | GitHub annotations format |
| `--reporter=json` | JSON output |
| `--diagnostic-level=error` | Errors only |
| `--max-diagnostics=N` | Limit output count |
| `--verbose` | Show detailed diagnostics |
| `--no-errors-on-unmatched` | Ignore unmatched files |
| `ci` | CI mode (check + exit code) |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## References

- Official docs: https://biomejs.dev
- Configuration: https://biomejs.dev/reference/configuration/
- Rules: https://biomejs.dev/linter/
- Migration guide: https://biomejs.dev/guides/migrate-eslint-prettier/
- Editor integration: https://biomejs.dev/
