#!/usr/bin/env bash
# Regression guard: the grouped-PR title-pattern tagging wedge + relabel
# recovery must survive future bulk edits of the SKILL.md body.
#
# Issue #1911: with `separate-pull-requests: false`, a custom
# `pull-request-title-pattern` containing `${version}` renders a bare, un-parseable
# grouped release-PR title, so release-please never tags the merged PR and every
# subsequent run aborts with "untagged, merged release PRs outstanding". The fix
# documents both the failure (drop the custom pattern) and the recovery (relabel
# `autorelease: pending` -> `autorelease: tagged`, then dispatch a fresh run).
#
# This asserts the load-bearing tokens remain so a "tightening" pass can't
# silently drop the entry (co-located per the collision-avoidance rule — the
# guard lives here, not in the shared plugin-compliance-check.sh).
#
# Run: bash git-plugin/skills/release-please-configuration/scripts/tests/test-grouped-pr-tagging-wedge.sh
# Exit 0 = all pass, Exit 1 = a required token is missing.
set -uo pipefail

SKILL="$(cd "$(dirname "$0")/../.." && pwd)/SKILL.md"
PASS=0
FAIL=0

if [ ! -f "$SKILL" ]; then
  echo "FAIL: SKILL.md not found at $SKILL" >&2
  exit 1
fi

assert_contains() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$SKILL"; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label — missing '$needle'" >&2
    FAIL=$((FAIL + 1))
  fi
}

# The failure symptom (the abort message that identifies the wedge)
assert_contains "abort-symptom" "untagged, merged release PRs outstanding"
# The log tell that pins the diagnosis to the title pattern
assert_contains "log-tell" 'pullRequestTitlePattern miss the part'
# The root-cause knob
assert_contains "title-pattern-cause" "pull-request-title-pattern"
# The recovery labels (both source and target)
assert_contains "recovery-target-label" "autorelease: tagged"
assert_contains "recovery-source-label" "autorelease: pending"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
