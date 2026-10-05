#!/usr/bin/env bash
# Assertions use the `cmd && pass++ || fail` idiom deliberately (pass++ is
# arithmetic that always exits 0 here, so the || branch only runs on real
# failure) and pipe fixtures through cat for readability. Expected values
# carry literal backticks (SC2016).
# shellcheck disable=SC2015,SC2002,SC2016
#
# Regression test for parse_trace.py -- the only component of evaluate-plugin
# that reads Claude Code stream-json (design decision D6). Every trace.json
# field is asserted on three fixtures:
#
#   stream-skill-commit.jsonl  happy path: Skill + Bash git commit + Writes,
#                              hooks, a failed Edit, a >2000-char input value,
#                              a message id split across two events
#   stream-denied.jsonl        permission_denied system events, user-rejected
#                              tool_result_meta, and a denial carried ONLY by
#                              result.permission_denials
#   stream-truncated.jsonl     no result event, one malformed (cut-off) line,
#                              a tool_use with no tool_result, an unanswered hook
#
# plus the exit-2 paths (empty / missing / all-malformed input), the
# max_turns / budget / error stop_reason mapping, stdin input, and the
# structured stdout block.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(dirname "$script_dir")"
fixtures="$script_dir/fixtures"
parser="$scripts_dir/parse_trace.py"

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
  # jf <trace.json> <python expression over t>  -> prints the value as JSON
  python3 -c 'import json,sys; t=json.load(open(sys.argv[1])); print(json.dumps(eval(sys.argv[2]), sort_keys=True, separators=(",", ":")))' "$1" "$2"
}

tmp_dir="$(mktemp -d)" || { echo "FAIL: mktemp" >&2; exit 1; }
[ -n "$tmp_dir" ] && [ -d "$tmp_dir" ] || { echo "FAIL: mktemp returned no dir" >&2; exit 1; }
trap 'rm -rf "$tmp_dir"' EXIT

wd="/tmp/eval-wd.Xk3p9"

# ---------------------------------------------------------------------------
echo "=== TEST: stream-skill-commit (happy path) ==="
t="$tmp_dir/commit.json"
out="$(python3 "$parser" --input "$fixtures/stream-skill-commit.jsonl" --output "$t" --workdir "$wd/")"
check "commit: exit code" "0" "$?"
check "commit: block STATUS" "OK" "$(field "$out" STATUS)"
check "commit: block ISSUE_COUNT" "0" "$(field "$out" ISSUE_COUNT)"
check "commit: block has no REASON on OK" "" "$(field "$out" REASON)"
check "commit: block NUM_TURNS" "7" "$(field "$out" NUM_TURNS)"
check "commit: block TOOL_CALLS" "7" "$(field "$out" TOOL_CALLS)"
check "commit: block SKILLS_INVOKED" "git-plugin:git-commit" "$(field "$out" SKILLS_INVOKED)"
check "commit: block STOP_REASON" "completed" "$(field "$out" STOP_REASON)"
check "commit: block header" "=== PARSE TRACE ===" "$(printf '%s\n' "$out" | head -1)"
check "commit: block footer" "=== END PARSE TRACE ===" "$(printf '%s\n' "$out" | tail -1)"

# identity
check "commit: version" "1" "$(jf "$t" 't["version"]')"
check "commit: harness" '"claude-code"' "$(jf "$t" 't["harness"]')"
check "commit: harness_version" '"2.1.289"' "$(jf "$t" 't["harness_version"]')"
check "commit: model_id" '"claude-haiku-4-5-20251001"' "$(jf "$t" 't["model_id"]')"
check "commit: session_id" '"11111111-2222-4333-8444-555555555555"' "$(jf "$t" 't["session_id"]')"
check "commit: cwd" "\"$wd\"" "$(jf "$t" 't["cwd"]')"
check "commit: permission_mode" '"bypassPermissions"' "$(jf "$t" 't["permission_mode"]')"
# catalogue
check "commit: plugins_loaded names" '["git-plugin","cc-plugin-telemetry"]' "$(jf "$t" '[p["name"] for p in t["plugins_loaded"]]')"
check "commit: plugins_loaded[0]" '{"name":"git-plugin","path":"/home/user/claude-plugins/git-plugin","source":"git-plugin@inline","version":"2.58.4"}' "$(jf "$t" 't["plugins_loaded"][0]')"
check "commit: builtin plugin has no version key" "false" "$(jf "$t" '"version" in t["plugins_loaded"][1]')"
# skills_available mirrors init.skills, which the real CLI (2.1.289) fills with
# USER-INVOCABLE skills only: git-commit (user-invocable: false) is absent from
# it live even though the model can still invoke it. So the fixture omits it, and
# an invoked skill missing from skills_available is the normal case, not a bug.
check "commit: skills_available" '["git-plugin:git-commit-push-pr","git-plugin:git-conflicts"]' "$(jf "$t" 't["skills_available"]')"
check "commit: invoked skill need not be in skills_available" "false" "$(jf "$t" '"git-plugin:git-commit" in t["skills_available"]')"
# skills_invoked
check "commit: skills_invoked" '[{"args":"README","denied":false,"is_error":false,"skill":"git-plugin:git-commit","tool_use_id":"toolu_c_skill","turn":1}]' "$(jf "$t" 't["skills_invoked"]')"
# tool_calls -- turn numbering: msg_c01 spans thinking + tool_use events (one turn)
check "commit: tool_calls (turn,name)" '[[1,"Skill"],[2,"Bash"],[3,"Write"],[3,"Write"],[4,"Edit"],[5,"Bash"],[6,"Bash"]]' "$(jf "$t" '[[c["turn"], c["name"]] for c in t["tool_calls"]]')"
check "commit: tool_calls keys" '["denied","input","input_summary","is_error","name","tool_use_id","turn"]' "$(jf "$t" 'sorted(t["tool_calls"][0])')"
check "commit: input_summary Bash = command" '"git status --porcelain"' "$(jf "$t" 't["tool_calls"][1]["input_summary"]')"
check "commit: input_summary Skill = skill" '"git-plugin:git-commit"' "$(jf "$t" 't["tool_calls"][0]["input_summary"]')"
check "commit: input_summary Write = file_path" "\"$wd/docs/NOTES.md\"" "$(jf "$t" 't["tool_calls"][2]["input_summary"]')"
check "commit: input value capped at 2000 chars" "2000" "$(jf "$t" 'len(t["tool_calls"][2]["input"]["content"])')"
check "commit: short input value untouched" '"scratch\n"' "$(jf "$t" 't["tool_calls"][3]["input"]["content"]')"
check "commit: failed Edit is_error" "true" "$(jf "$t" 't["tool_calls"][4]["is_error"]')"
check "commit: Write without is_error key -> false" "false" "$(jf "$t" 't["tool_calls"][2]["is_error"]')"
check "commit: no call denied" "[]" "$(jf "$t" '[c["tool_use_id"] for c in t["tool_calls"] if c["denied"]]')"
# bash_commands
check "commit: bash_commands" '[{"command":"git status --porcelain","denied":false,"is_error":false,"turn":2},{"command":"git add README.md docs/NOTES.md","denied":false,"is_error":false,"turn":5},{"command":"git commit -m \"docs: add README and notes\"","denied":false,"is_error":false,"turn":6}]' "$(jf "$t" 't["bash_commands"]')"
# files_written: relativized via --workdir; outside path stays absolute; failed Edit excluded
check "commit: files_written" '[{"path":"docs/NOTES.md","tool":"Write"},{"path":"/tmp/elsewhere/scratch.txt","tool":"Write"}]' "$(jf "$t" 't["files_written"]')"
check "commit: permission_denied" "[]" "$(jf "$t" 't["permission_denied"]')"
# hooks_fired: SessionStart at turn 0, PreToolUse paired by hook_id
check "commit: hooks_fired (turn,event,outcome,exit)" '[[0,"SessionStart","success",0],[2,"PreToolUse","success",0],[5,"PreToolUse","success",0],[6,"PreToolUse","success",0]]' "$(jf "$t" '[[h["turn"], h["hook_event"], h["outcome"], h["exit_code"]] for h in t["hooks_fired"]]')"
check "commit: hooks_fired hook_name" '"SessionStart:startup"' "$(jf "$t" 't["hooks_fired"][0]["hook_name"]')"
check "commit: hooks_fired hook_id" '"h-pre-1"' "$(jf "$t" 't["hooks_fired"][1]["hook_id"]')"
# totals
check "commit: num_turns" "7" "$(jf "$t" 't["num_turns"]')"
check "commit: cost_usd" "0.0421" "$(jf "$t" 't["cost_usd"]')"
check "commit: usage.output_tokens" "900" "$(jf "$t" 't["usage"]["output_tokens"]')"
check "commit: duration_ms" "21000" "$(jf "$t" 't["duration_ms"]')"
check "commit: duration_api_ms" "18500" "$(jf "$t" 't["duration_api_ms"]')"
# outcome
check "commit: final_text" '"Committed as `docs: add README and notes`."' "$(jf "$t" 't["final_text"]')"
check "commit: stop_reason" '"completed"' "$(jf "$t" 't["stop_reason"]')"
check "commit: is_error" "false" "$(jf "$t" 't["is_error"]')"
check "commit: parse_warnings" '{"malformed_lines":0,"missing_init":false,"missing_result":false}' "$(jf "$t" 't["parse_warnings"]')"

echo "=== TEST: --workdir fallback and mismatch ==="
# Without --workdir, paths are relativized against the init event's cwd.
t2="$tmp_dir/commit-nowd.json"
python3 "$parser" --input "$fixtures/stream-skill-commit.jsonl" --output "$t2" >/dev/null
check "nowd: falls back to init cwd" '["docs/NOTES.md","/tmp/elsewhere/scratch.txt"]' "$(jf "$t2" '[f["path"] for f in t["files_written"]]')"
# A workdir the paths are not under leaves them absolute.
t3="$tmp_dir/commit-otherwd.json"
python3 "$parser" --input "$fixtures/stream-skill-commit.jsonl" --output "$t3" --workdir /srv/unrelated >/dev/null
check "otherwd: paths stay absolute" "[\"$wd/docs/NOTES.md\",\"/tmp/elsewhere/scratch.txt\"]" "$(jf "$t3" '[f["path"] for f in t["files_written"]]')"
# A sibling dir sharing the prefix is NOT inside the workdir.
t4="$tmp_dir/commit-prefixwd.json"
python3 "$parser" --input "$fixtures/stream-skill-commit.jsonl" --output "$t4" --workdir /tmp/eval-wd >/dev/null
check "prefixwd: no string-prefix relativization" "\"$wd/docs/NOTES.md\"" "$(jf "$t4" 't["files_written"][0]["path"]')"

echo "=== TEST: stdout JSON mode + stdin input ==="
json_out="$(cat "$fixtures/stream-skill-commit.jsonl" | python3 "$parser" --input - 2>"$tmp_dir/stderr.txt")"
check "stdin: exit code" "0" "$?"
check "stdin: stdout is pure JSON" "7" "$(printf '%s' "$json_out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["num_turns"])')"
check "stdin: block goes to stderr" "OK" "$(field "$(cat "$tmp_dir/stderr.txt")" STATUS)"

# ---------------------------------------------------------------------------
echo "=== TEST: stream-denied ==="
t="$tmp_dir/denied.json"
out="$(python3 "$parser" --input "$fixtures/stream-denied.jsonl" --output "$t" --workdir "$wd")"
check "denied: exit code" "0" "$?"
check "denied: block STATUS" "OK" "$(field "$out" STATUS)"
check "denied: block PERMISSION_DENIED" "3" "$(field "$out" PERMISSION_DENIED)"
check "denied: permission_mode" '"default"' "$(jf "$t" 't["permission_mode"]')"
check "denied: denied Skill still listed as invoked" '[{"args":null,"denied":true,"is_error":true,"skill":"git-plugin:git-commit","tool_use_id":"toolu_d_skill","turn":1}]' "$(jf "$t" 't["skills_invoked"]')"
check "denied: bash_commands" '[{"command":"git commit -m '"'"'fix: thing'"'"'","denied":true,"is_error":true,"turn":2}]' "$(jf "$t" 't["bash_commands"]')"
check "denied: every tool call denied" "[true,true,true]" "$(jf "$t" '[c["denied"] for c in t["tool_calls"]]')"
check "denied: Write denied via result.permission_denials only" "true" "$(jf "$t" 't["tool_calls"][2]["denied"]')"
check "denied: denied Write not in files_written" "[]" "$(jf "$t" 't["files_written"]')"
check "denied: permission_denied (system + result-only, no duplicates)" '[["Skill","toolu_d_skill"],["Bash","toolu_d_commit"],["Write","toolu_d_write"]]' "$(jf "$t" '[[d["tool_name"], d["tool_use_id"]] for d in t["permission_denied"]]')"
check "denied: permission_denied turns" "[1,2,3]" "$(jf "$t" '[d["turn"] for d in t["permission_denied"]]')"
check "denied: system-event message kept" '"This command requires approval"' "$(jf "$t" 't["permission_denied"][1]["message"]')"
check "denied: result-only denial message null" "null" "$(jf "$t" 't["permission_denied"][2]["message"]')"
check "denied: hook error outcome" '[["PreToolUse","error",2]]' "$(jf "$t" '[[h["hook_event"], h["outcome"], h["exit_code"]] for h in t["hooks_fired"]]')"
check "denied: num_turns" "4" "$(jf "$t" 't["num_turns"]')"
check "denied: cost_usd" "0.0113" "$(jf "$t" 't["cost_usd"]')"
check "denied: stop_reason" '"completed"' "$(jf "$t" 't["stop_reason"]')"
check "denied: is_error" "false" "$(jf "$t" 't["is_error"]')"
check "denied: final_text" '"I was not permitted to run the commit. Suggested message: `fix: thing`."' "$(jf "$t" 't["final_text"]')"
check "denied: parse_warnings" '{"malformed_lines":0,"missing_init":false,"missing_result":false}' "$(jf "$t" 't["parse_warnings"]')"

# ---------------------------------------------------------------------------
echo "=== TEST: stream-truncated ==="
t="$tmp_dir/truncated.json"
out="$(python3 "$parser" --input "$fixtures/stream-truncated.jsonl" --output "$t" --workdir "$wd")"
check "truncated: exit code (partial parse is still 0)" "0" "$?"
check "truncated: block STATUS" "WARN" "$(field "$out" STATUS)"
check "truncated: block ISSUE_COUNT" "2" "$(field "$out" ISSUE_COUNT)"
check "truncated: block REASON" "missing_result: no result event; stream truncated (stop_reason=incomplete) (+1 more)" "$(field "$out" REASON)"
check "truncated: block MALFORMED_LINES" "1" "$(field "$out" MALFORMED_LINES)"
check "truncated: block STOP_REASON" "incomplete" "$(field "$out" STOP_REASON)"
check "truncated: stop_reason" '"incomplete"' "$(jf "$t" 't["stop_reason"]')"
check "truncated: is_error true without result" "true" "$(jf "$t" 't["is_error"]')"
check "truncated: parse_warnings" '{"malformed_lines":1,"missing_init":false,"missing_result":true}' "$(jf "$t" 't["parse_warnings"]')"
check "truncated: num_turns counted from stream" "2" "$(jf "$t" 't["num_turns"]')"
check "truncated: totals null" "[null,null,null,null]" "$(jf "$t" '[t["cost_usd"], t["usage"], t["duration_ms"], t["duration_api_ms"]]')"
check "truncated: bare skill name kept" '[["git-commit",1,false,false]]' "$(jf "$t" '[[s["skill"], s["turn"], s["denied"], s["is_error"]] for s in t["skills_invoked"]]')"
check "truncated: unanswered tool call is_error null" "null" "$(jf "$t" 't["tool_calls"][1]["is_error"]')"
check "truncated: bash_commands" '[{"command":"git add README.md && git commit -m '"'"'docs: readme'"'"'","denied":false,"is_error":null,"turn":2}]' "$(jf "$t" 't["bash_commands"]')"
check "truncated: final_text from last assistant text" '"Staging the README now."' "$(jf "$t" 't["final_text"]')"
check "truncated: unanswered hook outcome null" '[[0,"SessionStart",null,null]]' "$(jf "$t" '[[h["turn"], h["hook_event"], h["outcome"], h["exit_code"]] for h in t["hooks_fired"]]')"
check "truncated: identity from init" '["claude-code","2.1.289","claude-haiku-4-5-20251001","bypassPermissions"]' "$(jf "$t" '[t["harness"], t["harness_version"], t["model_id"], t["permission_mode"]]')"
check "truncated: files_written" "[]" "$(jf "$t" 't["files_written"]')"
check "truncated: permission_denied" "[]" "$(jf "$t" 't["permission_denied"]')"

# ---------------------------------------------------------------------------
echo "=== TEST: stop_reason mapping ==="
stop_for() {
  # stop_for <result-subtype> <is_error> -> stop_reason of a one-result stream
  printf '{"type":"result","subtype":"%s","is_error":%s,"num_turns":3}\n' "$1" "$2" \
    | python3 "$parser" --input - 2>/dev/null \
    | python3 -c 'import json,sys; t=json.load(sys.stdin); print(t["stop_reason"], str(t["parse_warnings"]["missing_init"]).lower())'
}
check "map: success" "completed true" "$(stop_for success false)"
check "map: error_max_turns" "max_turns true" "$(stop_for error_max_turns true)"
check "map: error_max_budget_usd" "budget true" "$(stop_for error_max_budget_usd true)"
check "map: error_during_execution" "error true" "$(stop_for error_during_execution true)"

# ---------------------------------------------------------------------------
echo "=== TEST: exit 2 on empty / unreadable input ==="
: >"$tmp_dir/empty.jsonl"
out="$(python3 "$parser" --input "$tmp_dir/empty.jsonl" --output "$tmp_dir/x.json")"
check "empty: exit code" "2" "$?"
check "empty: STATUS" "ERROR" "$(field "$out" STATUS)"
check "empty: REASON names cause" "empty_input" "$(field "$out" REASON | cut -d: -f1)"
check "empty: no trace written" "false" "$([ -e "$tmp_dir/x.json" ] && echo true || echo false)"

python3 "$parser" --input "$tmp_dir/does-not-exist.jsonl" --output "$tmp_dir/x.json" >/dev/null
check "missing: exit code" "2" "$?"

printf 'not json\n{"truncated":\n' >"$tmp_dir/garbage.jsonl"
out="$(python3 "$parser" --input "$tmp_dir/garbage.jsonl" --output "$tmp_dir/x.json")"
check "all-malformed: exit code" "2" "$?"
check "all-malformed: REASON" "no_parseable_events" "$(field "$out" REASON | cut -d: -f1)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
