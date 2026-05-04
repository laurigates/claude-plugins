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
| `curl \| sh` / `wget \| bash` | Download first, review, then execute |
| Fork bombs | Blocked unconditionally |
| `chmod 777` | Use restrictive permissions (755, 644, 600) |
| Write to block device | Blocked unconditionally |

### git-stash-session-init.sh

A SessionStart hook that records the stash baseline for session-scoped tracking. Required by `git-stash-reminder.sh`.

### git-stash-reminder.sh

A Stop hook that checks for git stashes **created during the current session**. Pre-existing stashes (recorded at session start by `git-stash-session-init.sh`) are ignored.

| Condition | Action |
|-----------|--------|
| Session stashes exist | Recommend `git stash pop` |
| Only pre-existing stashes | Silent exit (no block) |
| No stashes at all | Silent exit |

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

### secret-protection.sh

A PreToolUse hook that blocks access to sensitive files and prevents credential exposure.

| Category | Blocked Patterns |
|----------|-----------------|
| Environment files | `.env`, `.env.*` (allows `.env.example`, `.env.sample`) |
| SSH credentials | `.ssh/id_*`, `.pem`, `*_rsa`, `*_ed25519` |
| Cloud credentials | `.aws/credentials`, `.config/gcloud/`, `.kube/config`, `.docker/config.json` |
| Credential files | `credentials.json`, `secrets.json`, `*.keystore`, `*.key` |
| Env var exposure | Commands that echo `$API_KEY`, `$SECRET`, `$TOKEN`, `$PASSWORD` |
| Full env dump | Bare `printenv` or `env` commands |

**Toggle:** `CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1`

### branch-protection.sh

A PreToolUse hook that blocks write operations on protected branches (main, master).

| Operation | Behavior |
|-----------|----------|
| Read-only git (status, diff, log, show) | Allowed |
| Checkout/switch to another branch | Allowed |
| Push with explicit refspec (`main:feature`) | Allowed |
| Merge (local feature branch into main) | Allowed (reversible) |
| Commit, rebase, push | Blocked with branch creation suggestion |
| Staging (git add, rm, mv) | Blocked |
| Reset | Blocked |

**Toggle:** `export CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1` in your shell environment (e.g. in a personal repo, dotfiles, or main-branch-dev workflow). This is a **human-operator** opt-in — inline prefixes like `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 git commit ...` on a Bash command are intentionally not honored, so that agents cannot self-serve the bypass. When blocked on a protected branch, an agent should follow `.claude/rules/handling-blocked-hooks.md` and delegate to the user instead.

### auto-checkpoint.sh

A PreToolUse hook that creates a git stash checkpoint before destructive operations.

| Trigger | Checkpoint Created |
|---------|-------------------|
| `git reset` | Named stash with timestamp |
| `git checkout -- <files>` | Named stash with timestamp |
| `git restore` (non-staged) | Named stash with timestamp |
| `rm -rf` (non-build-artifact) | Named stash with timestamp |
| `git clean -f` | Named stash with timestamp |

Skips checkpointing for build artifact removal (node_modules, dist, build, .next, etc.).

**Toggle:** `CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1`

### event-logger.sh

A development hook that logs all hook events to `~/.claude/hook-events.log`.

| Mode | Environment Variable | Output |
|------|---------------------|--------|
| Off (default) | — | No logging |
| Summary | `CLAUDE_HOOKS_ENABLE_EVENT_LOGGER=1` | One-line per event (timestamp, event, tool, session) |
| Verbose | Above + `CLAUDE_HOOKS_EVENT_LOGGER_VERBOSE=1` | Full JSON input logged |

Custom log path: `CLAUDE_HOOKS_EVENT_LOG=/path/to/log`

### permission-auto-approve.sh

A PermissionRequest hook that auto-approves safe operations and auto-denies dangerous ones.

| Decision | Patterns |
|----------|----------|
| Auto-approve | Read-only git, test runners, linters, gh CLI reads |
| Auto-deny | `rm -rf /`, force push to main/master |
| Pass through | Everything else (user decides) |

**Toggle:** `CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO=1`

### task-completeness.sh

A Stop hook that checks for obvious signs of incomplete work using deterministic heuristics. Replaces the former `type: "prompt"` task-completeness hook to avoid leaking the full LLM prompt in error output (see [#1009](https://github.com/laurigates/claude-plugins/issues/1009)).

| Check | Trigger |
|-------|---------|
| TODO/FIXME/HACK/XXX added in uncommitted diff | Blocks with count and message |
| Merge conflict markers (`<<<<<<<`, `>>>>>>>`) in changed files | Blocks with affected filenames |
| Debugging artifacts (`console.log`, `debugger;`, `breakpoint()`, `pdb.set_trace`) added in diff | Blocks with count |
| `stop_hook_active=true` in input | Exits 0 immediately (prevents infinite loops) |
| Non-git directory | Exits 0 silently |

Documentation files (`*.md`, `*.mdx`, `*.rst`, `*.txt`) and vendor/generated paths (`node_modules`, `vendor`, `dist`, `build`, `*.min.*`) are excluded from all three checks — they routinely quote literal TODO/FIXME tokens, conflict markers, and `console.log` examples in prose.

**Toggle:** `CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1`

### test-verification.sh

A Stop hook that auto-detects the project's test runner and runs tests when uncommitted changes touch source files. Skips silently when no source files changed, no recognised runner is found, or the diff is documentation-only.

| Aspect | Detail |
|--------|--------|
| Type | `command` (deterministic — replaced the former `type: "agent"` variant for latency) |
| Timeout | 60s framework / 45s hard internal (configurable via `CLAUDE_HOOKS_TEST_TIMEOUT`) |
| Detected runners | `justfile` (prefers `test-quick` → `test-unit` → `test`), `Makefile` (same priority), Bun, npm, pytest (uv-aware), cargo, go |
| Skip conditions | Only docs/config files changed, no test runner found, `stop_hook_active=true` |
| Timeout behaviour | Approves with a warning instead of blocking (does not interrupt flow) |

**Toggle:** `CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION=1`

> **Note on prompt-type Stop hooks**: When a `type: "prompt"` hook on `Stop` or `SubagentStop` returns `{"ok": false}`, Claude Code surfaces the full prompt text in the error message (e.g. `Stop hook error: [You are evaluating...]: reason`). This is a runtime behavior that cannot be configured away. Prefer `type: "command"` hooks with deterministic heuristics for Stop events to avoid this leakage. Only use `type: "prompt"` on Stop hooks when the check genuinely requires LLM judgment and cannot be deterministic.

## Prompt-Based and Agent-Based Hooks

LLM-powered hooks that use judgment instead of deterministic rules.

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

## Toggling Hooks

Every hook can be individually enabled or disabled via environment variables. Set these in your shell profile or `.claude/settings.json` environment.

| Hook | Disable Variable | Default |
|------|-----------------|---------|
| secret-protection.sh | `CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION=1` | Enabled |
| branch-protection.sh | `CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1` | Enabled |
| auto-checkpoint.sh | `CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1` | Enabled |
| permission-auto-approve.sh | `CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO=1` | Enabled |
| task-completeness.sh | `CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS=1` | Enabled |
| test-verification.sh | `CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION=1` | Enabled |
| event-logger.sh | `CLAUDE_HOOKS_ENABLE_EVENT_LOGGER=1` | **Disabled** (opt-in) |

Example — disable branch protection for a session:

```bash
CLAUDE_HOOKS_DISABLE_BRANCH_PROTECTION=1 claude
```

## Hook Performance

Hooks run synchronously — a slow hook adds latency to every Claude action. Keep PreToolUse hooks fast since they fire most frequently.

| Language | Startup Latency | Best For |
|----------|----------------|----------|
| Bash | ~10-20ms | Pattern matching, file checks, git operations |
| Node.js | ~50-100ms | Complex JSON parsing, multi-step logic |
| Python | ~200-400ms | Heavy computation, ML-based checks |

**Guidelines:**
- Keep PreToolUse hooks under 100ms total (fires on every tool call)
- Stop/SessionEnd hooks can be slower (fire infrequently)
- Prefer Bash for simple regex/grep checks
- Use `jq` for JSON parsing in Bash hooks (fast, no startup overhead)
- Set explicit timeouts to document expected performance

## Hook Exit Codes

- **0**: Command allowed
- **2**: Command blocked with reminder (message shown to Claude)
- **Other**: Non-blocking error (logged in verbose mode)
