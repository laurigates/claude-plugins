#!/usr/bin/env bash
# GitHub Actions FinOps — deterministic data-gathering for the
# github-actions-finops skill.
#
# Extracts the mechanical procedure that previously lived inline in SKILL.md:
#   - org-level Actions billing fetch (gh api + jq projection)
#   - workflow-run grouping + per-workflow duration aggregation
#   - waste detection (skipped / bot-triggered / high-frequency counts)
#   - threshold comparison (skipped-ratio red flag)
#   - static fix-suggestion lookup per detected waste pattern
#
# Reading workflow YAML for missing concurrency / bot guards, synthesis, and
# any prose recommendation stay with the model — they are not in this script.
#
# Usage:
#   bash github-actions-finops.sh --home-dir <path> --project-dir <path> \
#        [--org <org>] [--repo <owner/name>]
#
# Output: the structured-script-output contract
# (=== GITHUB ACTIONS FINOPS === … STATUS=/ISSUE_COUNT=/ISSUES: …
#  === END GITHUB ACTIONS FINOPS ===), exit 0 on OK/WARN, 1 on ERROR.
#
# Testing seam: set GITHUB_ACTIONS_FINOPS_FIXTURE=<path> to a JSON file shaped
# like the GitHub /actions/runs response ({"workflow_runs":[...]}) optionally
# carrying a top-level "billing" object. The script then runs fully offline,
# making no gh / network call. Without the fixture it queries the live API.
#
# shellcheck disable=SC2016  # jq programs use $ for jq variables, not shell vars

set -uo pipefail

home_dir=""
project_dir=""
finops_org=""
finops_repo=""

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --org) finops_org="$2"; shift 2 ;;
    --repo) finops_repo="$2"; shift 2 ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

fixture_path="${GITHUB_ACTIONS_FINOPS_FIXTURE:-}"

echo "=== GITHUB ACTIONS FINOPS ==="

finops_status="OK"
issue_count=0
issues_list=""

add_issue() {
  # $1 severity, $2 type, $3 message
  issues_list="${issues_list}  - SEVERITY=$1 TYPE=$2 MSG=$3\n"
  issue_count=$((issue_count + 1))
  if [ "$1" = "ERROR" ]; then
    finops_status="ERROR"
  elif [ "$1" = "WARN" ] && [ "$finops_status" = "OK" ]; then
    finops_status="WARN"
  fi
}

emit_trailer() {
  echo "STATUS=${finops_status}"
  echo "ISSUE_COUNT=${issue_count}"
  if [ -n "$issues_list" ]; then
    echo "ISSUES:"
    echo -e "$issues_list" | sed '/^$/d'
  fi
  echo "=== END GITHUB ACTIONS FINOPS ==="
}

# jq is a hard dependency for every projection below.
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  add_issue ERROR missing_tool "jq is required but not installed"
  emit_trailer
  exit 1
fi
echo "JQ_AVAILABLE=true"

# --- Acquire the runs payload (and optional billing) ------------------------
# Fixture seam: a captured JSON file stands in for the gh api response so the
# test suite runs offline. Live mode requires gh.
runs_json=""
billing_json=""

if [ -n "$fixture_path" ]; then
  echo "DATA_SOURCE=fixture"
  if [ ! -f "$fixture_path" ]; then
    echo "FIXTURE_FOUND=false"
    add_issue ERROR fixture_missing "fixture not found at ${fixture_path}"
    emit_trailer
    exit 1
  fi
  if ! jq empty "$fixture_path" >/dev/null 2>&1; then
    echo "FIXTURE_VALID=false"
    add_issue ERROR fixture_invalid "fixture is not valid JSON: ${fixture_path}"
    emit_trailer
    exit 1
  fi
  echo "FIXTURE_VALID=true"
  runs_json=$(jq -c '{workflow_runs: (.workflow_runs // [])}' "$fixture_path")
  billing_json=$(jq -c '.billing // empty' "$fixture_path")
else
  echo "DATA_SOURCE=live"
  if ! command -v gh >/dev/null 2>&1; then
    echo "GH_AVAILABLE=false"
    add_issue ERROR missing_tool "gh CLI is required for live mode but not installed"
    emit_trailer
    exit 1
  fi
  echo "GH_AVAILABLE=true"

  : "${finops_repo:=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)}"
  if [ -z "$finops_repo" ]; then
    add_issue ERROR no_repo_context "no repository context; pass --repo owner/name"
    emit_trailer
    exit 1
  fi
  echo "REPO=${finops_repo}"

  # Org billing fetch (deterministic projection). Admin-gated; absence is not
  # an error — note it and continue.
  #
  # /settings/billing/actions returns HTTP 410 ("This endpoint has been moved")
  # and has done for some time; /settings/billing/usage replaces it. The old
  # flat {included_minutes, total_minutes_used} summary is gone — usage returns
  # one line item per repo x month x SKU, so the totals are summed here.
  #
  # NOTE: the default response is WINDOWED and nothing in the payload says so,
  # so these totals cover whatever slice GitHub returns rather than the year.
  # Pass explicit ?year=&month= when a specific period is needed.
  : "${finops_org:=${finops_repo%%/*}}"
  echo "ORG=${finops_org}"
  billing_json=$(gh api "/orgs/${finops_org}/settings/billing/usage" \
    --jq '{usageItems: [.usageItems[] | select(.product == "actions" and .unitType == "Minutes")]}' \
    2>/dev/null) || billing_json=""

  runs_json=$(gh api "/repos/${finops_repo}/actions/runs?per_page=100" \
    --jq '{workflow_runs: (.workflow_runs // [])}' 2>/dev/null) || runs_json=""
  if [ -z "$runs_json" ]; then
    add_issue ERROR runs_fetch_failed "could not fetch workflow runs for ${finops_repo}"
    emit_trailer
    exit 1
  fi
fi

# --- Billing projection -----------------------------------------------------
# netAmount, not grossAmount, is the spend: public-repo minutes are free, so
# those rows carry grossAmount == discountAmount and netAmount == 0. Both are
# emitted — gross for exposure (what a runner-tier change would start costing),
# net for what is actually billed today.
#
# The product/unitType filter is applied HERE rather than relying on the fetch's
# --jq, because the fixture path feeds `.billing` through unfiltered. Filtering
# only at the fetch made the live and fixture paths disagree, and a packages row
# summed into an Actions-minutes total.
billing_actions='[(.usageItems // [])[] | select(.product == "actions" and .unitType == "Minutes")]'
if [ -n "$billing_json" ] && [ "$billing_json" != "null" ]; then
  item_count=$(echo "$billing_json" | jq -r "${billing_actions} | length")
  if [ "${item_count:-0}" -gt 0 ]; then
    echo "BILLING_AVAILABLE=true"
    echo "BILLING_MINUTES=$(echo "$billing_json" | jq -r "${billing_actions} | [.[].quantity] | add // 0 | floor")"
    echo "BILLING_GROSS_USD=$(echo "$billing_json" | jq -r "${billing_actions} | [.[].grossAmount] | add // 0 | .*100 | round / 100")"
    echo "BILLING_NET_USD=$(echo "$billing_json" | jq -r "${billing_actions} | [.[].netAmount] | add // 0 | .*100 | round / 100")"
  else
    echo "BILLING_AVAILABLE=false"
  fi
else
  echo "BILLING_AVAILABLE=false"
fi

# --- Run grouping + duration aggregation ------------------------------------
total_runs=$(echo "$runs_json" | jq -r '.workflow_runs | length')
echo "TOTAL_RUNS=${total_runs}"

# Per-workflow run counts (sorted desc). Graceful on zero runs (emits nothing).
echo "$runs_json" | jq -r '
  .workflow_runs | group_by(.name) |
  map({name: (.[0].name // "unknown"), runs: length}) |
  sort_by(-.runs)[] |
  "WORKFLOW_RUNS=\(.name)|\(.runs)"'

# Per-workflow total duration (seconds) over runs with both timestamps present.
# floor to whole seconds.
echo "$runs_json" | jq -r '
  [.workflow_runs[]
    | select(.run_started_at != null and .updated_at != null)] |
  group_by(.name) |
  map({name: (.[0].name // "unknown"),
       seconds: (map((.updated_at | fromdateiso8601) - (.run_started_at | fromdateiso8601)) | add | floor)}) |
  sort_by(-.seconds)[] |
  "WORKFLOW_DURATION_SECONDS=\(.name)|\(.seconds)"' 2>/dev/null

# --- Waste detection (counts) -----------------------------------------------
skipped_count=$(echo "$runs_json" | jq -r '[.workflow_runs[] | select(.conclusion == "skipped")] | length')
bot_count=$(echo "$runs_json" | jq -r '[.workflow_runs[] | select(.triggering_actor.type == "Bot")] | length')
high_freq_count=$(echo "$runs_json" | jq -r '[.workflow_runs | group_by(.name)[] | select(length > 50)] | length')

echo "SKIPPED_RUNS=${skipped_count}"
echo "BOT_TRIGGERED_RUNS=${bot_count}"
echo "HIGH_FREQUENCY_WORKFLOWS=${high_freq_count}"

# Skipped ratio as integer percent.
if [ "$total_runs" -gt 0 ]; then
  skipped_pct=$(( skipped_count * 100 / total_runs ))
else
  skipped_pct=0
fi
echo "SKIPPED_PERCENT=${skipped_pct}"

# --- Threshold comparison + static fix-suggestion lookup --------------------
# Threshold: skipped runs >10% of total → flag with the path-filter fix.
if [ "$skipped_pct" -gt 10 ]; then
  add_issue WARN skipped_runs "skipped runs ${skipped_pct}% exceed 10% — add paths: filters to skip irrelevant triggers"
fi

# Bot-to-bot waste: any bot-triggered run → suggest the bot guard.
if [ "$bot_count" -gt 0 ]; then
  add_issue WARN bot_triggered "${bot_count} bot-triggered runs — add if: github.event.sender.type != 'Bot' to jobs"
fi

# High-frequency workflows → suggest concurrency + path filters.
if [ "$high_freq_count" -gt 0 ]; then
  add_issue WARN high_frequency "${high_freq_count} workflow(s) >50 runs — add concurrency groups with cancel-in-progress and paths: filters"
fi

emit_trailer
[ "$finops_status" = "ERROR" ] && exit 1
exit 0
