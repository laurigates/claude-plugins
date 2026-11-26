#!/usr/bin/env bash
# issue-flow.sh — measure an issue tracker's inflow against its outflow.
# DATA-ONLY: reads search counts and the open-issue list; performs NO mutations.
#
# Usage: bash issue-flow.sh [--repo owner/name] [--days N] [--label-cap N]
#          [--label-pattern ERE]   (cap only labels matching ERE, e.g. '^(build|area):')
#
# Emits, per .claude/rules/structured-script-output.md:
#   OPEN_TOTAL               open issues now (PRs excluded)
#   OPENED_WINDOW            issues created in the last N days
#   CLOSED_WINDOW            issues closed in the last N days
#   CLOSED_NOT_PLANNED_WINDOW  the part of CLOSED_WINDOW closed as not planned
#   NET_WINDOW               OPENED_WINDOW - CLOSED_WINDOW (positive = growing)
#   LABEL_<name>=<count>     open issues per label, only labels above --label-cap
#   LABELS_OVER_CAP          how many labels are above the cap
#
# Every count comes from the REST search and issues endpoints, never GraphQL,
# so it works where GraphQL answers 403 (cloud sessions). Pages are walked with
# an explicit &page=N loop that stops on a short page, not `gh api --paginate`.
#
# Test seam: ISSUE_FLOW_GH names the gh binary (a stub in the tests).

set -uo pipefail

gh_bin="${ISSUE_FLOW_GH:-gh}"
repo=""
days=28
label_cap=20
label_pattern=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --days) days="${2:-}"; shift 2 ;;
    --label-cap) label_cap="${2:-}"; shift 2 ;;
    --label-pattern) label_pattern="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

issues=()
add_issue() { issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3"); }

finish() {
  local status="$1"
  echo "STATUS=${status}"
  if [ "$status" != "OK" ] && [ ${#issues[@]} -gt 0 ]; then
    local first="${issues[0]}"
    local type="${first#*TYPE=}"; type="${type%% *}"
    local msg="${first#*MSG=}"
    local extra=""
    [ ${#issues[@]} -gt 1 ] && extra=" (+$(( ${#issues[@]} - 1 )) more)"
    echo "REASON=${type}: ${msg:0:150}${extra}"
  fi
  echo "ISSUE_COUNT=${#issues[@]}"
  if [ ${#issues[@]} -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
  fi
  echo "=== END ISSUE FLOW ==="
  exit 0
}

echo "=== ISSUE FLOW ==="

case "$days$label_cap" in
  *[!0-9]*|"") add_issue ERROR bad_argument "--days and --label-cap take whole numbers"; finish ERROR ;;
esac

if [ -z "$repo" ]; then
  url="$(git remote get-url origin 2>/dev/null || true)"
  repo="$(printf '%s' "$url" | sed -E 's#^(https://[^/]+/|git@[^:]+:)##; s#\.git$##')"
fi
case "$repo" in
  */*) ;;
  *) add_issue ERROR no_repo "pass --repo owner/name or run inside a clone with an origin remote"; finish ERROR ;;
esac

since="$(date -u -d "-${days} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${days}"d +%Y-%m-%d)"
echo "REPO=${repo}"
echo "WINDOW_DAYS=${days}"
echo "SINCE=${since}"

count() {
  local out
  out="$("$gh_bin" api -X GET search/issues -f q="repo:${repo} is:issue $1" --jq .total_count 2>/dev/null)"
  case "$out" in
    ''|*[!0-9]*) echo "unknown" ;;
    *) echo "$out" ;;
  esac
}

open_total="$(count "is:open")"
opened="$(count "created:>=${since}")"
closed="$(count "is:closed closed:>=${since}")"
not_planned="$(count "is:closed closed:>=${since} reason:\"not planned\"")"

echo "OPEN_TOTAL=${open_total}"
echo "OPENED_WINDOW=${opened}"
echo "CLOSED_WINDOW=${closed}"
echo "CLOSED_NOT_PLANNED_WINDOW=${not_planned}"

for k in open_total opened closed not_planned; do
  [ "${!k}" = "unknown" ] && add_issue WARN count_unknown "search count for ${k} could not be read"
done

if [ "$opened" != "unknown" ] && [ "$closed" != "unknown" ]; then
  echo "NET_WINDOW=$(( opened - closed ))"
else
  echo "NET_WINDOW=unknown"
fi

# Open issues per label, from the issues endpoint (entries with pull_request are PRs).
labels_tmp="$(mktemp)"
trap 'rm -f "$labels_tmp"' EXIT
page=1
list_ok=true
while :; do
  body="$("$gh_bin" api "repos/${repo}/issues?state=open&per_page=100&page=${page}" 2>/dev/null)" || { list_ok=false; break; }
  n="$(printf '%s' "$body" | jq 'length' 2>/dev/null)" || { list_ok=false; break; }
  printf '%s' "$body" | jq -r '.[] | select(has("pull_request") | not) | .labels[].name' >>"$labels_tmp"
  [ "$n" -lt 100 ] && break
  page=$(( page + 1 ))
done

over=0
if $list_ok; then
  while read -r c name; do
    [ -z "$name" ] && continue
    if [ -n "$label_pattern" ] && ! grep -Eq -- "$label_pattern" <<<"$name"; then continue; fi
    if [ "$c" -gt "$label_cap" ]; then
      key="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9\n' '_')"
      echo "LABEL_${key}=${c}"
      over=$(( over + 1 ))
    fi
  done < <(sort "$labels_tmp" | uniq -c | sort -rn)
  echo "LABELS_OVER_CAP=${over}"
  [ "$over" -gt 0 ] && add_issue WARN label_over_cap "${over} label(s) above ${label_cap} open issues"
else
  echo "LABELS_OVER_CAP=unknown"
  add_issue WARN list_failed "open-issue list could not be read"
fi

if [ "$opened" != "unknown" ] && [ "$closed" != "unknown" ] && [ "$opened" -gt "$closed" ]; then
  add_issue WARN inflow_exceeds_outflow "${opened} opened vs ${closed} closed in ${days} days"
fi

if [ ${#issues[@]} -gt 0 ]; then finish WARN; else finish OK; fi
