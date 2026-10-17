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
# For the workflow file given, this samples its most recent runs in which the
# Claude job actually ran, reads each run's log, and reports cost, turns and
# denials per run, plus whether the turn draw came within NEAR_CAP_MARGIN of
# that run's `--max-turns`. Past the cap counts too: the action counts turns
# beyond it before failing (72 against a cap of 40 on obsidian-cli-changelog run
# 35737375212).
#
# INVARIANT: a billed run is never dropped. A run whose log carries a
# claude-code-action accounting object is sampled at its measured cost, whatever
# its job list says. The job list is a parse of the workflow file, and it cannot
# read every way a workflow invokes Claude, so its verdict is a first pass and
# the log is the backstop.
#
# "Ran" is first read from the run's job list, not its run conclusion. A run
# whose Claude job was skipped by its own `if:` (obsidian-cli-changelog:
# check-cli-doc succeeded, claude-review skipped), or whose Claude step was
# skipped by a step-level `if:` (plugin-pr-checks: the compliance job succeeds
# while its "Claude Skill Quality Review" step is skipped), still concludes
# success, so the run list cannot tell it apart. A run the job list calls gated
# is left out of the sample only when its log carries no accounting either, and
# is counted in GATED_OFF_RUNS. The walk covers the newest --scan runs, so --limit
# is filled from further back without reading unbounded history, and a walk that
# ends with the sample short says so in SCAN_TRUNCATED. A run whose job list
# cannot be read, or matches no Claude job or Claude step the workflow file names
# (a templated or unnamed step, say), is sampled as before, so an unclassifiable
# run stays visible rather than vanishing.
#
# The per-run cap is the one the run actually used, read from the `claude_args:`
# line the log echoes, because caps change: workflow-model-audit run
# 34234073610 failed at 42 turns against 40, and the file has said 60 since.
# The file's current cap is the header MAX_TURNS, and the per-run fallback when
# a log does not echo one.
#
# A sampled run whose log carries no accounting object (its Claude job printed
# none, the log has expired, or its job list could not be matched to a Claude
# job or step, so the run was kept rather than dropped) reports COST_USD=unknown,
# never 0: an audit that ranks by spend must not read "no data" as "free".
#
# Usage: bash scripts/workflow-run-cost.sh <workflow-file> [--limit N] [--scan N]
#   --limit N   model-reaching runs to sample (default 3)
#   --scan N    newest runs to walk while filling the sample (default: the larger
#               of 20 and 4 x --limit; must be at least --limit)
# Needs gh (with Actions read access to the repository) and jq.
#
# Output: one `=== WORKFLOW RUN COST ===` KEY=VALUE block
# (.claude/rules/structured-script-output.md). STATUS=WARN when a sampled run
# is near or past its cap. RUNS_SAMPLED, RUNS_SCANNED (listed runs examined),
# GATED_OFF_RUNS (examined runs the job list calls gated whose log carries no
# accounting) and SCAN_TRUNCATED (true when the walk stopped at --scan with the
# sample short) describe the walk. Exit 0 on OK/WARN, 1 on ERROR (the runs could
# not be listed), 2 on a usage error.

set -uo pipefail

NEAR_CAP_MARGIN=2
LIMIT=3
SCAN=""
WF=""

usage() {
  echo "Usage: bash scripts/workflow-run-cost.sh <workflow-file> [--limit N] [--scan N]" >&2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --limit)
      [ $# -ge 2 ] || { usage; exit 2; }
      LIMIT="$2"; shift 2 ;;
    --scan)
      [ $# -ge 2 ] || { usage; exit 2; }
      SCAN="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "workflow-run-cost.sh: unknown flag: $1" >&2; usage; exit 2 ;;
    *)
      [ -z "$WF" ] || { usage; exit 2; }
      WF="$1"; shift ;;
  esac
done

[ -n "$WF" ] || { usage; exit 2; }

# positive_int <value> -- succeeds for a decimal integer >= 1. Leading zeros are
# read as decimal (10#), so "08" is 8, not an invalid octal.
positive_int() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$((10#$1))" -ge 1 ]
}
positive_int "$LIMIT" || { echo "workflow-run-cost.sh: --limit needs a positive integer" >&2; exit 2; }
LIMIT=$((10#$LIMIT))
# The walk defaults to the larger of 20 and four times --limit: headroom for
# gated-off runs, which are passed over without being sampled.
if [ -z "$SCAN" ]; then
  SCAN=$((LIMIT * 4)); [ "$SCAN" -ge 20 ] || SCAN=20
fi
positive_int "$SCAN" || { echo "workflow-run-cost.sh: --scan needs a positive integer" >&2; exit 2; }
SCAN=$((10#$SCAN))
[ "$SCAN" -ge "$LIMIT" ] || { echo "workflow-run-cost.sh: --scan ($SCAN) must be at least --limit ($LIMIT)" >&2; exit 2; }
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

# One list call bounds the walk. Most event-triggered workflows skip far more
# runs than they execute, so the newest runs alone are often all `skipped`; the
# walk goes past them and stops at --scan.
RUNS_JSON="$(gh run list --workflow "$WF_BASE" -L "$SCAN" --json databaseId,conclusion,createdAt 2>/dev/null)" \
  || emit_error run_list_failed "gh run list failed for $WF_BASE"
WALK="$(printf '%s' "$RUNS_JSON" | jq -r --argjson n "$SCAN" '
  .[:$n][] | "\(.databaseId) \(.conclusion) \(.createdAt)"' 2>/dev/null)" \
  || emit_error run_list_unparseable "gh run list returned JSON jq could not read for $WF_BASE"
LISTED="$(printf '%s' "$RUNS_JSON" | jq -r --argjson n "$SCAN" '.[:$n] | length' 2>/dev/null)" || LISTED=0

# claude_jobs <workflow-file> -- one `job<TAB><key><TAB><name><TAB><step>...` line
# per job in the file that invokes Claude. <name> is the job's `name:` when it
# sets a plain one (empty otherwise); each <step> is the `name:` of a step in
# that job whose block invokes Claude. A job invokes Claude when its block,
# comments aside, names claude-code-action or the npx CLI. A templated or
# single-quoted name is not read, so such a job or step is matched by its key
# alone, or not at all. A job key the parser cannot read (a quoted key, say)
# closes the job above it, so its Claude lines are never credited to that job.
claude_jobs() {
  LC_ALL=C awk '
    function flush_step() {
      if (instep && step_claude && step_name != "") steps[++nsteps] = step_name
      instep = 0; step_claude = 0; step_name = ""
    }
    function flush_job(   rec, i) {
      flush_step()
      if (job != "" && claude) {
        rec = "job\t" job "\t" name
        for (i = 1; i <= nsteps; i++) rec = rec "\t" steps[i]
        print rec
      }
      job = ""; name = ""; claude = 0; nsteps = 0; split("", steps)
    }
    /^jobs:[[:space:]]*$/ { injobs = 1; next }
    injobs && /^[^[:space:]#]/ { flush_job(); injobs = 0 }
    # A job key, optionally followed by a comment (`  claude:  # the model job`).
    injobs && /^  [A-Za-z0-9_][A-Za-z0-9_-]*:[[:space:]]*(#.*)?$/ {
      flush_job(); job = $0; sub(/^  /, "", job); sub(/:.*$/, "", job); next
    }
    # Any other 2-space key is one this parser cannot read: close the job above it.
    injobs && /^  [^[:space:]#]/ { flush_job(); next }
    injobs && job != "" && /^    [^[:space:]#]/ { flush_step() }
    injobs && job != "" && /^    name:/ {
      name = $0; sub(/^    name:[[:space:]]*/, "", name); gsub(/"/, "", name); next
    }
    injobs && job != "" && /^      - / {
      flush_step(); instep = 1
      rest = $0; sub(/^      - /, "", rest)
      if (rest ~ /^name:/) { step_name = rest; sub(/^name:[[:space:]]*/, "", step_name); gsub(/"/, "", step_name) }
    }
    injobs && job != "" && instep && /^        name:/ {
      step_name = $0; sub(/^        name:[[:space:]]*/, "", step_name); gsub(/"/, "", step_name); next
    }
    injobs && job != "" && $0 !~ /^[[:space:]]*#/ && /anthropics\/claude-code-action|npx @anthropic-ai\/claude-code/ {
      claude = 1; if (instep) step_claude = 1
    }
    END { flush_job() }
  ' "$1"
}
CLAUDE_JSON="$(claude_jobs "$WF" | jq -R -s -c '
  split("\n") | map(select(length > 0) | split("\t") | select(.[0] == "job")
    | {key: .[1], name: (.[2] // ""), steps: .[3:]})')"

# gate_of <run-id> -- "gated" when the run's job list says it never reached the
# model: every job of the run that matches a Claude job was skipped, or the job
# ran but every Claude step it names was skipped (a step-level `if:`). "ran" when
# a matched job reached a Claude step, and "unknown" when the job list cannot be
# read or matches no Claude job. The main loop samples a "gated" run anyway when
# its log carries accounting. "unknown" is always sampled, so a run that cannot
# be classified stays visible as COST_USD=unknown instead of vanishing.
gate_of() {
  local jobs_json
  jobs_json="$(gh run view "$1" --json jobs 2>/dev/null)" || { echo unknown; return; }
  printf '%s' "$jobs_json" | jq -r --argjson claude "$CLAUDE_JSON" '
    # A gh job matches a Claude record by its key or its name:, either one
    # optionally followed by the matrix suffix " (...)" that gh appends.
    def claude_records($n): [ $claude[] as $c | select(
        $n == $c.key or ($n | startswith($c.key + " ("))
        or ($c.name != "" and ($n == $c.name or ($n | startswith($c.name + " (")))) ) | $c ];
    [ (.jobs // [])[] | (.name // "") as $n | claude_records($n) as $recs
      | select($recs | length > 0)
      | (.conclusion // "") as $jc
      | [ (.steps // [])[] | (.name // "") as $sn | (.conclusion // "") as $sc
          | select(any($recs[].steps[]; . == $sn)) | $sc ] as $claude_steps
      | if $jc == "skipped" then "gated"
        elif ($claude_steps | length) > 0 and all($claude_steps[]; . == "skipped") then "gated"
        else "ran" end
    ] as $verdicts
    | if ($verdicts | length) == 0 then "unknown"
      elif any($verdicts[]; . == "ran") then "ran"
      else "gated" end' 2>/dev/null || echo unknown
}

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
scanned=0
sampled=0
gated=0
costed=0
near_count=0
total_cost=0

while read -r run_id conclusion created; do
  [ -n "${run_id:-}" ] || continue
  [ "$sampled" -lt "$LIMIT" ] || break
  scanned=$((scanned + 1))
  # A run conclusion that never ran a job at all is not a candidate.
  case "$conclusion" in
    success|failure|cancelled|timed_out) ;;
    *) continue ;;
  esac
  # The job list calls the run gated, which is a parse of the workflow file and
  # can miss an invocation spelling. The log is the backstop: its accounting, read
  # once here and reused below, means the run was billed, so it is sampled. Only
  # a gated run with no accounting is left out, and counted.
  acct=""
  if [ "$(gate_of "$run_id")" = gated ]; then
    acct="$(gh run view "$run_id" --log 2>/dev/null | read_accounting)"
    if [ "${acct%% *}" = unknown ]; then
      gated=$((gated + 1))
      continue
    fi
  fi
  sampled=$((sampled + 1))
  [ -n "$acct" ] || acct="$(gh run view "$run_id" --log 2>/dev/null | read_accounting)"
  read -r cost turns denials cap <<<"$acct"
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
done <<< "$WALK"

# The walk ended at --scan with the sample short, so older runs exist that were
# never examined: a short sample is reported, never mistaken for the history.
truncated=false
if [ "$sampled" -lt "$LIMIT" ] && [ "$LISTED" -ge "$SCAN" ]; then truncated=true; fi

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
echo "RUNS_SCANNED=$scanned"
echo "GATED_OFF_RUNS=$gated"
echo "SCAN_TRUNCATED=$truncated"
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
