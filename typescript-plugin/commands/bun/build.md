---
model: haiku
description: Bundle or compile with Bun
args: <entry> [--compile] [--minify]
allowed-tools: Bash, Read
argument-hint: ./src/index.ts [--compile] [--minify]
created: 2025-12-20
modified: 2025-12-20
reviewed: 2025-12-20
---

# /bun:build

Bundle JavaScript/TypeScript or compile to standalone executable.

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
