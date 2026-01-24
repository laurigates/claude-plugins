# TypeScript Plugin

TypeScript development for Claude Code - strict types, ESLint, Biome, Bun runtime, and dead code detection.

## Overview

TypeScript development support with modern tooling: strict type configuration, ESLint/Biome for linting, Bun for fast runtime/testing/bundling, and Knip for dead code detection.

## Skills

| Skill | Description |
|-------|-------------|
| `typescript-strict` | Strict TypeScript configuration and patterns |
| `typescript-debugging` | Debugging with Bun inspector, VSCode, memory profiling |
| `typescript-sentry` | Error monitoring and performance tracking with Sentry |
| `eslint-configuration` | ESLint configuration and patterns |
| `biome-tooling` | Biome linter and formatter |
| `bun-package-manager` | Fast package management with Bun |
| `bun-development` | Bun runtime, testing, and bundling |
| `bun-publishing` | Publish packages to npm with Bun build |
| `knip-dead-code` | Detect dead code in TypeScript/JavaScript projects |

## Agents

| Agent | Description |
|-------|-------------|
| `typescript-development` | TypeScript-specific development tasks |
| `javascript-development` | JavaScript/Node.js development tasks |

## Usage Examples

### Strict TypeScript Config

```json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true
  }
}
```

### Biome Setup

```bash
biome init
biome check .
biome format . --write
```

### Bun Commands

```bash
/bun:install           # Install dependencies
/bun:add lodash        # Add package
/bun:test              # Run tests with compact output
/bun:build ./src/index.ts  # Bundle for production
/bun:debug script.ts   # Debug with inspector
/bun:debug --brk app.ts # Break at first line
/bun:outdated          # Check for updates
/bun:publish           # Publish to npm
/bun:publish --dry-run # Preview publish
```

### Debugging

```bash
# Debug with web inspector
bun --inspect script.ts

# Break at first line
bun --inspect-brk script.ts

# Debug tests
bun --inspect-brk test

# Memory profiling
bun -e "import{heapStats}from'bun:jsc';console.log(heapStats())"

# Network request debugging
BUN_CONFIG_VERBOSE_FETCH=curl bun script.ts
```

### Sentry Error Monitoring

```typescript
import * as Sentry from "@sentry/bun";

// Initialize (in instrument.ts)
Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 0.1,
});

// Capture errors
Sentry.captureException(error, {
  tags: { feature: "checkout" },
});

// Performance spans
await Sentry.startSpan({ op: "db.query", name: "Fetch users" }, async () => {
  return db.query("SELECT * FROM users");
});

// Cron monitoring
Sentry.withMonitor("daily-cleanup", () => cleanupOldRecords());
```

### Dead Code Detection

```bash
knip
```

## Companion Plugins

Works well with:
- **testing-plugin** - For vitest patterns
- **code-quality-plugin** - For code review

## Installation

```bash
/plugin install typescript-plugin@laurigates-plugins
```

## License

MIT
