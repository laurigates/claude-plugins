#!/usr/bin/env bash
# merge-gate.sh — decide, per open PR, whether the sweep may ready it and merge
# it, and report every PR it may not with the first gate that stopped it.
#
# PURE: jq over files, no gh and no git. The roster must be freshly re-listed
# with `list-sweep-prs.sh --resolve-blockers` just before this runs; a stale
# roster is the one input this script cannot detect.
#
# Usage:
#   merge-gate.sh [--chunk N] [--out FILE] <roster.json> <review.json> [<fix.json>...]
#
#   --chunk N   PRs per merge chunk, 1..8 (default 8). Each chunk is one
#               merge-chain.sh --prs list; the external-PR merge guard runs one
#               gh pr view per listed PR inside its hook timeout.
#   --out FILE  write the plan JSON to FILE and print the summary on stdout;
#               without it the JSON goes to stdout and the summary to stderr.
#
# review.json   {prs:[{number, head_sha, status, open, unverified, verifierFailed}]}.
#               Pass a file holding {"prs":[]} when no review exists: every PR then
#               fails the review gate, which is the point.
# fix.json      optional, one or more files, each either
#                 {prs:[{number, row_status, pushed_status, head_sha, detail}]}
#               or one pr-fix / repair-round return {rows, finalisePlan, pushed},
#               or an array of them, with unit ids "pr-<n>"; the latest row per
#               PR wins (later files are later).
#
# Gates, in order (the first failure is `gate`; `failed` lists every failure):
#   G1 skip    sweep_skip is null (release-please and Renovate PRs have their own flow)
#   G2 author  author_kind is self or bot (git-plugin:external-pr-trust)
#   G3 wip     no WIP / DNM / do-not-merge / blocked marker
#   G4 review  review status `reviewed`, no unverified finding, no dead verifier,
#              and open[] empty, or the fix row PASS/REPAIRED_PASS and pushed
#   G5 head    roster head_sha equals the expected head (fix push head, else the
#              reviewed head)
#   G6 ci      ci is not red (pending passes for a non-draft: merge-chain waits)
#   G7 base    the base is the default branch
#   G8 draft   drafts only: draft_class ready_candidate and ci green
#
# Output:
#   {repo, passed:[n], ready:[n], merge:[[n]],
#    report:[{number, url, is_draft, gate, reason, failed:[gate], open_count}]}
#   ready  drafts that passed every gate; the main session runs gh pr ready on each
#   merge  every passing PR, ascending, chunked; paste each chunk as a literal --prs
#
# Exit: 0 OK, 1 ERROR, 2 usage. Reported PRs are not script errors.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/lib/summary.sh disable=SC1091
source "$SCRIPT_DIR/lib/summary.sh"

usage() {
  echo "Usage: merge-gate.sh [--chunk N] [--out FILE] <roster.json> <review.json> [<fix.json>...]" >&2
  exit 2
}

chunk=8
out_file=""
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --chunk) [ $# -ge 2 ] || usage; chunk="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out_file="$2"; shift 2 ;;
    -h|--help) usage ;;
    --) shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) positional+=("$1"); shift ;;
  esac
done
[ "${#positional[@]}" -ge 2 ] || usage
[[ "$chunk" =~ ^[1-8]$ ]] || { echo "--chunk must be 1..8" >&2; exit 2; }
roster="${positional[0]}"
review="${positional[1]}"
fixes=("${positional[@]:2}")

SUMMARY_FD=2
# shellcheck disable=SC2034 # SUMMARY_FD is read by lib/summary.sh
[ -n "$out_file" ] && SUMMARY_FD=1
summary_init "PR SWEEP MERGE GATE"

fail() {
  summary_issue ERROR "$1" "$2"
  summary_emit
  exit 1
}

command -v jq >/dev/null 2>&1 || fail missing_tool "jq is required but not installed"
[ -f "$roster" ] || fail missing_input "roster not found: $roster"
[ -f "$review" ] || fail missing_input "review not found: $review"
jq -e '.prs | type == "array"' "$roster" >/dev/null 2>&1 || fail bad_roster "roster has no .prs array: $roster"
jq -e '.prs | type == "array"' "$review" >/dev/null 2>&1 || fail bad_review "review has no .prs array: $review"
fix_json='{"prs":[]}'
for fix in "${fixes[@]}"; do
  [ -f "$fix" ] || fail missing_input "fix not found: $fix"
  jq -e . "$fix" >/dev/null 2>&1 || fail bad_fix "fix is not JSON: $fix"
done
if [ "${#fixes[@]}" -eq 1 ]; then
  fix_json=$(cat "${fixes[0]}")
elif [ "${#fixes[@]}" -gt 1 ]; then
  # Several files: one array, in argument order, so a later file's row wins.
  fix_json=$(jq -s '[.[] | if type == "array" then .[] else . end]' "${fixes[@]}")
fi

# Normalise fix input to {number, row_status, pushed_status, head_sha, detail}.
# shellcheck disable=SC2016
fix_rows=$(jq -c '
  def from_rr:
    . as $run
    | ($run.rows // []) | map(
        .unit as $u
        | ([$u | strings | capture("^pr-(?<n>[0-9]+)$")? | .n | tonumber] | first) as $n
        | if $n == null then error("repair-round unit id \($u | tojson) is not pr-<number>") else . end
        | (($run.finalisePlan // []) | map(select(.unit == $u)) | last) as $fp
        | (($run.pushed // []) | map(select(.unit == $u)) | last) as $pu
        | {number: $n, row_status: .status, pushed_status: ($pu.status // null),
           head_sha: ($fp.head_sha // .fix.head_sha // null), detail: ($pu.detail // "")});
  (if type == "object" and has("prs") then .prs
   elif type == "array" then map(if type == "object" and has("prs") then .prs else from_rr end) | add // []
   else from_rr end)
  | group_by(.number) | map(last)' <<<"$fix_json" 2>&1) ||
  fail bad_fix "could not read fix input: ${fix_rows:0:160}"

# shellcheck disable=SC2016
out=$(jq -n --slurpfile r "$roster" --slurpfile v "$review" --argjson fixrows "$fix_rows" --argjson chunk "$chunk" '
  $r[0] as $R
  | ($v[0].prs | map({key: (.number | tostring), value: .}) | from_entries) as $byN
  | ($fixrows | map({key: (.number | tostring), value: .}) | from_entries) as $fixN
  | def short: if . == null or . == "" then "none" else .[0:8] end;
    def gates($p; $rv; $fx):
      (($rv.open // []) | length) as $oc
      | (($rv.unverified // []) | length) as $uv
      | (($rv.verifierFailed // []) | length) as $vf
      | (if ($fx.pushed_status // null) == "pushed" then $fx.head_sha else ($rv.head_sha // null) end) as $expected
      | [
          (if $p.sweep_skip == null then empty
           elif $p.sweep_skip == "release_please" then {gate: "skip", reason: "release PR; handled by its own flow (git-plugin:release-please-pr-workflow)"}
           elif $p.sweep_skip == "renovate" then {gate: "skip", reason: "dependency PR; merging stays with Renovate'"'"'s own flow"}
           else {gate: "skip", reason: "head branch lives in a fork (\($p.sweep_skip)); not merged by the sweep"} end),
          (if ($p.author_kind == "self" or $p.author_kind == "bot") then empty
           else {gate: "author", reason: "author \($p.author | tojson) is external; review it, do not chain-merge it (git-plugin:external-pr-trust)"} end),
          (if ($p.wip | not) then empty
           else {gate: "wip", reason: "WIP/do-not-merge marker: \(($p.wip_markers // []) | join(", "))"} end),
          (if $rv == null then {gate: "review", reason: "not reviewed"}
           elif ($rv.status // "") == "unreviewed" then {gate: "review", reason: "review status unreviewed (finder died)"}
           elif ($uv + $vf) > 0 then {gate: "review", reason: "\($uv) unverified finding(s), \($vf) dead verifier(s); run a verify-only re-run"}
           elif ($rv.status // "") != "reviewed" then {gate: "review", reason: "review status \($rv.status // "missing")"}
           elif $oc == 0 then empty
           elif $fx == null then {gate: "review", reason: "\($oc) open finding(s), no fix ran"}
           elif (($fx.row_status // "") | IN("PASS", "REPAIRED_PASS") | not) then {gate: "review", reason: "\($oc) open finding(s); fix row \($fx.row_status // "missing")"}
           elif ($fx.pushed_status // null) != "pushed" then {gate: "review", reason: "\($oc) open finding(s) fixed but not pushed (\($fx.pushed_status // "null"))"}
           else empty end),
          (if $expected != null and $expected != "" and $p.head_sha == $expected then empty
           else {gate: "head", reason: "head moved: roster \($p.head_sha | short) != expected \($expected | short); a push landed after the review or fix"} end),
          (if $p.ci != "red" then empty
           else {gate: "ci", reason: "CI red: \(($p.ci_failed // []) | join(", "))"} end),
          (if $p.base_is_default then empty
           else {gate: "base", reason: "base \($p.base | tojson) is not the default branch \($R.default_branch | tojson); stacked PR, retarget by hand"} end),
          (if ($p.is_draft | not) then empty
           elif $p.draft_class == "ready_candidate" and $p.ci == "green" then empty
           elif $p.draft_class == "ready_candidate" then {gate: "draft", reason: "draft CI is \($p.ci); readying needs green"}
           elif $p.draft_class == "no_section" then {gate: "draft", reason: "draft without ## Draft status; cannot be readied"}
           elif $p.draft_class == "no_blocker_urls" then {gate: "draft", reason: "## Draft status names no PR URL; readiness is the owner'"'"'s call"}
           elif $p.draft_class == "blockers_unresolved" then {gate: "draft", reason: "blocker states not resolved; re-list with --resolve-blockers"}
           elif $p.draft_class == "blocked" then {gate: "draft", reason: ("blocked by " + ([$p.draft_status.blockers[] | select(.state != "MERGED") | "\(.url) (\(.state // "UNKNOWN"))"] | join(", ")))}
           else {gate: "draft", reason: "draft_class \($p.draft_class)"} end)
        ];
  [ $R.prs | sort_by(.number)[]
    | . as $p
    | ($byN[$p.number | tostring]) as $rv
    | ($fixN[$p.number | tostring]) as $fx
    | gates($p; $rv; $fx) as $g
    | {p: $p, g: $g, oc: (($rv.open // []) | length)} ] as $evaluated
  | [$evaluated[] | select(.g | length == 0) | .p] as $passed
  | {
      repo: ($R.repo // null),
      passed: [$passed[] | .number],
      ready: [$passed[] | select(.is_draft) | .number],
      merge: ([$passed[] | .number] as $n | [range(0; $n | length; $chunk) as $i | $n[$i:$i + $chunk]]),
      report: [$evaluated[] | select(.g | length > 0)
        | {number: .p.number, url: .p.url, is_draft: .p.is_draft,
           gate: .g[0].gate, reason: .g[0].reason, failed: [.g[].gate], open_count: .oc}]
    }' 2>&1) || fail gate_failed "jq gate evaluation failed: ${out:0:160}"

summary_kv REPO "$(jq -r '.repo // ""' <<<"$out")"
summary_kv PASSED "$(jq '.passed | length' <<<"$out")"
summary_kv READY "$(jq -r '.ready | join(",")' <<<"$out")"
summary_kv MERGE_CHUNKS "$(jq '.merge | length' <<<"$out")"
i=1
while IFS= read -r line; do
  [ -n "$line" ] || continue
  summary_kv "MERGE_CHUNK_$i" "$line"
  i=$((i + 1))
done < <(jq -r '.merge[] | join(",")' <<<"$out")
summary_kv REPORTED "$(jq '.report | length' <<<"$out")"
for g in skip author wip review head ci base draft; do
  summary_kv "GATE_$(tr '[:lower:]' '[:upper:]' <<<"$g")" "$(jq --arg g "$g" '[.report[] | select(.gate == $g)] | length' <<<"$out")"
done

if [ -n "$out_file" ]; then
  printf '%s\n' "$out" > "$out_file" || fail write_failed "could not write $out_file"
  summary_kv OUT "$out_file"
else
  printf '%s\n' "$out"
fi
summary_emit
exit 0
