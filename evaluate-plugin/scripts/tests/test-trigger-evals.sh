#!/usr/bin/env bash
# Assertions use the `cmd && pass++ || fail` idiom deliberately (pass++ is
# arithmetic that always exits 0 here, so the || branch only runs on real
# failure).
# shellcheck disable=SC2015
#
# Regression test for run_trigger_evals.py (interface E of the headless-harness
# spec). No live calls: EVAL_ROLLOUT_SCRIPT points at a stub rollout written
# below, which honours the rollout_headless.sh contract (the
# `=== HEADLESS ROLLOUT ===` KEY=VALUE block + a trace.json) and picks its
# behaviour from a `[[SEQ:...]]` token in the prompt -- one letter per run:
#
#   T  target skill invoked, child killed on it (stopped_on_skill, cost unknown)
#   C  target skill invoked, completed, cost 0.02
#   D  target skill invoked but DENIED, completed, cost 0.01
#   B  target invoked by its BARE name, completed, cost 0.01
#   P  a peer plugin's skill invoked, killed (cost unknown)
#   O  another plugin's skill sharing the target's bare name, cost 0.01
#   N  no skill invoked, completed, cost 0.01
#   E  rollout STATUS=ERROR, exit 1, no trace
#   U  rollout usage error, exit 2
#
# Covers: --dry-run (no rollouts, no files), triggers-block validation, the
# tp/fp/fn/tn maths, precision null with no predicted positives, the --runs
# rate >= 0.5 rule, ERROR rows excluded from the maths, the >50%-errors ERROR,
# budget abort keeping partial results with killed runs charged at the
# per-prompt cap, a rollout usage error aborting, STATUS OK/WARN/ERROR,
# the triggers.json shape, the rollout argv, and the eval-results/ copy.
# All skill dirs are temp dirs -- no real skill is touched.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
scripts_dir="$(dirname "$script_dir")"
runner="$scripts_dir/run_trigger_evals.py"
repo_root="$(cd "$scripts_dir/../.." && pwd -P)"

fail_count=0
pass_count=0

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() {
  # field <output> <KEY>  -> prints the value after KEY=
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2-
}

jf() {
  # jf <json file> <python expression over d>  -> prints the value as JSON
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(json.dumps(eval(sys.argv[2]), sort_keys=True, separators=(",", ":")))' "$1" "$2"
}

unset EVAL_ROLLOUT_SCRIPT EVAL_RUNS_ROOT

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] && [ -d "$sandbox" ] || { echo "FAIL: mktemp -d" >&2; exit 1; }
trap 'rm -rf "$sandbox"' EXIT
sandbox="$(cd "$sandbox" && pwd -P)"

# ---------------------------------------------------------------- stub rollout
stub="$sandbox/stub-rollout.sh"
cat >"$stub" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
run_dir="" workdir="" prompt=""
args=("$@")
while [ $# -gt 0 ]; do
  case "$1" in
    --run-dir) run_dir="$2"; shift 2 ;;
    --workdir) workdir="$2"; shift 2 ;;
    --prompt) prompt="$2"; shift 2 ;;
    *) shift ;;
  esac
done
wd_empty=no
[ -d "$workdir" ] && [ -z "$(ls -A "$workdir")" ] && wd_empty=yes
{
  printf 'CALL'
  printf ' %q' "${args[@]}"
  printf '\nWD=%s WD_EMPTY=%s\n' "$workdir" "$wd_empty"
} >>"$STUB_LOG"
seq="$(printf '%s' "$prompt" | sed -n 's/.*\[\[SEQ:\([A-Z]*\)\]\].*/\1/p')"
key="$(printf '%s' "$prompt" | cksum | cut -d' ' -f1)"
n=$(( $(cat "$STUB_STATE/$key" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$STUB_STATE/$key"
idx=$(( n <= ${#seq} ? n - 1 : ${#seq} - 1 ))
act="${seq:$idx:1}"

target="demo-plugin:demo-skill"
skills="" denied=false cost="0.01" stop="completed" status="OK"
case "$act" in
  T) skills="$target"; cost=""; stop="stopped_on_skill" ;;
  C) skills="$target"; cost="0.02" ;;
  D) skills="$target"; denied=true ;;
  B) skills="demo-skill" ;;
  P) skills="peer-plugin:peer-skill"; cost=""; stop="stopped_on_skill" ;;
  O) skills="peer-plugin:demo-skill" ;;
  N) ;;
  E) echo "=== HEADLESS ROLLOUT ==="; echo "RUN_DIR=$run_dir"; echo "TRACE="; echo "COST_USD=";
     echo "STOP_REASON=error"; echo "STATUS=ERROR"; echo "REASON=truncated_stream: the stream ended without a result event";
     echo "ISSUE_COUNT=1"; echo "=== END HEADLESS ROLLOUT ==="; exit 1 ;;
  U) echo "=== HEADLESS ROLLOUT ==="; echo "STATUS=ERROR"; echo "REASON=usage: claude CLI not found on PATH";
     echo "ISSUE_COUNT=1"; echo "=== END HEADLESS ROLLOUT ==="; exit 2 ;;
  *) echo "stub: no action for prompt" >&2; exit 3 ;;
esac
inv="[]"
[ -n "$skills" ] && inv="[{\"skill\":\"$skills\",\"args\":\"\",\"turn\":1,\"tool_use_id\":\"toolu_1\",\"denied\":$denied,\"is_error\":false}]"
cost_json="${cost:-null}"
printf '{"version":1,"harness":"claude-code","model_id":"claude-haiku-stub","skills_invoked":%s,"cost_usd":%s,"stop_reason":"%s"}\n' \
  "$inv" "$cost_json" "$([ "$stop" = stopped_on_skill ] && echo incomplete || echo "$stop")" >"$run_dir/trace.json"
echo "=== HEADLESS ROLLOUT ==="
echo "RUN_DIR=$run_dir"
echo "WORKDIR=$workdir"
echo "TRACE=$run_dir/trace.json"
echo "MODEL_ID=claude-haiku-stub"
echo "COST_USD=$cost"
echo "SKILLS_INVOKED=$skills"
echo "STOP_REASON=$stop"
echo "CHILD_EXIT=0"
echo "STATUS=$status"
echo "ISSUE_COUNT=0"
echo "=== END HEADLESS ROLLOUT ==="
STUB
chmod +x "$stub"

export EVAL_ROLLOUT_SCRIPT="$stub"
export EVAL_RUNS_ROOT="$sandbox/runs"
export STUB_LOG="$sandbox/stub.log"
export STUB_STATE="$sandbox/state"

# ---------------------------------------------------------------- temp marketplace
mkt="$sandbox/mkt"
mkdir -p "$mkt/demo-plugin/.claude-plugin" "$mkt/peer-plugin/.claude-plugin" "$mkt/notaplugin" \
  "$mkt/demo-plugin/skills/demo-skill"
printf '{"name":"demo-plugin","version":"0.0.0"}\n' >"$mkt/demo-plugin/.claude-plugin/plugin.json"
printf '{"name":"peer-plugin","version":"0.0.0"}\n' >"$mkt/peer-plugin/.claude-plugin/plugin.json"
skill="$mkt/demo-plugin/skills/demo-skill"
printf -- '---\nname: demo-skill\ndescription: Demo. Use when testing.\n---\n# Demo\n' >"$skill/SKILL.md"

# write_evals <should_trigger json> <should_not_trigger json> [peers json] [extra json]
write_evals() {
  python3 - "$skill/evals.json" "$1" "$2" "${3:-[\"peer-plugin\"]}" "${4:-{\}}" <<'PY'
import json, sys
path, pos, neg, peers, extra = sys.argv[1:]
t = {"skill": "demo-plugin:demo-skill", "should_trigger": json.loads(pos),
     "should_not_trigger": json.loads(neg), "peers": json.loads(peers), "max_turns": 2}
t.update(json.loads(extra))
json.dump({"skill_name": "demo-skill", "evals": [{"id": "dm-001", "prompt": "x", "expectations": []}],
           "triggers": t}, open(path, "w"), indent=2)
PY
}

reset_state() {
  rm -rf "$STUB_STATE" "$skill/eval-results" "$EVAL_RUNS_ROOT"
  mkdir -p "$STUB_STATE"
  : >"$STUB_LOG"
}

calls() { grep -c '^CALL' "$STUB_LOG" 2>/dev/null || true; }

run_runner() {
  # run_runner <args...>  -> sets out / rc
  out="$(python3 "$runner" --skill-dir "$skill" "$@" 2>"$sandbox/stderr")"
  rc=$?
}

# ---------------------------------------------------------------------------
echo "=== TEST: --dry-run ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:T]] commit"},{"id":"s2","prompt":"[[SEQ:N]] save"}]' \
            '[{"id":"n1","prompt":"[[SEQ:N]] rebase","near_miss_of":"git-rebase"}]'
run_runner --dry-run
check "dry-run exit" "0" "$rc"
check "dry-run STATUS" "OK" "$(field "$out" STATUS)"
check "dry-run MODE" "dry-run" "$(field "$out" MODE)"
check "dry-run PROMPTS" "3" "$(field "$out" PROMPTS)"
check "dry-run PLANNED_RUNS" "3" "$(field "$out" PLANNED_RUNS)"
check "dry-run MAX_COST_USD" "0.15" "$(field "$out" MAX_COST_USD)"
check "dry-run MAX_TURNS" "2" "$(field "$out" MAX_TURNS)"
check "dry-run plugin dirs (own + peer)" "$mkt/demo-plugin,$mkt/peer-plugin" "$(field "$out" PLUGIN_DIRS)"
check "dry-run no REASON on OK" "" "$(field "$out" REASON)"
check "dry-run plan lists near miss" "yes" "$(printf '%s\n' "$out" | grep -q '^  - ID=n1 EXPECTED=no_trigger NEAR_MISS_OF=git-rebase$' && echo yes || echo no)"
check "dry-run ran no rollout" "0" "$(calls)"
check "dry-run wrote no copy" "no" "$([ -e "$skill/eval-results/triggers.json" ] && echo yes || echo no)"
check "dry-run wrote no runs" "no" "$([ -e "$EVAL_RUNS_ROOT" ] && echo yes || echo no)"
check "dry-run block closes" "yes" "$(printf '%s\n' "$out" | tail -1 | grep -qx '=== END TRIGGER EVALS ===' && echo yes || echo no)"

run_runner --dry-run --runs 3 --total-budget-usd 0.20
check "dry-run over budget exit" "0" "$rc"
check "dry-run over budget STATUS" "WARN" "$(field "$out" STATUS)"
check "dry-run over budget PLANNED_RUNS" "9" "$(field "$out" PLANNED_RUNS)"
check "dry-run over budget REASON" "yes" "$(field "$out" REASON | grep -q '^plan_exceeds_budget: .*aborts after at most 4 runs' && echo yes || echo no)"

run_runner --dry-run --only s2
check "dry-run --only PROMPTS" "1" "$(field "$out" PROMPTS)"

# ---------------------------------------------------------------------------
echo "=== TEST: usage errors (exit 2) ==="
out="$(python3 "$runner" --skill-dir "$sandbox/nope" 2>&1)"; rc=$?
check "missing skill dir exit" "2" "$rc"
check "missing skill dir STATUS" "ERROR" "$(field "$out" STATUS)"
run_runner --dry-run --only zz
check "unknown --only exit" "2" "$rc"
run_runner --dry-run --runs 0
check "--runs 0 exit" "2" "$rc"
cp "$skill/evals.json" "$sandbox/evals.bak"
printf '{"skill_name":"demo-skill","evals":[]}\n' >"$skill/evals.json"
run_runner --dry-run
check "no triggers block exit" "2" "$rc"
check "no triggers block REASON" "yes" "$(field "$out" REASON | grep -q 'no triggers block' && echo yes || echo no)"
cp "$sandbox/evals.bak" "$skill/evals.json"
EVAL_ROLLOUT_SCRIPT="$sandbox/missing.sh" run_runner
check "missing rollout script (live) exit" "2" "$rc"

# ---------------------------------------------------------------------------
echo "=== TEST: triggers-block validation (exit 1) ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:T]] a"},{"id":"s1","prompt":"b"},{"id":"dm-001","prompt":"c"},{"id":"s4","prompt":"  "}]' \
            '[{"id":"n1","prompt":"d","near_miss_of":""}]' '["peer-plugin","notaplugin","missing-plugin","../escape"]' \
            '{"max_turns":0}'
run_runner --dry-run
check "invalid block exit" "1" "$rc"
check "invalid block STATUS" "ERROR" "$(field "$out" STATUS)"
check "invalid block ISSUE_COUNT" "8" "$(field "$out" ISSUE_COUNT)"
for frag in "duplicates triggers.should_trigger\[0\]" "collides with an evals\[\].id" "should_trigger\[3\].prompt must be a non-empty" \
            "near_miss_of must be" "'notaplugin' is not a plugin dir" "'missing-plugin' is not a plugin dir" \
            "must not contain '..'" "max_turns must be a positive integer"; do
  check "invalid block reports: $frag" "yes" "$(printf '%s\n' "$out" | grep -q -- "TYPE=invalid_triggers MSG=.*$frag" && echo yes || echo no)"
done
check "invalid block ran no rollout" "0" "$(calls)"

write_evals '[{"id":"s1","prompt":"x"}]' '[]' '[]' '{"skill":"other-plugin:demo-skill"}'
run_runner --dry-run
check "wrong plugin in triggers.skill exit" "1" "$rc"
write_evals '[{"id":"s1","prompt":"x"}]' '[]' '[]' '{"skill":"demo-skill"}'
run_runner --dry-run
check "bare triggers.skill rejected" "1" "$rc"
write_evals '[]' '[]' '[]'
run_runner --dry-run
check "no prompts rejected" "1" "$rc"

# ---------------------------------------------------------------------------
echo "=== TEST: tp/fp/fn/tn maths + triggers.json shape + argv ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:T]] commit this"},{"id":"s2","prompt":"[[SEQ:N]] save work"},{"id":"s3","prompt":"[[SEQ:B]] bare"},{"id":"s4","prompt":"[[SEQ:D]] denied"}]' \
            '[{"id":"n1","prompt":"[[SEQ:N]] rebase?"},{"id":"n2","prompt":"[[SEQ:P]] pr title","near_miss_of":"peer-plugin:peer-skill"},{"id":"n3","prompt":"[[SEQ:O]] other"},{"id":"n4","prompt":"[[SEQ:C]] changelog"}]'
run_runner
check "maths exit (WARN)" "0" "$rc"
check "maths STATUS" "WARN" "$(field "$out" STATUS)"
check "maths MODE" "live" "$(field "$out" MODE)"
check "maths TP" "3" "$(field "$out" TP)"
check "maths FP" "1" "$(field "$out" FP)"
check "maths FN" "1" "$(field "$out" FN)"
check "maths TN" "3" "$(field "$out" TN)"
check "maths ERRORS" "0" "$(field "$out" ERRORS)"
check "maths RECALL" "0.75" "$(field "$out" RECALL)"
check "maths PRECISION" "0.75" "$(field "$out" PRECISION)"
check "maths FPR" "0.25" "$(field "$out" FPR)"
# T and P are killed (cost unknown) -> charged 0.05 each; N,B,D,N,O at 0.01; C at 0.02.
check "maths TOTAL_COST_USD (killed runs at cap)" "0.17" "$(field "$out" TOTAL_COST_USD)"
check "maths BUDGET_ABORTED" "false" "$(field "$out" BUDGET_ABORTED)"
check "maths MODEL_ID" "claude-haiku-stub" "$(field "$out" MODEL_ID)"
check "maths REASON names the fp" "yes" "$(field "$out" REASON | grep -q '^false_positives: 1 false positive(s) > --max-false-positives 0: n4' && echo yes || echo no)"
check "maths results row s3" "yes" "$(printf '%s\n' "$out" | grep -qx '  - ID=s3 EXPECTED=trigger TRIGGERED=true RATE=1 OUTCOME=tp STATUS=OK' && echo yes || echo no)"
check "maths results row n3 (other plugin, same bare name)" "yes" "$(printf '%s\n' "$out" | grep -qx '  - ID=n3 EXPECTED=no_trigger TRIGGERED=false RATE=0 OUTCOME=tn STATUS=OK' && echo yes || echo no)"
tj="$(field "$out" OUTPUT)"
check "default output under EVAL_RUNS_ROOT" "yes" "$(case "$tj" in "$EVAL_RUNS_ROOT"/demo-plugin/demo-skill/triggers/*/triggers.json) echo yes ;; *) echo no ;; esac)"
check "triggers.json exists" "yes" "$([ -f "$tj" ] && echo yes || echo no)"
check "copy path" "$skill/eval-results/triggers.json" "$(field "$out" COPY)"
check "copy identical to output" "yes" "$(cmp -s "$tj" "$skill/eval-results/triggers.json" && echo yes || echo no)"
check "json top-level keys" '["finished_at","harness","issues","max_budget_usd_per_prompt","max_turns","model","model_id","plugin_dirs","prompts","runs_dir","runs_per_prompt","skill","skill_dir","started_at","status","summary","thresholds","total_budget_usd","version"]' "$(jf "$tj" 'sorted(d)')"
check "json version/harness/skill" '[1,"claude-code","demo-plugin:demo-skill"]' "$(jf "$tj" '[d["version"],d["harness"],d["skill"]]')"
check "json summary" '{"abort_reason":null,"aborted":false,"attempted":8,"cost_includes_cap_charges":true,"errors":0,"fn":1,"fp":1,"fpr":0.25,"precision":0.75,"recall":0.75,"skipped":0,"tn":3,"total_cost":0.17,"tp":3}' "$(jf "$tj" 'd["summary"]')"
check "json row keys" '["cost","cost_known","expected","id","kind","near_miss_of","outcome","prompt","prompt_sha256","runs","runs_error","runs_ok","skills_invoked","status","trigger_rate","triggered"]' "$(jf "$tj" 'sorted(d["prompts"][0])')"
check "json s1 row" '[true,["demo-plugin:demo-skill"],0.05,false,"OK","tp"]' "$(jf "$tj" '[d["prompts"][0][k] for k in ("triggered","skills_invoked","cost","cost_known","status","outcome")]')"
check "json s4 denied counts as triggered" '[true,"tp"]' "$(jf "$tj" '[d["prompts"][3]["triggered"],d["prompts"][3]["outcome"]]')"
check "json n2 near_miss_of + peer skill" '["peer-plugin:peer-skill",["peer-plugin:peer-skill"],false]' "$(jf "$tj" '[d["prompts"][5]["near_miss_of"],d["prompts"][5]["skills_invoked"],d["prompts"][5]["triggered"]]')"
check "json run record" '[1,null,0.05,false,"stopped_on_skill","OK"]' "$(jf "$tj" '[d["prompts"][0]["runs"][0][k] for k in ("run","cost","cost_charged","cost_known","stop_reason","status")]')"
check "json thresholds" '{"max_false_positives":0,"min_recall":0.67,"trigger_rate_min":0.5}' "$(jf "$tj" 'd["thresholds"]')"
check "json status" '"WARN"' "$(jf "$tj" 'd["status"]')"
check "rollout called once per prompt" "8" "$(calls)"
first_call="$(grep -m1 '^CALL' "$STUB_LOG")"
for flag in "--allowed-tools Skill" "--permission default" "--stop-on-skill" "--max-turns 2" "--model haiku" \
            "--max-budget-usd 0.05" "--plugin-dir $mkt/demo-plugin" "--plugin-dir $mkt/peer-plugin" "--no-snapshot"; do
  check "rollout argv has: $flag" "yes" "$(printf '%s\n' "$first_call" | grep -qF -- " $flag" && echo yes || echo no)"
done
check "every workdir was empty" "8" "$(grep -c 'WD_EMPTY=yes' "$STUB_LOG")"
wd1="$(grep -m1 '^WD=' "$STUB_LOG" | sed 's/^WD=\([^ ]*\) .*/\1/')"
check "workdir outside the repo" "yes" "$(case "$wd1/" in "$repo_root"/*) echo no ;; *) echo yes ;; esac)"
check "workdir removed after the run" "no" "$([ -e "$wd1" ] && echo yes || echo no)"
check "run dir kept per prompt" "yes" "$([ -f "$(dirname "$tj")/s1-run-1/rollout.out" ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo "=== TEST: STATUS OK + --output ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:T]] commit"}]' '[{"id":"n1","prompt":"[[SEQ:N]] explain"}]'
run_runner --output "$sandbox/out/custom.json"
check "OK exit" "0" "$rc"
check "OK STATUS" "OK" "$(field "$out" STATUS)"
check "OK no REASON" "" "$(field "$out" REASON)"
check "OK ISSUE_COUNT" "0" "$(field "$out" ISSUE_COUNT)"
check "OK --output honoured" "$sandbox/out/custom.json" "$(field "$out" OUTPUT)"
check "OK custom output exists" "yes" "$([ -f "$sandbox/out/custom.json" ] && echo yes || echo no)"
check "OK copy written too" "yes" "$(cmp -s "$sandbox/out/custom.json" "$skill/eval-results/triggers.json" && echo yes || echo no)"
check "OK runs dir beside --output" "yes" "$([ -d "$sandbox/out/custom-runs/s1-run-1" ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
# A smoke/test run must be able to leave a skill's genuine eval-results alone:
# the offline smoke test once overwrote git-commit's real triggers.json.
echo "=== TEST: --no-copy leaves <skill>/eval-results untouched ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:T]] commit"}]' '[{"id":"n1","prompt":"[[SEQ:N]] explain"}]'
mkdir -p "$skill/eval-results"
printf '{"genuine":true}\n' >"$skill/eval-results/triggers.json"
run_runner --output "$sandbox/out/nocopy.json" --no-copy
check "--no-copy exit" "0" "$rc"
check "--no-copy STATUS" "OK" "$(field "$out" STATUS)"
check "--no-copy COPY=none" "none" "$(field "$out" COPY)"
check "--no-copy output still written" "yes" "$([ -f "$sandbox/out/nocopy.json" ] && echo yes || echo no)"
check "--no-copy genuine copy untouched" '{"genuine":true}' "$(cat "$skill/eval-results/triggers.json")"

# ---------------------------------------------------------------------------
echo "=== TEST: precision null when nothing predicted positive ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:N]] a"},{"id":"s2","prompt":"[[SEQ:N]] b"}]' '[{"id":"n1","prompt":"[[SEQ:N]] c"}]'
run_runner
check "null-precision exit (WARN)" "0" "$rc"
check "null-precision PRECISION empty" "" "$(field "$out" PRECISION)"
check "null-precision RECALL" "0" "$(field "$out" RECALL)"
check "null-precision STATUS" "WARN" "$(field "$out" STATUS)"
check "null-precision REASON" "yes" "$(field "$out" REASON | grep -q '^recall_below_threshold: recall 0 < --min-recall 0.67' && echo yes || echo no)"
tj="$(field "$out" OUTPUT)"
check "null-precision json" '[null,0.0,0.0]' "$(jf "$tj" '[d["summary"]["precision"],d["summary"]["recall"],d["summary"]["fpr"]]')"
# Only negatives selected: recall and precision both null, no recall WARN.
reset_state
run_runner --only n1
check "negatives-only STATUS" "OK" "$(field "$out" STATUS)"
check "negatives-only RECALL empty" "" "$(field "$out" RECALL)"
check "negatives-only PRECISION empty" "" "$(field "$out" PRECISION)"
check "negatives-only ran one prompt" "1" "$(calls)"

# ---------------------------------------------------------------------------
echo "=== TEST: --runs 3 rate >= 0.5 rule ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:TTN]] a"},{"id":"s2","prompt":"[[SEQ:TNN]] b"},{"id":"s3","prompt":"[[SEQ:TEN]] c"}]' \
            '[{"id":"n1","prompt":"[[SEQ:NNC]] d"}]'
run_runner --runs 3 --total-budget-usd 1.00
check "runs3 exit" "0" "$rc"
tj="$(field "$out" OUTPUT)"
check "runs3 rates" '[0.6667,0.3333,0.5,0.3333]' "$(jf "$tj" '[r["trigger_rate"] for r in d["prompts"]]')"
check "runs3 triggered" '[true,false,true,false]' "$(jf "$tj" '[r["triggered"] for r in d["prompts"]]')"
check "runs3 s3 ok/error runs" '[2,1,"OK"]' "$(jf "$tj" '[d["prompts"][2][k] for k in ("runs_ok","runs_error","status")]')"
check "runs3 TP/FN/TN/FP" "2/1/1/0" "$(field "$out" TP)/$(field "$out" FN)/$(field "$out" TN)/$(field "$out" FP)"
check "runs3 rollout calls" "12" "$(calls)"
check "runs3 RATE line" "yes" "$(printf '%s\n' "$out" | grep -qx '  - ID=s1 EXPECTED=trigger TRIGGERED=true RATE=0.6667 OUTCOME=tp STATUS=OK' && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo "=== TEST: ERROR rows excluded ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:E]] a"},{"id":"s2","prompt":"[[SEQ:T]] b"}]' \
            '[{"id":"n1","prompt":"[[SEQ:N]] c"},{"id":"n2","prompt":"[[SEQ:N]] d"}]'
run_runner
check "error-row exit" "0" "$rc"
check "error-row STATUS (WARN, not ERROR at 25%)" "WARN" "$(field "$out" STATUS)"
check "error-row ERRORS" "1" "$(field "$out" ERRORS)"
check "error-row TP/FN/TN/FP" "1/0/2/0" "$(field "$out" TP)/$(field "$out" FN)/$(field "$out" TN)/$(field "$out" FP)"
check "error-row RECALL ignores the error row" "1" "$(field "$out" RECALL)"
check "error-row REASON" "yes" "$(field "$out" REASON | grep -q '^prompt_error: s1: truncated_stream' && echo yes || echo no)"
tj="$(field "$out" OUTPUT)"
check "error-row json row" '["ERROR","error",null,0.05]' "$(jf "$tj" '[d["prompts"][0][k] for k in ("status","outcome","triggered","cost")]')"

reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:E]] a"},{"id":"s2","prompt":"[[SEQ:E]] b"}]' \
            '[{"id":"n1","prompt":"[[SEQ:E]] c"},{"id":"n2","prompt":"[[SEQ:N]] d"}]'
run_runner
check ">50% errors exit" "1" "$rc"
check ">50% errors STATUS" "ERROR" "$(field "$out" STATUS)"
check ">50% errors REASON" "yes" "$(field "$out" REASON | grep -q '^too_many_errors: 3 of 4 prompts errored' && echo yes || echo no)"
check ">50% errors still writes triggers.json" "yes" "$([ -f "$(field "$out" OUTPUT)" ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
echo "=== TEST: budget abort keeps partial results ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:T]] a"},{"id":"s2","prompt":"[[SEQ:T]] b"},{"id":"s3","prompt":"[[SEQ:T]] c"}]' \
            '[{"id":"n1","prompt":"[[SEQ:N]] d"}]'
run_runner --total-budget-usd 0.12
check "budget exit" "1" "$rc"
check "budget STATUS" "ERROR" "$(field "$out" STATUS)"
check "budget BUDGET_ABORTED" "true" "$(field "$out" BUDGET_ABORTED)"
check "budget rollouts run before abort" "2" "$(calls)"
check "budget TOTAL_COST_USD (2 killed runs at cap)" "0.1" "$(field "$out" TOTAL_COST_USD)"
check "budget SKIPPED" "2" "$(field "$out" SKIPPED)"
check "budget TP kept" "2" "$(field "$out" TP)"
check "budget REASON" "yes" "$(field "$out" REASON | grep -q '^budget_abort: budget: spent 0.1 USD' && echo yes || echo no)"
tj="$(field "$out" OUTPUT)"
check "budget partial json statuses" '["OK","OK","SKIPPED","SKIPPED"]' "$(jf "$tj" '[r["status"] for r in d["prompts"]]')"
check "budget skipped row shape" '[null,[],0.0,"skipped"]' "$(jf "$tj" '[d["prompts"][2][k] for k in ("triggered","runs","cost","outcome")]')"
check "budget summary" '[true,0.1,2]' "$(jf "$tj" '[d["summary"]["aborted"],d["summary"]["total_cost"],d["summary"]["attempted"]]')"
check "budget copy written" "yes" "$(cmp -s "$tj" "$skill/eval-results/triggers.json" && echo yes || echo no)"
# Known costs leave room: 0.01 each never trips a 0.12 total with a 0.05 cap.
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:C]] a"},{"id":"s2","prompt":"[[SEQ:C]] b"},{"id":"s3","prompt":"[[SEQ:C]] c"}]' '[]'
run_runner --total-budget-usd 0.12
check "known-cost budget not aborted" "false" "$(field "$out" BUDGET_ABORTED)"
check "known-cost total" "0.06" "$(field "$out" TOTAL_COST_USD)"

# ---------------------------------------------------------------------------
echo "=== TEST: rollout usage error aborts ==="
reset_state
write_evals '[{"id":"s1","prompt":"[[SEQ:U]] a"},{"id":"s2","prompt":"[[SEQ:T]] b"}]' '[]'
run_runner
check "usage-abort exit" "1" "$rc"
check "usage-abort STATUS" "ERROR" "$(field "$out" STATUS)"
check "usage-abort REASON" "yes" "$(field "$out" REASON | grep -q '^rollout_usage: rollout usage error: usage: claude CLI not found' && echo yes || echo no)"
check "usage-abort stops after first call" "1" "$(calls)"
check "usage-abort charges nothing" "0" "$(field "$out" TOTAL_COST_USD)"

# ---------------------------------------------------------------------------
# Contract check against the REAL rollout_headless.sh + parse_trace.py, with
# the fake `claude` stub first on PATH replaying stream-skill-commit.jsonl
# (which invokes git-plugin:git-commit). Proves the runner parses the real
# KEY=VALUE block and trace.json, not just this file's stub.
echo "=== TEST: real rollout_headless.sh + fake claude ==="
real_rollout="$scripts_dir/rollout_headless.sh"
fake="$script_dir/fixtures/fake-claude.sh"
# The scripts ship together: a missing one is a broken tree, not a skip (a
# stand-in or a skip here would hide the integration break this check exists
# for). Only a missing jq -- a host tool -- skips.
for f in "$real_rollout" "$scripts_dir/parse_trace.py" "$fake"; do
  [ -f "$f" ] || { echo "FAIL: $(basename "$f") missing; the real-rollout contract cannot run" >&2; fail_count=$((fail_count + 1)); }
done
if [ -f "$real_rollout" ] && [ -f "$scripts_dir/parse_trace.py" ] && [ -f "$fake" ] && command -v jq >/dev/null 2>&1; then
  bin="$sandbox/bin"
  mkdir -p "$bin" "$mkt/git-plugin/.claude-plugin" "$mkt/git-plugin/skills/git-commit"
  {
    echo '#!/usr/bin/env bash'
    printf 'export %q\n' "FAKE_CLAUDE_DELAY=0.05"
    printf 'exec bash %q "$@"\n' "$fake"
  } >"$bin/claude"
  chmod +x "$bin/claude"
  printf '{"name":"git-plugin","version":"0.0.0"}\n' >"$mkt/git-plugin/.claude-plugin/plugin.json"
  gskill="$mkt/git-plugin/skills/git-commit"
  printf -- '---\nname: git-commit\ndescription: Commit. Use when committing.\n---\n# Commit\n' >"$gskill/SKILL.md"
  printf '{"skill_name":"git-commit","evals":[],"triggers":{"skill":"git-plugin:git-commit","should_trigger":[{"id":"t1","prompt":"commit the README"}],"should_not_trigger":[],"max_turns":2}}\n' >"$gskill/evals.json"
  rm -rf "$EVAL_RUNS_ROOT"
  out="$(EVAL_ROLLOUT_SCRIPT="$real_rollout" PATH="$bin:$PATH" python3 "$runner" --skill-dir "$gskill" 2>"$sandbox/stderr")"
  rc=$?
  check "real rollout exit" "0" "$rc"
  check "real rollout STATUS" "OK" "$(field "$out" STATUS)"
  check "real rollout TP" "1" "$(field "$out" TP)"
  check "real rollout ERRORS" "0" "$(field "$out" ERRORS)"
  tj="$(field "$out" OUTPUT)"
  check "real rollout run status + skill" '["OK",["git-plugin:git-commit"]]' "$(jf "$tj" '[d["prompts"][0]["runs"][0]["status"],d["prompts"][0]["skills_invoked"]]')"
  check "real rollout stop reason" '"stopped_on_skill"' "$(jf "$tj" 'd["prompts"][0]["runs"][0]["stop_reason"]')"
  check "real rollout killed run charged at cap" '[0.05,false]' "$(jf "$tj" '[d["prompts"][0]["cost"],d["prompts"][0]["cost_known"]]')"
else
  echo "NOTE: real-rollout contract check not run (see FAIL above, or jq absent)"
fi

# ---------------------------------------------------------------------------
echo "=== TEST: Step 4b is not silently covered by the workflow template ==="
# Regression: evaluate-skill/SKILL.md said the bundled workflow "covers Steps
# 2-7", which includes Step 4b, but the template has no trigger stage -- an
# agent trusting the claim on the harness path dropped --triggers silently.
# While the template never calls the trigger runner, SKILL.md must say Step 4b
# runs outside it.
skill_md="$repo_root/evaluate-plugin/skills/evaluate-skill/SKILL.md"
wf_js="$repo_root/evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js"
if grep -q 'run_trigger_evals' "$wf_js"; then
  pass_count=$((pass_count + 1))
else
  check "SKILL.md: workflow coverage excludes Step 4b" "yes" "$(grep -q 'except Step 4b' "$skill_md" && echo yes || echo no)"
  check "SKILL.md: no 'skip Steps 4-7' (4b sits inside it)" "no" "$(grep -q 'Steps 4-7' "$skill_md" && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
