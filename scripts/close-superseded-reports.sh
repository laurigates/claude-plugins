#!/usr/bin/env bash
# Close the earlier reports a periodic audit has just superseded (#3346).
#
# Lifecycle (docs/issue-lifecycle.md): a monthly report closes when the next
# month's report opens, and the new report carries forward the items that are
# still open. Before this, the duplicate guard skipped a run while the previous
# report stayed open, so an unprocessed report blocked every later one.
#
# Two modes:
#
#   default   The current report (an open issue titled exactly --current-title)
#             must exist. Every other open issue carrying LABEL whose title
#             starts with --title-prefix is closed with a comment naming the
#             current report. If the current report is missing (the create was
#             denied, or filed under another title) nothing is closed and the
#             script exits 1, so last month's findings are not lost with it.
#   --clean   The audit ran and found nothing, so no current report exists.
#             Earlier reports are closed with a comment saying so.
#
# Issues that carry the label but not the title prefix (routing tags, #2729)
# are never touched.
#
# Usage:
#   bash scripts/close-superseded-reports.sh --label LABEL --title-prefix PREFIX \
#     --current-title TITLE [--clean]
#
# Exit codes: 0 done (including nothing to close), 1 gh failure or missing
# current report, 2 usage error.

set -uo pipefail

LABEL=""
TITLE_PREFIX=""
CURRENT_TITLE=""
CLEAN=false

usage() {
  echo "Usage: close-superseded-reports.sh --label LABEL --title-prefix PREFIX --current-title TITLE [--clean]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      if [ $# -lt 2 ]; then usage; exit 2; fi
      LABEL="$2"; shift 2 ;;
    --title-prefix)
      if [ $# -lt 2 ]; then usage; exit 2; fi
      TITLE_PREFIX="$2"; shift 2 ;;
    --current-title)
      if [ $# -lt 2 ]; then usage; exit 2; fi
      CURRENT_TITLE="$2"; shift 2 ;;
    --clean) CLEAN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "close-superseded-reports.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if [ -z "$LABEL" ] || [ -z "$TITLE_PREFIX" ] || [ -z "$CURRENT_TITLE" ]; then
  echo "close-superseded-reports.sh: --label, --title-prefix and --current-title are required" >&2
  usage
  exit 2
fi

for dep in gh jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "close-superseded-reports.sh: $dep not found on PATH" >&2
    exit 2
  fi
done

REPO_ARGS=()
if [ -n "${GITHUB_REPOSITORY:-}" ]; then REPO_ARGS=(--repo "$GITHUB_REPOSITORY"); fi

if ! ISSUES_JSON="$(gh issue list "${REPO_ARGS[@]}" --label "$LABEL" --state open \
    --limit 100 --json number,title)"; then
  echo "close-superseded-reports.sh: gh issue list failed for label '$LABEL'" >&2
  exit 1
fi
if ! printf '%s' "${ISSUES_JSON:-[]}" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "close-superseded-reports.sh: gh issue list did not return a JSON array" >&2
  exit 1
fi

# The newest issue with the exact current title is the report that supersedes.
CURRENT="$(printf '%s' "$ISSUES_JSON" | jq -r --arg c "$CURRENT_TITLE" \
  '[.[] | select(.title == $c) | .number] | max // empty')"
EARLIER="$(printf '%s' "$ISSUES_JSON" | jq -r --arg p "$TITLE_PREFIX" --arg c "$CURRENT_TITLE" \
  '[.[] | select((.title // "") | startswith($p)) | select(.title != $c) | .number] | sort | .[] | tostring')"

if [ "$CLEAN" = false ] && [ -z "$CURRENT" ]; then
  echo "close-superseded-reports.sh: no open issue titled '$CURRENT_TITLE' carries '$LABEL'; closing nothing" >&2
  echo "=== CLOSE SUPERSEDED REPORTS ==="
  echo "CURRENT="
  echo "CLOSED="
  echo "=== END CLOSE SUPERSEDED REPORTS ==="
  exit 1
fi

if [ "$CLEAN" = true ]; then
  COMMENT="The '$CURRENT_TITLE' run found nothing to report, so this report is closed: nothing in it is still detected. Lifecycle: docs/issue-lifecycle.md."
else
  COMMENT="Superseded by #$CURRENT, which carries forward the items from this report that are still open. Lifecycle: docs/issue-lifecycle.md."
fi

CLOSED=()
FAILED=0
while IFS= read -r num; do
  [ -n "$num" ] || continue
  if gh issue close "$num" "${REPO_ARGS[@]}" --comment "$COMMENT"; then
    CLOSED+=("$num")
  else
    echo "close-superseded-reports.sh: failed to close #$num" >&2
    FAILED=1
  fi
done <<<"$EARLIER"

CLOSED_CSV="$(IFS=,; echo "${CLOSED[*]}")"
echo "=== CLOSE SUPERSEDED REPORTS ==="
echo "CURRENT=$CURRENT"
echo "CLOSED=$CLOSED_CSV"
echo "=== END CLOSE SUPERSEDED REPORTS ==="

if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ -n "$CLOSED_CSV" ]; then
  {
    echo "### Superseded reports closed"
    echo
    echo "#${CLOSED_CSV//,/, #}"
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit "$FAILED"
