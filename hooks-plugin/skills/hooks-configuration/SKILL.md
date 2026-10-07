---
name: hooks-configuration
description: Claude Code hooks configuration and development. Use when the user mentions hooks, PreToolUse, PostToolUse, SessionStart, SubagentStart, PermissionRequest, or TaskCompleted.
user-invocable: false
allowed-tools: Bash(bash *), Bash(cat *), Read, Write, Edit, Glob, Grep, TodoWrite
created: 2025-12-16
modified: 2026-09-02
compatibility: claude-code
reviewed: 2026-09-02
---

# Claude Code Hooks Configuration

Expert knowledge for configuring and developing Claude Code hooks to automate workflows and enforce best practices.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|---------------------------|
| Configuring hook lifecycle events (PreToolUse, PostToolUse, etc.) | Writing general shell scripts unrelated to hooks |
| Blocking dangerous commands or enforcing patterns | Setting up CI/CD pipelines (use CI tooling) |
| Auto-formatting files after edits | Configuring Claude Code settings unrelated to hooks |
| Injecting context at session or subagent start | Writing standalone automation scripts |
| Setting up PermissionRequest auto-approve/deny | Managing project permissions via settings.json directly |
| Developing prompt or agent hooks for judgment-based decisions | Building MCP servers or custom tool integrations |

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
| **PreModelSwitch**     | Before the session model changes (`/model`, `fallbackModel`, safety-classifier fallback) | Audit or record the outgoing model |
| **PostModelSwitch**    | After the session model has changed        | Re-apply per-model settings, log the new model |

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

Example frontmatter: [references/frontmatter-hooks.md](references/frontmatter-hooks.md).

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

## Input/Output Schema Summary

Hooks receive JSON via stdin with common fields (`session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`). Event-specific fields include `tool_name` and `tool_input` for PreToolUse, plus `tool_response` for PostToolUse, and `subagent_type`/`subagent_prompt` for SubagentStart.

**Exit codes**: 0 = allow, 2 = block (stderr shown to Claude), other = non-blocking error.

**JSON responses** vary by event: PreToolUse uses `hookSpecificOutput` with `permissionDecision`; Stop/SubagentStop use `decision`/`reason`; SubagentStart uses `updatedPrompt`; SessionStart uses `hookSpecificOutput` with `additionalContext`.

For detailed hook schemas and examples, see [REFERENCE.md](REFERENCE.md).

## Common Hook Patterns

Worked scripts (block dangerous commands, auto-format after edits, tool reminders, SessionStart context): [references/hook-patterns.md](references/hook-patterns.md).

For additional patterns (subagent injection, desktop notifications, audit logging, auto-approve, worktree setup, task gating), see [REFERENCE.md](REFERENCE.md).

## Prompt-Based and Agent-Based Hooks

Four hook types: `command` (shell script, exit code), `http` (HTTPS endpoint), `prompt` (single-turn LLM call), and `agent` (multi-turn with tool access). Use `command` for deterministic rules; `prompt`/`agent` for judgment-based decisions. Add `async: true` for fire-and-forget; `once: true` to run only once per session.

Prompt and agent hooks work on `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Stop`, `SubagentStop`, `TaskCompleted`, `UserPromptSubmit`. All other events support `command` hooks only.

For hook type details, `CLAUDE_ENV_FILE`, and configuration examples, see [REFERENCE.md](REFERENCE.md) and [.claude/rules/prompt-agent-hooks.md](../../.claude/rules/prompt-agent-hooks.md).

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

## Timeout Guidelines

The default hook timeout is 600s (10 minutes) since Claude Code 2.1.50. Set explicit timeouts to document intent and prevent "Hook cancelled" errors:

| Hook Type | Recommended Timeout | Use Case |
|-----------|---------------------|----------|
| SessionStart | 120–300s | Tests, linters, dependency checks |
| SessionEnd | 60–120s | Logging, cleanup, state saving |
| Stop / SubagentStop | 30–60s | Git status checks, quick validations |
| PreToolUse | 10–30s | Quick validations |
| PostToolUse | 30–120s | Logging, notifications |
| PermissionRequest | 5–15s | Keep fast for good UX |

For slow work, run it in a background subshell: [references/hook-patterns.md](references/hook-patterns.md#background-subshell-pattern-recommended-for-slow-hooks).

## Best Practices

| Area | Key Points |
|------|------------|
| Script | Read stdin with `cat`; parse with `jq`; quote all vars; exit 2 to block, 0 to allow; stderr for messages; keep < 5s |
| Config | `$CLAUDE_PROJECT_DIR` for portable paths; explicit timeouts; specific matchers over wildcards; test before enabling |
| Security | Validate all inputs; use absolute paths; avoid `.env` / `.git/` directly; review before deploy |

## Debugging

Hook cancelled, failing, or not firing: [references/troubleshooting.md](references/troubleshooting.md).

