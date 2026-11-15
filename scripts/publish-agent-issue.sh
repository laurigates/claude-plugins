#!/usr/bin/env bash
# Publish the issue body a Claude workflow step wrote to a file: find or create
# the issue once, apply its labels and assignee, and read them back.
#
# Background (#2769, #2720). When a Claude step runs `gh issue create` itself,
# the agent both writes the report and posts it. On github.com,
# `gh issue create --assignee` files the issue and then assigns it in a second
# `replaceActorsForAssignable` call; when that call fails, gh exits non-zero
# without printing the URL. The changelog-review agent saw a failure, retried,
# and filed every tracking issue twice (#2656/#2657, #2711/#2712), then recorded
# labels it had never applied. laurigates/.github#70 split that workflow: the
# agent writes the body to a file, a bash step publishes it. This script is that
# bash step for the workflows in this repo whose Claude step filed an issue.
#
# What it guarantees:
#   - One issue per title. An open issue titled exactly --title is reused, so a
#     re-run after a partial failure does not file a second one.
#   - The create carries no labels and no assignee, so it is a single API call
#     that either files the issue or does not.
#   - A failed create is never retried. The script re-reads the open issues, and
#     an issue that appeared anyway (created, then the response was lost) is
#     adopted; otherwise the step fails.
#   - Labels and assignees are applied through REST and READ BACK. The output
#     reports what the issue carries, not what was requested. A missing label is
#     an ERROR (the label is what scripts/assert-issue-filed.sh and the
#     supersede logic key on); a missing assignee is a WARN.
#
# Usage:
#   bash scripts/publish-agent-issue.sh --repo OWNER/REPO --title TITLE \
#     --body-file PATH [--label "a,b"] [--assignee LOGIN] \
#     [--processing TEXT] [--optional]
#
#   --label TEXT        Comma-separated labels, the same shape as
#                       `gh issue create --label` (scripts/check-workflow-labels.sh
#                       reads this flag to pair it with label provisioning).
#                       Repeatable.
#   --assignee LOGIN    Repeatable.
#   --processing TEXT   Appended to the body after a blank line: the report's
#                       `## Processing` section (docs/issue-lifecycle.md). The
#                       workflow supplies it, so the agent's file need not.
#   --optional          A missing or empty body file means the agent had nothing
#                       to report: exit 0 with ACTION=skipped. Without this flag
#                       a missing body is an ERROR.
#
# Output follows .claude/rules/structured-script-output.md
# (=== AGENT ISSUE PUBLISH === / ACTION= / STATUS= / ISSUE_COUNT=). When
# GITHUB_OUTPUT is set, `action`, `number` and `url` are also written there.
#
# Exit codes:
#   0 - published (or skipped under --optional); a missing assignee is a WARN
#   1 - nothing published, or a label did not stick
#   2 - usage error

set -uo pipefail

usage() {
  echo "Usage: publish-agent-issue.sh --repo OWNER/REPO --title TITLE --body-file PATH [--label a,b] [--assignee LOGIN] [--processing TEXT] [--optional]" >&2
}

repo=""
title=""
body_file=""
processing=""
optional=false
labels=()
assignees=()

while [ $# -gt 0 ]; do
  case "$1" in
    --repo|--title|--body-file|--label|--assignee|--processing)
      if [ $# -lt 2 ]; then
        echo "publish-agent-issue.sh: $1 requires a value" >&2
        usage
        exit 2
      fi
      case "$1" in
        --repo) repo="$2" ;;
        --title) title="$2" ;;
        --body-file) body_file="$2" ;;
        --processing) processing="$2" ;;
        --label)
          IFS=',' read -r -a parts <<<"$2"
          for p in "${parts[@]}"; do
            p="${p#"${p%%[![:space:]]*}"}"
            p="${p%"${p##*[![:space:]]}"}"
            [ -n "$p" ] && labels+=("$p")
          done ;;
        --assignee) assignees+=("$2") ;;
      esac
      shift 2 ;;
    --optional) optional=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "publish-agent-issue.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if ! [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "publish-agent-issue.sh: --repo must be OWNER/REPO" >&2
  usage
  exit 2
fi
if [ -z "${title//[[:space:]]/}" ]; then
  echo "publish-agent-issue.sh: --title is required" >&2
  usage
  exit 2
fi
if [ -z "$body_file" ]; then
  echo "publish-agent-issue.sh: --body-file is required" >&2
  usage
  exit 2
fi
for l in "${labels[@]+"${labels[@]}"}"; do
  if ! [[ "$l" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
    echo "publish-agent-issue.sh: label '$l' must match [A-Za-z0-9_.:-]+" >&2
    exit 2
  fi
done
for a in "${assignees[@]+"${assignees[@]}"}"; do
  if ! [[ "$a" =~ ^[A-Za-z0-9-]+$ ]]; then
    echo "publish-agent-issue.sh: assignee '$a' is not a GitHub login" >&2
    exit 2
  fi
done
for tool in gh jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "publish-agent-issue.sh: $tool not found on PATH" >&2
    exit 2
  fi
done

join_csv() { local IFS=,; echo "$*"; }
labels_csv="$(join_csv "${labels[@]+"${labels[@]}"}")"
assignees_csv="$(join_csv "${assignees[@]+"${assignees[@]}"}")"

action="none"
number=""
url=""
labels_applied=""
assignees_applied=""
rows=()   # "SEVERITY=... TYPE=... MSG=..."

emit() { # emit <status>
  local status="$1"
  echo "=== AGENT ISSUE PUBLISH ==="
  echo "REPO=$repo"
  echo "TITLE=$title"
  echo "ACTION=$action"
  echo "ISSUE_NUMBER=$number"
  echo "ISSUE_URL=$url"
  echo "LABELS_REQUESTED=$labels_csv"
  echo "LABELS_APPLIED=$labels_applied"
  echo "ASSIGNEES_REQUESTED=$assignees_csv"
  echo "ASSIGNEES_APPLIED=$assignees_applied"
  echo "STATUS=$status"
  if [ "$status" != "OK" ]; then
    local first="" row
    for row in "${rows[@]}"; do
      case "$row" in "SEVERITY=$status "*) first="$row"; break ;; esac
    done
    local rtype="${first#*TYPE=}"; rtype="${rtype%% *}"
    local rmsg="${first#* MSG=}"
    local reason
    reason="$(printf '%s: %s' "$rtype" "$rmsg" | tr -s '[:space:]' ' ' | cut -c1-180)"
    if [ "${#rows[@]}" -gt 1 ]; then reason="$reason (+$(( ${#rows[@]} - 1 )) more)"; fi
    echo "REASON=$reason"
  fi
  echo "ISSUE_COUNT=${#rows[@]}"
  if [ "${#rows[@]}" -gt 0 ]; then
    echo "ISSUES:"
    for row in "${rows[@]}"; do echo "  - $row"; done
  fi
  echo "=== END AGENT ISSUE PUBLISH ==="
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
      echo "action=$action"
      echo "number=$number"
      echo "url=$url"
    } >> "$GITHUB_OUTPUT"
  fi
}

# --- The body -----------------------------------------------------------------
# A body that is missing or blank is the agent saying it had nothing to file
# (research-radar in a quiet week) or that it failed before writing one.
if [ ! -f "$body_file" ] || ! grep -q '[^[:space:]]' "$body_file"; then
  if [ "$optional" = true ]; then
    action="skipped"
    emit OK
    exit 0
  fi
  rows+=("SEVERITY=ERROR TYPE=body_missing MSG=the Claude step wrote no body to $body_file, so there is nothing to publish; read the uploaded execution transcript")
  emit ERROR
  exit 1
fi

work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then
  echo "publish-agent-issue.sh: mktemp -d failed" >&2
  exit 2
fi
trap 'rm -rf "$work"' EXIT

# The agent's file is copied, never edited in place.
cp "$body_file" "$work/body.md"
if [ -n "$processing" ]; then
  printf '\n\n%s\n' "$processing" >> "$work/body.md"
fi

# --- Find ---------------------------------------------------------------------
# Exact title among OPEN issues (pull requests excluded). Labels are not part of
# the key: an issue left unlabelled by an earlier partial failure must still be
# found.
find_issue() {
  local listing
  if ! listing="$(gh api --paginate "repos/$repo/issues?state=open&per_page=100" \
      --jq '.[] | select(.pull_request == null) | {number, html_url, title} | @json' 2>"$work/find.err")"; then
    return 2
  fi
  jq -rs --arg t "$title" \
    '[.[] | select(.title == $t)] | sort_by(.number) | first // empty | "\(.number) \(.html_url)"' \
    <<<"$listing"
}

if ! found="$(find_issue)"; then
  rows+=("SEVERITY=ERROR TYPE=api_unreadable MSG=could not list open issues: $(head -1 "$work/find.err")")
  emit ERROR
  exit 1
fi

if [ -n "$found" ]; then
  action="reused"
  number="${found%% *}"
  url="${found#* }"
else
  # --- Create, once -----------------------------------------------------------
  jq -n --arg title "$title" --rawfile body "$work/body.md" '{title: $title, body: $body}' > "$work/create.json"
  if created="$(gh api -X POST "repos/$repo/issues" --input "$work/create.json" \
      --jq '"\(.number) \(.html_url)"' 2>"$work/create.err")" && [ -n "$created" ]; then
    action="created"
    number="${created%% *}"
    url="${created#* }"
  else
    # No retry: a create that failed after filing would duplicate. Look again.
    if found="$(find_issue)" && [ -n "$found" ]; then
      action="created"
      number="${found%% *}"
      url="${found#* }"
      rows+=("SEVERITY=WARN TYPE=create_response_lost MSG=the create call failed ($(head -1 "$work/create.err")) but issue #$number exists, so it was adopted rather than filed again")
    else
      rows+=("SEVERITY=ERROR TYPE=create_failed MSG=the create call failed and no open issue titled '$title' exists: $(head -1 "$work/create.err")")
      emit ERROR
      exit 1
    fi
  fi
fi

# --- Metadata, applied then read back -----------------------------------------
if [ "${#labels[@]}" -gt 0 ]; then
  jq -n '{labels: $ARGS.positional}' --args "${labels[@]}" > "$work/labels.json"
  if ! gh api -X POST "repos/$repo/issues/$number/labels" --input "$work/labels.json" \
      --jq '.[].name' >/dev/null 2>"$work/labels.err"; then
    echo "publish-agent-issue.sh: adding labels failed: $(head -1 "$work/labels.err")" >&2
  fi
fi
if [ "${#assignees[@]}" -gt 0 ]; then
  jq -n '{assignees: $ARGS.positional}' --args "${assignees[@]}" > "$work/assignees.json"
  if ! gh api -X POST "repos/$repo/issues/$number/assignees" --input "$work/assignees.json" \
      --jq '.number' >/dev/null 2>"$work/assignees.err"; then
    echo "publish-agent-issue.sh: adding assignees failed: $(head -1 "$work/assignees.err")" >&2
  fi
fi

if ! readback="$(gh api "repos/$repo/issues/$number" \
    --jq '{labels: [.labels[].name], assignees: [.assignees[].login]} | @json' 2>"$work/read.err")"; then
  rows+=("SEVERITY=ERROR TYPE=readback_failed MSG=issue #$number was published but its labels could not be read back: $(head -1 "$work/read.err")")
  emit ERROR
  exit 1
fi
labels_applied="$(jq -r '.labels | join(",")' <<<"$readback")"
assignees_applied="$(jq -r '.assignees | join(",")' <<<"$readback")"

for l in "${labels[@]+"${labels[@]}"}"; do
  if ! jq -e --arg l "$l" '.labels | index($l)' <<<"$readback" >/dev/null; then
    rows+=("SEVERITY=ERROR TYPE=label_missing MSG=issue #$number does not carry label '$l' after it was applied")
  fi
done
for a in "${assignees[@]+"${assignees[@]}"}"; do
  if ! jq -e --arg a "$a" '.assignees | index($a)' <<<"$readback" >/dev/null; then
    rows+=("SEVERITY=WARN TYPE=assignee_missing MSG=issue #$number is not assigned to '$a' after the assignment call")
  fi
done

status="OK"
for row in "${rows[@]+"${rows[@]}"}"; do
  case "$row" in
    SEVERITY=ERROR*) status="ERROR" ;;
    SEVERITY=WARN*) [ "$status" = "OK" ] && status="WARN" ;;
  esac
done

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  echo "Published issue #$number ($action): $url" >> "$GITHUB_STEP_SUMMARY"
fi

emit "$status"
[ "$status" = "ERROR" ] && exit 1
exit 0
