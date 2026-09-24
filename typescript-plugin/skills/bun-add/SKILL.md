---
description: "Bun add: install a package, add dev dependency, pin exact version, or target a workspace. Use when the user wants to add/install a specific package with bun."
args: <package> [--dev] [--exact]
allowed-tools: Bash, Read
argument-hint: package-name [--dev] [--exact]
created: 2025-12-20
modified: 2026-09-24
reviewed: 2026-09-24
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

## An unpinned `bun add` bypasses the lockfile

`bun install --frozen-lockfile` governs only what *that* install resolves. A
later `bun add <pkg>` with no version resolves the registry's **`latest`
dist-tag** at run time, and the lockfile does not apply to it. The usual place
this happens is a Dockerfile that installs with `--production` (to skip dev
packages) and then re-adds one CLI from `devDependencies`.

`latest` is a registry convention, not a stability guarantee. Publishers can
tag a prerelease as `latest`.

> Observed 2026-08: `bun add --dev prisma` in a `--production` Docker stage
> pulled `8.0.0-rc.12`, because npm's `latest` for `prisma` was a release
> candidate. Its CLI had no `generate` command, so the image build failed at a
> commit that touched neither Prisma nor the Dockerfile. Another image built
> from a plain `--frozen-lockfile` install kept working, which is the sign that
> a version was being resolved rather than locked. Unit-test CI stayed green
> because it never built the image.

When an install line has to name a package that the primary install skipped,
read the version from `package.json` instead of hardcoding a second copy. That
keeps one source of truth, and Renovate keeps bumping it:

```dockerfile
RUN bun add --dev "prisma@$(bun -e 'console.log(JSON.parse(await Bun.file("package.json").text()).devDependencies.prisma)')"
```

If `package.json` holds a range (`^7.9.1`), this resolves the highest version
inside that range, which may differ from the locked one. Pin exact versions in
`package.json` when that difference matters.

## Post-add

1. Report package version added
2. Show dependency tree impact with `bun why <package>`
3. Suggest running tests to verify compatibility
