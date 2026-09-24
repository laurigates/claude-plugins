#!/usr/bin/env bash
# Assert that a Claude workflow step actually delivered its PR comment.
#
# Background (#2630 Rec 1, #2719). Two Claude steps whose ONLY deliverable is a
# PR comment reported green while posting nothing: release-pr-doc-audit.yml on
# every release PR since 2026-09-01 (4 permission denials, subtype success,
# is_error false, no comment), and the Claude Skill Quality Review step in
# plugin-pr-checks.yml on PR #2664 (4 denials, 0 reviews, 0 inline comments).
# The SDK exits 0 on a denial, so a denied posting call is a green job. This
# helper is the post-step gate: it counts the comments that appeared on the PR
# since the Claude step started and fails when there are none.
#
# Time-bounded on purpose. release-please force-pushes its PR and the audit
# re-runs on every push, so a heading-carrying comment from a PREVIOUS run sits
# on the same PR; without the --since bound it would satisfy every later run.
#
# Usage:
#   bash scripts/assert-pr-comment-delivered.sh --repo OWNER/REPO --pr N \
#     --since EPOCH [--author LOGIN] [--heading TEXT] [--include-review-comments]
#
#   --since EPOCH              Count only comments created at/after this Unix
#                              time (record it in a step before the Claude step).
#   --author LOGIN             Count only comments by this login (e.g. claude[bot]).
#   --heading TEXT             Count only issue comments with a line that starts
#                              with TEXT once leading whitespace is dropped.
#   --include-review-comments  Also count inline review comments
#                              (pulls/N/comments). The heading filter does not
#                              apply to them: an inline finding carries no heading.
#
# Output follows .claude/rules/structured-script-output.md
# (=== PR COMMENT DELIVERY === / DELIVERED= / STATUS= / ISSUE_COUNT=).
#
# Exit codes:
#   0 - at least one matching comment was delivered
#   1 - nothing was delivered
#   2 - usage error, or the API could not be read (DELIVERED=unknown)

set -euo pipefail

usage() {
  echo "Usage: assert-pr-comment-delivered.sh --repo OWNER/REPO --pr N --since EPOCH [--author LOGIN] [--heading TEXT] [--include-review-comments]" >&2
}

repo=""
pr=""
since=""
author=""
heading=""
include_review=false

while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--pr|--since|--author|--heading)
      if [ $# -lt 2 ]; then
        echo "assert-pr-comment-delivered.sh: $1 requires a value" >&2
        usage
        exit 2
      fi
      case "$1" in
        --repo) repo="$2" ;;
        --pr) pr="$2" ;;
        --since) since="$2" ;;
        --author) author="$2" ;;
        --heading) heading="$2" ;;
      esac
      shift 2 ;;
    --include-review-comments) include_review=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "assert-pr-comment-delivered.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "assert-pr-comment-delivered.sh: --repo must be OWNER/REPO" >&2
  usage
  exit 2
fi
if ! [[ "$pr" =~ ^[0-9]+$ ]]; then
  echo "assert-pr-comment-delivered.sh: --pr must be a pull request number" >&2
  usage
  exit 2
fi
if ! [[ "$since" =~ ^[0-9]+$ ]]; then
  echo "assert-pr-comment-delivered.sh: --since must be a Unix timestamp" >&2
  usage
  exit 2
fi
for tool in gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "assert-pr-comment-delivered.sh: $tool not found on PATH" >&2
    exit 2
  fi
done

emit() { # emit <status> <delivered> <issue-scanned> <issue-matched> <review-scanned> <review-matched> [issue-row]
  echo "=== PR COMMENT DELIVERY ==="
  echo "REPO=$repo"
  echo "PR=$pr"
  echo "SINCE=$since"
  echo "AUTHOR_FILTER=${author:-any}"
  echo "HEADING_FILTER=${heading:-none}"
  echo "ISSUE_COMMENTS_SCANNED=$3"
  echo "ISSUE_COMMENTS_MATCHED=$4"
  echo "REVIEW_COMMENTS_SCANNED=$5"
  echo "REVIEW_COMMENTS_MATCHED=$6"
  echo "DELIVERED=$2"
  echo "STATUS=$1"
  if [ -n "${7:-}" ]; then
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - $7"
  else
    echo "ISSUE_COUNT=0"
  fi
  echo "=== END PR COMMENT DELIVERY ==="
}

# fetch <endpoint> — every item on every page, one compact JSON object per line.
fetch() {
  gh api --paginate "$1" --jq '.[] | {created_at, login: .user.login, body: (.body // "")} | @json'
}

# count <ndjson> <apply-heading:true|false> — "<scanned> <matched>".
count() {
  local use_heading="$2"
  jq -rs --argjson since "$since" --arg author "$author" --arg heading "$heading" \
    --argjson use_heading "$use_heading" '
      [ .[] | select(.created_at != null) ] as $all
      | [ $all[]
          | select((.created_at | fromdateiso8601) >= $since)
          | select($author == "" or .login == $author)
          | select(($use_heading | not) or $heading == ""
                   or (.body | split("\n") | any(sub("^\\s+"; "") | startswith($heading))))
        ] as $hit
      | "\($all | length) \($hit | length)"' <<< "$1"
}

errf="$(mktemp)"
trap 'rm -f "$errf"' EXIT

if ! issue_json=$(fetch "repos/$repo/issues/$pr/comments?per_page=100" 2>"$errf"); then
  emit ERROR unknown unknown unknown unknown unknown \
    "SEVERITY=ERROR TYPE=api_unreadable MSG=could not list issue comments on PR #$pr: $(head -1 "$errf")"
  exit 2
fi
read -r issue_scanned issue_matched <<< "$(count "$issue_json" true)"

review_scanned="skipped"
review_matched="skipped"
if [ "$include_review" = "true" ]; then
  if ! review_json=$(fetch "repos/$repo/pulls/$pr/comments?per_page=100" 2>"$errf"); then
    emit ERROR unknown "$issue_scanned" "$issue_matched" unknown unknown \
      "SEVERITY=ERROR TYPE=api_unreadable MSG=could not list review comments on PR #$pr: $(head -1 "$errf")"
    exit 2
  fi
  read -r review_scanned review_matched <<< "$(count "$review_json" false)"
fi

total=$issue_matched
[ "$review_matched" != "skipped" ] && total=$((total + review_matched))

if [ "$total" -gt 0 ]; then
  emit OK true "$issue_scanned" "$issue_matched" "$review_scanned" "$review_matched"
  exit 0
fi

emit ERROR false "$issue_scanned" "$issue_matched" "$review_scanned" "$review_matched" \
  "SEVERITY=ERROR TYPE=deliverable_missing MSG=no matching comment on PR #$pr since the Claude step started; read the uploaded execution transcript for denied tool calls"
exit 1
