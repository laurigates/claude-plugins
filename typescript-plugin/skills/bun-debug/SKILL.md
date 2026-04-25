---
description: |
  Launch a script with Bun's debugger enabled via `--inspect`. Use when the user
  wants to interactively debug a TypeScript/JavaScript file, break at the first
  line of a fast-exiting script, wait for a debugger to attach before running,
  or debug tests via `bun --inspect-brk test`. Triggers: "debug this script",
  "attach debugger", "open debug.bun.sh", "break on start".
args: <file> [--brk] [--wait] [--port=<port>]
allowed-tools: Bash, BashOutput, Read
argument-hint: <script.ts> [--brk] [--wait] [--port=9229]
created: 2026-01-22
modified: 2026-04-25
reviewed: 2026-04-25
name: bun-debug
---

# /bun:debug

Launch a script with Bun's debugger enabled for interactive debugging.

## When to Use This Skill

| Use this skill when... | Use typescript-debugging instead when... |
|---|---|
| Attaching an interactive debugger to a Bun script via `--inspect` | Diagnosing TypeScript compile errors or type mismatches |
| Breaking at the first line of a fast-exiting script (`--inspect-brk`) | Setting up VSCode launch configurations for non-Bun runtimes |
| Debugging Bun tests with `bun --inspect-brk test` | Use bun-test when you just want to run tests, not step through them |
| Waiting for a debugger to attach before execution | Use bun-build when reproducing a build-time error |

## Parameters

- `file` (required): Script file to debug
- `--brk`: Break at first line (for fast-exiting scripts)
- `--wait`: Wait for debugger to attach before running
- `--port=<port>`: Use specific port (default: auto-assigned)

## Execution

**Standard debug (opens debug URL):**
```bash
bun --inspect $FILE
```

**Break at first line:**
```bash
bun --inspect-brk $FILE
```

**Wait for debugger attachment:**
```bash
bun --inspect-wait $FILE
```

**Custom port:**
```bash
bun --inspect=$PORT $FILE
```

**Debug tests:**
```bash
bun --inspect-brk test $PATTERN
```

## Output

The command outputs a debug URL:
```
------------------- Bun Inspector -------------------
Listening: ws://localhost:6499/
Open: debug.bun.sh/#localhost:6499
-----------------------------------------------------
```

## Post-launch

1. Report the debug URL to user
2. Explain how to connect:
   - Open `debug.bun.sh/#localhost:<port>` in browser
   - Or use VSCode with Bun extension attached to the WebSocket URL
3. Remind about breakpoint controls (F8 continue, F10 step over, F11 step into)

## VSCode Integration

For VSCode debugging, suggest adding to `.vscode/launch.json`:

```json
{
  "type": "bun",
  "request": "launch",
  "name": "Debug",
  "program": "${file}",
  "stopOnEntry": true
}
```
