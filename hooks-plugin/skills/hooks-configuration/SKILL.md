---
model: haiku
name: hooks-configuration
description: |
  Claude Code hooks configuration and development. Covers hook lifecycle events,
  configuration patterns, input/output schemas, and common automation use cases.
  Use when user mentions hooks, automation, PreToolUse, PostToolUse, SessionStart,
  SubagentStart, PermissionRequest, WorktreeCreate, WorktreeRemove, TeammateIdle,
  TaskCompleted, ConfigChange, or needs to enforce consistent behavior in Claude
  Code workflows.
user-invocable: false
allowed-tools: Bash(bash *), Bash(cat *), Read, Write, Edit, Glob, Grep, TodoWrite
created: 2025-12-16
modified: 2026-03-09
reviewed: 2026-03-09
---

# Claude Code Hooks Configuration

Expert knowledge for configuring and developing Claude Code hooks to automate workflows and enforce best practices.

## Core Concepts

**What Are Hooks?**
Hooks are user-defined shell commands that execute at specific points in Claude Code's lifecycle. Unlike relying on Claude to "decide" to run something, hooks provide **deterministic, guaranteed execution**.

**Why Use Hooks?**

- Enforce code formatting automatically
- Block dangerous commands before execution
- Inject context at session start
- Log commands for audit trails
- Send notifications when tasks complete

## Hook Lifecycle Events

| Event                  | When It Fires                              | Key Use Cases                              |
| ---------------------- | ------------------------------------------ | ------------------------------------------ |
| **SessionStart**       | Session begins/resumes                     | Environment setup, context loading         |
| **SessionEnd**         | Session terminates                         | Cleanup, state persistence                 |
| **UserPromptSubmit**   | User submits prompt                        | Input validation, context injection        |
| **PreToolUse**         | Before tool execution                      | Permission control, blocking dangerous ops |
| **PostToolUse**        | After tool completes                       | Auto-formatting, logging, validation       |
| **PostToolUseFailure** | After tool execution fails                 | Retry decisions, error handling            |
| **PermissionRequest**  | Claude requests permission for a tool      | Auto approve/deny without user prompt      |
| **Stop**               | **Main agent** finishes responding         | Notifications, git reminders               |
| **SubagentStart**      | Subagent (Task tool) is about to start     | Input modification, context injection      |
| **SubagentStop**       | **Subagent** finishes                      | Per-task completion evaluation             |
| **WorktreeCreate**     | New git worktree created via EnterWorktree | Worktree setup, dependency install         |
| **WorktreeRemove**     | Worktree removed after session exits       | Cleanup, uncommitted changes alert         |
| **TeammateIdle**       | Teammate in agent team goes idle           | Assign additional tasks to teammate        |
| **TaskCompleted**      | Task in shared task list marked complete   | Validation gates before task acceptance    |
| **PreCompact**         | Before context compaction                  | Transcript backup                          |
| **Notification**       | Claude sends notification                  | Custom alerts                              |
| **ConfigChange**       | Claude Code settings change at runtime     | Audit config changes, validation           |

> **Stop vs SubagentStop**: `Stop` fires at the session level when the main agent finishes a response turn. `SubagentStop` fires when an individual subagent (spawned via the Task tool) completes. Use `Stop` for session-level notifications; use `SubagentStop` for per-task quality gates.

For full schemas, examples, and timeout recommendations for each event, see [.claude/rules/hooks-reference.md](../../.claude/rules/hooks-reference.md).

## Configuration

### File Locations

Hooks are configured in settings files:

- **`~/.claude/settings.json`** - User-level (applies everywhere)
- **`.claude/settings.json`** - Project-level (committed to repo)
- **`.claude/settings.local.json`** - Local project (not committed)

Claude Code merges all matching hooks from all files.

### Frontmatter Hooks (Skills and Commands)

Hooks can also be defined directly in skill and command frontmatter using the `hooks` field:

```yaml
---
name: my-skill
description: A skill with hooks
allowed-tools: Bash, Read
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo 'Pre-tool hook from skill'"
          timeout: 10
---
```

This allows skills and commands to define their own hooks that are active only when that skill/command is in use.

### Basic Structure

```json
{
  "hooks": {
    "EventName": [
      {
        "matcher": "ToolPattern",
        "hooks": [
          {
            "type": "command",
            "command": "your-command-here",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### Matcher Patterns

- **Exact match**: `"Bash"` - matches exactly "Bash" tool
- **Regex patterns**: `"Edit|Write"` - matches either tool
- **Wildcards**: `"Notebook.*"` - matches tools starting with "Notebook"
- **All tools**: `"*"` - matches everything
- **MCP tools**: `"mcp__server__tool"` - targets MCP server tools

## Input Schema

Hooks receive JSON via stdin with these common fields:

```json
{
  "session_id": "unique-session-id",
  "transcript_path": "/path/to/conversation.json",
  "cwd": "/current/working/directory",
  "permission_mode": "mode",
  "hook_event_name": "PreToolUse"
}
```

**PreToolUse additional fields:**

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  }
}
```

**PostToolUse additional fields:**

```json
{
  "tool_name": "Bash",
  "tool_input": { ... },
  "tool_response": { ... }
}
```

**SubagentStart additional fields:**

```json
{
  "subagent_type": "Explore",
  "subagent_prompt": "original prompt text",
  "subagent_model": "claude-opus"
}
```

## Output Schema

### Exit Codes

- **0**: Success (command allowed)
- **2**: Blocking error (stderr shown to Claude, operation blocked)
- **Other**: Non-blocking error (logged in verbose mode)

### JSON Response (optional)

**PreToolUse** (wrapped in `hookSpecificOutput`):

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

**Stop/SubagentStop:**

```json
{
  "decision": "block",
  "reason": "required explanation for continuing"
}
```

**SubagentStart (input modification):**

```json
{
  "updatedPrompt": "modified prompt text to inject context or modify behavior"
}
```

**SessionStart** (wrapped in `hookSpecificOutput`):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Information to inject into session"
  }
}
```

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

## Prompt-Based and Agent-Based Hooks

In addition to command hooks, Claude Code supports LLM-powered hooks for decisions that require judgment.

### Hook Types

| Type | How It Works | Default Timeout | Use When |
|------|-------------|-----------------|----------|
| `command` | Runs a shell command, reads stdin, returns exit code | 600s | Deterministic rules (regex, field checks) |
| `http` | Sends hook data to an HTTPS endpoint, reads JSON response | 30s | Remote/centralized policy enforcement |
| `prompt` | Single-turn LLM call (Haiku), returns `{ok: true/false}` | 30s | Judgment on hook input data alone |
| `agent` | Multi-turn subagent with tool access, returns `{ok: true/false}` | 60s | Verification needing file/tool access |

### Additional Hook Handler Fields

- **`async: true`**: Fire-and-forget for command hooks (non-blocking, exit code ignored)
- **`once: true`**: Run only once per session; subsequent triggers are skipped

### HTTP Hook Configuration

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

### Supported Events

Prompt and agent hooks work on: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`, `SubagentStop`, `TaskCompleted`, `UserPromptSubmit`.

### CLAUDE_ENV_FILE (SessionStart)

SessionStart hooks can write environment variables that persist for the session via `CLAUDE_ENV_FILE`:

```bash
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "NODE_ENV=development" >> "$CLAUDE_ENV_FILE"
fi
```

All other events (`SessionStart`, `SessionEnd`, `PreCompact`, etc.) support only `command` hooks.

### Prompt Hook Configuration

```json
{
  "type": "prompt",
  "prompt": "Evaluate whether all tasks are complete. $ARGUMENTS",
  "model": "haiku",
  "timeout": 30,
  "statusMessage": "Checking completeness..."
}
```

### Agent Hook Configuration

```json
{
  "type": "agent",
  "prompt": "Check for TODO/FIXME comments and debugging artifacts in changed files. $ARGUMENTS",
  "model": "haiku",
  "timeout": 60,
  "statusMessage": "Checking implementation quality..."
}
```

> **Note**: Prefer `command` hooks over `agent` hooks when the logic is deterministic. For example, test verification (detect changed files → find test runner → run tests) is better as a bash script than an agent hook — it eliminates LLM latency on every invocation.

### Response Schema (both types)

```json
{"ok": true}
{"ok": false, "reason": "Explanation of what's wrong"}
```

### Stop Hook Loop Prevention

Stop hooks fire every time Claude finishes responding, including after acting on stop hook feedback. Include this check in Stop hook prompts:

```
First: if stop_hook_active is true in the input, respond with {"ok": true} immediately.
```

For the full decision guide on when to use each hook type, see [.claude/rules/prompt-agent-hooks.md](../../.claude/rules/prompt-agent-hooks.md).

## Handling Blocked Commands

When a PreToolUse hook blocks a command:

| Situation                 | Action                                                           |
| ------------------------- | ---------------------------------------------------------------- |
| Hook suggests alternative | Use the suggested tool/approach                                  |
| Alternative won't work    | Ask user to run command manually                                 |
| User says "proceed"       | Still blocked - explain and provide command for manual execution |

**Critical**: User permission does NOT bypass hooks. Retrying a blocked command will fail again.

**When command is legitimately needed:**

1. Explain why the command is required
2. Describe alternatives considered and why they won't work
3. Provide exact command for user to run manually
4. Let user decide

Example response:

```
The hook blocked `git reset --hard abc123` because it's usually unnecessary.

I considered:
- `git pull`: Won't work because we need to discard local commits, not merge
- `git restore`: Only handles file changes, not commit history

If you need to proceed, please run manually:
git reset --hard abc123

This is needed because [specific justification].
```

## Best Practices

**Script Development:**

1. Always read input from stdin with `cat`
2. Use `jq` for JSON parsing
3. Quote all variables to prevent injection
4. Exit with code 2 to block, 0 to allow
5. Write blocking messages to stderr
6. Keep hooks fast (< 5 seconds)

**Configuration:**

1. Use `$CLAUDE_PROJECT_DIR` for portable paths
2. Set explicit timeouts (default: 10 minutes / 600s as of 2.1.50)
3. Use specific matchers over wildcards
4. Test hooks manually before enabling

**Security:**

1. Validate all inputs
2. Use absolute paths
3. Avoid touching `.env` or `.git/` directly
4. Review hook code before deployment

## Debugging

**Verify hook registration:**

```
/hooks
```

**Enable debug logging:**

```bash
claude --debug
```

**Test hooks manually:**

```bash
echo '{"tool_input": {"command": "cat file.txt"}}' | bash your-hook.sh
echo $?  # Check exit code
```

## Available Hooks in This Plugin

- **bash-antipatterns.sh**: Detects when Claude uses shell commands instead of built-in tools (cat, grep, sed, timeout, etc.)

See `hooks/README.md` for full documentation.
