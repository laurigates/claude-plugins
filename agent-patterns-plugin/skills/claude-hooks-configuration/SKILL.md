---
model: haiku
name: claude-hooks-configuration
description: |
  Set up Claude Code lifecycle hooks and event handlers in settings.json. Use when you
  want to trigger a script on session start, run a hook before or after tool calls
  (PreToolUse/PostToolUse), configure hook timeouts to prevent cancellation errors,
  or debug hooks that aren't firing correctly.
allowed-tools: Bash(cat *), Bash(bash *), Read, Write, Edit, Grep, Glob, TodoWrite
created: 2025-12-27
modified: 2026-02-05
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

**Solutions** (in order of preference):
1. **Background subshell** - Run slow operations in background, exit immediately
2. **Explicit timeout** - Add `timeout` field to hook configuration

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

### Recommended: Background Subshell Pattern

The most portable and robust solution is to run slow operations in a background subshell and exit immediately:

```bash
#!/bin/bash
# ~/.claude/session-logger.sh
# Exits instantly, work continues in background

(
  # All slow operations go here
  echo "$(date): Session ended" >> ~/.claude/session.log
  curl -s -X POST "https://api.example.com/log" -d "session_end=$(date)"
  # Any other slow work...
) &>/dev/null &

exit 0
```

**Why this works:**
- `( )` creates a subshell for the commands
- `&` runs the subshell in background
- `&>/dev/null` prevents stdout/stderr from blocking
- `exit 0` returns success immediately

**Comparison of approaches:**

| Approach | Portability | Speed | Notes |
|----------|-------------|-------|-------|
| `( ) &` | bash, zsh, sh | Instant | Recommended |
| `disown` | Bash-only | Instant | Not POSIX |
| `nohup` | POSIX | Slight overhead | Overkill for hooks |

### Alternative: Increase Timeout

If you need synchronous execution, add explicit timeout to settings:

```bash
cat ~/.claude/settings.json | jq '.hooks'
# Edit to add "timeout": <seconds> to each hook
```

### Script Optimization Patterns

| Optimization | Pattern |
|--------------|---------|
| Background subshell | `( commands ) &>/dev/null &` |
| Fast test modes | `--bail=1`, `-x`, `--dots` |
| Skip heavy operations | Conditional execution |
| Parallel execution | Use `&` and `wait` |

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

1. **Use background subshell** - Wrap slow operations in `( ) &>/dev/null &` and `exit 0`
2. **Set explicit timeouts** - Add `timeout` field for hooks requiring synchronous execution
3. **Test hook timing** - Use `time bash ~/.claude/script.sh` to measure execution
4. **Redirect all output** - Use `&>/dev/null` to prevent blocking on stdout/stderr
5. **Apply `/hooks` menu** - Use Claude Code's hook menu to reload settings after changes
