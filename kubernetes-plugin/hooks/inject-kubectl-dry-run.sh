#!/usr/bin/env bash
# PreToolUse hook for Bash tool - injects --dry-run=client into kubectl destructive commands
#
# Intercepts kubectl apply, delete, and patch commands that lack a --dry-run flag and
# rewrites them to add --dry-run=client. This creates a natural checkpoint: the model
# sees the dry-run output and must explicitly re-run without the flag to apply for real.
#
# Bypass: add --dry-run=none to explicitly skip dry-run mode.
# The validate-kubectl-context.sh hook runs in parallel and enforces --context presence.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then exit 0; fi

# Only intercept kubectl apply, delete, or patch
if ! echo "$COMMAND" | grep -qE '(^|\s)kubectl\s+(apply|delete|patch)(\s|$)'; then
    exit 0
fi

# Already has any --dry-run flag (including --dry-run=none for explicit bypass)
if echo "$COMMAND" | grep -qE '\-\-dry-run'; then
    exit 0
fi

# Inject --dry-run=client and output modified command via updatedInput
UPDATED="${COMMAND} --dry-run=client"
jq -n --arg cmd "$UPDATED" '{
    "permissionDecision": "allow",
    "updatedInput": {
        "command": $cmd
    }
}'
exit 0
