---
model: haiku
created: 2025-12-16
modified: 2026-02-10
reviewed: 2026-02-10
description: Check and configure MCP servers for project integration. Use when setting up MCP servers, checking MCP status, or adding new servers to a project.
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--core] [--server <name>]"
name: configure-mcp
---

# /configure:mcp

Check and configure Model Context Protocol (MCP) servers for this project.

**MCP Philosophy:** Servers are managed **project-by-project** (in `.mcp.json`), not user-scoped (in `~/.claude/settings.json`), to keep context clean and dependencies explicit.

For server configurations, environment variable reference, and report templates, see [REFERENCE.md](REFERENCE.md).

## Context

- Config exists: !`test -f .mcp.json && echo "EXISTS" || echo "MISSING"`
- Config contents: !`cat .mcp.json 2>/dev/null`
- Installed servers: !`cat .mcp.json 2>/dev/null | jq -r '.mcpServers | keys[]' 2>/dev/null`
- Git tracking: !`grep -q '.mcp.json' .gitignore 2>/dev/null && echo "IGNORED" || echo "NOT IGNORED"`
- Standards file: !`test -f .project-standards.yaml && echo "EXISTS" || echo "MISSING"`
- Has playwright config: !`find . -maxdepth 1 -name 'playwright.config.*' 2>/dev/null`
- Has TS/JS files: !`find . -maxdepth 2 -name '*.ts' -o -name '*.py' -o -name '*.go' -o -name '*.rs' 2>/dev/null | head -5`
- Dotfiles registry: !`test -f ~/.local/share/chezmoi/.chezmoidata.toml && echo "EXISTS" || echo "MISSING"`

## Parameters

Parse these from `$ARGUMENTS`:

- `--check-only`: Report current status, do not offer installation
- `--fix`: Install servers without prompting for confirmation
- `--core`: Install all core servers (`context7`, `sequential-thinking`)
- `--server <name>`: Install specific server by name (repeatable)

If no flags provided, run interactive mode (detect → report → offer to install).

## Core Servers

These servers should be installed in **all projects**:

| Server | Purpose | Env Vars |
|--------|---------|----------|
| `context7` | Documentation context from Upstash | None |
| `sequential-thinking` | Enhanced reasoning and planning | None |

## Execution

Execute this MCP configuration workflow:

### Step 1: Detect current state

Check the context values above. Determine:
1. Does `.mcp.json` exist? If yes, parse it and list all configured servers.
2. For each server, check its command type (`npx`, `bunx`, `uvx`, `go run`) and required env vars.
3. Flag any servers with missing required environment variables.

If `--check-only`, skip to Step 4 (report only).

### Step 2: Identify servers to install

Based on the flags:

- **`--core`**: Select `context7` and `sequential-thinking`.
- **`--server <name>`**: Select the named server(s). Validate against the available servers in [REFERENCE.md](REFERENCE.md).
- **No flags (interactive)**: Show the user what's installed vs available. Use AskUserQuestion to ask which servers to add. Suggest servers based on project context (e.g., suggest `playwright` if `playwright.config.*` exists, suggest `cclsp` if large TS/Python/Rust codebase).

If all requested servers are already installed, report "All servers already configured" and stop.

### Step 3: Install selected servers

For each selected server:

1. Get the server configuration from [REFERENCE.md](REFERENCE.md).
2. If `.mcp.json` doesn't exist, create it with `{"mcpServers": {}}`.
3. Merge the server config into the existing `mcpServers` object. Preserve existing servers.
4. Write the updated `.mcp.json` with proper JSON formatting.

If `cclsp` is selected, also set up `cclsp.json` (see [REFERENCE.md](REFERENCE.md) for language detection and setup details).

Handle git tracking:
- Check if `.mcp.json` is in `.gitignore`.
- If not tracked and not ignored, recommend adding to `.gitignore` for personal projects or tracking for team projects.

### Step 4: Report results

Print a summary using the report format from [REFERENCE.md](REFERENCE.md):
- List all configured servers with their status
- Flag missing environment variables with where to set them
- Show git tracking status
- If servers were added, show next steps (restart Claude Code, set env vars)

### Step 5: Update standards tracking

If `.project-standards.yaml` exists, update the MCP section with current server list and timestamp.

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering to install servers |
| `--fix` | Install specified or suggested servers without prompting |
| `--core` | Install all core servers (context7, sequential-thinking) |
| `--server <name>` | Install specific server (can be repeated) |

## Error Handling

- **Invalid `.mcp.json`**: Offer to backup and replace with valid template
- **Server already installed**: Skip with informational message
- **Missing env var**: Warn but continue (server may work with defaults)
- **Unknown server**: Report error with available server names
