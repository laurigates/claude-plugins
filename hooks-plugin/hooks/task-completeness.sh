#!/usr/bin/env bash
# Stop hook - checks for obvious signs of incomplete work before allowing stop
# Replaces the prompt-based hook to avoid leaking the full prompt text in error
# output (see #1009). Uses deterministic heuristics instead of LLM judgment.
set -euo pipefail

# Allow disabling via environment variable
if [ "${CLAUDE_HOOKS_DISABLE_TASK_COMPLETENESS:-0}" = "1" ]; then
    exit 0
fi

# Read JSON input from stdin and extract fields
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
# Guard: stop_hook_active - prevent infinite loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Guard: no working directory provided
if [ -z "$CWD" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Check 1: Look for TODO/FIXME markers in staged or unstaged changes
# These indicate the author left intentional "finish this" markers
DIFF_TODOS=$(
    {
        git -C "$CWD" diff 2>/dev/null || true
        git -C "$CWD" diff --cached 2>/dev/null || true
    } | grep -c '^\+.*\(TODO\|FIXME\|HACK\|XXX\)' 2>/dev/null
) || DIFF_TODOS=0

if [ "$DIFF_TODOS" -gt 0 ]; then
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Found ${DIFF_TODOS} TODO/FIXME/HACK/XXX marker(s) in uncommitted changes. Address or remove them before finishing." \
        '{"decision": "block", "reason": $reason}'
    exit 0
fi

# Check 2: Look for conflict markers in changed files
#
# Real merge markers come paired (<<<<<<< … ======= … >>>>>>>), so any
# conflict — fully unresolved or partially resolved — leaves at least
# one of <<<<<<< or >>>>>>> behind. Standalone `=======` lines have too
# many legitimate non-conflict uses (decorative dividers in fenced code
# blocks, console-output examples, ASCII art) and were the dominant
# false-positive signal, so they are intentionally excluded.
CONFLICT_FILES=$(
    {
        git -C "$CWD" diff --name-only 2>/dev/null || true
        git -C "$CWD" diff --name-only --cached 2>/dev/null || true
    } | sort -u | while IFS= read -r file; do
        [ -z "$file" ] && continue
        [ -f "$CWD/$file" ] || continue
        if grep -lE '^(<{7}|>{7})' "$CWD/$file" >/dev/null 2>&1; then
            echo "$file"
        fi
    done
)

if [ -n "$CONFLICT_FILES" ]; then
    FILE_LIST=$(echo "$CONFLICT_FILES" | head -5 | tr '\n' ', ' | sed 's/,$//')
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Unresolved merge conflict markers found in: ${FILE_LIST}" \
        '{"decision": "block", "reason": $reason}'
    exit 0
fi

# Check 3: Look for debugging artifacts in uncommitted changes
DEBUG_COUNT=$(
    {
        git -C "$CWD" diff 2>/dev/null || true
        git -C "$CWD" diff --cached 2>/dev/null || true
    } | grep -cE '^\+.*(console\.log|debugger;|print\(.*DEBUG|breakpoint\(\)|pdb\.set_trace)' 2>/dev/null
) || DEBUG_COUNT=0

if [ "$DEBUG_COUNT" -gt 0 ]; then
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Found ${DEBUG_COUNT} debugging artifact(s) (console.log, debugger, breakpoint, etc.) in uncommitted changes. Clean up before finishing." \
        '{"decision": "block", "reason": $reason}'
    exit 0
fi

# All checks passed
exit 0
