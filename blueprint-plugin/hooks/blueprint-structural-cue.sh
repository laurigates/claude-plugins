#!/usr/bin/env bash
# blueprint-structural-cue.sh — PostToolUse cue for architecture-affecting edits.
#
# When an Edit/Write touches a plugin/marketplace manifest or adds a public-API
# (export) line, this appends a one-line, once-per-session cue to the tool result
# suggesting a blueprint check. It is a behavioral cue (ADR-0017), not a gate:
# it never blocks an edit and degrades to silence on any error.
#
# Mechanism: PostToolUse hookSpecificOutput.updatedToolOutput replaces the tool
# result, so the original tool_response is preserved and the cue is appended.
# Dedup is per session (one cue per session) to bound transcript-replay cost.
#
# -e is intentionally omitted: a best-effort cue must never break a tool call.
set -uo pipefail

# Bypass (shared blueprint-plugin convention).
if [ "${BLUEPRINT_SKIP_HOOKS:-}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || echo "")
file_path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
new_string=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null || echo "")
content=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null || echo "")
original=$(printf '%s' "$INPUT" | jq -r '.tool_response | if type == "string" then . else tostring end // empty' 2>/dev/null || echo "")
session_id=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'a-zA-Z0-9_-')

# Only Edit/Write carry structural edits.
case "$tool_name" in
    Edit|Write) ;;
    *) exit 0 ;;
esac

[ -z "$file_path" ] && exit 0

# --- Detection: narrow, start small (ADR-0017 roadmap widens later) ---
base_name="${file_path##*/}"
payload="${new_string}
${content}"
is_structural=0

# Signal 1: plugin/marketplace manifest.
case "$file_path" in
    *.claude-plugin/marketplace.json) is_structural=1 ;;
esac
if [ "$base_name" = "plugin.json" ]; then
    is_structural=1
fi

# Signal 2: a public-API / export line in the edit payload.
if [ "$is_structural" -eq 0 ] && \
    printf '%s' "$payload" | grep -Eq '(export |export default|module\.exports|^[+[:space:]]*pub |def __all__)'; then
    is_structural=1
fi

# Deliberately exclude docs/adrs|prds — validate-*-frontmatter.sh +
# auto-sync-id-registry.sh already cover those; a cue there is redundant.
case "$file_path" in
    docs/adrs/*|docs/prds/*|*/docs/adrs/*|*/docs/prds/*) is_structural=0 ;;
esac

[ "$is_structural" -eq 0 ] && exit 0

# --- Dedup: one cue per session ---
# BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR is the test seam.
cache_dir="${BLUEPRINT_STRUCTURAL_CUE_CACHE_DIR:-${HOME}/.cache/blueprint-structural-cue}"
if [ -n "$session_id" ]; then
    marker="${cache_dir}/${session_id}"
    [ -f "$marker" ] && exit 0
    mkdir -p "$cache_dir" 2>/dev/null || true
    touch "$marker" 2>/dev/null || true
fi

cue="Structural change detected (manifest / public API). Consider /blueprint:derive-plans or /blueprint:adr-validate to keep PRDs/ADRs current."

augmented="${original}

[blueprint] ${cue}"

jq -n --arg out "$augmented" '{
    hookSpecificOutput: {
        hookEventName: "PostToolUse",
        updatedToolOutput: $out
    }
}'

exit 0
