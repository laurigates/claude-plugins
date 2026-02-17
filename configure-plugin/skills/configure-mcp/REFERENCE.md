# MCP Server Reference

## Server Configurations

Use these JSON configurations when adding servers to `.mcp.json`:

```json
{
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
  },
  "cclsp": {
    "command": "npx",
    "args": ["-y", "cclsp@latest"],
    "env": {
      "CCLSP_CONFIG_PATH": "./cclsp.json"
    }
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
- `pal` - PAL (Provider Abstraction Layer) - Multi-provider LLM integration (no env vars)

**Infrastructure & Monitoring:**
- `argocd-mcp` - ArgoCD GitOps deployment management (requires `ARGOCD_SERVER`, `ARGOCD_AUTH_TOKEN`)
- `sentry` - Sentry error tracking and monitoring (requires `SENTRY_AUTH_TOKEN`)

**Code Intelligence (optional):**
- `cclsp` - LSP navigation (find-references, go-to-definition, rename) for TS/Python/Rust projects

## cclsp Setup Details

When installing `cclsp`, create `cclsp.json` in the project root with language servers based on detected project files:

| Files Present | Language Server Entry |
|---------------|----------------------|
| `*.ts`, `*.tsx`, `*.js`, `*.jsx` | `{"extensions": ["js", "ts", "jsx", "tsx", "mjs", "cjs"], "command": ["typescript-language-server", "--stdio"], "rootDir": "."}` |
| `*.py` | `{"extensions": ["py", "pyi"], "command": ["pylsp"], "rootDir": "."}` |
| `*.go` | `{"extensions": ["go"], "command": ["gopls", "serve"], "rootDir": "."}` |
| `*.rs` | `{"extensions": ["rs"], "command": ["rust-analyzer"], "rootDir": "."}` |

Write `cclsp.json` with detected servers:
```json
{
  "servers": [
    // entries based on detected languages
  ]
}
```

Add `cclsp.json` to `.gitignore` (machine-specific language server paths).

Required language server installations:
- TypeScript: `npm i -g typescript-language-server`
- Python: `pip install python-lsp-server`
- Go: `go install golang.org/x/tools/gopls@latest`
- Rust: Install via `rustup component add rust-analyzer`

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
