#!/usr/bin/env bash
# shellcheck disable=SC2015  # test idiom: `cond && pass || fail` — `pass` returns 0
set -uo pipefail

# Regression test for plugin-compliance-check.sh check_skill_size().
#
# Guards the metric switch from lines (`wc -l`) to characters: lines are a poor
# token proxy (chars/line spans ~3.6x in this repo), so the gate measures
# decoded UTF-8 characters and reports a chars/4 token estimate.
#
# Also guards the unit itself (issue #2135): the gate must count CHARACTERS,
# not bytes. `wc -c` counts bytes and bare `wc -m` counts bytes under a C/POSIX
# locale, so a body using em-dashes/arrows can cross the ceiling on UTF-8
# encoding overhead alone. The `straddle` fixture below is the semantic
# invariant — bytes above the ceiling, characters below it, must PASS. Every
# other fixture here is ASCII, where bytes == characters and the bug is
# invisible.
#
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
assert_not_matches() {
  # assert_not_matches <description> <haystack> <extended-regex>
  # Here-string, not a pipe: `grep -q` closes stdin on first match, which under
  # `set -o pipefail` would surface the writer's SIGPIPE as a false failure.
  if grep -qE "$3" <<<"$2"; then
    echo "  FAIL: $1"
    echo "    expected NOT to match: $3"
    fail=$((fail + 1))
  else
    echo "  PASS: $1"
    pass=$((pass + 1))
  fi
}

# Decoded UTF-8 character count — the unit the gate is supposed to measure.
char_count() { python3 -c 'import sys; print(len(open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read()))' "$1"; }

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
make_skill toobig 30000   # ~30k chars → ERROR (>26000), genuinely over in CHARACTERS

# The #2135 straddle fixture: ASCII filler plus U+2014 EM DASH (3 bytes in
# UTF-8, so +2 bytes per character). Byte count lands ABOVE the 26000 ceiling
# while the character count stays BELOW it — a byte-counting gate ERRORs here,
# a character-counting gate does not.
make_straddle_skill() {
  # make_straddle_skill <skill-name> <ascii-filler-chars> <em-dash-count>
  local dir="$tmp/sizetest-plugin/skills/$1"
  mkdir -p "$dir"
  printf -- '---\nname: %s\ndescription: x\nallowed-tools: Read\n---\n' "$1" > "$dir/SKILL.md"
  head -c "$2" /dev/zero | tr '\0' 'a' >> "$dir/SKILL.md"
  python3 -c 'import sys; sys.stdout.write("—" * int(sys.argv[1]))' "$3" >> "$dir/SKILL.md"
}
make_straddle_skill straddle 25600 200

straddle_file="$tmp/sizetest-plugin/skills/straddle/SKILL.md"
straddle_bytes=$(wc -c < "$straddle_file" | tr -d ' ')
straddle_chars=$(char_count "$straddle_file")

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

# --- #2135: the gate's UNIT is characters, not bytes -------------------------
# Fixture-validity guard first: if the straddle property does not hold, the
# assertions below prove nothing.
if [ "$straddle_bytes" -gt 26000 ] && [ "$straddle_chars" -le 26000 ]; then
  echo "  PASS: straddle fixture is valid (${straddle_bytes} bytes > 26000 >= ${straddle_chars} chars)"
  pass=$((pass + 1))
else
  echo "  FAIL: straddle fixture is invalid (${straddle_bytes} bytes, ${straddle_chars} chars)"
  echo "    expected bytes > 26000 and chars <= 26000"
  fail=$((fail + 1))
fi
assert_not_matches "bytes-over/chars-under body does NOT trip ERROR (#2135)" "$out" \
  'straddle: SKILL.md is [0-9]+ chars \(~[0-9]+ tokens, >26000 ceiling\)'
assert_contains "size line reports the CHARACTER count (#2135)" "$out" \
  "straddle: SKILL.md is ${straddle_chars} chars"
assert_absent "size line does not report the BYTE count (#2135)" "$out" \
  "straddle: SKILL.md is ${straddle_bytes} chars"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
