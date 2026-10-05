#!/usr/bin/env bash
# LIVE smoke for the headless eval harness: real `claude -p` calls, haiku only.
#
# Deliberately NOT named test-*.sh, so scripts/run-skill-script-tests.sh and CI
# never discover it -- it spends real money. It does nothing unless EVAL_LIVE=1.
#
#   EVAL_LIVE=1 bash evaluate-plugin/scripts/tests/live/smoke-headless.sh
#
# What it proves end to end (rollout_headless.sh -> parse_trace.py ->
# grade_deterministic.py, and run_trigger_evals.py), on git-plugin/git-commit:
#   1. gc-007 WITH the skill: the fixture applies, the child runs in clean env
#      mode, a trace.json and a workspace snapshot land, and the grader grades
#      the trace/workspace checks (HARNESS_DEFERRED=0) instead of deferring.
#   2. gc-007 BASELINE (no --plugin-dir): same plumbing, and the child cannot
#      have invoked git-plugin:git-commit -- the plugin was never loaded.
#   3. Env-leak invariants on both rollouts: ENV_MODE=clean, no session_id_leak
#      or foreign_hook issue, the child session_id differs from this session's,
#      and no exported auth token value appears anywhere in the run dir.
#   4. Trigger evals on git-commit with a $0.60 total cap: the run completes
#      (not ERROR), every prompt was attempted, spend stays under its cap.
#   5. The whole run spends at most COST_CAP_USD ($1.50). A rollout whose cost
#      is unknown (killed / timed out) is charged at its own --max-budget-usd.
#
# Routing and model quality are REPORTED, never asserted. Whether haiku routes
# to the skill, or writes a conventional subject, is what the evals measure, not
# what this smoke guards. The plumbing is deterministic; routing is not. On
# 2026-10-05 (claude 2.1.289, n=1), haiku committed gc-007 without invoking
# git-plugin:git-commit and missed all 3 should_trigger prompts (recall 0.0),
# and a second round reproduced both. A probe showed git-commit in haiku's Skill
# listing by NAME only: git-plugin's 48 skill descriptions were elided ("not
# provided"), consistent with the CLI's listing budget
# (SLASH_COMMAND_TOOL_CHAR_BUDGET), so the "Use when user says commit" trigger
# never reached the child and these runs measure name-only routing (see
# docs/cross-model-evaluation.md, "Skill descriptions"). So:
#   - WITH_SKILL_ROUTED=false (the with-skill run never invoked git-commit) and
#     a trigger run that misses its thresholds (TRIGGERS_STATUS=WARN) are WARN
#     issues: STATUS=WARN, exit 0, REASON= naming them. They are not failures.
#   - A routing decision needs trigger evals at --runs 3 (and a stronger model
#     than haiku), not this n=1 smoke.
# Every workdir and run dir is a mktemp dir OUTSIDE the repo
# (rollout_headless.sh refuses a workdir inside it).
#
# Output: === LIVE HEADLESS SMOKE === KEY=VALUE lines, then === SUMMARY ===
# PASSED/FAILED/WARNED/COST_USD_TOTAL/STATUS. Exit 0 on OK, WARN or skipped;
# 1 on an assertion failure.
set -uo pipefail

if [ "${EVAL_LIVE:-}" != "1" ]; then
  echo "=== LIVE HEADLESS SMOKE ==="
  echo "SKIPPED=true"
  echo "SKIP_REASON=EVAL_LIVE is not 1; this smoke makes real claude -p calls"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END LIVE HEADLESS SMOKE ==="
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../../.." && pwd)"
scripts="$repo_root/evaluate-plugin/scripts"
skill_dir="$repo_root/git-plugin/skills/git-commit"
evals="$skill_dir/evals.json"
plugin_dir="$repo_root/git-plugin"

MODEL="haiku"
ROLLOUT_CAP_USD="0.25"
TRIGGER_TOTAL_USD="0.60"
TRIGGER_PER_PROMPT_USD="0.05"
COST_CAP_USD="1.50"

pass=0; fail=0; warned=0
cost_total="0"
issues=()   # "SEVERITY=... TYPE=... MSG=..." rows for the ISSUES: block
check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail=$((fail + 1))
    issues+=("SEVERITY=ERROR TYPE=assertion MSG=$1 (expected '$2', got '$3')")
  fi
}
warn() {
  # warn <type> <message> -- a reported, non-asserted finding (routing quality)
  echo "WARN: $1: $2" >&2
  warned=$((warned + 1))
  issues+=("SEVERITY=WARN TYPE=$1 MSG=$2")
}
field() { printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2-; }
add_cost() { cost_total="$(python3 -c 'import sys; print(round(float(sys.argv[1]) + float(sys.argv[2]), 6))' "$cost_total" "$1")"; }

for tool in claude jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool not on PATH" >&2; exit 1; }
done

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/eval-live-smoke.XXXXXX")"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then echo "mktemp failed" >&2; exit 1; fi
case "$tmp_root" in
  "$repo_root"/*) echo "ERROR: temp root $tmp_root is inside the repo; set TMPDIR elsewhere" >&2; exit 1 ;;
esac
trap 'rm -rf "$tmp_root"' EXIT

echo "=== LIVE HEADLESS SMOKE ==="
echo "MODEL=$MODEL"
echo "TMP_ROOT=$tmp_root"

fixture="$(jq -c '.evals[] | select(.id == "gc-007") | .fixture' "$evals")"
jq -r '.evals[] | select(.id == "gc-007") | .prompt' "$evals" > "$tmp_root/prompt.txt"
check "gc-007 exists with a fixture" "true" "$([ -n "$fixture" ] && [ "$fixture" != "null" ] && echo true || echo false)"

# rollout_gc007 <config: with-skill|baseline>
rollout_gc007() {
  local config="$1" run_dir wd_block workdir out rc plugin_args=() cost trace grade key
  key="$(printf '%s' "$config" | tr 'a-z-' 'A-Z_')"   # with-skill -> WITH_SKILL
  run_dir="$tmp_root/run-$config"
  mkdir -p "$run_dir"
  wd_block="$(bash "$scripts/apply_fixture.sh" --fixture "$fixture" --repo-root "$repo_root")"
  workdir="$(field "$wd_block" WORKDIR)"
  check "$config: fixture applied" "OK" "$(field "$wd_block" STATUS)"
  if [ -z "$workdir" ] || [ ! -d "$workdir" ]; then
    check "$config: fixture workdir exists" "true" "false"; add_cost "$ROLLOUT_CAP_USD"; return
  fi
  [ "$config" = "with-skill" ] && plugin_args=(--plugin-dir "$plugin_dir")

  out="$(bash "$scripts/rollout_headless.sh" --run-dir "$run_dir" --workdir "$workdir" \
    --prompt-file "$tmp_root/prompt.txt" --model "$MODEL" --max-budget-usd "$ROLLOUT_CAP_USD" \
    --max-turns 15 "${plugin_args[@]+"${plugin_args[@]}"}")"; rc=$?
  bash "$scripts/apply_fixture.sh" --teardown "$workdir" --fixture "$fixture" >/dev/null 2>&1

  cost="$(field "$out" COST_USD)"
  if [ -n "$cost" ]; then add_cost "$cost"; else add_cost "$ROLLOUT_CAP_USD"; fi
  echo "${key}_STATUS=$(field "$out" STATUS)"
  echo "${key}_STOP_REASON=$(field "$out" STOP_REASON)"
  echo "${key}_COST_USD=${cost:-unknown}"
  echo "${key}_MODEL_ID=$(field "$out" MODEL_ID)"
  echo "${key}_SKILLS_INVOKED=$(field "$out" SKILLS_INVOKED)"

  check "$config: rollout exit is not a usage/ERROR exit" "0" "$rc"
  check "$config: env mode is clean (no inherit fallback)" "clean" "$(field "$out" ENV_MODE)"
  check "$config: no session_id_leak issue" "false" "$(grep -q 'TYPE=session_id_leak' <<<"$out" && echo true || echo false)"
  check "$config: no foreign_hook issue" "false" "$(grep -q 'TYPE=foreign_hook' <<<"$out" && echo true || echo false)"

  trace="$(field "$out" TRACE)"
  if [ -z "$trace" ] || [ ! -f "$trace" ]; then
    check "$config: trace.json written" "true" "false"; return
  fi
  if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then
    check "$config: child session_id differs from this session's" "false" \
      "$([ "$(jq -r '.session_id // ""' "$trace")" = "$CLAUDE_CODE_SESSION_ID" ] && echo true || echo false)"
  fi
  local secret
  for secret in ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN; do
    if [ -n "${!secret:-}" ]; then
      check "$config: $secret value never written to the run dir" "false" \
        "$(grep -rqF -- "${!secret}" "$run_dir" && echo true || echo false)"
    fi
  done
  # Full or bare name, as grade_deterministic.py's skill_triggered counts it.
  local routed
  routed="$(jq -r '[.skills_invoked[].skill] | any(. == "git-plugin:git-commit" or . == "git-commit")' "$trace")"
  echo "${key}_ROUTED=$routed"
  if [ "$config" = "baseline" ]; then
    check "baseline: git-commit cannot be invoked without its plugin" "false" "$routed"
  elif [ "$routed" != "true" ]; then
    warn "unrouted" "with-skill gc-007 rollout never invoked git-plugin:git-commit (model routing at n=1; reported, not asserted)"
  fi

  grade="$(python3 "$scripts/grade_deterministic.py" --evals "$evals" --eval-id gc-007 \
    --output "$run_dir/transcript.md" --trace "$trace" \
    --workspace "$(field "$out" WORKSPACE)" --allow-exec)"
  check "$config: trace/workspace checks graded, not deferred" "0" "$(field "$grade" HARNESS_DEFERRED)"
  check "$config: all three deterministic checks graded" "3" "$(field "$grade" DETERMINISTIC_TOTAL)"
  echo "${key}_DETERMINISTIC_PASSED=$(field "$grade" DETERMINISTIC_PASSED)"
}

rollout_gc007 with-skill
rollout_gc007 baseline

# Trigger evals: the runner enforces its own total cap; --output keeps every
# per-prompt run dir under tmp_root, and --no-copy keeps this n=1 smoke from
# overwriting git-commit's genuine eval-results/triggers.json in the checkout
# (the offline test-smoke-headless.sh drives this same line with a fake claude).
trig_out="$(python3 "$scripts/run_trigger_evals.py" --skill-dir "$skill_dir" --model "$MODEL" \
  --max-budget-usd-per-prompt "$TRIGGER_PER_PROMPT_USD" --total-budget-usd "$TRIGGER_TOTAL_USD" \
  --output "$tmp_root/triggers/triggers.json" --no-copy)"; trig_rc=$?
trig_json="$tmp_root/triggers/triggers.json"
trig_status="$(field "$trig_out" STATUS)"
echo "TRIGGERS_STATUS=$trig_status"
echo "TRIGGERS_COPY=$(field "$trig_out" COPY)"
check "triggers: no copy into the skill's eval-results" "none" "$(field "$trig_out" COPY)"
check "triggers: runner did not ERROR" "true" "$([ "$trig_rc" -ne 1 ] && [ "$trig_rc" -ne 2 ] && echo true || echo false)"
if [ "$trig_status" = "WARN" ]; then
  warn "trigger_threshold" "trigger evals missed a threshold ($(field "$trig_out" REASON)); n=1 routing noise, use --runs 3 to decide"
fi
if [ -f "$trig_json" ]; then
  trig_cost="$(jq -r '.summary.total_cost // 0' "$trig_json")"
  add_cost "$trig_cost"
  echo "TRIGGERS_COST_USD=$trig_cost"
  echo "TRIGGERS_RECALL=$(jq -r '.summary.recall // ""' "$trig_json")"
  echo "TRIGGERS_FP=$(jq -r '.summary.fp' "$trig_json")"
  check "triggers: every prompt attempted" "$(jq '(.triggers.should_trigger | length) + (.triggers.should_not_trigger | length)' "$evals")" \
    "$(jq -r '.summary.attempted' "$trig_json")"
  check "triggers: spend within its cap" "true" \
    "$(python3 -c 'import sys; print(str(float(sys.argv[1]) <= float(sys.argv[2])).lower())' "$trig_cost" "$TRIGGER_TOTAL_USD")"
else
  check "triggers: triggers.json written" "true" "false"
  add_cost "$TRIGGER_TOTAL_USD"
fi

within="$(python3 -c 'import sys; print(str(float(sys.argv[1]) <= float(sys.argv[2])).lower())' "$cost_total" "$COST_CAP_USD")"
check "total spend <= \$$COST_CAP_USD" "true" "$within"
smoke_status="OK"; sev=""
if [ "$fail" -gt 0 ]; then smoke_status="ERROR"; sev="ERROR"
elif [ "$warned" -gt 0 ]; then smoke_status="WARN"; sev="WARN"; fi
echo "COST_USD_TOTAL=$cost_total"
echo "STATUS=$smoke_status"
if [ -n "$sev" ]; then
  # REASON: the first finding at the reported severity, <TYPE>: <MSG>, <=200 chars.
  first=""; row=""
  for row in "${issues[@]}"; do
    case "$row" in "SEVERITY=$sev "*) first="$row"; break ;; esac
  done
  first_type="${first#*TYPE=}"; first_type="${first_type%% MSG=*}"
  first_msg="${first#* MSG=}"
  more=$(( ${#issues[@]} - 1 ))
  reason="$(printf '%s: %s' "$first_type" "$first_msg" | tr -s '[:space:]' ' ' | cut -c1-180)"
  [ "$more" -gt 0 ] && reason="$reason (+$more more)"
  echo "REASON=$reason"
fi
echo "ISSUE_COUNT=${#issues[@]}"
if [ "${#issues[@]}" -gt 0 ]; then
  echo "ISSUES:"
  for row in "${issues[@]}"; do echo "  - $row"; done
fi
echo "=== END LIVE HEADLESS SMOKE ==="

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass"
echo "FAILED=$fail"
echo "WARNED=$warned"
echo "COST_USD_TOTAL=$cost_total"
echo "STATUS=$smoke_status"
[ "$fail" -gt 0 ] && exit 1
exit 0
