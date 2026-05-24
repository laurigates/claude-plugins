#!/usr/bin/env bash
# drift-protocol.sh — shared helpers for drift-nudge probes.
#
# Source this from a SessionStart probe to write a per-plugin signal file under
# ${CLAUDE_DRIFT_SIGNALS_DIR:-/tmp/claude-drift-signals}/<sanitized-session-id>/.
#
# The aggregator (hooks-plugin/hooks/drift-aggregator.sh) reads every JSON file
# in that directory and emits one consolidated SessionStart additionalContext
# nudge per session.
#
# Schema (per file):
#   {
#     "plugin": "<plugin-name>",
#     "checked_at": "<ISO-8601 UTC>",
#     "findings": [
#       {
#         "severity": "info|warn|error",
#         "kind": "<short snake_case identifier>",
#         "summary": "<one-line human readable>",
#         "remediation_skill": "/<plugin>:<skill>"
#       },
#       ...
#     ]
#   }
#
# Always write the file (empty findings = "checked, no drift"). The aggregator
# tells "didn't run" from "ran clean" by file presence.
#
# Sourcing pattern:
#
#   #!/usr/bin/env bash
#   set -uo pipefail
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   # shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
#   . "${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
#   drift_init "blueprint-plugin"   # parses stdin, sets DRIFT_SID / DRIFT_CWD, prepares signal dir
#   drift_no_op_if_missing "docs/blueprint/manifest.json"
#   drift_add_finding warn format_version_drift "manifest 3.2 < plugin 3.3" "/blueprint:upgrade"
#   drift_emit

# This file is sourced — we deliberately omit `set -e` so a non-zero command
# inside a helper does not exit the calling probe. `set -uo pipefail` is safe
# because every variable is initialized below and probes already enable both.
set -uo pipefail

# ---------- internals ----------

# DRIFT_SID, DRIFT_CWD, DRIFT_PLUGIN, DRIFT_SIGNAL_DIR, DRIFT_SIGNAL_FILE
# DRIFT_FINDINGS — JSON-array string built up by drift_add_finding.
DRIFT_FINDINGS="[]"
DRIFT_PLUGIN=""
DRIFT_SID=""
DRIFT_CWD=""
DRIFT_SIGNAL_DIR=""
DRIFT_SIGNAL_FILE=""

# drift_signal_dir — returns the per-session signal directory path on stdout.
# Honors $CLAUDE_DRIFT_SIGNALS_DIR override, sanitizes the session id, mkdir -p.
drift_signal_dir() {
    local sid="$1"
    local base="${CLAUDE_DRIFT_SIGNALS_DIR:-/tmp/claude-drift-signals}"
    # Sanitize: keep only alnum, hyphen, underscore. Prevents path traversal.
    local clean
    clean=$(printf '%s' "$sid" | tr -cd 'a-zA-Z0-9_-')
    if [ -z "$clean" ]; then
        clean="unknown"
    fi
    printf '%s/%s' "$base" "$clean"
}

# drift_init <plugin-name>
#   Reads JSON hook input from stdin, populates DRIFT_* globals, ensures the
#   signal directory exists. Exits 0 (silently) if session_id or cwd is missing,
#   or if jq is unavailable.
drift_init() {
    DRIFT_PLUGIN="${1:-}"
    if [ -z "$DRIFT_PLUGIN" ]; then
        exit 0
    fi

    if ! command -v jq >/dev/null 2>&1; then
        exit 0
    fi

    local input
    input=$(cat)
    DRIFT_SID=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)
    DRIFT_CWD=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)

    if [ -z "$DRIFT_SID" ]; then
        exit 0
    fi

    DRIFT_SIGNAL_DIR=$(drift_signal_dir "$DRIFT_SID")
    DRIFT_SIGNAL_FILE="${DRIFT_SIGNAL_DIR}/${DRIFT_PLUGIN}.json"
    mkdir -p "$DRIFT_SIGNAL_DIR" 2>/dev/null || exit 0
}

# drift_no_op_if_missing <path>
#   Exit 0 (after writing an empty signal file) if the given path does not exist.
#   Path is resolved relative to DRIFT_CWD when not absolute.
drift_no_op_if_missing() {
    local target="$1"
    case "$target" in
        /*) ;;
        *)
            if [ -n "$DRIFT_CWD" ]; then
                target="${DRIFT_CWD}/${target}"
            fi
            ;;
    esac
    if [ ! -e "$target" ]; then
        drift_emit
        exit 0
    fi
}

# drift_no_op_if_command_missing <command>
#   Exit 0 (with empty signal) if a required CLI is unavailable.
drift_no_op_if_command_missing() {
    if ! command -v "$1" >/dev/null 2>&1; then
        drift_emit
        exit 0
    fi
}

# drift_add_finding <severity> <kind> <summary> <remediation_skill>
#   Append a finding to DRIFT_FINDINGS. Severity must be info|warn|error.
drift_add_finding() {
    local severity="$1"
    local kind="$2"
    local summary="$3"
    local skill="$4"

    case "$severity" in
        info|warn|error) ;;
        *) severity="info" ;;
    esac

    DRIFT_FINDINGS=$(
        printf '%s' "$DRIFT_FINDINGS" | jq -c \
            --arg sev "$severity" \
            --arg kind "$kind" \
            --arg summary "$summary" \
            --arg skill "$skill" \
            '. + [{severity: $sev, kind: $kind, summary: $summary, remediation_skill: $skill}]' \
            2>/dev/null
    ) || DRIFT_FINDINGS="[]"
}

# drift_emit — writes the signal file atomically and returns 0. Safe to call
# multiple times; only the last DRIFT_FINDINGS state survives.
drift_emit() {
    if [ -z "$DRIFT_SIGNAL_FILE" ]; then
        return 0
    fi

    local checked_at
    checked_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")

    local payload
    payload=$(
        jq -n -c \
            --arg plugin "$DRIFT_PLUGIN" \
            --arg checked_at "$checked_at" \
            --argjson findings "$DRIFT_FINDINGS" \
            '{plugin: $plugin, checked_at: $checked_at, findings: $findings}' \
            2>/dev/null
    ) || return 0

    # Atomic write: temp file in same dir, then mv.
    local tmp="${DRIFT_SIGNAL_FILE}.tmp.$$"
    printf '%s\n' "$payload" > "$tmp" 2>/dev/null || return 0
    mv -f "$tmp" "$DRIFT_SIGNAL_FILE" 2>/dev/null || rm -f "$tmp"
}
