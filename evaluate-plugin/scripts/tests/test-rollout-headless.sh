#!/usr/bin/env bash
# Assertions use the `cmd && pass++ || fail` idiom deliberately (see
# test-grade-deterministic.sh); suppress the style nag rather than rewrite them.
# shellcheck disable=SC2015
#
# Regression test for rollout_headless.sh (the opt-in headless rollout harness).
# Runs the script against fixtures/fake-claude.sh put first on PATH as `claude`,
# so no test here makes a live API call.
#
# What this pins:
#   (a) env scrub: in clean mode no CLAUDE_CODE_SESSION_ID / CLAUDECODE /
#       CLAUDE_CODE_REMOTE* (or any other parent var) reaches the child, HOME is
#       a fake one; inherit mode drops the session vars but keeps the rest
#   (b) --plugin-dir is forwarded (absolute) for with-skill and absent for baseline
#   (c) guards exit 2: workdir inside the repo -- including the CALLER's repo
#       when the script runs from an installed copy outside it, and any repo
#       rooted above the workdir -- a `skills` path component, a missing run
#       dir, a missing budget (unless EVAL_ALLOW_UNCAPPED=1), a missing claude CLI
#   (d) every RUN_DIR file is written, and the KEY=VALUE block is complete
#   (e) --stop-on-skill kills the child at the first Skill tool_use
#   (f) a truncated stream is STATUS=ERROR exit 1; a timeout is STOP_REASON=timeout
#   (g) a rejected --max-turns is retried without it and WARNs
#   (h) clean-mode auth failure is an ERROR with no inherit retry (the retry
#       handed parent credentials to a bypass child); explicit inherit strips a
#       credential denylist and WARNs; ~/.claude/.credentials.json is the only
#       file copied into the fake HOME
#   (j) the prompt goes on stdin, never argv, so a dash-leading prompt is text
#   (k) the REAL parse_trace.py is resolved (no test-local stub; a renamed
#       parser must fail here, not pass through a stand-in)
#   (i) leaks surface as WARN: a child session_id equal to the parent's, and
#       hooks no --plugin-dir declares
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
scripts_dir="$(dirname "$script_dir")"
fixtures="$script_dir/fixtures"
rollout="$scripts_dir/rollout_headless.sh"
fake="$fixtures/fake-claude.sh"
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

has_line() {
  # has_line <file> <fixed string at line start> -> yes/no
  grep -qF -- "$2" "$1" 2>/dev/null && echo yes || echo no
}

# Neutralise inherited git context (#1745) -- nothing here runs git against the
# repo, but a leaked GIT_DIR must not reach anything that might.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
unset EVAL_ALLOW_UNCAPPED EVAL_PARSE_TRACE

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
[ -d "$sandbox" ] || { echo "FAIL: mktemp -d dir missing" >&2; exit 1; }
trap 'rm -rf "$sandbox"' EXIT
sandbox="$(cd "$sandbox" && pwd -P)"

# (k) The real parser must exist where rollout_headless.sh looks for it. No
# stand-in: a renamed parser would otherwise pass this suite while every real
# rollout failed with parse_trace_missing.
if [ ! -f "$scripts_dir/parse_trace.py" ]; then
  echo "FAIL: parse_trace.py missing beside rollout_headless.sh" >&2
  fail_count=$((fail_count + 1))
fi

bin="$sandbox/bin"
mkdir -p "$bin"
log="$sandbox/fake.log"

# make_claude KEY=VAL...  -> (re)write the `claude` wrapper with baked env.
make_claude() {
  {
    echo '#!/usr/bin/env bash'
    printf 'export %q\n' "FAKE_CLAUDE_LOG=$log"
    for kv in "$@"; do printf 'export %q\n' "$kv"; done
    printf 'exec bash %q "$@"\n' "$fake"
  } >"$bin/claude"
  chmod +x "$bin/claude"
  rm -f "$log"
}

# A plugin dir whose hooks.json declares the events the fixture fires.
plugin="$sandbox/demo-plugin"
mkdir -p "$plugin/.claude-plugin"
printf '{"name":"demo-plugin","version":"0.0.0","hooks":"./hooks.json"}\n' >"$plugin/.claude-plugin/plugin.json"
printf '{"hooks":{"SessionStart":[],"PreToolUse":[]}}\n' >"$plugin/hooks.json"

new_dirs() {  # fresh run_dir + workdir, and a fresh invocation log
  rm -f "$log"
  run_dir="$(mktemp -d "$sandbox/run.XXXXXX")" || { echo 'mktemp failed' >&2; exit 1; }
  [ -n "$run_dir" ] && [ -d "$run_dir" ] || { echo 'bad run dir' >&2; exit 1; }
  workdir="$(mktemp -d "$sandbox/work.XXXXXX")" || { echo 'mktemp failed' >&2; exit 1; }
  [ -n "$workdir" ] && [ -d "$workdir" ] || { echo 'bad workdir' >&2; exit 1; }
}

# Parent env the child must NOT see in clean mode.
export CLAUDE_CODE_SESSION_ID="parent-session-0000"
export CLAUDECODE=1
export CLAUDE_CODE_REMOTE=true
export CLAUDE_CODE_REMOTE_SESSION_ID="remote-parent-0000"
export PARENT_ONLY_VAR="parent-only-value"
export FOO_PASS="foo-pass-value"
real_home="$HOME"

run() {  # run <args...> -> sets out, rc
  out="$(PATH="$bin:$PATH" bash "$rollout" "$@" 2>"$sandbox/stderr.txt")"
  rc=$?
}

echo "=== TEST: with-skill rollout, clean env ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl" "FAKE_CLAUDE_TOUCH=out/hello.txt"
new_dirs
prompt="Commit the staged README change"
run --run-dir "$run_dir" --workdir "$workdir" --prompt "$prompt" --plugin-dir "$plugin" --max-budget-usd 0.05
check "exit 0" "0" "$rc"
check "STATUS=OK" "OK" "$(field "$out" STATUS)"
check "ISSUE_COUNT=0" "0" "$(field "$out" ISSUE_COUNT)"
check "no REASON on OK" "" "$(field "$out" REASON)"
check "STOP_REASON=completed" "completed" "$(field "$out" STOP_REASON)"
check "SKILLS_INVOKED" "git-plugin:git-commit" "$(field "$out" SKILLS_INVOKED)"
check "MODEL_ID" "claude-haiku-4-5-20251001" "$(field "$out" MODEL_ID)"
check "COST_USD" "0.0421" "$(field "$out" COST_USD)"
check "NUM_TURNS" "7" "$(field "$out" NUM_TURNS)"
check "CHILD_EXIT" "0" "$(field "$out" CHILD_EXIT)"
check "ENV_MODE" "clean" "$(field "$out" ENV_MODE)"
check "RUN_DIR" "$run_dir" "$(field "$out" RUN_DIR)"
check "WORKDIR" "$workdir" "$(field "$out" WORKDIR)"
check "header line" "=== HEADLESS ROLLOUT ===" "$(printf '%s\n' "$out" | head -1)"
check "footer line" "=== END HEADLESS ROLLOUT ===" "$(printf '%s\n' "$out" | tail -1)"
for k in TRANSCRIPT_JSONL TRANSCRIPT_MD TRACE WORKSPACE; do
  v="$(field "$out" "$k")"
  check "$k is set and exists" "yes" "$([ -n "$v" ] && [ -e "$v" ] && echo yes || echo no)"
done
# (d) files written
check "transcript.jsonl replays the full fixture" "$(wc -l <"$fixtures/stream-skill-commit.jsonl")" "$(wc -l <"$run_dir/transcript.jsonl")"
check "stderr.log exists" "yes" "$([ -f "$run_dir/stderr.log" ] && echo yes || echo no)"
check "trace.json is a v1 object" "1" "$(jq -r .version "$run_dir/trace.json" 2>/dev/null)"
# (k) fields only the real parse_trace.py emits
check "trace.json from the real parser (parse_warnings)" "object" "$(jq -r '.parse_warnings | type' "$run_dir/trace.json" 2>/dev/null)"
check "trace.json from the real parser (bash_commands)" "array" "$(jq -r '.bash_commands | type' "$run_dir/trace.json" 2>/dev/null)"
check "transcript.md has the tool-calls appendix" "yes" "$(has_line "$run_dir/transcript.md" "## Tool calls")"
check "transcript.md appendix marker shape" "1" "$(python3 -c 'import sys; print(int("\n\n---\n## Tool calls" in open(sys.argv[1]).read()))' "$run_dir/transcript.md")"
check "transcript.md lists the Skill call" "yes" "$(has_line "$run_dir/transcript.md" "Skill:")"
check "timing.json harness" "claude-code" "$(jq -r .harness "$run_dir/timing.json")"
check "timing.json total_cost_usd" "0.0421" "$(jq -r .total_cost_usd "$run_dir/timing.json")"
check "timing.json num_turns" "7" "$(jq -r .num_turns "$run_dir/timing.json")"
check "timing.json duration_ms is a number" "number" "$(jq -r '.duration_ms | type' "$run_dir/timing.json")"
check "workspace snapshot has the child's file" "written by fake-claude" "$(cat "$run_dir/workspace/out/hello.txt" 2>/dev/null)"
expect_sha="$(printf '%s' "$prompt" | sha256sum | cut -d' ' -f1)"
check "rollout-meta prompt_sha256" "$expect_sha" "$(jq -r .prompt_sha256 "$run_dir/rollout-meta.json")"
check "rollout-meta never stores the prompt text" "no" "$(has_line "$run_dir/rollout-meta.json" "$prompt")"
check "rollout-meta env_mode" "clean" "$(jq -r .env_mode "$run_dir/rollout-meta.json")"
# (b) plugin dir forwarded, budget forwarded, bypass permissions
check "--plugin-dir forwarded (absolute)" "yes" "$(has_line "$log" "$(printf 'ARG\t%q' "$plugin")")"
check "--plugin-dir flag present" "yes" "$(has_line "$log" "$(printf 'ARG\t--plugin-dir')")"
check "--max-budget-usd forwarded" "yes" "$(has_line "$log" "$(printf 'ARG\t0.05')")"
check "stream-json requested" "yes" "$(has_line "$log" "$(printf 'ARG\tstream-json')")"
check "bypass permissions" "yes" "$(has_line "$log" "$(printf 'ARG\t--dangerously-skip-permissions')")"
check "no session persistence" "yes" "$(has_line "$log" "$(printf 'ARG\t--no-session-persistence')")"
check "child cwd is the workdir" "yes" "$(has_line "$log" "$(printf 'CWD\t%s' "$workdir")")"
# (a) env scrub
check "scrub: CLAUDE_CODE_SESSION_ID absent" "no" "$(has_line "$log" "$(printf 'ENV\tCLAUDE_CODE_SESSION_ID=')")"
check "scrub: CLAUDECODE absent" "no" "$(has_line "$log" "$(printf 'ENV\tCLAUDECODE=')")"
check "scrub: CLAUDE_CODE_REMOTE* absent" "0" "$(grep -c "$(printf '^ENV\tCLAUDE_CODE_REMOTE')" "$log")"
check "scrub: arbitrary parent var absent" "no" "$(has_line "$log" "$(printf 'ENV\tPARENT_ONLY_VAR=')")"
child_home="$(grep -m1 "$(printf '^ENV\tHOME=')" "$log" | cut -d= -f2-)"
check "scrub: HOME is set" "yes" "$([ -n "$child_home" ] && echo yes || echo no)"
check "scrub: HOME is fake (not the parent's)" "yes" "$([ "$child_home" != "$real_home" ] && echo yes || echo no)"
check "scrub: fake HOME is cleaned up" "no" "$([ -e "$child_home" ] && echo yes || echo no)"
check "scrub: PATH passes" "yes" "$(has_line "$log" "$(printf 'ENV\tPATH=')")"
if [ "$(id -u)" = "0" ]; then
  check "IS_SANDBOX=1 under bypass as root" "yes" "$(has_line "$log" "$(printf 'ENV\tIS_SANDBOX=1')")"
fi

echo "=== TEST: baseline rollout (no --plugin-dir) ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt "$prompt" --max-budget-usd 0.05
check "baseline: exit 0" "0" "$rc"
check "baseline: no --plugin-dir in argv" "no" "$(has_line "$log" "$(printf 'ARG\t--plugin-dir')")"
# (i) the fixture fires SessionStart/PreToolUse hooks; with no plugin declaring
# them they are foreign and must surface, not be hidden.
check "baseline: foreign hooks WARN" "WARN" "$(field "$out" STATUS)"
check "baseline: foreign_hook issue" "yes" "$(grep -q 'TYPE=foreign_hook' <<<"$out" && echo yes || echo no)"
check "baseline: REASON names it" "yes" "$(field "$out" REASON | grep -q '^foreign_hook: ' && echo yes || echo no)"

echo "=== TEST: (j) the prompt goes on stdin; a dash-leading prompt is not an option ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
new_dirs
printf -- '--- title: x\n---\nCommit it.\n' >"$sandbox/fm-prompt.txt"
run --run-dir "$run_dir" --workdir "$workdir" --prompt-file "$sandbox/fm-prompt.txt" --plugin-dir "$plugin" --max-budget-usd 0.05
check "dash prompt: exit 0" "0" "$rc"
check "dash prompt: delivered verbatim on stdin" "yes" "$(has_line "$log" "$(printf 'STDIN\t%q' "$(cat "$sandbox/fm-prompt.txt")")")"
check "dash prompt: no argv element starts with ---" "0" "$(grep -c "$(printf '^ARG\t---')" "$log")"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt "--version" --plugin-dir "$plugin" --max-budget-usd 0.05
check "prompt --version: not consumed as a flag" "no" "$(has_line "$log" "$(printf 'ARG\t--version')")"
check "prompt --version: sent as text" "yes" "$(has_line "$log" "$(printf 'STDIN\t--version')")"
check "prompt --version: rollout completed" "completed" "$(field "$out" STOP_REASON)"
check "-p carries no positional prompt" "yes" "$(grep -A1 "$(printf '^ARG\t-p$')" "$log" | tail -1 | grep -q "$(printf '^ARG\t--output-format')" && echo yes || echo no)"

echo "=== TEST: guards exit 2 ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
new_dirs
run --run-dir "$run_dir" --workdir "$repo_root" --prompt p --max-budget-usd 0.05
check "workdir = repo root -> exit 2" "2" "$rc"
run --run-dir "$run_dir" --workdir "$scripts_dir" --prompt p --max-budget-usd 0.05
check "workdir inside repo -> exit 2" "2" "$rc"
check "guard: STATUS=ERROR on usage error" "ERROR" "$(field "$out" STATUS)"
mkdir -p "$sandbox/x/skills/y"
run --run-dir "$run_dir" --workdir "$sandbox/x/skills/y" --prompt p --max-budget-usd 0.05
check "workdir with skills component -> exit 2" "2" "$rc"
run --run-dir "$sandbox/does-not-exist" --workdir "$workdir" --prompt p --max-budget-usd 0.05
check "missing run dir -> exit 2" "2" "$rc"
run --run-dir "$run_dir" --workdir "$workdir" --prompt p
check "missing --max-budget-usd -> exit 2" "2" "$rc"
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --max-budget-usd 0
check "zero budget -> exit 2" "2" "$rc"
run --run-dir "$run_dir" --workdir "$workdir" --max-budget-usd 0.05
check "missing prompt -> exit 2" "2" "$rc"
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --max-budget-usd 0.05 --permission yolo
check "bad --permission -> exit 2" "2" "$rc"
# An installed copy (${CLAUDE_PLUGIN_ROOT} under ~/.claude/plugins, outside any
# repo) run from the user's checkout: the guard must test the CALLER's repo,
# not only the tree the script lives in.
inst="$sandbox/installed/evaluate-plugin/scripts"
mkdir -p "$inst"
cp "$rollout" "$scripts_dir/parse_trace.py" "$inst/"
out="$(cd "$repo_root" && PATH="$bin:$PATH" bash "$inst/rollout_headless.sh" --run-dir "$run_dir" \
  --workdir "$repo_root/docs" --prompt p --max-budget-usd 0.05 2>/dev/null)"
check "installed copy: workdir inside the caller's repo -> exit 2" "2" "$?"
check "installed copy: REASON names the repo" "yes" "$(field "$out" REASON | grep -qF "$repo_root" && echo yes || echo no)"
# A workdir nested inside some other repo (not the caller's) is refused too.
nest="$sandbox/nest-repo"
mkdir -p "$nest/sub"
git -C "$nest" init -q
run --run-dir "$run_dir" --workdir "$nest/sub" --prompt p --max-budget-usd 0.05
check "workdir below another repo's toplevel -> exit 2" "2" "$rc"
check "guards never launched the child" "no" "$([ -f "$log" ] && echo yes || echo no)"
# A workdir that IS a repo toplevel (a fixture ran `git init` in it) is fine.
run --run-dir "$run_dir" --workdir "$nest" --prompt p --max-budget-usd 0.05 --no-snapshot
check "workdir that is a repo toplevel -> allowed" "0" "$rc"
nobin="$sandbox/nobin"; mkdir -p "$nobin"
if [ -z "$(PATH="$nobin:/usr/bin:/bin:/usr/local/bin" command -v claude)" ] \
   && PATH="$nobin:/usr/bin:/bin:/usr/local/bin" command -v jq >/dev/null; then
  out="$(PATH="$nobin:/usr/bin:/bin:/usr/local/bin" bash "$rollout" --run-dir "$run_dir" --workdir "$workdir" --prompt p --max-budget-usd 0.05 2>/dev/null)"
  check "claude missing -> exit 2" "2" "$?"
fi

echo "=== TEST: EVAL_ALLOW_UNCAPPED=1 runs without a cap, with a WARN ==="
new_dirs
out="$(EVAL_ALLOW_UNCAPPED=1 PATH="$bin:$PATH" bash "$rollout" --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" 2>/dev/null)"
check "uncapped: exit 0" "0" "$?"
check "uncapped: no --max-budget-usd in argv" "no" "$(has_line "$log" "$(printf 'ARG\t--max-budget-usd')")"
check "uncapped: WARN" "WARN" "$(field "$out" STATUS)"
check "uncapped: issue" "yes" "$(grep -q 'TYPE=uncapped' <<<"$out" && echo yes || echo no)"

echo "=== TEST: --prompt-file, --model, --effort, --max-turns, --allowed-tools, default permission ==="
new_dirs
printf 'prompt from a file\n' >"$sandbox/prompt.txt"
run --run-dir "$run_dir" --workdir "$workdir" --prompt-file "$sandbox/prompt.txt" --plugin-dir "$plugin" \
  --max-budget-usd 0.05 --model sonnet --effort low --max-turns 3 --allowed-tools Skill --permission default --no-snapshot
check "flags: exit 0" "0" "$rc"
check "flags: prompt read from file (on stdin)" "yes" "$(has_line "$log" "$(printf 'STDIN\t%q' 'prompt from a file')")"
check "flags: prompt never in argv" "no" "$(has_line "$log" "$(printf 'ARG\t%q' 'prompt from a file')")"
check "flags: --model sonnet" "yes" "$(has_line "$log" "$(printf 'ARG\tsonnet')")"
check "flags: --effort low" "yes" "$(has_line "$log" "$(printf 'ARG\t--effort')")"
check "flags: --max-turns forwarded" "yes" "$(has_line "$log" "$(printf 'ARG\t--max-turns')")"
check "flags: --allowedTools Skill" "yes" "$(has_line "$log" "$(printf 'ARG\t--allowedTools')")"
check "flags: --permission-mode default" "yes" "$(has_line "$log" "$(printf 'ARG\t--permission-mode')")"
check "flags: no bypass under default" "no" "$(has_line "$log" "$(printf 'ARG\t--dangerously-skip-permissions')")"
check "flags: no IS_SANDBOX under default" "no" "$(has_line "$log" "$(printf 'ENV\tIS_SANDBOX=')")"
check "flags: --no-snapshot leaves WORKSPACE empty" "" "$(field "$out" WORKSPACE)"
check "flags: no workspace dir" "no" "$([ -e "$run_dir/workspace" ] && echo yes || echo no)"
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --prompt-file "$sandbox/prompt.txt" --max-budget-usd 0.05
check "both --prompt and --prompt-file -> exit 2" "2" "$rc"

echo "=== TEST: the snapshot cap measures apparent size (a sparse file cannot slip past) ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
new_dirs
truncate -s 5M "$workdir/sparse.bin"
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --snapshot-max-mb 1
check "sparse: snapshot skipped" "yes" "$(grep -q 'TYPE=snapshot_skipped' <<<"$out" && echo yes || echo no)"
check "sparse: no workspace" "" "$(field "$out" WORKSPACE)"

echo "=== TEST: --stop-on-skill kills the child at the first Skill tool_use ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl" "FAKE_CLAUDE_DELAY=0.2"
new_dirs
t0="$(date +%s)"
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 \
  --allowed-tools Skill --permission default --stop-on-skill
t1="$(date +%s)"
check "stop: exit 0" "0" "$rc"
check "stop: STOP_REASON=stopped_on_skill" "stopped_on_skill" "$(field "$out" STOP_REASON)"
check "stop: STATUS=OK (an expected stop, not an error)" "OK" "$(field "$out" STATUS)"
check "stop: SKILLS_INVOKED" "git-plugin:git-commit" "$(field "$out" SKILLS_INVOKED)"
check "stop: COST_USD unknown (empty)" "" "$(field "$out" COST_USD)"
check "stop: transcript cut short" "yes" \
  "$([ "$(wc -l <"$run_dir/transcript.jsonl")" -lt "$(wc -l <"$fixtures/stream-skill-commit.jsonl")" ] && echo yes || echo no)"
check "stop: no result event recorded" "0" "$(grep -c '"type":"result"' "$run_dir/transcript.jsonl")"
check "stop: returned well before the full replay (<5s)" "yes" "$([ $((t1 - t0)) -lt 5 ] && echo yes || echo no)"
check "stop: timing.json total_cost_usd null" "null" "$(jq -r .total_cost_usd "$run_dir/timing.json")"

echo "=== TEST: truncated stream is STATUS=ERROR, exit 1 ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-truncated.jsonl" "FAKE_CLAUDE_EXIT=1"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05
check "truncated: exit 1" "1" "$rc"
check "truncated: STATUS=ERROR" "ERROR" "$(field "$out" STATUS)"
check "truncated: STOP_REASON=error" "error" "$(field "$out" STOP_REASON)"
check "truncated: CHILD_EXIT recorded" "1" "$(field "$out" CHILD_EXIT)"
check "truncated: REASON names the truncation" "yes" "$(field "$out" REASON | grep -q '^truncated_stream: ' && echo yes || echo no)"
check "truncated: files still written" "yes" "$([ -f "$run_dir/timing.json" ] && [ -f "$run_dir/rollout-meta.json" ] && echo yes || echo no)"

echo "=== TEST: empty output is STATUS=ERROR ==="
printf '' >"$sandbox/empty.jsonl"
make_claude "FAKE_CLAUDE_FIXTURE=$sandbox/empty.jsonl" "FAKE_CLAUDE_EXIT=1"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --max-budget-usd 0.05
check "empty: exit 1" "1" "$rc"
check "empty: REASON" "yes" "$(field "$out" REASON | grep -q '^empty_transcript: ' && echo yes || echo no)"

echo "=== TEST: --timeout kills a slow child ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl" "FAKE_CLAUDE_DELAY=0.5"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --timeout 1
check "timeout: exit 1" "1" "$rc"
check "timeout: STOP_REASON=timeout" "timeout" "$(field "$out" STOP_REASON)"

echo "=== TEST: a rejected --max-turns is retried without it ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl" "FAKE_CLAUDE_REJECT_FLAG=--max-turns"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --max-turns 2
check "max-turns: exit 0" "0" "$rc"
check "max-turns: WARN" "WARN" "$(field "$out" STATUS)"
check "max-turns: issue" "yes" "$(grep -q 'TYPE=max_turns_rejected' <<<"$out" && echo yes || echo no)"
check "max-turns: two invocations" "2" "$(grep -c '^=== INVOCATION ===' "$log")"
check "max-turns: completed on retry" "completed" "$(field "$out" STOP_REASON)"
check "max-turns: meta records rejection" "false" "$(jq -r .max_turns_accepted "$run_dir/rollout-meta.json")"

echo "=== TEST: inherit mode drops session vars but keeps the rest ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --env-mode inherit
check "inherit: exit 0" "0" "$rc"
check "inherit: CLAUDE_CODE_SESSION_ID absent" "no" "$(has_line "$log" "$(printf 'ENV\tCLAUDE_CODE_SESSION_ID=')")"
check "inherit: CLAUDECODE absent" "no" "$(has_line "$log" "$(printf 'ENV\tCLAUDECODE=')")"
check "inherit: CLAUDE_CODE_REMOTE* absent" "0" "$(grep -c "$(printf '^ENV\tCLAUDE_CODE_REMOTE')" "$log")"
check "inherit: other parent vars kept" "yes" "$(has_line "$log" "$(printf 'ENV\tPARENT_ONLY_VAR=')")"
check "inherit: real HOME kept" "yes" "$(has_line "$log" "$(printf 'ENV\tHOME=%s' "$real_home")")"

echo "=== TEST: --passthrough-env passes names, refuses session vars ==="
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 \
  --passthrough-env FOO_PASS,CLAUDE_CODE_SESSION_ID
check "passthrough: exit 0" "0" "$rc"
check "passthrough: FOO_PASS reaches the child" "yes" "$(has_line "$log" "$(printf 'ENV\tFOO_PASS=foo-pass-value')")"
check "passthrough: session var still scrubbed" "no" "$(has_line "$log" "$(printf 'ENV\tCLAUDE_CODE_SESSION_ID=')")"
check "passthrough: WARN passthrough_denied" "yes" "$(grep -q 'TYPE=passthrough_denied' <<<"$out" && echo yes || echo no)"
check "passthrough: meta lists the name" '["FOO_PASS"]' "$(jq -c .passthrough_env_names "$run_dir/rollout-meta.json")"
check "passthrough: meta never stores the value" "no" "$(has_line "$run_dir/rollout-meta.json" "foo-pass-value")"

echo "=== TEST: skill listing budget (SLASH_COMMAND_TOOL_CHAR_BUDGET) ==="
# The CLI elides skill descriptions past this budget; with a 48-skill plugin the
# default left git-commit listed by name only (2026-10-05 live smoke), so
# rollouts raise it unless told to keep the CLI default.
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05
check "budget: default reaches the child" "yes" "$(has_line "$log" "$(printf 'ENV\tSLASH_COMMAND_TOOL_CHAR_BUDGET=100000')")"
check "budget: default in KEY block" "100000" "$(field "$out" SKILL_LISTING_BUDGET)"
check "budget: default in meta" "100000" "$(jq -r .skill_listing_budget "$run_dir/rollout-meta.json")"
new_dirs
EVAL_SKILL_LISTING_BUDGET=7777 run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05
check "budget: EVAL_SKILL_LISTING_BUDGET sets the default" "yes" "$(has_line "$log" "$(printf 'ENV\tSLASH_COMMAND_TOOL_CHAR_BUDGET=7777')")"
new_dirs
SLASH_COMMAND_TOOL_CHAR_BUDGET=1 run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" \
  --max-budget-usd 0.05 --passthrough-env SLASH_COMMAND_TOOL_CHAR_BUDGET --skill-listing-budget 4242
check "budget: flag beats a passed-through value" "yes" "$(has_line "$log" "$(printf 'ENV\tSLASH_COMMAND_TOOL_CHAR_BUDGET=4242')")"
check "budget: passed-through value overridden" "no" "$(has_line "$log" "$(printf 'ENV\tSLASH_COMMAND_TOOL_CHAR_BUDGET=1')")"
new_dirs
SLASH_COMMAND_TOOL_CHAR_BUDGET=1 run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" \
  --max-budget-usd 0.05 --env-mode inherit --skill-listing-budget cli
check "budget: cli exit 0" "0" "$rc"
check "budget: cli strips an inherited value" "no" "$(has_line "$log" "$(printf 'ENV\tSLASH_COMMAND_TOOL_CHAR_BUDGET=')")"
check "budget: cli in KEY block" "cli" "$(field "$out" SKILL_LISTING_BUDGET)"
check "budget: cli in meta" "cli" "$(jq -r .skill_listing_budget "$run_dir/rollout-meta.json")"
new_dirs
SLASH_COMMAND_TOOL_CHAR_BUDGET=1 run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" \
  --max-budget-usd 0.05 --passthrough-env SLASH_COMMAND_TOOL_CHAR_BUDGET --skill-listing-budget cli
check "budget: cli drops a passed-through value too" "no" "$(has_line "$log" "$(printf 'ENV\tSLASH_COMMAND_TOOL_CHAR_BUDGET=')")"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --skill-listing-budget lots
check "budget: invalid value is a usage error" "2" "$rc"

echo "=== TEST: --tools limits the child's toolset ==="
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --tools Skill
check "tools: exit 0" "0" "$rc"
check "tools: --tools forwarded" "yes" "$(has_line "$log" "$(printf 'ARG\t--tools')")"
check "tools: value forwarded" "yes" "$(grep -A1 "$(printf '^ARG\t--tools$')" "$log" | grep -q "$(printf '^ARG\tSkill$')" && echo yes || echo no)"
check "tools: in meta" "Skill" "$(jq -r .tools "$run_dir/rollout-meta.json")"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05
check "tools: absent by default" "no" "$(has_line "$log" "$(printf 'ARG\t--tools')")"

echo "=== TEST: child session_id equal to the parent's is a WARN ==="
new_dirs
out="$(CLAUDE_CODE_SESSION_ID=11111111-2222-4333-8444-555555555555 PATH="$bin:$PATH" bash "$rollout" \
  --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 2>/dev/null)"
check "session leak: exit 0" "0" "$?"
check "session leak: WARN" "WARN" "$(field "$out" STATUS)"
check "session leak: issue" "yes" "$(grep -q 'TYPE=session_id_leak' <<<"$out" && echo yes || echo no)"

echo "=== TEST: (h) clean-mode auth failure is an ERROR, never an inherit retry ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl" "FAKE_CLAUDE_AUTH_MARKER=FAKE_INHERIT_ONLY"
export FAKE_INHERIT_ONLY=1
export GH_TOKEN="fake-gh-token" AWS_SECRET_ACCESS_KEY="fake-aws-secret" CCR_SESSION_PROFILE="fake-profile"
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05
check "auth: exit 1" "1" "$rc"
check "auth: STATUS=ERROR" "ERROR" "$(field "$out" STATUS)"
check "auth: ENV_MODE stays clean" "clean" "$(field "$out" ENV_MODE)"
check "auth: one invocation, no retry" "1" "$(grep -c '^=== INVOCATION ===' "$log")"
check "auth: TYPE=auth_failed" "yes" "$(grep -q 'TYPE=auth_failed' <<<"$out" && echo yes || echo no)"
check "auth: no env_fallback_inherit" "no" "$(grep -q 'env_fallback_inherit' <<<"$out" && echo yes || echo no)"
check "auth: credentials never reached a child" "no" "$(has_line "$log" "$(printf 'ENV\tGH_TOKEN=')")"
check "auth: bypass child never saw the real HOME" "no" "$(has_line "$log" "$(printf 'ENV\tHOME=%s' "$real_home")")"

echo "=== TEST: explicit inherit strips third-party credentials and WARNs ==="
new_dirs
run --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 --env-mode inherit
check "inherit creds: exit 0" "0" "$rc"
check "inherit creds: WARN" "WARN" "$(field "$out" STATUS)"
check "inherit creds: GH_TOKEN stripped" "no" "$(has_line "$log" "$(printf 'ENV\tGH_TOKEN=')")"
check "inherit creds: AWS_* stripped" "no" "$(has_line "$log" "$(printf 'ENV\tAWS_SECRET_ACCESS_KEY=')")"
check "inherit creds: CCR_* stripped" "no" "$(has_line "$log" "$(printf 'ENV\tCCR_SESSION_PROFILE=')")"
check "inherit creds: WARN counts what was stripped" "yes" "$(printf '%s\n' "$out" | grep 'TYPE=inherit_env' | grep -qE 'stripped [1-9][0-9]* credential' && echo yes || echo no)"
check "inherit creds: meta names GH_TOKEN" "true" "$(jq -r '.inherit_stripped_env | index("GH_TOKEN") != null' "$run_dir/rollout-meta.json")"
check "inherit creds: meta never stores the value" "no" "$(has_line "$run_dir/rollout-meta.json" "fake-gh-token")"
check "inherit creds: WARN names the real HOME" "yes" "$(printf '%s\n' "$out" | grep 'TYPE=inherit_env' | grep -q 'real HOME' && echo yes || echo no)"
unset FAKE_INHERIT_ONLY GH_TOKEN AWS_SECRET_ACCESS_KEY CCR_SESSION_PROFILE

echo "=== TEST: only ~/.claude/.credentials.json is copied into the fake HOME ==="
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
user_home="$sandbox/user-home"
mkdir -p "$user_home/.claude"
printf '{"claudeAiOauth":{"accessToken":"fake"}}\n' >"$user_home/.claude/.credentials.json"
printf '{"hooks":{}}\n' >"$user_home/.claude/settings.json"
new_dirs
out="$(env -u CLAUDE_CODE_OAUTH_TOKEN -u ANTHROPIC_API_KEY HOME="$user_home" PATH="$bin:$PATH" bash "$rollout" \
  --run-dir "$run_dir" --workdir "$workdir" --prompt p --plugin-dir "$plugin" --max-budget-usd 0.05 2>/dev/null)"
check "creds copy: exit 0" "0" "$?"
check "creds copy: child sees credentials" "yes" "$(has_line "$log" "$(printf 'CREDS\tyes')")"
check "creds copy: child HOME is still fake" "no" "$(has_line "$log" "$(printf 'ENV\tHOME=%s' "$user_home")")"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
