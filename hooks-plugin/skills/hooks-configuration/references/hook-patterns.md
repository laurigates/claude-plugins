# hooks-configuration: hook script patterns

## Common Hook Patterns

### Block Dangerous Commands (PreToolUse)

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block rm -rf /
if echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+/'; then
    echo "BLOCKED: Refusing to run destructive command on root" >&2
    exit 2
fi

exit 0
```

### Auto-Format After Edits (PostToolUse)

```bash
#!/bin/bash
INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ "$FILE" == *.py ]]; then
    ruff format "$FILE" 2>/dev/null
    ruff check --fix "$FILE" 2>/dev/null
elif [[ "$FILE" == *.ts ]] || [[ "$FILE" == *.tsx ]]; then
    prettier --write "$FILE" 2>/dev/null
fi

exit 0
```

### Remind About Built-in Tools (PreToolUse)

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if echo "$COMMAND" | grep -Eq '^\s*cat\s+[^|><]'; then
    echo "REMINDER: Use the Read tool instead of 'cat'" >&2
    exit 2
fi

exit 0
```

### Load Context at Session Start (SessionStart)

```bash
#!/bin/bash
GIT_STATUS=$(git status --short 2>/dev/null | head -5)
BRANCH=$(git branch --show-current 2>/dev/null)

CONTEXT="Current branch: $BRANCH\nPending changes:\n$GIT_STATUS"
jq -n --arg ctx "$CONTEXT" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ctx
  }
}'
```

### Background Subshell Pattern (Recommended for Slow Hooks)

When a hook needs to do slow work (logging, API calls) without blocking, run it in a background subshell:

```bash
#!/bin/bash
# Exits instantly; slow work continues in background
(
  echo "$(date): Session ended" >> ~/.claude/session.log
  # Any other slow work...
) &>/dev/null &
exit 0
```

Why this works: `( )` creates a subshell, `&` runs it in background, `&>/dev/null` prevents stdout/stderr from blocking, `exit 0` returns success immediately.
