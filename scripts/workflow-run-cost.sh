#!/usr/bin/env bash
# Measured cost and turn draw of one Claude-invoking workflow's recent runs (#2669).
#
# claude-code-action prints its own accounting at the end of every run: a
# pretty-printed `"type": "result"` object in the job log carrying `num_turns`,
# `total_cost_usd` and `permission_denials_count`. It exposes that nowhere else
# (no step output, no API field), so workflow-model-audit.yml's pre-compute,
# which read only run conclusions, could tell the monthly audit which workflow
# was slow or red but never which one was expensive, and could not see a
# `--max-turns` budget that was binding rather than generous.
#
# For the workflow file given, this samples its most recent runs that reached a
# job (skipped runs never reach the model), reads each run's log, and reports
# cost, turns and denials per run, plus whether the turn draw came within
# NEAR_CAP_MARGIN of that run's `--max-turns`. Past the cap counts too: the
# action counts turns beyond it before failing (72 against a cap of 40 on
# obsidian-cli-changelog run 35737375212).
#
# The per-run cap is the one the run actually used, read from the `claude_args:`
# line the log echoes, because caps change: workflow-model-audit run
# 34234073610 failed at 42 turns against 40, and the file has said 60 since.
# The file's current cap is the header MAX_TURNS, and the per-run fallback when
# a log does not echo one.
#
# A run whose log carries no accounting object (the Claude step was skipped by
# its own `if:`, or the log has expired) reports COST_USD=unknown, never 0: an
# audit that ranks by spend must not read "no data" as "free".
#
# Usage: bash scripts/workflow-run-cost.sh <workflow-file> [--limit N]
#   --limit N   runs to sample (default 3)
# Needs gh (with Actions read access to the repository) and jq.
#
# Output: one `=== WORKFLOW RUN COST ===` KEY=VALUE block
# (.claude/rules/structured-script-output.md). STATUS=WARN when a sampled run
# is near or past its cap. Exit 0 on OK/WARN, 1 on ERROR (the runs could not be
# listed), 2 on a usage error.

set -uo pipefail

NEAR_CAP_MARGIN=2
LIMIT=3
WF=""

usage() {
  echo "Usage: bash scripts/workflow-run-cost.sh <workflow-file> [--limit N]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --limit)
      [ $# -ge 2 ] || { usage; exit 2; }
      LIMIT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "workflow-run-cost.sh: unknown flag: $1" >&2; usage; exit 2 ;;
    *)
      [ -z "$WF" ] || { usage; exit 2; }
      WF="$1"; shift ;;
  esac
done

[ -n "$WF" ] || { usage; exit 2; }
case "$LIMIT" in
  ''|*[!0-9]*|0) echo "workflow-run-cost.sh: --limit needs a positive integer" >&2; exit 2 ;;
esac
[ -f "$WF" ] || { echo "workflow-run-cost.sh: no such workflow file: $WF" >&2; exit 2; }

WF_BASE="$(basename "$WF")"

# The cap is `--max-turns N` on its own line: the one-flag-per-line shape of a
# folded `claude_args:` scalar (scripts/check-workflow-model.sh relies on the
# same shape), or of a `npx @anthropic-ai/claude-code` call continued with a
# trailing backslash (auto-resolve-conflicts.yml). A comment or prompt line that
# mentions a cap in prose (`# --max-turns 25 budget`) does not match the anchor.
MAX_TURNS="$(grep -E '^[[:space:]]*--max-turns[[:space:]]+[0-9]+[[:space:]]*(\\[[:space:]]*)?$' "$WF" | head -n 1 | sed -E 's/^[[:space:]]*--max-turns[[:space:]]+([0-9]+).*/\1/')"
[ -n "$MAX_TURNS" ] || MAX_TURNS=none

emit_error() {
  echo "=== WORKFLOW RUN COST ==="
  echo "WORKFLOW=$WF_BASE"
  echo "MAX_TURNS=$MAX_TURNS"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=$1 MSG=$2"
  echo "=== END WORKFLOW RUN COST ==="
  exit 1
}

command -v jq >/dev/null 2>&1 || emit_error missing_jq "jq is required to read gh run list output"

# -L 20 then filter: most event-triggered workflows skip far more runs than
# they execute, so the newest N runs alone are often all `skipped`.
RUNS_JSON="$(gh run list --workflow "$WF_BASE" -L 20 --json databaseId,conclusion,createdAt 2>/dev/null)" \
  || emit_error run_list_failed "gh run list failed for $WF_BASE"
SAMPLE="$(printf '%s' "$RUNS_JSON" | jq -r --argjson n "$LIMIT" '
  [ .[] | select(.conclusion == "success" or .conclusion == "failure"
                 or .conclusion == "cancelled" or .conclusion == "timed_out") ]
  | .[:$n][] | "\(.databaseId) \(.conclusion) \(.createdAt)"' 2>/dev/null)" \
  || emit_error run_list_unparseable "gh run list returned JSON jq could not read for $WF_BASE"

# Reads one `gh run view --log` stream and prints
# "<cost> <turns> <denials> <cap>", cost unrounded so the total below sums the
# measured values rather than the rounded ones. Only TIMESTAMPED lines are the action's own
# output: a multi-line `with:` input such as the prompt echoes its continuation
# lines with no timestamp, so a prompt that quotes an accounting object or a
# `--max-turns` is never mistaken for one. Several result objects in one run
# (several Claude steps) sum cost and denials and keep the highest turn count;
# the cap is the first `claude_args:` echo's.
read_accounting() {
  LC_ALL=C awk -F '\t' '
    NF >= 3 {
      # gh run view --log lines are <job> TAB <step> TAB <timestamp> <content>.
      line = $3
      for (i = 4; i <= NF; i++) line = line "\t" $i
      if (sub(/^[0-9][0-9-]*T[0-9:.]*Z ?/, "", line) == 0) next
      if (cap == "" && line ~ /^  claude_args: / && match(line, /--max-turns[ =]+[0-9]+/)) {
        cap = substr(line, RSTART, RLENGTH); gsub(/[^0-9]/, "", cap)
      }
      if (line ~ /^  "type": "result",?$/) { inres = 1; next }
      if (line == "}") { inres = 0; next }
      if (!inres) next
      if (line ~ /^  "num_turns": [0-9]+,?$/) {
        v = line; gsub(/[^0-9]/, "", v); v += 0
        if (!has_t || v > turns) turns = v
        has_t = 1
      } else if (line ~ /^  "total_cost_usd": [0-9.eE+-]+,?$/) {
        v = line; sub(/^  "total_cost_usd": /, "", v); sub(/,$/, "", v)
        cost += v; has_c = 1
      } else if (line ~ /^  "permission_denials_count": [0-9]+,?$/) {
        v = line; gsub(/[^0-9]/, "", v)
        den += v; has_d = 1
      }
    }
    END {
      printf "%s %s %s %s\n", (has_c ? sprintf("%.8f", cost) : "unknown"),
        (has_t ? turns : "unknown"), (has_d ? den : "unknown"),
        (cap != "" ? cap : "none")
    }'
}

rows=""
issues=""
sampled=0
costed=0
near_count=0
total_cost=0

while read -r run_id conclusion created; do
  [ -n "${run_id:-}" ] || continue
  sampled=$((sampled + 1))
  read -r cost turns denials cap < <(gh run view "$run_id" --log 2>/dev/null | read_accounting)
  [ "$cap" != none ] || cap="$MAX_TURNS"

  if [ "$cap" = none ]; then
    near=n/a
  elif [ "$turns" = unknown ]; then
    near=unknown
  elif [ "$turns" -ge $((cap - NEAR_CAP_MARGIN)) ]; then
    near=true
    near_count=$((near_count + 1))
    issues="${issues}  - SEVERITY=WARN TYPE=near_cap RUN=$run_id MSG=$turns turns against --max-turns $cap"$'\n'
  else
    near=false
  fi

  if [ "$cost" != unknown ]; then
    costed=$((costed + 1))
    total_cost="$(LC_ALL=C awk -v a="$total_cost" -v b="$cost" 'BEGIN { printf "%.8f", a + b }')"
    cost="$(LC_ALL=C awk -v c="$cost" 'BEGIN { printf "%.2f", c }')"
  fi

  rows="${rows}  - RUN=$run_id CONCLUSION=$conclusion CREATED=$created COST_USD=$cost TURNS=$turns MAX_TURNS=$cap NEAR_CAP=$near DENIALS=$denials"$'\n'
done <<< "$SAMPLE"

if [ "$costed" -gt 0 ]; then
  total_cost="$(LC_ALL=C awk -v c="$total_cost" 'BEGIN { printf "%.2f", c }')"
else
  total_cost=unknown
fi
status=OK
[ "$near_count" -eq 0 ] || status=WARN

echo "=== WORKFLOW RUN COST ==="
echo "WORKFLOW=$WF_BASE"
echo "MAX_TURNS=$MAX_TURNS"
echo "NEAR_CAP_MARGIN=$NEAR_CAP_MARGIN"
echo "RUNS_SAMPLED=$sampled"
if [ -n "$rows" ]; then
  echo "RUNS:"
  printf '%s' "$rows"
fi
echo "COSTED_RUNS=$costed"
echo "TOTAL_COST_USD=$total_cost"
echo "NEAR_CAP_RUNS=$near_count"
echo "STATUS=$status"
echo "ISSUE_COUNT=$near_count"
if [ -n "$issues" ]; then
  echo "ISSUES:"
  printf '%s' "$issues"
fi
echo "=== END WORKFLOW RUN COST ==="
exit 0
