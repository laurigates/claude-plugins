#!/usr/bin/env bash
# PreCompact hook for blueprint-plugin
#
# Detects active document derivation workflows (derive-adr, derive-prd, derive-plans,
# derive-tests, derive-rules) and injects a systemMessage to guide context compaction.
#
# When long derivation sessions hit the context limit, compaction can lose critical
# state: which PRP/ADR is being derived from, which sections are complete, what remains.
# This hook preserves that state by instructing the compaction algorithm on what to keep.
#
# Exits silently (0) when no derivation is in progress — non-disruptive.

set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# Detect active derivation: look for Skill/SlashCommand tool uses matching derive-* skills
ACTIVE_DERIVATION=$(jq -r '
    select(.type == "tool_use")
    | select(.name == "Skill" or .name == "SlashCommand")
    | .input.skill // .input.name // ""
    | select(test("derive-|blueprint:derive"; "i"))
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

# Also capture the derivation source (PRP/ADR name passed as args)
DERIVATION_SOURCE=$(jq -r '
    select(.type == "tool_use")
    | select(.name == "Skill" or .name == "SlashCommand")
    | select((.input.skill // .input.name // "") | test("derive-"; "i"))
    | .input.args // .input.arguments // ""
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

# Check for output documents being actively written (derivation targets)
DERIVATION_OUTPUT=$(jq -r '
    select(.type == "tool_use")
    | select(.name == "Write" or .name == "Edit")
    | .input.file_path // ""
    | select(test("docs/(adrs|prds|plans|tests)|rules/"; "i"))
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -3 || true)

# Check for recent TodoWrite state (section completion tracking)
RECENT_TODOS=$(jq -r '
    select(.type == "tool_use")
    | select(.name == "TodoWrite")
' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 || true)

# Only inject context if derivation activity is detected
if [ -z "$ACTIVE_DERIVATION" ] && [ -z "$DERIVATION_OUTPUT" ]; then
    exit 0
fi

# Build preservation message
parts=()

if [ -n "$ACTIVE_DERIVATION" ]; then
    derivation_info="$ACTIVE_DERIVATION"
    [ -n "$DERIVATION_SOURCE" ] && derivation_info="${derivation_info} (from: ${DERIVATION_SOURCE})"
    parts+=("active derivation workflow: ${derivation_info}")
fi

if [ -n "$DERIVATION_OUTPUT" ]; then
    file_list=$(echo "$DERIVATION_OUTPUT" | tr '\n' ', ' | sed 's/,$//')
    parts+=("output documents being written: ${file_list}")
fi

if [ -n "$RECENT_TODOS" ]; then
    parts+=("current task list state and which derivation sections are complete vs pending")
fi

parts+=("PRP/ADR/PRD source document name, path, and its frontmatter fields")
parts+=("section-by-section derivation progress (what has been written vs what remains)")
parts+=("any validation errors or quality checks already performed")

instructions="Blueprint derivation workflow is in progress. When compacting, prioritize preserving:"
for part in "${parts[@]}"; do
    instructions="${instructions}\n- ${part}"
done
instructions="${instructions}\n\nDo not summarize away the derivation source, target document path, or the list of remaining sections. The model must be able to resume the derivation exactly where it left off."

escaped=$(echo -e "$instructions" | jq -Rs .)
echo "{\"systemMessage\":${escaped}}"
exit 0
