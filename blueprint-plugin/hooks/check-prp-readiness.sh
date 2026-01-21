#!/bin/bash
# PreToolUse hook - checks PRP readiness before execution
# Blocks if confidence < 7, required sections missing, or broken references
# See docs/hook-design-decisions.md for rationale

set -euo pipefail

# Check for bypass
if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

# Configuration
MIN_CONFIDENCE=7
URL_TIMEOUT=5

# Read the JSON input from stdin
INPUT=$(cat)

# Extract skill arguments (prp-name)
SKILL_ARGS=$(echo "$INPUT" | jq -r '.tool_input.args // empty')

# If no args, we can't validate - let the skill handle the error
if [ -z "$SKILL_ARGS" ]; then
    exit 0
fi

# Extract PRP name from args (first word)
PRP_NAME=$(echo "$SKILL_ARGS" | awk '{print $1}')

# Construct PRP path
PRP_PATH="docs/prps/${PRP_NAME}.md"

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

# Check if PRP file exists
if [ ! -f "$PRP_PATH" ]; then
    # Try with .md suffix already included
    if [ ! -f "${PRP_NAME}" ]; then
        block_error "PRP file not found: ${PRP_PATH}"
    else
        PRP_PATH="$PRP_NAME"
    fi
fi

# Read PRP content
PRP_CONTENT=$(cat "$PRP_PATH")

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

FRONTMATTER=$(extract_frontmatter "$PRP_CONTENT")

if [ -z "$FRONTMATTER" ]; then
    block_error "PRP has no frontmatter. Cannot validate readiness"
fi

# Check confidence score
CONFIDENCE=$(get_field "$FRONTMATTER" "confidence")
if [ -z "$CONFIDENCE" ]; then
    block_error "PRP missing confidence score. Run /blueprint:prp-create to add one"
fi

# Extract numeric confidence value
SCORE=$(echo "$CONFIDENCE" | sed 's|/10||' | tr -d ' ')
if ! [[ "$SCORE" =~ ^[0-9]+$ ]]; then
    block_error "Invalid confidence format: '${CONFIDENCE}'. Expected N/10 (e.g., 7/10)"
fi

if [ "$SCORE" -lt "$MIN_CONFIDENCE" ]; then
    block_error "Confidence score ${SCORE}/10 is below minimum ${MIN_CONFIDENCE}/10. Refine PRP with /blueprint:prp-create before execution"
fi

# Check for required sections
check_section() {
    local section="$1"
    if ! echo "$PRP_CONTENT" | grep -q "^## ${section}"; then
        block_error "PRP missing required section: ## ${section}"
    fi
}

check_section "Context Framing"
check_section "AI Documentation"
check_section "Implementation Blueprint"
check_section "Test Strategy"
check_section "Validation Gates"
check_section "Success Criteria"

# Extract and validate ai_docs references
# Look for patterns like: ai_docs/libraries/*.md, ai_docs/project/*.md
AI_DOC_REFS=$(echo "$PRP_CONTENT" | grep -oE 'ai_docs/[a-zA-Z0-9_/-]+\.md' | sort -u || true)

MISSING_FILES=()
for ref in $AI_DOC_REFS; do
    # Check relative to docs/blueprint/ (common location)
    if [ ! -f "docs/blueprint/${ref}" ] && [ ! -f "${ref}" ]; then
        MISSING_FILES+=("$ref")
    fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
    block_error "PRP references missing ai_docs files: ${MISSING_FILES[*]}"
fi

# Extract and validate URL references (markdown links)
# Pattern: [text](https://...) or bare https://... URLs
URLS=$(echo "$PRP_CONTENT" | grep -oE 'https?://[a-zA-Z0-9./_?&=%-]+' | sort -u || true)

UNREACHABLE_URLS=()
for url in $URLS; do
    # Skip common documentation URLs that may be rate-limited or require auth
    case "$url" in
        *github.com/*/blob/*|*github.com/*/tree/*|*githubusercontent.com/*)
            # GitHub raw/blob links - skip validation, usually behind auth
            continue
            ;;
        *localhost*|*127.0.0.1*|*0.0.0.0*)
            # Local URLs - skip
            continue
            ;;
    esac

    # Perform HEAD request with timeout
    if ! curl -sI --max-time "$URL_TIMEOUT" "$url" >/dev/null 2>&1; then
        UNREACHABLE_URLS+=("$url")
    fi
done

# Warn about unreachable URLs (don't block)
if [ ${#UNREACHABLE_URLS[@]} -gt 0 ]; then
    warn "Some URLs in PRP are unreachable (may be temporary): ${UNREACHABLE_URLS[*]}"
fi

# All critical checks passed
info "PRP readiness check passed: ${PRP_NAME} (confidence: ${SCORE}/10)"
exit 0
