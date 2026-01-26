# Claude Code Hooks

This directory contains hooks that enforce best practices and remind Claude to use the correct tools.

## bash-antipatterns.sh

A PreToolUse hook that intercepts Bash commands and blocks those that should use built-in tools instead.

### Anti-patterns Detected

| Pattern | Reminder |
|---------|----------|
| `cat file` | Use **Read** tool instead |
| `head`/`tail file` | Use **Read** tool with offset/limit |
| `sed -i` | Use **Edit** tool instead |
| `echo > file` | Use **Write** tool instead |
| `cat > file` | Use **Write** tool instead |
| `timeout cmd` | Remove timeout (Bash tool has its own, human approval time exceeds it anyway) |
| `find` | Use **Glob** tool instead |
| `grep`/`rg` | Use **Grep** tool instead |
| `ls *pattern*` | Consider **Glob** tool |
| `cat/tail ...tasks/*.output` | Use **TaskOutput** tool instead |
| `sleep && cat/tail` | Use **TaskOutput** tool with block parameter |
| `git X && git Y` | Run git commands as separate Bash calls (avoids index.lock race condition) |

### How It Works

1. The hook receives JSON input from Claude Code containing the Bash command
2. It extracts the command and checks against known anti-patterns
3. If an anti-pattern is detected, it exits with code 2 (blocking error) and prints a helpful reminder
4. The reminder is shown to Claude, who will then use the correct tool

### Configuration

The hook is configured in `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/.claude/hooks/bash-antipatterns.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Testing

To test the hook manually:

```bash
echo '{"tool_input": {"command": "cat README.md"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 2 (blocked)

echo '{"tool_input": {"command": "git status"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 0 (allowed)

echo '{"tool_input": {"command": "git stash && git checkout -b branch"}}' | bash .claude/hooks/bash-antipatterns.sh
echo $?  # Should be 2 (blocked - chained git commands cause lock race conditions)
```

### Customization

Edit `bash-antipatterns.sh` to:
- Add new anti-patterns
- Modify reminder messages
- Adjust detection regex patterns
- Whitelist specific commands

### Exit Codes

- **0**: Command allowed
- **2**: Command blocked with reminder (Claude sees the message)

---

## validate-kubectl-context.sh

A PreToolUse hook that enforces explicit Kubernetes context selection to prevent accidental operations on the wrong cluster.

### Why This Hook Exists

Running `kubectl` or `helm` commands without specifying `--context` uses whatever context is currently active in your kubeconfig. This can lead to:

- Accidentally deploying to production instead of staging
- Deleting resources from the wrong cluster
- Applying configuration changes to unintended environments

This hook blocks kubectl/helm commands that don't explicitly specify their target context, forcing the agent to be explicit about which cluster it's operating on.

### Commands Blocked

| Tool | Flag Required | Example |
|------|---------------|---------|
| `kubectl` | `--context=NAME` | `kubectl --context=staging get pods` |
| `helm` | `--kube-context=NAME` | `helm --kube-context=production list` |

### Safe Commands (Not Blocked)

Some commands are safe without context specification:

**kubectl safe commands:**
- `kubectl config` (manages kubeconfig, not cluster resources)
- `kubectl version` (shows client/server versions)
- `kubectl api-resources` (lists available resources)
- `kubectl api-versions` (lists API versions)
- `kubectl explain` (shows resource documentation)
- `kubectl completion` (shell completion)

**helm safe commands:**
- `helm version` / `helm completion` / `helm env`
- `helm repo` (manages chart repositories)
- `helm search` (searches for charts)
- `helm show` (shows chart information)
- `helm plugin` (manages plugins)
- `helm create` / `helm package` / `helm template` (local chart operations)

### Configuration

**Automatic (via plugin):** This hook is automatically enabled when the hooks-plugin is installed. The configuration is included in `plugin.json`.

**Manual (standalone):** To use this hook without the full plugin, add to your `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/validate-kubectl-context.sh",
            "timeout": 3000
          }
        ]
      }
    ]
  }
}
```

### Testing

```bash
# Should be blocked (no context)
echo '{"tool_input": {"command": "kubectl get pods"}}' | bash validate-kubectl-context.sh
echo $?  # 2

# Should be allowed (has context)
echo '{"tool_input": {"command": "kubectl --context=staging get pods"}}' | bash validate-kubectl-context.sh
echo $?  # 0

# Should be allowed (safe command)
echo '{"tool_input": {"command": "kubectl config get-contexts"}}' | bash validate-kubectl-context.sh
echo $?  # 0

# Helm - should be blocked
echo '{"tool_input": {"command": "helm list"}}' | bash validate-kubectl-context.sh
echo $?  # 2

# Helm - should be allowed
echo '{"tool_input": {"command": "helm --kube-context=production list"}}' | bash validate-kubectl-context.sh
echo $?  # 0
```

### Error Message

When blocked, the agent receives a helpful message explaining:
- Why the context is required
- How to specify the context
- How to list available contexts
- Example commands with proper context usage
