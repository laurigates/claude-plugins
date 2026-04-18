#!/usr/bin/env bash
# Smoke tests for check-open-pr.sh.
#
# Uses a PATH shim directory to fake `gh` and `git` so the hook can be exercised
# without network access or a real PR.
#
# Run: bash feedback-plugin/hooks/tests/test_check_open_pr.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
hook="$here/../check-open-pr.sh"
fail=0
pass=0

make_shim() {
  local tmp
  tmp=$(mktemp -d)
  echo "$tmp"
}

run_hook() {
  local shim="$1"
  local payload="$2"
  PATH="$shim:$PATH" bash "$hook" <<< "$payload"
}

assert_empty() {
  local label="$1"
  local out="$2"
  if [ -z "$out" ]; then
    printf 'PASS %s\n' "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %s: expected empty output, got: %s\n' "$label" "$out"
    fail=$((fail + 1))
  fi
}

assert_ask() {
  local label="$1"
  local out="$2"
  local decision
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || echo "")
  if [ "$decision" = "ask" ]; then
    printf 'PASS %s\n' "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %s: expected permissionDecision=ask, got: %s\n' "$label" "$out"
    fail=$((fail + 1))
  fi
}

shim=$(make_shim)
cat > "$shim/gh" <<'EOF'
#!/usr/bin/env bash
# Fake gh: emit PR 42 for any --head branch.
echo "42"
EOF
chmod +x "$shim/gh"
cat > "$shim/git" <<'EOF'
#!/usr/bin/env bash
# Fake git: only rev-parse and log are exercised by the hook.
case "$1 $2" in
  "rev-parse --abbrev-ref") echo "feature/foo"; exit 0 ;;
  "log -1") echo "feat: something"; exit 0 ;;
esac
exec /usr/bin/env git "$@"
EOF
chmod +x "$shim/git"

# 1. non-Bash tool: must pass through silently
out=$(run_hook "$shim" '{"tool_name":"Read","tool_input":{}}')
assert_empty "non-Bash tool exits silently" "$out"

# 2. Bash but not git push
out=$(run_hook "$shim" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}')
assert_empty "non-push Bash command exits silently" "$out"

# 3. git push to branch with open PR: must ask
out=$(run_hook "$shim" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/foo"}}')
assert_ask "git push to branch with open PR prompts for confirmation" "$out"

# 4. force-push-ok marker suppresses the prompt
cat > "$shim/git" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "rev-parse --abbrev-ref") echo "feature/foo"; exit 0 ;;
  "log -1") echo "feat: x [force-push-ok]"; exit 0 ;;
esac
exec /usr/bin/env git "$@"
EOF
chmod +x "$shim/git"
out=$(run_hook "$shim" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/foo"}}')
assert_empty "[force-push-ok] marker bypasses prompt" "$out"

# 5. no open PR on target branch: must be silent
cat > "$shim/gh" <<'EOF'
#!/usr/bin/env bash
# emit nothing (no open PR)
exit 0
EOF
chmod +x "$shim/gh"
out=$(run_hook "$shim" '{"tool_name":"Bash","tool_input":{"command":"git push origin feature/foo"}}')
assert_empty "no open PR exits silently" "$out"

# 6. refspec form: resolve destination side of origin HEAD:feature/foo
cat > "$shim/gh" <<'EOF'
#!/usr/bin/env bash
# Echo a PR only when --head is feature/foo
for arg in "$@"; do
  if [ "$arg" = "feature/foo" ]; then
    echo "77"
    exit 0
  fi
done
exit 0
EOF
chmod +x "$shim/gh"
cat > "$shim/git" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "rev-parse --abbrev-ref") echo "main"; exit 0 ;;
  "log -1") echo "feat: x"; exit 0 ;;
esac
exec /usr/bin/env git "$@"
EOF
chmod +x "$shim/git"
out=$(run_hook "$shim" '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:feature/foo"}}')
assert_ask "refspec push resolves destination branch" "$out"

rm -rf "$shim"

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then
  printf '\n%d/%d test(s) failed\n' "$fail" "$total" >&2
  exit 1
fi
printf '\n%d/%d test(s) passed\n' "$pass" "$total"
