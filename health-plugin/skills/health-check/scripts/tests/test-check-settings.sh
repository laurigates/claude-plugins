#!/usr/bin/env bash
# Regression test for check-settings.sh nested .claude/ discovery (issue #1483).
# When the workspace root has no .claude/settings.json, the script must look one
# level down and resolve to a single nested */.claude/settings.json, emitting
# PROJECT_DIR_RESOLVED=. With multiple nested configs it emits PROJECT_DIR_HINT=;
# with a root config present it stays at the root (no resolution).
#
# Output contract (#3580): cases 5-8 fail against the version that predates
# REASON= and used `declare -A`. WARN/ERROR blocks carry REASON= naming the
# first row at the reported severity, every block passes
# check-structured-output-contract.sh --validate, and the script stays bash 3.2
# safe (under macOS /bin/bash 3.2 `declare -A` stopped it with no STATUS line).
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-settings.sh"
contract_script="${script_dir}/../../../../../scripts/check-structured-output-contract.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

# assert_contract <label> <output>
assert_contract() {
  [ -f "$contract_script" ] || fail "contract checker not found at $contract_script"
  bash "$contract_script" --validate - <<<"$2" >/dev/null \
    || fail "$1: structured-output contract violated:\n$2"
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
proj1="$(mktemp -d)" || fail "mktemp -d failed"
proj1=$(cd -P -- "$proj1" && pwd -P) || fail "cannot resolve $proj1"
mkdir -p "${proj1}/tooling/.claude"
printf '{"permissions":{"allow":["Bash(git status *)"]}}' > "${proj1}/tooling/.claude/settings.json"

out1="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj1")"
grep -q "PROJECT_DIR_RESOLVED=${proj1}/tooling" <<<"$out1" \
  || fail "expected PROJECT_DIR_RESOLVED=${proj1}/tooling, got:\n$out1"
grep -q "^PROJECT_SETTINGS=OK$" <<<"$out1" \
  || fail "expected PROJECT_SETTINGS=OK after resolving nested config, got:\n$out1"
assert_contract "case 1" "$out1"
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
grep -q "^PROJECT_DIR_HINT=" <<<"$out2" \
  || fail "expected PROJECT_DIR_HINT= with multiple nested configs, got:\n$out2"
grep -q "PROJECT_DIR_RESOLVED=" <<<"$out2" \
  && fail "must not resolve project_dir when multiple nested configs exist:\n$out2"
grep -q "^PROJECT_SETTINGS=MISSING$" <<<"$out2" \
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
grep -qE "PROJECT_DIR_(RESOLVED|HINT)=" <<<"$out3" \
  && fail "must not resolve/hint when root has its own .claude/:\n$out3"
grep -q "^PROJECT_SETTINGS=OK$" <<<"$out3" \
  || fail "expected PROJECT_SETTINGS=OK from root config, got:\n$out3"
pass "root config present takes precedence over nested config"
rm -rf "$proj3"

# -----------------------------------------------------------------------------
# Case 4: no root and no nested config → MISSING, no hint
# -----------------------------------------------------------------------------
proj4="$(mktemp -d)"
out4="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj4")"
grep -qE "PROJECT_DIR_(RESOLVED|HINT)=" <<<"$out4" \
  && fail "must not emit resolution/hint when no config exists anywhere:\n$out4"
grep -q "^PROJECT_SETTINGS=MISSING$" <<<"$out4" \
  || fail "expected PROJECT_SETTINGS=MISSING when no config exists, got:\n$out4"
pass "no config anywhere stays MISSING without spurious hint"
rm -rf "$proj4"

# -----------------------------------------------------------------------------
# Case 5: allow/deny conflict -> WARN with REASON naming it
# -----------------------------------------------------------------------------
proj5="$(mktemp -d)"
mkdir -p "${proj5}/.claude"
printf '{"permissions":{"allow":["Bash(rm *)"],"deny":["Bash(rm *)"]}}' > "${proj5}/.claude/settings.json"
out5="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj5")"
grep -q "^STATUS=WARN$" <<<"$out5" || fail "expected STATUS=WARN for a conflict, got:\n$out5"
grep -q "^REASON=permission_conflict: " <<<"$out5" \
  || fail "expected REASON=permission_conflict: ..., got:\n$out5"
assert_contract "case 5" "$out5"
pass "permission conflict gives WARN with REASON="

# -----------------------------------------------------------------------------
# Case 6: mixed ERROR (invalid JSON) + WARN (conflict) -> REASON names the
# ERROR row and the (+N more) tail counts both rows
# -----------------------------------------------------------------------------
printf '{"permissions":{"allow":["Bash(rm *)"],"deny":["Bash(rm *)"]}}' > "${proj5}/.claude/settings.json"
printf '{not json' > "${proj5}/.claude/settings.local.json"
out6="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj5")"
grep -q "^STATUS=ERROR$" <<<"$out6" || fail "expected STATUS=ERROR, got:\n$out6"
grep -q "^REASON=invalid_json: .* (+1 more)$" <<<"$out6" \
  || fail "expected REASON=invalid_json: ... (+1 more), got:\n$out6"
grep -q "^ISSUE_COUNT=2$" <<<"$out6" || fail "expected ISSUE_COUNT=2, got:\n$out6"
assert_contract "case 6" "$out6"
pass "mixed ERROR/WARN: REASON names the ERROR row"
rm -rf "$proj5"

# -----------------------------------------------------------------------------
# Case 7: clean run carries no REASON
# -----------------------------------------------------------------------------
proj7="$(mktemp -d)"
out7="$(bash "$check_script" --home-dir "$home_dir" --project-dir "$proj7")"
grep -q "^STATUS=OK$" <<<"$out7" || fail "expected STATUS=OK, got:\n$out7"
grep -q "^REASON=" <<<"$out7" && fail "STATUS=OK must not carry REASON=:\n$out7"
assert_contract "case 7" "$out7"
pass "OK carries no REASON="
rm -rf "$proj7"

# -----------------------------------------------------------------------------
# Case 8: bash 3.2 safety. The script and the lib it sources use no bash-4-only
# constructs; when a bash older than 4 is on the host, run under it too.
# -----------------------------------------------------------------------------
summary_lib="${script_dir}/../lib/summary.sh"
for src in "$check_script" "$summary_lib"; do
  grep -nE '^[^#]*(declare -A|local -A|typeset -A|mapfile|readarray|local -n|declare -n)' "$src" \
    && fail "$(basename "$src") uses a bash-4-only construct (see the lines above)"
done
old_bash=""
for candidate in /bin/bash /usr/bin/bash; do
  # shellcheck disable=SC2016 # the candidate shell expands it, not this one
  if [ -x "$candidate" ] && [ "$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"')" -lt 4 ]; then
    old_bash="$candidate"; break
  fi
done
if [ -n "$old_bash" ]; then
  proj8="$(mktemp -d)"
  out8="$("$old_bash" "$check_script" --home-dir "$home_dir" --project-dir "$proj8")"
  assert_contract "case 8 (bash 3.2)" "$out8"
  rm -rf "$proj8"
  pass "runs under $old_bash with a STATUS line"
else
  echo "SKIP: case 8 runtime half needs a bash older than 4 (none at /bin/bash or /usr/bin/bash)"
fi
pass "check-settings.sh and lib/summary.sh use no bash-4-only constructs"

echo "ALL TESTS PASSED"
