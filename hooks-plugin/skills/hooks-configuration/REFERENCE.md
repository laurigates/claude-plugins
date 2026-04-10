# Hooks Configuration Reference

Detailed schemas, configuration examples, and advanced hook patterns for Claude Code hooks.

## Input Schema Details

Hooks receive JSON via stdin. All events include these common fields:

```json
{
  "session_id": "unique-session-id",
  "transcript_path": "/path/to/conversation.json",
  "cwd": "/current/working/directory",
  "permission_mode": "mode",
  "hook_event_name": "PreToolUse"
}
```

### PreToolUse Additional Fields

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  }
}
```

### PostToolUse Additional Fields

```json
{
  "tool_name": "Bash",
  "tool_input": { ... },
  "tool_response": { ... }
}
```

### SubagentStart Additional Fields

```json
{
  "subagent_type": "Explore",
  "subagent_prompt": "original prompt text",
  "subagent_model": "claude-opus"
}
```

## Output Schema Details

### Exit Codes

- **0**: Success (command allowed)
- **2**: Blocking error (stderr shown to Claude, operation blocked)
- **Other**: Non-blocking error (logged in verbose mode)

### PreToolUse JSON Response

Wrapped in `hookSpecificOutput`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny|ask",
    "permissionDecisionReason": "explanation",
    "updatedInput": { "modified": "input" }
  }
}
```

### Stop/SubagentStop JSON Response

```json
{
  "decision": "block",
  "reason": "required explanation for continuing"
}
```

### SubagentStart JSON Response (Input Modification)

```json
{
  "updatedPrompt": "modified prompt text to inject context or modify behavior"
}
```

### SessionStart JSON Response

Wrapped in `hookSpecificOutput`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Information to inject into session"
  }
}
```

### PermissionRequest JSON Response

```json
{"decision": "approve", "reason": "Read-only git operation"}
{"decision": "deny", "reason": "Destructive root operation blocked"}
```

## Advanced Hook Patterns

### Inject Context for Subagents (SubagentStart)

```bash
#!/bin/bash
INPUT=$(cat)
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.subagent_type // empty')
ORIGINAL_PROMPT=$(echo "$INPUT" | jq -r '.subagent_prompt // empty')

# Add project context to Explore agents
if [ "$SUBAGENT_TYPE" = "Explore" ]; then
    PROJECT_INFO="Project uses TypeScript with Bun. Main source in src/."
    cat << EOF
{
  "updatedPrompt": "$PROJECT_INFO\n\n$ORIGINAL_PROMPT"
}
EOF
fi

exit 0
```

### Desktop Notification on Stop (Stop)

```bash
#!/bin/bash
# Linux
notify-send "Claude Code" "Task completed" 2>/dev/null

# macOS
osascript -e 'display notification "Task completed" with title "Claude Code"' 2>/dev/null

exit 0
```

### Audit Logging (PostToolUse)

```bash
#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // "N/A"')

echo "$(date -Iseconds) | $TOOL | $COMMAND" >> ~/.claude/audit.log
exit 0
```

### Auto-Approve Safe Operations (PermissionRequest)

```bash
#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Auto-approve read-only git operations
if [ "$TOOL" = "Bash" ] && echo "$COMMAND" | grep -Eq '^git (status|log|diff|branch|remote)'; then
  echo '{"decision": "approve", "reason": "Read-only git operation"}'
  exit 0
fi

# Auto-deny destructive operations on root
if [ "$TOOL" = "Bash" ] && echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+/'; then
  echo '{"decision": "deny", "reason": "Destructive root operation blocked"}'
  exit 0
fi

exit 0
```

### Set Up Worktree Environment (WorktreeCreate)

```bash
#!/bin/bash
INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path')

if [ -f "$WORKTREE_PATH/package.json" ]; then
  (cd "$WORKTREE_PATH" && bun install --frozen-lockfile) 2>/dev/null
fi

exit 0
```

### Gate Task Completion (TaskCompleted)

```bash
#!/bin/bash
INPUT=$(cat)
TASK_TITLE=$(echo "$INPUT" | jq -r '.task_title')

if echo "$TASK_TITLE" | grep -qi 'implement\|add\|fix\|refactor'; then
  if ! npm test --bail 2>/dev/null; then
    echo '{"decision": "block", "reason": "Tests must pass before task is accepted."}'
    exit 0
  fi
fi

exit 0
```

## Configuration Examples

### Anti-Pattern Detection

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/hooks-plugin/hooks/bash-antipatterns.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Auto-Format Python Files

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'FILE=$(cat | jq -r \".tool_input.file_path\"); [[ \"$FILE\" == *.py ]] && ruff format \"$FILE\"'"
          }
        ]
      }
    ]
  }
}
```

### Git Reminder on Stop

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'changes=$(git status --porcelain | wc -l); [ $changes -gt 0 ] && echo \"Reminder: $changes uncommitted changes\"'"
          }
        ]
      }
    ]
  }
}
```

## Prompt Hook Configuration

```json
{
  "type": "prompt",
  "prompt": "Evaluate whether all tasks are complete. $ARGUMENTS",
  "model": "haiku",
  "timeout": 30,
  "statusMessage": "Checking completeness..."
}
```

## Agent Hook Configuration

```json
{
  "type": "agent",
  "prompt": "Check for TODO/FIXME comments and debugging artifacts in changed files. $ARGUMENTS",
  "model": "haiku",
  "timeout": 60,
  "statusMessage": "Checking implementation quality..."
}
```

## HTTP Hook Configuration

```json
{
  "type": "http",
  "url": "https://hooks.example.com/pre-tool-use",
  "headers": {
    "Authorization": "Bearer ${HOOKS_API_KEY}"
  },
  "timeout": 30
}
```

Only HTTPS URLs are allowed. Header values support `${ENV_VAR}` expansion.

## Prompt/Agent Hook Response Schema

Both prompt and agent hooks return the same response format:

```json
{"ok": true}
{"ok": false, "reason": "Explanation of what's wrong"}
```

## Stop Hook Loop Prevention

Stop hooks fire every time Claude finishes responding, including after acting on stop hook feedback. Include this check in Stop hook prompts:

```
First: if stop_hook_active is true in the input, respond with {"ok": true} immediately.
```
