#!/usr/bin/env bash
# merge-review.sh — combine pr-review run results into one review.json.
#
# PURE: jq over files, no gh and no git. The main session writes each
# pr-review return to its own file, then this script joins them, so no agent
# and no hand edit ever merges review rows.
#
# Usage:
#   merge-review.sh [--out FILE] <run.json>...
#
#   --out FILE  write the JSON to FILE and print the summary on stdout; without
#               it the JSON goes to stdout and the summary to stderr.
#
# Each run.json is one pr-review return: {repo, mode: full|verify-only, status,
# prs:[{number, head_sha, status, lensesFailed, open, refuted, unverified,
# verifierFailed, stats}]}. An aborted run ({abort: true}) is an ERROR.
#
# Rules:
#   full runs         rows are taken as they are; one PR in two full runs is an
#                     ERROR (each PR belongs to one planned run)
#   verify-only runs  each row updates the full-run row with the same number:
#                     open and refuted are appended, unverified and
#                     verifierFailed are replaced, lensesFailed is kept. A row
#                     whose head_sha differs from the full-run row is skipped
#                     (WARN stale_verify): the PR moved after its review.
#   status            recomputed for every row, the same rule pr-review uses:
#                     unreviewed when both lenses died, partial when a lens died
#                     or a finding is unverified or behind a dead verifier,
#                     otherwise reviewed. open[] ids are renumbered F1..Fn.
#
# Output: {repo, runs:[{mode, status}], prs:[rows sorted by number]}
#
# Exit: 0 OK/WARN, 1 ERROR, 2 usage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

usage() {
  echo "Usage: merge-review.sh [--out FILE] <run.json>..." >&2
  exit 2
}

out_file=""
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) [ $# -ge 2 ] || usage; out_file="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
[ "${#positional[@]}" -ge 1 ] || usage

SUMMARY_FD=2
# shellcheck disable=SC2034 # SUMMARY_FD is read by lib/summary.sh
[ -n "$out_file" ] && SUMMARY_FD=1
summary_init "PR SWEEP REVIEW MERGE"

fail() {
  summary_issue ERROR "$1" "$2"
  summary_emit
  exit 1
}

command -v jq >/dev/null 2>&1 || fail missing_tool "jq is required but not installed"
for f in "${positional[@]}"; do
  [ -f "$f" ] || fail missing_input "run file not found: $f"
  jq -e 'type == "object"' "$f" >/dev/null 2>&1 || fail bad_run "not a JSON object: $f"
  if jq -e '.abort == true' "$f" >/dev/null 2>&1; then
    fail aborted_run "$f is an aborted run ($(jq -r '.reason // "?"' "$f")); fix the args and re-run it"
  fi
  jq -e '(.prs | type == "array") and ((.mode // "full") | IN("full", "verify-only"))' "$f" >/dev/null 2>&1 ||
    fail bad_run "$f has no .prs array or an unknown mode"
done

repos=$(jq -rs '[.[].repo // empty] | unique | join(",")' "${positional[@]}")
case "$repos" in *,*) fail repo_mismatch "runs name different repos: $repos" ;; esac

dups=$(jq -rs '[.[] | select((.mode // "full") == "full") | .prs[].number] | group_by(.) | map(select(length > 1) | .[0]) | map(tostring) | join(",")' "${positional[@]}")
[ -z "$dups" ] || fail duplicate_pr "PR(s) $dups appear in more than one full run"

# shellcheck disable=SC2016
out=$(jq -s '
  def status_of: if ((.lensesFailed // []) | length) >= 2 then "unreviewed"
    elif ((.lensesFailed // []) | length) > 0 or ((.unverified // []) | length) > 0 or ((.verifierFailed // []) | length) > 0 then "partial"
    else "reviewed" end;
  def renumber: .open = [(.open // []) | to_entries[] | .value + {id: "F\(.key + 1)"}];
  . as $runs
  | ([$runs[] | select((.mode // "full") == "full") | .prs[]] | map({key: (.number | tostring), value: .}) | from_entries) as $base
  | (reduce ($runs[] | select(.mode == "verify-only") | .prs[]) as $v ({rows: $base, stale: [], orphan: []};
      (.rows[$v.number | tostring]) as $b
      | if $b == null then .orphan += [$v.number]
        elif $b.head_sha != $v.head_sha then .stale += [$v.number]
        else .rows[$v.number | tostring] = ($b
          | .open = ((.open // []) + ($v.open // []))
          | .refuted = ((.refuted // []) + ($v.refuted // []))
          | .unverified = ($v.unverified // [])
          | .verifierFailed = ($v.verifierFailed // []))
        end)) as $acc
  | {
      repo: ([$runs[].repo // empty] | first // null),
      runs: [$runs[] | {mode: (.mode // "full"), status: (.status // null)}],
      prs: ([$acc.rows[]] | map(renumber | .status = status_of) | sort_by(.number)),
      stale: $acc.stale,
      orphan: $acc.orphan
    }' "${positional[@]}" 2>&1) || fail transform_failed "jq transform failed: ${out:0:160}"

stale=$(jq -r '.stale | map(tostring) | join(",")' <<<"$out")
orphan=$(jq -r '.orphan | map(tostring) | join(",")' <<<"$out")
[ -n "$stale" ] && summary_issue WARN stale_verify "verify-only rows for PR(s) $stale skipped: head moved since the review"
[ -n "$orphan" ] && summary_issue WARN no_base_row "verify-only rows for PR(s) $orphan skipped: no full-run row to update"
out=$(jq 'del(.stale, .orphan)' <<<"$out")

summary_kv REPO "$(jq -r '.repo // ""' <<<"$out")"
summary_kv RUNS "$(jq '.runs | length' <<<"$out")"
summary_kv PRS "$(jq '.prs | length' <<<"$out")"
summary_kv REVIEWED "$(jq '[.prs[] | select(.status == "reviewed")] | length' <<<"$out")"
summary_kv PARTIAL "$(jq -r '[.prs[] | select(.status == "partial") | .number | tostring] | join(",")' <<<"$out")"
summary_kv UNREVIEWED "$(jq -r '[.prs[] | select(.status == "unreviewed") | .number | tostring] | join(",")' <<<"$out")"
summary_kv OPEN_FINDINGS "$(jq '[.prs[].open[]] | length' <<<"$out")"
summary_kv UNVERIFIED "$(jq '[.prs[] | (.unverified // [])[]] | length' <<<"$out")"

if [ -n "$out_file" ]; then
  printf '%s\n' "$out" > "$out_file" || fail write_failed "could not write $out_file"
  summary_kv OUT "$out_file"
else
  printf '%s\n' "$out"
fi
summary_emit
exit 0
