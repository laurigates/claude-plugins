---
name: bun-publishing
description: "Publish npm packages built with Bun: package.json config, CLI tool packaging, provenance signing, release automation. Use when setting up `publishConfig`/`files`/`bin`, packaging a CLI, enabling `--provenance`, or wiring release-please."
user-invocable: false
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-12-21
modified: 2026-06-06
reviewed: 2026-06-06
---

# Bun npm Publishing

## When to Use This Skill

| Scenario | Use this skill | Alternative |
|----------|---------------|-------------|
| Configuring package.json for npm publishing | Yes | N/A |
| Publishing a package to npm registry | Yes | N/A |
| Setting up CLI tool packaging with `bin` | Yes | N/A |
| Configuring provenance signing | Yes | N/A |
| Setting up release-please automation | Yes | N/A |
| Validating tarball contents before publish | Yes | N/A |
| Installing or updating dependencies | No - use `bun-package-manager` | `bun-add` for quick additions |
| Building/bundling before publish | No - use `bun-development` | `bun-build` for quick builds |

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
      - uses: google-github-actions/release-please-action@v4.1.1
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
      - uses: actions/checkout@v4.3.1

      - uses: actions/setup-node@v4.4.0
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org

      - uses: oven-sh/setup-bun@v2.2.0
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

**2FA publish (`EOTP`) is not automatable:**

A non-interactive shell — a CI step, or an agent's Bash tool — cannot
supply a one-time password. `npm publish` fails with:

```
npm error code EOTP
npm error This operation requires a one-time password.
```

Two ways through:

- **Human, interactive**: `npm publish --otp=<6-digit-code>` (the code
  comes from the publisher's authenticator app, not from npm on demand).
- **Automation token (CI / unattended)**: a Granular/Automation token
  (npmjs.com → Access Tokens) **bypasses 2FA at publish time**. Put it in
  `NODE_AUTH_TOKEN` / `NPM_TOKEN`. This is exactly why the release-please
  workflow above publishes cleanly while a local `npm publish` prompts —
  CI uses the token, the human uses the OTP.

An agent that hits `EOTP` should hand the publish to the user or switch
the repo to an automation token — it cannot mint or supply one itself
(`npm token create` also requires a valid, OTP-satisfied session).

**Fresh publish 404s for a few minutes (propagation lag):**

Right after a first publish, *public / unauthenticated* reads can 404
while the package is genuinely live — the access record updates instantly
but the public metadata CDN lags. Don't conclude the publish failed.
Confirm with authenticated, version-pinned checks:

```bash
npm access list packages              # shows it under your account immediately
npm view @org/pkg@<version> _id       # version-pinned, authed — resolves once live
npm pack @org/pkg@<version>           # actually fetches the tarball (definitive)
```

Signature of *propagation lag* (not a private/failed publish): a public
404 **plus** `npm access list packages` shows the package **plus** an
authed `npm pack @org/pkg@<version>` succeeds. (`npm config get
//registry.npmjs.org/:_authToken` often returns empty even when logged
in, so a hand-rolled `curl` with that "token" is an unauthenticated probe
— use the `npm` CLI itself, which reads auth correctly, to test.)
