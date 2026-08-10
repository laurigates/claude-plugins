#!/usr/bin/env bash
# blueprint-drift-probe.sh — SessionStart probe for blueprint-plugin drift.
#
# Checks (when docs/blueprint/manifest.json is present):
#   1. manifest.format_version vs the plugin's current format version (3.4.0)
#   2. generated.rules{filename}.content_hash vs current hash of the file on disk
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

CURRENT_FORMAT_VERSION="3.4.0"
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
# generated.rules is an OBJECT map, filename -> generatedRecord, per
# blueprint-plugin/schemas/manifest.schema.json — NOT an array. Iterating it as
# an array (`(.generated.rules // [])[]`) yields nothing on every real manifest,
# so this check silently passed over every registered rule (issue #2331).
#
# The key is a bare filename relative to structure.generated_rules_path,
# INCLUDING the .md extension, so the file is "$RULES_DIR/$key" — never
# "$RULES_DIR/$key.md". A record may also carry an explicit `path` (relative to
# the repo root) from an older migration; prefer it when present.
if command -v shasum >/dev/null 2>&1; then
    rules_dir=$(jq -r '.structure.generated_rules_path // ".claude/rules/"' "$MANIFEST" 2>/dev/null)
    [ -n "$rules_dir" ] && [ "$rules_dir" != "null" ] || rules_dir=".claude/rules/"
    rules_dir="${rules_dir%/}"

    drifted_count=0
    while IFS=$'\t' read -r rule_path rule_hash; do
        [ -z "$rule_path" ] && continue
        [ -z "$rule_hash" ] && continue
        case "$rule_path" in
            /*) full="$rule_path" ;;
            *)  full="${DRIFT_CWD}/${rule_path}" ;;
        esac
        [ -f "$full" ] || continue
        current=$(shasum -a 256 "$full" 2>/dev/null | awk '{print $1}')
        [ -z "$current" ] && continue
        if [ "$current" != "$rule_hash" ]; then
            drifted_count=$((drifted_count + 1))
        fi
    done < <(
        jq -r --arg dir "$rules_dir" '
            (.generated.rules // {})
            | to_entries[]
            | select((.value.content_hash // "") != "")
            | [(.value.path // ($dir + "/" + .key)), .value.content_hash]
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
        # GNU form first: on GNU, `stat -f %m` succeeds but prints the MOUNT
        # POINT (non-numeric); BSD lacks -c and falls through to -f %m (mtime).
        todo_epoch=$(stat -c %Y "$TODO" 2>/dev/null || stat -f %m "$TODO" 2>/dev/null || echo "")
        case "$todo_epoch" in
            *[!0-9]*) todo_epoch="" ;;
        esac
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
