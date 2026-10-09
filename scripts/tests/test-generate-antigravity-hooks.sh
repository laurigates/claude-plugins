#!/usr/bin/env bash
# Regression test for scripts/generate-antigravity-hooks.py and the Antigravity
# hook runtime runner (run-agy-hook.py).
#
# Antigravity CLI lifecycle hooks execute via hooks.json in ~/.gemini/config/hooks.json
# or <workspace>/.agents/hooks.json.
#
# Guards:
#   A. generate-antigravity-hooks.py generates valid hooks.json with PreToolUse only
#   B. generated hooks.json matches run_command and addresses the runner by absolute path
#   C. run-agy-hook.py and run-agy-hook.sh are generated with executable permissions
#   D. all allowlisted safety hooks and their libs are copied into hook-scripts/
#   E. variable rewriting: CommandLine with ${CLAUDE_SKILL_DIR} or ${CLAUDE_PLUGIN_ROOT}
#      is rewritten via overwrite.CommandLine in PreToolUse
#   F. safety gating: blocking command (secret access, exit 2) yields decision: "deny"
#   G. clean command yields allow
#   H. error fail-open: non-blocking hook error does not abort Antigravity execution
#   I. JSON deny in hookSpecificOutput.permissionDecision (branch-protection.sh on
#      main) yields deny — the shape most of the allowlisted hooks use
#   J. hookSpecificOutput ask -> decision "ask"; updatedInput.command -> deny with
#      the rewritten command in the reason (never a silent allow of the original)
#   K. ${CLAUDE_SKILL_DIR} that matches zero, several, or no path -> deny, never a guess
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
generator="$repo_root/scripts/generate-antigravity-hooks.py"

pass_count=0
fail_count=0
assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

# Field of the runner's JSON response, or ERR when it is not JSON.
field() {
  python3 -c 'import json,sys
try:
    r = json.loads(sys.argv[1])
    v = r
    for k in sys.argv[2].split("."):
        v = v.get(k, "") if isinstance(v, dict) else ""
    print(v)
except Exception:
    print("ERR")' "$1" "$2"
}

# Run the runner in <dir> on a run_command whose workspace is <cwd>.
run_agy() {
  local dir="$1" cwd="$2" cmd="$3"
  python3 -c 'import json,sys; print(json.dumps({"toolCall": {"name": "run_command", "args": {"CommandLine": sys.argv[1]}}, "workspacePaths": [sys.argv[2]], "conversationId": "test-conv"}))' "$cmd" "$cwd" \
    | python3 "$dir/run-agy-hook.py" pre-tool-use 2>/dev/null
}

fixture="$(mktemp -d)"
[ -n "$fixture" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT
# The generator resolves symlinks (macOS /var -> /private/var); compare like with like.
fixture="$(cd "$fixture" && pwd -P)"

echo "=== TEST A/B/C/D: generator against repo ==="
gen_out="$(python3 "$generator" "$repo_root" "$fixture/out" 2>&1)" && gen_rc=0 || gen_rc=$?

assert "generator exits 0" "$([ "$gen_rc" -eq 0 ] && echo true || echo false)"
assert "generator reports exported hooks" \
  "$(echo "$gen_out" | grep -qE 'EXPORTED_HOOKS=[1-9]' && echo true || echo false)"
assert "hooks.json exists" "$([ -f "$fixture/out/hooks.json" ] && echo true || echo false)"
assert "run-agy-hook.py exists and is executable" \
  "$([ -x "$fixture/out/run-agy-hook.py" ] && echo true || echo false)"
assert "run-agy-hook.sh exists and is executable" \
  "$([ -x "$fixture/out/run-agy-hook.sh" ] && echo true || echo false)"
assert "hook-scripts directory exists and has .sh files" \
  "$([ "$(find "$fixture/out/hook-scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && echo true || echo false)"

assert "hooks.json registers only PreToolUse on run_command, runner by absolute path" \
  "$(python3 - "$fixture/out/hooks.json" "$fixture/out/run-agy-hook.py" <<'PY'
import json, shlex, sys
data = json.load(open(sys.argv[1]))
hooks = data.get("claude-safety-hooks") or {}
pre = hooks.get("PreToolUse", [])
argv = shlex.split(pre[0]["hooks"][0]["command"]) if pre else []
ok = (
    set(hooks) == {"PreToolUse"}
    and pre[0].get("matcher") == "run_command"
    and len(argv) >= 3
    and argv[2].startswith("/")
    and argv[2].endswith("run-agy-hook.py")
)
print("true" if ok else "false")
PY
)"

out="$fixture/out"

echo "=== TEST E: variable rewriting ==="
# shellcheck disable=SC2016
var_output="$(run_agy "$out" "$fixture" 'bash ${CLAUDE_SKILL_DIR}/scripts/check-adr-numbers.sh')"
assert "CLAUDE_SKILL_DIR is rewritten with export in overwrite.CommandLine" \
  "$(case "$(field "$var_output" overwrite.CommandLine)" in "export CLAUDE_SKILL_DIR="*/blueprint-adr-validate*) echo true ;; *) echo false ;; esac)"

echo "=== TEST F: safety blocking (secret access, exit 2) ==="
secret_output="$(run_agy "$out" "$fixture" 'cat ~/.ssh/id_rsa')"
assert "reading id_rsa produces decision: deny" \
  "$([ "$(field "$secret_output" decision)" = "deny" ] && echo true || echo false)"

echo "=== TEST G: benign command passes cleanly ==="
safe_output="$(run_agy "$out" "$fixture" 'echo hello world')"
assert "safe echo command is allowed with no overwrite" \
  "$([ "$(field "$safe_output" decision)" = "allow" ] && [ -z "$(field "$safe_output" overwrite)" ] && echo true || echo false)"

echo "=== TEST H: fail-open on malformed input ==="
bad_output="$(echo '{"tool_name": "run_command", "not_valid": true}' | python3 "$out/run-agy-hook.py" pre-tool-use 2>/dev/null)"
assert "malformed input fails open cleanly without crash or denial" \
  "$([ "$(field "$bad_output" decision)" = "allow" ] && echo true || echo false)"

echo "=== TEST I: JSON deny via hookSpecificOutput (branch-protection on main) ==="
main_repo="$fixture/main-repo"
git init -q -b main "$main_repo"
git -C "$main_repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
bp_output="$(run_agy "$out" "$main_repo" 'git commit -m x')"
assert "git commit on main is denied (hookSpecificOutput.permissionDecision)" \
  "$([ "$(field "$bp_output" decision)" = "deny" ] && echo true || echo false)"
assert "deny carries the hook's permissionDecisionReason" \
  "$(case "$(field "$bp_output" reason)" in *"feature branch"*) echo true ;; *) echo false ;; esac)"

echo "=== TEST J/K: stub hooks and skills in a fixture repo ==="
stub_repo="$fixture/stub-repo"
mkdir -p "$stub_repo/stub-plugin/hooks" \
  "$stub_repo/a-plugin/skills/s1/scripts" "$stub_repo/b-plugin/skills/s2/scripts"
cat > "$stub_repo/stub-plugin/hooks.json" <<'JSON'
{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stub-ask.sh\""},
  {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/stub-rewrite.sh\""}
]}]}}
JSON
cat > "$stub_repo/stub-plugin/hooks/stub-ask.sh" <<'SH'
#!/usr/bin/env bash
grep -q ASKME && printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"stub asks"}}'
exit 0
SH
cat > "$stub_repo/stub-plugin/hooks/stub-rewrite.sh" <<'SH'
#!/usr/bin/env bash
grep -q REWRITEME && printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"stub rewrote","updatedInput":{"command":"echo REWRITTEN --dry-run"}}}'
exit 0
SH
touch "$stub_repo/a-plugin/skills/s1/scripts/run.sh" "$stub_repo/b-plugin/skills/s2/scripts/run.sh" \
  "$stub_repo/a-plugin/skills/s1/scripts/only-s1.sh"
python3 "$generator" "$stub_repo" "$fixture/stub-out" \
  --allow stub-plugin/stub-ask.sh --allow stub-plugin/stub-rewrite.sh >/dev/null
stub_out="$fixture/stub-out"

ask_output="$(run_agy "$stub_out" "$fixture" 'echo ASKME')"
assert "hookSpecificOutput ask -> decision ask" \
  "$([ "$(field "$ask_output" decision)" = "ask" ] && [ "$(field "$ask_output" reason)" = "stub asks" ] && echo true || echo false)"

rw_output="$(run_agy "$stub_out" "$fixture" 'echo REWRITEME')"
assert "updatedInput.command -> deny naming the rewritten command" \
  "$([ "$(field "$rw_output" decision)" = "deny" ] && case "$(field "$rw_output" reason)" in *"echo REWRITTEN --dry-run"*) true ;; *) false ;; esac && echo true || echo false)"

# shellcheck disable=SC2016
amb_output="$(run_agy "$stub_out" "$fixture" 'bash ${CLAUDE_SKILL_DIR}/scripts/run.sh')"
assert "CLAUDE_SKILL_DIR matching two skills -> deny listing both" \
  "$([ "$(field "$amb_output" decision)" = "deny" ] && case "$(field "$amb_output" reason)" in *"/s1"*"/s2"*) true ;; *) false ;; esac && echo true || echo false)"

# shellcheck disable=SC2016
none_output="$(run_agy "$stub_out" "$fixture" 'bash ${CLAUDE_SKILL_DIR}/scripts/missing.sh')"
assert "CLAUDE_SKILL_DIR matching no skill -> deny" \
  "$([ "$(field "$none_output" decision)" = "deny" ] && echo true || echo false)"

# shellcheck disable=SC2016
bare_output="$(run_agy "$stub_out" "$fixture" 'ls ${CLAUDE_SKILL_DIR}')"
assert "bare CLAUDE_SKILL_DIR with no path -> deny" \
  "$([ "$(field "$bare_output" decision)" = "deny" ] && echo true || echo false)"

# shellcheck disable=SC2016
one_output="$(run_agy "$stub_out" "$fixture" 'bash ${CLAUDE_SKILL_DIR}/scripts/only-s1.sh ${CLAUDE_PLUGIN_ROOT}')"
assert "unique CLAUDE_SKILL_DIR resolves, with CLAUDE_PLUGIN_ROOT as its plugin" \
  "$(case "$(field "$one_output" overwrite.CommandLine)" in *"CLAUDE_PLUGIN_ROOT=$stub_repo/a-plugin "*"CLAUDE_SKILL_DIR=$stub_repo/a-plugin/skills/s1"*) echo true ;; *) echo false ;; esac)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -eq 0 ]; then
  echo "STATUS=OK"
  exit 0
fi
echo "STATUS=FAIL"
exit 1
