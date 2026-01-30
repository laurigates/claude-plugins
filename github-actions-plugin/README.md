# GitHub Actions Plugin

**Complete toolkit for GitHub Actions CI/CD workflows, automation, authentication, and inspection.**

This plugin provides comprehensive support for designing, implementing, and managing GitHub Actions workflows and CI/CD pipelines.

## What's Inside

### Commands

Located in `commands/workflow/`:

- **dev.md** - Automated development loop with issue creation and TDD
  - Continuous development cycles with issue tracking
  - Test-driven development workflows
  - GitHub issue integration
  - Automated PR creation and CI monitoring

- **dev-zen.md** - AI-powered development loop with PAL MCP integration
  - Enhanced development automation with code review
  - Plan generation using multiple AI models
  - Pre-commit checks and validation
  - GitHub issue consideration during planning

### Skills

All skills are located in the `skills/` directory:

#### Core GitHub Actions Skills

- **claude-code-github-workflows** - Workflow design and automation patterns
  - PR review automation
  - Issue triage workflows
  - CI failure auto-fix
  - Custom trigger configurations
  - Path-filtered reviews
  - External contributor handling

- **github-actions-auth-security** - Authentication and security
  - Anthropic Direct API configuration
  - AWS Bedrock with OIDC
  - Google Vertex AI setup
  - Secrets management and rotation
  - Permission scoping
  - Commit signing
  - Prompt injection prevention

- **github-actions-mcp-config** - MCP server configuration
  - Single and multi-server setups
  - Tool permission patterns
  - Environment variable management
  - Language-specific tool configurations
  - Security best practices

- **github-actions-inspection** - Workflow debugging and inspection
  - Workflow run status checking
  - Log analysis and error extraction
  - Flaky test identification
  - Performance timing analysis
  - Common failure pattern diagnosis

#### GitHub Integration Skills

- **github-issue-search** - Search for solutions in GitHub issues
  - Error message-based searching
  - Symptom and version-specific queries
  - Workaround discovery
  - Repository identification from stack traces
  - Best practices for effective searching

- **github-social-preview** - Generate repository social preview images
  - Open Graph image creation for repositories
  - 1280x640 optimized preview images
  - Integration with nano-banana-pro
  - Multiple design templates
  - Post-generation optimization

### Agent

Located in `agents/`:

- **cicd-pipelines** - Pipeline Engineer agent
  - CI/CD pipeline architecture design
  - GitHub Actions workflow optimization
  - Deployment strategy implementation
  - Build and test automation
  - Pipeline security and compliance
  - Performance optimization

## Use Cases

### Workflow Development

- Design and implement GitHub Actions workflows
- Configure authentication and secrets management
- Set up MCP servers with proper tool permissions
- Create custom composite actions
- Implement matrix builds for multi-platform testing

### CI/CD Automation

- Automated PR reviews with inline comments
- Issue triage and labeling
- CI failure auto-fix workflows
- Deployment orchestration
- Security scanning integration

### Debugging and Monitoring

- Inspect workflow run status and logs
- Analyze test failures and identify flaky tests
- Extract error messages and stack traces
- Monitor workflow performance
- Compare working vs failing runs

### Issue Management

- Search GitHub issues for error solutions
- Find workarounds for known bugs
- Identify relevant discussions and fixes
- Track upstream issues

### Repository Enhancement

- Generate professional social preview images
- Create Open Graph images for better sharing
- Optimize images for social media platforms

## Getting Started

### Prerequisites

- GitHub CLI (`gh`) installed and authenticated
- Access to GitHub repositories
- For workflows: ANTHROPIC_API_KEY secret configured

### Basic Workflow Setup

1. Create `.github/workflows/claude.yml`:

```yaml
name: Claude Code

on:
  issue_comment:
    types: [created]
  pull_request:
    types: [opened, synchronize]

jobs:
  claude:
    if: contains(github.event.comment.body, '@claude')
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
```

2. Add repository secret: `ANTHROPIC_API_KEY`

3. Test by creating an issue and commenting `@claude`

### Inspecting Workflows

```bash
# List recent workflow runs
gh run list --workflow=ci.yml --limit 10

# View failed logs
gh run view <run-id> --log-failed

# Extract errors
gh run view <run-id> --log-failed | grep -i "error\|failed"
```

### Searching for Solutions

When encountering an error:

1. Extract key terms from error message
2. Identify repository from stack trace or package.json
3. Search GitHub issues:
   ```
   "error keywords repo:org/repo is:closed"
   ```
4. Review high-priority results (recently updated, many comments)
5. Extract and test workarounds

### Development Automation

Use workflow commands for automated development:

```bash
# Standard development loop
/workflow:dev

# Limit to 3 cycles
/workflow:dev --max-cycles 3

# Focus on bugs only
/workflow:dev --focus bug

# AI-enhanced with code review
/workflow:dev-zen
```

## Examples

### CI Failure Auto-Fix

```yaml
name: Auto-Fix CI Failures

on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]

jobs:
  auto-fix:
    if: github.event.workflow_run.conclusion == 'failure'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Analyze the CI failure, identify root cause,
            implement fix, and create PR
```

### Path-Filtered Reviews

```yaml
name: Review Backend Changes

on:
  pull_request:
    paths:
      - 'backend/**'
      - 'api/**'

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            Review backend changes focusing on:
            - API design
            - Database optimization
            - Security vulnerabilities
```

### Issue Search Integration

```javascript
// In your debugging workflow
const { searchIssues } = require('@octokit/plugin-search-issues');

// Search for error in repository
const results = await searchIssues({
  query: "ENOENT no such file repo:nodejs/node is:closed",
  sort: "updated",
  order: "desc"
});
```

## Configuration

### Tool Permissions

Configure allowed tools in workflows:

```yaml
claude_args: |
  --allowedTools 'Bash(npm *)' 'Bash(pytest *)' 'Bash(git *)'
  --disallowedTools 'Bash(rm -rf *)' 'Bash(curl *)'
```

### MCP Server Setup

Configure MCP servers with secrets:

```yaml
claude_args: |
  --mcp-config '{
    "mcpServers": {
      "github": {
        "command": "node",
        "args": ["./github-mcp/dist/index.js"],
        "env": {"GITHUB_TOKEN": "${{ secrets.GITHUB_TOKEN }}"}
      }
    }
  }'
```

### Security Best Practices

- Always use `${{ secrets.SECRET_NAME }}` for credentials
- Implement minimal required permissions
- Validate external inputs
- Enable commit signing (automatic with `contents: write`)
- Use OIDC for cloud provider authentication

## Troubleshooting

### Workflow Not Triggering

- Check trigger conditions in `if:` clause
- Verify permissions (contents, pull-requests, issues)
- Check GitHub App installation

### Authentication Failures

```bash
# Verify secret exists
gh secret list

# Test API key
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01"
```

### CI Failures

```bash
# Find failing runs
gh run list --status=failure --limit 5

# View detailed logs
gh run view <run-id> --log-failed

# Extract specific errors
gh run view <run-id> --log-failed | grep -E "FAIL|Error" -A 5
```

### Tool Access Issues

- Enable specific tools with `--allowedTools`
- Check tool syntax: `'Bash(npm *)'` not `'Bash(npm *)'`
- Verify permissions include `actions: read` for CI/CD tools

## Integration

This plugin works well with:

- **git-plugin** - For Git operations and repository management
- **testing-plugin** - For test execution and analysis
- **code-quality-plugin** - For linting and code quality checks
- **python-plugin** / **typescript-plugin** - For language-specific workflows

## Resources

### Official Documentation

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Claude Code Action](https://github.com/anthropics/claude-code-action)
- [GitHub CLI Manual](https://cli.github.com/manual/)

### Skills Reference

Each skill has detailed documentation including:
- Use cases and when to apply
- Configuration examples
- Best practices
- Troubleshooting guides
- Real-world scenarios

Refer to individual skill files in `skills/` for comprehensive guides.

## Contributing

When adding or modifying workflows:

1. Follow GitHub Actions best practices
2. Use proper security measures (secrets, permissions)
3. Test locally when possible (with `act`)
4. Validate workflow syntax with `actionlint`
5. Document any new patterns or configurations

## License

MIT License - See repository root for details.

## Support

For issues or questions:

1. Check skill documentation in `skills/` directory
2. Review workflow examples in this README
3. Search GitHub issues for similar problems
4. Use the `cicd-pipelines` agent for complex pipeline design

---

**Part of the Claude Plugins collection** - Modular, composable skills and agents for Claude Code.
