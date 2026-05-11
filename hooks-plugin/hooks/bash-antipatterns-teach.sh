#!/usr/bin/env bash
# PostToolUse hook for Bash tool - teaches built-in-tool alternatives by augmenting
# the agent-visible tool output rather than blocking the command (Claude Code 2.1.121+).
#
# Companion to bash-antipatterns.sh: that hook continues to PreToolUse-block patterns
# that risk data loss or security (git reset --hard, curl | bash, fork bombs, etc.).
# This hook handles the "soft-teach" antipatterns where the command produces a
# useful result and the right response is "here is your result + use the dedicated
# tool next time."
#
# Why PostToolUse + updatedToolOutput instead of PreToolUse + exit 2?
#
# 2026-W20 friction analysis (.claude/rules/friction/2026-W20-frictions.md):
# - grep/rg vs Grep tool: 41 events / 33 sessions / 24% per-session rate / 21%
#   same-session repeat-block rate
# - find vs Glob: 29 events / 25 sessions / 17% per-session / 12% repeat-block
# - git && chains: 39/36/23% per-session / 8% repeat-block
#
# git && chains land at ~8% repeat-block because the agent has a concrete fallback
# (issue git commands as separate Bash calls). grep/rg sits at 21% because the
# agent sees only the block message - not the would-have-been-result - so the
# "use Grep" advice lands abstractly. By letting the command run and prepending
# the corrective hint to the result, the agent learns the right tool while still
# getting the data it asked for.

set -euo pipefail

# Phase 1 opt-in: this hook is wired into plugin.json by default but no-ops
# unless the user explicitly enables it. Matches event-logger.sh convention.
# See hooks-plugin/docs/teach-mode-experiment.md for rationale.
if [ "${CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH:-}" != "1" ]; then
    exit 0
fi

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Compose the hint based on which soft-teach pattern (if any) the command matched.
# A command can match at most one hint - we pick the most specific.
hint=""

# cat file (not in pipeline, not heredoc)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*cat\s+[^|><]' && \
   ! echo "$COMMAND" | grep -Eq '<<|cat\s*>' && \
   ! echo "$COMMAND" | grep -q '|'; then
    hint="Use the Read tool instead of 'cat' to read files. Read returns line-numbered content and respects token budgets."
fi

# head/tail file (not in pipeline)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*(head|tail)\s+(-[0-9n]+\s+)?[^|]' && \
   ! echo "$COMMAND" | grep -q '|'; then
    hint="Use the Read tool with offset/limit parameters instead of 'head' or 'tail'. Example: Read with offset=100, limit=50."
fi

# find -name without directory-discovery flags
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*find\s+' && \
   ! echo "$COMMAND" | grep -Eq 'find\s+.*(-maxdepth|-mindepth|-type\s|-print0)'; then
    hint="Use the Glob tool for filename matching. Example: Glob(pattern=\"**/*.ts\") instead of 'find . -name \"*.ts\"'. Keep 'find' only when you need -maxdepth/-type d/-print0."
fi

# grep/rg as standalone search (not piped, not -q)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*(grep|rg)\s+' && \
   ! echo "$COMMAND" | grep -q '|' && \
   ! echo "$COMMAND" | grep -Eq '(grep|rg)[^|]*\s(-[a-zA-Z]*q[a-zA-Z]*(\s|$)|--quiet(\s|$))'; then
    hint="Use the Grep tool for codebase searches. Example: Grep(pattern=\"foo\", path=\"src\", -n=true). Keep grep/rg for pipelines or boolean -q checks."
fi

# ls with a glob
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*ls\s+.*\*'; then
    hint="Use the Glob tool for pattern-based file listing - it returns paths sorted by modification time and handles large directories better."
fi

# No soft-teach pattern matched - leave tool output untouched.
if [ -z "$hint" ]; then
    exit 0
fi

# Build the augmented tool output: original response first, then the hint banner.
# We stringify tool_response defensively because its shape varies per Bash exit code
# and per harness version. jq's `tostring` handles strings, objects, and null.
ORIGINAL=$(echo "$INPUT" | jq -r '.tool_response | if type == "string" then . else tostring end // empty')

# Compose the augmented output. Trailing newline before the hint keeps the banner
# visually distinct from command output, especially when stdout ends without one.
AUGMENTED=$(printf '%s\n\n--- bash-antipatterns hint ---\n💡 %s\n' "$ORIGINAL" "$hint")

# Emit the PostToolUse JSON envelope. hookSpecificOutput.updatedToolOutput replaces
# what the model sees as the tool result (Claude Code 2.1.121+).
jq -n --arg out "$AUGMENTED" '{
    hookSpecificOutput: {
        hookEventName: "PostToolUse",
        updatedToolOutput: $out
    }
}'

exit 0
