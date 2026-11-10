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
#   on-change    : event-driven (PostToolUse hooks). An agent-judgment task is
#                  never runner-due. A DETERMINISTIC task is also reconciled on
#                  every run (STATE=reconcile): the on-change signal is
#                  best-effort — a Bash edit's change list can miss files, and
#                  edits by people or other tools fire no hook at all.
#                  Reconciling writes the manifest only when the result
#                  differs, so a clean tree stays clean.
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
#
# Works on a copy and replaces the manifest only when .id_registry differs:
# jq re-serialises the whole file, so an unconditional write would reformat a
# hand-edited manifest on every session start and leave the tree dirty.
#
# The body is a subshell ( ... ), not a brace group, so the cleanup traps
# below are scoped to the process that creates and owns the work copy and can
# never replace a trap in the calling shell. `$$` is the top-level script's
# PID even here (bash keeps $$ across subshells); it only names the file.
#
# Killed mid-sweep (the SessionStart probe's 5 s hook timeout does this on
# big repos, #3169), the EXIT/INT/TERM traps remove the work copy and its
# .tmp. The live manifest is only ever replaced by an atomic mv, so a kill
# leaves it either untouched or fully updated. SIGKILL cannot be trapped.
#
# Prints "<docs_seen> <changed:true|false>".
run_sync_ids() (
    local docs_seen=0
    local work="${manifest}.autorun.$$"

    # shellcheck disable=SC2329,SC2317  # invoked indirectly by the EXIT trap
    sync_ids_cleanup() { rm -f "$work" "${work}.tmp"; }
    trap sync_ids_cleanup EXIT
    # Exit with the conventional 128+signal status so the run still dies;
    # the EXIT trap then performs the cleanup.
    trap 'exit 130' INT
    trap 'exit 143' TERM

    cp "$manifest" "$work" || return 1

    if ! jq -e '.id_registry' "$work" >/dev/null 2>&1; then
        if ! { jq '. + {"id_registry": {"last_prd": 0, "last_prp": 0, "documents": {}, "github_issues": {}}}' \
                   "$work" > "${work}.tmp" && mv "${work}.tmp" "$work"; }; then
            rm -f "$work" "${work}.tmp"
            return 1
        fi
    fi

    # One awk pass over every document emits one row per document carrying an
    # id: path, id, status, title, created, separated by \037 (US) so tabs,
    # quotes and backslashes in values survive. One jq call then registers all
    # rows. The per-document loop this replaces forked awk, grep/sed/tr per
    # field and one jq read-modify-write per document; at 88 documents that
    # took 6.3 s, past the probe's 5 s hook budget (#3169).
    #
    # Per-document rules: the frontmatter is the lines between the first two
    # `---` lines, and only when the file's first line is `---` (as the
    # write-time hook requires); the first `<key>:` line wins, leading whitespace
    # stripped and CRs removed; an empty title falls back to the file's first
    # `# ` heading; a document without an id is skipped.
    local rows
    rows=$(find "${project_dir}/docs/prds" "${project_dir}/docs/adrs" "${project_dir}/docs/prps" \
                "${project_dir}/docs/blueprint/work-orders" \
                -maxdepth 1 -type f -name '*.md' -exec awk '
        function field(line, key,    v) {
            v = substr(line, length(key) + 2)
            sub(/^[[:space:]]+/, "", v)
            gsub(/\r/, "", v)
            return v
        }
        function emit() {
            if (doc != "" && id != "") {
                if (title == "") title = heading
                printf "%s\037%s\037%s\037%s\037%s\n", doc, id, status, title, created
            }
        }
        FNR == 1 {
            emit()
            doc = FILENAME; n = 0; id = status = title = created = heading = ""
            has_id = has_status = has_title = has_created = has_heading = 0
            # Frontmatter opens the file. A file whose first line is not
            # `---` has none, so a later `---` pair (a fenced format example
            # in an index README) is body text and is never read as fields.
            if ($0 != "---") n = 2
        }
        n < 2 && /^---$/ { n++; next }
        n == 1 {
            if (!has_id && /^id:/) { id = field($0, "id"); has_id = 1 }
            if (!has_status && /^status:/) { status = field($0, "status"); has_status = 1 }
            if (!has_title && /^title:/) { title = field($0, "title"); has_title = 1 }
            if (!has_created && /^created:/) { created = field($0, "created"); has_created = 1 }
        }
        !has_heading && /^# / { heading = substr($0, 3); gsub(/\r/, "", heading); has_heading = 1 }
        END { emit() }
    ' {} + 2>/dev/null)

    if [ -n "$rows" ]; then
        docs_seen=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
    fi

    if ! { printf '%s\n' "$rows" | jq -R -s \
             --arg pfx "${project_dir}/" \
             --arg now "$now_iso" \
             --slurpfile manifest_doc "$work" \
             'def or_default($d): if . == "" then $d else . end;
              def counter($prefix): ltrimstr($prefix) | tonumber? // 0;
              [split("\n")[] | select(length > 0) | split("\u001f")] as $rows
              | reduce $rows[] as $r ($manifest_doc[0];
                  ($r[1]) as $id
                  | .id_registry.documents[$id] =
                      ((.id_registry.documents[$id]
                        // {"created": ($r[4] | or_default($now)), "relates_to": [], "github_issues": []})
                       + {path: ($r[0] | ltrimstr($pfx)),
                          status: ($r[2] | or_default("unknown")),
                          title: ($r[3] | or_default("untitled"))})
                  | if ($id | startswith("PRD-")) then
                      .id_registry.last_prd = ([.id_registry.last_prd // 0, ($id | counter("PRD-"))] | max)
                    elif ($id | startswith("PRP-")) then
                      .id_registry.last_prp = ([.id_registry.last_prp // 0, ($id | counter("PRP-"))] | max)
                    else . end)' \
             > "${work}.tmp" && mv "${work}.tmp" "$work"; }; then
        rm -f "$work" "${work}.tmp"
        return 1
    fi

    local changed=true
    if [ "$(jq -S '.id_registry' "$work" 2>/dev/null)" = "$(jq -S '.id_registry' "$manifest" 2>/dev/null)" ]; then
        changed=false
        rm -f "$work"
    else
        mv "$work" "$manifest" || { rm -f "$work"; return 1; }
    fi

    printf '%s %s' "$docs_seen" "$changed"
    return 0
)

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
            if is_deterministic "$task_name"; then
                task_state="reconcile"
            else
                task_state="event_driven"
            fi
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

    if [ "$task_state" != "due" ] && [ "$task_state" != "reconcile" ]; then
        printf 'TASK=%s SCHEDULE=%s STATE=%s\n' "$task_name" "$task_schedule" "$task_state"
        continue
    fi

    if is_deterministic "$task_name"; then
        if [ "$run_mode" = "report" ] || [ "$autonomy_level" -lt 1 ]; then
            printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=%s\n' "$task_name" "$task_schedule" "$task_state"
            continue
        fi
        case "$task_name" in
            sync-ids)
                sync_out=$(run_sync_ids)
                sync_rc=$?
                docs_count=${sync_out%% *}
                sync_changed=${sync_out##* }
                if [ "$sync_rc" -eq 0 ]; then
                    # A reconcile that changed nothing leaves the manifest
                    # alone, last_completed_at included: it runs every session.
                    if [ "$task_state" = "due" ] || [ "$sync_changed" = "true" ]; then
                        record_task_result "$task_name" "ok"
                    fi
                    printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=ran DOCS=%s CHANGED=%s\n' \
                        "$task_name" "$task_schedule" "$docs_count" "$sync_changed"
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
