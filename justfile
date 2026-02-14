# Justfile - Claude Code Plugin Collection
# Run `just` or `just help` to see available recipes

set positional-arguments

# Show available recipes
default:
    @just --list

####################
# Claude Code Setup
####################

# Add Sentry MCP server to project
[group: "claude"]
mcp-sentry:
    claude mcp add-json -s project sentry '{"type": "http", "url": "https://mcp.sentry.dev/mcp"}'

# Add GitHub MCP server to project
[group: "claude"]
mcp-github:
    claude mcp add-json -s project github '{"command": "github-mcp-server", "args": ["stdio"], "env": {"GITHUB_PERSONAL_ACCESS_TOKEN": "$GITHUB_PERSONAL_ACCESS_TOKEN"}}'

# Add Context7 MCP server (documentation lookup)
[group: "claude"]
mcp-context7:
    claude mcp add-json -s project context7 '{"command": "bunx", "args": ["-y", "@upstash/context7-mcp"]}'

# Add Playwright MCP server (browser automation)
[group: "claude"]
mcp-playwright:
    claude mcp add-json -s project playwright '{"command": "bunx", "args": ["-y", "@playwright/mcp@latest"]}'

# Add Sequential Thinking MCP server (multi-step reasoning)
[group: "claude"]
mcp-sequential-thinking:
    claude mcp add-json -s project sequential-thinking '{"command": "bunx", "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]}'

# Add Chrome DevTools MCP server
[group: "claude"]
mcp-chrome-devtools:
    claude mcp add-json -s project chrome-devtools '{"type": "stdio", "command": "bunx", "args": ["chrome-devtools-mcp@latest"], "env": {}}'

# Set up Claude Code Language Server Protocol
[group: "claude"]
cclsp:
    bunx cclsp@latest setup

# Add all MCP servers and set up cclsp
[group: "claude"]
claude-setup: mcp-sentry mcp-github mcp-context7 mcp-playwright mcp-sequential-thinking mcp-chrome-devtools cclsp
