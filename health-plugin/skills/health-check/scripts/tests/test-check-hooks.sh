#!/usr/bin/env bash
# Regression test for check-hooks.sh timeout units (issue #3091).
# Claude Code hook `timeout` values are SECONDS. The script used to read them
# as milliseconds (warn only above 60000, print an `ms` suffix), so a 300 s
# budget passed silently and a 5000 "ms" typo (83 minutes) was never caught.
# Now: > 60 s is high_timeout (TIMEOUT=<n>s); >= 1000 is ms_timeout, the same
# threshold and TYPE as scripts/check-hook-timeout-units.sh (#3088).
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-hooks.sh"

fail() {
  printf 'FAIL: %b\n' "$1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-hooks tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-hooks.sh not found at $check_script"

home_dir="$(mktemp -d)"
proj_dir="$(mktemp -d)"
trap 'rm -rf "$home_dir" "$proj_dir"' EXIT
mkdir -p "${home_dir}/.claude"

# run_with_timeout <timeout-json-fragment>
# Writes a single PreToolUse hook (command `true`, always on PATH) to the
# scratch user settings and prints the script output.
run_with_timeout() {
  local fragment="$1"
  printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"true"%s}]}]}}' \
    "$fragment" > "${home_dir}/.claude/settings.json"
  bash "$check_script" --home-dir "$home_dir" --project-dir "$proj_dir"
}

assert_no_timeout_issue() {
  local label="$1" out="$2"
  grep -qE "TYPE=(high_timeout|ms_timeout)" <<<"$out" \
    && fail "${label}: expected no timeout issue, got:\n$out"
  grep -q "^STATUS=OK$" <<<"$out" \
    || fail "${label}: expected STATUS=OK, got:\n$out"
  grep -q "^ISSUE_COUNT=0$" <<<"$out" \
    || fail "${label}: expected ISSUE_COUNT=0, got:\n$out"
}

# -----------------------------------------------------------------------------
# Case 1: 30 s, 60 s and no timeout ("default") are fine
# -----------------------------------------------------------------------------
assert_no_timeout_issue "timeout=30" "$(run_with_timeout ',"timeout":30')"
pass "timeout 30 s raises no issue"
assert_no_timeout_issue "timeout=60" "$(run_with_timeout ',"timeout":60')"
pass "timeout 60 s (boundary) raises no issue"
assert_no_timeout_issue "no timeout" "$(run_with_timeout '')"
pass "missing timeout (default) raises no issue"

# -----------------------------------------------------------------------------
# Case 2: 300 s is a high timeout, reported in seconds
# -----------------------------------------------------------------------------
out300="$(run_with_timeout ',"timeout":300')"
grep -q "SEVERITY=WARN TYPE=high_timeout EVENT=PreToolUse TIMEOUT=300s " <<<"$out300" \
  || fail "timeout=300: expected high_timeout with TIMEOUT=300s, got:\n$out300"
grep -q "TIMEOUT=[0-9]*ms" <<<"$out300" \
  && fail "timeout=300: must not print an ms suffix:\n$out300"
grep -q "^STATUS=WARN$" <<<"$out300" \
  || fail "timeout=300: expected STATUS=WARN, got:\n$out300"
pass "timeout 300 s is high_timeout with TIMEOUT=300s"

# -----------------------------------------------------------------------------
# Case 3: 5000 is a millisecond figure written as seconds
# -----------------------------------------------------------------------------
out5000="$(run_with_timeout ',"timeout":5000')"
grep -q "SEVERITY=WARN TYPE=ms_timeout EVENT=PreToolUse TIMEOUT=5000s " <<<"$out5000" \
  || fail "timeout=5000: expected ms_timeout with TIMEOUT=5000s, got:\n$out5000"
grep -q "TYPE=high_timeout" <<<"$out5000" \
  && fail "timeout=5000: ms_timeout must replace, not duplicate, high_timeout:\n$out5000"
grep -q "^ISSUE_COUNT=1$" <<<"$out5000" \
  || fail "timeout=5000: expected ISSUE_COUNT=1, got:\n$out5000"
pass "timeout 5000 is flagged as a likely millisecond value (ms_timeout)"

# -----------------------------------------------------------------------------
# Case 4: 1000 is the threshold (>= 1000 is ms_timeout; 999 is high_timeout)
# -----------------------------------------------------------------------------
out1000="$(run_with_timeout ',"timeout":1000')"
grep -q "TYPE=ms_timeout" <<<"$out1000" \
  || fail "timeout=1000: expected ms_timeout at the threshold, got:\n$out1000"
out999="$(run_with_timeout ',"timeout":999')"
grep -q "TYPE=high_timeout EVENT=PreToolUse TIMEOUT=999s " <<<"$out999" \
  || fail "timeout=999: expected high_timeout below the threshold, got:\n$out999"
pass "ms_timeout threshold is 1000, matching check-hook-timeout-units.sh"

echo "ALL TESTS PASSED"
