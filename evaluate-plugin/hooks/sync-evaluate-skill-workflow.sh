#!/usr/bin/env bash
# sync-evaluate-skill-workflow.sh — SessionStart: keep the registered copy of
# the evaluate-skill workflow in step with the bundled template (issue #2829).
#
# evaluate-plugin-batch calls workflow('evaluate-skill', …), which resolves BY
# NAME against ~/.claude/workflows/. This hook copies
#   ${CLAUDE_PLUGIN_ROOT}/skills/evaluate-skill/workflows/evaluate-skill.workflow.js
# to ~/.claude/workflows/evaluate-skill.workflow.js when the target is missing
# or differs. The installed basename matches the template's meta.name; keep the
# two in step (docs/dynamic-workflow-registration.md).
#
# The workflow registry does not re-read the directory mid-session, so a copy
# written here takes effect from the next session.
#
# Silent and fail-open: no output, and exit 0 on every path, including a
# missing template, an unset HOME, and an unwritable target.

# No -e: a failed copy must fall through to exit 0, never abort with non-zero.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 0
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-${SCRIPT_DIR}/..}"
SRC="${PLUGIN_ROOT}/skills/evaluate-skill/workflows/evaluate-skill.workflow.js"

[ -n "${HOME:-}" ] || exit 0
[ -f "$SRC" ] || exit 0

DEST_DIR="${HOME}/.claude/workflows"
DEST="${DEST_DIR}/evaluate-skill.workflow.js"

if [ -f "$DEST" ] && cmp -s "$SRC" "$DEST"; then
    exit 0
fi

mkdir -p "$DEST_DIR" 2>/dev/null || exit 0

# Copy to a temp name and rename, so a session never reads a half-written file.
TMP="${DEST}.tmp.$$"
if cp "$SRC" "$TMP" 2>/dev/null && mv -f "$TMP" "$DEST" 2>/dev/null; then
    exit 0
fi
rm -f "$TMP" 2>/dev/null
exit 0
