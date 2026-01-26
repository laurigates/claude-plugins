#!/bin/bash
#
# PreToolUse: Enforce orchestrator pattern
#
# Orchestrators investigate and delegate - they don't implement.
# Subagents (spawned via Task) get full tool access.
#
# Configuration:
#   ORCHESTRATOR_BYPASS=1        - Disable this hook entirely
#   CLAUDE_IS_SUBAGENT=1         - Set by parent to grant full access
#
# Exit codes:
#   0 - Allow (no output or JSON with allow decision)
#   0 - Deny (JSON output with deny decision)
#   2 - Error (stderr message blocks operation)
#

set -euo pipefail

# Bypass check
[[ "${ORCHESTRATOR_BYPASS:-0}" == "1" ]] && exit 0

# Subagent detection - environment variable set by parent agent
# When Task spawns subagents, set CLAUDE_IS_SUBAGENT=1 in the environment
[[ "${CLAUDE_IS_SUBAGENT:-0}" == "1" ]] && exit 0

# Read hook input
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# Empty tool name - allow
[[ -z "$TOOL_NAME" ]] && exit 0

# --- Helper Functions ---

deny() {
    local reason="$1"
    cat <<EOF
{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"$reason"}}
EOF
    exit 0
}

# --- Tool Categories ---

# Always allowed: delegation
[[ "$TOOL_NAME" == "Task" ]] && exit 0

# Always allowed: investigation tools
case "$TOOL_NAME" in
    Read|Grep|Glob|WebFetch|WebSearch)
        exit 0
        ;;
esac

# Always allowed: planning tools
case "$TOOL_NAME" in
    TodoWrite)
        exit 0
        ;;
esac

# Blocked: implementation tools
case "$TOOL_NAME" in
    Edit|Write|NotebookEdit)
        deny "Tool '$TOOL_NAME' blocked for orchestrator. Use Task() to delegate implementation to a subagent."
        ;;
esac

# --- Bash Command Validation ---

if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [[ -z "$COMMAND" ]] && exit 0

    # Extract first word (command name)
    FIRST_WORD="${COMMAND%% *}"

    # Git commands: allow read, block write
    if [[ "$FIRST_WORD" == "git" ]]; then
        # Extract git subcommand
        GIT_CMD=$(echo "$COMMAND" | awk '{print $2}')

        case "$GIT_CMD" in
            # Read operations - allow
            status|log|diff|branch|show|remote|fetch|ls-files|rev-parse|describe|config)
                exit 0
                ;;
            # Navigation - allow
            checkout|switch|stash)
                exit 0
                ;;
            # Write operations - block
            add|commit|push|merge|rebase|reset|cherry-pick|revert|tag)
                deny "Git '$GIT_CMD' blocked for orchestrator. Use Task() to delegate git operations."
                ;;
            # Default - allow (for unknown git commands)
            *)
                exit 0
                ;;
        esac
    fi

    # Build/test commands - allow for investigation
    case "$FIRST_WORD" in
        npm|yarn|pnpm|bun|cargo|go|make|gradle|mvn|pytest|jest|vitest)
            exit 0
            ;;
    esac

    # System info commands - allow
    case "$FIRST_WORD" in
        ls|pwd|which|whoami|env|printenv|uname|date|wc|sort|uniq|head|tail|less|more)
            exit 0
            ;;
    esac

    # File content commands that don't modify - allow
    case "$FIRST_WORD" in
        cat|grep|rg|find|fd|jq|yq|tree|file|stat|du|df)
            exit 0
            ;;
    esac

    # GitHub CLI - allow read operations
    if [[ "$FIRST_WORD" == "gh" ]]; then
        GH_CMD=$(echo "$COMMAND" | awk '{print $2}')
        case "$GH_CMD" in
            pr|issue|run|repo|api)
                # Check for read vs write subcommands
                GH_SUBCMD=$(echo "$COMMAND" | awk '{print $3}')
                case "$GH_SUBCMD" in
                    view|list|checks|status|diff)
                        exit 0
                        ;;
                    create|edit|merge|close|reopen|comment)
                        deny "GitHub CLI '$GH_CMD $GH_SUBCMD' blocked for orchestrator. Use Task() to delegate."
                        ;;
                    *)
                        exit 0  # Allow unknown subcommands
                        ;;
                esac
                ;;
            *)
                exit 0
                ;;
        esac
    fi

    # Block file modification patterns
    if [[ "$COMMAND" =~ (^|[[:space:]])(sed[[:space:]]+-i|awk.*\>|tee[[:space:]]|>[[:space:]]|>>) ]]; then
        deny "File modification via Bash blocked for orchestrator. Use Task() to delegate."
    fi

    # Default: allow other bash commands
    exit 0
fi

# Default: allow unknown tools
exit 0
