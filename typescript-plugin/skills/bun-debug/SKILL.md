---
description: Debug TypeScript/JavaScript with Bun inspector
args: <file> [--brk] [--wait] [--port=<port>]
allowed-tools: Bash, BashOutput, Read
argument-hint: <script.ts> [--brk] [--wait] [--port=9229]
created: 2026-01-22
modified: 2026-01-22
reviewed: 2026-01-22
name: bun-debug
---

# /bun:debug

Launch a script with Bun's debugger enabled for interactive debugging.

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
