#!/usr/bin/env bash
# Regression tests for check-open-pr.sh.
#
# Uses a PATH shim directory to fake `gh` and `git` so the hook can be exercised
# without network access or a real PR.
#
# Filename/location matter: scripts/run-skill-script-tests.sh discovers hook
# suites as `*/hooks/test-*.sh`. This suite previously lived at
# `hooks/tests/test_check_open_pr.sh`, matching neither the directory nor the
# hyphen, and so never ran in CI.
#
# Run: bash feedback-plugin/hooks/test-check-open-pr.sh

set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
hook="$here/check-open-pr.sh"
fail=0
pass=0

run_hook() {
  local shim="$1"
  local payload="$2"
  PATH="$shim:$PATH" bash "$hook" <<< "$payload"
}

bash_payload() {
  jq -nc --arg cmd "$1" '{tool_name:"Bash", tool_input:{command:$cmd}}'
}

assert_empty() {
  local label="$1" out="$2"
  if [ -z "$out" ]; then
    printf 'PASS %s\n' "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %s: expected empty output, got: %s\n' "$label" "$out"
    fail=$((fail + 1))
  fi
}

assert_deny() {
  local label="$1" out="$2" decision
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || echo "")
  if [ "$decision" = "deny" ]; then
    printf 'PASS %s\n' "$label"
    pass=$((pass + 1))
  else
    printf 'FAIL %s: expected permissionDecision=deny, got: %s\n' "$label" "$out"
    fail=$((fail + 1))
  fi
}

assert_reason_contains() {
  local label="$1" out="$2" needle="$3" reason
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || echo "")
  case "$reason" in
    *"$needle"*)
      printf 'PASS %s\n' "$label"
      pass=$((pass + 1))
      ;;
    *)
      printf 'FAIL %s: reason missing %q, got: %s\n' "$label" "$needle" "$reason"
      fail=$((fail + 1))
      ;;
  esac
}

# --- shims --------------------------------------------------------------
# gh: emit PR 42 only when --head names feature/foo, so a mis-parsed branch
# (e.g. "-f" or "+HEAD") surfaces as a silent pass rather than a false deny.
shim=$(mktemp -d)
write_gh_with_pr() {
  cat > "$shim/gh" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  [ "$arg" = "feature/foo" ] && { echo "42"; exit 0; }
done
exit 0
EOF
  chmod +x "$shim/gh"
}
write_gh_no_pr() {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$shim/gh"
  chmod +x "$shim/gh"
}
write_git() {
  local branch="$1" msg="$2"
  cat > "$shim/git" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in
  "rev-parse --abbrev-ref") echo "$branch"; exit 0 ;;
  "log -1") echo "$msg"; exit 0 ;;
esac
exec /usr/bin/env git "\$@"
EOF
  chmod +x "$shim/git"
}

write_gh_with_pr
write_git "feature/foo" "feat: something"

# --- pass-through cases -------------------------------------------------

out=$(run_hook "$shim" '{"tool_name":"Read","tool_input":{}}')
assert_empty "non-Bash tool exits silently" "$out"

out=$(run_hook "$shim" "$(bash_payload 'ls -la')")
assert_empty "non-push Bash command exits silently" "$out"

# The regression this hook was rewritten for: a plain push to an open PR is the
# normal workflow and must never prompt or deny.
out=$(run_hook "$shim" "$(bash_payload 'git push origin feature/foo')")
assert_empty "plain push to open PR passes silently" "$out"

out=$(run_hook "$shim" "$(bash_payload 'git push -u origin HEAD:feature/foo 2>&1 | tail -5 && git rev-parse HEAD')")
assert_empty "plain compound push to open PR passes silently" "$out"

# --force-with-lease already refuses when the remote moved, so it needs no gate.
out=$(run_hook "$shim" "$(bash_payload 'git push --force-with-lease origin feature/foo')")
assert_empty "--force-with-lease passes silently" "$out"

out=$(run_hook "$shim" "$(bash_payload 'git push --force-with-lease=feature/foo:abc123 origin feature/foo')")
assert_empty "--force-with-lease=<ref> passes silently" "$out"

out=$(run_hook "$shim" "$(bash_payload 'git push --force-if-includes origin feature/foo')")
assert_empty "--force-if-includes passes silently" "$out"

# --- deny cases ---------------------------------------------------------

out=$(run_hook "$shim" "$(bash_payload 'git push --force origin feature/foo')")
assert_deny "bare --force to open PR is denied" "$out"
assert_reason_contains "deny reason names the remedy" "$out" "--force-with-lease"
assert_reason_contains "deny reason names the PR" "$out" "#42"

# -f must be recognised as a flag, not consumed as the branch name.
out=$(run_hook "$shim" "$(bash_payload 'git push -f origin feature/foo')")
assert_deny "-f to open PR is denied (and resolves the branch past the flag)" "$out"

out=$(run_hook "$shim" "$(bash_payload 'git push -fu origin feature/foo')")
assert_deny "short bundle -fu to open PR is denied" "$out"

out=$(run_hook "$shim" "$(bash_payload 'git push origin +HEAD:feature/foo')")
assert_deny "leading-+ refspec to open PR is denied" "$out"

out=$(run_hook "$shim" "$(bash_payload 'git push --force origin HEAD:refs/heads/feature/foo')")
assert_deny "refs/heads/ prefix is stripped before the PR lookup" "$out"

out=$(run_hook "$shim" "$(bash_payload 'cd repo && git push --force origin feature/foo 2>&1 | tail -5')")
assert_deny "force push inside a compound command is denied" "$out"

# Current-branch fallback: no refspec on the command line.
out=$(run_hook "$shim" "$(bash_payload 'git push --force')")
assert_deny "bare --force with no refspec falls back to the current branch" "$out"

# --- escape hatches -----------------------------------------------------

write_git "feature/foo" "feat: x [force-push-ok]"
out=$(run_hook "$shim" "$(bash_payload 'git push --force origin feature/foo')")
assert_empty "[force-push-ok] in the last commit message bypasses the deny" "$out"

write_git "feature/foo" "feat: something"
write_gh_no_pr
out=$(run_hook "$shim" "$(bash_payload 'git push --force origin feature/foo')")
assert_empty "force push to a branch with no open PR passes silently" "$out"

# A branch other than feature/foo has no PR under the shim, which also proves
# the parser did not mistake a flag for the branch name.
write_gh_with_pr
out=$(run_hook "$shim" "$(bash_payload 'git push --force origin feature/other')")
assert_empty "force push to an unrelated branch passes silently" "$out"

rm -rf "$shim"

total=$((pass + fail))
if [ "$fail" -gt 0 ]; then
  printf '\n%d/%d test(s) failed\n' "$fail" "$total" >&2
  exit 1
fi
printf '\n%d/%d test(s) passed\n' "$pass" "$total"
