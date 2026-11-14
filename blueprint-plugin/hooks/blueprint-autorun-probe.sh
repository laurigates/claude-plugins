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
#   - a run that never returned (killed by the hook timeout) becomes an
#     autorun_incomplete finding in the next session (#3169)
#   - on the run that produced it (never from a TTL-fresh cache), a task line
#     with CHANGED=true becomes a registry_reconciled finding (remediation:
#     commit docs/blueprint/manifest.json) and STATE=error becomes an
#     autorun_task_error finding naming the task (#3551)
#
# Level 0 / missing automation block is a complete no-op (empty signal file).
# Opt out entirely with BLUEPRINT_AUTORUN_DISABLE=1; tune the debounce with
# BLUEPRINT_AUTORUN_TTL (seconds, default 3600). Test seams:
# BLUEPRINT_AUTORUN_BIN (runner path), CLAUDE_BLUEPRINT_AUTORUN_CACHE_DIR.

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

# Start/done markers make a killed run visible (#3169). The harness kills the
# hook when the runner outlives the 5 s SessionStart budget, so the killed
# session reports nothing; a later session that finds the start marker
# without the done marker reports autorun_incomplete instead of looking like
# "nothing due". The done marker is written once the runner returns, whatever
# its exit status: only a run that never returned is incomplete.
started_marker="${cache_base}/${project_key}.started"
done_marker="${cache_base}/${project_key}.done"

ran_now=0
if [ "$cache_fresh" -eq 0 ]; then
    rm -f "$done_marker"
    touch "$started_marker" "$cache_file" 2>/dev/null
    if bash "$AUTORUN_BIN" --project-dir "$DRIFT_CWD" > "${cache_file}.tmp" 2>/dev/null; then
        if mv -f "${cache_file}.tmp" "$cache_file"; then
            ran_now=1
        else
            rm -f "${cache_file}.tmp"
        fi
    else
        rm -f "${cache_file}.tmp"
    fi
    touch "$done_marker" 2>/dev/null
fi

# What the sweep did this session (#3551). Read only from the run that just
# produced the output: a TTL-fresh cache is re-read for up to an hour, and a
# finding taken from it would repeat after the manifest was committed.
if [ "$ran_now" -eq 1 ]; then
    while IFS= read -r task_line; do
        task_line=${task_line%$'\r'}
        line_task=$(printf '%s\n' "$task_line" | sed -n 's/^TASK=\([^ ]*\).*/\1/p')
        [ -n "$line_task" ] || continue
        case " $task_line " in
            *" STATE=error "*)
                drift_add_finding warn \
                    autorun_task_error \
                    "blueprint autorun task ${line_task} failed at session start; the manifest was left unchanged" \
                    "/blueprint:${line_task}"
                ;;
            *" CHANGED=true "*)
                counts=""
                for count_key in ADDED UPDATED PRUNED; do
                    count_val=$(printf '%s\n' "$task_line" | sed -n "s/.* ${count_key}=\([0-9][0-9]*\).*/\1/p")
                    [ -n "$count_val" ] && counts="${counts}${counts:+, }${count_key}=${count_val}"
                done
                drift_add_finding info \
                    registry_reconciled \
                    "blueprint ${line_task} reconciled the id registry at session start and wrote docs/blueprint/manifest.json${counts:+ (${counts})}" \
                    "commit docs/blueprint/manifest.json"
                ;;
        esac
    done < <(grep '^TASK=' "$cache_file" 2>/dev/null)
fi

if [ -f "$started_marker" ] && [ ! -f "$done_marker" ]; then
    drift_add_finding warn \
        autorun_incomplete \
        "blueprint autorun did not finish within the SessionStart hook budget; the id-registry reconcile has not landed" \
        "/blueprint:sync-ids"
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
