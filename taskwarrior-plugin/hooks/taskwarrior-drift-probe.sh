#!/usr/bin/env bash
# taskwarrior-drift-probe.sh — SessionStart probe for taskwarrior-plugin drift.
#
# The plugin's task-add skill references custom UDAs (bpid, bpdoc, bpms, ghid,
# ghpr, agent, pid, host, branch, worktree). If those UDAs are not declared in
# ~/.taskrc, `task add` silently drops the field. This probe surfaces that gap
# at session start so the user can install the UDAs via `/taskwarrior:task-add`
# (which offers the install).
#
# No-ops when ~/.taskrc is absent OR the task binary is missing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    for candidate in \
        "${CLAUDE_PLUGIN_ROOT:-}/../hooks-plugin/hooks/lib/drift-protocol.sh" \
        "$HOME/.claude/plugins/hooks-plugin/hooks/lib/drift-protocol.sh"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ]; then
            PROTO_LIB="$candidate"
            break
        fi
    done
fi
if [ ! -f "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via fallback chain
. "$PROTO_LIB"

drift_init "taskwarrior-plugin"

# No-op if user doesn't use taskwarrior.
TASKRC="${HOME}/.taskrc"
if [ ! -f "$TASKRC" ]; then
    drift_emit
    exit 0
fi
if ! command -v task >/dev/null 2>&1; then
    drift_emit
    exit 0
fi

# UDAs the plugin's task-add skill emits.
required_udas=(bpid bpdoc bpms ghid ghpr agent pid host branch worktree)

missing=()
for uda in "${required_udas[@]}"; do
    # Match either inline taskrc form (uda.<name>.type=...) or include-based.
    # `task _udas` is the authoritative list; fall back to grep on taskrc.
    if task _udas 2>/dev/null | grep -qx "$uda"; then
        continue
    fi
    if grep -qE "^uda\.${uda}\.type" "$TASKRC" 2>/dev/null; then
        continue
    fi
    missing+=("$uda")
done

if [ "${#missing[@]}" -gt 0 ]; then
    list=$(IFS=, ; printf '%s' "${missing[*]}")
    drift_add_finding warn \
        udas_missing \
        "${#missing[@]} UDA(s) missing from ~/.taskrc: ${list}" \
        "/taskwarrior:task-add"
fi

drift_emit
exit 0
