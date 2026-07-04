#!/usr/bin/env bash
# Regression guard for code-review/SKILL.md rubric depth (issue #1921).
#
# The code-review skill lost the "instruction quality" axis to the official
# marketplace code-review plugin because ours described WHAT to review without
# constraining HOW findings are scored and verified. #1921 folded three
# load-bearing constructs directly into the skill body:
#   1. a Severity Rubric with explicit Critical/High/Medium/Low anchors,
#   2. a Confidence Scale with a reporting threshold,
#   3. a Re-verification Pass that re-checks each candidate finding against the
#      actual code (a false-positive gate) BEFORE the report step.
# It also must retain the `context: fork` canary (issue #980) that already lived
# in the frontmatter — this guard co-verifies it so a rubric-depth bulk edit
# can't strip it.
#
# This is a semantic guard (per .claude/rules/regression-testing.md): a future
# bulk edit that "tightens" the skill and silently drops any of these markers
# would revert the instruction-depth improvement. Auto-discovered by
# `just test-skill-scripts` (scripts/run-skill-script-tests.sh).
#
# Exit 0 on success, non-zero on any failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_md="${script_dir}/../../SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

[ -f "$skill_md" ] || fail "SKILL.md not found at $skill_md"

# 1. Severity Rubric section with all four anchors.
grep -q '^## Severity Rubric$' "$skill_md" \
  || fail "SKILL.md missing '## Severity Rubric' heading (rubric depth, #1921)"
for anchor in Critical High Medium Low; do
  grep -q "\*\*${anchor}\*\*" "$skill_md" \
    || fail "Severity Rubric missing the **${anchor}** severity anchor (#1921)"
done
pass "Severity Rubric present with Critical/High/Medium/Low anchors"

# 2. Confidence Scale section with a reporting threshold.
grep -q '^## Confidence Scale$' "$skill_md" \
  || fail "SKILL.md missing '## Confidence Scale' heading (#1921)"
grep -qi 'confidence' "$skill_md" \
  || fail "SKILL.md dropped the 'confidence' token (#1921)"
grep -qi 'threshold' "$skill_md" \
  || fail "Confidence Scale missing a reporting threshold (#1921)"
pass "Confidence Scale present with a reporting threshold"

# 3. Re-verification Pass — the false-positive gate before reporting.
grep -q '^## Re-verification Pass$' "$skill_md" \
  || fail "SKILL.md missing '## Re-verification Pass' heading (false-positive gate, #1921)"
grep -qi 'false.positive' "$skill_md" \
  || fail "Re-verification Pass dropped the false-positive-gate rationale (#1921)"
# The re-verification MUST precede the report step in the numbered analysis flow.
reverify_line="$(grep -n 'Re-verify each candidate finding' "$skill_md" | head -1 | cut -d: -f1)"
report_line="$(grep -n 'Generate report' "$skill_md" | head -1 | cut -d: -f1)"
[ -n "$reverify_line" ] || fail "missing 'Re-verify each candidate finding' analysis step (#1921)"
[ -n "$report_line" ] || fail "missing 'Generate report' analysis step (#1921)"
[ "$reverify_line" -lt "$report_line" ] \
  || fail "Re-verification step must come BEFORE report generation (#1921): reverify=$reverify_line report=$report_line"
pass "Re-verification Pass present and ordered before report generation"

# 4. The #980 canary must survive this rubric-depth edit.
grep -q '^context: fork$' "$skill_md" \
  || fail "SKILL.md lost the 'context: fork' canary (issue #980)"
pass "context: fork canary preserved (#980)"

# 5. Size floor: the skill body must stay under the compliance ERROR ceiling.
size_chars="$(wc -c < "$skill_md")"
[ "$size_chars" -le 26000 ] \
  || fail "SKILL.md is ${size_chars} chars, over the 26000-char ERROR ceiling (skill-quality.md)"
pass "SKILL.md size ${size_chars} chars is within the compliance ceiling"

echo "ALL TESTS PASSED"
