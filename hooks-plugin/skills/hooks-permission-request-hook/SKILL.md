---
name: hooks-permission-request-hook
description: Generate a PermissionRequest hook with auto-approve/deny rules. Use when needing a safer alternative to --dangerouslySkipPermissions tailored to your project stack.
args: "[--strict] [--category <name>...]"
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, TodoWrite
argument-hint: "--strict to deny unknown commands, --category git|test|lint|build|gh|deny"
disable-model-invocation: true
created: 2026-03-13
modified: 2026-07-18
compatibility: claude-code
reviewed: 2026-04-29
---

# /hooks:permission-request-hook

Generate a `PermissionRequest` hook that auto-approves safe operations, auto-denies dangerous ones, and passes everything else through for user decision. A safer, project-aware alternative to `--dangerouslySkipPermissions`.

## When to Use This Skill

| Use this skill when... | Use `/hooks:hooks-configuration` instead when... |
|---|---|
| You want auto-approve/deny rules for Claude Code permissions | Configuring other hook types (PreToolUse, Stop, SessionStart) |
| Replacing `--dangerouslySkipPermissions` with targeted rules | Need general hooks knowledge or debugging |
| Setting up project-specific permission automation | Writing entirely custom hook logic from scratch |
| You need a test harness to validate approve/deny behavior | Understanding hook lifecycle events |

### Auto Mode vs `PermissionRequest` Hook

Auto mode (Claude Code 2.1.83+) routes most approve/deny decisions through a classifier model. It overlaps with — but does not replace — a `PermissionRequest` hook. Choose this skill when you need any of:

- **Deterministic, auditable rules** — the classifier's probabilistic answer is unsuitable for compliance contexts
- **Project-specific deny lists** that go beyond the default trust set
- **Hard 0% false-positive guarantees** for specific commands (the hook is exact, the classifier is not)
- **Pre-approve narrow patterns** so they skip the classifier round-trip and avoid latency/token cost

Hooks coexist with auto mode — they fire alongside the classifier. See `.claude/rules/auto-mode.md` for the full auto-mode model and how it interacts with allow rules and subagents.

## Context

Detect project stack:

- Lockfiles: !`find . -maxdepth 1 \( -name 'package-lock.json' -o -name 'yarn.lock' -o -name 'pnpm-lock.yaml' -o -name 'bun.lockb' -o -name 'poetry.lock' -o -name 'uv.lock' -o -name 'Cargo.lock' -o -name 'go.sum' -o -name 'Gemfile.lock' \)`
- Project files: !`find . -maxdepth 1 \( -name 'package.json' -o -name 'pyproject.toml' -o -name 'requirements.txt' -o -name 'Cargo.toml' -o -name 'go.mod' -o -name 'Gemfile' \)`
- Existing settings: !`find . -path '*/.claude/settings.json' -maxdepth 3 -type f`
- Existing hooks dir: !`find . -maxdepth 2 -type d -name 'scripts'`
- jq available: !`jq --version`
- Existing PermissionRequest hooks: !`find . -path '*/.claude/settings.json' -maxdepth 3 -exec jq -r '.hooks.PermissionRequest // empty' {} +`

## Parameters

Parse these from `$ARGUMENTS`:

| Flag | Default | Description |
|---|---|---|
| `--strict` | off | Deny unrecognized Bash commands by default instead of passing through to user |
| `--category <name>` | all | Include only specific rule categories. Repeatable. Values: `git`, `test`, `lint`, `build`, `gh`, `deny` |

## Execution

Execute this workflow:

### Step 1: Detect project stack

Identify languages and tooling from the context above.

**Language detection:**

| File Present | Language | Package Manager (from lockfile) |
|---|---|---|
| `package.json` | Node.js | npm (`package-lock.json`), yarn (`yarn.lock`), pnpm (`pnpm-lock.yaml`), bun (`bun.lockb`) |
| `pyproject.toml` / `requirements.txt` | Python | poetry (`poetry.lock`), uv (`uv.lock`), pip (fallback) |
| `Cargo.toml` | Rust | cargo |
| `go.mod` | Go | go modules |
| `Gemfile` | Ruby | bundler |

Report detected stack to user before generating.

### Step 2: Generate the hook script

Create the script at `scripts/permission-request.sh` (or `.claude/hooks/permission-request.sh` if no `scripts/` directory exists).

Use the **Script Template** from [REFERENCE.md](REFERENCE.md). Adapt it by:
1. Including only sections for detected languages (remove `{{ if ... }}` markers)
2. Including only selected categories if `--category` flags were provided
3. Removing all template comments (`{{ ... }}`)
4. If `--strict` is set, include the strict mode catch-all deny at the end

### Step 3: Generate the test script

Create `scripts/test-permission-hook.sh` (or `.claude/hooks/test-permission-hook.sh` to match the hook location).

Use the **Test Script Specification** from [REFERENCE.md](REFERENCE.md). Include test cases only for detected stacks and selected categories. Remove all `{{ ... }}` template markers.

### Step 4: Configure `.claude/settings.json`

Read existing `.claude/settings.json` if it exists. **Merge** the PermissionRequest hook — preserve all existing configuration.

If a `PermissionRequest` hook already exists, ask the user whether to:
- **Replace** the existing PermissionRequest hook
- **Add alongside** the existing hook (both will run)
- **Abort** and keep existing configuration

Configuration to merge:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$CLAUDE_PROJECT_DIR/scripts/permission-request.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Use `timeout: 10` (10 seconds). Use empty matcher `""` to match all tools. Adjust path if script is in `.claude/hooks/` instead of `scripts/`.

### Step 5: Finalize

1. Make both scripts executable: `chmod +x <hook-path> <test-path>`
2. Create `.claude/` directory if needed for settings.json
3. Run the test script to verify all test cases pass
4. Report summary:
   - List files created/modified
   - Show number of approve rules, deny rules
   - Show test results (pass/fail count)

## Post-Actions

After generating the hook:

1. Suggest committing the new files:
   ```
   scripts/permission-request.sh
   scripts/test-permission-hook.sh
   .claude/settings.json
   ```
2. If `--strict` was NOT used, mention the flag for environments where unknown commands should be denied
3. Explain how to add custom rules — edit the APPROVE/DENY sections of the generated script
4. Remind about `CLAUDE_HOOKS_DISABLE_PERMISSION_REQUEST=1` to toggle the hook off temporarily
5. Note that empty matcher `""` catches all tools; suggest narrowing to `"Bash"` if only Bash commands need filtering

## PermissionRequest Schema

### Input (via stdin)

| Field | Type | Description |
|---|---|---|
| `session_id` | string | Current session ID |
| `tool_name` | string | Tool being invoked (`Bash`, `Write`, `Edit`, `Read`, etc.) |
| `tool_input` | object | Tool-specific input (`.command` for Bash, `.file_path` for Write/Edit) |
| `permission_type` | string | Always `"tool_use"` |
| `description` | string | Human-readable description of the operation |

### Output (via stdout)

| Decision | JSON | Effect |
|---|---|---|
| Approve | `{"decision":"approve","reason":"..."}` | Tool runs without user prompt |
| Deny | `{"decision":"deny","reason":"..."}` | Tool blocked, reason shown to Claude |
| Passthrough | Exit 0 with no output | User prompted as normal |

## Agentic Optimizations

| Context | Approach |
|---|---|
| Quick setup, all categories | `/hooks:permission-request-hook` |
| Strict mode (deny unknown commands) | `/hooks:permission-request-hook --strict` |
| Only git and test rules | `/hooks:permission-request-hook --category git --category test` |
| Only deny rules (block dangerous ops) | `/hooks:permission-request-hook --category deny` |
| Test the hook manually | `echo '{"tool_name":"Bash","tool_input":{"command":"git status"}}' \| bash scripts/permission-request.sh` |
| Disable hook temporarily | `CLAUDE_HOOKS_DISABLE_PERMISSION_REQUEST=1` |

## Quick Reference

| Item | Value |
|---|---|
| Hook event | `PermissionRequest` |
| Script location | `scripts/permission-request.sh` or `.claude/hooks/permission-request.sh` |
| Test script | `scripts/test-permission-hook.sh` |
| Settings location | `.claude/settings.json` |
| Timeout | 10 seconds |
| Matcher | `""` (all tools) |
| Toggle | `CLAUDE_HOOKS_DISABLE_PERMISSION_REQUEST=1` |
| Decisions | approve, deny, passthrough (no output) |
| Categories | `git`, `test`, `lint`, `build`, `gh`, `deny` |
