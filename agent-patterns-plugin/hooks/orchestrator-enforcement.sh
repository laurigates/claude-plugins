#!/bin/bash
#
# PreToolUse: Enforce orchestrator pattern and git safety
#
# Orchestrators investigate and delegate - they don't implement.
# Subagents (spawned via Task) get implementation access but NOT git write access.
# Only the git-ops agent (with CLAUDE_GIT_AGENT=1) can perform git write operations.
#
# This prevents parallel agent conflicts where multiple agents doing git operations
# (branching, stashing, committing) cause files to disappear/reappear for each other.
#
# Configuration:
#   ORCHESTRATOR_MODE=1          - Enable orchestrator enforcement (disabled by default)
#   CLAUDE_IS_SUBAGENT=1         - Set by parent to grant implementation access (not git)
#   CLAUDE_GIT_AGENT=1           - Set for git-ops agent to grant git write access
#
# Exit codes:
#   0 - Allow (no output or JSON with allow decision)
#   0 - Deny (JSON output with deny decision)
#   2 - Error (stderr message blocks operation)
#

set -euo pipefail

# Opt-in check: if orchestrator mode is not enabled, allow everything
[[ "${ORCHESTRATOR_MODE:-0}" != "1" ]] && exit 0

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

# --- Context Detection ---
IS_SUBAGENT="${CLAUDE_IS_SUBAGENT:-0}"
IS_GIT_AGENT="${CLAUDE_GIT_AGENT:-0}"

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

# Implementation tools: blocked for orchestrator, allowed for subagents
case "$TOOL_NAME" in
    Edit|Write|NotebookEdit)
        if [[ "$IS_SUBAGENT" != "1" ]]; then
            deny "Tool '$TOOL_NAME' blocked for orchestrator. Use Task() to delegate implementation to a subagent."
        fi
        # Subagents can use Edit/Write/NotebookEdit
        exit 0
        ;;
esac

# --- Bash Command Validation ---

if [[ "$TOOL_NAME" == "Bash" ]]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [[ -z "$COMMAND" ]] && exit 0

    # Extract first word (command name)
    FIRST_WORD="${COMMAND%% *}"

    # Git commands: allow read, block write (for ALL contexts except git-agent)
    # This prevents parallel agent conflicts where multiple agents doing git operations
    # cause shared state corruption (files disappearing, branch confusion, etc.)
    if [[ "$FIRST_WORD" == "git" ]]; then
        # Extract git subcommand
        GIT_CMD=$(echo "$COMMAND" | awk '{print $2}')

        case "$GIT_CMD" in
            # Read operations - always allow
            status|log|diff|branch|show|remote|fetch|ls-files|rev-parse|describe|config)
                exit 0
                ;;
            # Navigation operations - allow for git-agent only (can cause parallel conflicts)
            checkout|switch)
                if [[ "$IS_GIT_AGENT" == "1" ]]; then
                    exit 0
                fi
                if [[ "$IS_SUBAGENT" == "1" ]]; then
                    deny "Git '$GIT_CMD' blocked for parallel safety. Branch switching during parallel execution causes file conflicts. Request orchestrator to coordinate git operations after parallel work completes."
                fi
                deny "Git '$GIT_CMD' blocked for orchestrator. Use Task() to delegate to git-ops agent."
                ;;
            # Stash operations - allow for git-agent only (can cause parallel conflicts)
            stash)
                if [[ "$IS_GIT_AGENT" == "1" ]]; then
                    exit 0
                fi
                if [[ "$IS_SUBAGENT" == "1" ]]; then
                    deny "Git stash blocked for parallel safety. Stashing during parallel execution causes files to disappear for other agents. Request orchestrator to coordinate git operations after parallel work completes."
                fi
                deny "Git stash blocked for orchestrator. Use Task() to delegate to git-ops agent."
                ;;
            # Write operations - only git-agent
            add|commit|push|merge|rebase|reset|cherry-pick|revert|tag)
                if [[ "$IS_GIT_AGENT" == "1" ]]; then
                    exit 0
                fi
                if [[ "$IS_SUBAGENT" == "1" ]]; then
                    deny "Git '$GIT_CMD' blocked for parallel safety. Git writes during parallel execution cause conflicts. Edit files in place and let the orchestrator coordinate commits after parallel work completes."
                fi
                deny "Git '$GIT_CMD' blocked for orchestrator. Use Task() to delegate to git-ops agent."
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

    # GitHub CLI - read operations always allowed, write operations allowed for subagents
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
                        # Subagents can perform GitHub write operations as part of their tasks
                        if [[ "$IS_SUBAGENT" == "1" ]]; then
                            exit 0
                        fi
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

    # Block file modification patterns for orchestrator only - subagents can implement
    if [[ "$COMMAND" =~ (^|[[:space:]])(sed[[:space:]]+-i|awk.*\>|tee[[:space:]]|>[[:space:]]|>>) ]]; then
        if [[ "$IS_SUBAGENT" != "1" ]]; then
            deny "File modification via Bash blocked for orchestrator. Use Task() to delegate."
        fi
    fi

    # Default: allow other bash commands
    exit 0
fi

# Default: allow unknown tools
exit 0
