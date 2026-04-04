---
name: hooks-session-end-issue-hook
description: |
  Configure a Stop hook that surfaces unfinished todos before a session ends and suggests
  creating GitHub issues for deferred work. Use when you want unfinished Claude Code session
  tasks automatically flagged for GitHub issue creation at session end.
args: "[--no-verify]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
argument-hint: "--no-verify to skip gh auth verification"
disable-model-invocation: true
created: 2026-02-27
modified: 2026-03-30
reviewed: 2026-03-30
---

# /hooks:session-end-issue-hook

Configure a `Stop` hook that checks for unfinished `TodoWrite` todos at the end of each Claude response. If any pending or in-progress todos exist when you try to end the session, Claude is prompted to create GitHub issues for them before the conversation closes.

## When to Use This Skill

| Use this skill when... | Use `/hooks:hooks-configuration` instead when... |
|---|---|
| You want unfinished todos deferred to GitHub issues | Configuring other hook types (PreToolUse, SessionEnd, etc.) |
| Preventing tasks from being forgotten at session end | Need general hooks knowledge or debugging |
| Projects with active issue trackers on GitHub | Understanding hook lifecycle events |
| Teams that rely on GitHub issues for work tracking | Writing custom hook logic from scratch |

## Context

Detect current state:

- Settings file: !`find .claude -maxdepth 1 -name 'settings.json'`
- Existing Stop hooks: !`jq -r '.hooks.Stop // empty' .claude/settings.json`
- gh auth: !`gh auth status`
- jq available: !`jq --version`

## Parameters

| Flag | Default | Description |
|---|---|---|
| `--no-verify` | off | Skip checking `gh` authentication status |

## Execution

### Step 1: Check prerequisites

Verify that `jq` is installed — the hook requires it to parse the session transcript. Report if missing.

Unless `--no-verify` is passed: verify `gh` is installed and authenticated (`gh auth status`). Report the auth state so the user knows whether GitHub issue creation will work when the hook fires.

### Step 2: Locate hook script

The hook script ships with the hooks-plugin. Determine its path:

- If `${CLAUDE_PLUGIN_ROOT}` is set: use `${CLAUDE_PLUGIN_ROOT}/hooks/session-end-issue-hook.sh`
- Otherwise: look for the script relative to this skill's location (`../../hooks/session-end-issue-hook.sh`)
- Last resort: ask the user for the absolute path to the installed hooks-plugin

Report the resolved path to the user.

### Step 3: Configure `.claude/settings.json`

Read existing `.claude/settings.json` if it exists. **Merge** the Stop hook — preserve all existing configuration.

If a `Stop` hook pointing to `session-end-issue-hook.sh` already exists, report that the hook is already configured and skip to Step 4.

If other Stop hooks exist, add alongside them (both will run).

Configuration to merge under the `hooks` key:

```json
{
  "Stop": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/session-end-issue-hook.sh\"",
          "timeout": 15
        }
      ]
    }
  ]
}
```

Use `timeout: 15` (15 seconds) — transcript parsing is fast. Create `.claude/` directory if it does not exist.

### Step 4: Finalize

Report a summary of what was configured, including:
- Path to the hook script
- Location of `.claude/settings.json`
- Whether `gh` auth is ready

## Post-Actions

After configuring the hook:

1. Suggest committing `.claude/settings.json` to share the hook with the team
2. Remind the user that the hook fires at the end of **every** Claude response — it is silent when all todos are completed and only blocks when pending todos exist
3. If `gh` is not authenticated, remind the user to run `gh auth login` so GitHub issue creation works when the hook fires

## How the Hook Works

When the hook fires at the end of a Claude response:

1. It reads the session transcript from `transcript_path`
2. Finds the **last `TodoWrite` call** — the final state of the todo list
3. Extracts any todos with `status: "pending"` or `status: "in_progress"`
4. If none exist → silently exits (no interruption)
5. If any exist → outputs a block decision with the list of pending todos and suggested `gh issue create` commands

Claude then has the opportunity to create the issues or ask the user what to do with the deferred work.

## Agentic Optimizations

| Context | Approach |
|---|---|
| Quick setup, skip auth check | `/hooks:session-end-issue-hook --no-verify` |
| Full setup with auth verification | `/hooks:session-end-issue-hook` |
| Test the hook manually | `echo '{"transcript_path":"/path/to/transcript","cwd":"."}' \| bash hooks/session-end-issue-hook.sh` |

## Quick Reference

| Item | Value |
|---|---|
| Hook event | `Stop` (fires after each Claude response) |
| Settings location | `.claude/settings.json` |
| Timeout | 15 seconds |
| Trigger condition | Pending or in-progress todos in last TodoWrite call |
| Silent when | All todos completed or no TodoWrite calls in transcript |
| Issue label | `claude-deferred` (suggested in output, not auto-applied) |
