#!/usr/bin/env bash
# PermissionRequest hook — auto-approve safe operations, auto-deny dangerous ones
#
# Toggle: set CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO=1 to skip this hook
#
# Matches: Bash (and optionally all tools)
# Approves: read-only git, test runners, linters
# Denies: destructive filesystem ops, force push to protected branches
# Passes through: everything else (user decides)
#
# Customize the APPROVE and DENY patterns below for your project.

set -euo pipefail

# Toggle off
[ "${CLAUDE_HOOKS_DISABLE_PERMISSION_AUTO:-}" = "1" ] && exit 0

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only handle Bash commands
if [ "$TOOL_NAME" != "Bash" ]; then
  exit 0
fi

[ -z "$COMMAND" ] && exit 0

# --- AUTO-APPROVE: Safe, read-only operations ---

# Read-only git operations
if echo "$COMMAND" | grep -Eq '^\s*git\s+(status|log|diff|branch|remote|show|blame|shortlog|describe|ls-files|rev-parse|rev-list)'; then
  echo '{"decision": "approve", "reason": "Read-only git operation"}'
  exit 0
fi

# Test runners (read-only, fail-fast)
if echo "$COMMAND" | grep -Eq '^\s*(npm\s+test|npx\s+(vitest|jest)|bun\s+test|pytest|cargo\s+test|go\s+test|make\s+test)'; then
  echo '{"decision": "approve", "reason": "Test execution"}'
  exit 0
fi

# Linters and formatters (read-only check mode)
if echo "$COMMAND" | grep -Eq '^\s*(npx\s+(biome|eslint|prettier)|bun\s+run\s+(lint|check|format)|ruff\s+check|mypy|tsc\s+--noEmit)'; then
  echo '{"decision": "approve", "reason": "Linter/formatter check"}'
  exit 0
fi

# gh CLI read operations
if echo "$COMMAND" | grep -Eq '^\s*gh\s+(pr\s+(view|checks|list|diff)|issue\s+(view|list)|run\s+(view|list))'; then
  echo '{"decision": "approve", "reason": "GitHub CLI read operation"}'
  exit 0
fi

# --- AUTO-DENY: Dangerous operations ---

# Destructive filesystem operations on root or home
# shellcheck disable=SC2016  # $HOME is a grep pattern, not shell expansion
if echo "$COMMAND" | grep -Eq 'rm\s+(-rf|-fr)\s+(/|~/|\$HOME)'; then
  echo '{"decision": "deny", "reason": "Destructive operation on root or home directory"}'
  exit 0
fi

# Force push to protected branches
if echo "$COMMAND" | grep -Eq 'git\s+push\s+.*--force.*\s(main|master)\b'; then
  echo '{"decision": "deny", "reason": "Force push to protected branch"}'
  exit 0
fi

# --- PASS THROUGH: Everything else requires user decision ---
exit 0
