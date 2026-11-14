#!/usr/bin/env bash
# PostToolUse handler - auto-syncs id_registry in manifest after document writes
# Called by blueprint-doc-change.sh for each changed docs/** path (Write, Edit, or
# a Bash command's bashEditDiff); acts on docs/{prds,adrs,prps}/*.md and
# docs/blueprint/work-orders/*.md.
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

# Write/Edit payloads carry an absolute file_path; the checks below are
# project-relative. Resolve from the project root.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # lib/doc-paths.sh resolves at runtime from HOOK_DIR
. "${HOOK_DIR}/lib/doc-paths.sh"
ROOT=$(blueprint_project_root) || exit 0
cd "$ROOT" || exit 0
FILE_PATH=$(blueprint_relpath "$FILE_PATH" "$ROOT")
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

# Read the fields with the parser the session-start sweep and the sync-ids
# audit use (blueprint-autorun.sh --frontmatter-rows, #3549), so the hook and
# the sweep cannot register one document two ways. Row fields, \037-separated:
# path, has_frontmatter, id, status, title (heading fallback applied), created,
# relates_to, github_issues (lists \036-separated).
AUTORUN_BIN="${HOOK_DIR}/../scripts/blueprint-autorun.sh"
ROW=$(bash "$AUTORUN_BIN" --frontmatter-rows "$FILE_PATH")
IFS=$'\037' read -r _ HAS_FM DOC_ID DOC_STATUS DOC_TITLE DOC_CREATED DOC_RELATES DOC_ISSUES <<<"$ROW" || true

# No frontmatter or no ID means nothing to register (PreToolUse should have
# caught this)
if [ "${HAS_FM:-0}" != "1" ] || [ -z "$DOC_ID" ]; then
    exit 0
fi

# Check if this ID is already in the registry
if jq -e --arg id "$DOC_ID" '.id_registry.documents[$id]' "$MANIFEST" >/dev/null 2>&1; then
    # Already registered — update path/status/title in case they changed.
    # Most edits change the body, not the registered fields. jq re-serialises
    # the whole manifest, so writing anyway would reformat a hand-edited file
    # (expanding inline arrays) on every document edit.
    if jq -e --arg id "$DOC_ID" \
          --arg path "$FILE_PATH" \
          --arg status "${DOC_STATUS:-unknown}" \
          --arg title "${DOC_TITLE:-untitled}" \
          '.id_registry.documents[$id] as $d
           | $d.path == $path and $d.status == $status and $d.title == $title' \
          "$MANIFEST" >/dev/null 2>&1; then
        exit 0
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

# New document — register it. Cross-references come from the parser's list
# fields; a github-issues item that is not a number is dropped.
RELATES_TO=$(jq -cn --arg l "$DOC_RELATES" '$l | split("\u001e") | map(select(length > 0))')
GITHUB_ISSUES=$(jq -cn --arg l "$DOC_ISSUES" '$l | split("\u001e") | map(ltrimstr("#") | tonumber? // empty)')

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
