#!/usr/bin/env bash
# blueprint-drift-probe.sh — SessionStart probe for blueprint-plugin drift.
#
# Checks (when docs/blueprint/manifest.json is present):
#   1. manifest.format_version vs the plugin's current format version (3.3.0)
#   2. generated.rules[].content_hash vs current hash of the file on disk
#   3. docs/blueprint/feature_tracker.json `last_updated` vs TODO.md mtime
#
# Emits findings to the shared drift-signal directory via drift-protocol.sh.
# No-ops silently when manifest.json is absent.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve protocol library. It ships from hooks-plugin. When this probe is
# installed via the marketplace, both plugins live as siblings under
# ~/.claude/plugins/<marketplace>/, so ../../hooks-plugin/hooks/lib resolves.
PROTO_LIB="${SCRIPT_DIR}/../../hooks-plugin/hooks/lib/drift-protocol.sh"
if [ ! -f "$PROTO_LIB" ]; then
    # Best-effort fallback locations.
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

drift_init "blueprint-plugin"
drift_no_op_if_missing "docs/blueprint/manifest.json"

CURRENT_FORMAT_VERSION="3.3.0"
MANIFEST="${DRIFT_CWD}/docs/blueprint/manifest.json"

# ---- check 1: format_version drift ----
manifest_version=$(jq -r '.format_version // empty' "$MANIFEST" 2>/dev/null || echo "")
if [ -n "$manifest_version" ] && [ "$manifest_version" != "$CURRENT_FORMAT_VERSION" ]; then
    # Lexical compare is enough for "differs"; we don't try to order versions.
    drift_add_finding warn \
        format_version_drift \
        "manifest format_version ${manifest_version} != plugin ${CURRENT_FORMAT_VERSION}" \
        "/blueprint:upgrade"
fi

# ---- check 2: generated rule content_hash drift ----
# generated.rules is an array of {path, content_hash, source_hash, ...}. If the
# file on disk doesn't hash to content_hash anymore, someone hand-edited it.
if command -v shasum >/dev/null 2>&1; then
    drifted_count=0
    while IFS=$'\t' read -r rule_path rule_hash; do
        [ -z "$rule_path" ] && continue
        [ -z "$rule_hash" ] && continue
        full="${DRIFT_CWD}/${rule_path}"
        [ -f "$full" ] || continue
        current=$(shasum -a 256 "$full" 2>/dev/null | awk '{print $1}')
        [ -z "$current" ] && continue
        if [ "$current" != "$rule_hash" ]; then
            drifted_count=$((drifted_count + 1))
        fi
    done < <(
        jq -r '
            (.generated.rules // [])[]
            | select((.content_hash // "") != "")
            | [.path, .content_hash]
            | @tsv
        ' "$MANIFEST" 2>/dev/null
    )
    if [ "$drifted_count" -gt 0 ]; then
        drift_add_finding warn \
            generated_rules_drift \
            "${drifted_count} generated rule file(s) drifted from manifest hash" \
            "/blueprint:sync"
    fi
fi

# ---- check 3: feature_tracker last_updated vs TODO.md mtime ----
TRACKER="${DRIFT_CWD}/docs/blueprint/feature_tracker.json"
TODO="${DRIFT_CWD}/TODO.md"
if [ -f "$TRACKER" ] && [ -f "$TODO" ]; then
    tracker_iso=$(jq -r '.last_updated // empty' "$TRACKER" 2>/dev/null || echo "")
    if [ -n "$tracker_iso" ]; then
        # Convert tracker timestamp + TODO mtime to epoch seconds (portable).
        tracker_epoch=""
        if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$tracker_iso" "+%s" >/dev/null 2>&1; then
            tracker_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$tracker_iso" "+%s" 2>/dev/null)
        elif date -j -f "%Y-%m-%d" "${tracker_iso%%T*}" "+%s" >/dev/null 2>&1; then
            tracker_epoch=$(date -j -f "%Y-%m-%d" "${tracker_iso%%T*}" "+%s" 2>/dev/null)
        elif date -d "$tracker_iso" "+%s" >/dev/null 2>&1; then
            tracker_epoch=$(date -d "$tracker_iso" "+%s" 2>/dev/null)
        fi
        todo_epoch=$(stat -f %m "$TODO" 2>/dev/null || stat -c %Y "$TODO" 2>/dev/null || echo "")
        if [ -n "$tracker_epoch" ] && [ -n "$todo_epoch" ] && [ "$todo_epoch" -gt "$tracker_epoch" ]; then
            drift_add_finding warn \
                feature_tracker_stale \
                "TODO.md modified after feature_tracker last_updated (${tracker_iso})" \
                "/blueprint:feature-tracker-sync"
        fi
    fi
fi

drift_emit
exit 0
