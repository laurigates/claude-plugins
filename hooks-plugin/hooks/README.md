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
| `git add -A` / `git add .` | Stage specific files by name instead of broad staging |
| `git X && git Y` | Run git commands as separate Bash calls (avoids index.lock race condition) |
| `git reset --hard` | Use safer alternatives; if truly needed, ask user to run manually |

### Handling Blocked Commands

When a command is blocked:

1. **Read the reminder** - It explains why and suggests alternatives
2. **Use the alternative** - Most of the time, the suggested approach is correct
3. **If truly needed** - Don't retry; ask the user to run the command manually with an explanation

**Important**: User permission does not bypass hook blocks. If a command is blocked, retrying will fail again. For rare edge cases where the blocked command is legitimately required, ask the user to run it manually and explain why.

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

---

## git-stash-reminder.sh

A Stop hook that checks for orphaned git stashes before Claude exits. Stashes created during a session (branch switches, conflict resolution) are easily forgotten — this hook blocks the exit until they're addressed.

### Behavior

| Stash Age | Classification | Recommendation |
|-----------|---------------|----------------|
| < 2 hours | Recent | `git stash pop` (likely from this session) |
| >= 2 hours | Stale | `git stash drop stash@{N}` (probably orphaned) |
| No stashes | — | Silent exit (no output) |
| Not a git repo | — | Silent exit (no output) |

### How It Works

1. The hook receives JSON input from Claude Code containing the working directory (`cwd`)
2. It checks whether the directory is a git repository
3. It lists all stashes with `git stash list --format='%gd|%ct|%gs'`
4. Each stash is classified by age (2-hour threshold)
5. If stashes exist, it outputs a `{"decision": "block", "reason": "..."}` JSON response
6. Claude sees the stash list grouped by age with recommended actions

### Edge Cases

- **No stashes**: Exits silently with code 0
- **Not a git repo**: Exits silently with code 0
- **No `cwd` in input**: Exits silently with code 0
- **Stash subjects containing `|`**: Handled safely via `IFS='|' read -r ref ts subject` (subject captures remainder)
- **Mixed ages**: Both "Recent" and "Stale" sections shown in a single message

### Configuration

The hook is configured in `.claude-plugin/plugin.json` as a Stop event:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/git-stash-reminder.sh",
            "timeout": 10000
          }
        ]
      }
    ]
  }
}
```

### Testing

```bash
# Test: no stashes (should exit 0, no output)
echo '{"cwd": "/tmp/test-repo"}' | bash hooks/git-stash-reminder.sh

# Test: with stashes (should output block JSON)
cd /tmp && git init test-stash && cd test-stash
echo "test" > file.txt && git add . && git commit -m "init"
echo "change" > file.txt && git stash
echo '{"cwd": "/tmp/test-stash"}' | bash hooks/git-stash-reminder.sh
# Expected: {"decision":"block","reason":"Found 1 git stash(es)..."}

# Test: not a git repo (should exit 0, no output)
echo '{"cwd": "/tmp"}' | bash hooks/git-stash-reminder.sh

# Cleanup
rm -rf /tmp/test-stash
```

### Customization

Edit `git-stash-reminder.sh` to:
- Adjust the `STALE_THRESHOLD` variable (default: 7200 seconds / 2 hours)
- Change age display format
- Modify classification logic or recommendations
