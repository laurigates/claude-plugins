#!/usr/bin/env bash
# Regression test for check-settings.sh nested .claude/ discovery (issue #1483).
# When the workspace root has no .claude/settings.json, the script must look one
# level down and resolve to a single nested */.claude/settings.json, emitting
# PROJECT_DIR_RESOLVED=. With multiple nested configs it emits PROJECT_DIR_HINT=;
# with a root config present it stays at the root (no resolution).
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-settings.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-settings tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-settings.sh not found at $check_script"

home_dir="$(mktemp -d)"
trap 'rm -rf "$home_dir"' EXIT

# -----------------------------------------------------------------------------
# Case 1: root lacks .claude/, exactly one nested config → resolve to it
# -----------------------------------------------------------------------------
proj1="$(mktemp -d)"
mkdir -p "${proj1}/tooling/.claude"
printf '{"permissions":{"allow":["Bash(git status *)"]}}' > "${proj1}/tooling/.claude/settings.json"

out1="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj1")"
echo "$out1" | grep -q "PROJECT_DIR_RESOLVED=${proj1}/tooling" \
  || fail "expected PROJECT_DIR_RESOLVED=${proj1}/tooling, got:\n$out1"
echo "$out1" | grep -q "^PROJECT_SETTINGS=OK$" \
  || fail "expected PROJECT_SETTINGS=OK after resolving nested config, got:\n$out1"
pass "single nested config resolves project_dir and validates its settings"
rm -rf "$proj1"

# -----------------------------------------------------------------------------
# Case 2: root lacks .claude/, multiple nested configs → hint, no resolution
# -----------------------------------------------------------------------------
proj2="$(mktemp -d)"
mkdir -p "${proj2}/a/.claude" "${proj2}/b/.claude"
printf '{}' > "${proj2}/a/.claude/settings.json"
printf '{}' > "${proj2}/b/.claude/settings.json"

out2="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj2")"
echo "$out2" | grep -q "^PROJECT_DIR_HINT=" \
  || fail "expected PROJECT_DIR_HINT= with multiple nested configs, got:\n$out2"
echo "$out2" | grep -q "PROJECT_DIR_RESOLVED=" \
  && fail "must not resolve project_dir when multiple nested configs exist:\n$out2"
echo "$out2" | grep -q "^PROJECT_SETTINGS=MISSING$" \
  || fail "expected PROJECT_SETTINGS=MISSING with ambiguous nested configs, got:\n$out2"
pass "multiple nested configs emit hint and keep MISSING behavior"
rm -rf "$proj2"

# -----------------------------------------------------------------------------
# Case 3: root has its own .claude/, never look down (no false resolution)
# -----------------------------------------------------------------------------
proj3="$(mktemp -d)"
mkdir -p "${proj3}/.claude" "${proj3}/nested/.claude"
printf '{}' > "${proj3}/.claude/settings.json"
printf '{}' > "${proj3}/nested/.claude/settings.json"

out3="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj3")"
echo "$out3" | grep -qE "PROJECT_DIR_(RESOLVED|HINT)=" \
  && fail "must not resolve/hint when root has its own .claude/:\n$out3"
echo "$out3" | grep -q "^PROJECT_SETTINGS=OK$" \
  || fail "expected PROJECT_SETTINGS=OK from root config, got:\n$out3"
pass "root config present takes precedence over nested config"
rm -rf "$proj3"

# -----------------------------------------------------------------------------
# Case 4: no root and no nested config → MISSING, no hint
# -----------------------------------------------------------------------------
proj4="$(mktemp -d)"
out4="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj4")"
echo "$out4" | grep -qE "PROJECT_DIR_(RESOLVED|HINT)=" \
  && fail "must not emit resolution/hint when no config exists anywhere:\n$out4"
echo "$out4" | grep -q "^PROJECT_SETTINGS=MISSING$" \
  || fail "expected PROJECT_SETTINGS=MISSING when no config exists, got:\n$out4"
pass "no config anywhere stays MISSING without spurious hint"
rm -rf "$proj4"

echo "ALL TESTS PASSED"
