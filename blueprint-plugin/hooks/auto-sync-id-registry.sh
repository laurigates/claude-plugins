#!/usr/bin/env bash
# PostToolUse handler - reconciles id_registry after one document write.
#
# Kept for direct invocation with a Write-shaped payload. The registration
# itself is the one id-registry engine, `blueprint-autorun.sh
# --registry-reconcile` (ADR-0027 Q4, #3550): this script only decides whether
# the payload's path is a blueprint document and then calls it. The dispatcher
# blueprint-doc-change.sh calls the engine directly, once per tool call.
#
# The per-field registration body and its shared `${MANIFEST}.tmp` writes
# lived here before #3550. Concurrent calls through that one temp file lost
# registrations and truncated the manifest to 0 bytes; the engine writes under
# a lock through a per-PID temp file.

set -euo pipefail

if [ "${BLUEPRINT_SKIP_HOOKS:-0}" = "1" ]; then
    exit 0
fi

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
if [ -z "$FILE_PATH" ]; then
    exit 0
fi

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091  # lib/doc-paths.sh resolves at runtime from HOOK_DIR
. "${HOOK_DIR}/lib/doc-paths.sh"
ROOT=$(blueprint_project_root) || exit 0
FILE_PATH=$(blueprint_relpath "$FILE_PATH" "$ROOT")

# A deleted document counts too: the engine prunes nothing for a missing path,
# but it must still see the change to rebuild counters and the reverse index.
if ! blueprint_is_registry_path "$FILE_PATH"; then
    exit 0
fi
[ -f "${ROOT}/docs/blueprint/manifest.json" ] || exit 0

bash "${HOOK_DIR}/../scripts/blueprint-autorun.sh" --registry-reconcile --project-dir "$ROOT" >/dev/null 2>&1 || true
exit 0
