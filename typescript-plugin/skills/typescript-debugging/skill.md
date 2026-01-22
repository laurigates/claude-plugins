---
name: TypeScript Debugging
description: Modern TypeScript/JavaScript debugging with Bun - inspector flags, web debugger, VSCode integration, memory profiling, and heap analysis.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2026-01-22
modified: 2026-01-22
reviewed: 2026-01-22
---

# TypeScript Debugging

## Core Expertise

Modern debugging for TypeScript/JavaScript with Bun runtime:
- WebKit Inspector Protocol (debug.bun.sh)
- VSCode integration with Bun extension
- Memory profiling with V8 heap snapshots
- Automatic sourcemap generation for TypeScript
- Chrome DevTools for heap analysis

## Inspector Flags

### Basic Debugging

```bash
# Start with debugger enabled
bun --inspect script.ts

# Custom port
bun --inspect=4000 script.ts

# Custom host:port
bun --inspect=localhost:4000 script.ts
```

### Break on Start

```bash
# Break at first line (for fast scripts)
bun --inspect-brk script.ts

# Wait for debugger before running
bun --inspect-wait script.ts
```

### Debugging Tests

```bash
# Debug test file
bun --inspect test

# Break before tests run
bun --inspect-brk test auth.test.ts
```

## Web Debugger (debug.bun.sh)

Bun's built-in web debugger is a modified WebKit Web Inspector:

```bash
# Start debugging - outputs debug URL
bun --inspect script.ts
# ------------------- Bun Inspector -------------------
# Listening: ws://localhost:6499/
# Open: debug.bun.sh/#localhost:6499
# -----------------------------------------------------
```

### Features

| Feature | Description |
|---------|-------------|
| Source view | View original TypeScript/JSX with sourcemaps |
| Breakpoints | Click line numbers to set/remove |
| Console | Execute code in current context |
| Call stack | Inspect execution frames |
| Scope | View local/closure/global variables |
| Watch | Add expressions to monitor |

### Execution Controls

| Control | Action |
|---------|--------|
| Continue (F8) | Run until next breakpoint |
| Step Over (F10) | Execute line, skip into functions |
| Step Into (F11) | Enter function call |
| Step Out (Shift+F11) | Complete function, return to caller |

## VSCode Integration

### Extension Setup

Install [Bun for Visual Studio Code](https://marketplace.visualstudio.com/items?itemName=oven.bun-vscode).

### launch.json Configuration

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "bun",
      "request": "launch",
      "name": "Debug Script",
      "program": "${workspaceFolder}/src/index.ts",
      "cwd": "${workspaceFolder}",
      "stopOnEntry": false,
      "watchMode": false
    },
    {
      "type": "bun",
      "request": "launch",
      "name": "Debug Tests",
      "program": "${workspaceFolder}/tests/index.test.ts",
      "cwd": "${workspaceFolder}",
      "runtime": "bun",
      "runtimeArgs": ["test"]
    },
    {
      "type": "bun",
      "request": "launch",
      "name": "Debug with Watch",
      "program": "${workspaceFolder}/src/index.ts",
      "watchMode": true
    },
    {
      "type": "bun",
      "request": "attach",
      "name": "Attach to Bun",
      "url": "ws://localhost:6499/"
    }
  ]
}
```

### Configuration Options

| Option | Type | Description |
|--------|------|-------------|
| `program` | string | Entry file path |
| `cwd` | string | Working directory |
| `args` | string[] | Arguments to script |
| `env` | object | Environment variables |
| `stopOnEntry` | boolean | Break at first line |
| `watchMode` | boolean | Enable --watch/--hot |
| `noDebug` | boolean | Run without debugger |
| `strictEnv` | boolean | Only use specified env |

## Memory Debugging

### Heap Snapshots

Create snapshots for Chrome DevTools analysis:

```typescript
import { writeHeapSnapshot } from "v8";

// Create snapshot at any point
writeHeapSnapshot("before.heapsnapshot");

// After suspect operation
doSomeWork();

writeHeapSnapshot("after.heapsnapshot");
```

Load `.heapsnapshot` files in Chrome DevTools Memory tab for comparison.

### Heap Statistics (bun:jsc)

```typescript
import { heapStats } from "bun:jsc";

const stats = heapStats();
console.log({
  heapSize: stats.heapSize,
  objectCount: stats.objectCount,
  objectTypeCounts: stats.objectTypeCounts
});
// objectTypeCounts: { Array: 1234, Object: 5678, Function: 890, ... }
```

### Process Memory

```typescript
// Resident Set Size (actual RAM used)
console.log(process.memoryUsage.rss());

// Full memory breakdown
console.log(process.memoryUsage());
// { rss, heapTotal, heapUsed, external, arrayBuffers }
```

### Non-JS Memory (mimalloc)

```bash
# Show native memory stats
MIMALLOC_SHOW_STATS=1 bun script.ts
```

## Performance Profiling

### CPU Profiling

```bash
# Generate CPU profile
bun --cpu-prof script.ts

# Produces .cpuprofile file for Chrome DevTools
```

### Network Request Debugging

```bash
# Log all fetch/http requests
BUN_CONFIG_VERBOSE_FETCH=1 bun script.ts

# Log as curl commands
BUN_CONFIG_VERBOSE_FETCH=curl bun script.ts
```

## Sourcemaps

Bun automatically generates sourcemaps for transpiled files:

- TypeScript → JavaScript mapping preserved
- JSX transformations tracked
- Stack traces show original source locations
- Debugger shows TypeScript, not transpiled JS

### Build with Sourcemaps

```bash
# External sourcemaps (recommended for debugging)
bun build ./src/index.ts --outdir=dist --sourcemap=external

# Inline sourcemaps
bun build ./src/index.ts --outdir=dist --sourcemap=inline

# No sourcemaps (production)
bun build ./src/index.ts --outdir=dist --sourcemap=none
```

## Console Debugging

### Beyond console.log

```typescript
// Structured object/array display
console.table([{ id: 1, name: "a" }, { id: 2, name: "b" }]);

// Timing operations
console.time("fetch");
await fetch(url);
console.timeEnd("fetch"); // fetch: 234ms

// Group related logs
console.group("Request");
console.log("URL:", url);
console.log("Method:", method);
console.groupEnd();

// Conditional logging
console.assert(value > 0, "Value must be positive", value);

// Stack trace without error
console.trace("Reached here");
```

### Programmatic Breakpoints

```typescript
// Pause execution when debugger attached
debugger;

// Conditional breakpoint
if (suspiciousCondition) {
  debugger;
}
```

## Common Leak Patterns

### Closure Entrapment

```typescript
// BAD: largeData retained in closure
const largeData = loadHugeArray();
setInterval(() => {
  console.log(largeData.length); // Keeps largeData alive forever
}, 1000);

// GOOD: Copy only needed data
const dataLength = largeData.length;
setInterval(() => {
  console.log(dataLength);
}, 1000);
```

### Event Listener Cleanup

```typescript
// BAD: Listener never removed
emitter.on("data", handler);

// GOOD: Use once for single events
emitter.once("data", handler);

// GOOD: Explicit cleanup
emitter.on("data", handler);
// Later...
emitter.removeListener("data", handler);
```

### AbortSignal/AbortController

```typescript
// For long-running operations
const controller = new AbortController();
const response = await fetch(url, { signal: controller.signal });

// Cleanup on timeout
setTimeout(() => controller.abort(), 30000);
```

### Module-Level Variables

```typescript
// BAD: Grows indefinitely
const cache: Map<string, Data> = new Map();

export function getData(key: string) {
  if (!cache.has(key)) {
    cache.set(key, expensiveCompute(key));
  }
  return cache.get(key);
}

// GOOD: Use LRU or TTL cache
import { LRUCache } from "lru-cache";
const cache = new LRUCache<string, Data>({ max: 1000 });
```

## Debugging Workflow

### Memory Leak Investigation

1. **Baseline**: Create heap snapshot at startup
2. **Reproduce**: Perform suspect operations
3. **Compare**: Create second snapshot, compare in DevTools
4. **Identify**: Look for growing object counts (Delta column)
5. **Trace**: Use retainers view to find what's holding references

### Performance Investigation

1. **Profile**: Run with `--cpu-prof`
2. **Load**: Open `.cpuprofile` in Chrome DevTools
3. **Analyze**: Check flame graph for hot paths
4. **Optimize**: Focus on widest flames first

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick debug | `bun --inspect-brk script.ts` |
| Debug tests | `bun --inspect-brk test` |
| Memory check | `bun -e "import{heapStats}from'bun:jsc';console.log(heapStats())"` |
| Network debug | `BUN_CONFIG_VERBOSE_FETCH=curl bun script.ts` |
| CPU profile | `bun --cpu-prof script.ts` |
| Native memory | `MIMALLOC_SHOW_STATS=1 bun script.ts` |

## Quick Reference

### Inspector Flags

| Flag | Description |
|------|-------------|
| `--inspect` | Enable debugger on available port |
| `--inspect=<port>` | Enable debugger on specific port |
| `--inspect-brk` | Break at first line |
| `--inspect-wait` | Wait for debugger attachment |
| `--cpu-prof` | Generate CPU profile |

### Debug URLs

| URL | Purpose |
|-----|---------|
| `debug.bun.sh` | Bun's web debugger |
| `chrome://inspect` | Chrome DevTools (for heap analysis) |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUN_CONFIG_VERBOSE_FETCH` | `1` or `curl` for request logging |
| `MIMALLOC_SHOW_STATS` | `1` to show native memory stats |

### Memory APIs

| API | Import | Purpose |
|-----|--------|---------|
| `writeHeapSnapshot()` | `v8` | Create heap snapshot file |
| `heapStats()` | `bun:jsc` | Get heap statistics |
| `memoryUsage()` | `process` | Get process memory |
| `memoryUsage.rss()` | `process` | Get resident set size |

## Troubleshooting

### Debugger Not Connecting

```bash
# Check if port is in use
lsof -i :6499

# Try explicit port
bun --inspect=9229 script.ts
```

### Breakpoints Not Hit

- Ensure sourcemaps are enabled
- Use `--inspect-brk` for fast-exiting scripts
- Check file paths match in debugger

### VSCode Issues (Windows)

Bun's Unix socket debugging may not work on Windows. Use WSL or the web debugger instead.
