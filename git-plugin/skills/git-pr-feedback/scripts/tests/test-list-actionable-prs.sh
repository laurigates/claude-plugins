#!/usr/bin/env bash
# Regression tests for list-actionable-prs.sh
#
# Run: bash git-plugin/skills/git-pr-feedback/scripts/tests/test-list-actionable-prs.sh
# Exit 0 = all pass, 1 = failures
#
# Uses PR_FEEDBACK_FIXTURE to feed a captured GraphQL response so the jq
# filtering logic is exercised without network/auth.
#
# Regression (issue #1420): --all surfaced automation-authored PRs (e.g. a
# release-please PR with no review feedback) purely because CI was failing,
# forcing a per-PR AskUserQuestion. Automation authors are now excluded by
# default; --include-automation opts back in.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECTOR="$SCRIPT_DIR/../list-actionable-prs.sh"
PASS=0
FAIL=0

fixture="$(mktemp)"
trap 'rm -f "$fixture"' EXIT

# Five open PRs:
#  #10 human, CI FAILURE              -> actionable, kept
#  #11 release-please[bot], CI FAILURE-> actionable but automation, excluded by default
#  #12 fvh-buildbot, CI FAILURE       -> custom automation login, excluded by default
#  #13 some-bot, 2 unresolved threads -> *-bot pattern, excluded by default
#  #14 human, all green/resolved      -> not actionable, never listed
cat > "$fixture" <<'EOF'
{
  "data": { "repository": { "pullRequests": { "nodes": [
    { "number": 10, "title": "feat: real work", "url": "u10", "isDraft": false,
      "author": {"login": "alice"}, "headRefName": "feat-x", "reviewDecision": null, "updatedAt": "2026-06-03T10:00:00Z",
      "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]},
      "reviewThreads": {"nodes": []} },
    { "number": 11, "title": "chore: release main", "url": "u11", "isDraft": false,
      "author": {"login": "release-please[bot]"}, "headRefName": "release-please--branches--main", "reviewDecision": null, "updatedAt": "2026-06-03T09:00:00Z",
      "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]},
      "reviewThreads": {"nodes": []} },
    { "number": 12, "title": "build: bump image", "url": "u12", "isDraft": false,
      "author": {"login": "fvh-buildbot"}, "headRefName": "image-update", "reviewDecision": null, "updatedAt": "2026-06-03T08:00:00Z",
      "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]},
      "reviewThreads": {"nodes": []} },
    { "number": 13, "title": "chore: deps", "url": "u13", "isDraft": false,
      "author": {"login": "some-bot"}, "headRefName": "deps", "reviewDecision": null, "updatedAt": "2026-06-03T07:00:00Z",
      "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]},
      "reviewThreads": {"nodes": [{"isResolved": false, "isOutdated": false},{"isResolved": false, "isOutdated": false}]} },
    { "number": 14, "title": "feat: done", "url": "u14", "isDraft": false,
      "author": {"login": "bob"}, "headRefName": "done", "reviewDecision": null, "updatedAt": "2026-06-03T06:00:00Z",
      "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "SUCCESS"}}}]},
      "reviewThreads": {"nodes": [{"isResolved": true, "isOutdated": false}]} }
  ] } } }
}
EOF

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (expected [%s], got [%s])\n" "$desc" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

numbers() { jq -c '[.[].number]'; }

echo "=== list-actionable-prs automation filtering (issue #1420) ==="

default_out=$(PR_FEEDBACK_FIXTURE="$fixture" bash "$SELECTOR" acme widgets)
assert_eq "default excludes all automation authors, keeps only human #10" \
  '[10]' "$(printf '%s' "$default_out" | numbers)"

incl_out=$(PR_FEEDBACK_FIXTURE="$fixture" bash "$SELECTOR" --include-automation acme widgets)
assert_eq "--include-automation surfaces automation PRs too (#10-#13, not green #14)" \
  '[10,11,12,13]' "$(printf '%s' "$incl_out" | numbers)"

# Env-var extension: add a custom non-pattern automation login.
cat > "$fixture.custom" <<'EOF'
{ "data": { "repository": { "pullRequests": { "nodes": [
  { "number": 20, "title": "auto", "url": "u20", "isDraft": false,
    "author": {"login": "acme-ci-runner"}, "headRefName": "auto", "reviewDecision": null, "updatedAt": "2026-06-03T10:00:00Z",
    "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]},
    "reviewThreads": {"nodes": []} }
] } } } }
EOF
custom_out=$(PR_FEEDBACK_FIXTURE="$fixture.custom" PR_FEEDBACK_AUTOMATION_AUTHORS="acme-ci-runner" bash "$SELECTOR" acme widgets)
assert_eq "PR_FEEDBACK_AUTOMATION_AUTHORS extends the exclusion list (#20 dropped)" \
  '[]' "$(printf '%s' "$custom_out" | numbers)"
rm -f "$fixture.custom"

# Regression (issue #3129): feedback posted as a top-level PR conversation
# comment or as a COMMENTED review body was invisible — reviewDecision stays
# null (a COMMENTED review never sets it, and an author cannot request changes
# on their own PR), so --all reported "No PRs need attention." with feedback
# waiting. Selection keys on presence + recency (newer than the latest
# commit), never on parsed severity, and skips the skill's own
# `Fixed in <sha>` style replies.
echo ""
echo "=== list-actionable-prs top-level feedback (issue #3129) ==="
cat > "$fixture.toplevel" <<'EOF'
{ "data": { "repository": { "pullRequests": { "nodes": [
  { "number": 30, "title": "author comment", "url": "u30", "isDraft": false,
    "author": {"login": "alice"}, "headRefName": "c30", "reviewDecision": null, "updatedAt": "2026-06-03T10:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-01T10:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": [{"author": {"login": "alice"}, "body": "## Review\nVerdict: looks fine\n- [Nit] rename x", "createdAt": "2026-06-02T10:00:00Z"}]},
    "reviews": {"nodes": []},
    "reviewThreads": {"nodes": []} },
  { "number": 31, "title": "commented review", "url": "u31", "isDraft": false,
    "author": {"login": "alice"}, "headRefName": "c31", "reviewDecision": null, "updatedAt": "2026-06-03T09:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-01T10:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": []},
    "reviews": {"nodes": [{"author": {"login": "carol"}, "state": "COMMENTED", "body": "One more defect in parse()", "submittedAt": "2026-06-02T11:00:00Z"}]},
    "reviewThreads": {"nodes": []} },
  { "number": 32, "title": "stale feedback", "url": "u32", "isDraft": false,
    "author": {"login": "alice"}, "headRefName": "c32", "reviewDecision": null, "updatedAt": "2026-06-03T08:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-03T07:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": [{"author": {"login": "alice"}, "body": "Please fix the typo", "createdAt": "2026-06-02T10:00:00Z"}]},
    "reviews": {"nodes": [{"author": {"login": "carol"}, "state": "COMMENTED", "body": "Also check null input", "submittedAt": "2026-06-02T11:00:00Z"}]},
    "reviewThreads": {"nodes": []} },
  { "number": 33, "title": "own reply only", "url": "u33", "isDraft": false,
    "author": {"login": "alice"}, "headRefName": "c33", "reviewDecision": null, "updatedAt": "2026-06-03T07:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-01T10:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": [{"author": {"login": "alice"}, "body": "Fixed in abc1234 — handle empty input.", "createdAt": "2026-06-02T10:00:00Z"}]},
    "reviews": {"nodes": []},
    "reviewThreads": {"nodes": []} },
  { "number": 34, "title": "whitespace-only COMMENTED review", "url": "u34", "isDraft": false,
    "author": {"login": "alice"}, "headRefName": "c34", "reviewDecision": null, "updatedAt": "2026-06-03T06:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-01T10:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": []},
    "reviews": {"nodes": [{"author": {"login": "carol"}, "state": "COMMENTED", "body": "  \n", "submittedAt": "2026-06-02T11:00:00Z"}]},
    "reviewThreads": {"nodes": []} },
  { "number": 35, "title": "draft with fresh comment", "url": "u35", "isDraft": true,
    "author": {"login": "alice"}, "headRefName": "c35", "reviewDecision": null, "updatedAt": "2026-06-03T05:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-01T10:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": [{"author": {"login": "carol"}, "body": "Needs a test", "createdAt": "2026-06-02T10:00:00Z"}]},
    "reviews": {"nodes": []},
    "reviewThreads": {"nodes": []} },
  { "number": 36, "title": "bot PR with fresh comment", "url": "u36", "isDraft": false,
    "author": {"login": "renovate[bot]"}, "headRefName": "c36", "reviewDecision": null, "updatedAt": "2026-06-03T04:00:00Z",
    "commits": {"nodes": [{"commit": {"committedDate": "2026-06-01T10:00:00Z", "statusCheckRollup": {"state": "SUCCESS"}}}]},
    "comments": {"nodes": [{"author": {"login": "carol"}, "body": "Hold this one", "createdAt": "2026-06-02T10:00:00Z"}]},
    "reviews": {"nodes": []},
    "reviewThreads": {"nodes": []} }
] } } } }
EOF
top_out=$(PR_FEEDBACK_FIXTURE="$fixture.toplevel" bash "$SELECTOR" acme widgets)
assert_eq "author conversation comment (#30) and COMMENTED review (#31) select; stale (#32), own Fixed-in reply (#33), blank body (#34), draft (#35), automation (#36) do not" \
  '[30,31]' "$(printf '%s' "$top_out" | numbers)"
assert_eq "topLevelFeedback reports the count that drove selection" \
  '[1,1]' "$(printf '%s' "$top_out" | jq -c '[.[].topLevelFeedback]')"
assert_eq "existing selection unchanged: fixture without comments/reviews reports topLevelFeedback 0" \
  '[0]' "$(printf '%s' "$default_out" | jq -c '[.[].topLevelFeedback]')"
rm -f "$fixture.toplevel"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
