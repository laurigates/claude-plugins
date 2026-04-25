---
description: |
  Install all dependencies from package.json using Bun. Use when the user wants
  to bootstrap a fresh checkout with `bun install`, run a reproducible CI
  install with `--frozen-lockfile`, or prepare a production deployment with
  `--production` (no devDependencies). Triggers: "install deps", "bun install",
  "restore node_modules", "CI install", "production install".
args: "[--frozen-lockfile] [--production]"
argument-hint: "--frozen-lockfile for CI, --production for deployment"
allowed-tools: Bash, Read
created: 2025-12-20
modified: 2026-04-25
reviewed: 2026-04-25
name: bun-install
---

# /bun:install

Install all dependencies from package.json using Bun.

## When to Use This Skill

| Use this skill when... | Use bun-add instead when... |
|---|---|
| Bootstrapping a fresh checkout from existing package.json | Adding a new dependency to package.json |
| Running a CI install with `--frozen-lockfile` | Installing a single package with version pinning |
| Preparing a production deployment with `--production` | Updating an existing dependency (use bun-lockfile-update) |
| Restoring node_modules after deletion | Auditing what could be upgraded (use bun-outdated) |

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
