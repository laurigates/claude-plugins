#!/usr/bin/env bash
# blueprint-tracker-check.sh — deterministic feature-tracker integrity check (issue #2128).
#
# The verification counterpart to the sync WRITE path: #1354 fixed sync writing
# wrong statuses, but nothing detected disagreement afterwards, so a tracker
# that drifted by any other route stayed wrong indefinitely. Dogfooding blueprint
# on a C/SDL2 port surfaced five mechanical defects that had accumulated for
# ~3 months, none caught by any existing check.
#
# Checks (all deterministic; none is a project opinion):
#   1. statistics_divergence     `statistics` is a CACHE of the features
#                                collection. Recomputed here and compared
#                                per field, so a stale "68% complete" that
#                                every downstream reader quotes turns red. ERROR
#   2. feature_status_*          A feature status outside the schema enum.
#                                In the tolerated union -> WARN naming the
#                                canonical spelling; outside it -> ERROR.
#   3. task_feature_disagreement `features` status vs `tasks.{pending,
#                                in_progress,completed}[]` membership.        WARN
#   4. fr_cited_not_minted       An FR id cited across docs/** (or inside the
#                                tracker's own evidence strings) that the
#                                features collection never minted, so it is
#                                invisible to every status query.            WARN
#   5. doc_status_stale          Doc frontmatter `status:` still unfinished
#                                while every FR it cites has landed.         WARN
#   6. dead_statistics_bucket    A `statistics` key naming no schema bucket.  WARN
#      duplicate_timestamp_field Two fields for one fact (`last_updated` is
#                                canonical). ERROR when they disagree.
#
# ── THE FALSE POSITIVE THIS SCRIPT EXISTS TO NOT MAKE ─────────────────────────
#
# From the issue, verbatim: "My first version walked the whole JSON tree for
# id-bearing objects and reported 7 false 'duplicate records' — .tasks.pending[]
# / .tasks.completed[] legitimately repeat an FR id already in .features[], which
# is the documented drain design. Status must be read from .features[] only, with
# the task lists checked separately for *agreement*."
#
# So: status is read from the FEATURES COLLECTION ONLY (see `recs` in the jq
# program below — it never descends into `.tasks`), and an FR id appearing in
# BOTH the features collection and a task list is never a duplicate. There is
# deliberately no duplicate-record check in this script at all. The regression
# test pins this negative case, because it is the one mistake guaranteed to
# recur.
#
# ── TWO SHAPES OF `features` ──────────────────────────────────────────────────
#
# schemas/feature-tracker.schema.json declares `features` as an OBJECT keyed by
# FR id (patternProperties `^FR\d+$`), each an FR category holding a nested
# `features` object of FR sub-features. Real trackers in the wild (and
# blueprint-feature-tracker-sync.sh's own rollup) also use a flat ARRAY of
# records carrying `id` + `status`. Both are handled and the resolved shape is
# reported as FEATURES_SHAPE=object|array|absent.
#
# A "feature record" is any object inside the features collection that carries a
# `status` field. In the object shape, an FR *category* with no `status` of its
# own is therefore not counted; its status-bearing sub-features are.
#
# ── STATUS VOCABULARY BOUNDARY ────────────────────────────────────────────────
#
# The FEATURE status enum is a plugin-owned schema invariant and is read from
# get-validation-config.sh's CANONICAL_FEATURE_STATUSES (never from the
# manifest). `status_vocabulary` governs DOCUMENT FRONTMATTER statuses (check 5)
# — a repo convention. Per that script's documented concession, feature-status
# drift consults CANONICAL u STATUS_DONE u STATUS_UNFINISHED as an additional
# TOLERATED set: inside it -> WARN naming the canonical spelling, outside it ->
# ERROR.
#
# ── OUTPUT ────────────────────────────────────────────────────────────────────
#
# Structured KEY=VALUE per .claude/rules/structured-script-output.md. Exit 0 on
# OK/WARN, 1 on ERROR (parallel-safe per .claude/rules/parallel-safe-queries.md);
# exit 2 only on a caller error (unknown argument — the #2057 lesson: a silently
# swallowed flag is worse than a loud rejection).
#
# A repo with NO feature tracker is the common case (most repos have none) and
# degrades to STATUS=OK / ISSUE_COUNT=0 / exit 0. Absent jq likewise reports
# CHECKED=false and exits 0 rather than blocking.
#
# `set -u` only (not `set -euo pipefail`), matching get-automation-config.sh and
# get-validation-config.sh: this is a multi-section collector whose every section
# must be reached, and a `producer | head` SIGPIPE under pipefail would abort the
# run mid-way (.claude/rules/shell-scripting.md).
#
# Usage: blueprint-tracker-check.sh [--project-dir DIR] [--tracker PATH]

set -u

SECTION="BLUEPRINT TRACKER INTEGRITY"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    printf 'Usage: blueprint-tracker-check.sh [--project-dir DIR] [--tracker PATH]\n'
}

project_dir="$(pwd)"
tracker=""

while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)   project_dir="${2:-.}"; shift 2 ;;
        --project-dir=*) project_dir="${1#*=}"; shift ;;
        --tracker)       tracker="${2:-}"; shift 2 ;;
        --tracker=*)     tracker="${1#*=}"; shift ;;
        -h|--help)       usage; exit 0 ;;
        *)
            printf 'blueprint-tracker-check.sh: unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

[ -n "$tracker" ] || tracker="${project_dir}/docs/blueprint/feature-tracker.json"

emit() { printf '%s\n' "$1"; }

issues=""
issue_count=0
has_error=0

# add_issue SEVERITY TYPE EXTRA_TOKENS MSG
#   EXTRA_TOKENS may be empty; when set it is inserted verbatim before MSG=
#   (the health-check `HOOK=... MSG=...` shape).
add_issue() {
    local ai_extra="$3"
    issues="${issues}  - SEVERITY=$1 TYPE=$2 ${ai_extra:+$ai_extra }MSG=$4"$'\n'
    issue_count=$((issue_count + 1))
    [ "$1" = "ERROR" ] && has_error=1
    return 0
}

finish() {
    local f_status
    if [ "$has_error" -eq 1 ]; then
        f_status="ERROR"
    elif [ "$issue_count" -gt 0 ]; then
        f_status="WARN"
    else
        f_status="OK"
    fi
    emit "STATUS=${f_status}"
    emit "ISSUE_COUNT=${issue_count}"
    if [ "$issue_count" -gt 0 ]; then
        emit "ISSUES:"
        printf '%s' "$issues"
    fi
    emit "=== END ${SECTION} ==="
    [ "$has_error" -eq 1 ] && exit 1
    exit 0
}

# in_list NEEDLE [HAYSTACK...] — case-sensitive membership.
in_list() {
    local il_needle="$1"; shift
    local il_e
    for il_e in "$@"; do
        [ "$il_e" = "$il_needle" ] && return 0
    done
    return 1
}

# lc VALUE — lowercase.
lc() { printf '%s' "${1,,}"; }

# squash VALUE — lowercase with `-`, `_` and spaces removed, for near-miss
# matching (`in-progress` / `In Progress` -> `inprogress`).
squash() {
    local s_v
    s_v="$(lc "$1")"
    s_v="${s_v//-/}"
    s_v="${s_v//_/}"
    s_v="${s_v// /}"
    printf '%s' "$s_v"
}

emit "=== ${SECTION} ==="

# ── Shared config (issue #2129's reader; consumed, never re-implemented) ───────
cfg=""
if [ -f "${SCRIPT_DIR}/get-validation-config.sh" ]; then
    cfg="$(bash "${SCRIPT_DIR}/get-validation-config.sh" --project-dir "$project_dir")"
fi

cfg_key() { # KEY -> raw value (may contain TABs)
    local ck_line
    ck_line="$(printf '%s\n' "$cfg" | grep -m1 "^$1=")"
    printf '%s' "${ck_line#"$1"=}"
}

declare -a cfg_status_done=() cfg_status_unfinished=() cfg_exclude=() cfg_doc_globs=() cfg_canonical=()
IFS=$'\t' read -r -a cfg_status_done      <<<"$(cfg_key STATUS_DONE)"
IFS=$'\t' read -r -a cfg_status_unfinished <<<"$(cfg_key STATUS_UNFINISHED)"
IFS=$'\t' read -r -a cfg_exclude          <<<"$(cfg_key EXCLUDE_BASENAMES)"
IFS=$'\t' read -r -a cfg_doc_globs        <<<"$(cfg_key DOC_GLOBS)"
IFS=$'\t' read -r -a cfg_canonical        <<<"$(cfg_key CANONICAL_FEATURE_STATUSES)"
cfg_source="$(cfg_key SOURCE)"

# The reader emits every key on EVERY run, so an empty value from a successful
# read is a deliberate empty configuration (`"exclude_basenames": []`) and must be
# honoured as such. These fallbacks therefore fire only when the reader itself
# could not run — without them a check would silently no-op (an empty enum flags
# nothing; empty doc globs skip check 5 entirely), which is worse than degrading
# to the reader's documented defaults.
if [ -z "$cfg" ]; then
    cfg_canonical=(not_started in_progress partial complete blocked)
    cfg_status_unfinished=(draft proposed ready in_progress)
    cfg_status_done=(complete)
    cfg_doc_globs=('docs/prds/*.md' 'docs/prps/*.md' 'docs/adrs/*.md')
    cfg_exclude=(README.md)
fi

emit "CONFIG_SOURCE=${cfg_source:-none}"

# The tolerated union (lowercased) from the documented concession.
declare -a tolerated=()
for _t in "${cfg_canonical[@]}" "${cfg_status_done[@]}" "${cfg_status_unfinished[@]}"; do
    [ -n "$_t" ] || continue
    tolerated+=("$(lc "$_t")")
done

tracker_rel="${tracker#"${project_dir}"/}"
emit "TRACKER=${tracker_rel}"

if [ ! -f "$tracker" ]; then
    # Most repos have no feature tracker at all. Not a defect.
    emit "TRACKER_PRESENT=false"
    emit "CHECKED=false"
    finish
fi
emit "TRACKER_PRESENT=true"

if ! command -v jq >/dev/null 2>&1; then
    emit "JQ_AVAILABLE=false"
    emit "CHECKED=false"
    finish
fi
emit "JQ_AVAILABLE=true"

if ! jq empty "$tracker" >/dev/null 2>&1; then
    emit "CHECKED=false"
    add_issue ERROR invalid_json "" "feature-tracker.json is not valid JSON"
    finish
fi
emit "CHECKED=true"

# ── Normalize the features collection ─────────────────────────────────────────
#
# `recs` reads ONLY the features collection — never `.tasks` (see the
# false-positive note in the header).
JQ_RECS='
def objrecs:
  to_entries[]
  | select((.value | type) == "object")
  | ( (if (.value | has("status")) then {id: .key, status: (.value.status | tostring)} else empty end),
      (if ((.value.features // null) | type) == "object" then (.value.features | objrecs) else empty end) );

def recs:
  (.features // null) as $f
  | if ($f | type) == "array" then
      [ $f[]
        | select(type == "object")
        | select(has("status"))
        | {id: ((.id // .code // .name // "?") | tostring), status: (.status | tostring)} ]
    elif ($f | type) == "object" then [ $f | objrecs ]
    else [] end;

recs[] | [.id, .status] | @tsv
'

# Every id/key the features collection MENTIONS, status-bearing or not. In the
# object shape an FR *category* (`FR1`) carries no `status` of its own, so it is
# not a feature record — but it IS minted, and check 4 must not report a doc
# citing it as "absent from the features collection".
JQ_IDS='
def objids:
  to_entries[]
  | select((.value | type) == "object")
  | ( .key,
      (if ((.value.features // null) | type) == "object" then (.value.features | objids) else empty end) );

(.features // null) as $f
| if ($f | type) == "array" then
    ($f[] | select(type == "object") | ((.id // .code // .name // empty) | tostring))
  elif ($f | type) == "object" then ($f | objids)
  else empty end
'

features_shape="$(jq -r '(.features // null) | type' "$tracker" 2>/dev/null)"
case "$features_shape" in
    array|object) : ;;
    *) features_shape="absent" ;;
esac
emit "FEATURES_SHAPE=${features_shape}"

recs_file="$(mktemp)" || { emit "CHECKED=false"; finish; }
[ -n "$recs_file" ] || { emit "CHECKED=false"; finish; }
trap 'rm -f "$recs_file"' EXIT
jq -r "$JQ_RECS" "$tracker" 2>/dev/null > "$recs_file"

# norm_fr TOKEN -> canonical FR key (`FR-025` / `fr_25` / ` FR 25` -> `FR25`),
# or empty when the token is not an FR reference.
norm_fr() {
    printf '%s' "$1" \
        | sed -nE 's/^[^0-9A-Za-z]?[Ff][Rr][-_ ]?0*([0-9]+)((\.[0-9]+)*)$/FR\1\2/p'
}

declare -A fr_status_by_key=()   # normalized (or raw) id -> raw status
declare -A fr_canon_by_key=()    # normalized (or raw) id -> canonical status ("" = unresolved)
declare -A fr_label_by_key=()    # normalized (or raw) id -> id as written
declare -A fr_present_by_key=()  # every minted id/key, status-bearing or not
declare -A stat_count=()
for _c in "${cfg_canonical[@]}"; do stat_count["$_c"]=0; done

record_count=0
enum_drift=0

# canon_of STATUS -> the canonical spelling it most plausibly means, or "".
canon_of() {
    local co_raw="$1" co_sq co_c co_csq
    if in_list "$co_raw" "${cfg_canonical[@]}"; then
        printf '%s' "$co_raw"; return 0
    fi
    co_sq="$(squash "$co_raw")"
    for co_c in "${cfg_canonical[@]}"; do
        co_csq="$(squash "$co_c")"
        if [ "$co_sq" = "$co_csq" ]; then printf '%s' "$co_c"; return 0; fi
    done
    for co_c in "${cfg_canonical[@]}"; do
        co_csq="$(squash "$co_c")"
        case "$co_sq" in
            "$co_csq"*) printf '%s' "$co_c"; return 0 ;;
        esac
        case "$co_csq" in
            "$co_sq"*) printf '%s' "$co_c"; return 0 ;;
        esac
    done
    return 0
}

while IFS= read -r minted_id; do
    [ -n "$minted_id" ] || continue
    minted_key="$(norm_fr "$minted_id")"
    [ -n "$minted_key" ] || minted_key="$minted_id"
    fr_present_by_key["$minted_key"]=1
done < <(jq -r "$JQ_IDS" "$tracker" 2>/dev/null)

while IFS=$'\t' read -r rec_id rec_status; do
    [ -n "${rec_id:-}" ] || continue
    record_count=$((record_count + 1))
    rec_key="$(norm_fr "$rec_id")"
    [ -n "$rec_key" ] || rec_key="$rec_id"
    fr_present_by_key["$rec_key"]=1
    fr_status_by_key["$rec_key"]="$rec_status"
    fr_label_by_key["$rec_key"]="$rec_id"

    rec_canon="$(canon_of "$rec_status")"
    fr_canon_by_key["$rec_key"]="$rec_canon"

    if in_list "$rec_status" "${cfg_canonical[@]}"; then
        stat_count["$rec_status"]=$(( ${stat_count["$rec_status"]} + 1 ))
    else
        enum_drift=$((enum_drift + 1))
        if in_list "$(lc "$rec_status")" "${tolerated[@]}"; then
            if [ -n "$rec_canon" ]; then
                add_issue WARN feature_status_near_miss \
                    "FR=${rec_id} FOUND=${rec_status} CANONICAL=${rec_canon}" \
                    "feature status '${rec_status}' is not the schema spelling; use '${rec_canon}'"
            else
                add_issue WARN feature_status_near_miss \
                    "FR=${rec_id} FOUND=${rec_status}" \
                    "feature status '${rec_status}' is in the configured status_vocabulary but not the schema enum"
            fi
        else
            add_issue ERROR feature_status_unknown \
                "FR=${rec_id} FOUND=${rec_status}" \
                "feature status '${rec_status}' is in neither the schema enum nor the configured status_vocabulary"
        fi
        # A resolved near-miss still counts toward its canonical bucket, so the
        # recomputed statistics reflect intent rather than double-punishing the
        # same drift twice.
        if [ -n "$rec_canon" ]; then
            stat_count["$rec_canon"]=$(( ${stat_count["$rec_canon"]} + 1 ))
        fi
    fi
done < "$recs_file"

emit "FEATURE_RECORD_COUNT=${record_count}"
emit "STATUS_ENUM_DRIFT_COUNT=${enum_drift}"

# ── Check 1: recompute `statistics` and diff it per field ─────────────────────
exp_total="$record_count"
exp_complete="${stat_count[complete]:-0}"
exp_partial="${stat_count[partial]:-0}"
exp_in_progress="${stat_count[in_progress]:-0}"
exp_not_started="${stat_count[not_started]:-0}"
exp_blocked="${stat_count[blocked]:-0}"

# Same formula blueprint-feature-tracker-sync.sh uses: complete/total to one
# decimal place. Keeping them identical is the point — a divergence report is
# worthless if the checker and the writer disagree on the arithmetic.
exp_pct=0
if [ "$exp_total" -gt 0 ]; then
    exp_pct="$(jq -n --argjson c "$exp_complete" --argjson t "$exp_total" '(($c / $t) * 1000 | round) / 10')"
fi

emit "EXPECTED_TOTAL_FEATURES=${exp_total}"
emit "EXPECTED_COMPLETE=${exp_complete}"
emit "EXPECTED_PARTIAL=${exp_partial}"
emit "EXPECTED_IN_PROGRESS=${exp_in_progress}"
emit "EXPECTED_NOT_STARTED=${exp_not_started}"
emit "EXPECTED_BLOCKED=${exp_blocked}"
emit "EXPECTED_COMPLETION_PERCENTAGE=${exp_pct}"
emit "COMPLETION_FORMULA=round(complete/total_features*1000)/10"

stats_present=false
if jq -e '(.statistics | type) == "object"' "$tracker" >/dev/null 2>&1; then
    stats_present=true
fi
emit "STATISTICS_PRESENT=${stats_present}"

divergence_count=0
if [ "$stats_present" = true ]; then
    for field in total_features complete partial in_progress not_started blocked completion_percentage; do
        case "$field" in
            total_features)        expected="$exp_total" ;;
            complete)              expected="$exp_complete" ;;
            partial)               expected="$exp_partial" ;;
            in_progress)           expected="$exp_in_progress" ;;
            not_started)           expected="$exp_not_started" ;;
            blocked)               expected="$exp_blocked" ;;
            completion_percentage) expected="$exp_pct" ;;
        esac

        actual="$(jq -r --arg f "$field" '.statistics[$f] | if . == null then "absent" else tostring end' "$tracker" 2>/dev/null)"
        emit "ACTUAL_$(printf '%s' "$field" | tr '[:lower:]' '[:upper:]')=${actual}"

        if [ "$actual" = "absent" ]; then
            add_issue WARN statistics_field_missing \
                "FIELD=${field} EXPECTED=${expected}" \
                "statistics has no '${field}' bucket; expected ${expected}"
            continue
        fi

        same=false
        if [ "$field" = "completion_percentage" ]; then
            # Numeric compare with a 0.05 tolerance so 68 and 68.0 agree.
            pct_same="$(jq -n --argjson a "$actual" --argjson e "$expected" \
                'if (($a - $e) < 0) then ($e - $a) else ($a - $e) end < 0.05' 2>/dev/null)"
            [ "$pct_same" = "true" ] && same=true
        elif [ "$actual" = "$expected" ]; then
            same=true
        fi

        if [ "$same" != true ]; then
            divergence_count=$((divergence_count + 1))
            add_issue ERROR statistics_divergence \
                "FIELD=${field} EXPECTED=${expected} ACTUAL=${actual}" \
                "statistics.${field} is a stale cache of the features collection"
        fi
    done
fi
emit "STATISTICS_DIVERGENCE_COUNT=${divergence_count}"

# ── Check 6a: dead / non-schema statistics buckets ───────────────────────────
# `partial` IS a schema bucket and is never flagged. `pending` is the dead one.
dead_bucket_count=0
if [ "$stats_present" = true ]; then
    while IFS= read -r bucket; do
        [ -n "$bucket" ] || continue
        case "$bucket" in
            total_features|complete|partial|in_progress|not_started|blocked|completion_percentage) continue ;;
        esac
        dead_bucket_count=$((dead_bucket_count + 1))
        add_issue WARN dead_statistics_bucket "BUCKET=${bucket}" \
            "statistics.${bucket} names no schema bucket; the schema buckets are total_features, complete, partial, in_progress, not_started, blocked, completion_percentage"
    done < <(jq -r '.statistics | keys[]' "$tracker" 2>/dev/null)
fi
emit "DEAD_BUCKET_COUNT=${dead_bucket_count}"

# ── Check 6b: two timestamp fields for one fact ──────────────────────────────
# The canonical schema field is `last_updated`.
declare -a ts_present=() ts_values=()
for ts_field in last_updated updated_at last_update lastUpdated updated; do
    ts_val="$(jq -r --arg f "$ts_field" '.[$f] // empty | tostring' "$tracker" 2>/dev/null)"
    [ -n "$ts_val" ] || continue
    ts_present+=("$ts_field")
    ts_values+=("$ts_val")
done
emit "TIMESTAMP_FIELD_COUNT=${#ts_present[@]}"
if [ "${#ts_present[@]}" -gt 0 ]; then
    emit "TIMESTAMP_FIELDS=$(IFS=,; printf '%s' "${ts_present[*]}")"
fi
if [ "${#ts_present[@]}" -gt 1 ]; then
    ts_disagree=false
    for _i in "${!ts_values[@]}"; do
        [ "${ts_values[$_i]}" = "${ts_values[0]}" ] || ts_disagree=true
    done
    ts_detail=""
    for _i in "${!ts_present[@]}"; do
        ts_detail="${ts_detail}${ts_detail:+, }${ts_present[$_i]}=${ts_values[$_i]}"
    done
    if [ "$ts_disagree" = true ]; then
        add_issue ERROR duplicate_timestamp_field \
            "FIELDS=$(IFS=,; printf '%s' "${ts_present[*]}") CANONICAL=last_updated" \
            "two timestamp fields for one fact and they disagree (${ts_detail}); the schema field is last_updated"
    else
        add_issue WARN duplicate_timestamp_field \
            "FIELDS=$(IFS=,; printf '%s' "${ts_present[*]}") CANONICAL=last_updated" \
            "two timestamp fields for one fact (${ts_detail}); the schema field is last_updated"
    fi
fi

# ── Check 3: features status vs task-list membership (AGREEMENT, not dupes) ───
#
# An FR id in both the features collection and a task list is the documented
# drain design, NOT a duplicate. Only a genuine contradiction is reported.
task_disagreement=0
while IFS=$'\t' read -r task_list task_id; do
    [ -n "${task_id:-}" ] || continue
    task_key="$(norm_fr "$task_id")"
    [ -n "$task_key" ] || task_key="$task_id"
    # Only FR ids present in the features collection can disagree with it; a
    # WO-NNN or custom task id has no feature status to contradict.
    [ -n "${fr_status_by_key[$task_key]+x}" ] || continue
    fr_canon="${fr_canon_by_key[$task_key]}"
    fr_raw="${fr_status_by_key[$task_key]}"
    case "$task_list" in
        completed)
            if [ "$fr_canon" != "complete" ]; then
                task_disagreement=$((task_disagreement + 1))
                add_issue WARN task_feature_disagreement \
                    "FR=${task_id} TASK_LIST=completed FEATURE_STATUS=${fr_raw}" \
                    "tasks.completed carries ${task_id} but its feature status is '${fr_raw}'"
            fi
            ;;
        pending|in_progress)
            if [ "$fr_canon" = "complete" ]; then
                task_disagreement=$((task_disagreement + 1))
                add_issue WARN task_feature_disagreement \
                    "FR=${task_id} TASK_LIST=${task_list} FEATURE_STATUS=${fr_raw}" \
                    "tasks.${task_list} still carries ${task_id} but its feature status is '${fr_raw}'"
            fi
            ;;
    esac
done < <(jq -r '
    (.tasks // {}) as $t
    | ["pending", "in_progress", "completed"][]
    | . as $list
    | (($t[$list] // []) | if type == "array" then .[] else empty end)
    | select(type == "object")
    | [$list, ((.id // "") | tostring)]
    | @tsv
' "$tracker" 2>/dev/null)
emit "TASK_DISAGREEMENT_COUNT=${task_disagreement}"

# ── Doc sweep helpers ────────────────────────────────────────────────────────
is_excluded_basename() {
    local ib_base
    ib_base="$(basename "$1")"
    in_list "$ib_base" "${cfg_exclude[@]}"
}

# fr_keys_in_file FILE -> unique normalized FR keys cited in the file.
fr_keys_in_file() {
    grep -oE '(^|[^A-Za-z0-9])[Ff][Rr][-_ ]?[0-9]+(\.[0-9]+)*' "$1" 2>/dev/null \
        | sed -nE 's/^[^0-9A-Za-z]?[Ff][Rr][-_ ]?0*([0-9]+)((\.[0-9]+)*)$/FR\1\2/p' \
        | sort -u
}

# expand_glob PATTERN — pathname expansion that survives spaces in the pattern
# (config list elements may legitimately contain a space).
expand_glob() {
    local eg_pat="$1" eg_f eg_old_ifs="${IFS}"
    IFS=''
    for eg_f in $eg_pat; do
        [ -e "$eg_f" ] && printf '%s\n' "$eg_f"
    done
    IFS="$eg_old_ifs"
}

# ── Check 4: FR ids cited across docs/** but never minted ────────────────────
#
# The tracker itself is swept too: the reported FR-025 defect was cited inside
# another feature's own `evidence` string, which is exactly the kind of citation
# that keeps an unminted FR looking real.
declare -A cited_missing_files=()
declare -A cited_missing_count=()
docs_root="${project_dir}/docs"

sweep_file_for_citations() {
    local sf_file="$1" sf_key
    while IFS= read -r sf_key; do
        [ -n "$sf_key" ] || continue
        [ -n "${fr_present_by_key[$sf_key]+x}" ] && continue
        cited_missing_count["$sf_key"]=$(( ${cited_missing_count["$sf_key"]:-0} + 1 ))
        if [ -z "${cited_missing_files[$sf_key]:-}" ]; then
            cited_missing_files["$sf_key"]="${sf_file#"${project_dir}"/}"
        fi
    done < <(fr_keys_in_file "$sf_file")
}

if [ -d "$docs_root" ]; then
    while IFS= read -r doc_file; do
        [ -n "$doc_file" ] || continue
        is_excluded_basename "$doc_file" && continue
        sweep_file_for_citations "$doc_file"
    done < <(find "$docs_root" -type f -name '*.md' 2>/dev/null)
fi
sweep_file_for_citations "$tracker"

cited_not_minted=0
for miss_key in "${!cited_missing_count[@]}"; do
    cited_not_minted=$((cited_not_minted + 1))
    add_issue WARN fr_cited_not_minted \
        "FR=${miss_key} CITATIONS=${cited_missing_count[$miss_key]} EXAMPLE=${cited_missing_files[$miss_key]}" \
        "${miss_key} is cited by ${cited_missing_count[$miss_key]} file(s) but absent from the features collection, so it is invisible to every status query"
done
emit "FR_CITED_NOT_MINTED_COUNT=${cited_not_minted}"

# ── Check 5: doc frontmatter status vs tracker, for docs whose FRs all landed ─
doc_status_stale=0
doc_scanned=0
for glob_pat in "${cfg_doc_globs[@]}"; do
    [ -n "$glob_pat" ] || continue
    while IFS= read -r doc_file; do
        [ -n "$doc_file" ] || continue
        [ -f "$doc_file" ] || continue
        is_excluded_basename "$doc_file" && continue
        doc_scanned=$((doc_scanned + 1))

        doc_status="$(head -50 "$doc_file" 2>/dev/null | grep -m1 '^status:' | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')"
        [ -n "$doc_status" ] || continue

        doc_unfinished=false
        for _u in "${cfg_status_unfinished[@]}"; do
            [ "$(lc "$doc_status")" = "$(lc "$_u")" ] && doc_unfinished=true
        done
        [ "$doc_unfinished" = true ] || continue

        cited_n=0
        all_done=true
        while IFS= read -r doc_key; do
            [ -n "$doc_key" ] || continue
            if [ -z "${fr_present_by_key[$doc_key]+x}" ]; then
                # An unminted citation is check 4's business; we cannot judge
                # "all landed" without it, so this doc is not flagged.
                all_done=false
                continue
            fi
            # A minted-but-statusless key is an FR *category* (object shape) —
            # a container, not a landing claim. Judge on its leaves, which the
            # doc cites alongside it.
            [ -n "${fr_status_by_key[$doc_key]+x}" ] || continue
            cited_n=$((cited_n + 1))
            [ "${fr_canon_by_key[$doc_key]}" = "complete" ] || all_done=false
        done < <(fr_keys_in_file "$doc_file")

        if [ "$cited_n" -gt 0 ] && [ "$all_done" = true ]; then
            doc_status_stale=$((doc_status_stale + 1))
            add_issue WARN doc_status_stale \
                "DOC=${doc_file#"${project_dir}"/} DOC_STATUS=${doc_status} FRS=${cited_n}" \
                "every one of the ${cited_n} FR(s) this doc cites is complete, but its frontmatter still says '${doc_status}'"
        fi
    done < <(expand_glob "${project_dir}/${glob_pat}")
done
emit "DOCS_SCANNED=${doc_scanned}"
emit "DOC_STATUS_STALE_COUNT=${doc_status_stale}"

finish
