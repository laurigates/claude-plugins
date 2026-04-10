---
description: Bundle or compile with Bun
args: <entry> [--compile] [--minify]
allowed-tools: Bash, Read
argument-hint: ./src/index.ts [--compile] [--minify]
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
name: bun-build
---

# /bun:build

Bundle JavaScript/TypeScript or compile to standalone executable.

## When to Use This Skill

| Scenario | Use this skill | Alternative |
|----------|---------------|-------------|
| Quick production bundle of an entry point | Yes | N/A |
| Compiling to a standalone executable | Yes | N/A |
| Building for a specific target (browser/bun/node) | Yes | N/A |
| Configuring complex build pipelines | No - use `bun-development` | Full build configuration guidance |
| Running project build scripts (`bun run build`) | No - use `bun-development` | N/A |

## Parameters

- `entry` (required): Entry point file
- `--compile`: Create standalone executable
- `--minify`: Minify output

## Execution

**Production bundle:**
```bash
bun build $ENTRY --outdir=dist --minify --sourcemap=external
```

**Standalone executable:**
```bash
bun build --compile --minify $ENTRY --outfile={{ OUTFILE | default: "app" }}
```

**Development bundle:**
```bash
bun build $ENTRY --outdir=dist --sourcemap=inline
```

## Build Targets

```bash
# Browser (default)
bun build $ENTRY --target=browser --outdir=dist

# Bun runtime
bun build $ENTRY --target=bun --outdir=dist

# Node.js
bun build $ENTRY --target=node --outdir=dist
```

## Post-build

1. Report output file sizes
2. List generated files in output directory
3. For --compile: verify executable runs with `./app --help` or similar
