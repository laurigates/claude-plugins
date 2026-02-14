---
model: haiku
created: 2025-12-16
modified: 2025-12-16
reviewed: 2025-12-16
name: knip-dead-code
description: |
  Knip finds unused files, dependencies, exports, and types in JavaScript/TypeScript projects.
  Plugin system for frameworks (React, Next.js, Vite), test runners (Vitest, Jest), and build tools.
  Use when cleaning up codebases, optimizing bundle size, or enforcing strict dependency hygiene in CI.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Knip Dead Code Detection

Knip is a comprehensive tool for finding unused code, dependencies, and exports in JavaScript and TypeScript projects. It helps maintain clean codebases and catch dead code before it accumulates.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Finding unused dependencies | Removing unused CSS (use PurgeCSS) |
| Detecting unused exports in libraries | Finding runtime dead code paths |
| Cleaning up codebases after refactors | Optimizing bundle size (use bundler tree-shaking) |
| Enforcing dependency hygiene in CI | Detecting duplicate dependencies (use npm-dedupe) |

## Core Expertise

**What is Knip?**
- **Unused detection**: Files, dependencies, exports, types, enum members
- **Plugin system**: Supports 80+ frameworks and tools
- **Fast**: Analyzes large codebases in seconds
- **Actionable**: Clear reports with file locations
- **CI-ready**: Exit codes for failing builds

## Installation

```bash
# Project-local (recommended)
bun add --dev knip

# Verify installation
bunx knip --version
```

## Basic Usage

```bash
# Run Knip (scans entire project)
bunx knip

# Show only unused dependencies
bunx knip --dependencies

# Show only unused exports
bunx knip --exports

# Show only unused files
bunx knip --files

# Production mode (only check production dependencies)
bunx knip --production

# Exclude specific issue types
bunx knip --exclude-exports-used-in-file

# Output JSON (for CI)
bunx knip --reporter json

# Debug mode (show configuration)
bunx knip --debug
```

## Configuration

### Auto-detection (Zero Config)

Knip automatically detects:
- Entry points (package.json `main`, `exports`, `bin`)
- Frameworks (Next.js, Vite, Remix, etc.)
- Test runners (Vitest, Jest, Playwright)
- Build tools (ESLint, TypeScript, PostCSS)

**No configuration needed for standard projects.**

### knip.json (Explicit Configuration)

```json
{
  "$schema": "https://unpkg.com/knip@latest/schema.json",
  "entry": ["src/index.ts", "src/cli.ts"],
  "project": ["src/**/*.ts"],
  "ignore": ["**/*.test.ts", "scripts/**"],
  "ignoreDependencies": ["@types/*"],
  "ignoreBinaries": ["npm-check-updates"]
}
```

### knip.ts (TypeScript Configuration)

```typescript
// knip.ts
import type { KnipConfig } from 'knip';

const config: KnipConfig = {
  entry: ['src/index.ts', 'src/cli.ts'],
  project: ['src/**/*.ts', 'scripts/**/*.ts'],
  ignore: ['**/*.test.ts', '**/*.spec.ts', 'tmp/**'],
  ignoreDependencies: [
    '@types/*', // Type definitions
    'typescript', // Always needed
  ],
  ignoreExportsUsedInFile: true,
  ignoreWorkspaces: ['packages/legacy/**'],
};

export default config;
```

## Common Patterns

### Check Only Unused Dependencies

```bash
# Fastest check - only dependencies
bunx knip --dependencies

# Exit with error if any unused dependencies
bunx knip --dependencies --max-issues 0
```

**Use in CI to enforce strict dependency hygiene.**

### Check Only Exports (Library Development)

```bash
# Check for unused exports
bunx knip --exports

# Allow exports used in same file
bunx knip --exports --exclude-exports-used-in-file
```

**Use for libraries to ensure clean public API.**

### Production vs Development Dependencies

```bash
# Check production code only
bunx knip --production

# Check everything (including dev dependencies)
bunx knip
```

## Interpreting Results

### Example Output

```
No unused files
No unused dependencies
2 unused exports

src/utils.ts:
  - calculateTax (line 42)
  - formatDate (line 58)

src/types.ts:
  - UserRole (line 12)
```

### Issue Types

| Type | Description | Action |
|------|-------------|--------|
| Unused file | File not imported anywhere | Delete or add to entry points |
| Unused dependency | Package in package.json not used | Remove from dependencies |
| Unused export | Exported but never imported | Remove export or make private |
| Unused type | Type/interface exported but unused | Remove or make internal |
| Unused enum member | Enum member never referenced | Remove member |
| Duplicate export | Same export from multiple files | Consolidate exports |

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick scan | `bunx knip` |
| Dependencies only | `bunx knip --dependencies` |
| Exports only | `bunx knip --exports` |
| CI strict mode | `bunx knip --max-issues 0` |
| Production check | `bunx knip --production` |
| JSON output | `bunx knip --reporter json` |
| Debug config | `bunx knip --debug` |
| Changed files | `bunx knip --changed --base main` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `--dependencies` | Check only unused dependencies |
| `--exports` | Check only unused exports |
| `--files` | Check only unused files |
| `--production` | Production dependencies only |
| `--max-issues N` | Fail if more than N issues |
| `--reporter json` | JSON output for CI |
| `--reporter compact` | Compact output |
| `--debug` | Show configuration details |
| `--changed` | Check only changed files |
| `--changed --base main` | Changed files since main |
| `--workspace NAME` | Check specific workspace |
| `--exclude-exports-used-in-file` | Ignore same-file exports |

For detailed examples, advanced patterns, and best practices, see [REFERENCE.md](REFERENCE.md).

## References

- Official docs: https://knip.dev
- Configuration: https://knip.dev/reference/configuration
- Plugins: https://knip.dev/reference/plugins
- CLI reference: https://knip.dev/reference/cli
- FAQ: https://knip.dev/reference/faq
