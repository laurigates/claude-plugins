#!/usr/bin/env bash
# check-issue-grouping.sh — list open issues that belong to no group.
#
# THE CONVENTION (.claude/rules/issue-grouping.md)
# Related issues are grouped under an `epic` tracking issue (as native
# sub-issues) or a milestone, so an agent implements a group together instead
# of opening one PR per issue that later have to be reconciled. An open issue
# with no parent issue and no milestone is "ungrouped": nothing tells the next
# agent which siblings its change has to stay compatible with.
#
# WHAT IT REPORTS
# One WARN row per open issue that has no `parent_issue_url`, no milestone, and
# matches no entry in scripts/issue-grouping-exempt.txt (recurring machine-filed
# and feedback issues, plus the epics themselves). Pull requests are skipped.
# Advisory: findings exit 0 with STATUS=WARN. Only a failed fetch is ERROR.
#
# The daily issue-resolving Routine runs this script to find the issues it
# reports as UNGROUPED (docs/routines/resolve-claude-plugins-issues.md).
#
# Usage:
#   check-issue-grouping.sh [--repo OWNER/REPO] [--exempt-file PATH]
# Repo resolution: --repo, then $GH_REPO, then the `origin` remote URL.
# REST only (`gh api`), paginated by hand with &page=N — no GraphQL, so it runs
# where GraphQL is blocked.
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
# ISSUES_FETCHED= counts GitHub issues; ISSUE_COUNT= counts this script's findings.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXEMPT_FILE="$ROOT_DIR/scripts/issue-grouping-exempt.txt"
REPO="${GH_REPO:-}"
MAX_PAGES=20

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --exempt-file) EXEMPT_FILE="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,27p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

emit_error() {
    # emit_error TYPE MSG — the fetch-failure report, then exit 1.
    local err_type="$1" msg="$2"
    echo "=== ISSUE GROUPING ==="
    echo "REPO=${REPO:-unknown}"
    echo "STATUS=ERROR"
    echo "REASON=$(printf '%s: %s' "$err_type" "$msg" | tr -s '[:space:]' ' ' | cut -c1-180)"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - SEVERITY=ERROR TYPE=$err_type MSG=$msg"
    echo "=== END ISSUE GROUPING ==="
    exit 1
}

if [ -z "$REPO" ]; then
    origin_url="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
    REPO="$(printf '%s' "$origin_url" | sed -E 's#^(git@[^:]+:|[a-z]+://([^@/]+@)?[^/]+/)##; s#\.git$##; s#/$##')"
    case "$REPO" in */*) ;; *) REPO="" ;; esac
fi
[ -n "$REPO" ] || emit_error repo_unresolved "pass --repo OWNER/REPO or set GH_REPO"
[ -f "$EXEMPT_FILE" ] || emit_error exempt_file_missing "no exempt list at ${EXEMPT_FILE#"$ROOT_DIR"/}"
command -v jq >/dev/null 2>&1 || emit_error jq_missing "jq is required"

# Exempt list -> two JSON arrays for jq.
exempt_labels="$(awk '$1 == "label" { sub(/^label[ \t]+/, ""); print }' "$EXEMPT_FILE" | jq -R . | jq -sc .)"
exempt_titles="$(awk '$1 == "title" { sub(/^title[ \t]+/, ""); print }' "$EXEMPT_FILE" | jq -R . | jq -sc .)"

# Fetch every open issue (the endpoint also returns PRs; filtered below). Each
# page is slimmed to the fields used here before accumulating, so no page body
# is ever passed as a command-line argument (MAX_ARG_STRLEN is 128 KiB).
work="$(mktemp -d)" || emit_error mktemp_failed "mktemp -d failed"
# shellcheck disable=SC2015  # the sandbox-guard shape check-git-sandbox-guards.sh expects
[ -n "$work" ] && [ -d "$work" ] || emit_error mktemp_failed "bad temp dir"
trap 'rm -rf "$work"' EXIT
: > "$work/items.jsonl"
page=1
while [ "$page" -le "$MAX_PAGES" ]; do
    if ! body="$(gh api "repos/$REPO/issues?state=open&per_page=100&page=$page" 2>&1)"; then
        emit_error fetch_failed "gh api repos/$REPO/issues page $page failed: $(printf '%s' "$body" | head -c 120)"
    fi
    if ! count="$(jq 'length' <<<"$body" 2>/dev/null)"; then
        emit_error fetch_failed "page $page of repos/$REPO/issues is not a JSON array"
    fi
    jq -c '.[] | {number, title, labels: [.labels[].name], pull_request, parent_issue_url, milestone: (.milestone.number // null)}' \
        <<<"$body" >> "$work/items.jsonl"
    [ "$count" -lt 100 ] && break
    page=$((page + 1))
done
if [ "$page" -gt "$MAX_PAGES" ]; then
    emit_error fetch_truncated "more than $((MAX_PAGES * 100)) open items; raise MAX_PAGES"
fi

classified="$(jq -sc --argjson labels "$exempt_labels" --argjson titles "$exempt_titles" '
  [ .[] | select(.pull_request == null)
    | . as $i
    | {
        number,
        title,
        epic:     (.labels | index("epic") != null),
        grouped:  ((.parent_issue_url // null) != null or (.milestone // null) != null),
        exempt:   ((.labels | any(. as $l | $labels | index($l) != null))
                   or ($titles | any(. as $re | $i.title | test($re))))
      } ]' "$work/items.jsonl")"

fetched="$(jq 'length' <<<"$classified")"
epics="$(jq '[.[] | select(.epic)] | length' <<<"$classified")"
grouped="$(jq '[.[] | select(.grouped)] | length' <<<"$classified")"
exempt="$(jq '[.[] | select(.exempt and (.grouped | not))] | length' <<<"$classified")"
mapfile -t rows < <(jq -r '
  [.[] | select((.grouped | not) and (.exempt | not))] | sort_by(.number) | .[]
  | "  - SEVERITY=WARN TYPE=ungrouped_issue ISSUE=\(.number) MSG=#\(.number) \(.title | gsub("[\r\n]+"; " "))"' <<<"$classified")

issue_count="${#rows[@]}"
item_status="OK"
[ "$issue_count" -gt 0 ] && item_status="WARN"

echo "=== ISSUE GROUPING ==="
echo "REPO=$REPO"
echo "ISSUES_FETCHED=$fetched"
echo "EPICS=$epics"
echo "GROUPED=$grouped"
echo "EXEMPT=$exempt"
echo "UNGROUPED=$issue_count"
echo "STATUS=$item_status"
if [ "$issue_count" -gt 0 ]; then
    first_msg="${rows[0]#*MSG=}"
    reason="$(printf 'ungrouped_issue: %s' "$first_msg" | tr -s '[:space:]' ' ' | cut -c1-180)"
    [ "$issue_count" -gt 1 ] && reason="$reason (+$((issue_count - 1)) more)"
    echo "REASON=$reason"
fi
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${rows[@]}"
    echo ""
    echo "FIX: attach each issue to an epic as a sub-issue, or give it a milestone; see .claude/rules/issue-grouping.md"
fi
echo "=== END ISSUE GROUPING ==="
exit 0
