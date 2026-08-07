---
description: "Bun add: install a package, add dev dependency, pin exact version, or target a workspace. Use when the user wants to add/install a specific package with bun."
args: <package> [--dev] [--exact]
allowed-tools: Bash, Read
argument-hint: package-name [--dev] [--exact]
created: 2025-12-20
modified: 2026-08-07
reviewed: 2026-08-07
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

Parse `$ARGUMENTS`. These are supplied by the **caller**; nothing substitutes
them for you.

| Token in `$ARGUMENTS` | Binds | Default when absent |
|---|---|---|
| First non-flag token (required) | `PACKAGE` — name, optionally with a version (`lodash`, `react@18`) | none — ask for it rather than guessing |
| `--dev` | add to `devDependencies` | added to `dependencies` |
| `--exact` | pin the exact version (no `^` range) | caret range |

## Execution

Pick the row matching the flags the caller passed, substitute `PACKAGE`, and run it:

| Flags in `$ARGUMENTS` | Command |
|---|---|
| (none) | `bun add PACKAGE` |
| `--dev` | `bun add --dev PACKAGE` |
| `--exact` | `bun add --exact PACKAGE` |
| `--dev --exact` | `bun add --dev --exact PACKAGE` |

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

# Preview without writing package.json
bun add --dry-run zod
```

## Post-add

1. Report package version added
2. Show dependency tree impact with `bun why <package>`
3. Suggest running tests to verify compatibility
