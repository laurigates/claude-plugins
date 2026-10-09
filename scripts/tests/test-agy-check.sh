#!/usr/bin/env bash
# Regression test for scripts/check-antigravity.sh and the `agy-check` justfile recipe.
#
# Antigravity CLI prerequisites and configuration audit.
#
# Guards:
#   A. on an unconfigured target, reports MISSING for skills.json, agents, and hooks
#   B. on a configured target (skills added), reports SKILLS_JSON=configured
#   C. on an installed target (agents and hooks present), reports AGENTS and HOOKS present
#   D. check-antigravity.sh exits 0 in all cases (audit is informational, never breaks workflow)
#   E. justfile defines agy-check and setup-antigravity recipes under [group: "antigravity"]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
check_sh="$repo_root/scripts/check-antigravity.sh"
configure_sh="$repo_root/scripts/configure-antigravity.sh"
install_sh="$repo_root/scripts/install-antigravity.sh"
justfile="$repo_root/justfile"

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

echo "=== TEST A: unconfigured target ==="
unconfigured="$fixture/empty"
mkdir -p "$unconfigured"
out_unconf="$(bash "$check_sh" "$unconfigured" 2>&1)"
rc_unconf=$?

assert "unconfigured check exits 0" "$([ "$rc_unconf" -eq 0 ] && echo true || echo false)"
assert "reports header and footer" \
  "$(echo "$out_unconf" | grep -q '=== ANTIGRAVITY PREREQS ===' && echo "$out_unconf" | grep -q '=== END ANTIGRAVITY PREREQS ===' && echo true || echo false)"
assert "reports SKILLS_JSON=MISSING" \
  "$(echo "$out_unconf" | grep -q 'SKILLS_JSON=MISSING' && echo true || echo false)"
assert "reports AGENTS=MISSING" \
  "$(echo "$out_unconf" | grep -q 'AGENTS=MISSING' && echo true || echo false)"
assert "reports HOOKS=MISSING" \
  "$(echo "$out_unconf" | grep -q 'HOOKS=MISSING' && echo true || echo false)"

echo "=== TEST B/C: configured target ==="
configured="$fixture/configured"
mkdir -p "$configured"
bash "$configure_sh" "$configured" >/dev/null
bash "$install_sh" "$configured" >/dev/null

out_conf="$(bash "$check_sh" "$configured" 2>&1)"
rc_conf=$?

assert "configured check exits 0" "$([ "$rc_conf" -eq 0 ] && echo true || echo false)"
assert "reports SKILLS_JSON=configured with marketplace entries" \
  "$(echo "$out_conf" | grep -qE 'SKILLS_JSON=configured \([1-9][0-9]* marketplace entries\)' && echo true || echo false)"
assert "reports AGENTS installed" \
  "$(echo "$out_conf" | grep -qE 'AGENTS=[1-9][0-9]* installed' && echo true || echo false)"
assert "reports HOOKS present with safety hook scripts" \
  "$(echo "$out_conf" | grep -qE 'HOOKS=present \([1-9][0-9]* safety hook scripts' && echo true || echo false)"

echo "=== TEST D: justfile recipe coverage ==="
assert "justfile contains [group: \"antigravity\"]" \
  "$(grep -q '\[group: "antigravity"\]' "$justfile" && echo true || echo false)"
assert "justfile defines agy-check recipe" \
  "$(grep -q '^agy-check ' "$justfile" && echo true || echo false)"
assert "justfile defines setup-antigravity recipe" \
  "$(grep -q '^setup-antigravity ' "$justfile" && echo true || echo false)"

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
