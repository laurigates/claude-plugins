#!/usr/bin/env bash
# Doc pin for #2758: session-spinup renders the unanswered-Discussions keys that
# session-survey.sh emits in GITHUB_DRIFT (#2569), and renders a failed query as
# "not queried" rather than a zero.
#
# The collector's own behaviour is covered by test-session-survey.sh (TEST AQ).
# What no execution test can see is whether the SKILL still TELLS the agent to
# read DISCUSSIONS_QUERY_OK before printing a count — drop that and a failed
# GraphQL call is briefed as "0 unanswered" again. So this pins the semantic
# tokens, not the prose around them.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SPINUP_SKILL_DIR_UNDER_TEST:-$SCRIPT_DIR/../../skills/session-spinup}"
SKILL_MD="$SKILL_DIR/SKILL.md"
REFERENCE_MD="$SKILL_DIR/REFERENCE.md"

pass=0
fail=0
pin() {  # $1 = label, $2 = file, $3 = literal token
  if [ -f "$2" ] && grep -qF -- "$3" "$2"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $1"
    echo "  expected $(basename "$2") to contain: $3"
  fi
}

# SKILL.md — the execution path the agent follows.
pin "SKILL gates the count on the query's own ok-key" "$SKILL_MD" "DISCUSSIONS_QUERY_OK=false"
pin "SKILL renders a failed query as not queried, with its reason" "$SKILL_MD" \
  "discussions: not queried (<DISCUSSIONS_FAIL_REASON>)"
pin "SKILL forbids a zero for a failed query" "$SKILL_MD" "never render a zero"
pin "SKILL reads the unanswered count" "$SKILL_MD" "DISCUSSIONS_UNANSWERED"
pin "SKILL renders the per-thread rows" "$SKILL_MD" "DISCUSSION_<n>_"
pin "SKILL treats a disabled Discussions feature as a genuine zero" "$SKILL_MD" \
  "DISCUSSIONS_ENABLED=false"
pin "SKILL renders a truncated read as a floor" "$SKILL_MD" "DISCUSSIONS_TRUNCATED=true"
pin "SKILL names the 100+ floor" "$SKILL_MD" "100+"

# REFERENCE.md — the interpretation table the SKILL defers detail to.
pin "REFERENCE documents DISCUSSIONS_QUERY_OK" "$REFERENCE_MD" "DISCUSSIONS_QUERY_OK=false"
pin "REFERENCE documents the not-queried rendering" "$REFERENCE_MD" "discussions: not queried"

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
