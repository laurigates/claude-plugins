---
model: haiku
description: Install dependencies with Bun package manager
args: "[--frozen-lockfile] [--production]"
argument-hint: "--frozen-lockfile for CI, --production for deployment"
allowed-tools: Bash, Read
created: 2025-12-20
modified: 2026-02-03
reviewed: 2025-12-20
---

# /bun:install

Install all dependencies from package.json using Bun.

## Context

```
Package file: `find . -maxdepth 1 -name "package.json" | head -1`
Lock file: `find . -maxdepth 1 -name "bun.lock*" -o -name "bun.lockb" | head -1`
```

## Execution

1. Check if package.json exists
2. Run installation with appropriate flags:

**Development (default):**
```bash
bun install
```

**CI/Reproducible builds:**
```bash
bun install --frozen-lockfile
```

**Production deployment:**
```bash
bun install --production
```

3. Report installed package count and any warnings

## Post-install

- Verify node_modules exists
- Check for peer dependency warnings
- Run `bun run prepare` if it exists (for husky/hooks)
