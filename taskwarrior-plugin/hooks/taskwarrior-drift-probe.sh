#!/usr/bin/env bash
# taskwarrior-drift-probe.sh — SessionStart probe for taskwarrior-plugin drift.
#
# The plugin's skills reference custom UDAs (bpid, bpdoc, bpms, ghid, ghpr,
# agent, pid, host, branch, worktree). If those UDAs are not declared in
# ~/.taskrc, `task add` silently drops the field. This probe surfaces that gap
# at session start so the user can install the UDAs via `/taskwarrior:task-add`
# (which offers the install). The canonical UDA list lives in the shared
# scripts/ensure-udas.sh — this probe calls it in --check mode so the list is
# single-sourced and never mutates ~/.taskrc from a SessionStart hook.
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

# Single-source the required-UDA list: ask the shared ensure-udas.sh script
# (which task-add / task-claim also use) what is missing, in --check mode so it
# never mutates ~/.taskrc from a SessionStart probe.
ENSURE_UDAS="${SCRIPT_DIR}/../scripts/ensure-udas.sh"
if [ -f "$ENSURE_UDAS" ]; then
    uda_report=$(bash "$ENSURE_UDAS" --check 2>/dev/null || true)
    missing_count=$(printf '%s\n' "$uda_report" | grep -m1 '^UDAS_MISSING=' | cut -d= -f2)
    missing_count="${missing_count:-0}"
    if [ "$missing_count" -gt 0 ] 2>/dev/null; then
        list=$(printf '%s\n' "$uda_report" | grep -m1 '^MISSING_NAMES=' | cut -d= -f2)
        drift_add_finding warn \
            udas_missing \
            "${missing_count} UDA(s) missing from ~/.taskrc: ${list}" \
            "/taskwarrior:task-add"
    fi
fi

drift_emit
exit 0
