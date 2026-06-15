#!/usr/bin/env bash
# shellcheck disable=SC2015  # test idiom: `cond && pass || fail` — `pass` returns 0
set -uo pipefail

# Regression test for plugin-compliance-check.sh check_skill_size().
#
# Guards the metric switch from lines (`wc -l`) to characters (`wc -c`):
# lines are a poor token proxy (chars/line spans ~3.6x in this repo), so the
# gate now measures bytes ≈ characters and reports a chars/4 token estimate.
# See .claude/rules/skill-quality.md "Size Limits" and the
# "skill-line-count-validity" row in .claude/rules/regression-testing.md.
#
# Thresholds under test:
#   ≤ 10000 chars        → OK   (silent — no size line)
#   10001 – 26000 chars  → WARN (recommendation, "⚠️ ... >10000")
#   > 26000 chars        → ERROR ("❌ ... >26000 ceiling")
#
# check_skill_size() resolves "${plugin}/skills", and the script cd's to the
# repo root, so an *absolute* plugin path lets us test against a temp fixture
# without polluting the repo tree.

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
assert_matches() {
  # assert_matches <description> <haystack> <extended-regex>
  if printf '%s' "$2" | grep -qE "$3"; then
    echo "  PASS: $1"
    pass=$((pass + 1))
  else
    echo "  FAIL: $1"
    echo "    expected to match: $3"
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

# Build a fixture plugin with three skills at controlled char counts.
make_skill() {
  # make_skill <skill-name> <body-char-count>
  local dir="$tmp/sizetest-plugin/skills/$1"
  mkdir -p "$dir"
  printf -- '---\nname: %s\ndescription: x\nallowed-tools: Read\n---\n' "$1" > "$dir/SKILL.md"
  head -c "$2" /dev/zero | tr '\0' 'a' >> "$dir/SKILL.md"
}
make_skill ok 5000        # ~5k chars  → OK   (no size line)
make_skill warnish 15000  # ~15k chars → WARN (>10000)
make_skill toobig 30000   # ~30k chars → ERROR (>26000)

# check_skill_size returns non-zero on ERROR, and the fixture trips unrelated
# checks (no plugin.json, no When-to-Use heading) — the script exits non-zero
# regardless. We only assert on the size lines, so ignore the exit code.
out="$(bash "$CHECK" "$tmp/sizetest-plugin" 2>&1 || true)"

echo "test-plugin-compliance-skill-size:"
assert_matches "ERROR fires above 26000 chars (toobig)" "$out" \
  'toobig: SKILL.md is [0-9]+ chars \(~[0-9]+ tokens, >26000 ceiling\)'
assert_matches "WARN fires in 10001-26000 band (warnish)" "$out" \
  'warnish: SKILL.md is [0-9]+ chars \(~[0-9]+ tokens, >10000\)'
assert_absent  "OK skill below 10000 chars emits no size line (ok)" "$out" "ok: SKILL.md is"
# The gate must measure chars, not lines: the fixtures are single-line bodies
# (one long 'aaa...' run) yet still trip the WARN/ERROR thresholds — impossible
# under a line-count gate.
assert_contains "metric is characters/tokens, not lines" "$out" "tokens,"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
