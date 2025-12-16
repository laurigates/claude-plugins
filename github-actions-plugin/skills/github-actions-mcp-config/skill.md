---
name: GitHub Actions MCP Configuration
description: MCP server configuration for GitHub Actions including tool permissions, environment variables, and multi-server setups. Use when configuring MCP servers in GitHub Actions workflows.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, WebFetch
---

# GitHub Actions MCP Configuration

Expert knowledge for configuring MCP (Model Context Protocol) servers in GitHub Actions workflows, including tool permissions and multi-server coordination.

## Core Expertise

**MCP Server Configuration**
- Single and multi-server setups
- Environment variable management
- Server initialization and validation
- Tool permission patterns

**Tool Access Control**
- Allowed and disallowed tool patterns
- Command-specific permissions
- Security boundaries and restrictions
- Language-specific tool configurations

## MCP Server Configuration

### Single MCP Server (Node.js)
```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    claude_args: |
      --mcp-config '{"mcpServers":{"github":{"command":"node","args":["/path/to/server.js"]}}}'
```

### Multiple MCP Servers with Secrets
```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    claude_args: |
      --mcp-config '{
        "mcpServers": {
          "github": {
            "command": "node",
            "args": ["./github-mcp/dist/index.js"],
            "env": {"GITHUB_TOKEN": "${{ secrets.GITHUB_TOKEN }}"}
          },
          "postgres": {
            "command": "uvx",
            "args": ["mcp-server-postgres", "--connection-string", "${{ secrets.DB_URL }}"]
          }
        }
      }'
```

### Python MCP Server with uv
```yaml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    claude_args: |
      --mcp-config '{
        "mcpServers": {
          "data-processor": {
            "command": "uvx",
            "args": ["--from", "my-mcp-package", "run-server"],
            "env": {
              "API_KEY": "${{ secrets.API_KEY }}"
            }
          }
        }
      }'
```

## Tool Access Control

### Allow Specific Bash Commands
```yaml
claude_args: |
  --allowedTools 'Bash(npm:*)' 'Bash(pytest:*)' 'Bash(cargo:*)'
```

### Enable GitHub Actions Access
```yaml
permissions:
  actions: read  # Required for CI/CD tools

claude_args: |
  --allowedTools 'Bash(gh run:*)' 'Bash(gh workflow:*)'
```

### Allow Test and Lint Commands
```yaml
claude_args: |
  --allowedTools 'Bash(npm test:*)' 'Bash(npm run lint:*)' 'Bash(pre-commit:*)'
```

### Allow Build Commands with Restrictions
```yaml
claude_args: |
  --allowedTools 'Bash(make:*)' 'Bash(docker build:*)'
  --disallowedTools 'Bash(docker push:*)' 'Bash(rm -rf:*)'
```

### Block Dangerous Operations
```yaml
claude_args: |
  --allowedTools 'Bash(docker build:*)'
  --disallowedTools 'Bash(docker push:*)' 'Bash(rm -rf:*)' 'Bash(curl:*)' 'Bash(wget:*)'
```

## Tool Permission Reference

### Always Enabled (No Configuration Needed)
- `Read, Write, Edit, Glob, Grep` - File operations
- `mcp__github` - GitHub operations
- Basic Claude Code tools

### Language-Specific Tool Patterns

| Pattern | Purpose | Example |
|---------|---------|---------|
| `'Bash(npm:*)'` | All npm commands | `npm test`, `npm run build` |
| `'Bash(pytest:*)'` | Python testing | `pytest`, `pytest --cov` |
| `'Bash(cargo:*)'` | Rust commands | `cargo test`, `cargo build` |
| `'Bash(go test:*)'` | Go testing | `go test ./...` |
| `'Bash(git:*)'` | All git commands | `git status`, `git commit` |
| `'Bash(pre-commit:*)'` | Pre-commit hooks | `pre-commit run --all-files` |
| `'Bash(actionlint:*)'` | Action linting | `actionlint .github/workflows/` |
| `'Bash(gh:*)'` | GitHub CLI | `gh pr create`, `gh issue list` |

### Build and Deployment Tools

| Pattern | Purpose | Use Case |
|---------|---------|----------|
| `'Bash(make:*)'` | Make commands | Build automation |
| `'Bash(docker build:*)'` | Docker build only | Container creation |
| `'Bash(kubectl:*)'` | Kubernetes CLI | K8s operations |
| `'Bash(terraform:*)'` | Infrastructure as Code | Terraform operations |

## MCP Server Best Practices

**Configuration**
- Always use GitHub secrets for sensitive credentials
- Validate MCP server availability before workflow execution
- Use environment variables for dynamic configuration
- Document required secrets in repository README
- Test MCP servers locally before deploying to CI

**Error Handling**
```yaml
# Verify server availability
- run: node ./mcp-server/index.js --version

# Check environment variables
- run: env | grep API_KEY

# Test server locally
- run: |
    cd mcp-server
    npm install
    npm test
```

**Security**
- Never hardcode credentials in MCP configuration
- Use minimal required permissions for tools
- Validate server command paths
- Restrict network access when possible
- Audit MCP server dependencies

## Environment-Specific Configuration

### Development Environment
```yaml
# development.yml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    claude_args: |
      --max-turns 20
      --allowedTools 'Bash(npm:*)' 'Bash(git:*)'
```

### Production Environment
```yaml
# production.yml
- uses: anthropics/claude-code-action@v1
  with:
    anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
    claude_args: |
      --max-turns 10
      --allowedTools 'Bash(npm test:*)' 'Bash(npm run lint:*)'
      --disallowedTools 'Bash(npm publish:*)'
```

## Multi-Repository Setup

### Organization-Wide Template
```yaml
# .github/workflows/claude-template.yml
name: Claude Code Template

on:
  workflow_call:
    secrets:
      ANTHROPIC_API_KEY:
        required: true
      MCP_SECRETS:
        required: false

jobs:
  claude:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          claude_args: |
            --mcp-config '${{ secrets.MCP_SECRETS }}'
```

## Troubleshooting

### MCP Server Errors
```bash
# Verify server availability
node ./mcp-server/index.js --version

# Check environment variables
env | grep API_KEY

# Test server locally
cd mcp-server && npm install && npm test
```

### Tool Access Issues
```yaml
# Enable specific tools
claude_args: |
  --allowedTools 'Bash(npm:*)' 'Bash(git:*)'

# Check tool syntax
# Correct: 'Bash(npm:*)'
# Wrong:   'Bash(npm *)'

# Verify additional_permissions
additional_permissions:
  actions: read
```

### Configuration Validation
```bash
# Validate workflow syntax
actionlint .github/workflows/claude.yml

# Test locally (with act)
act -j claude

# Check workflow logs
gh run list --workflow=claude.yml
```

## Quick Reference

### Configuration Options

| Option | Purpose | Example |
|--------|---------|---------|
| `--mcp-config` | Configure MCP servers | `--mcp-config '{...}'` |
| `--allowedTools` | Permit specific tools | `'Bash(npm:*)'` |
| `--disallowedTools` | Block specific tools | `'Bash(rm -rf:*)'` |
| `--max-turns` | Limit conversation length | `--max-turns 10` |

### Required Secrets

| Secret | Purpose | Format |
|--------|---------|--------|
| `ANTHROPIC_API_KEY` | Claude API access | `sk-ant-api03-...` |
| `GITHUB_TOKEN` | GitHub operations | Auto-provided by Actions |
| `DB_URL` | Database connection | Custom format |
| `API_KEY` | Custom MCP server auth | Service-specific |

For authentication methods and security best practices, see the github-actions-auth-security skill. For workflow design patterns, see the claude-code-github-workflows skill.
