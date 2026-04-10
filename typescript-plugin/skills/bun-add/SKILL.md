---
description: Add package dependency with Bun
args: <package> [--dev] [--exact]
allowed-tools: Bash, Read
argument-hint: package-name [--dev] [--exact]
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
name: bun-add
---

# /bun:add

Add a package to dependencies using Bun.

## When to Use This Skill

| Scenario | Use this skill | Alternative |
|----------|---------------|-------------|
| Quickly adding a single package | Yes | N/A |
| Adding a dev dependency | Yes | N/A |
| Pinning an exact package version | Yes | N/A |
| Installing all project dependencies | No - use `bun-package-manager` | `bun install` |
| Removing or updating packages | No - use `bun-package-manager` | N/A |
| Managing workspace dependencies | No - use `bun-package-manager` | N/A |

## Parameters

- `package` (required): Package name, optionally with version (e.g., `lodash`, `react@18`)
- `--dev`: Add to devDependencies
- `--exact`: Pin exact version (no ^ range)

## Execution

```bash
bun add {{ if DEV }}--dev {{ endif }}{{ if EXACT }}--exact {{ endif }}$PACKAGE
```

## Examples

```bash
# Add runtime dependency
bun add express

# Add dev dependency
bun add --dev typescript vitest

# Pin exact version
bun add --exact react@18.2.0

# Add to specific workspace
bun add lodash --cwd packages/utils
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Add runtime dep | `bun add <package>` |
| Add dev dep | `bun add --dev <package>` |
| Pin exact version | `bun add --exact <package>` |
| Add to workspace | `bun add <package> --cwd <path>` |
| Preview changes | `bun add --dry-run <package>` |

## Post-add

1. Report package version added
2. Show dependency tree impact with `bun why <package>`
3. Suggest running tests to verify compatibility
