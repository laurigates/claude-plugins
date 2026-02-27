# Hook System Reference (Claude Code 2.1.50+)

Comprehensive reference for Claude Code hook events, schemas, and patterns. This supplements `.claude/rules/handling-blocked-hooks.md` with full event coverage. For guidance on when to use `type: "prompt"` and `type: "agent"` hooks instead of `type: "command"`, see `.claude/rules/prompt-agent-hooks.md`.

## Hook Events

### Core Session Events

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `SessionStart` | Session begins, resumes, or after `/clear` | matcher: `"startup"`, `"resume"`, `"clear"`, `"compact"`, `""` (all) |
| `SessionEnd` | Session terminates | none |
| `UserPromptSubmit` | User submits a prompt | none |
| `PreCompact` | Before context compaction | none |

### Tool Execution Events

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `PreToolUse` | Before a tool executes | tool name (regex) |
| `PostToolUse` | After a tool completes | tool name (regex) |
| `PermissionRequest` | Claude requests permission for a tool | tool name (regex) |

### Agent Lifecycle Events

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `Stop` | **Main agent** finishes responding | none |
| `SubagentStart` | A subagent (Task tool) is about to start | subagent type |
| `SubagentStop` | A **subagent** finishes | none |

### Worktree Events (2.1.50+)

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `WorktreeCreate` | A new git worktree is created via `EnterWorktree` | none |
| `WorktreeRemove` | A worktree is removed after a session exits | none |

### Agent Teams Events (2.1.50+)

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `TeammateIdle` | A teammate in an agent team goes idle | teammate name |
| `TaskCompleted` | A task in the shared task list is marked complete | task list name |

### Notification and Config Events

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `Notification` | Claude sends a desktop/system notification | none |
| `ConfigChange` | Claude Code settings change at runtime (2.1.50+) | config key (regex) |

---

## Stop vs SubagentStop Distinction

These are the two most commonly confused events:

| Aspect | `Stop` | `SubagentStop` |
|--------|--------|----------------|
| **Fires when** | Main session agent completes a response | A subagent spawned via the Task tool finishes |
| **Scope** | Session-level | Per-subagent |
| **Use case** | Git reminders, session-end notifications | Per-task validation, quality gates |
| **Blocking** | Can block next user turn with `"decision": "block"` | Can block subagent from being considered complete |
| **Frequency** | Once per response cycle | Once per Task tool invocation |

```json
// Stop — blocks the session from completing the turn
{
  "decision": "block",
  "reason": "Uncommitted changes detected. Please commit before finishing."
}

// SubagentStop — blocks the subagent result from being accepted
{
  "decision": "block",
  "reason": "Tests must pass before this task is considered complete."
}
```

---

## Timeouts

As of Claude Code 2.1.50, the default hook timeout is **10 minutes (600 seconds)**, increased from the previous 60-second default.

| Hook Type | Recommended Timeout | Notes |
|-----------|---------------------|-------|
| `SessionStart` | 300–600s | Dependency installs can be slow |
| `SessionEnd` | 60–120s | Logging and cleanup |
| `PreToolUse` | 10–30s | Keep fast to avoid blocking tool execution |
| `PostToolUse` | 30–120s | Formatting, linting, logging |
| `Stop` / `SubagentStop` | 30–60s | Notifications, git checks |
| `PermissionRequest` | 5–15s | Must respond quickly for good UX |
| `WorktreeCreate` | 60–300s | May involve setup scripts |
| `WorktreeRemove` | 30–60s | Cleanup operations |
| `TeammateIdle` | 10–30s | Should assign work quickly |
| `TaskCompleted` | 30–60s | Validation before acceptance |

Set timeout explicitly even though the default is now 10 minutes — explicit timeouts document intent:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/bash-validator.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

---

## Input Schemas

### Common Fields (all events)

```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/conversation.json",
  "cwd": "/current/working/directory",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse"
}
```

### PreToolUse / PostToolUse

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  },
  "tool_response": { }
}
```
`tool_response` is only present for `PostToolUse`.

### PermissionRequest (2.1.50+)

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf build/"
  },
  "permission_type": "tool_use",
  "description": "Run shell command: rm -rf build/"
}
```

### SubagentStart

```json
{
  "subagent_type": "Explore",
  "subagent_prompt": "original prompt text",
  "subagent_model": "claude-sonnet-4-6"
}
```

### WorktreeCreate (2.1.50+)

```json
{
  "worktree_path": "/path/to/worktrees/feature-branch",
  "worktree_branch": "feature-branch",
  "worktree_name": "feature-branch"
}
```

### WorktreeRemove (2.1.50+)

```json
{
  "worktree_path": "/path/to/worktrees/feature-branch",
  "worktree_branch": "feature-branch",
  "worktree_name": "feature-branch",
  "had_changes": false
}
```

### TeammateIdle (2.1.50+)

```json
{
  "teammate_name": "researcher",
  "teammate_id": "agent-uuid",
  "team_name": "my-team",
  "last_task_id": "task-123",
  "last_task_status": "completed"
}
```

### TaskCompleted (2.1.50+)

```json
{
  "task_id": "task-123",
  "task_title": "Implement authentication",
  "task_owner": "researcher",
  "team_name": "my-team",
  "completed_at": "2026-02-25T14:00:00Z"
}
```

### ConfigChange (2.1.50+)

```json
{
  "config_key": "permissions.allow",
  "old_value": ["Bash(git *)"],
  "new_value": ["Bash(git *)", "Bash(npm *)"],
  "source_file": ".claude/settings.json"
}
```

---

## Output Schemas

### PreToolUse — Allow, Deny, or Modify

```json
{
  "permissionDecision": "allow",
  "permissionDecisionReason": "Command matches approved pattern"
}
```

```json
{
  "permissionDecision": "deny",
  "permissionDecisionReason": "Destructive operation blocked by policy"
}
```

```json
{
  "permissionDecision": "ask",
  "permissionDecisionReason": "Unusual command, require human confirmation"
}
```

Optionally modify the tool input before execution:

```json
{
  "permissionDecision": "allow",
  "updatedInput": {
    "command": "npm test -- --bail=1"
  }
}
```

### PermissionRequest — Auto Approve/Deny (2.1.50+)

```json
{
  "decision": "approve",
  "reason": "Command matches trusted pattern"
}
```

```json
{
  "decision": "deny",
  "reason": "Operation not permitted in this environment"
}
```

### Stop / SubagentStop — Block or Allow

```json
{
  "decision": "block",
  "reason": "Uncommitted changes detected. Commit your work before finishing."
}
```

Return nothing (exit 0) to allow the stop.

### SubagentStart — Modify Prompt

```json
{
  "updatedPrompt": "Additional context injected...\n\nOriginal prompt here"
}
```

### SessionStart — Inject Context

```json
{
  "additionalContext": "Branch: main\nUncommitted: 0 files\nTests: passing"
}
```

### TaskCompleted — Gate Completion (2.1.50+)

```json
{
  "decision": "block",
  "reason": "Tests must pass before this task is accepted. Run: npm test"
}
```

---

## PermissionRequest Hook Pattern

`PermissionRequest` hooks fire when Claude requests permission for an operation (e.g., in default permission mode). They allow automated approval/denial without user interaction.

### Auto-Approve Known Safe Patterns

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

# Auto-approve npm test runs
if [ "$TOOL" = "Bash" ] && echo "$COMMAND" | grep -Eq '^npm (test|run test)'; then
  echo '{"decision": "approve", "reason": "Test execution approved"}'
  exit 0
fi

# All other requests: require human approval (default behavior)
exit 0
```

### Auto-Deny Dangerous Patterns

```bash
#!/bin/bash
INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block destructive filesystem operations
if [ "$TOOL" = "Bash" ] && echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+/'; then
  echo '{"decision": "deny", "reason": "Destructive root filesystem operation blocked"}'
  exit 0
fi

# Block force push to protected branches
if [ "$TOOL" = "Bash" ] && echo "$COMMAND" | grep -Eq 'git push.*--force.*main|git push.*--force.*master'; then
  echo '{"decision": "deny", "reason": "Force push to protected branch blocked"}'
  exit 0
fi

exit 0
```

---

## New Event Examples

### WorktreeCreate — Set Up Worktree Environment

```bash
#!/bin/bash
# .claude/hooks/worktree-create.sh
INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path')
BRANCH=$(echo "$INPUT" | jq -r '.worktree_branch')

# Install dependencies in the new worktree
if [ -f "$WORKTREE_PATH/package.json" ]; then
  (cd "$WORKTREE_PATH" && bun install --frozen-lockfile) 2>/dev/null
fi

echo "Worktree ready: $BRANCH at $WORKTREE_PATH" >&2
exit 0
```

### WorktreeRemove — Clean Up After Worktree

```bash
#!/bin/bash
# .claude/hooks/worktree-remove.sh
INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path')
HAD_CHANGES=$(echo "$INPUT" | jq -r '.had_changes')

# Alert if worktree had uncommitted changes
if [ "$HAD_CHANGES" = "true" ]; then
  echo "WARNING: Worktree $WORKTREE_PATH removed with uncommitted changes" >&2
fi

exit 0
```

### TeammateIdle — Assign Work to Idle Teammates

```bash
#!/bin/bash
# .claude/hooks/teammate-idle.sh
INPUT=$(cat)
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name')
TEAM=$(echo "$INPUT" | jq -r '.team_name')

# Log idle event for team lead awareness
echo "$(date -Iseconds): Teammate $TEAMMATE is idle in team $TEAM" >> ~/.claude/team-activity.log

exit 0
```

### TaskCompleted — Validate Before Accepting

```bash
#!/bin/bash
# .claude/hooks/task-completed.sh
INPUT=$(cat)
TASK_TITLE=$(echo "$INPUT" | jq -r '.task_title')

# Run tests if implementation task
if echo "$TASK_TITLE" | grep -qi 'implement\|add\|fix\|refactor'; then
  if ! npm test --bail 2>/dev/null; then
    echo '{"decision": "block", "reason": "Tests must pass before task is accepted. Fix failing tests first."}'
    exit 0
  fi
fi

exit 0
```

### ConfigChange — Audit Configuration Changes

```bash
#!/bin/bash
# .claude/hooks/config-change.sh
INPUT=$(cat)
CONFIG_KEY=$(echo "$INPUT" | jq -r '.config_key')
NEW_VALUE=$(echo "$INPUT" | jq -c '.new_value')

# Audit log all config changes
echo "$(date -Iseconds) | CONFIG | $CONFIG_KEY = $NEW_VALUE" >> ~/.claude/config-audit.log

exit 0
```

---

## Exit Codes

| Code | Meaning | Effect |
|------|---------|--------|
| `0` | Success | Operation allowed/continues |
| `2` | Blocking error | Operation blocked; stderr shown to Claude |
| Other | Non-blocking error | Logged in verbose mode, operation continues |

---

## Configuration Example

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/permission-request.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "WorktreeCreate": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/worktree-create.sh",
            "timeout": 300
          }
        ]
      }
    ],
    "WorktreeRemove": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/worktree-remove.sh",
            "timeout": 60
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/teammate-idle.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/task-completed.sh",
            "timeout": 60
          }
        ]
      }
    ],
    "ConfigChange": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash .claude/hooks/config-change.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

---

## Quick Reference

### All Hook Events

| Event | Category | New in 2.1.50 |
|-------|----------|---------------|
| `SessionStart` | Session | |
| `SessionEnd` | Session | |
| `UserPromptSubmit` | Session | |
| `PreCompact` | Session | |
| `PreToolUse` | Tool | |
| `PostToolUse` | Tool | |
| `PermissionRequest` | Tool | ✓ |
| `Stop` | Agent | |
| `SubagentStart` | Agent | |
| `SubagentStop` | Agent | |
| `WorktreeCreate` | Worktree | ✓ |
| `WorktreeRemove` | Worktree | ✓ |
| `TeammateIdle` | Teams | ✓ |
| `TaskCompleted` | Teams | ✓ |
| `Notification` | Misc | |
| `ConfigChange` | Misc | ✓ |
