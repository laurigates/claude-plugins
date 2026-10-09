#!/usr/bin/env bash
# blueprint-doc-change.sh — PostToolUse dispatcher for blueprint document edits.
#
# Registered once in hooks.json with `"matcher": "Write|Edit|Bash"`. It reads
# the changed paths from either payload shape (lib/doc-paths.sh), converts each
# to a project-relative path, and hands every path under docs/ to the per-file
# handlers as a Write-shaped payload:
#
#   auto-sync-id-registry.sh   id_registry entry for PRD/ADR/PRP/WO documents
#   sync-feature-tracker.sh    tracker last_updated/statistics (autonomy >= 1)
#   validate-frontmatter.sh    schema check of PRD/ADR/PRP documents; ERRORs are
#                              returned to Claude as additionalContext (a nudge:
#                              the edit already happened). The commit-time gate
#                              is the `blueprint-doc-schemas` pre-commit hook.
#
# Why one dispatcher instead of path matchers: a hook `matcher` is tested
# against the tool NAME only, so the former `Write(docs/adrs/**)` matchers were
# invalid regular expressions that never fired; and a Write|Edit hook never sees
# an edit made through Bash. Path filtering therefore has to happen here.
#
# Cost: this runs after every Bash call. Payloads that do not mention docs/ exit
# before jq is spawned.
#
# Best-effort and non-blocking: always exits 0. The SessionStart sweep
# (scripts/blueprint-autorun.sh) reconciles whatever this misses.

set -u

if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)

case "$INPUT" in
    *docs/*) ;;
    *) exit 0 ;;
esac

command -v jq >/dev/null 2>&1 || exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # lib/doc-paths.sh resolves at runtime from HOOK_DIR
. "${HOOK_DIR}/lib/doc-paths.sh"

ROOT=$(blueprint_project_root) || exit 0
[ -n "$ROOT" ] || exit 0
cd "$ROOT" || exit 0
[ -f docs/blueprint/manifest.json ] || exit 0

schema_errors=""
while IFS= read -r changed; do
    rel=$(blueprint_relpath "$changed" "$ROOT")
    case "$rel" in
        docs/*) ;;
        *) continue ;;
    esac
    payload=$(jq -nc --arg f "$rel" '{tool_name: "Write", tool_input: {file_path: $f}}')
    printf '%s' "$payload" | bash "${HOOK_DIR}/auto-sync-id-registry.sh" || true
    printf '%s' "$payload" | bash "${HOOK_DIR}/sync-feature-tracker.sh" || true

    case "$rel" in
        docs/prds/*.md|docs/adrs/*.md|docs/prps/*.md)
            errors=$(bash "${HOOK_DIR}/validate-frontmatter.sh" "$rel" 2>/dev/null \
                | grep -E 'SEVERITY=ERROR' | sed -E 's/^[[:space:]]*-[[:space:]]*//' || true)
            if [ -n "$errors" ]; then
                schema_errors="${schema_errors}${rel}:
${errors}
"
            fi
            ;;
    esac
done < <(blueprint_changed_paths "$INPUT")

if [ -n "$schema_errors" ]; then
    detail=$(printf '%s' "$schema_errors" | head -n 20)
    msg="Blueprint schema check: a document you just changed violates its schema (blueprint-plugin/schemas/). The edit was kept; fix these before committing, because the blueprint-doc-schemas pre-commit hook fails on ERROR.
${detail}"
    jq -nc --arg msg "$msg" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
fi

exit 0
