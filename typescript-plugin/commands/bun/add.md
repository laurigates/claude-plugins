---
model: haiku
description: Add package dependency with Bun
args: <package> [--dev] [--exact]
allowed-tools: Bash, Read
argument-hint: package-name [--dev] [--exact]
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
---

# /bun:add

Add a package to dependencies using Bun.

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

## Post-add

1. Report package version added
2. Show dependency tree impact with `bun why <package>`
3. Suggest running tests to verify compatibility
