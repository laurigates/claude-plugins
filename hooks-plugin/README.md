# Hooks Plugin

Claude Code hooks for enforcing best practices and workflow automation.

## Overview

This plugin provides pre-built hooks that can be installed in any project to enforce consistent behavior and remind Claude to use the correct tools.

## Available Hooks

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
| `git add -A` / `git add .` | Stage specific files by name instead |
| 5+ pipe chain | Simplify with JSON output or awk |
| Multi-grep test parsing | Use `--reporter=json` instead |

### git-stash-reminder.sh

A Stop hook that checks for orphaned git stashes before Claude exits. Classifies stashes by age and recommends `pop` (recent) or `drop` (stale).

| Stash Age | Action |
|-----------|--------|
| < 2 hours | Recommend `git stash pop` |
| >= 2 hours | Recommend `git stash drop stash@{N}` |

### session-end-issue-hook.sh

A Stop hook that fires when the main agent finishes a response. If the session transcript contains any `TodoWrite` todos with `status: "pending"` or `status: "in_progress"`, it blocks and surfaces the list to Claude with suggested `gh issue create` commands. Silent when all todos are completed.

| Condition | Behaviour |
|-----------|-----------|
| No pending todos | Exits 0 silently — no interruption |
| Pending / in-progress todos | Blocks with list and `gh issue create` suggestions |

Configure via `/hooks:session-end-issue-hook` or see [Session End Issue Hook](#session-end-issue-hook) below.

### git-session-cleanup.sh

A SessionEnd hook that runs cleanup operations when the session terminates: commits any staged changes, switches to the main/master branch, and pulls the latest changes.

| Step | Behaviour |
|------|-----------|
| Commit | Commits staged files with `chore: auto-commit staged changes` (skipped if nothing staged) |
| Switch | Switches to `main` (or `master` if `main` doesn't exist); no-op if already on main |
| Pull | Runs `git pull --ff-only` to fast-forward the branch |

## Prompt-Based and Agent-Based Hooks

LLM-powered hooks that use judgment instead of deterministic rules.

### Stop — Task Completeness Gate (prompt)

A `type: "prompt"` hook that evaluates whether Claude completed all user-requested tasks before stopping. Prevents Claude from finishing prematurely with incomplete work.

| Aspect | Detail |
|--------|--------|
| Type | `prompt` (single-turn LLM call) |
| Timeout | 30s |
| Loop prevention | Checks `stop_hook_active` to avoid infinite loops |

### Stop — Test Verification (agent)

A `type: "agent"` hook that runs the project's test suite before allowing Claude to stop. Detects the test runner automatically (npm, pytest, cargo, go, make).

| Aspect | Detail |
|--------|--------|
| Type | `agent` (multi-turn with tool access) |
| Timeout | 120s |
| Skip condition | No source files changed, or no test runner found |

### SubagentStop — Output Quality Gate (prompt)

A `type: "prompt"` hook that evaluates subagent output completeness. Blocks vague or incomplete subagent results.

| Aspect | Detail |
|--------|--------|
| Type | `prompt` (single-turn LLM call) |
| Timeout | 30s |
| Checks | Addresses original task, specificity, completeness |

### TaskCompleted — Implementation Verification (agent)

A `type: "agent"` hook that verifies task implementation quality when a team task is marked complete. Checks for leftover TODOs, debug artifacts, and test coverage.

| Aspect | Detail |
|--------|--------|
| Type | `agent` (multi-turn with tool access) |
| Timeout | 60s |
| Checks | TODO/FIXME comments, debug artifacts, test presence |

### UserPromptSubmit — Prompt Safety Classification (prompt)

A `type: "prompt"` hook that classifies user prompts for safety before Claude processes them. Flags destructive operations (force push, rm -rf, production deployments).

| Aspect | Detail |
|--------|--------|
| Type | `prompt` (single-turn LLM call) |
| Timeout | 15s |
| Scope | Only flags explicitly destructive requests |

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

| Skill | Invocation | Purpose |
|-------|-----------|---------|
| hooks-configuration | `/hooks:hooks-configuration` | Guide for setting up and customizing hooks |
| hooks-session-start-hook | `/hooks:session-start-hook` | Generate SessionStart hooks for Claude Code on the web |
| hooks-session-end-issue-hook | `/hooks:session-end-issue-hook` | Configure Stop hook that defers unfinished todos to GitHub issues |

## Session Start Hooks

Generate a SessionStart hook to prepare your repository for Claude Code on the web:

```bash
/hooks:session-start-hook
```

This auto-detects your project stack and generates:
- A hook script that installs dependencies and verifies tooling
- `.claude/settings.json` configuration for the SessionStart event
- Environment variable persistence via `CLAUDE_ENV_FILE`

Options:
- `--remote-only`: Only run in web sessions (skip local)
- `--no-verify`: Skip test/linter verification step

## Session End Issue Hook

Configure a Stop hook that surfaces unfinished todos at session end and suggests creating GitHub issues:

```bash
/hooks:session-end-issue-hook
```

This configures a `Stop` hook in `.claude/settings.json` that:
- Reads the session transcript after each Claude response
- Finds any todos with `status: "pending"` or `status: "in_progress"` from the last `TodoWrite` call
- If any exist: blocks with the list and suggested `gh issue create` commands so Claude can defer them
- If all completed: exits silently

Options:
- `--no-verify`: Skip `gh` authentication check

## Extending

Add new hooks by:

1. Creating a new `.sh` script in `hooks/`
2. Following the input/output conventions (see existing hooks)
3. Adding configuration to `.claude/settings.json`

## Hook Exit Codes

- **0**: Command allowed
- **2**: Command blocked with reminder (message shown to Claude)
- **Other**: Non-blocking error (logged in verbose mode)
