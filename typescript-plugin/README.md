# TypeScript Plugin

TypeScript development for Claude Code - strict types, ESLint, Biome, and dead code detection.

## Overview

TypeScript development support with modern tooling: strict type configuration, ESLint/Biome for linting, and Knip for dead code detection.

## Skills

| Skill | Description |
|-------|-------------|
| `typescript-strict` | Strict TypeScript configuration and patterns |
| `eslint-configuration` | ESLint configuration and patterns |
| `biome-tooling` | Biome linter and formatter |
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
/plugin install typescript-plugin@lgates-claude-plugins
```

## License

MIT
