#!/usr/bin/env bash
# Test assertions use the `cmd && pass++ || fail` idiom deliberately (pass++ is
# arithmetic that always exits 0 here, so the || branch only runs on real
# failure) and pipe fixtures through cat for readability. Expectation JSON and
# fixture text carry literal `$` / backticks in single quotes on purpose
# (SC2016). Suppress the style nags rather than rewrite every assertion.
# shellcheck disable=SC2015,SC2002,SC2016
#
# Regression test for grade_deterministic.py and render_matrix_report.py.
#
# Per .claude/rules/regression-testing.md, the deterministic grader (the
# token-frugality lever of the cross-model framework) ships with a test that
# proves: (a) machine-checkable assertions pass on good output, (b) they fail
# on bad output, (c) judge-typed assertions are deferred not graded, and
# (d) the matrix renderer produces the delta table.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(dirname "$script_dir")"
fixtures="$script_dir/fixtures"
evals="$scripts_dir/../../git-plugin/skills/git-commit/evals.json"
grader="$scripts_dir/grade_deterministic.py"
renderer="$scripts_dir/render_matrix_report.py"

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
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2
}

echo "=== TEST: deterministic grading (gc-001) ==="

# Good output: all 5 deterministic checks pass. gc-001's former bare-string
# "imperative mood" judge is now an absent_regex (#2667 rec 5), so nothing is
# deferred to the LLM judge and the status is OK rather than WARN.
good_out="$(python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-good.txt")"
check "good: deterministic total" "5" "$(field "$good_out" DETERMINISTIC_TOTAL)"
check "good: deterministic passed" "5" "$(field "$good_out" DETERMINISTIC_PASSED)"
check "good: deterministic failed" "0" "$(field "$good_out" DETERMINISTIC_FAILED)"
check "good: judge pending" "0" "$(field "$good_out" JUDGE_PENDING)"
check "good: status" "OK" "$(field "$good_out" STATUS)"

# Bad output: all 5 deterministic checks fail -- including the imperative-mood
# check, which the past-tense "Added" in the bad fixture must trip.
bad_out="$(python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-bad.txt")"
check "bad: deterministic passed" "0" "$(field "$bad_out" DETERMINISTIC_PASSED)"
check "bad: deterministic failed" "5" "$(field "$bad_out" DETERMINISTIC_FAILED)"
check "bad: status" "ERROR" "$(field "$bad_out" STATUS)"

# --strict exits non-zero when a deterministic check fails.
python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-bad.txt" --strict >/dev/null
check "bad: --strict exit code" "1" "$?"
python3 "$grader" --evals "$evals" --eval-id gc-001 --output "$fixtures/gc-001-good.txt" --strict >/dev/null
check "good: --strict exit code" "0" "$?"

echo "=== TEST: stdin + JSON mode ==="
json_out="$(cat "$fixtures/gc-001-good.txt" | python3 "$grader" --evals "$evals" --eval-id gc-001 --output - --json)"
check "json: passed count" "5" "$(printf '%s' "$json_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["deterministic_passed"])')"

echo "=== TEST: abstention control (#2690) ==="
# Every assertion shape is positive (something must appear or match) and the
# judge passes only on evidence of satisfaction, so a case whose honest answer
# is "this cannot be done" has nothing to pass and a fabricated answer has
# nothing to fail. The control is an abstain case whose fabrication detector is
# an absent_regex: the fabricated answer FAILS it, the honest refusal PASSES it.
abstain_ids="$(python3 -c 'import json,sys; print(" ".join(e["id"] for e in json.load(open(sys.argv[1]))["evals"] if e.get("expected_outcome") == "abstain"))' "$evals")"
check "evals.json carries >=1 abstention case" "true" "$([ -n "$abstain_ids" ] && echo true || echo false)"
check "gc-006 is an abstention case" "true" "$(case " $abstain_ids " in *" gc-006 "*) echo true ;; *) echo false ;; esac)"

# A fabricated answer: a plausible commit message for changes that do not exist.
fab_out="$(python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-fabricated.txt")"
check "fabricated: expected outcome reported" "abstain" "$(field "$fab_out" EXPECTED_OUTCOME)"
check "fabricated: absent_regex fails" "true" "$(grep -q 'CHECK=absent_regex RESULT=FAIL' <<<"$fab_out" && echo true || echo false)"
check "fabricated: status" "ERROR" "$(field "$fab_out" STATUS)"
python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-fabricated.txt" --strict >/dev/null
check "fabricated: --strict exit code" "1" "$?"

# The honest refusal passes every deterministic check; only the judge half is
# deferred. Guard integrity: the total must be non-zero, or "0 failed" is
# what a case with no deterministic checks at all would also report.
ref_out="$(python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-refusal.txt")"
check "refusal: deterministic total" "2" "$(field "$ref_out" DETERMINISTIC_TOTAL)"
check "refusal: deterministic failed" "0" "$(field "$ref_out" DETERMINISTIC_FAILED)"
check "refusal: absent_regex passes" "true" "$(grep -q 'CHECK=absent_regex RESULT=PASS' <<<"$ref_out" && echo true || echo false)"
check "refusal: judge pending" "1" "$(field "$ref_out" JUDGE_PENDING)"
check "refusal: status" "WARN" "$(field "$ref_out" STATUS)"

# A satisfiable case reports comply (the default when the field is absent).
check "gc-001 reports comply" "comply" "$(field "$good_out" EXPECTED_OUTCOME)"
check "json: expected_outcome field" "abstain" "$(python3 "$grader" --evals "$evals" --eval-id gc-006 --output "$fixtures/gc-006-refusal.txt" --json | python3 -c 'import json,sys; print(json.load(sys.stdin).get("expected_outcome"))')"

# A misspelled expected_outcome fails fast (exit 2) instead of silently grading
# the case as comply, which would fail an honest refusal on the judge half.
bad_evals="$(mktemp)"
[ -n "$bad_evals" ] || { echo "mktemp failed" >&2; exit 1; }
printf '%s\n' '{"evals":[{"id":"x-001","expected_outcome":"abstian","expectations":[]}]}' > "$bad_evals"
python3 "$grader" --evals "$bad_evals" --eval-id x-001 --output "$fixtures/gc-006-refusal.txt" >/dev/null 2>&1
check "invalid expected_outcome exit code" "2" "$?"
rm -f "$bad_evals"

# The judge half of the rule lives in an agent prompt, which
# plugin-compliance-check.sh's check_skill_body() cannot reach, so pin its
# load-bearing phrases here (the #2301 pattern for a prompt outside SKILL.md).
grader_md="$scripts_dir/../agents/eval-grader.md"
for tok in 'expected_outcome' 'the correct abstention is the passing response' 'A fabricated deliverable fails'; do
  grep -qF -- "$tok" "$grader_md" \
    && pass_count=$((pass_count + 1)) \
    || { echo "FAIL: eval-grader.md lost the abstention rule token '$tok'" >&2; fail_count=$((fail_count + 1)); }
done

echo "=== TEST: matrix report rendering ==="
report="$(python3 "$renderer" "$fixtures/example-model-matrix.json")"
grep -q "earns its keep" <<<"$report" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: report missing 'earns its keep' verdict" >&2; fail_count=$((fail_count + 1)); }
grep -q "claude-opus-4-8" <<<"$report" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: report missing pinned model id" >&2; fail_count=$((fail_count + 1)); }
grep -q "Portability flag" <<<"$report" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: report missing portability flag (opus-haiku spread = 30pts)" >&2; fail_count=$((fail_count + 1)); }

# Executability flag (Slice 2): absent when haiku (0.7) is above the 0.5 floor.
grep -q "executable_on_haiku=false" <<<"$report" \
  && { echo "FAIL: example report should NOT fire executability flag (haiku 0.7 >= floor)" >&2; fail_count=$((fail_count + 1)); } \
  || pass_count=$((pass_count + 1))

echo "=== TEST: executability callout fires when haiku < floor < opus ==="
low_report="$(python3 "$renderer" "$fixtures/low-haiku-model-matrix.json")"
grep -q "executable_on_haiku=false" <<<"$low_report" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: low-haiku report missing executability flag (haiku 0.3 < 0.5 <= opus 0.9)" >&2; fail_count=$((fail_count + 1)); }
grep -q "Executability flag" <<<"$low_report" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: low-haiku report missing 'Executability flag' heading" >&2; fail_count=$((fail_count + 1)); }

# ---------------------------------------------------------------------------
# Trace and workspace checks (headless harness, interface C)
# ---------------------------------------------------------------------------
# Every new check type is exercised in its pass, fail and harness-deferred
# forms against a temporary evals.json (the shipped git-commit evals.json is
# not edited here). Workspaces are built in a guarded mktemp root so no nested
# .git is ever committed and an empty mktemp result can never point git at
# this checkout (issue #1692).
tmp_root="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
[ -n "$tmp_root" ] && [ -d "$tmp_root" ] || { echo "mktemp gave no dir" >&2; exit 1; }
trap 'rm -rf "$tmp_root"' EXIT

one_evals="$tmp_root/one-evals.json"
no_trace_out="$tmp_root/plain.txt"
printf 'docs(readme): add project readme\n' > "$no_trace_out"

grade_one() {
  # grade_one <expectation-json> <output-file> [grader args...]
  #   -> PASS | FAIL | DEFERRED | HARNESS_DEFERRED (empty on a crash)
  local exp_json="$1" out_file="$2"
  shift 2
  printf '{"evals":[{"id":"t-1","expectations":[%s]}]}\n' "$exp_json" > "$one_evals"
  python3 "$grader" --evals "$one_evals" --eval-id t-1 --output "$out_file" "$@" 2>/dev/null \
    | grep -m1 -o 'RESULT=[A-Z_]*' | cut -d= -f2
}

evidence_one() {
  # evidence_one <expectation-json> <output-file> [grader args...] -> evidence text
  local exp_json="$1" out_file="$2"
  shift 2
  printf '{"evals":[{"id":"t-1","expectations":[%s]}]}\n' "$exp_json" > "$one_evals"
  python3 "$grader" --evals "$one_evals" --eval-id t-1 --output "$out_file" --json "$@" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); r=(d["deterministic"]+d["deferred"]+d["harness_deferred"])[0]; print(r.get("evidence",""))'
}

t_good="$fixtures/gc-007-good.trace.json"
t_bad="$fixtures/gc-007-bad.trace.json"
t_6="$fixtures/gc-006-nocommit.trace.json"

echo "=== TEST: trace checks ==="
# skill_triggered: full name, bare name, expect=false, deferred without a trace.
e='{"assertion":"a","check":"skill_triggered","skill":"git-plugin:git-commit"}'
check "skill_triggered full: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
check "skill_triggered full: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_bad")"
check "skill_triggered: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"skill_triggered","skill":"git-commit"}'
check "skill_triggered bare: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
e='{"assertion":"a","check":"skill_triggered","skill":"other-plugin:git-commit"}'
check "skill_triggered: other plugin's same bare name does not match" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
e='{"assertion":"a","check":"skill_triggered","skill":"git-commit","expect":false}'
check "skill_triggered expect=false: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_bad")"
check "skill_triggered expect=false: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
# A denied invocation still counts as triggered (routing chose the skill).
t_denied="$tmp_root/denied.trace.json"
python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); t["skills_invoked"][0]["denied"]=True; json.dump(t,open(sys.argv[2],"w"))' "$t_good" "$t_denied"
e='{"assertion":"a","check":"skill_triggered","skill":"git-plugin:git-commit"}'
check "skill_triggered: denied counts as triggered" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_denied")"
e='{"assertion":"a","check":"skill_triggered","skill":"git-commit","expect":"yes"}'
check "skill_triggered: non-bool expect is malformed" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"

# tool_called: name only, with pattern, min/max bounds, deferred.
e='{"assertion":"a","check":"tool_called","tool":"Skill"}'
check "tool_called: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
check "tool_called: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_bad")"
check "tool_called: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"tool_called","tool":"Bash","pattern":"git\\s+diff\\s+--cached"}'
check "tool_called pattern: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
check "tool_called pattern: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_bad")"
e='{"assertion":"a","check":"tool_called","tool":"Bash","max":2}'
check "tool_called max: over the bound fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
check "tool_called max: within the bound passes" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_bad")"
e='{"assertion":"a","check":"tool_called","tool":"Bash","min":3,"max":1}'
check "tool_called min>max is malformed" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
check "tool_called min>max evidence" "true" "$(evidence_one "$e" "$no_trace_out" --trace "$t_good" | grep -q '^malformed check' && echo true || echo false)"

# command_ran: pass, fail, max:0 ("never ran"), deferred.
e='{"assertion":"a","check":"command_ran","pattern":"git\\s+commit"}'
check "command_ran: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
check "command_ran: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_bad")"
check "command_ran: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"command_ran","pattern":"git\\s+commit","max":0}'
check "command_ran max:0: honest gc-006 trace passes" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_6")"
check "command_ran max:0: a commit fails it" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"
# A denied command did not run.
t_cmd_denied="$tmp_root/cmd-denied.trace.json"
python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); [c.update(denied=True) for c in t["bash_commands"] if "commit" in c["command"]]; json.dump(t,open(sys.argv[2],"w"))' "$t_good" "$t_cmd_denied"
check "command_ran max:0: a denied commit did not run" "PASS" "$(grade_one "$e" "$no_trace_out" --trace "$t_cmd_denied")"

echo "=== TEST: workspace checks ==="
outside="$tmp_root/outside"
mkdir -p "$outside"
printf 'TOP-SECRET\n' > "$outside/secret.txt"

gitc() { git -C "$1" -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false "${@:2}"; }

ws_good="$tmp_root/ws-good"
ws_bad="$tmp_root/ws-bad"
for ws in "$ws_good" "$ws_bad"; do
  mkdir -p "$ws"
  git -C "$ws" init -q
  gitc "$ws" commit -q --allow-empty -m initial
  printf '# Demo\n' > "$ws/README.md"
  git -C "$ws" add README.md
done
printf '%s\n' '{"name":"demo","enabled":true,"items":[{"id":1,"tags":["alpha","beta"]}]}' > "$ws_good/config.json"
printf 'not json {\n' > "$ws_bad/config.json"
printf 'TODO: nothing\n' > "$ws_good/notes.txt"
# Commit everything in the good workspace so its tree is clean.
git -C "$ws_good" add config.json notes.txt
gitc "$ws_good" commit -q -m "docs(readme): add project readme"
# A copy of it carrying symlinks that leave the workspace (escape tests).
ws_leak="$tmp_root/ws-leak"
cp -a "$ws_good" "$ws_leak"
ln -s "$outside/secret.txt" "$ws_leak/leak.txt"
ln -s "$outside" "$ws_leak/leakdir"

# file_exists
e='{"assertion":"a","check":"file_exists","path":"config.json"}'
check "file_exists: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
check "file_exists: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"file_exists","path":"missing.txt"}'
check "file_exists: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"file_exists","path":"missing.txt","expect":false}'
check "file_exists expect=false: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"

# file_regex: missing file is a FAIL
e='{"assertion":"a","check":"file_regex","path":"README.md","pattern":"^# Demo"}'
check "file_regex: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
check "file_regex: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"file_regex","path":"README.md","pattern":"^# Other"}'
check "file_regex: no match fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"file_regex","path":"nope.md","pattern":"x"}'
check "file_regex: missing file fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"

# file_absent_regex: missing file is a PASS
e='{"assertion":"a","check":"file_absent_regex","path":"notes.txt","pattern":"FIXME"}'
check "file_absent_regex: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
check "file_absent_regex: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"file_absent_regex","path":"notes.txt","pattern":"todo","flags":"i"}'
check "file_absent_regex: present fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"file_absent_regex","path":"nope.txt","pattern":"x"}'
check "file_absent_regex: missing file passes" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"

# json_path: equals / regex / exists, deferred, invalid JSON, malformed.
e='{"assertion":"a","check":"json_path","path":"config.json","query":"items[0].tags[1]","equals":"beta"}'
check "json_path equals: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
check "json_path: deferred" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out")"
check "json_path: invalid JSON fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_bad")"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"enabled","equals":1}'
check "json_path equals: true != 1" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"name","regex":"^de"}'
check "json_path regex: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"name","regex":"^x"}'
check "json_path regex: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"items[5]","exists":false}'
check "json_path exists=false: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"items[0].id","exists":false}'
check "json_path exists=false: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"name","equals":"demo","exists":true}'
check "json_path two comparators: malformed" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_good" | grep -q '^malformed check' && echo true || echo false)"
e='{"assertion":"a","check":"json_path","path":"config.json","query":"items..id","exists":true}'
check "json_path bad query: malformed" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_good" | grep -q '^malformed check' && echo true || echo false)"
# A malformed check surfaces even without its input -- it is not hidden behind the deferral.
check "json_path bad query: malformed even when deferred" "FAIL" "$(grade_one "$e" "$no_trace_out")"

echo "=== TEST: path and symlink escape ==="
for rel in '../outside/secret.txt' '/etc/hostname' 'leak.txt' 'leakdir/secret.txt'; do
  e="{\"assertion\":\"a\",\"check\":\"file_exists\",\"path\":\"$rel\"}"
  check "escape $rel: file_exists fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_leak")"
  e="{\"assertion\":\"a\",\"check\":\"file_regex\",\"path\":\"$rel\",\"pattern\":\"SECRET\"}"
  check "escape $rel: file_regex fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_leak")"
  # The escape is a FAIL, not the absent-file PASS -- reading outside is refused.
  e="{\"assertion\":\"a\",\"check\":\"file_absent_regex\",\"path\":\"$rel\",\"pattern\":\"SECRET\"}"
  check "escape $rel: file_absent_regex fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_leak")"
done
e='{"assertion":"a","check":"file_regex","path":"leak.txt","pattern":"SECRET"}'
check "symlink escape evidence names it" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_leak" | grep -q 'path escape' && echo true || echo false)"
# A '..' that stays inside the workspace is fine. (Through a symlinked dir it
# would not be: 'leakdir/..' is the link target's parent, per POSIX resolution.)
e='{"assertion":"a","check":"file_exists","path":".git/../README.md"}'
check "inside-workspace '..' resolves" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"

echo "=== TEST: run_command (exec gating, isolation, timeout) ==="
subj_re='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\\([^)]+\\))?!?: [a-z]'
e="{\"assertion\":\"a\",\"check\":\"run_command\",\"command\":\"git log -1 --format=%s\",\"stdout_regex\":\"$subj_re\"}"
check "run_command: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
check "run_command: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_bad" --allow-exec)"
check "run_command: deferred (no workspace)" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out" --allow-exec)"
check "run_command: gated without --allow-exec" "HARNESS_DEFERRED" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good")"
check "run_command gate evidence" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_good" | grep -q 'allow-exec' && echo true || echo false)"
e='{"assertion":"a","check":"run_command","command":"git status --porcelain","stdout_regex":"\\A\\Z"}'
check "run_command porcelain empty: pass" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
check "run_command porcelain empty: fail" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_bad" --allow-exec)"
e='{"assertion":"a","check":"run_command","command":"exit 3","expect_exit":3}'
check "run_command expect_exit" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
# Minimal env: a secret in the grader's env never reaches the command.
e='{"assertion":"a","check":"run_command","command":"test -z \"${EVAL_TEST_SECRET:-}\""}'
check "run_command: env is scrubbed" "PASS" "$(EVAL_TEST_SECRET=hunter2 grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
# Fresh temp copy: the snapshot is never mutated.
e='{"assertion":"a","check":"run_command","command":"rm -f README.md && touch MUTATED && test -f MUTATED"}'
check "run_command: mutating command runs" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
check "run_command: snapshot untouched" "true" "$([ -f "$ws_good/README.md" ] && [ ! -e "$ws_good/MUTATED" ] && echo true || echo false)"
# The snapshot's .git/config is agent-written: a planted core.fsmonitor must
# not execute when a check runs `git status` (it does without the override).
ws_fsm="$tmp_root/ws-fsm"
mkdir -p "$ws_fsm"
git -C "$ws_fsm" init -q
gitc "$ws_fsm" commit -q --allow-empty -m initial
git -C "$ws_fsm" config core.fsmonitor "touch $tmp_root/FSMONITOR-RAN; false"
e='{"assertion":"a","check":"run_command","command":"git status --porcelain"}'
check "run_command: git status runs" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_fsm" --allow-exec)"
check "run_command: planted fsmonitor never executes" "false" "$([ -e "$tmp_root/FSMONITOR-RAN" ] && echo true || echo false)"
# Timeout: a hung command fails promptly instead of hanging the grader.
e='{"assertion":"a","check":"run_command","command":"sleep 30","timeout":1}'
t_start=$SECONDS
check "run_command: timeout fails" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
check "run_command: timeout is prompt" "true" "$([ $((SECONDS - t_start)) -lt 15 ] && echo true || echo false)"
check "run_command: timeout evidence" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec | grep -q 'timed out' && echo true || echo false)"
e='{"assertion":"a","check":"run_command","command":"true","timeout":0}'
check "run_command: non-positive timeout is malformed" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec | grep -q '^malformed check' && echo true || echo false)"
# The gate's evidence carries the same "requires headless harness" prefix as
# every other harness deferral (docs + eval-grader.md promise that prefix).
e='{"assertion":"a","check":"run_command","command":"true"}'
check "run_command gate evidence prefix" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_good" | grep -q '^requires headless harness with --allow-exec' && echo true || echo false)"

echo "=== TEST: run_command on an agent-written workspace (hostile snapshot) ==="
# Each case below is a workspace the agent under test can leave behind; the
# rollout snapshot (cp -a) keeps all of them.
# (1) A FIFO made copytree raise shutil.Error out of main(): traceback, no
#     KEY=value block, every other result lost. Now that check FAILs alone.
ws_fifo="$tmp_root/ws-fifo"
mkdir -p "$ws_fifo"
printf 'hi\n' > "$ws_fifo/a.txt"
mkfifo "$ws_fifo/pipe"
fifo_evals="$tmp_root/fifo-evals.json"
cat > "$fifo_evals" <<'JSON'
{"evals":[{"id":"t-fifo","expectations":[
  {"assertion":"a.txt says hi","check":"file_regex","path":"a.txt","pattern":"hi"},
  {"assertion":"runs","check":"run_command","command":"true"}
]}]}
JSON
fifo_out="$(python3 "$grader" --evals "$fifo_evals" --eval-id t-fifo --output "$no_trace_out" --workspace "$ws_fifo" --allow-exec 2>&1)"
check "fifo: grader exits 0" "0" "$?"
check "fifo: no traceback" "false" "$(grep -q 'Traceback' <<<"$fifo_out" && echo true || echo false)"
check "fifo: other check still graded" "1" "$(field "$fifo_out" DETERMINISTIC_PASSED)"
check "fifo: run_command FAILs" "1" "$(field "$fifo_out" DETERMINISTIC_FAILED)"
e='{"assertion":"a","check":"run_command","command":"true"}'
check "fifo: evidence" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$ws_fifo" --allow-exec | grep -q '^workspace error' && echo true || echo false)"
# (2) A sparse file passes a block-count size measure (du) but copytree writes
#     it out at full size; the apparent-size cap refuses it before copying.
ws_sparse="$tmp_root/ws-sparse"
mkdir -p "$ws_sparse"
truncate -s 300M "$ws_sparse/sparse.bin"
t_start=$SECONDS
check "sparse: run_command FAILs" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_sparse" --allow-exec)"
check "sparse: refused before copying (<10s)" "true" "$([ $((SECONDS - t_start)) -lt 10 ] && echo true || echo false)"
check "sparse: no grade-exec dir left behind" "0" "$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'grade-exec-*' -newer "$ws_sparse/sparse.bin" 2>/dev/null | wc -l | tr -d ' ')"
# (3) A char device (/dev/zero) was read forever by copytree, before the
#     timeout applied. Root only (mknod).
if [ "$(id -u)" = "0" ] && mknod "$tmp_root/zdev-probe" c 1 5 2>/dev/null; then
  rm -f "$tmp_root/zdev-probe"
  ws_dev="$tmp_root/ws-dev"
  mkdir -p "$ws_dev"
  mknod "$ws_dev/z" c 1 5
  printf '{"evals":[{"id":"t-1","expectations":[%s]}]}\n' \
    '{"assertion":"a","check":"run_command","command":"true","timeout":1}' > "$one_evals"
  t_start=$SECONDS
  # `timeout` bounds a regression: the old copy read /dev/zero until the disk filled.
  dev_out="$(timeout -s INT 20 python3 "$grader" --evals "$one_evals" --eval-id t-1 --output "$no_trace_out" --workspace "$ws_dev" --allow-exec 2>&1)"
  check "device: grader returns" "0" "$?"
  check "device: run_command FAILs" "1" "$(field "$dev_out" DETERMINISTIC_FAILED)"
  check "device: refused promptly (<10s)" "true" "$([ $((SECONDS - t_start)) -lt 10 ] && echo true || echo false)"
fi
# (4) A .git symlink (or gitfile) pointing at another repo made `git log` read
#     THAT repo's HEAD -- an agent that never committed passed -- and `git
#     status` refreshed-and-wrote its index. Both are now a path escape FAIL.
ext_repo="$tmp_root/ext-repo"
mkdir -p "$ext_repo"
git -C "$ext_repo" init -q
printf 'x\n' > "$ext_repo/a.txt"
git -C "$ext_repo" add a.txt
gitc "$ext_repo" commit -q -m "feat: outside repo commit"
ext_index_before="$(stat -c %Y.%s "$ext_repo/.git/index" 2>/dev/null || stat -f %m.%z "$ext_repo/.git/index")"
sleep 1
ws_gitlink="$tmp_root/ws-gitlink"
mkdir -p "$ws_gitlink"
printf 'x\n' > "$ws_gitlink/a.txt"
ln -s "$ext_repo/.git" "$ws_gitlink/.git"
ws_gitfile="$tmp_root/ws-gitfile"
mkdir -p "$ws_gitfile"
printf 'x\n' > "$ws_gitfile/a.txt"
printf 'gitdir: %s\n' "$ext_repo/.git" > "$ws_gitfile/.git"
e="{\"assertion\":\"a\",\"check\":\"run_command\",\"command\":\"git log -1 --format=%s\",\"stdout_regex\":\"$subj_re\"}"
e2='{"assertion":"a","check":"run_command","command":"git status --porcelain"}'
for wsx in "$ws_gitlink" "$ws_gitfile"; do
  check "$(basename "$wsx"): outside HEAD never passes" "FAIL" "$(grade_one "$e" "$no_trace_out" --workspace "$wsx" --allow-exec)"
  check "$(basename "$wsx"): evidence is a path escape" "true" "$(evidence_one "$e" "$no_trace_out" --workspace "$wsx" --allow-exec | grep -q '^path escape' && echo true || echo false)"
  grade_one "$e2" "$no_trace_out" --workspace "$wsx" --allow-exec >/dev/null
done
ext_index_after="$(stat -c %Y.%s "$ext_repo/.git/index" 2>/dev/null || stat -f %m.%z "$ext_repo/.git/index")"
check "outside repo index never rewritten" "$ext_index_before" "$ext_index_after"
# A repo with no .git of its own must not discover one above the temp copy.
ws_nogit="$tmp_root/ws-nogit"
mkdir -p "$ws_nogit"
e='{"assertion":"a","check":"run_command","command":"git rev-parse --git-dir","expect_exit":128}'
check "no .git: git finds no repo above the copy" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_nogit" --allow-exec)"
# (5) A planted clean filter (.git/config + .gitattributes) ran an arbitrary
#     command in the grader on `git status`. The copied config is cut to
#     format keys, so the driver is undefined and inert.
ws_filter="$tmp_root/ws-filter"
mkdir -p "$ws_filter"
git -C "$ws_filter" init -q
printf '* filter=pwn\n' > "$ws_filter/.gitattributes"
printf 'data\n' > "$ws_filter/f.txt"
git -C "$ws_filter" add .gitattributes f.txt
gitc "$ws_filter" commit -q -m "chore: init"
git -C "$ws_filter" config filter.pwn.clean "sh -c 'touch $tmp_root/FILTER-RAN; cat'"
git -C "$ws_filter" config filter.pwn.smudge "sh -c 'touch $tmp_root/FILTER-RAN; cat'"
mkdir -p "$ws_filter/.git/hooks"
rm -f "$tmp_root/FILTER-RAN"
e='{"assertion":"a","check":"run_command","command":"git status --porcelain","stdout_regex":"\\A\\Z"}'
check "filter: git status runs and is clean" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_filter" --allow-exec)"
check "filter: planted clean filter never executes" "false" "$([ -e "$tmp_root/FILTER-RAN" ] && echo true || echo false)"
e='{"assertion":"a","check":"run_command","command":"git config --get filter.pwn.clean","expect_exit":1}'
check "filter: copied config no longer defines the driver" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_filter" --allow-exec)"
check "filter: snapshot config untouched" "true" "$(git -C "$ws_filter" config --get filter.pwn.clean >/dev/null && echo true || echo false)"
# (6) The process group was killed only on timeout: a grandchild that detached
#     its stdio outlived the check in a deleted cwd.
bg_pid_file="$tmp_root/bg.pid"
rm -f "$bg_pid_file"
e="{\"assertion\":\"a\",\"check\":\"run_command\",\"command\":\"(sleep 47 >/dev/null 2>&1 & echo \$! > $bg_pid_file); true\"}"
check "background: check passes" "PASS" "$(grade_one "$e" "$no_trace_out" --workspace "$ws_good" --allow-exec)"
bg_alive=false
if [ -s "$bg_pid_file" ]; then
  bg_pid="$(cat "$bg_pid_file")"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    bg_state="$(ps -o stat= -p "$bg_pid" 2>/dev/null | tr -d ' ')"
    case "$bg_state" in ''|Z*) bg_alive=false; break ;; *) bg_alive=true ;; esac
    sleep 0.2
  done
  [ "$bg_alive" = true ] && kill -9 "$bg_pid" 2>/dev/null
fi
check "background: pid recorded" "true" "$([ -s "$bg_pid_file" ] && echo true || echo false)"
check "background: grandchild killed with the check" "false" "$bg_alive"

echo "=== TEST: bad-flags regression (malformed checks no longer crash) ==="
# Regression: an unknown regex flag raised an uncaught ValueError out of
# _compile_flags, crashing the grader with a traceback and no KEY=value block.
e='{"assertion":"a","check":"regex","pattern":"x","flags":"q"}'
printf '{"evals":[{"id":"t-1","expectations":[%s]}]}\n' "$e" > "$one_evals"
bf_out="$(python3 "$grader" --evals "$one_evals" --eval-id t-1 --output "$no_trace_out" 2>&1)"
check "bad flags: grader exits 0" "0" "$?"
check "bad flags: graded FAIL" "true" "$(grep -q 'CHECK=regex RESULT=FAIL' <<<"$bf_out" && echo true || echo false)"
check "bad flags: no traceback" "false" "$(grep -q 'Traceback' <<<"$bf_out" && echo true || echo false)"
check "bad flags: evidence" "true" "$(evidence_one "$e" "$no_trace_out" | grep -q "^malformed check: unknown regex flag" && echo true || echo false)"
python3 "$grader" --evals "$one_evals" --eval-id t-1 --output "$no_trace_out" --strict >/dev/null 2>&1
check "bad flags: --strict exit code" "1" "$?"
e='{"assertion":"a","check":"absent_regex","pattern":"(unclosed"}'
check "invalid regex: graded FAIL" "FAIL" "$(grade_one "$e" "$no_trace_out")"
e='{"assertion":"a","check":"command_ran","pattern":"x","flags":"z"}'
check "bad flags on a trace check: FAIL" "FAIL" "$(grade_one "$e" "$no_trace_out" --trace "$t_good")"

echo "=== TEST: scope cut at the tool-calls appendix ==="
scoped_out="$tmp_root/transcript.md"
printf 'Committed as docs(readme): add project readme\n\n---\n## Tool calls\n- Bash: git commit -m "feat: sneaky"\n' > "$scoped_out"
e='{"assertion":"a","check":"absent_regex","pattern":"feat:"}'
check "scope cut: appendix not graded by absent_regex" "PASS" "$(grade_one "$e" "$scoped_out")"
e='{"assertion":"a","check":"substring","value":"sneaky"}'
check "scope cut: appendix not graded by substring" "FAIL" "$(grade_one "$e" "$scoped_out")"
e='{"assertion":"a","check":"regex","pattern":"add project readme$","flags":"m","scope":"body"}'
check "scope cut: body scope stops at the marker" "FAIL" "$(grade_one "$e" "$scoped_out")"

echo "=== TEST: harness-deferred accounting and inputs ==="
mixed_evals="$tmp_root/mixed-evals.json"
cat > "$mixed_evals" <<'JSON'
{"evals":[{"id":"gc-007","prompt":"Commit my staged README.","expectations":[
  {"assertion":"Runs git commit","check":"command_ran","pattern":"git\\s+commit"},
  {"assertion":"HEAD subject is conventional","check":"run_command","command":"git log -1 --format=%s","stdout_regex":"^(feat|fix|docs|chore)(\\([^)]+\\))?: [a-z]"},
  {"assertion":"Working tree clean","check":"run_command","command":"git status --porcelain","stdout_regex":"\\A\\Z"},
  {"assertion":"Says it committed","check":"regex","pattern":"[Cc]ommitted"},
  "The commit message describes the README change"
]}]}
JSON
good_md="$tmp_root/good.md"
printf 'Committed the staged README as `docs(readme): add project readme`.\n' > "$good_md"
sub_out="$(python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$good_md")"
check "subagent run: harness deferred" "3" "$(field "$sub_out" HARNESS_DEFERRED)"
check "subagent run: deterministic total excludes them" "1" "$(field "$sub_out" DETERMINISTIC_TOTAL)"
check "subagent run: judge pending excludes them" "1" "$(field "$sub_out" JUDGE_PENDING)"
check "subagent run: never false-fails" "0" "$(field "$sub_out" DETERMINISTIC_FAILED)"
check "subagent run: harness-deferred lines" "3" "$(printf '%s\n' "$sub_out" | grep -c 'RESULT=HARNESS_DEFERRED')"
hl_out="$(python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$good_md" --trace "$t_good" --workspace "$ws_good" --allow-exec)"
check "headless good: harness deferred" "0" "$(field "$hl_out" HARNESS_DEFERRED)"
check "headless good: all deterministic pass" "4" "$(field "$hl_out" DETERMINISTIC_PASSED)"
check "headless good: status" "WARN" "$(field "$hl_out" STATUS)"
hb_out="$(python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$no_trace_out" --trace "$t_bad" --workspace "$ws_bad" --allow-exec)"
check "headless bad: commit/log/status checks fail" "4" "$(field "$hb_out" DETERMINISTIC_FAILED)"
check "headless bad: status" "ERROR" "$(field "$hb_out" STATUS)"
# Only-deferred grading is WARN, never a clean OK on zero graded checks.
e='{"assertion":"a","check":"command_ran","pattern":"x"}'
printf '{"evals":[{"id":"t-1","expectations":[%s]}]}\n' "$e" > "$one_evals"
check "only harness-deferred: status WARN" "WARN" "$(field "$(python3 "$grader" --evals "$one_evals" --eval-id t-1 --output "$no_trace_out")" STATUS)"
hj="$(python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$good_md" --trace "$t_good" --json)"
check "json: summary.harness_deferred" "2" "$(printf '%s' "$hj" | python3 -c 'import json,sys; print(json.load(sys.stdin)["summary"]["harness_deferred"])')"
check "json: inputs.trace recorded" "$t_good" "$(printf '%s' "$hj" | python3 -c 'import json,sys; print(json.load(sys.stdin)["inputs"]["trace"])')"
check "json: inputs.workspace null" "None" "$(printf '%s' "$hj" | python3 -c 'import json,sys; print(json.load(sys.stdin)["inputs"]["workspace"])')"
check "json: harness-deferred evidence" "true" "$(printf '%s' "$hj" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(str(all(r["evidence"].startswith("requires headless harness") for r in d["harness_deferred"])).lower())')"

# Bad inputs are usage errors (exit 2), not silent deferrals.
python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$good_md" --trace "$tmp_root/nope.json" >/dev/null 2>&1
check "missing --trace file: exit 2" "2" "$?"
printf '{"version":2}\n' > "$tmp_root/v2.json"
python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$good_md" --trace "$tmp_root/v2.json" >/dev/null 2>&1
check "wrong trace version: exit 2" "2" "$?"
python3 "$grader" --evals "$mixed_evals" --eval-id gc-007 --output "$good_md" --workspace "$tmp_root/no-such-dir" >/dev/null 2>&1
check "missing --workspace dir: exit 2" "2" "$?"

# The trace fixtures are trace.json v1 (interface B).
for tf in "$t_good" "$t_bad" "$t_6"; do
  check "fixture $(basename "$tf") is trace v1" "1" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version"))' "$tf")"
done

# The eval-grader agent must never judge a harness-deferred item (#2301 pattern:
# pin the load-bearing phrase of a prompt outside SKILL.md).
grep -qF -- 'RESULT=HARNESS_DEFERRED' "$grader_md" \
  && grep -qF -- 'never judge' "$grader_md" \
  && pass_count=$((pass_count + 1)) \
  || { echo "FAIL: eval-grader.md lost the harness-deferred rule" >&2; fail_count=$((fail_count + 1)); }

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
