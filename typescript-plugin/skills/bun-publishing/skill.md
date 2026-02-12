---
model: haiku
name: bun-publishing
description: Publish packages to npm with Bun - package.json configuration, CLI packaging, provenance signing, and release automation.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-12-21
modified: 2025-12-21
reviewed: 2025-12-21
---

# Bun npm Publishing

## Core Expertise

Publishing npm packages built with Bun:
- Package.json configuration for npm registry
- CLI tool packaging with executable binaries
- Provenance signing for supply chain security
- Release automation with release-please

## Package.json Configuration

### Essential Publishing Fields

```json
{
  "name": "@org/package-name",
  "version": "1.0.0",
  "description": "Package description",
  "main": "build/index.js",
  "type": "module",
  "publishConfig": {
    "access": "public"
  },
  "files": [
    "build/",
    "README.md",
    "LICENSE"
  ],
  "scripts": {
    "build": "tsc && chmod +x build/index.js",
    "prepublishOnly": "bun run build"
  },
  "engines": {
    "node": ">=20.0.0",
    "bun": ">=1.0.0"
  }
}
```

### Field Reference

| Field | Purpose |
|-------|---------|
| `publishConfig.access` | `public` required for scoped packages |
| `files` | Whitelist of files/dirs to include in tarball |
| `main` | Entry point for CommonJS/ES import |
| `type` | `module` for ESM, `commonjs` for CJS |
| `engines` | Runtime version requirements |
| `prepublishOnly` | Runs before `npm publish` |

### Scoped Packages

Scoped packages (`@org/name`) require explicit public access:

```json
{
  "name": "@myorg/mypackage",
  "publishConfig": {
    "access": "public"
  }
}
```

Or use the CLI flag:
```bash
npm publish --access public
```

## CLI Tool Packaging

### Binary Entry Configuration

```json
{
  "bin": {
    "mycli": "build/index.js"
  }
}
```

For single-command packages:
```json
{
  "bin": "build/index.js"
}
```

### Executable Setup

Entry point requires shebang and executable permission:

```typescript
#!/usr/bin/env node
// build/index.js

import { main } from "./main.js";
main();
```

Build script must set permissions:
```json
{
  "scripts": {
    "build": "tsc && chmod +x build/index.js"
  }
}
```

### Makefile Integration

```makefile
build-prod:
	rm -rf build
	tsc --declaration --sourceMap
	chmod +x build/index.js

publish: build-prod
	npm publish --access public
```

## Publishing Commands

### Manual Publishing

```bash
# Standard publish (runs prepublishOnly)
npm publish

# Scoped package (requires --access public)
npm publish --access public

# Dry run to verify contents
npm publish --dry-run

# View what would be published
npm pack --dry-run
```

### With Provenance

Supply chain security via npm provenance:

```bash
npm publish --provenance --access public
```

Requires:
- CI environment (GitHub Actions, GitLab CI)
- `id-token: write` permission in workflow
- npm registry-url configured

## Files Whitelist

### Recommended Pattern

```json
{
  "files": [
    "build/",
    "README.md",
    "LICENSE"
  ]
}
```

### What to Include

| Include | Examples |
|---------|----------|
| Build output | `build/`, `dist/` |
| Type definitions | `*.d.ts` (usually in build) |
| Documentation | `README.md`, `LICENSE` |
| Config scripts | User-facing setup scripts |

### What to Exclude

Already excluded by npm (no need to list):
- `node_modules/`
- `.git/`
- `.env*`
- `*.log`

Explicitly exclude via `.npmignore` if needed:
```
src/
tests/
*.test.ts
.github/
```

## Release Automation

### Release-Please Integration

`.github/workflows/release-please.yml`:
```yaml
name: Release Please

on:
  push:
    branches: [main]

permissions:
  contents: write
  pull-requests: write
  id-token: write

jobs:
  release-please:
    runs-on: ubuntu-latest
    outputs:
      release_created: ${{ steps.release.outputs.release_created }}
    steps:
      - uses: google-github-actions/release-please-action@v4
        id: release
        with:
          release-type: node
          package-name: mypackage

  publish:
    needs: release-please
    if: ${{ needs.release-please.outputs.release_created == 'true' }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org

      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest

      - run: bun install --frozen-lockfile
      - run: bun run build
      - run: npm publish --provenance --access public
        env:
          NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

### Conventional Commits for Versioning

| Commit Type | Version Bump |
|-------------|--------------|
| `feat:` | Minor (1.x.0) |
| `fix:` | Patch (1.0.x) |
| `feat!:` or `BREAKING CHANGE:` | Major (x.0.0) |
| `chore:`, `docs:`, `refactor:` | No bump |

## Pre-publish Validation

### Build Hook

```json
{
  "scripts": {
    "prepublishOnly": "bun run build"
  }
}
```

### Full Validation

```bash
# Type check
bun run tsc --noEmit

# Lint
bun run check

# Test
bun test

# Build
bun run build

# Verify tarball contents
npm pack --dry-run
```

## Repository Metadata

Complete metadata for npm and GitHub:

```json
{
  "repository": {
    "type": "git",
    "url": "https://github.com/org/repo.git"
  },
  "homepage": "https://github.com/org/repo#readme",
  "bugs": {
    "url": "https://github.com/org/repo/issues"
  },
  "keywords": ["keyword1", "keyword2"],
  "author": "Name <email>",
  "license": "MIT"
}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Preview tarball | `npm pack --dry-run` |
| Preview publish | `npm publish --dry-run` |
| Scoped publish | `npm publish --access public` |
| Provenance | `npm publish --provenance --access public` |
| Check outdated | `npm outdated` |
| View package | `npm view @org/pkg` |

## Quick Reference

### Publishing Flags

| Flag | Description |
|------|-------------|
| `--access public` | Required for scoped packages |
| `--provenance` | Enable supply chain provenance |
| `--dry-run` | Preview without publishing |
| `--tag <tag>` | Publish with dist-tag (e.g., `beta`) |

### Package.json Scripts

| Script | When It Runs |
|--------|--------------|
| `prepublish` | Before `pack` and `publish` (deprecated) |
| `prepublishOnly` | Before `publish` only |
| `prepack` | Before `pack` and `publish` |
| `postpack` | After `pack` |
| `postpublish` | After `publish` |

### CI Environment Variables

| Variable | Purpose |
|----------|---------|
| `NODE_AUTH_TOKEN` | npm authentication |
| `NPM_TOKEN` | Alternative npm token name |

## Common Issues

**Scoped package 402 error:**
```bash
# Add --access public for scoped packages
npm publish --access public
```

**Missing files in tarball:**
```bash
# Check what's included
npm pack --dry-run

# Verify files array in package.json
```

**Binary not executable after install:**
```bash
# Ensure shebang in entry point
#!/usr/bin/env node

# Ensure chmod in build script
chmod +x build/index.js
```
