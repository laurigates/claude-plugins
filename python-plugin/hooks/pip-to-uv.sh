#!/usr/bin/env bash
# pip-to-uv.sh — PreToolUse hook that rewrites pip commands to uv equivalents
#
# Transformations:
#   pip <cmd>                     -> uv pip <cmd>
#   pip3 <cmd>                    -> uv pip <cmd>
#   python -m pip <cmd>           -> uv pip <cmd>
#   python3 -m pip <cmd>          -> uv pip <cmd>
#   python3.x -m pip <cmd>        -> uv pip <cmd>

set -euo pipefail

INPUT=$(cat)

TOOL=$(echo "$INPUT" | jq -r '.tool_name')
if [ "$TOOL" != "Bash" ]; then
  exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [ -z "$COMMAND" ]; then
  exit 0
fi

NEW_COMMAND="$COMMAND"

# pip <cmd> -> uv pip <cmd>
if echo "$COMMAND" | grep -qE '^[[:space:]]*pip[[:space:]]+'; then
  NEW_COMMAND=$(echo "$COMMAND" | sed -E 's/^([[:space:]]*)pip([[:space:]]+)/\1uv pip\2/')

# pip3 <cmd> -> uv pip <cmd>
elif echo "$COMMAND" | grep -qE '^[[:space:]]*pip3[[:space:]]+'; then
  NEW_COMMAND=$(echo "$COMMAND" | sed -E 's/^([[:space:]]*)pip3([[:space:]]+)/\1uv pip\2/')

# python[3][.x] -m pip <cmd> -> uv pip <cmd>
elif echo "$COMMAND" | grep -qE '^[[:space:]]*python[0-9.]*[[:space:]]+-m[[:space:]]+pip[[:space:]]+'; then
  NEW_COMMAND=$(echo "$COMMAND" | sed -E 's/^([[:space:]]*)python[0-9.]*[[:space:]]+-m[[:space:]]+pip([[:space:]]+)/\1uv pip\2/')
fi

if [ "$NEW_COMMAND" != "$COMMAND" ]; then
  echo "pip-to-uv: rewrote \`$COMMAND\` → \`$NEW_COMMAND\`" >&2
  jq -n --arg cmd "$NEW_COMMAND" \
    '{"permissionDecision": "allow", "updatedInput": {"command": $cmd}}'
  exit 0
fi

exit 0
