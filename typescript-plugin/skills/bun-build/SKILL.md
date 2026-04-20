---
description: |
  Bundle or compile JavaScript/TypeScript with Bun. Use when the user wants a
  quick production bundle of an entry point, to compile to a standalone
  executable with `bun build --compile`, or to build for a specific target
  (browser, bun, node). Triggers: "bundle src/index.ts", "compile to binary",
  "build for node target", "make a standalone executable".
args: <entry> [--compile] [--minify]
allowed-tools: Bash, Read
argument-hint: ./src/index.ts [--compile] [--minify]
created: 2025-12-20
modified: 2026-04-19
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

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Prod bundle | `bun build ./src/index.ts --outdir=dist --minify --sourcemap=external` |
| Compile to exe | `bun build --compile --minify ./app.ts --outfile myapp` |
| Dev bundle | `bun build ./src/index.ts --outdir=dist --sourcemap=inline` |
| Browser target | `bun build ./src/index.ts --target=browser --outdir=dist` |
| Node target | `bun build ./src/index.ts --target=node --outdir=dist` |

## Post-build

1. Report output file sizes
2. List generated files in output directory
3. For --compile: verify executable runs with `./app --help` or similar
