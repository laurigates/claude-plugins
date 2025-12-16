---
description: Check and configure MCP servers for project integration
allowed-tools: Glob, Grep, Read, Write, Edit, Bash, AskUserQuestion, TodoWrite
argument-hint: "[--check-only] [--fix] [--server <name>]"
---

# /configure:mcp

Check and configure Model Context Protocol (MCP) servers for this project.

## Context

This command validates MCP server configuration and installs servers from the favorites registry.

**MCP Philosophy:** Servers are managed **project-by-project** to avoid context bloat:
- ❌ **User-scoped** (in `~/.claude/settings.json`) - Bloated context everywhere
- ✅ **Project-scoped** (in `.mcp.json`) - Clean context, explicit dependencies, team-shareable

## Workflow

### Phase 1: Current State Detection

Check for existing MCP configuration:

| File | Purpose | Status |
|------|---------|--------|
| `.mcp.json` | Project MCP configuration | EXISTS / MISSING |
| `~/.claude/settings.json` | User-level MCP (discouraged) | CHECK |

### Phase 2: Current Configuration Analysis

For existing `.mcp.json`, analyze:

- [ ] File exists and is valid JSON
- [ ] mcpServers object present
- [ ] Installed servers list
- [ ] Environment variable references validated
- [ ] Required env vars documented

**Currently Installed Servers:**
List each server with:
- Name
- Command type (npx, bunx, uvx, go run)
- Required environment variables
- Status (✅ configured / ⚠️ missing env var)

### Phase 3: Compliance Report

```
MCP Configuration Report
========================
Project: [name]
Config file: .mcp.json

Installed Servers:
  github                    go run           [✅ CONFIGURED | ⚠️ NEEDS GITHUB_TOKEN]
  playwright                bunx             [✅ CONFIGURED]
  pal                       uvx              [✅ CONFIGURED]
  context7                  bunx             [✅ CONFIGURED]

Environment Variables:
  GITHUB_TOKEN              ~/.api_tokens    [✅ SET | ❌ MISSING]
  ARGOCD_SERVER             project .env     [✅ SET | ❌ MISSING]
  ARGOCD_AUTH_TOKEN         project .env     [✅ SET | ❌ MISSING]

Git Tracking:
  .mcp.json                 .gitignore       [✅ IGNORED | ⚠️ TRACKED | ❌ NOT FOUND]

Overall: [X issues found]

Recommendations:
  - Add 'github' server for GitHub API integration
  - Set GITHUB_TOKEN in ~/.api_tokens
  - Add .mcp.json to .gitignore for personal projects
```

### Phase 4: Available MCP Servers

**From dotfiles favorites registry** (`~/.local/share/chezmoi/.chezmoidata.toml`):

**Memory & Knowledge:**
- `graphiti-memory` - Graph-based memory and knowledge management
- `context7` - Upstash context management

**Testing & Automation:**
- `playwright` - Browser automation and testing

**Version Control:**
- `github` - GitHub API integration (issues, PRs, repos)

**Productivity:**
- `pal` - PAL (Provider Abstraction Layer) - Multi-provider LLM integration
- `podio-mcp` - Podio project management integration

**Infrastructure & Monitoring:**
- `argocd-mcp` - ArgoCD GitOps deployment management
- `sentry` - Sentry error tracking and monitoring

**AI Enhancement:**
- `sequential-thinking` - Enhanced reasoning with sequential thinking

### Phase 5: Configuration (if --fix or user confirms)

#### Server Configurations

```json
{
  "graphiti-memory": {
    "command": "npx",
    "args": ["-y", "@getzep/graphiti-mcp-server"],
    "env": { "GRAPHITI_API_KEY": "${GRAPHITI_API_KEY}" }
  },
  "pal": {
    "command": "uvx",
    "args": [
      "--from",
      "git+https://github.com/BeehiveInnovations/pal-mcp-server.git",
      "pal-mcp-server"
    ]
  },
  "playwright": {
    "command": "bunx",
    "args": ["-y", "@playwright/mcp@latest"]
  },
  "context7": {
    "command": "bunx",
    "args": ["-y", "@upstash/context7-mcp"]
  },
  "github": {
    "command": "go",
    "args": [
      "run",
      "github.com/github/github-mcp-server/cmd/github-mcp-server@latest",
      "stdio"
    ]
  },
  "podio-mcp": {
    "command": "bunx",
    "args": ["https://github.com/ForumViriumHelsinki/podio-mcp"],
    "env": {
      "PODIO_CLIENT_ID": "${PODIO_CLIENT_ID}",
      "PODIO_CLIENT_SECRET": "${PODIO_CLIENT_SECRET}",
      "PODIO_APP_ID": "${PODIO_APP_ID}",
      "PODIO_APP_TOKEN": "${PODIO_APP_TOKEN}"
    }
  },
  "argocd-mcp": {
    "command": "bunx",
    "args": ["-y", "argocd-mcp@latest", "stdio"],
    "env": {
      "ARGOCD_SERVER": "${ARGOCD_SERVER}",
      "ARGOCD_AUTH_TOKEN": "${ARGOCD_AUTH_TOKEN}"
    }
  },
  "sequential-thinking": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
  }
}
```

#### Installation Steps

1. **Ask which servers to install** (unless --server specified):
   - Use AskUserQuestion with multi-select
   - Show descriptions and required env vars
   - Suggest based on project type (e.g., playwright if `playwright.config.*` exists)

2. **Create/update `.mcp.json`**:
   - If missing, create new file with mcpServers object
   - If exists, merge new servers (preserve existing)
   - Use proper JSON formatting

3. **Handle environment variables**:
   - Document required variables for each server
   - Check if set in `~/.api_tokens` or project `.env`
   - Warn about missing required variables

4. **Git tracking recommendation**:
   - Personal projects → recommend `.gitignore` (keep API configs local)
   - Team projects → recommend tracking (share MCP setup with team)

### Phase 6: Environment Variable Reference

| Server | Required Variables | Where to Set |
|--------|-------------------|--------------|
| `github` | `GITHUB_TOKEN` | `~/.api_tokens` |
| `graphiti-memory` | `GRAPHITI_API_KEY` | `~/.api_tokens` |
| `podio-mcp` | `PODIO_CLIENT_ID`, `PODIO_CLIENT_SECRET`, `PODIO_APP_ID`, `PODIO_APP_TOKEN` | project `.env` |
| `argocd-mcp` | `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN` | project `.env` |
| `sentry` | `SENTRY_AUTH_TOKEN` | `~/.api_tokens` |

**Never hardcode tokens in `.mcp.json`** - always use `${VAR_NAME}` references.

### Phase 7: Standards Tracking

Update `.fvh-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  mcp: "2025.1"
  mcp_servers: ["github", "playwright", "context7"]
  mcp_project_scoped: true
```

### Phase 8: Final Report

```
MCP Configuration Complete
==========================

Servers Added:
  ✅ github (requires GITHUB_TOKEN)
  ✅ playwright
  ✅ context7

Environment Variables:
  ⚠️ Set GITHUB_TOKEN in ~/.api_tokens or project .env

Git Tracking:
  ✅ .mcp.json added to .gitignore

Next Steps:
  1. Restart Claude Code to load new MCP servers
  2. Set required environment variables
  3. Verify servers are loaded (check status bar)

Tip: Run /configure:mcp again to add more servers anytime.
```

## Flags

| Flag | Description |
|------|-------------|
| `--check-only` | Report status without offering to install servers |
| `--fix` | Install specified or suggested servers without prompting |
| `--server <name>` | Install specific server (can be repeated) |

## Examples

```bash
# Check current MCP configuration
/configure:mcp --check-only

# Interactive server installation
/configure:mcp

# Install specific servers automatically
/configure:mcp --fix --server github --server playwright

# Quick add github server
/configure:mcp --server github
```

## Error Handling

- **Invalid `.mcp.json`**: Offer to backup and replace with valid template
- **Server already installed**: Skip with informational message
- **Missing env var**: Warn but don't fail (server may work with defaults)
- **Unknown server**: Error with suggestion to check registry

## See Also

- `/configure:all` - Run all FVH compliance checks
- **MCP Management skill** - Intelligent server suggestions based on project
- **Dotfiles registry**: `~/.local/share/chezmoi/.chezmoidata.toml`
