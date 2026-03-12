#!/usr/bin/env bash
# PreToolUse hook - validates PRD frontmatter before Write/Edit
# Blocks on missing required fields (id, title, status)
# See docs/hook-design-decisions.md for rationale

set -euo pipefail

# Check for bypass
if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

# Read the JSON input from stdin
INPUT=$(cat)

# Extract content from tool input
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')

# If no content (e.g., reading), allow
if [ -z "$CONTENT" ]; then
    exit 0
fi

# Function to output blocking error (exit code 2)
block() {
    echo "$1" >&2
    exit 2
}

# Function to output warning (non-blocking)
warn() {
    echo "WARNING: $1" >&2
}

# Function to output info
info() {
    echo "INFO: $1" >&2
}

# Extract frontmatter (between first two ---)
extract_frontmatter() {
    echo "$1" | awk '/^---$/{if(++n==2)exit}n' | tail -n +2
}

# Extract field value from frontmatter
get_field() {
    local frontmatter="$1"
    local field="$2"
    echo "$frontmatter" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || true
}

# Check for required frontmatter field
check_required_field() {
    local frontmatter="$1"
    local field="$2"
    local value
    value=$(get_field "$frontmatter" "$field")
    if [ -z "$value" ]; then
        block "ERROR: Missing required frontmatter field: ${field}"
    fi
}

# Validate PRD status value
validate_status() {
    local prd_status="$1"
    case "$prd_status" in
        Draft|Active|Completed|Deprecated|Proposed)
            return 0
            ;;
        *)
            block "ERROR: Invalid PRD status: '${prd_status}'. Valid values: Draft, Active, Completed, Deprecated, Proposed"
            ;;
    esac
}

# Main validation
FRONTMATTER=$(extract_frontmatter "$CONTENT")

if [ -z "$FRONTMATTER" ]; then
    block "ERROR: No YAML frontmatter found. PRDs must have frontmatter between --- delimiters"
fi

# Required: id field with PRD-NNN format
check_required_field "$FRONTMATTER" "id"

PRD_ID=$(get_field "$FRONTMATTER" "id")
if [ -n "$PRD_ID" ] && ! [[ "$PRD_ID" =~ ^PRD-[0-9]{3,}$ ]]; then
    block "ERROR: Invalid PRD id format: '${PRD_ID}'. Expected format: PRD-NNN (e.g., PRD-001)"
fi

# Required: status and dates
check_required_field "$FRONTMATTER" "status"
check_required_field "$FRONTMATTER" "created"
check_required_field "$FRONTMATTER" "modified"

# Validate status value
PRD_STATUS=$(get_field "$FRONTMATTER" "status")
validate_status "$PRD_STATUS"

# Optional but recommended fields (warn only)
TITLE=$(get_field "$FRONTMATTER" "title")
if [ -z "$TITLE" ]; then
    warn "Missing 'title' field in frontmatter. Recommended for manifest registry"
fi

# All checks passed
info "PRD frontmatter validation passed"
exit 0
