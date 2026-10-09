#!/usr/bin/env bash
# configure-drift-probe.sh — SessionStart probe for configure-plugin drift.
#
# Checks (when .project-standards.yaml is present):
#   1. last_configured > 90 days ago
#   2. declared project_type vs detected stack (pyproject.toml / package.json /
#      Cargo.toml / go.mod)
#
# Emits findings via the shared drift-protocol library. No-op when
# .project-standards.yaml is absent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# >>> drift-protocol resolver >>>
# Keep this block byte-identical in every drift probe;
# scripts/tests/test-drift-probe-lib-resolution.sh enforces it.
# hooks-plugin ships the library. Layouts searched, in order:
#   flat    <root>/<plugin>/hooks          -> <root>/hooks-plugin/hooks/lib
#           (a claude-plugins checkout, --plugin-dir)
#   cache   <mkt>/<plugin>/<version>/hooks -> <mkt>/hooks-plugin/<version>/hooks/lib
#           (marketplace installs; old versions stay cached, highest wins)
#   legacy  ~/.claude/plugins/hooks-plugin/hooks/lib
# Before the cache layout was searched, every installed probe found nothing
# here and exited silently.
PROTO_LIB=""
for _dp_base in \
    "${SCRIPT_DIR}/../.." \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/..}" \
    "${SCRIPT_DIR}/../../.." \
    "${CLAUDE_PLUGIN_ROOT:+${CLAUDE_PLUGIN_ROOT}/../..}" \
    "$HOME/.claude/plugins"; do
    if [ -z "$_dp_base" ] || [ ! -d "$_dp_base/hooks-plugin" ]; then
        continue
    fi
    if [ -f "$_dp_base/hooks-plugin/hooks/lib/drift-protocol.sh" ]; then
        PROTO_LIB="$_dp_base/hooks-plugin/hooks/lib/drift-protocol.sh"
        break
    fi
    _dp_ver=$(
        for _dp_lib in "$_dp_base"/hooks-plugin/*/hooks/lib/drift-protocol.sh; do
            if [ -f "$_dp_lib" ]; then
                _dp_lib="${_dp_lib#"$_dp_base"/hooks-plugin/}"
                printf '%s\n' "${_dp_lib%%/*}"
            fi
        done | sort -V | tail -n 1
    ) || _dp_ver=""
    if [ -n "$_dp_ver" ]; then
        PROTO_LIB="$_dp_base/hooks-plugin/$_dp_ver/hooks/lib/drift-protocol.sh"
        break
    fi
done
unset _dp_base _dp_ver _dp_lib
if [ -z "$PROTO_LIB" ]; then
    exit 0
fi
# shellcheck source=../../hooks-plugin/hooks/lib/drift-protocol.sh
# shellcheck disable=SC1091  # PROTO_LIB resolves at runtime via the search above
. "$PROTO_LIB"
# <<< drift-protocol resolver <<<

drift_init "configure-plugin"
drift_no_op_if_missing ".project-standards.yaml"

STANDARDS="${DRIFT_CWD}/.project-standards.yaml"

# ---- check 1: last_configured > 90 days ----
last_configured=$(
    grep -m1 '^last_configured:' "$STANDARDS" 2>/dev/null \
        | sed 's/^[^:]*:[[:space:]]*//' \
        | tr -d '"' \
        | tr -d "'" \
        | tr -d '\r' \
        || echo ""
)
if [ -n "$last_configured" ]; then
    configured_epoch=""
    # Accept YYYY-MM-DD or full ISO-8601.
    if date -j -f "%Y-%m-%d" "${last_configured%%T*}" "+%s" >/dev/null 2>&1; then
        configured_epoch=$(date -j -f "%Y-%m-%d" "${last_configured%%T*}" "+%s" 2>/dev/null)
    elif date -d "$last_configured" "+%s" >/dev/null 2>&1; then
        configured_epoch=$(date -d "$last_configured" "+%s" 2>/dev/null)
    fi
    if [ -n "$configured_epoch" ]; then
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - configured_epoch) / 86400 ))
        if [ "$age_days" -gt 90 ]; then
            drift_add_finding warn \
                last_configured_stale \
                ".project-standards.yaml last_configured ${age_days} days ago (>90)" \
                "/configure:status"
        fi
    fi
fi

# ---- check 2: declared project_type vs detected stack ----
declared_type=$(
    grep -m1 '^project_type:' "$STANDARDS" 2>/dev/null \
        | sed 's/^[^:]*:[[:space:]]*//' \
        | tr -d '"' \
        | tr -d "'" \
        | tr -d '\r' \
        || echo ""
)
if [ -n "$declared_type" ]; then
    declared_lc=$(printf '%s' "$declared_type" | tr '[:upper:]' '[:lower:]')

    detected=""
    if [ -f "${DRIFT_CWD}/pyproject.toml" ] || [ -f "${DRIFT_CWD}/requirements.txt" ]; then
        detected="python"
    elif [ -f "${DRIFT_CWD}/package.json" ]; then
        detected="node"
    elif [ -f "${DRIFT_CWD}/Cargo.toml" ]; then
        detected="rust"
    elif [ -f "${DRIFT_CWD}/go.mod" ]; then
        detected="go"
    fi

    if [ -n "$detected" ] && [ "$declared_lc" != "$detected" ]; then
        # Avoid false positives for compound declarations like "python+node".
        case "$declared_lc" in
            *"$detected"*) ;;
            *)
                drift_add_finding warn \
                    project_type_drift \
                    "declared project_type='${declared_type}' but detected stack '${detected}'" \
                    "/configure:status"
                ;;
        esac
    fi
fi

drift_emit
exit 0
