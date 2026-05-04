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

# Returns 0 if the path should be excluded from completeness checks.
# Documentation files (*.md, *.mdx, *.rst, *.txt) frequently quote literal
# TODO/FIXME tokens, conflict markers, or console.log examples in prose
# (this very plugin's docs do). Vendor / generated paths are excluded for
# the same reason — they are not the author's working code.
is_excluded() {
    case "$1" in
        *.md|*.mdx|*.rst|*.txt) return 0 ;;
        *.min.js|*.min.css|*.min.map) return 0 ;;
        */node_modules/*|*/.git/*|*/vendor/*|*/dist/*|*/build/*) return 0 ;;
        */.obsidian/plugins/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Build the list of changed files we actually care about (staged + unstaged,
# de-duplicated, excluded paths filtered out, must currently exist on disk).
RELEVANT_FILES=()
while IFS= read -r file; do
    [ -z "$file" ] && continue
    is_excluded "$file" && continue
    [ -f "$CWD/$file" ] || continue
    RELEVANT_FILES+=("$file")
done < <(
    {
        git -C "$CWD" diff --name-only 2>/dev/null || true
        git -C "$CWD" diff --name-only --cached 2>/dev/null || true
    } | sort -u
)

# Nothing relevant changed → nothing to check.
if [ "${#RELEVANT_FILES[@]}" -eq 0 ]; then
    exit 0
fi

# Combined diff (staged + unstaged) restricted to the relevant files.
# Re-used by Check 1 and Check 3.
RELEVANT_DIFF=$(
    {
        git -C "$CWD" diff -- "${RELEVANT_FILES[@]}" 2>/dev/null || true
        git -C "$CWD" diff --cached -- "${RELEVANT_FILES[@]}" 2>/dev/null || true
    }
)

# Check 1: TODO/FIXME/HACK/XXX markers added in this diff.
DIFF_TODOS=$(printf '%s\n' "$RELEVANT_DIFF" | grep -cE '^\+.*(TODO|FIXME|HACK|XXX)' || true)

if [ "${DIFF_TODOS:-0}" -gt 0 ]; then
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Found ${DIFF_TODOS} TODO/FIXME/HACK/XXX marker(s) in uncommitted changes. Address or remove them before finishing." \
        '{"decision": "block", "reason": $reason}'
    exit 0
fi

# Check 2: conflict markers in relevant files.
#
# Real merge markers come paired (<<<<<<< … ======= … >>>>>>>), so any
# conflict — fully unresolved or partially resolved — leaves at least
# one of <<<<<<< or >>>>>>> behind. Standalone `=======` lines have too
# many legitimate non-conflict uses (decorative dividers in fenced code
# blocks, console-output examples, ASCII art) and were the dominant
# false-positive signal, so they are intentionally excluded.
CONFLICT_FILES=()
for file in "${RELEVANT_FILES[@]}"; do
    if grep -lE '^(<{7}|>{7})' "$CWD/$file" >/dev/null 2>&1; then
        CONFLICT_FILES+=("$file")
    fi
done

if [ "${#CONFLICT_FILES[@]}" -gt 0 ]; then
    FILE_LIST=$(printf '%s\n' "${CONFLICT_FILES[@]}" | head -5 | tr '\n' ', ' | sed 's/,$//')
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Unresolved merge conflict markers found in: ${FILE_LIST}" \
        '{"decision": "block", "reason": $reason}'
    exit 0
fi

# Check 3: debugging artifacts added in this diff.
DEBUG_COUNT=$(printf '%s\n' "$RELEVANT_DIFF" | grep -cE '^\+.*(console\.log|debugger;|print\(.*DEBUG|breakpoint\(\)|pdb\.set_trace)' || true)

if [ "${DEBUG_COUNT:-0}" -gt 0 ]; then
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Found ${DEBUG_COUNT} debugging artifact(s) (console.log, debugger, breakpoint, etc.) in uncommitted changes. Clean up before finishing." \
        '{"decision": "block", "reason": $reason}'
    exit 0
fi

# All checks passed
exit 0
