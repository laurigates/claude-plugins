# Knip Dead Code Detection - Reference

Detailed reference material for Knip dead code detection.

## Recommended Production Setup

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

## Monorepo Workflows

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

### Maintenance Schedule

- **Weekly**: Run full Knip scan, clean up issues
- **PR Review**: Check for new unused exports
- **Pre-release**: Full scan with `--production`
- **Refactors**: Run Knip before and after

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
