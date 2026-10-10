#!/usr/bin/env bash
# Duplicate-issue guard for .github/actions/script-to-issue.
#
# Decides whether a scheduled audit should run, by asking whether its previous
# report is still open. Called from the composite's "Check for existing open
# issue" step; it lives under scripts/ so `test-skill-scripts.yml` runs its
# self-test (scripts/tests/test-script-to-issue-guard.sh) on every change.
#
# The bug this exists for (#2729): the guard used to count EVERY open issue
# carrying the audit's label. The label doubles as a routing tag, so an
# unrelated open issue that carries it (#2696, an on-hold enhancement labelled
# `workflow-model-audit`) switched the monthly audit off for as long as it
# stayed open -- and the skip was silent: a green run that filed nothing.
#
# Two modes:
#
#   label-only    (no --title-prefix)  any open issue carrying LABEL counts.
#                                      The pre-#2729 behaviour, kept for callers
#                                      whose report title is not a fixed string.
#   label+prefix  (--title-prefix P)   only open issues carrying LABEL whose
#                                      title STARTS WITH P count. Others that
#                                      carry the label are listed as ignored.
#
# Usage:
#   bash scripts/script-to-issue-guard.sh --label LABEL [--title-prefix PREFIX]
#
# Outputs:
#   stdout                 === SCRIPT-TO-ISSUE GUARD === block (EXISTS=, MATCHED=, IGNORED=)
#   $GITHUB_OUTPUT         exists=true|false, matched=<comma-separated issue numbers>
#   $GITHUB_STEP_SUMMARY   one paragraph naming the matched (and ignored) issues,
#                          so a skipped run says which issue caused the skip
#
# Exit codes:
#   0 - decided (whether or not a match exists; an empty issue list is exit 0)
#   1 - `gh issue list` failed, or its output was not a JSON array. Failing the
#       step is deliberate: reporting exists=false would file a duplicate, and
#       exists=true would silently skip the audit again.
#   2 - usage error (missing --label, unknown argument, missing dependency)
#
# The prefix arrives as an argument and is matched with `jq --arg`, so it is
# data end to end, never code (.claude/rules/github-actions-security.md).

set -uo pipefail

LABEL=""
TITLE_PREFIX=""

usage() {
  echo "Usage: script-to-issue-guard.sh --label LABEL [--title-prefix PREFIX]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057).
while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      if [ $# -lt 2 ]; then usage; exit 2; fi
      LABEL="$2"; shift 2 ;;
    --title-prefix)
      if [ $# -lt 2 ]; then usage; exit 2; fi
      TITLE_PREFIX="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "script-to-issue-guard.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if [ -z "$LABEL" ]; then
  echo "script-to-issue-guard.sh: --label is required" >&2
  usage
  exit 2
fi

for dep in gh jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "script-to-issue-guard.sh: $dep not found on PATH" >&2
    exit 2
  fi
done

REPO_ARGS=()
if [ -n "${GITHUB_REPOSITORY:-}" ]; then REPO_ARGS=(--repo "$GITHUB_REPOSITORY"); fi

# --limit 100: the default page is 30, and in label+prefix mode a report could
# sit past a page of label-carrying non-reports (.claude/rules/gh-json-fields.md).
if ! ISSUES_JSON="$(gh issue list "${REPO_ARGS[@]}" --label "$LABEL" --state open \
    --limit 100 --json number,title)"; then
  echo "script-to-issue-guard.sh: gh issue list failed for label '$LABEL'" >&2
  exit 1
fi

if ! printf '%s' "${ISSUES_JSON:-[]}" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "script-to-issue-guard.sh: gh issue list did not return a JSON array" >&2
  exit 1
fi

# startswith("") is true for every title, so label-only mode is the same filter
# with an empty prefix -- one code path, no divergence between the two modes.
MATCHED="$(printf '%s' "${ISSUES_JSON:-[]}" | jq -r --arg p "$TITLE_PREFIX" \
  '[.[] | select((.title // "") | startswith($p)) | .number] | sort | map(tostring) | join(",")')"
IGNORED="$(printf '%s' "${ISSUES_JSON:-[]}" | jq -r --arg p "$TITLE_PREFIX" \
  '[.[] | select((.title // "") | startswith($p) | not) | .number] | sort | map(tostring) | join(",")')"

if [ -n "$MATCHED" ]; then EXISTS=true; else EXISTS=false; fi

if [ -n "$TITLE_PREFIX" ]; then MODE="label+prefix"; else MODE="label-only"; fi

echo "=== SCRIPT-TO-ISSUE GUARD ==="
echo "LABEL=$LABEL"
echo "MODE=$MODE"
echo "EXISTS=$EXISTS"
echo "MATCHED=$MATCHED"
echo "IGNORED=$IGNORED"
echo "=== END SCRIPT-TO-ISSUE GUARD ==="

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "exists=$EXISTS"
    echo "matched=$MATCHED"
  } >> "$GITHUB_OUTPUT"
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  as_refs() { printf '%s' "$1" | sed -e 's/^/#/' -e 's/,/, #/g'; }
  if [ -n "$TITLE_PREFIX" ]; then
    KEY="label \`$LABEL\` and a title starting \`$TITLE_PREFIX\`"
  else
    KEY="label \`$LABEL\`"
  fi
  {
    echo "### script-to-issue duplicate guard"
    echo
    if [ "$EXISTS" = true ]; then
      echo "Skipped: open issue(s) with $KEY already exist: $(as_refs "$MATCHED")."
      echo "Close them to let the next scheduled run file a new report."
    else
      echo "No open issue with $KEY; the audit runs."
    fi
    if [ -n "$IGNORED" ]; then
      echo
      echo "Ignored (carry the label, but the title is not a report): $(as_refs "$IGNORED")."
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

exit 0
