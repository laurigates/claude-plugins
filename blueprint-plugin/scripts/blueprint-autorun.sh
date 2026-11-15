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
#   daily/weekly : an agent-judgment task is due when last_completed_at is
#                  null/unparseable or older than the interval. A
#                  DETERMINISTIC task keeps no run state, so it reconciles on
#                  every run (STATE=reconcile), as for on-change.
#   on-change    : event-driven (PostToolUse hooks). An agent-judgment task is
#                  never runner-due. A DETERMINISTIC task is also reconciled on
#                  every run (STATE=reconcile): the on-change signal is
#                  best-effort — a Bash edit's change list can miss files, and
#                  edits by people or other tools fire no hook at all.
#   on-demand    : never due
#
# Nothing here writes task_registry (ADR-0027 Q3, #3548): the only manifest
# write is a reconcile that changed id_registry, so a clean tree stays clean.
#
# Execution is gated on automation.autonomy_level >= 1 (missing block = 0).
# --report computes due-ness only: no execution, no manifest write.
# BLUEPRINT_AUTORUN_DISABLE=1 makes the whole script a no-op.
#
# Output follows .claude/rules/structured-script-output.md.
# Exit 0 on OK/WARN, 1 on ERROR (parallel-safe).
#
# Usage: blueprint-autorun.sh [--project-dir DIR] [--report]
#        blueprint-autorun.sh --frontmatter-rows FILE...
#
# --frontmatter-rows is the one frontmatter parser the write-time hook
# (hooks/auto-sync-id-registry.sh), the session-start sweep (run_sync_ids) and
# the sync-ids audit share (ADR-0027 Q1, #3549). It prints one row per file and
# nothing else; see frontmatter_rows below for the row shape. Level 3 vendors
# this script as one file, so the parser lives here rather than in a library.

# set -u only (no -e/pipefail): this is a run-every-section collector — a
# single failing task must not abort the remaining tasks (see
# .claude/rules/shell-scripting.md "Error Handling Flags").
set -u

usage() {
    printf 'usage: blueprint-autorun.sh [--project-dir DIR] [--report]\n' >&2
    printf '       blueprint-autorun.sh --frontmatter-rows FILE...\n' >&2
}

# frontmatter_rows FILE... — print one row per file, fields separated by \037:
#   path, has_frontmatter (1|0), id, status, title, created, relates_to,
#   github_issues
# relates_to and github_issues are lists, items separated by \036.
#
# Semantics follow check-schema.py split_frontmatter plus the YAML scalar
# subset blueprint documents use, so the hook, the sweep and the audit cannot
# read one file three ways:
#   - CRs are stripped before every test;
#   - frontmatter exists only when line 1 is `---` and a later line closes it
#     (a fenced `---` example further down an index README is body text);
#   - the first top-level `key:` wins; `# comment` lines are skipped;
#   - an unquoted ` #` starts a comment; matching quotes are removed (`''`
#     inside single quotes is one quote, `\"` inside double quotes is a quote);
#     trailing whitespace is trimmed;
#   - a plain id, status, title or created value continues on more-indented
#     lines, each folded in with one space, until a ` #` comment, a list item
#     or a less-indented line; a blank line inside is skipped, not kept as
#     the newline YAML would fold it to;
#   - relates-to and github-issues are read as block (`- x`) or flow (`[x, y]`)
#     lists;
#   - an empty title falls back to the first `# ` heading of the body (outside
#     code fences), never to a line inside the frontmatter;
#   - a zero-byte file still gets its row: has_frontmatter 0, every other
#     field empty.
# Files are sorted with LC_ALL=C first, so the output order is the same on
# every machine.
frontmatter_rows() {
    [ $# -gt 0 ] || return 0
    local -a fm_files=()
    local fm_file
    while IFS= read -r -d '' fm_file; do
        fm_files+=("$fm_file")
    done < <(printf '%s\0' "$@" | LC_ALL=C sort -z)
    # SQ carries a single quote into the program: hex escapes are not POSIX awk.
    awk -v SQ="'" '
        function ltrim(s) { sub(/^[ \t]+/, "", s); return s }
        function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
        function trim(s) { return rtrim(ltrim(s)) }
        # Parse one YAML scalar (the text after `key:` or `- `). Sets SC_REST
        # to whatever follows a quoted scalar, for the flow-list reader.
        function scalar(s,    c, i, n, out, ch, nx) {
            s = ltrim(s)
            SC_REST = ""
            if (s == "") return ""
            c = substr(s, 1, 1)
            n = length(s)
            if (c == "\"") {
                out = ""
                for (i = 2; i <= n; i++) {
                    ch = substr(s, i, 1)
                    if (ch == "\\" && i < n) {
                        nx = substr(s, i + 1, 1)
                        if (nx == "t") out = out "\t"
                        else if (nx == "n") out = out " "
                        else out = out nx
                        i++
                    } else if (ch == "\"") {
                        SC_REST = substr(s, i + 1)
                        return out
                    } else out = out ch
                }
                return out
            }
            if (c == SQ) {
                out = ""
                for (i = 2; i <= n; i++) {
                    ch = substr(s, i, 1)
                    if (ch == SQ) {
                        if (substr(s, i + 1, 1) == SQ) { out = out SQ; i++; continue }
                        SC_REST = substr(s, i + 1)
                        return out
                    }
                    out = out ch
                }
                return out
            }
            if (c == "#") return ""
            if (match(s, /[ \t]#/)) s = substr(s, 1, RSTART - 1)
            return rtrim(s)
        }
        # Items of a flow list `[a, "b, c", d]`, joined with \036.
        function flow_list(s,    n, i, ch, q, item, out, items) {
            s = substr(ltrim(s), 2)
            n = length(s); q = ""; item = ""; out = ""; items = 0
            for (i = 1; i <= n; i++) {
                ch = substr(s, i, 1)
                if (q != "") {
                    item = item ch
                    if (ch == q) q = ""
                    continue
                }
                if (ch == "\"" || ch == SQ) { q = ch; item = item ch; continue }
                if (ch == "," || ch == "]") {
                    item = scalar(item)
                    if (item != "") { out = out (items++ ? "\036" : "") item }
                    item = ""
                    if (ch == "]") break
                    continue
                }
                item = item ch
            }
            return out
        }
        function list_value(s,    v) {
            s = ltrim(s)
            if (substr(s, 1, 1) == "[") return flow_list(s)
            return scalar(s)
        }
        function set_field(key, v) {
            if (key == "id") id = v
            else if (key == "status") status = v
            else if (key == "title") title = v
            else if (key == "created") created = v
        }
        # Whether the value after `key:` is a plain scalar a following
        # indented line may continue: empty, or opening with a comment, or
        # unquoted text that no ` #` comment has already ended.
        function plain_open(s,    c) {
            s = ltrim(s)
            if (s == "") return 1
            c = substr(s, 1, 1)
            if (c == "#") return 1
            if (index("\"" SQ "[{|>&*!", c)) return 0
            return !match(s, /[ \t]#/)
        }
        function add_item(key, v) {
            if (v == "") return
            if (key == "relates-to") rel = rel (rel == "" ? "" : "\036") v
            else gh = gh (gh == "" ? "" : "\036") v
        }
        function emit(    t) {
            if (doc == "") return
            if (state != 2) {
                # Line 1 opened frontmatter but nothing closed it: no
                # frontmatter (split_frontmatter returns None), the whole
                # file is body.
                has_fm = 0; id = status = title = created = rel = gh = ""
                body_heading = any_heading
            }
            t = title
            if (t == "") t = body_heading
            gsub(/[\036\037\n]/, " ", t)
            printf "%s\037%d\037%s\037%s\037%s\037%s\037%s\037%s\n", \
                doc, has_fm, id, status, t, created, rel, gh
        }
        # any_heading: first heading of the whole file (the fallback when an
        # opened frontmatter never closes); body_heading: first heading after
        # the frontmatter. Each tracks its own fence state.
        function heading_scan(line) {
            if (line ~ /^[ \t]*(```|~~~)/) {
                any_fence = !any_fence
                if (state == 2) in_fence = !in_fence
                return
            }
            if (line !~ /^# /) return
            if (!any_fence && any_heading == "") any_heading = trim(substr(line, 3))
            if (state == 2 && !in_fence && body_heading == "") body_heading = trim(substr(line, 3))
        }
        # A zero-byte file has no FNR == 1 record, so awk never visits it.
        # Walk ARGV alongside the input and print an empty row for each file
        # skipped that way, keeping one row per file in argument order.
        function emit_empty_until(f) {
            while (argi < ARGC && ARGV[argi] != f) {
                printf "%s\0370\037\037\037\037\037\037\n", ARGV[argi]
                argi++
            }
            argi++
        }
        BEGIN { argi = 1 }
        FNR == 1 {
            emit()
            emit_empty_until(FILENAME)
            doc = FILENAME
            has_fm = 0; state = 2; in_fence = any_fence = 0; inlist = ""; cont = ""
            id = status = title = created = rel = gh = ""
            body_heading = any_heading = ""
            split("", seen)
            line = $0; gsub(/\r/, "", line)
            if (trim(line) == "---") { has_fm = 1; state = 1; next }
            heading_scan(line)
            next
        }
        {
            line = $0
            gsub(/\r/, "", line)
            if (state == 1) {
                heading_scan(line)
                if (trim(line) == "---") { state = 2; inlist = ""; cont = ""; next }
                # A more-indented line continues the plain scalar of the
                # last scalar key; YAML folds the line break to one space.
                # A ` #` comment ends it; a blank line keeps it open (YAML
                # folds that to a newline, which a row cannot carry).
                if (cont != "") {
                    if (line ~ /^[ \t]+[^ \t]/ && ltrim(line) !~ /^(#|-([ \t]|$))/) {
                        v = ltrim(line)
                        stop = match(v, /[ \t]#/)
                        if (stop) v = substr(v, 1, RSTART - 1)
                        v = rtrim(v)
                        cval = (cval == "" ? v : cval " " v)
                        set_field(cont, cval)
                        if (stop) cont = ""
                        next
                    }
                    if (line ~ /^[ \t]*$/) next
                    cont = ""
                }
                if (inlist != "") {
                    if (line ~ /^[ \t]*-([ \t]|$)/) {
                        v = line; sub(/^[ \t]*-/, "", v)
                        add_item(inlist, scalar(v))
                        next
                    }
                    if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
                    inlist = ""
                }
                if (line ~ /^[ \t]*#/) next
                if (line !~ /^[A-Za-z_][A-Za-z0-9_-]*:([ \t]|$)/) next
                key = line; sub(/:.*/, "", key)
                rest = substr(line, length(key) + 2)
                if (key in seen) next
                seen[key] = 1
                if (key == "id" || key == "status" || key == "title" || key == "created") {
                    cval = scalar(rest)
                    set_field(key, cval)
                    if (plain_open(rest)) cont = key
                }
                else if (key == "relates-to" || key == "github-issues") {
                    v = ltrim(rest)
                    if (v == "" || substr(v, 1, 1) == "#") inlist = key
                    else if (substr(v, 1, 1) == "[") {
                        if (key == "relates-to") rel = flow_list(v)
                        else gh = flow_list(v)
                    } else add_item(key, scalar(v))
                }
                next
            }
            heading_scan(line)
        }
        END { emit(); emit_empty_until("") }
    ' "${fm_files[@]}"
}

if [ "${1:-}" = "--frontmatter-rows" ]; then
    shift
    frontmatter_rows "$@"
    exit $?
fi

project_dir="."
run_mode="apply"

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)
            if [ $# -lt 2 ]; then
                usage
                exit 2
            fi
            project_dir="$2"
            shift 2
            ;;
        --report)
            run_mode="report"
            shift
            ;;
        *)
            printf 'blueprint-autorun.sh: unknown argument: %s\n' "$1" >&2
            usage
            exit 2
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

    # One frontmatter_rows pass (one awk process) reads every document; one jq
    # call then registers every row carrying an id. The per-document loop this
    # replaced forked awk, grep/sed/tr per field and one jq read-modify-write
    # per document; at 88 documents that took 6.3 s, past the probe's 5 s hook
    # budget (#3169). Row fields: see frontmatter_rows.
    local rows
    local -a scan_files=()
    local scan_file
    while IFS= read -r -d '' scan_file; do
        scan_files+=("$scan_file")
    done < <(find "${project_dir}/docs/prds" "${project_dir}/docs/adrs" "${project_dir}/docs/prps" \
                  "${project_dir}/docs/blueprint/work-orders" \
                  -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
    rows=$(frontmatter_rows "${scan_files[@]}" | awk -F'\037' '$3 != ""')

    if [ -n "$rows" ]; then
        docs_seen=$(printf '%s\n' "$rows" | wc -l | tr -d ' ')
    elif ! jq -e '.id_registry' "$work" >/dev/null 2>&1; then
        # No document carries an id and there is no registry: creating an
        # empty one would dirty every fresh clone of such a consumer (#3548).
        rm -f "$work"
        printf '0 false'
        return 0
    fi

    if ! jq -e '.id_registry' "$work" >/dev/null 2>&1; then
        if ! { jq '. + {"id_registry": {"last_prd": 0, "last_prp": 0, "documents": {}, "github_issues": {}}}' \
                   "$work" > "${work}.tmp" && mv "${work}.tmp" "$work"; }; then
            rm -f "$work" "${work}.tmp"
            return 1
        fi
    fi

    if ! { printf '%s\n' "$rows" | jq -R -s \
             --arg pfx "${project_dir}/" \
             --arg now "$now_iso" \
             --slurpfile manifest_doc "$work" \
             'def or_default($d): if . == "" then $d else . end;
              def counter($prefix): ltrimstr($prefix) | tonumber? // 0;
              [split("\n")[] | select(length > 0) | split("\u001f")] as $rows
              | reduce $rows[] as $r ($manifest_doc[0];
                  ($r[2]) as $id
                  | .id_registry.documents[$id] =
                      ((.id_registry.documents[$id]
                        // {"created": ($r[5] | or_default($now)), "relates_to": [], "github_issues": []})
                       + {path: ($r[0] | ltrimstr($pfx)),
                          status: ($r[3] | or_default("unknown")),
                          title: ($r[4] | or_default("untitled"))})
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

# Run state is never written here (ADR-0027 Q3, #3548). A deterministic task
# keeps none: the tracked manifest changes only when id_registry does, so a
# session start on a clean tree leaves it clean. An agent-judgment task's
# last_completed_at/last_result are written only after an explicit run (the
# skill itself, or /blueprint:autopilot after running it).
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
            # A deterministic task keeps no last_completed_at to measure an
            # interval from, so it reconciles on every run like on-change.
            if is_deterministic "$task_name"; then
                task_state="reconcile"
            else
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
                    printf 'TASK=%s KIND=deterministic SCHEDULE=%s STATE=ran DOCS=%s CHANGED=%s\n' \
                        "$task_name" "$task_schedule" "$docs_count" "$sync_changed"
                    ran_count=$((ran_count + 1))
                else
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
