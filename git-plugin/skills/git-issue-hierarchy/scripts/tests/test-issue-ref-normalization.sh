#!/usr/bin/env bash
# Semantic regression guard for git-issue-hierarchy (issue #1660).
#
# The skill consumes every issue argument (`<parent-issue>` and each `<N>` flag
# value: --add/--remove/--block/--blocked-by/--unblock) as a bare numeric ID
# piped straight into `gh api repos/$OWNER/$REPO/issues/$N/...`. The
# argument-handling sweep (.claude/rules/skill-argument-handling.md) flagged the
# input-form gap (axis 1) + cross-context gap (axis 9): a user pasting `#N` or a
# GitHub issue URL — or a URL pointing at a DIFFERENT repo — had it silently
# ignored. The fix adds a Step 0 that normalizes `N | #N | URL -> (number, repo)`
# and carries `-R <owner>/<repo>` for cross-repo refs.
#
# This guard asserts the fix survives future bulk edits. It pins a
# NORMALIZATION-specific marker (`normaliz`) plus the cross-repo `-R ` plumbing.
# It deliberately does NOT reuse the bare `/issues/` token that the sibling
# git-issue guard uses — in this skill `/issues/` already appears throughout as
# `gh api ...` endpoint paths, so that token would pass spuriously here.
#
# Exit 0 on success, non-zero on failure.

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

body="$(cat "$skill_md")"

# 1. A normalization step must be present (case-insensitive `normaliz` catches
#    "Normalize" / "normalization" / "normalized").
grep -iq 'normaliz' <<<"$body" \
  || fail "SKILL.md dropped the issue-ref normalization step (no 'normaliz' marker); #N / URL forms would be ignored again"
pass "normalization marker present"

# 2. Cross-repo (#N/URL pointing at another repo) plumbing must be present.
grep -q -- '-R ' <<<"$body" \
  || fail "SKILL.md dropped cross-repo '-R ' plumbing; a URL for a different repo would hit the wrong remote"
pass "cross-repo -R plumbing present"

# 3. The normalization must actually cover the URL form (axis 1), not just #N.
grep -q '/issues/<N>\|/issues/<digits>\|/issues/123' <<<"$body" \
  || fail "SKILL.md normalization no longer references the /issues/<N> URL shape"
pass "issue-URL form referenced in normalization"

# 4. The Step 0 heading anchors the normalization at the start of Execution.
grep -q '^### Step 0: Normalize issue references' <<<"$body" \
  || fail "SKILL.md lost the 'Step 0: Normalize issue references' section heading"
pass "Step 0 normalization heading present"

echo "STATUS=OK"
