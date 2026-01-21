#!/bin/bash
# PreToolUse hook - validates ADR frontmatter before Write/Edit
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

# Validate ADR status value (extended set)
validate_status() {
    local adr_status="$1"
    case "$adr_status" in
        Draft|Proposed|Accepted|Rejected|Withdrawn|Superseded|Deprecated)
            return 0
            ;;
        *)
            block_error "Invalid ADR status: '${adr_status}'. Valid values: Draft, Proposed, Accepted, Rejected, Withdrawn, Superseded, Deprecated"
            ;;
    esac
}

# Check for supersedes consistency
check_supersedes_consistency() {
    local frontmatter="$1"
    local adr_status="$2"

    local supersedes
    supersedes=$(get_field "$frontmatter" "supersedes")

    # If status is Superseded, warn if no superseded-by reference
    if [ "$adr_status" = "Superseded" ]; then
        local superseded_by
        superseded_by=$(get_field "$frontmatter" "superseded-by")
        if [ -z "$superseded_by" ]; then
            warn "ADR status is 'Superseded' but no 'superseded-by' field found. Consider adding reference to the superseding ADR"
        fi
    fi

    # If supersedes field exists, the referenced ADR should exist (warning only)
    if [ -n "$supersedes" ]; then
        info "ADR supersedes: ${supersedes}"
    fi
}

# Check domain field for conflict detection preparation
check_domain() {
    local frontmatter="$1"
    local domain
    domain=$(get_field "$frontmatter" "domain")

    if [ -z "$domain" ]; then
        warn "Missing 'domain' field. Adding domain helps detect ADR conflicts in the same area"
    fi
}

# Main validation
FRONTMATTER=$(extract_frontmatter "$CONTENT")

if [ -z "$FRONTMATTER" ]; then
    block_error "No YAML frontmatter found. ADRs must have frontmatter between --- delimiters"
fi

# Required frontmatter fields
check_required_field "$FRONTMATTER" "status"
check_required_field "$FRONTMATTER" "created"
check_required_field "$FRONTMATTER" "modified"

# Validate status value
ADR_STATUS=$(get_field "$FRONTMATTER" "status")
validate_status "$ADR_STATUS"

# Check for domain (warning only)
check_domain "$FRONTMATTER"

# Check supersedes consistency
check_supersedes_consistency "$FRONTMATTER" "$ADR_STATUS"

# Required markdown sections (extended set)
check_required_section "$CONTENT" "Context"
check_required_section "$CONTENT" "Decision"
check_required_section "$CONTENT" "Consequences"
check_required_section "$CONTENT" "Options Considered"
check_required_section "$CONTENT" "Related ADRs"

# All checks passed
info "ADR frontmatter validation passed"
exit 0
