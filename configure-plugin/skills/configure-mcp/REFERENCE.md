# MCP Server Reference

## Server Configurations

Use these JSON configurations when adding servers to `.mcp.json`:

```json
{
  "pal": {
    "command": "pal-mcp-server"
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

## Environment Variable Reference

| Server | Required Variables | Where to Set |
|--------|-------------------|--------------|
| `github` | `GITHUB_TOKEN` | `~/.api_tokens` |
| `argocd-mcp` | `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN` | project `.env` |
| `sentry` | `SENTRY_AUTH_TOKEN` | `~/.api_tokens` |

Use `${VAR_NAME}` references in `.mcp.json` — never hardcode tokens.

## Available Servers (Full Registry)

**Context & Knowledge:**
- `context7` - Upstash context management (no env vars)

**AI Enhancement:**
- `sequential-thinking` - Enhanced reasoning with sequential thinking (no env vars)

**Testing & Automation:**
- `playwright` - Browser automation and testing (no env vars)

**Version Control:**
- `github` - GitHub API integration (requires `GITHUB_TOKEN`)

**Productivity:**
- `pal` - PAL (Provider Abstraction Layer) - Multi-provider LLM integration (no env vars). Install once with `uv tool install git+https://github.com/laurigates/pal-mcp-server`; the `.mcp.json` entry then invokes the bare `pal-mcp-server` command instead of re-resolving the git source via `uvx` on every launch.

**Infrastructure & Monitoring:**
- `argocd-mcp` - ArgoCD GitOps deployment management (requires `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN`)
- `sentry` - Sentry error tracking and monitoring (requires `SENTRY_AUTH_TOKEN`)

**Code intelligence** is no longer an MCP concern. Claude Code has a native LSP
client; language servers come from the official `*-lsp` plugins (`rust-analyzer-lsp`,
`typescript-lsp`, `pyright-lsp`, `gopls-lsp`, `clangd-lsp`, ...), enabled per user
rather than per project. Do not add an LSP bridge to `.mcp.json`.

Known trap: those plugins declare `lspServers` only in the marketplace's
`marketplace.json`, while the runtime reads it from the installed plugin's
`.claude-plugin/plugin.json` — so they install inert, with
`getAllLspServers returned 0 server(s)` and no warning. Upstream:
anthropics/claude-code#15148.

## Report Templates

### Compliance Report Format

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

Git Tracking:
  .mcp.json                 .gitignore       [✅ IGNORED | ⚠️ TRACKED | ❌ NOT FOUND]

Overall: [X issues found]
```

### Completion Report Format

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
```

## Remote MCP Servers (HTTP+SSE with OAuth)

For remote servers using HTTP+SSE transport (Claude Code 2.1.50+):

```json
{
  "my-remote-server": {
    "url": "https://mcp.example.com/sse",
    "headers": {
      "Authorization": "Bearer ${MY_API_TOKEN}"
    }
  }
}
```

### OAuth Authentication Flow

1. Claude Code discovers OAuth metadata from `/.well-known/oauth-authorization-server` (cached per server URL)
2. User authorizes in the browser on first use
3. Token is persisted and reused across sessions
4. Step-up auth triggered mid-session when a tool requires additional scopes

### Remote Server Notes

- Use `${VAR_NAME}` in header values — never hardcode tokens
- Discovery metadata is cached; use `/mcp disable` + `/mcp enable` to force refresh
- Remote servers using OAuth do not need `env` block; use `headers` with Bearer token instead
- Step-up auth is automatic — Claude Code handles re-authorization prompts

## Standards Tracking Template

Update `.project-standards.yaml`:

```yaml
standards_version: "2025.1"
last_configured: "[timestamp]"
components:
  mcp: "2025.1"
  mcp_servers: ["github", "playwright", "context7"]
  mcp_project_scoped: true
```
