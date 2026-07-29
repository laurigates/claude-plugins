#!/usr/bin/env bash
# file-wave.sh — Phase 3 of workflow-verify-before-filing: file a verified wave
# of upstream issues, paced so the forge's rate limiter does not eat the batch.
#
# WHY THIS IS A SCRIPT AND NOT PROSE
# Phase 3 is the purely MECHANICAL half of the workflow: read the gate-passing
# results, create one issue per draft, wait, retry on failure, record every URL.
# Retyping that loop out of REFERENCE.md each run re-derives it slightly
# differently every time (.claude/rules/offload-to-deterministic-substrate.md).
# The RATIONALE for the pacing numbers stays in REFERENCE.md; the loop lives here.
#
# INPUT — the shape the Phase 1+2 Workflow script returns
#   A JSON array of per-candidate result objects (or an object with a `.results`
#   array). Only entries with `disposition == "file"` are filed; every other
#   disposition is a recorded gate-out and is counted, never filed:
#     [{ "id": "W2-13", "slug": "…", "disposition": "file",
#        "draftPath": "/abs/drafts/W2-13-….md",
#        "title": "…", "targetProject": "group/subgroup/project" }, …]
#
# FORGE DISPATCH (deterministic, first match wins — reported as FORGE_SOURCE=)
#   1. --forge gh|glab            → flag
#   2. $FILE_WAVE_FORGE           → env:FILE_WAVE_FORGE
#   3. --host … or $GITLAB_HOST   → env:GITLAB_HOST   (a GitLab host implies glab)
#   4. otherwise                  → default           (gh)
#   There is no "sniff the project path" heuristic on purpose: `group/project`
#   and `owner/repo` are indistinguishable, so guessing would be silently wrong.
#
# OUTPUT — .claude/rules/structured-script-output.md (KEY=VALUE + STATUS=)
# EXIT   — 0 on OK/WARN (including an EMPTY input set, so the script stays
#          parallel-safe per .claude/rules/parallel-safe-queries.md);
#          1 on ERROR (a create exhausted its retries, a draft was missing);
#          2 on a usage error (unknown argument, missing --results).
#
# Usage:
#   bash file-wave.sh --results <results.json> [options]
#
#   --results <path>         REQUIRED. Workflow result JSON (array or {results:[…]}).
#   --forge <gh|glab|auto>   Forge dispatch (default: auto — see above).
#   --host <hostname>        GitLab host; exported as GITLAB_HOST for glab.
#   --draft-dir <dir>        Base dir for relative draftPath values.
#   --manifest <path>        URL manifest to append to
#                            (default: <dir of --results>/filed-urls.txt).
#   --pace-seconds <n>       Sleep between creates (default: 70).
#   --backoff-seconds <n>    Sleep after a failed attempt (default: 130).
#   --max-attempts <n>       Attempts per issue, including the first (default: 4).
#   --dry-run                Resolve and report, create nothing.

# Deliberately NOT `set -e`: a single failed create must be recorded and the
# batch must continue to the next draft (.claude/rules/shell-scripting.md —
# "match the flags to the script's job").
set -uo pipefail

RESULTS_FILE=""
FORGE_ARG=""
GITLAB_HOST_ARG=""
DRAFT_DIR=""
MANIFEST=""
PACE_SECONDS=70
BACKOFF_SECONDS=130
MAX_ATTEMPTS=4
DRY_RUN=0

usage() {
    sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die_usage() {
    echo "file-wave.sh: $1" >&2
    usage >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --results) RESULTS_FILE="${2:-}"; shift 2 ;;
        --forge) FORGE_ARG="${2:-}"; shift 2 ;;
        --host) GITLAB_HOST_ARG="${2:-}"; shift 2 ;;
        --draft-dir) DRAFT_DIR="${2:-}"; shift 2 ;;
        --manifest) MANIFEST="${2:-}"; shift 2 ;;
        --pace-seconds) PACE_SECONDS="${2:-}"; shift 2 ;;
        --backoff-seconds) BACKOFF_SECONDS="${2:-}"; shift 2 ;;
        --max-attempts) MAX_ATTEMPTS="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        # Fail fast on an unknown flag. A silently-swallowed argument turned a
        # BOUNDED apply into an unbounded one in taskwarrior's reconcile.sh
        # (issue #2057); the same trap here would silently drop --dry-run.
        *) die_usage "unknown argument: $1" ;;
    esac
done

[ -n "$RESULTS_FILE" ] || die_usage "--results <path> is required"

emit_section() {
    echo "=== FILE WAVE ==="
    printf '%s\n' "$@"
    echo "=== END FILE WAVE ==="
}

# --- Preflight -------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
    emit_section "JQ_AVAILABLE=false" "STATUS=ERROR" "ISSUE_COUNT=1" \
        "ISSUES:" "  - SEVERITY=ERROR TYPE=missing_dependency MSG=jq is required to read the results JSON"
    exit 1
fi

if [ ! -f "$RESULTS_FILE" ]; then
    emit_section "JQ_AVAILABLE=true" "RESULTS_FILE=$RESULTS_FILE" "STATUS=ERROR" "ISSUE_COUNT=1" \
        "ISSUES:" "  - SEVERITY=ERROR TYPE=missing_results MSG=results file not found"
    exit 1
fi

# Normalise a bare array and a {results: […]} wrapper to one array.
normalised=$(jq -c 'if type == "object" then (.results // []) else . end' "$RESULTS_FILE" 2>/dev/null)
if [ -z "$normalised" ]; then
    emit_section "JQ_AVAILABLE=true" "RESULTS_FILE=$RESULTS_FILE" "STATUS=ERROR" "ISSUE_COUNT=1" \
        "ISSUES:" "  - SEVERITY=ERROR TYPE=unparseable_results MSG=results file is not valid JSON"
    exit 1
fi

candidate_count=$(jq 'length' <<<"$normalised")

# --- Forge dispatch --------------------------------------------------------
forge=""
forge_source=""
case "$FORGE_ARG" in
    gh|glab) forge="$FORGE_ARG"; forge_source="flag" ;;
    auto|"") ;;
    *) die_usage "--forge must be gh, glab, or auto (got: $FORGE_ARG)" ;;
esac

if [ -z "$forge" ] && [ -n "${FILE_WAVE_FORGE:-}" ]; then
    case "$FILE_WAVE_FORGE" in
        gh|glab) forge="$FILE_WAVE_FORGE"; forge_source="env:FILE_WAVE_FORGE" ;;
        *) die_usage "FILE_WAVE_FORGE must be gh or glab (got: $FILE_WAVE_FORGE)" ;;
    esac
fi

gitlab_host="${GITLAB_HOST_ARG:-${GITLAB_HOST:-}}"
if [ -z "$forge" ] && [ -n "$gitlab_host" ]; then
    forge="glab"
    forge_source="env:GITLAB_HOST"
fi

if [ -z "$forge" ]; then
    forge="gh"
    forge_source="default"
fi

[ -n "$gitlab_host" ] && export GITLAB_HOST="$gitlab_host"

# --- Manifest --------------------------------------------------------------
if [ -z "$MANIFEST" ]; then
    MANIFEST="$(cd "$(dirname "$RESULTS_FILE")" && pwd)/filed-urls.txt"
fi

# --- Collect the gate-passing set -----------------------------------------
# Only `disposition == "file"` is filed. Fields are joined with US (0x1f), NOT
# a tab: bash's `read` treats IFS *whitespace* runs as one delimiter, so an
# empty title in a tab-separated row silently shifts targetProject into the
# title column (the #1627 column-slide failure, arrived at from the other end).
# US is not IFS whitespace, so empty fields survive. Any US/tab inside a value
# is scrubbed first so a title can never invent a column.
filing_rows=$(jq -r '
  def clean: (. // "") | gsub("[\t\u001f]"; " ");
  [ .[] | select(.disposition == "file") ]
  | .[]
  | [ (.id | clean), (.draftPath | clean), (.title | clean), (.targetProject | clean) ]
  | join("\u001f")
' <<<"$normalised")

file_count=0
[ -n "$filing_rows" ] && file_count=$(grep -c '' <<<"$filing_rows")

filed_count=0
failed_count=0
declare -a filed_rows=()
declare -a issues=()

# Empty input is a legitimate outcome (every candidate gated out), not an error.
if [ "$file_count" -eq 0 ]; then
    emit_section \
        "JQ_AVAILABLE=true" \
        "FORGE=$forge" \
        "FORGE_SOURCE=$forge_source" \
        "DRY_RUN=$([ "$DRY_RUN" -eq 1 ] && echo true || echo false)" \
        "RESULTS_FILE=$RESULTS_FILE" \
        "CANDIDATE_COUNT=$candidate_count" \
        "FILE_COUNT=0" \
        "FILED_COUNT=0" \
        "FAILED_COUNT=0" \
        "STATUS=OK" \
        "ISSUE_COUNT=0"
    exit 0
fi

# --- Title / body extraction ----------------------------------------------
# Title: the draft's first `# ` heading. Body: everything after it, minus the
# HTML target comments the drafting phase adds (they must not reach the forge).
draft_title() {
    # awk, not `sed … | head -1`: no producer pipe, so an early-closing reader
    # can never hand `pipefail` a SIGPIPE 141
    # (~/.claude/rules/shell-pipefail-grep-q.md).
    awk '/^# /{ sub(/^# /, ""); print; exit }' "$1"
}

draft_body() {
    sed '1d' "$1" | grep -v '^<!--'
}

create_issue() {
    # create_issue <repo> <title> <body>  → prints the forge's output
    local repo="$1" issue_title="$2" issue_body="$3"
    if [ "$forge" = "glab" ]; then
        glab issue create -R "$repo" -t "$issue_title" -d "$issue_body" -y 2>&1
    else
        gh issue create --repo "$repo" --title "$issue_title" --body "$issue_body" 2>&1
    fi
}

# --- The paced filing loop -------------------------------------------------
row_index=0
while IFS=$'\x1f' read -r item_id draft_path item_title repo; do
    [ -n "$draft_path" ] || continue
    row_index=$((row_index + 1))

    # Pace BETWEEN writes: sleep before every create except the first, so the
    # batch never pays a trailing wait it cannot use.
    if [ "$row_index" -gt 1 ] && [ "$DRY_RUN" -eq 0 ] && [ "$PACE_SECONDS" -gt 0 ]; then
        sleep "$PACE_SECONDS"
    fi

    case "$draft_path" in
        /*) resolved="$draft_path" ;;
        *) resolved="${DRAFT_DIR:+$DRAFT_DIR/}$draft_path" ;;
    esac

    if [ ! -f "$resolved" ]; then
        failed_count=$((failed_count + 1))
        issues+=("  - SEVERITY=ERROR TYPE=missing_draft ID=$item_id PATH=$resolved MSG=draft file not found")
        printf '%s -> FAILED (missing draft)\n' "$(basename "$resolved")" >>"$MANIFEST"
        continue
    fi

    [ -n "$item_title" ] || item_title="$(draft_title "$resolved")"
    if [ -z "$item_title" ] || [ -z "$repo" ]; then
        failed_count=$((failed_count + 1))
        issues+=("  - SEVERITY=ERROR TYPE=incomplete_entry ID=$item_id MSG=missing title or targetProject")
        printf '%s -> FAILED (incomplete entry)\n' "$(basename "$resolved")" >>"$MANIFEST"
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        filed_rows+=("  - ID=$item_id REPO=$repo URL=DRY_RUN TITLE=$item_title")
        filed_count=$((filed_count + 1))
        continue
    fi

    body="$(draft_body "$resolved")"
    issue_url=""
    attempt=1
    while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
        out="$(create_issue "$repo" "$item_title" "$body")"
        # The forge prints the created URL as its LAST line. A here-string
        # avoids a producer pipe entirely, so `pipefail` can never see a
        # SIGPIPE 141 from an early-closing reader
        # (~/.claude/rules/shell-pipefail-grep-q.md).
        last_line="$(tail -n1 <<<"$out")"
        case "$last_line" in
            https://*) issue_url="$last_line"; break ;;
        esac
        attempt=$((attempt + 1))
        if [ "$attempt" -le "$MAX_ATTEMPTS" ] && [ "$BACKOFF_SECONDS" -gt 0 ]; then
            sleep "$BACKOFF_SECONDS"
        fi
    done

    if [ -n "$issue_url" ]; then
        filed_count=$((filed_count + 1))
        filed_rows+=("  - ID=$item_id REPO=$repo URL=$issue_url")
        printf '%s -> %s\n' "$(basename "$resolved")" "$issue_url" >>"$MANIFEST"
    else
        # Continue past a failure and report it at the end rather than aborting
        # the batch — a half-filed wave with no record is the worst outcome.
        failed_count=$((failed_count + 1))
        issues+=("  - SEVERITY=ERROR TYPE=create_failed ID=$item_id REPO=$repo ATTEMPTS=$MAX_ATTEMPTS MSG=create exhausted its retries")
        printf '%s -> FAILED\n' "$(basename "$resolved")" >>"$MANIFEST"
    fi
done <<<"$filing_rows"

item_status="OK"
[ "$failed_count" -gt 0 ] && item_status="ERROR"

output=(
    "JQ_AVAILABLE=true"
    "FORGE=$forge"
    "FORGE_SOURCE=$forge_source"
    "DRY_RUN=$([ "$DRY_RUN" -eq 1 ] && echo true || echo false)"
    "RESULTS_FILE=$RESULTS_FILE"
    "MANIFEST=$MANIFEST"
    "PACE_SECONDS=$PACE_SECONDS"
    "BACKOFF_SECONDS=$BACKOFF_SECONDS"
    "MAX_ATTEMPTS=$MAX_ATTEMPTS"
    "CANDIDATE_COUNT=$candidate_count"
    "FILE_COUNT=$file_count"
    "FILED_COUNT=$filed_count"
    "FAILED_COUNT=$failed_count"
)
[ "${#filed_rows[@]}" -gt 0 ] && output+=("FILED:" "${filed_rows[@]}")
output+=("STATUS=$item_status" "ISSUE_COUNT=$failed_count")
[ "${#issues[@]}" -gt 0 ] && output+=("ISSUES:" "${issues[@]}")

emit_section "${output[@]}"

[ "$failed_count" -eq 0 ]
