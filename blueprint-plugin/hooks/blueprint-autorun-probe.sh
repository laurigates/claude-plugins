#!/usr/bin/env bash
# blueprint-autorun-probe.sh — SessionStart probe implementing the level-1
# rung of ADR-0020 (blueprint autonomy levels).
#
# When docs/blueprint/manifest.json is present and automation.autonomy_level
# is >= 1, runs scripts/blueprint-autorun.sh (TTL-debounced per
# .claude/rules/drift-detection-triggering.md):
#   - deterministic due tasks are executed silently by the runner
#   - due AGENT-JUDGMENT tasks become drift findings via drift-protocol.sh:
#       level 1  -> one finding per due task, remediation /blueprint:<task>
#       level 2+ -> one aggregated finding, remediation /blueprint:autopilot
#
# Level 0 / missing automation block is a complete no-op (empty signal file).
# Opt out entirely with BLUEPRINT_AUTORUN_DISABLE=1; tune the debounce with
# BLUEPRINT_AUTORUN_TTL (seconds, default 3600). Test seams:
# BLUEPRINT_AUTORUN_BIN (runner path), CLAUDE_BLUEPRINT_AUTORUN_CACHE_DIR.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve protocol library (ships from hooks-plugin; siblings under the
# marketplace dir when installed).
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

drift_init "blueprint-autorun"
drift_no_op_if_missing "docs/blueprint/manifest.json"
drift_no_op_if_command_missing jq

MANIFEST="${DRIFT_CWD}/docs/blueprint/manifest.json"

if [ "${BLUEPRINT_AUTORUN_DISABLE:-0}" = "1" ]; then
    drift_emit
    exit 0
fi

autorun_level=$(jq -r '.automation.autonomy_level // 0' "$MANIFEST" 2>/dev/null || echo 0)
case "$autorun_level" in
    ''|*[!0-9]*) autorun_level=0 ;;
esac
if [ "$autorun_level" -lt 1 ]; then
    drift_emit
    exit 0
fi

AUTORUN_BIN="${BLUEPRINT_AUTORUN_BIN:-${SCRIPT_DIR}/../scripts/blueprint-autorun.sh}"
if [ ! -f "$AUTORUN_BIN" ]; then
    drift_emit
    exit 0
fi

# TTL debounce: cache the runner's output per project so the run happens at
# most once per interval. Claim the window (touch) BEFORE running so a killed
# run degrades to "no change" instead of re-running every session.
cache_base="${CLAUDE_BLUEPRINT_AUTORUN_CACHE_DIR:-${TMPDIR:-/tmp}/claude-blueprint-autorun}"
project_key=$(printf '%s' "$DRIFT_CWD" | cksum | awk '{print $1}')
cache_file="${cache_base}/${project_key}.out"
autorun_ttl="${BLUEPRINT_AUTORUN_TTL:-3600}"

mkdir -p "$cache_base" 2>/dev/null || { drift_emit; exit 0; }

cache_fresh=0
if [ -f "$cache_file" ]; then
    # GNU form first: on GNU, `stat -f %m` succeeds but prints the MOUNT POINT
    # (non-numeric), so it must not be the first candidate. BSD lacks -c and
    # falls through to -f %m (mtime there). Guard non-numeric to 0 (= stale).
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
    case "$cache_mtime" in
        ''|*[!0-9]*) cache_mtime=0 ;;
    esac
    probe_now=$(date +%s)
    if [ $((probe_now - cache_mtime)) -lt "$autorun_ttl" ]; then
        cache_fresh=1
    fi
fi

if [ "$cache_fresh" -eq 0 ]; then
    touch "$cache_file" 2>/dev/null
    bash "$AUTORUN_BIN" --project-dir "$DRIFT_CWD" > "${cache_file}.tmp" 2>/dev/null \
        && mv -f "${cache_file}.tmp" "$cache_file" \
        || rm -f "${cache_file}.tmp"
fi

if [ ! -s "$cache_file" ]; then
    drift_emit
    exit 0
fi

due_tasks=$(grep -m1 '^DUE_AGENT_TASKS=' "$cache_file" | cut -d= -f2 | tr -d '\r' || true)

if [ -n "$due_tasks" ]; then
    if [ "$autorun_level" -ge 2 ]; then
        due_count=$(printf '%s' "$due_tasks" | awk -F',' '{print NF}')
        drift_add_finding info \
            autorun_tasks_due \
            "${due_count} blueprint task(s) due (${due_tasks})" \
            "/blueprint:autopilot"
    else
        finding_count=0
        old_ifs="$IFS"
        IFS=','
        for due_task in $due_tasks; do
            [ -n "$due_task" ] || continue
            [ "$finding_count" -ge 3 ] && break
            task_schedule=$(grep -m1 "^TASK=${due_task} KIND=agent" "$cache_file" \
                | sed -n 's/.*SCHEDULE=\([^ ]*\).*/\1/p' || true)
            drift_add_finding info \
                task_due \
                "blueprint task ${due_task} due (${task_schedule:-scheduled})" \
                "/blueprint:${due_task}"
            finding_count=$((finding_count + 1))
        done
        IFS="$old_ifs"
    fi
fi

drift_emit
exit 0
