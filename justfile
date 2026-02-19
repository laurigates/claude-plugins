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
    claude mcp add-json -s project github '{"command": "github-mcp-server", "args": ["stdio"], "env": {"GITHUB_TOKEN": "$GITHUB_TOKEN"}}'

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
    claude mcp add-json -s project chrome-devtools '{"command": "bunx", "args": ["chrome-devtools-mcp@latest"]}'

# Set up Claude Code Language Server Protocol
[group: "claude"]
cclsp:
    bunx cclsp@latest setup

####################
# Linting
####################

# Lint SKILL.md context commands for patterns that break backtick execution
[group: "lint"]
lint-context-commands *args:
    ./scripts/lint-context-commands.sh {{args}}

# Run plugin compliance checks (validates plugin.json, frontmatter, marketplace, release-please)
[group: "lint"]
lint-compliance *args:
    ./scripts/plugin-compliance-check.sh {{args}}

# Run blueprint health check (skill inventory, staleness, frontmatter completeness)
[group: "lint"]
lint-health:
    ./scripts/blueprint-health-check.sh

# Run infrastructure compliance check (registry sync, workflow health, versions, security)
[group: "lint"]
lint-infra:
    ./scripts/infra-compliance-check.sh

# Run all lint checks
[group: "lint"]
lint-all: lint-context-commands lint-compliance lint-health lint-infra

# Add all MCP servers and set up cclsp
[group: "claude"]
claude-setup: mcp-sentry mcp-github mcp-context7 mcp-playwright mcp-sequential-thinking mcp-chrome-devtools cclsp

####################
# GitHub
####################

# Rebase all open PRs onto their base branch
[group: "github"]
[confirm("This will rebase all open PRs. Continue?")]
pr-rebase-all:
    #!/usr/bin/env bash
    set -euo pipefail
    prs=$(gh pr list --json number,title --jq '.[].number')
    if [ -z "$prs" ]; then
        echo "No open PRs found"
        exit 0
    fi
    for pr in $prs; do
        title=$(gh pr view "$pr" --json title --jq '.title')
        printf "PR #%-5s %s ... " "$pr" "$title"
        if gh pr update-branch --rebase "$pr" 2>/dev/null; then
            echo "ok"
        else
            echo "FAILED"
        fi
    done
