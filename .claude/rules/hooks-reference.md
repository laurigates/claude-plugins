---
paths:
  - ".claude/hooks/**"
  - "**/.claude-plugin/plugin.json"
  - ".claude/settings*.json"
---

# Hook System Reference (Claude Code 2.1.76+)

Comprehensive reference for Claude Code hook events, schemas, and patterns. This supplements `.claude/rules/handling-blocked-hooks.md` with full event coverage. For guidance on when to use `type: "prompt"`, `type: "agent"`, and `type: "http"` hooks instead of `type: "command"`, see `.claude/rules/prompt-agent-hooks.md`.

> **Note (2.1.142)**: `SessionStart`, `Setup`, and `SubagentStart` accept only `type: "command"` hooks. Configuring a prompt- or agent-type hook for these events now surfaces a clear "use a command-type hook instead" error at load time, rather than silently ignoring the handler. See `.claude/rules/prompt-agent-hooks.md` for the events that do support prompt and agent hooks.

## Hook Events

### Core Session Events

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `SessionStart` | Session begins, resumes, or after `/clear` | matcher: `"startup"`, `"resume"`, `"clear"`, `"compact"`, `""` (all) |
| `SessionEnd` | Session terminates | none |
| `UserPromptSubmit` | User submits a prompt | none |
| `PreCompact` | Before context compaction | none |
| `PostCompact` | After context compaction completes (2.1.76+) | matcher: `"manual"`, `"auto"`, `""` (all) |

### Tool Execution Events

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `PreToolUse` | Before a tool executes | tool name (regex) |
| `PostToolUse` | After a tool completes | tool name (regex) |
| `PostToolUseFailure` | After a tool execution fails | tool name (regex) |
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

> **Note (2.1.141)**: Hooks fired after an `EnterWorktree` switch used to receive a `transcript_path` pointing at the pre-switch working directory, breaking transcript-reading helpers. The path now reflects the new worktree.

### Agent Teams Events (2.1.50+)

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `TeammateIdle` | A teammate in an agent team goes idle | teammate name |
| `TaskCompleted` | A task in the shared task list is marked complete | task list name |

### MCP Events (2.1.76+)

| Event | When It Fires | Matcher Support |
|-------|--------------|-----------------|
| `Elicitation` | An MCP server requests structured user input mid-task | MCP server name |
| `ElicitationResult` | After the user responds to an MCP elicitation dialog | MCP server name |

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

Default timeouts vary by hook type:

| Hook Type | Default Timeout |
|-----------|-----------------|
| `command` | 600 seconds (10 minutes) |
| `prompt` | 30 seconds |
| `agent` | 60 seconds |

The command hook default was increased from 60 seconds in Claude Code 2.1.50.

| Hook Type | Recommended Timeout | Notes |
|-----------|---------------------|-------|
| `SessionStart` | 300–600s | Dependency installs can be slow |
| `SessionEnd` | 60–120s | Configurable via `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` (fixed in 2.1.74; was hard-capped at 1.5s) |
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

## Command Invocation Forms (2.1.139+)

Command hooks support two invocation forms:

| Form | Field | Shell? | Quoting | When to use |
|------|-------|--------|---------|-------------|
| Shell form | `command` (string) | Yes — runs via `sh -c` | Caller responsible for quoting | Pipes, redirects, shell builtins |
| Exec form | `args` (string array) | No — spawns directly | Path placeholders never need quoting | Path arguments with spaces, untrusted input |

```json
{
  "type": "command",
  "args": ["bash", "${CLAUDE_PLUGIN_ROOT}/hooks/validate.sh", "${CLAUDE_PROJECT_DIR}"],
  "timeout": 30
}
```

The exec form (`args: string[]`) spawns the command directly without a shell, so path placeholders like `${CLAUDE_PROJECT_DIR}` are passed as a single argument even when they contain spaces. Prefer the exec form when the only reason to use a shell would be quoting paths.

---

## Input Schemas

### Common Fields (all events)

```json
{
  "session_id": "abc-123",
  "transcript_path": "/path/to/conversation.json",
  "cwd": "/current/working/directory",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "effort": {"level": "high"}
}
```

### PreToolUse / PostToolUse / PostToolUseFailure

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  },
  "tool_response": { },
  "duration_ms": 1234
}
```
`tool_response` is only present for `PostToolUse` and `PostToolUseFailure`.

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

### PostCompact (2.1.76+)

```json
{
  "trigger": "auto",
  "compact_summary": "Summary of compacted conversation content..."
}
```

`trigger` is `"manual"` or `"auto"`. PostCompact is observability only — no decision control.

### Elicitation (2.1.76+)

```json
// Form mode
{
  "mcp_server_name": "my-mcp-server",
  "message": "Please provide the deployment parameters",
  "mode": "form",
  "requested_schema": { }
}

// URL mode
{
  "mcp_server_name": "my-mcp-server",
  "message": "Please authorize via browser",
  "mode": "url",
  "url": "https://example.com/authorize"
}
```

### ElicitationResult (2.1.76+)

```json
{
  "mcp_server_name": "my-mcp-server",
  "action": "accept",
  "mode": "form",
  "elicitation_id": "elicit-uuid-123",
  "content": { "environment": "production" }
}
```

Output can override `action`/`content`. Exit code 2 changes action to `decline`.

---

## Output Schemas

### PreToolUse — Allow, Deny, or Modify

PreToolUse hooks wrap their JSON response in a `hookSpecificOutput` envelope:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "Command matches approved pattern"
  }
}
```

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Destructive operation blocked by policy"
  }
}
```

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "Unusual command, require human confirmation"
  }
}
```

> **Security Note (2.1.72)**: Prior to 2.1.72, returning `"allow"` from a PreToolUse hook could bypass `deny` rules (including enterprise managed settings). This is now fixed — `deny` rules always take precedence.

Optionally modify the tool input before execution:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "updatedInput": {
      "command": "npm test -- --bail=1"
    }
  }
}
```

### PostToolUse -- Replace Tool Output (2.1.121+)

`PostToolUse` hooks can replace tool output for any tool via `hookSpecificOutput.updatedToolOutput`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "updatedToolOutput": "Filtered or modified tool output"
  }
}
```

### PostToolUse -- Continue After Block (2.1.139+)

By default, a blocking `PostToolUse` hook (decision `"block"`) ends the turn with the reason shown to Claude. Set `continueOnBlock: true` on the hook handler to instead feed the rejection reason back to Claude and continue the turn — useful for soft validators that nudge a retry without aborting:

```json
{
  "type": "command",
  "command": "bash .claude/hooks/post-validate.sh",
  "continueOnBlock": true,
  "timeout": 30
}
```

This is `PostToolUse`-specific. Other events do not accept the field.

### Hook JSON Output — `terminalSequence` (2.1.141+)

Any hook can emit a `terminalSequence` field to send a terminal control sequence to the user's display — desktop notifications (OSC 9), window titles (OSC 0/2), or bells (`\a`) — without a controlling terminal:

```json
{
  "terminalSequence": "]9;Build finished"
}
```

Useful for `Stop`, `SubagentStop`, and `TaskCompleted` hooks that want to surface completion to the user even when Claude Code is running in a daemonised or backgrounded process.

### PermissionRequest -- Auto Approve/Deny (2.1.50+)

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
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Branch: main\nUncommitted: 0 files\nTests: passing"
  }
}
```

### TaskCompleted — Gate Completion (2.1.50+)

```json
{
  "decision": "block",
  "reason": "Tests must pass before this task is accepted. Run: npm test"
}
```

### Elicitation — Accept, Decline, or Cancel (2.1.76+)

```json
{ "action": "accept", "content": { } }
{ "action": "decline" }
{ "action": "cancel" }
```

Exit code 2 also declines. Return nothing to show dialog to user.

---

## Transcript Replay Cost

A second cost axis sits alongside the timeout budget: **anything a hook
makes the model *see* lands in the transcript and is re-sent on every
subsequent turn.** A one-line hint that fires on a high-frequency tool
call isn't a one-time ~30-token cost — it's ~30 tokens × every remaining
turn in the session. Hook authors should design for "never bloats the
replayed transcript" as deliberately as "never reaches a diff."

### Which output the model sees (and replays)

| Output mechanism | Reaches the model? | Replays each turn? |
|---|---|---|
| Exit 0, write to a log file / disk only | No | No — **free** |
| PreToolUse exit-2 stderr (block message) | Yes (as the tool result) | Yes |
| PostToolUse `updatedToolOutput` | Yes (replaces the tool result) | Yes |
| SessionStart `additionalContext` | Yes (prepended to first turn) | Yes |
| `Stop` / `SubagentStop` `{"decision":"block","reason":...}` | **Yes** — the `reason` is shown so the model keeps working | Yes |
| `Stop` exit 0 (allow) | No | No — **free** |

A common misconception is that "`Stop` output never reaches the model."
It does: a blocking `Stop` hook's `reason` is precisely what tells the
model to continue, and the `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` safety net
(2.1.143+) exists *because* the model re-reads that reason and keeps
addressing it. What actually makes our `Stop` checks
(`task-completeness.sh`, `git-stash-reminder.sh`) cheap is **frequency and
conditionality**, not invisibility:

- they fire at most once per stop attempt, not per tool call;
- they stay silent (exit 0) unless there is a concrete finding; and
- they are self-extinguishing — once the agent fixes the TODO / stray
  debug line / stash, the next stop passes clean and the reason stops
  replaying.

### Design guidance

| If the hook output is… | Do |
|---|---|
| Pure observability (logging, metrics) | Write to disk, exit 0 — never emit to the model (`event-logger.sh`) |
| A correction the model needs once | Emit once, then **dedup per session** so repeats don't accumulate (`bash-antipatterns-teach.sh` keys a per-session seen-list under `${TMPDIR:-/tmp}/claude-bash-teach-seen/<session_id>`) |
| A blocking gate | Keep the message short; fire only on a real finding; make it self-extinguishing so it stops replaying once resolved |
| High-frequency per-call feedback | Reconsider — this is the most expensive shape; cap, dedup, or move the check to `Stop` |

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

## HTTP Hooks (2.1.63+)

HTTP hooks send hook data to a URL endpoint instead of executing a shell command. Useful for centralized hook management and remote hook processing.

### Configuration

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

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `type` | Yes | — | `"http"` |
| `url` | Yes | — | HTTPS endpoint to receive hook data |
| `headers` | No | `{}` | HTTP headers; values support `${ENV_VAR}` expansion |
| `timeout` | No | 30s | Seconds before request is canceled |

### Security

- Only HTTPS URLs are allowed
- Environment variable expansion in headers uses `${VAR}` syntax
- Use `allowedEnvVars` in the hook configuration to restrict which env vars can be referenced

### Response Format

The HTTP endpoint returns the same JSON schema as command hooks for the given event. Non-2xx responses are treated as hook failures.

---

## Async Hooks

Command hooks can run asynchronously with `async: true`. Async hooks fire-and-forget — they do not block the operation and their exit code is ignored.

```json
{
  "type": "command",
  "command": "bash .claude/hooks/log-audit.sh",
  "async": true,
  "timeout": 60
}
```

Use async hooks for non-blocking side effects like logging, metrics, and notifications where you do not need to gate the operation on the hook result.

> **Note (2.1.75)**: Async hook completion messages are suppressed by default. Use `--verbose` or transcript mode to see them.

---

## Hook Handler Fields

### `once` Field

Set `once: true` on a hook handler to run it only once per session. Subsequent triggers of the same hook are skipped.

```json
{
  "type": "command",
  "command": "bash .claude/hooks/one-time-setup.sh",
  "once": true,
  "timeout": 120
}
```

Useful for `SessionStart` setup scripts or one-time validation checks.

---

## Hooks in Skill/Agent Frontmatter

Skills and agents can define scoped hooks in their YAML frontmatter. These hooks are only active when the skill/agent is loaded.

### Skill Frontmatter Hooks

```yaml
---
name: my-skill
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/hooks/validate.sh"
          timeout: 10
---
```

### Agent Frontmatter Hooks

Agent hooks defined with `Stop` are automatically converted to `SubagentStop` when the agent runs as a subagent, since agents execute in subagent context.

```yaml
---
name: my-agent
hooks:
  Stop:
    - matcher: ""
      hooks:
        - type: command
          command: "bash ${CLAUDE_PLUGIN_ROOT}/hooks/verify-output.sh"
          timeout: 30
---
```

---

## Environment Variables

### `CLAUDE_ENV_FILE`

When set, `CLAUDE_ENV_FILE` points to a file path where `SessionStart` hooks can write environment variables that persist for the session. Write `KEY=VALUE` lines to this file.

```bash
#!/bin/bash
# SessionStart hook using CLAUDE_ENV_FILE
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo "NODE_ENV=development" >> "$CLAUDE_ENV_FILE"
  echo "PYTHONDONTWRITEBYTECODE=1" >> "$CLAUDE_ENV_FILE"
fi
exit 0
```

### `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` (2.1.74+)

Override the `SessionEnd` hook timeout in milliseconds. Prior to 2.1.74, `SessionEnd` hooks were hard-capped at 1.5 seconds regardless of `hook.timeout`. Set this to allow longer cleanup hooks:

```bash
export CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS=30000  # 30 seconds
```

### `CLAUDE_CODE_REMOTE`

Set to `"true"` when Claude Code is running in a remote/web session (e.g., Claude Code on the web). Use this to conditionally run hooks only in remote environments:

```bash
#!/bin/bash
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0  # Skip in local sessions
fi
# Remote-only setup here
```

### `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` (2.1.143+)

A `Stop` hook that repeatedly returns `{"decision": "block"}` used to loop forever — Claude would address the feedback, hit the hook again, get blocked again, and never end the turn. As of 2.1.143, the turn ends with a warning after **8 consecutive blocks**. Override via:

```bash
export CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=16   # raise the ceiling
export CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0    # disable the cap (not recommended)
```

The cap is a safety net, not a substitute for the `stop_hook_active` check documented in `.claude/rules/prompt-agent-hooks.md` — a well-written stop hook still short-circuits when `stop_hook_active` is true.

---

## Matcher Patterns

### MCP Tool Matching

MCP tools use the naming pattern `mcp__<server>__<tool>`. Match them with regex patterns:

```json
{
  "matcher": "mcp__.*",
  "hooks": [...]
}
```

| Pattern | Matches |
|---------|---------|
| `mcp__.*` | All MCP tools from any server |
| `mcp__github__.*` | All tools from the `github` MCP server |
| `mcp__github__create_pull_request` | Specific MCP tool |

---

## Exit Codes

| Code | Meaning | Effect |
|------|---------|--------|
| `0` | Success | Operation allowed/continues |
| `2` | Blocking error | Operation blocked; stderr shown to Claude |
| Other | Non-blocking error | Logged in verbose mode, operation continues |

> **Note**: `WorktreeCreate` and `WorktreeRemove` treat any non-zero exit code as a failure (not just exit code 2).

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

| Event | Category | Since |
|-------|----------|-------|
| `SessionStart` | Session | |
| `SessionEnd` | Session | |
| `UserPromptSubmit` | Session | |
| `PreCompact` | Session | |
| `PostCompact` | Session | 2.1.76 |
| `PreToolUse` | Tool | |
| `PostToolUse` | Tool | |
| `PostToolUseFailure` | Tool | |
| `PermissionRequest` | Tool | 2.1.50 |
| `Stop` | Agent | |
| `SubagentStart` | Agent | |
| `SubagentStop` | Agent | |
| `WorktreeCreate` | Worktree | 2.1.50 |
| `WorktreeRemove` | Worktree | 2.1.50 |
| `TeammateIdle` | Teams | 2.1.50 |
| `TaskCompleted` | Teams | 2.1.50 |
| `Elicitation` | MCP | 2.1.76 |
| `ElicitationResult` | MCP | 2.1.76 |
| `Notification` | Misc | |
| `ConfigChange` | Misc | 2.1.50 |

