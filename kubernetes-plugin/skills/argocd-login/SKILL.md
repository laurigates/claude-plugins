---
name: argocd-login
description: |
  ArgoCD CLI authentication with SSO. Provides argocd login command, gRPC-Web
  configuration, and post-login operations. Use when user mentions ArgoCD login,
  argocd authentication, SSO auth, or accessing ArgoCD applications and clusters.
---

# ArgoCD CLI Login

ArgoCD CLI authentication with SSO for the Data Portal cluster.

## When to Use

Use this skill automatically when:
- User requests ArgoCD login or authentication
- User mentions accessing ArgoCD cluster or applications
- User needs to interact with ArgoCD CLI tools
- Authentication errors occur when using ArgoCD commands

## Authentication Command

```bash
argocd login argocd.dataportal.fi --grpc-web --sso
```

### Command Breakdown

- `argocd.dataportal.fi` - Data Portal ArgoCD server endpoint
- `--grpc-web` - Enable gRPC-Web protocol (required for web-based SSO)
- `--sso` - Use Single Sign-On authentication (opens browser for OAuth2 flow)

## Usage Flow

1. **Detect authentication need:**
   - User explicitly requests login
   - ArgoCD command fails with authentication error
   - User mentions accessing ArgoCD cluster

2. **Execute login command:**
   ```bash
   argocd login argocd.dataportal.fi --grpc-web --sso
   ```

3. **Guide user through SSO:**
   - Command will open browser automatically
   - User completes SSO authentication in browser
   - CLI receives token upon successful authentication
   - Session is stored in `~/.config/argocd/config`

4. **Verify authentication:**
   ```bash
   argocd account get-user-info
   ```

## Common ArgoCD Operations (Post-Login)

### Application Management
```bash
# List applications
argocd app list

# Get application details
argocd app get <app-name>

# Sync application
argocd app sync <app-name>

# View application resources
argocd app resources <app-name>
```

### Cluster Information
```bash
# List clusters
argocd cluster list

# Get cluster info
argocd cluster get <cluster-name>
```

### Project Management
```bash
# List projects
argocd proj list

# Get project details
argocd proj get <project-name>
```

## Authentication Session

- **Session storage:** `~/.config/argocd/config`
- **Session persistence:** Tokens have configurable expiration
- **Re-authentication:** Run login command again when session expires

## Troubleshooting

### Browser doesn't open
- Manually open the URL printed by the CLI
- Complete authentication in browser
- Token will be received by CLI

### gRPC-Web errors
- Ensure `--grpc-web` flag is present
- Check network connectivity to `argocd.dataportal.fi`
- Verify firewall/proxy settings allow gRPC-Web traffic

### SSO failures
- Verify SSO provider is accessible
- Check browser for authentication prompts
- Ensure popup blockers aren't interfering
- Try incognito/private browsing mode

### Token expiration
- Re-run login command: `argocd login argocd.dataportal.fi --grpc-web --sso`
- Check token validity: `argocd account get-user-info`

## Integration with ArgoCD MCP

This skill complements the ArgoCD MCP server tools:
- MCP tools (`mcp__argocd-mcp__*`) require authenticated CLI session
- Use this skill to establish authentication before MCP operations
- Both use same configuration (`~/.config/argocd/config`)

## Security Considerations

- **Token storage:** CLI tokens stored locally in config file
- **Token scope:** Full ArgoCD access (read/write based on RBAC)
- **Token rotation:** Re-authenticate periodically for security
- **Shared sessions:** CLI and MCP share authentication state

## Example Interaction

```
User: "I need to check the status of my ArgoCD applications"

Claude: I'll log you into ArgoCD first, then check the application status.

[Executes: argocd login argocd.dataportal.fi --grpc-web --sso]

Please complete the SSO authentication in the browser that just opened.
Once authenticated, I'll retrieve your application list.

[After successful auth, executes: argocd app list]

Here are your applications:
...
```

## Related Skills

- **Kubernetes Operations** - For kubectl operations on ArgoCD-managed resources
- **GitHub Actions Inspection** - For CI/CD pipeline integration with ArgoCD
- **Infrastructure Terraform** - For infrastructure managed by ArgoCD applications

## References

- [ArgoCD CLI Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd/)
- [ArgoCD SSO Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/#sso)
- [gRPC-Web Protocol](https://github.com/grpc/grpc-web)
