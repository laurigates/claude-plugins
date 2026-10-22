# Hook Event Examples

Worked example scripts for the newer hook events. Moved out of [`.claude/rules/hooks-reference.md`](../.claude/rules/hooks-reference.md) to keep that path-scoped rule under the 50,000-char ceiling; the input fields each script reads are documented under "Input Schemas" there. Every script reads the event JSON from stdin and exits 0. The `TaskCompleted` script blocks by printing a JSON `decision`, not through its exit code.

## WorktreeCreate — Set Up Worktree Environment

```bash
#!/bin/bash
# .claude/hooks/worktree-create.sh
INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path')
BRANCH=$(echo "$INPUT" | jq -r '.worktree_branch')

# Install dependencies in the new worktree
if [ -f "$WORKTREE_PATH/package.json" ]; then
  (cd "$WORKTREE_PATH" && bun install --frozen-lockfile) 2>/dev/null
fi

echo "Worktree ready: $BRANCH at $WORKTREE_PATH" >&2
exit 0
```

## WorktreeRemove — Clean Up After Worktree

```bash
#!/bin/bash
# .claude/hooks/worktree-remove.sh
INPUT=$(cat)
WORKTREE_PATH=$(echo "$INPUT" | jq -r '.worktree_path')
HAD_CHANGES=$(echo "$INPUT" | jq -r '.had_changes')

# Alert if worktree had uncommitted changes
if [ "$HAD_CHANGES" = "true" ]; then
  echo "WARNING: Worktree $WORKTREE_PATH removed with uncommitted changes" >&2
fi

exit 0
```

## TeammateIdle — Assign Work to Idle Teammates

```bash
#!/bin/bash
# .claude/hooks/teammate-idle.sh
INPUT=$(cat)
TEAMMATE=$(echo "$INPUT" | jq -r '.teammate_name')
TEAM=$(echo "$INPUT" | jq -r '.team_name')

# Log idle event for team lead awareness
echo "$(date -Iseconds): Teammate $TEAMMATE is idle in team $TEAM" >> ~/.claude/team-activity.log

exit 0
```

## TaskCompleted — Validate Before Accepting

```bash
#!/bin/bash
# .claude/hooks/task-completed.sh
INPUT=$(cat)
TASK_TITLE=$(echo "$INPUT" | jq -r '.task_title')

# Run tests if implementation task
if echo "$TASK_TITLE" | grep -qi 'implement\|add\|fix\|refactor'; then
  if ! npm test --bail 2>/dev/null; then
    echo '{"decision": "block", "reason": "Tests must pass before task is accepted. Fix failing tests first."}'
    exit 0
  fi
fi

exit 0
```

## ConfigChange — Audit Configuration Changes

```bash
#!/bin/bash
# .claude/hooks/config-change.sh
INPUT=$(cat)
CONFIG_KEY=$(echo "$INPUT" | jq -r '.config_key')
NEW_VALUE=$(echo "$INPUT" | jq -c '.new_value')

# Audit log all config changes
echo "$(date -Iseconds) | CONFIG | $CONFIG_KEY = $NEW_VALUE" >> ~/.claude/config-audit.log

exit 0
```
