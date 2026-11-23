#!/usr/bin/env bash
# plan-review-runs.sh — split a roster's reviewable PRs into pr-review runs,
# grouping small PRs so one pair of finders covers several of them.
#
# PURE: jq over one file, no gh and no git. The grouping is deterministic, so
# the same roster always yields the same runs, and the pr-review template only
# validates the groups it is given instead of re-deriving them in agents.
#
# Usage:
#   plan-review-runs.sh [--out FILE] <roster.json>
#
#   --out FILE  write the JSON to FILE and print the summary on stdout; without
#               it the JSON goes to stdout and the summary to stderr.
#
# Input: list-sweep-prs.sh output. A PR is reviewable when policy.review is true.
#
# Grouping (limits are pr-review.workflow.js's caps; its test pins them equal):
#   small PR   diff_lines <= 150 and changed_files <= 6
#   group      one large PR alone, or up to 3 small PRs whose diff_lines sum to
#              at most 300, packed greedily in PR-number order
#   run        up to 4 groups and up to 6 PRs, packed greedily in group order
#              (groups are ordered by their lowest PR number)
#
# Output:
#   {repo, default_branch, limits:{...},
#    runs:[{prs:[{number,title,url,head,head_sha,base,is_draft,diff_lines,
#                 changed_files,author_kind,draft_class}], groups:[[n]]}],
#    not_reviewed:[{number, reason}]}
#   Pass one runs[] element, plus repo and root, as pr-review's args.
#
# Exit: 0 OK, 1 ERROR, 2 usage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

# PRESERVE: equal to MAX_PRS / MAX_GROUPS / MAX_PER_GROUP in pr-review.workflow.js.
MAX_PRS=6
MAX_GROUPS=4
MAX_PER_GROUP=3
SMALL_LINES=150
SMALL_FILES=6
GROUP_LINES=300

usage() {
  echo "Usage: plan-review-runs.sh [--out FILE] <roster.json>" >&2
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
[ "${#positional[@]}" -eq 1 ] || usage
roster="${positional[0]}"

SUMMARY_FD=2
# shellcheck disable=SC2034 # SUMMARY_FD is read by lib/summary.sh
[ -n "$out_file" ] && SUMMARY_FD=1
summary_init "PR SWEEP REVIEW PLAN"

fail() {
  summary_issue ERROR "$1" "$2"
  summary_emit
  exit 1
}

command -v jq >/dev/null 2>&1 || fail missing_tool "jq is required but not installed"
[ -f "$roster" ] || fail missing_input "roster not found: $roster"
jq -e '.prs | type == "array"' "$roster" >/dev/null 2>&1 || fail bad_roster "roster has no .prs array: $roster"
jq -e 'all(.prs[]; (.policy | type == "object") and (.diff_lines | type == "number") and (.changed_files | type == "number"))' \
  "$roster" >/dev/null 2>&1 || fail bad_roster "roster rows lack policy/diff_lines/changed_files; produce it with list-sweep-prs.sh"

# shellcheck disable=SC2016
out=$(jq -n --slurpfile r "$roster" \
  --argjson mp "$MAX_PRS" --argjson mg "$MAX_GROUPS" --argjson mpg "$MAX_PER_GROUP" \
  --argjson sl "$SMALL_LINES" --argjson sf "$SMALL_FILES" --argjson gl "$GROUP_LINES" '
  $r[0] as $R
  | ($R.prs | sort_by(.number)) as $all
  | ($all | map(select(.policy.review == true))
     | map({number, title, url, head, head_sha, base, is_draft, diff_lines, changed_files, author_kind, draft_class})) as $rev
  | def small: .diff_lines <= $sl and .changed_files <= $sf;
    ($rev | map(select(small))) as $small
  | ($rev | map(select(small | not) | [.])) as $large
  | (reduce $small[] as $p ([];
      if length > 0 and (.[-1] | length) < $mpg and ((.[-1] | map(.diff_lines) | add) + $p.diff_lines) <= $gl
      then .[:-1] + [.[-1] + [$p]]
      else . + [[$p]] end)) as $smallGroups
  | ($large + $smallGroups | sort_by(.[0].number)) as $groups
  | (reduce $groups[] as $g ([];
      if length > 0 and (.[-1] | length) < $mg and ((.[-1] | map(length) | add) + ($g | length)) <= $mp
      then .[:-1] + [.[-1] + [$g]]
      else . + [[$g]] end)) as $runs
  | {
      repo: ($R.repo // null),
      default_branch: ($R.default_branch // null),
      limits: {max_prs: $mp, max_groups: $mg, max_per_group: $mpg, small_lines: $sl, small_files: $sf, group_lines: $gl},
      runs: [$runs[] | {prs: (map(.[]) | sort_by(.number)), groups: map(map(.number))}],
      not_reviewed: [$all[] | select(.policy.review != true) | {number, reason: (.policy.review_block // "not_reviewable")}]
    }' 2>&1) || fail transform_failed "jq transform failed: ${out:0:160}"

summary_kv REPO "$(jq -r '.repo // ""' <<<"$out")"
summary_kv REVIEWABLE "$(jq '[.runs[].prs[]] | length' <<<"$out")"
summary_kv GROUPS "$(jq '[.runs[].groups[]] | length' <<<"$out")"
summary_kv RUNS "$(jq '.runs | length' <<<"$out")"
summary_kv RUN_PRS "$(jq -r '[.runs[] | [.prs[].number] | map(tostring) | join(",")] | join(" | ")' <<<"$out")"
summary_kv NOT_REVIEWED "$(jq '.not_reviewed | length' <<<"$out")"

if [ -n "$out_file" ]; then
  printf '%s\n' "$out" > "$out_file" || fail write_failed "could not write $out_file"
  summary_kv OUT "$out_file"
else
  printf '%s\n' "$out"
fi
summary_emit
exit 0
