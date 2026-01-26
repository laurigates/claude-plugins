# Hooks Plugin

Claude Code hooks for enforcing best practices and workflow automation.

## Overview

This plugin provides pre-built hooks that can be installed in any project to enforce consistent behavior and remind Claude to use the correct tools.

## Available Hooks

### orchestrator-enforcement.sh

Enforces the orchestrator pattern where the main agent investigates and delegates, while subagents implement.

**Tool Access:**

| Category | Orchestrator | Subagent |
|----------|--------------|----------|
| Delegation (Task) | Allowed | Allowed |
| Investigation (Read, Grep, Glob) | Allowed | Allowed |
| Implementation (Edit, Write) | Blocked | Allowed |
| Git read (status, log, diff) | Allowed | Allowed |
| Git write (add, commit, push) | Blocked | Allowed |

**Environment variables:**
- `ORCHESTRATOR_BYPASS=1` - Disable enforcement
- `CLAUDE_IS_SUBAGENT=1` - Grant full access to subagents

### bash-antipatterns.sh

A PreToolUse hook that intercepts Bash commands and blocks those that should use built-in tools instead.

**Detected Anti-patterns:**

| Pattern | Reminder |
|---------|----------|
| `cat file` | Use **Read** tool instead |
| `head`/`tail file` | Use **Read** tool with offset/limit |
| `sed -i` | Use **Edit** tool instead |
| `echo > file` | Use **Write** tool instead |
| `cat > file` | Use **Write** tool instead |
| `timeout cmd` | Remove timeout (human approval time exceeds it) |
| `find` | Use **Glob** tool instead |
| `grep`/`rg` | Use **Grep** tool instead |
| 5+ pipe chain | Simplify with JSON output or awk |
| Multi-grep test parsing | Use `--reporter=json` instead |

## Installation

### Option 1: Copy to Project

Copy the hooks to your project's `.claude/hooks/` directory:

```bash
mkdir -p .claude/hooks
cp hooks-plugin/hooks/*.sh .claude/hooks/
chmod +x .claude/hooks/*.sh
```

Then add to your `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/bash-antipatterns.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Option 2: Reference Plugin Directly

If using this plugin repository, reference the hooks directly:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/hooks-plugin/hooks/bash-antipatterns.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

## How Hooks Work

1. Claude Code triggers the hook before/after tool execution
2. The hook receives JSON input via stdin with tool details
3. The hook validates the command against known anti-patterns
4. If an anti-pattern is detected:
   - Hook exits with code 2 (blocking error)
   - Reminder message is shown to Claude
   - Claude uses the correct tool instead

## Skills

- **hooks-configuration**: Guide for setting up and customizing hooks

## Extending

Add new hooks by:

1. Creating a new `.sh` script in `hooks/`
2. Following the input/output conventions (see existing hooks)
3. Adding configuration to `.claude/settings.json`

## Hook Exit Codes

- **0**: Command allowed
- **2**: Command blocked with reminder (message shown to Claude)
- **Other**: Non-blocking error (logged in verbose mode)
