# Claude Code Hooks

This directory contains hooks that enforce best practices and remind Claude to use the correct tools.

## orchestrator-enforcement.sh

A PreToolUse hook that enforces the orchestrator pattern - orchestrators investigate and delegate, subagents implement.

### What It Does

| Tool Category | Behavior |
|--------------|----------|
| **Delegation** (Task) | Always allowed |
| **Investigation** (Read, Grep, Glob, WebFetch, WebSearch) | Always allowed |
| **Planning** (TodoWrite) | Always allowed |
| **Implementation** (Edit, Write, NotebookEdit) | Blocked - must delegate |
| **Git read** (status, log, diff, branch, show) | Allowed |
| **Git write** (add, commit, push, merge) | Blocked - must delegate |
| **GitHub CLI read** (view, list, checks) | Allowed |
| **GitHub CLI write** (create, edit, merge) | Blocked - must delegate |

### Configuration

Environment variables:
- `ORCHESTRATOR_BYPASS=1` - Disable hook entirely
- `CLAUDE_IS_SUBAGENT=1` - Grant full tool access (set by parent agent)

### Usage

Add to `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|NotebookEdit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/orchestrator-enforcement.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

When spawning subagents via Task, set the environment:

```json
{
  "env": {
    "CLAUDE_IS_SUBAGENT": "1"
  }
}
```

### Testing

```bash
# Should block Edit for orchestrator
echo '{"tool_name": "Edit"}' | bash orchestrator-enforcement.sh
# Returns: {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",...}}

# Should allow with subagent flag
echo '{"tool_name": "Edit"}' | CLAUDE_IS_SUBAGENT=1 bash orchestrator-enforcement.sh
# Returns: (empty - allowed)

# Should allow Read
echo '{"tool_name": "Read"}' | bash orchestrator-enforcement.sh
# Returns: (empty - allowed)
```

---

## bash-antipatterns.sh

A PreToolUse hook that intercepts Bash commands and blocks those that should use built-in tools instead.

### Anti-patterns Detected

| Pattern | Reminder |
|---------|----------|
| `cat file` | Use **Read** tool instead |
| `head`/`tail file` | Use **Read** tool with offset/limit |
| `sed -i` | Use **Edit** tool instead |
| `echo > file` | Use **Write** tool instead |
| `cat > file` | Use **Write** tool instead |
| `timeout cmd` | Remove timeout (Bash tool has its own, human approval time exceeds it anyway) |
| `find` | Use **Glob** tool instead |
| `grep`/`rg` | Use **Grep** tool instead |
| `ls *pattern*` | Consider **Glob** tool |
| `cat/tail ...tasks/*.output` | Use **TaskOutput** tool instead |
| `sleep && cat/tail` | Use **TaskOutput** tool with block parameter |
| `git X && git Y` | Run git commands as separate Bash calls (avoids index.lock race condition) |

### How It Works

1. The hook receives JSON input from Claude Code containing the Bash command
2. It extracts the command and checks against known anti-patterns
3. If an anti-pattern is detected, it exits with code 2 (blocking error) and prints a helpful reminder
4. The reminder is shown to Claude, who will then use the correct tool

### Configuration

The hook is configured in `.claude/settings.json`:

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

### Testing

To test the hook manually:

```bash
echo '{"tool_input": {"command": "cat README.md"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 2 (blocked)

echo '{"tool_input": {"command": "git status"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 0 (allowed)

echo '{"tool_input": {"command": "git stash && git checkout -b branch"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 2 (blocked - chained git commands cause lock race conditions)
```

### Customization

Edit `bash-antipatterns.sh` to:
- Add new anti-patterns
- Modify reminder messages
- Adjust detection regex patterns
- Whitelist specific commands

### Exit Codes

- **0**: Command allowed
- **2**: Command blocked with reminder (Claude sees the message)
