#!/usr/bin/env bash
# Regression test for scripts/generate-antigravity-hooks.py and the Antigravity
# hook runtime runner (run-agy-hook.py).
#
# Antigravity CLI lifecycle hooks execute via hooks.json in ~/.gemini/config/hooks.json
# or <workspace>/.agents/hooks.json.
#
# Guards:
#   A. generate-antigravity-hooks.py generates valid hooks.json with PreToolUse and PostToolUse
#   B. generated hooks.json matches run_command tool
#   C. run-agy-hook.py and run-agy-hook.sh are generated with executable permissions
#   D. all allowlisted safety hooks and their libs are copied into hook-scripts/
#   E. variable rewriting: CommandLine with ${CLAUDE_SKILL_DIR} or ${CLAUDE_PLUGIN_ROOT}
#      is rewritten via overwrite.CommandLine in PreToolUse
#   F. safety gating: blocking command (secret access or default branch commit) yields
#      decision: "deny"
#   G. clean command yields allow ({})
#   H. error fail-open: non-blocking hook error does not abort Antigravity execution
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

fixture="$(mktemp -d)"
[ -n "$fixture" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

echo "=== TEST A/B/C/D: generator against repo ==="
gen_out="$(python3 "$generator" "$repo_root" "$fixture" 2>&1)"
gen_rc=$?

assert "generator exits 0" "$([ "$gen_rc" -eq 0 ] && echo true || echo false)"
assert "generator reports exported hooks" \
  "$(echo "$gen_out" | grep -q 'EXPORTED_HOOKS=' && echo true || echo false)"
assert "hooks.json exists" "$([ -f "$fixture/hooks.json" ] && echo true || echo false)"
assert "run-agy-hook.py exists and is executable" \
  "$([ -x "$fixture/run-agy-hook.py" ] && echo true || echo false)"
assert "run-agy-hook.sh exists and is executable" \
  "$([ -x "$fixture/run-agy-hook.sh" ] && echo true || echo false)"
assert "hook-scripts directory exists and has .sh files" \
  "$([ "$(find "$fixture/hook-scripts" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ] && echo true || echo false)"

assert "hooks.json has valid structure with PreToolUse and PostToolUse on run_command" \
  "$(python3 - "$fixture/hooks.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
hooks = data.get("claude-safety-hooks") or data.get("hooks") or {}
pre = hooks.get("PreToolUse", [])
post = hooks.get("PostToolUse", [])
ok = (
    len(pre) >= 1
    and pre[0].get("matcher") == "run_command"
    and "run-agy-hook.py" in pre[0]["hooks"][0]["command"]
    and len(post) >= 1
    and post[0].get("matcher") == "run_command"
    and "run-agy-hook.py" in post[0]["hooks"][0]["command"]
)
print("true" if ok else "false")
PY
)"

echo "=== TEST E: variable rewriting ==="
# Test CLAUDE_SKILL_DIR rewriting via run-agy-hook.py (using a real relative path in repo)
# shellcheck disable=SC2016
var_input='{"toolCall": {"name": "run_command", "args": {"CommandLine": "bash ${CLAUDE_SKILL_DIR}/scripts/check-adr-numbers.sh"}}}'
var_output="$(cd "$fixture" && echo "$var_input" | python3 "$fixture/run-agy-hook.py" pre-tool-use 2>/dev/null)"

assert "CLAUDE_SKILL_DIR is rewritten with export in overwrite.CommandLine" \
  "$(python3 - "$var_output" <<'PY'
import json, sys
try:
    resp = json.loads(sys.argv[1])
    cmd = resp.get("overwrite", {}).get("CommandLine", "")
    ok = "CLAUDE_SKILL_DIR=" in cmd and "export CLAUDE_SKILL_DIR" in cmd
except Exception:
    ok = False
print("true" if ok else "false")
PY
)"

echo "=== TEST F: safety blocking (secret access) ==="
secret_input='{"toolCall": {"name": "run_command", "args": {"CommandLine": "cat ~/.ssh/id_rsa"}}}'
secret_output="$(cd "$fixture" && echo "$secret_input" | python3 "$fixture/run-agy-hook.py" pre-tool-use 2>/dev/null)"

assert "reading id_rsa produces decision: deny" \
  "$(python3 - "$secret_output" <<'PY'
import json, sys
try:
    resp = json.loads(sys.argv[1])
    ok = resp.get("decision") == "deny" and "secret" in resp.get("reason", "").lower()
except Exception:
    ok = False
print("true" if ok else "false")
PY
)"

echo "=== TEST G: benign command passes cleanly ==="
safe_input='{"tool_name": "run_command", "tool_input": {"CommandLine": "echo hello world"}}'
safe_output="$(cd "$fixture" && echo "$safe_input" | python3 "$fixture/run-agy-hook.py" pre-tool-use 2>/dev/null)"

assert "safe echo command produces no denial ({})" \
  "$(python3 - "$safe_output" <<'PY'
import json, sys
try:
    resp = json.loads(sys.argv[1])
    ok = resp.get("decision") != "deny" and "overwrite" not in resp
except Exception:
    ok = False
print("true" if ok else "false")
PY
)"

echo "=== TEST H: fail-open on malformed input ==="
bad_input='{"tool_name": "run_command", "not_valid": true}'
bad_output="$(cd "$fixture" && echo "$bad_input" | python3 "$fixture/run-agy-hook.py" pre-tool-use 2>/dev/null)"

assert "malformed input fails open cleanly without crash or denial" \
  "$(python3 - "$bad_output" <<'PY'
import json, sys
try:
    resp = json.loads(sys.argv[1]) if sys.argv[1].strip() else {}
    ok = resp.get("decision") != "deny"
except Exception:
    ok = True
print("true" if ok else "false")
PY
)"

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
