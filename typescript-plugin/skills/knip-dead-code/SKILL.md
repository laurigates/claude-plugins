---
name: Knip Dead Code Detection
description: |
  Knip finds unused files, dependencies, exports, and types in JavaScript/TypeScript projects.
  Plugin system for frameworks (React, Next.js, Vite), test runners (Vitest, Jest), and build tools.
  Use when cleaning up codebases, optimizing bundle size, or enforcing strict dependency hygiene in CI.
allowed-tools: Glob, Grep, Read, Bash, Edit, Write, TodoWrite, WebFetch, WebSearch, BashOutput, KillShell
---

# Knip Dead Code Detection

Knip is a comprehensive tool for finding unused code, dependencies, and exports in JavaScript and TypeScript projects. It helps maintain clean codebases and catch dead code before it accumulates.

## Core Expertise

**What is Knip?**
- **Unused detection**: Files, dependencies, exports, types, enum members
- **Plugin system**: Supports 80+ frameworks and tools
- **Fast**: Analyzes large codebases in seconds
- **Actionable**: Clear reports with file locations
- **CI-ready**: Exit codes for failing builds

**Key Capabilities**
- Detect unused dependencies (npm, workspace packages)
- Find unused exports and types
- Identify unused files
- Discover unused enum members and class members
- Detect re-exports that aren't used
- Plugin support for frameworks (React, Next.js, Vue, Svelte)
- Integration with monorepos and workspaces

## Installation

```bash
# Project-local (recommended)
bun add --dev knip

# Global installation
bun add --global knip

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

### Recommended Production Setup

```typescript
// knip.ts
import type { KnipConfig } from 'knip';

const config: KnipConfig = {
  // Entry points
  entry: [
    'src/index.ts',
    'src/cli.ts',
    'scripts/**/*.ts', // Include scripts
  ],

  // Project files
  project: ['src/**/*.{ts,tsx}', 'scripts/**/*.ts'],

  // Ignore patterns
  ignore: [
    '**/*.test.ts',
    '**/*.spec.ts',
    '**/__tests__/**',
    '**/__mocks__/**',
    'dist/**',
    'build/**',
    'coverage/**',
    '.next/**',
  ],

  // Dependencies to ignore
  ignoreDependencies: [
    '@types/*', // Type definitions used implicitly
    'typescript', // Always needed for TS projects
    'tslib', // TypeScript helper library
    '@biomejs/biome', // Used via CLI
    'prettier', // Used via CLI
  ],

  // Binaries to ignore (used in package.json scripts)
  ignoreBinaries: ['npm-check-updates', 'semantic-release'],

  // Ignore exports used in the same file
  ignoreExportsUsedInFile: true,

  // Workspace configuration (for monorepos)
  workspaces: {
    '.': {
      entry: ['src/index.ts'],
    },
    'packages/*': {
      entry: ['src/index.ts', 'src/cli.ts'],
    },
  },
};

export default config;
```

## Plugin System

Knip automatically detects and configures plugins for popular tools:

### Framework Plugins

| Framework | Auto-detected | Entry Points |
|-----------|---------------|--------------|
| Next.js | `next.config.js` | `pages/`, `app/`, `middleware.ts` |
| Vite | `vite.config.ts` | `index.html`, config plugins |
| Remix | `remix.config.js` | `app/root.tsx`, `app/entry.*` |
| Astro | `astro.config.mjs` | `src/pages/`, config integrations |
| SvelteKit | `svelte.config.js` | `src/routes/`, `src/app.html` |
| Nuxt | `nuxt.config.ts` | `app.vue`, `pages/`, `layouts/` |

### Test Runner Plugins

| Tool | Auto-detected | Entry Points |
|------|---------------|--------------|
| Vitest | `vitest.config.ts` | `**/*.test.ts`, config files |
| Jest | `jest.config.js` | `**/*.test.js`, setup files |
| Playwright | `playwright.config.ts` | `tests/**/*.spec.ts` |
| Cypress | `cypress.config.ts` | `cypress/e2e/**/*.cy.ts` |

### Build Tool Plugins

| Tool | Auto-detected | Entry Points |
|------|---------------|--------------|
| TypeScript | `tsconfig.json` | Files in `include` |
| ESLint | `.eslintrc.js` | Config files, plugins |
| PostCSS | `postcss.config.js` | Config plugins |
| Tailwind | `tailwind.config.js` | Config plugins, content files |

### Plugin Configuration Override

```typescript
// knip.ts
const config: KnipConfig = {
  // Disable specific plugins
  eslint: false,
  prettier: false,

  // Override plugin config
  vitest: {
    entry: ['vitest.config.ts', 'test/setup.ts'],
    config: ['vitest.config.ts'],
  },

  next: {
    entry: [
      'next.config.js',
      'pages/**/*.tsx',
      'app/**/*.tsx',
      'middleware.ts',
      'instrumentation.ts',
    ],
  },
};
```

## Ignoring Issues

### Ignore Patterns

```typescript
// knip.ts
const config: KnipConfig = {
  // Ignore entire directories
  ignore: ['legacy/**', 'vendor/**'],

  // Ignore specific dependencies
  ignoreDependencies: [
    '@types/*',
    'some-peer-dependency',
  ],

  // Ignore specific exports
  ignoreExportsUsedInFile: {
    interface: true, // Ignore interfaces used only in same file
    type: true, // Ignore types used only in same file
  },

  // Ignore workspace packages
  ignoreWorkspaces: ['packages/deprecated/**'],
};
```

### Inline Comments

```typescript
// Ignore unused export
// @knip-ignore-export
export const unusedFunction = () => {};

// Ignore unused dependency in package.json
{
  "dependencies": {
    "some-package": "1.0.0" // @knip-ignore-dependency
  }
}
```

### Whitelist Pattern

```typescript
// knip.ts - Whitelist specific exports
const config: KnipConfig = {
  entry: ['src/index.ts'],
  project: ['src/**/*.ts'],

  // Only these exports are allowed to be unused (public API)
  exports: {
    include: ['src/index.ts'],
  },
};
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Knip
on:
  push:
    branches: [main]
  pull_request:

jobs:
  knip:
    name: Check for unused code
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - name: Install dependencies
        run: bun install --frozen-lockfile

      - name: Run Knip
        run: bunx knip --production

      - name: Run Knip (strict)
        run: bunx knip --max-issues 0
```

### GitLab CI

```yaml
knip:
  image: oven/bun:latest
  stage: test
  script:
    - bun install --frozen-lockfile
    - bunx knip --production
  only:
    - merge_requests
    - main
```

### Pre-commit Hook

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: knip
        name: Knip
        entry: bunx knip
        language: system
        pass_filenames: false
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

### Monorepo Workflows

```typescript
// knip.ts
const config: KnipConfig = {
  workspaces: {
    '.': {
      entry: ['scripts/**/*.ts'],
      ignoreDependencies: ['@org/internal-package'],
    },
    'packages/web': {
      entry: ['src/index.ts', 'src/App.tsx'],
      ignoreDependencies: ['react', 'react-dom'], // Provided by parent
    },
    'packages/api': {
      entry: ['src/server.ts'],
    },
  },
};
```

```bash
# Check all workspaces
bunx knip

# Check specific workspace
bunx knip --workspace packages/web
```

## Interpreting Results

### Example Output

```
✓ No unused files
✓ No unused dependencies
✗ 2 unused exports

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

## Troubleshooting

### False Positives (Exports Used via Side Effects)

```typescript
// knip.ts
const config: KnipConfig = {
  // Ignore exports that are used via side effects
  ignoreExportsUsedInFile: true,

  // Or add to entry points
  entry: ['src/index.ts', 'src/side-effect-file.ts'],
};
```

### Knip Not Finding Entry Points

```bash
# Debug configuration
bunx knip --debug

# Manually specify entry points
bunx knip --entry src/index.ts --entry src/cli.ts
```

### Performance Issues

```bash
# Exclude node_modules explicitly (usually automatic)
bunx knip --exclude '**/node_modules/**'

# Use .gitignore patterns
bunx knip --include-libs false

# Increase memory limit
NODE_OPTIONS=--max-old-space-size=4096 bunx knip
```

### Plugin Not Detected

```typescript
// knip.ts - Force enable plugin
const config: KnipConfig = {
  vite: {
    entry: ['vite.config.ts'],
    config: ['vite.config.ts'],
  },
};
```

### Unused Dependencies in Scripts

```json
// package.json - Knip detects binaries in scripts
{
  "scripts": {
    "lint": "eslint .", // Detects eslint dependency
    "test": "vitest" // Detects vitest dependency
  }
}
```

If not detected:
```typescript
// knip.ts
const config: KnipConfig = {
  ignoreDependencies: ['eslint', 'vitest'],
};
```

## Advanced Usage

### Custom Reporters

```bash
# JSON output (for CI)
bunx knip --reporter json > knip-report.json

# Compact output
bunx knip --reporter compact

# Custom format (coming soon)
bunx knip --reporter custom
```

### Incremental Checks (Changed Files Only)

```bash
# Check only changed files (requires git)
bunx knip --changed

# Since specific commit
bunx knip --changed --base main
```

### Type Checking Integration

```typescript
// knip.ts
const config: KnipConfig = {
  // Include type-only imports as used
  includeTypeImports: true,

  // Check for unused TypeScript types
  types: true,
};
```

## Best Practices

### Start with Dependencies Only

```bash
# Easiest wins first
bunx knip --dependencies

# Then move to exports
bunx knip --exports

# Finally check files
bunx knip --files
```

### Gradual Adoption

```typescript
// knip.ts - Start strict, then relax
const config: KnipConfig = {
  // Start with critical paths only
  entry: ['src/index.ts'],
  project: ['src/core/**/*.ts'],

  // Expand coverage over time
  // entry: ['src/**/*.ts'],
  // project: ['src/**/*.ts'],
};
```

### CI Strategy

```yaml
# Check dependencies in CI (fast, high value)
- name: Check unused dependencies
  run: bunx knip --dependencies --max-issues 0

# Check exports in PR (prevents API bloat)
- name: Check unused exports
  run: bunx knip --exports
  if: github.event_name == 'pull_request'
```

### Maintenance Schedule

- **Weekly**: Run full Knip scan, clean up issues
- **PR Review**: Check for new unused exports
- **Pre-release**: Full scan with `--production`
- **Refactors**: Run Knip before and after

## References

- Official docs: https://knip.dev
- Configuration: https://knip.dev/reference/configuration
- Plugins: https://knip.dev/reference/plugins
- CLI reference: https://knip.dev/reference/cli
- FAQ: https://knip.dev/reference/faq
