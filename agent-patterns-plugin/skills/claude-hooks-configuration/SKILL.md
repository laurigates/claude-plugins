---
name: Claude Code Hooks Configuration
description: Configure Claude Code lifecycle hooks with proper timeout settings to prevent hook cancellation errors.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-12-27
modified: 2025-12-27
reviewed: 2025-12-27
---

# Claude Code Hooks Configuration

## Core Expertise

Configure Claude Code lifecycle hooks (SessionStart, SessionEnd, Stop, PreToolUse, PostToolUse) with proper timeout settings to prevent "Hook cancelled" errors during session management.

## Hook Types

| Hook | Trigger | Default Timeout |
|------|---------|-----------------|
| `SessionStart` | When Claude Code session begins | 60 seconds |
| `SessionEnd` | When session ends or `/clear` runs | 60 seconds |
| `Stop` | When assistant stops responding | 60 seconds |
| `PreToolUse` | Before a tool executes | 60 seconds |
| `PostToolUse` | After a tool completes | 60 seconds |

## Common Issue: Hook Cancelled Error

```
SessionEnd hook [bash ~/.claude/session-logger.sh] failed: Hook cancelled
```

**Root cause**: Hook execution exceeds the 60-second default timeout.

**Solution**: Add explicit `timeout` field to hook configuration.

## Hook Configuration

### Location

Hooks are configured in `.claude/settings.json`:
- **User-level**: `~/.claude/settings.json`
- **Project-level**: `<project>/.claude/settings.json`

### Structure with Timeout

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/session-logger.sh",
            "timeout": 120
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/session-setup.sh",
            "timeout": 180
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/stop-hook-git-check.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### Timeout Guidelines

| Hook Type | Recommended Timeout | Use Case |
|-----------|---------------------|----------|
| SessionStart | 120-300s | Tests, linters, dependency checks |
| SessionEnd | 60-120s | Logging, cleanup, state saving |
| Stop | 30-60s | Git status checks, quick validations |
| PreToolUse | 10-30s | Quick validations |
| PostToolUse | 30-60s | Logging, notifications |

## Fixing Timeout Issues

### Step 1: Identify the Hook

Check current hook configuration:

```bash
cat ~/.claude/settings.json | jq '.hooks'
```

### Step 2: Add Timeout Field

Edit the settings to add explicit timeout:

```bash
# Edit ~/.claude/settings.json
# Add "timeout": <seconds> to each hook that's timing out
```

### Step 3: Optimize Hook Script

If the hook is genuinely slow, optimize the script:

| Optimization | Pattern |
|--------------|---------|
| Parallel execution | Use `&` and `wait` |
| Fast test modes | `--bail=1`, `-x`, `--dots` |
| Skip heavy operations | Conditional execution |
| Background processing | Detach slow operations |

### Example: Optimized Session Logger

```bash
#!/bin/bash
# ~/.claude/session-logger.sh
# Fast session logging with background processing

# Quick synchronous logging (< 1 second)
echo "$(date): Session ended" >> ~/.claude/session.log

# Heavy operations in background (detached)
{
  # Analytics, syncing, etc.
  curl -s -X POST "https://api.example.com/log" -d "session_end=$(date)"
} &>/dev/null &

exit 0  # Return immediately
```

## Related: Starship Timeout

If you see:
```
[WARN] - (starship::utils): Executing command "...node" timed out.
```

This is a separate starship issue. Fix by adding to `~/.config/starship.toml`:

```toml
command_timeout = 1000  # 1 second (default is 500ms)
```

For slow node version detection:
```toml
[nodejs]
disabled = false
detect_files = ["package.json"]  # Skip .nvmrc to speed up detection

[command]
command_timeout = 2000  # Increase if still timing out
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| View hooks config | `cat ~/.claude/settings.json \| jq '.hooks'` |
| Test hook script | `time bash ~/.claude/session-logger.sh` |
| Find slow operations | `bash -x ~/.claude/session-logger.sh 2>&1 \| head -50` |
| Check starship config | `starship config` |

## Quick Reference

| Setting | Location | Default |
|---------|----------|---------|
| Hook timeout | `.claude/settings.json` → hook → `timeout` | 60s |
| Starship timeout | `~/.config/starship.toml` → `command_timeout` | 500ms |
| Node detection | `~/.config/starship.toml` → `[nodejs]` | Auto |

## Error Handling

| Error | Cause | Fix |
|-------|-------|-----|
| Hook cancelled | Timeout exceeded | Add `"timeout": 120` |
| Hook failed | Script error | Check exit code, add error handling |
| Command not found | Missing script | Verify script path and permissions |
| Permission denied | Script not executable | `chmod +x ~/.claude/script.sh` |

## Best Practices

1. **Set explicit timeouts** - Always specify timeout for hooks that may take >30s
2. **Use fast patterns** - Optimize scripts to complete quickly
3. **Detach slow operations** - Background heavy work and exit immediately
4. **Test hook timing** - Use `time` to measure actual execution
5. **Apply `/hooks` menu** - Use Claude Code's hook menu to reload settings
