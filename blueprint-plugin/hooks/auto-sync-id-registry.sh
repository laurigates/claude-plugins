#!/usr/bin/env bash
# PostToolUse hook - auto-syncs id_registry in manifest after document writes
# Fires after Write/Edit to docs/{prds,adrs,prps}/** and docs/blueprint/work-orders/**
# Updates manifest.json id_registry so /blueprint:sync-ids is no longer needed for routine use

set -euo pipefail

# Check for bypass
if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the file path from tool input
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# If no file path, nothing to do
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

MANIFEST="docs/blueprint/manifest.json"

# If no manifest, skip silently (blueprint not initialized)
if [ ! -f "$MANIFEST" ]; then
    exit 0
fi

# If manifest has no id_registry, initialize it
if ! jq -e '.id_registry' "$MANIFEST" >/dev/null 2>&1; then
    jq '. + {"id_registry": {"last_prd": 0, "last_prp": 0, "documents": {}, "github_issues": {}}}' \
        "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"
fi

# Only process blueprint documents
case "$FILE_PATH" in
    docs/prds/*.md|docs/adrs/*.md|docs/prps/*.md|docs/blueprint/work-orders/*.md) ;;
    *) exit 0 ;;
esac

# File must exist (could have been deleted)
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# Extract frontmatter from the actual file on disk
FRONTMATTER=$(awk '/^---$/{if(++n==2)exit}n' "$FILE_PATH" | tail -n +2)

if [ -z "$FRONTMATTER" ]; then
    exit 0
fi

# Extract fields
DOC_ID=$(echo "$FRONTMATTER" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//' | tr -d '\r' || true)

# No ID means nothing to register (PreToolUse should have caught this)
if [ -z "$DOC_ID" ]; then
    exit 0
fi

# Check if this ID is already in the registry
if jq -e --arg id "$DOC_ID" '.id_registry.documents[$id]' "$MANIFEST" >/dev/null 2>&1; then
    # Already registered — update path/status/title in case they changed
    DOC_STATUS=$(echo "$FRONTMATTER" | grep -m1 "^status:" | sed 's/^status:[[:space:]]*//' | tr -d '\r' || true)
    DOC_TITLE=$(echo "$FRONTMATTER" | grep -m1 "^title:" | sed 's/^title:[[:space:]]*//' | tr -d '\r' || true)

    # If no title in frontmatter, try first heading
    if [ -z "$DOC_TITLE" ]; then
        DOC_TITLE=$(grep -m1 "^# " "$FILE_PATH" | sed 's/^# //' | tr -d '\r' || true)
    fi

    jq --arg id "$DOC_ID" \
       --arg path "$FILE_PATH" \
       --arg status "${DOC_STATUS:-unknown}" \
       --arg title "${DOC_TITLE:-untitled}" \
       '.id_registry.documents[$id].path = $path |
        .id_registry.documents[$id].status = $status |
        .id_registry.documents[$id].title = $title' \
       "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"

    echo "INFO: Updated registry entry for $DOC_ID" >&2
    exit 0
fi

# New document — register it
DOC_STATUS=$(echo "$FRONTMATTER" | grep -m1 "^status:" | sed 's/^status:[[:space:]]*//' | tr -d '\r' || true)
DOC_TITLE=$(echo "$FRONTMATTER" | grep -m1 "^title:" | sed 's/^title:[[:space:]]*//' | tr -d '\r' || true)
DOC_CREATED=$(echo "$FRONTMATTER" | grep -m1 "^created:" | sed 's/^created:[[:space:]]*//' | tr -d '\r' || true)

# If no title in frontmatter, try first heading
if [ -z "$DOC_TITLE" ]; then
    DOC_TITLE=$(grep -m1 "^# " "$FILE_PATH" | sed 's/^# //' | tr -d '\r' || true)
fi

# Extract cross-references (relates-to array)
RELATES_TO=$(echo "$FRONTMATTER" | awk '/^relates-to:/{flag=1; next} /^[a-z]/{flag=0} flag && /^  - /{gsub(/^  - /,""); print}' | jq -R -s 'split("\n") | map(select(length > 0))' || echo '[]')

# Extract github-issues array
GITHUB_ISSUES=$(echo "$FRONTMATTER" | awk '/^github-issues:/{flag=1; next} /^[a-z]/{flag=0} flag && /^  - /{gsub(/^  - /,""); print}' | jq -R -s 'split("\n") | map(select(length > 0) | tonumber)' 2>/dev/null || echo '[]')

# Add document to registry
jq --arg id "$DOC_ID" \
   --arg path "$FILE_PATH" \
   --arg status "${DOC_STATUS:-unknown}" \
   --arg title "${DOC_TITLE:-untitled}" \
   --arg created "${DOC_CREATED:-$(date +%Y-%m-%d)}" \
   --argjson relates_to "${RELATES_TO}" \
   --argjson github_issues "${GITHUB_ISSUES}" \
   '.id_registry.documents[$id] = {
      "path": $path,
      "title": $title,
      "status": $status,
      "relates_to": $relates_to,
      "github_issues": $github_issues,
      "created": $created
    }' \
   "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"

# Update counters based on document type
case "$DOC_ID" in
    PRD-*)
        NUM=${DOC_ID#PRD-}
        NUM=$((10#$NUM))  # Strip leading zeros
        CURRENT=$(jq '.id_registry.last_prd // 0' "$MANIFEST")
        if [ "$NUM" -gt "$CURRENT" ]; then
            jq --argjson num "$NUM" '.id_registry.last_prd = $num' \
                "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"
        fi
        ;;
    PRP-*)
        NUM=${DOC_ID#PRP-}
        NUM=$((10#$NUM))
        CURRENT=$(jq '.id_registry.last_prp // 0' "$MANIFEST")
        if [ "$NUM" -gt "$CURRENT" ]; then
            jq --argjson num "$NUM" '.id_registry.last_prp = $num' \
                "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"
        fi
        ;;
esac

# Update github_issues reverse index
for ISSUE in $(echo "$GITHUB_ISSUES" | jq -r '.[]' 2>/dev/null); do
    jq --arg id "$DOC_ID" --arg issue "$ISSUE" \
       'if .id_registry.github_issues[$issue] then
          .id_registry.github_issues[$issue] += [$id] | .id_registry.github_issues[$issue] |= unique
        else
          .id_registry.github_issues[$issue] = [$id]
        end' \
       "$MANIFEST" > "${MANIFEST}.tmp" && mv "${MANIFEST}.tmp" "$MANIFEST"
done

echo "INFO: Registered $DOC_ID in manifest id_registry ($FILE_PATH)" >&2
exit 0
