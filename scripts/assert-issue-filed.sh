#!/usr/bin/env bash
# Assert that a Claude workflow step actually filed its GitHub issue.
#
# Background (#2731). Three Claude workflows file one issue as their ONLY
# deliverable: golden-set-evaluation.yml (label golden-set-eval),
# scheduled-audits.yml agentic-audit (label agentic-audit) and
# workflow-model-audit.yml (label workflow-model-audit). The SDK exits 0 on a
# denied `gh issue create`, so a run that files nothing is green:
# workflow-model-audit.yml filed nothing in six runs before #2630, and the
# 2026-08-15 golden-set run filed nothing after 7 denials. This helper is the
# same-run post-step gate, the issue-filing sibling of
# scripts/assert-pr-comment-delivered.sh: it counts the issues carrying the
# deliverable label that were created since the Claude step started, and fails
# when there are none.
#
# Time-bounded on purpose: last month's report carries the same label, and
# --state all keeps an issue closed during the run countable.
#
# Usage:
#   bash scripts/assert-issue-filed.sh --repo OWNER/REPO --label LABEL \
#     --since EPOCH [--title-prefix TEXT]
#
#   --since EPOCH          Count only issues created at/after this Unix time
#                          (record it in a step before the Claude step).
#   --title-prefix TEXT    Count only issues whose title starts with TEXT, for a
#                          label that other chores share.
#
# Output follows .claude/rules/structured-script-output.md
# (=== ISSUE FILED === / FILED= / STATUS= / ISSUE_COUNT=). ISSUES_SCANNED= and
# ISSUES_MATCHED= count GitHub issues; ISSUE_COUNT= counts this script's findings.
#
# Exit codes:
#   0 - at least one matching issue was filed
#   1 - nothing was filed
#   2 - usage error, or the API could not be read (FILED=unknown)

set -euo pipefail

usage() {
  echo "Usage: assert-issue-filed.sh --repo OWNER/REPO --label LABEL --since EPOCH [--title-prefix TEXT]" >&2
}

repo=""
label=""
since=""
title_prefix=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--label|--since|--title-prefix)
      if [ $# -lt 2 ]; then
        echo "assert-issue-filed.sh: $1 requires a value" >&2
        usage
        exit 2
      fi
      case "$1" in
        --repo) repo="$2" ;;
        --label) label="$2" ;;
        --since) since="$2" ;;
        --title-prefix) title_prefix="$2" ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "assert-issue-filed.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "assert-issue-filed.sh: --repo must be OWNER/REPO" >&2
  usage
  exit 2
fi
# The label goes into a query string unencoded, so only URL-safe label names.
if ! [[ "$label" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
  echo "assert-issue-filed.sh: --label must match [A-Za-z0-9_.:-]+" >&2
  usage
  exit 2
fi
if ! [[ "$since" =~ ^[0-9]+$ ]]; then
  echo "assert-issue-filed.sh: --since must be a Unix timestamp" >&2
  usage
  exit 2
fi
for tool in gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "assert-issue-filed.sh: $tool not found on PATH" >&2
    exit 2
  fi
done

emit() { # emit <status> <filed> <scanned> <matched> <numbers> [finding-row]
  echo "=== ISSUE FILED ==="
  echo "REPO=$repo"
  echo "LABEL=$label"
  echo "SINCE=$since"
  echo "TITLE_PREFIX_FILTER=${title_prefix:-none}"
  echo "ISSUES_SCANNED=$3"
  echo "ISSUES_MATCHED=$4"
  echo "FILED_ISSUES=${5:-none}"
  echo "FILED=$2"
  echo "STATUS=$1"
  if [ -n "${6:-}" ]; then
    local row="$6"
    local rtype="${row#*TYPE=}"; rtype="${rtype%% *}"
    local rmsg="${row#* MSG=}"
    echo "REASON=$(printf '%s: %s' "$rtype" "$rmsg" | cut -c1-200)"
    echo "ISSUE_COUNT=1"
    echo "ISSUES:"
    echo "  - $row"
  else
    echo "ISSUE_COUNT=0"
  fi
  echo "=== END ISSUE FILED ==="
}

errf="$(mktemp)"
trap 'rm -f "$errf"' EXIT

# The issues endpoint also returns pull requests; the `since` query bounds
# updated_at (>= created_at), so it only trims the scan and never drops a match.
since_iso=$(jq -rn --argjson s "$since" '$s | todate')
endpoint="repos/$repo/issues?labels=$label&state=all&since=$since_iso&per_page=100"
if ! items=$(gh api --paginate "$endpoint" \
    --jq '.[] | {number, created_at, title: (.title // ""), is_pr: (.pull_request != null)} | @json' 2>"$errf"); then
  emit ERROR unknown unknown unknown "" \
    "SEVERITY=ERROR TYPE=api_unreadable MSG=could not list issues labelled $label: $(head -1 "$errf")"
  exit 2
fi

read -r scanned matched numbers <<< "$(jq -rs --argjson since "$since" --arg prefix "$title_prefix" '
  [ .[] | select(.created_at != null) ] as $all
  | [ $all[]
      | select(.is_pr | not)
      | select((.created_at | fromdateiso8601) >= $since)
      | select($prefix == "" or (.title | startswith($prefix)))
    ] as $hit
  | "\($all | length) \($hit | length) \([$hit[].number | tostring] | join(","))"' <<< "$items")"

if [ "$matched" -gt 0 ]; then
  emit OK true "$scanned" "$matched" "$numbers"
  exit 0
fi

emit ERROR false "$scanned" "$matched" "" \
  "SEVERITY=ERROR TYPE=deliverable_missing MSG=no issue labelled $label was created since the Claude step started; read the uploaded execution transcript for denied tool calls"
exit 1
