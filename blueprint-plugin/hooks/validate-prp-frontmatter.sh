#!/bin/bash
# PreToolUse hook - validates PRP frontmatter before Write/Edit
# Blocks on missing required fields or sections
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
block_error() {
    echo "ERROR: $1" >&2
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
        block_error "Missing required frontmatter field: ${field}"
    fi
}

# Check for required markdown section
check_required_section() {
    local content="$1"
    local section="$2"
    if ! echo "$content" | grep -q "^## ${section}"; then
        block_error "Missing required section: ## ${section}"
    fi
}

# Validate status value
validate_status() {
    local prp_status="$1"
    case "$prp_status" in
        draft|ready|in-progress|completed)
            return 0
            ;;
        *)
            block_error "Invalid PRP status: '${prp_status}'. Valid values: draft, ready, in-progress, completed"
            ;;
    esac
}

# Validate confidence score format
validate_confidence() {
    local confidence="$1"
    # Extract numeric part (e.g., "7/10" -> "7" or "7" -> "7")
    local score
    score=$(echo "$confidence" | sed 's|/10||' | tr -d ' ')

    if ! [[ "$score" =~ ^[0-9]+$ ]]; then
        block_error "Invalid confidence format: '${confidence}'. Use format: N/10 (e.g., 7/10)"
    fi

    if [ "$score" -lt 1 ] || [ "$score" -gt 10 ]; then
        block_error "Confidence score out of range: ${score}. Must be 1-10"
    fi
}

# Check review staleness (30 days)
check_review_staleness() {
    local reviewed="$1"
    # Skip if date format is invalid
    if ! date -j -f "%Y-%m-%d" "$reviewed" "+%s" >/dev/null 2>&1; then
        warn "Could not parse reviewed date: ${reviewed}. Expected format: YYYY-MM-DD"
        return
    fi

    local reviewed_epoch
    local now_epoch
    local days_old

    reviewed_epoch=$(date -j -f "%Y-%m-%d" "$reviewed" "+%s" 2>/dev/null || echo 0)
    now_epoch=$(date "+%s")
    days_old=$(( (now_epoch - reviewed_epoch) / 86400 ))

    if [ "$days_old" -gt 30 ]; then
        warn "PRP reviewed ${days_old} days ago (threshold: 30 days). Consider refreshing with /blueprint:prp-create"
    fi
}

# Main validation
FRONTMATTER=$(extract_frontmatter "$CONTENT")

if [ -z "$FRONTMATTER" ]; then
    block_error "No YAML frontmatter found. PRPs must have frontmatter between --- delimiters"
fi

# Required frontmatter fields (comprehensive set)
check_required_field "$FRONTMATTER" "created"
check_required_field "$FRONTMATTER" "modified"
check_required_field "$FRONTMATTER" "reviewed"
check_required_field "$FRONTMATTER" "status"
check_required_field "$FRONTMATTER" "confidence"
check_required_field "$FRONTMATTER" "domain"

# Feature-codes and related can be empty arrays, just need to exist
if ! echo "$FRONTMATTER" | grep -q "^feature-codes:"; then
    block_error "Missing required frontmatter field: feature-codes (can be empty array [])"
fi
if ! echo "$FRONTMATTER" | grep -q "^related:"; then
    block_error "Missing required frontmatter field: related (can be empty array [])"
fi

# Validate status value
PRP_STATUS=$(get_field "$FRONTMATTER" "status")
validate_status "$PRP_STATUS"

# Validate confidence format
CONFIDENCE=$(get_field "$FRONTMATTER" "confidence")
validate_confidence "$CONFIDENCE"

# Check review staleness
REVIEWED=$(get_field "$FRONTMATTER" "reviewed")
check_review_staleness "$REVIEWED"

# Required markdown sections (full structure)
check_required_section "$CONTENT" "Context Framing"
check_required_section "$CONTENT" "AI Documentation"
check_required_section "$CONTENT" "Implementation Blueprint"
check_required_section "$CONTENT" "Test Strategy"
check_required_section "$CONTENT" "Validation Gates"
check_required_section "$CONTENT" "Success Criteria"

# All checks passed
info "PRP frontmatter validation passed"
exit 0
