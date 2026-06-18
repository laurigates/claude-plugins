#!/usr/bin/env bash
# shellcheck disable=SC2015  # test idiom: `cond && pass || fail` — `pass` returns 0
set -uo pipefail

# Regression test for plugin-compliance-check.sh check_skill_frontmatter().
#
# Guards the duplicated-mapping-key detection. A skill frontmatter with two of
# the same top-level key (e.g. two `modified:` lines from a date-stamping
# script that appends instead of replacing) aborts the OpenCode/rulesync export
# (`just export-opencode`) with "duplicated mapping key". PyYAML's safe_load
# silently keeps the *last* value, so the prior parse check could not see it —
# the fix uses a SafeLoader subclass that rejects duplicates, matching
# rulesync's (js-yaml) strictness.
#
# See the "(just export-opencode)" regression comment in
# scripts/plugin-compliance-check.sh and the Known Regressions row in
# .claude/rules/regression-testing.md.
#
# check_skill_frontmatter() resolves "${plugin}/skills" and the script cd's to
# the repo root, so an *absolute* plugin path lets us test against a temp
# fixture without polluting the repo tree.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/plugin-compliance-check.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
assert_contains() {
  # assert_contains <description> <haystack> <needle>
  if printf '%s' "$2" | grep -qF "$3"; then
    echo "  PASS: $1"
    pass=$((pass + 1))
  else
    echo "  FAIL: $1"
    echo "    expected to find: $3"
    fail=$((fail + 1))
  fi
}
assert_absent() {
  # assert_absent <description> <haystack> <needle>
  if printf '%s' "$2" | grep -qF "$3"; then
    echo "  FAIL: $1"
    echo "    expected NOT to find: $3"
    fail=$((fail + 1))
  else
    echo "  PASS: $1"
    pass=$((pass + 1))
  fi
}

make_skill() {
  # make_skill <skill-name> <frontmatter-body>
  local dir="$tmp/dupkey-plugin/skills/$1"
  mkdir -p "$dir"
  printf -- '---\n%s\n---\nbody\n' "$2" > "$dir/SKILL.md"
}

# A skill with a duplicated `modified:` key — the exact shape that broke the
# OpenCode export.
make_skill dup \
  'name: dup
description: x
allowed-tools: Read
modified: 2026-05-09
reviewed: 2026-04-25
modified: 2026-06-18'

# A clean skill with the same keys, each appearing once.
make_skill clean \
  'name: clean
description: x
allowed-tools: Read
modified: 2026-06-18
reviewed: 2026-04-25'

# check_skill_frontmatter returns non-zero on ERROR, and the fixture trips
# unrelated checks (no plugin.json, no When-to-Use heading) — the script exits
# non-zero regardless. We only assert on the frontmatter lines, so ignore exit.
out="$(bash "$CHECK" "$tmp/dupkey-plugin" 2>&1 || true)"

echo "test-plugin-compliance-frontmatter-dupkey:"
assert_contains "duplicate modified: key is flagged as a parse error" "$out" \
  "duplicated mapping key: 'modified'"
assert_absent "clean skill (one of each key) is not flagged" "$out" \
  "dupkey-plugin/clean: SKILL.md frontmatter PARSE_ERROR"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
