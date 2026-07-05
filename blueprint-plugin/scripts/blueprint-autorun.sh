#!/usr/bin/env bash
# blueprint-autorun.sh — implement the manifest task_registry auto-run contract.
#
# Reads docs/blueprint/manifest.json, computes due-ness for every task with
# enabled:true + auto_run:true (schedule vs last_completed_at), executes the
# DETERMINISTIC due tasks directly (no model in the loop), and reports due
# AGENT-JUDGMENT tasks without executing them (the SessionStart probe turns
# those into drift findings; the level-2 autopilot skill executes them).
#
# Task-kind split (see ADR-0020 and
# .claude/rules/offload-to-deterministic-substrate.md):
#   deterministic : sync-ids (id-registry sweep — replays the
#                   auto-sync-id-registry.sh registration over all documents)
#   agent-judgment: everything else (adr-validate, feature-tracker-sync,
#                   story-audit, ...) — surfaced as due, never executed here.
#
# Schedule semantics:
#   daily/weekly : due when last_completed_at is null/unparseable or older
#                  than the interval
#   on-change    : event-driven (PostToolUse hooks) — never runner-due
#   on-demand    : never due
#
# Execution is gated on automation.autonomy_level >= 1 (missing block = 0).
# --report computes due-ness only: no execution, no writeback.
# BLUEPRINT_AUTORUN_DISABLE=1 makes the whole script a no-op.
#
# Output follows .claude/rules/structured-script-output.md.
# Exit 0 on OK/WARN, 1 on ERROR (parallel-safe).
#
# Usage: blueprint-autorun.sh [--project-dir DIR] [--report]

# set -u only (no -e/pipefail): this is a run-every-section collector — a
# single failing task must not abort the remaining tasks (see
# .claude/rules/shell-scripting.md "Error Handling Flags").
set -u

project_dir="."
run_mode="apply"

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)
            project_dir="${2:-.}"
            shift 2
            ;;
        --report)
            run_mode="report"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

section_open() { printf '=== BLUEPRINT AUTORUN ===\n'; }
section_close() { printf '=== END BLUEPRINT AUTORUN ===\n'; }

finish() {
    # finish <status> <issue_count> [extra KEY=VALUE lines already printed]
    printf 'STATUS=%s\n' "$1"
    printf 'ISSUE_COUNT=%s\n' "$2"
    section_close
    if [ "$1" = "ERROR" ]; then
        exit 1
    fi
    exit 0
}

section_open
printf 'MODE=%s\n' "$run_mode"

if [ "${BLUEPRINT_AUTORUN_DISABLE:-0}" = "1" ]; then
    printf 'AUTORUN=disabled_by_env\n'
    printf 'DUE_AGENT_TASKS=\n'
    printf 'RAN_COUNT=0\n'
    finish OK 0
fi

if ! command -v jq >/dev/null 2>&1; then
    printf 'AUTORUN=jq_unavailable\n'
    printf 'DUE_AGENT_TASKS=\n'
    printf 'RAN_COUNT=0\n'
    finish OK 0
fi

manifest=""
if [ -f "${project_dir}/docs/blueprint/manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/manifest.json"
elif [ -f "${project_dir}/docs/blueprint/.manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/.manifest.json"
fi

if [ -z "$manifest" ]; then
    printf 'AUTORUN=no_manifest\n'
    printf 'DUE_AGENT_TASKS=\n'
    printf 'RAN_COUNT=0\n'
    finish OK 0
fi
printf 'MANIFEST=%s\n' "$manifest"

autonomy_level=$(jq -r '.automation.autonomy_level // 0' "$manifest" 2>/dev/null || echo 0)
case "$autonomy_level" in
    ''|*[!0-9]*) autonomy_level=0 ;;
esac
printf 'AUTONOMY_LEVEL=%s\n' "$autonomy_level"

# Deterministic ISO-8601 UTC -> epoch (BSD fills unspecified fields with the
# current wall clock, so the format string pins every field; see
# .claude/rules/shell-scripting.md "GNU vs BSD Tool Differences").
iso_to_epoch() {
    local iso_ts="$1"
    if date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_ts" "+%s" >/dev/null 2>&1; then
        date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso_ts" "+%s" 2>/dev/null
    elif date -u -d "$iso_ts" "+%s" >/dev/null 2>&1; then
        date -u -d "$iso_ts" "+%s" 2>/dev/null
    else
        echo ""
    fi
}

now_epoch=$(date -u +%s)
now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

is_deterministic() {
    case "$1" in
        sync-ids) return 0 ;;
        *) return 1 ;;
    esac
}

# Replay the auto-sync-id-registry.sh registration over every blueprint
# document. Registry completeness only (path/status/title/counters) — the
# relates_to/github_issues cross-refs are the write-time PostToolUse hook's
# job and existing values are preserved by the merge.
run_sync_ids() {
    local docs_seen=0
    local doc_file frontmatter doc_id doc_status doc_title doc_created

    if ! jq -e '.id_registry' "$manifest" >/dev/null 2>&1; then
        jq '. + {"id_registry": {"last_prd": 0, "last_prp": 0, "documents": {}, "github_issues": {}}}' \
            "$manifest" > "${manifest}.tmp" && mv "${manifest}.tmp" "$manifest" || return 1
    fi

    while IFS= read -r doc_file; do
        [ -f "$doc_file" ] || continue
        frontmatter=$(awk '/^---$/{if(++n==2)exit}n' "$doc_file" | tail -n +2)
        [ -n "$frontmatter" ] || continue
        doc_id=$(printf '%s\n' "$frontmatter" | grep -m1 "^id:" | sed 's/^id:[[:space:]]*//' | tr -d '\r' || true)
        [ -n "$doc_id" ] || continue

        doc_status=$(printf '%s\n' "$frontmatter" | grep -m1 "^status:" | sed 's/^status:[[:space:]]*//' | tr -d '\r' || true)
        doc_title=$(printf '%s\n' "$frontmatter" | grep -m1 "^title:" | sed 's/^title:[[:space:]]*//' | tr -d '\r' || true)
        if [ -z "$doc_title" ]; then
            doc_title=$(grep -m1 "^# " "$doc_file" | sed 's/^# //' | tr -d '\r' || true)
        fi
        doc_created=$(printf '%s\n' "$frontmatter" | grep -m1 "^created:" | sed 's/^created:[[:space:]]*//' | tr -d '\r' || true)

        local rel_path="${doc_file#"${project_dir}"/}"
        jq --arg id "$doc_id" \
           --arg doc_path "$rel_path" \
           --arg doc_status "${doc_status:-unknown}" \
           --arg title "${doc_title:-untitled}" \
           --arg created "${doc_created:-$now_iso}" \
           '.id_registry.documents[$id] =
              ((.id_registry.documents[$id] // {"created": $created, "relates_to": [], "github_issues": []})
               + {path: $doc_path, status: $doc_status, title: $title}) |
            (if ($id | startswith("PRD-")) then
               .id_registry.last_prd = ([.id_registry.last_prd // 0, (($id | ltrimstr("PRD-")) | tonumber? // 0)] | max)
             elif ($id | startswith("PRP-")) then
               .id_registry.last_prp = ([.id_registry.last_prp // 0, (($id | ltrimstr("PRP-")) | tonumber? // 0)] | max)
             else . end)' \
           "$manifest" > "${manifest}.tmp" && mv "${manifest}.tmp" "$manifest" || return 1
        docs_seen=$((docs_seen + 1))
    done < <(find "${project_dir}/docs/prds" "${project_dir}/docs/adrs" "${project_dir}/docs/prps" \
                  "${project_dir}/docs/blueprint/work-orders" \
                  -maxdepth 1 -type f -name '*.md' 2>/dev/null)

    printf '%s' "$docs_seen"
    return 0
}

record_task_result() {
    # record_task_result <task> <result>
    jq --arg task "$1" --arg result "$2" --arg ts "$now_iso" \
       '.task_registry[$task].last_completed_at = $ts |
        .task_registry[$task].last_result = $result |
        .task_registry[$task].stats.runs = ((.task_registry[$task].stats.runs // 0) + 1)' \
       "$manifest" > "${manifest}.tmp" && mv "${manifest}.tmp" "$manifest"
}

due_agent_tasks=""
ran_count=0
issue_count=0
overall_status="OK"

while IFS=$'\t' read -r task_name task_enabled task_auto task_schedule task_last; do
    [ -n "$task_name" ] || continue

    if [ "$task_enabled" != "true" ] || [ "$task_auto" != "true" ]; then
        printf 'TASK=%s STATE=skipped REASON=%s\n' "$task_name" \
            "$([ "$task_enabled" != "true" ] && echo disabled || echo manual)"
        continue
    fi

    task_state="not_due"
    case "$task_schedule" in
        on-demand)
            task_state="on_demand"
            ;;
        on-change)
            task_state="event_driven"
            ;;
        daily|weekly)
            interval=86400
            [ "$task_schedule" = "weekly" ] && interval=604800
            if [ -z "$task_last" ] || [ "$task_last" = "null" ]; then
                task_state="due"
            else
                last_epoch=$(iso_to_epoch "$task_last")
                if [ -z "$last_epoch" ] || [ $((now_epoch - last_epoch)) -ge "$interval" ]; then
                    task_state="due"
                fi
            fi
            ;;
        *)
            task_state="unknown_schedule"
            ;;
    esac

    if [ "$task_state" != "due" ]; then
        printf 'TASK=%s SCHEDULE=%s STATE=%s\n' "$task_name" "$task_schedule" "$task_state"
        continue
    fi

    if is_deterministic "$task_name"; then
        if [ "$run_mode" = "report" ] || [ "$autonomy_level" -lt 1 ]; then
            printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=due\n' "$task_name" "$task_schedule"
            continue
        fi
        case "$task_name" in
            sync-ids)
                docs_count=$(run_sync_ids)
                sync_rc=$?
                if [ "$sync_rc" -eq 0 ]; then
                    record_task_result "$task_name" "ok"
                    printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=ran DOCS=%s\n' \
                        "$task_name" "$task_schedule" "$docs_count"
                    ran_count=$((ran_count + 1))
                else
                    record_task_result "$task_name" "error: sync-ids sweep failed"
                    printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=error\n' \
                        "$task_name" "$task_schedule"
                    issue_count=$((issue_count + 1))
                    overall_status="WARN"
                fi
                ;;
        esac
    else
        printf 'TASK=%s KIND=agent SCHEDULE=%s STATE=due REMEDIATION=/blueprint:%s\n' \
            "$task_name" "$task_schedule" "$task_name"
        if [ -z "$due_agent_tasks" ]; then
            due_agent_tasks="$task_name"
        else
            due_agent_tasks="${due_agent_tasks},${task_name}"
        fi
    fi
done < <(
    jq -r '(.task_registry // {}) | to_entries[] |
           [.key,
            (.value.enabled // false | tostring),
            (.value.auto_run // false | tostring),
            (.value.schedule // "on-demand"),
            (.value.last_completed_at // "null")] | @tsv' \
       "$manifest" 2>/dev/null
)

printf 'DUE_AGENT_TASKS=%s\n' "$due_agent_tasks"
printf 'RAN_COUNT=%s\n' "$ran_count"
finish "$overall_status" "$issue_count"
