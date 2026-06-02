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
# 2026-W20 friction analysis:
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
# A command can match at most one hint - we pick the most specific. hint_key is a
# stable identifier for the matched pattern, used below for session-scoped dedup.
hint=""
hint_key=""

# cat file (not in pipeline, not heredoc)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*cat\s+[^|><]' && \
   ! echo "$COMMAND" | grep -Eq '<<|cat\s*>' && \
   ! echo "$COMMAND" | grep -q '|'; then
    hint="Use the Read tool instead of 'cat' to read files. Read returns line-numbered content and respects token budgets."
    hint_key="read-cat"
fi

# head/tail file (not in pipeline)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*(head|tail)\s+(-[0-9n]+\s+)?[^|]' && \
   ! echo "$COMMAND" | grep -q '|'; then
    hint="Use the Read tool with offset/limit parameters instead of 'head' or 'tail'. Example: Read with offset=100, limit=50."
    hint_key="read-headtail"
fi

# find -name without directory-discovery flags
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*find\s+' && \
   ! echo "$COMMAND" | grep -Eq 'find\s+.*(-maxdepth|-mindepth|-type\s|-print0)'; then
    hint="Use the Glob tool for filename matching. Example: Glob(pattern=\"**/*.ts\") instead of 'find . -name \"*.ts\"'. Keep 'find' only when you need -maxdepth/-type d/-print0."
    hint_key="glob-find"
fi

# grep/rg as standalone search (not piped, not -q)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*(grep|rg)\s+' && \
   ! echo "$COMMAND" | grep -q '|' && \
   ! echo "$COMMAND" | grep -Eq '(grep|rg)[^|]*\s(-[a-zA-Z]*q[a-zA-Z]*(\s|$)|--quiet(\s|$))'; then
    hint="Use the Grep tool for codebase searches. Example: Grep(pattern=\"foo\", path=\"src\", -n=true). Keep grep/rg for pipelines or boolean -q checks."
    hint_key="grep"
fi

# ls with a glob
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*ls\s+.*\*'; then
    hint="Use the Glob tool for pattern-based file listing - it returns paths sorted by modification time and handles large directories better."
    hint_key="glob-ls"
fi

# No soft-teach pattern matched - leave tool output untouched.
if [ -z "$hint" ]; then
    exit 0
fi

# Session-scoped dedup: emit each distinct hint at most once per session.
#
# updatedToolOutput is replayed on every subsequent turn (it persists in the
# transcript like any tool result), so an un-capped hint on a high-frequency
# command (grep, cat) accumulates one replayed copy per matching call for the
# rest of the session. The lesson is identical each time, so the marginal copies
# are pure transcript bloat. Teaching once per pattern caps the replay cost at
# five hint banners for an entire session regardless of call count, while still
# delivering the correction the first time the agent reaches for the idiom.
#
# State lives in a per-session file (sanitised session_id, same convention as
# git-stash-session-init.sh) and is removed by git-session-cleanup.sh at
# SessionEnd. When session_id is absent we skip dedup and fall through to the
# old always-emit behaviour rather than guess at a key.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' | tr -cd 'a-zA-Z0-9_-')
if [ -n "$SESSION_ID" ]; then
    SEEN_DIR="${TMPDIR:-/tmp}/claude-bash-teach-seen"
    SEEN_FILE="${SEEN_DIR}/${SESSION_ID}"
    if [ -f "$SEEN_FILE" ] && grep -qxF "$hint_key" "$SEEN_FILE" 2>/dev/null; then
        # Already taught this lesson this session - leave tool output untouched.
        exit 0
    fi
    mkdir -p "$SEEN_DIR" 2>/dev/null || true
    echo "$hint_key" >> "$SEEN_FILE" 2>/dev/null || true
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
