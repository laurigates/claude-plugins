#!/usr/bin/env bash
# Regression test for github-actions-finops.sh (issue #1555).
#
# The script extracts the deterministic FinOps data-gathering from the skill:
# run grouping, duration aggregation, waste-count detection, the >10% skipped
# threshold, and the static fix-suggestion lookup. These tests pin the
# SEMANTIC invariants — correct STATUS / counts on planted-waste data, STATUS=OK
# / zero waste on clean data, and graceful degradation on an empty payload —
# all through the GITHUB_ACTIONS_FINOPS_FIXTURE seam so they run fully offline.
# Exit 0 on success, non-zero on any failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
finops_script="${script_dir}/../github-actions-finops.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run github-actions-finops tests"
  exit 0
fi

[ -f "$finops_script" ] || fail "github-actions-finops.sh not found at $finops_script"

fixtures_dir="$(mktemp -d)"
home_dir="$(mktemp -d)"
trap 'rm -rf "$fixtures_dir" "$home_dir"' EXIT

LAST_RC=0
SCRIPT_OUT=""
run_script() {
  # $1 = fixture path; sets global SCRIPT_OUT (output) and LAST_RC (exit code).
  # Sets globals rather than printing so callers don't nest a command
  # substitution (which would run this in a subshell and lose LAST_RC).
  local fixture="$1"
  SCRIPT_OUT="$(GITHUB_ACTIONS_FINOPS_FIXTURE="$fixture" \
    bash "$finops_script" --home-dir "$home_dir" --project-dir "$fixtures_dir")"
  LAST_RC=$?
}

# -----------------------------------------------------------------------------
# Case 1: planted waste — high skipped ratio, bot triggers, high-frequency.
#   6 skipped of 52 = 11% (> 10% threshold)  → skipped_runs WARN
#   2 bot-triggered                          → bot_triggered WARN
#   "noisy.yml" has 51 runs (> 50)           → high_frequency WARN
# Expect STATUS=WARN, the three counts, and the three issue rows.
# -----------------------------------------------------------------------------
planted="${fixtures_dir}/planted.json"
{
  echo '{'
  echo '  "billing": {"included_minutes": 2000, "total_minutes_used": 1500, "total_paid_minutes_used": 0},'
  echo '  "workflow_runs": ['
  # 51 runs on noisy.yml (high-frequency); 6 of them skipped → 6/52 = 11% (>10%)
  for i in $(seq 1 51); do
    conclusion="success"
    [ "$i" -le 6 ] && conclusion="skipped"
    actor='{"type": "User", "login": "alice"}'
    [ "$i" -le 2 ] && actor='{"type": "Bot", "login": "dependabot[bot]"}'
    sep=","
    echo "    {\"name\": \"noisy.yml\", \"conclusion\": \"${conclusion}\", \"triggering_actor\": ${actor}, \"run_started_at\": \"2026-01-01T00:00:00Z\", \"updated_at\": \"2026-01-01T00:05:00Z\"}${sep}"
  done
  # one trailing run with no comma issue: add a final calm.yml run
  echo '    {"name": "calm.yml", "conclusion": "success", "triggering_actor": {"type": "User", "login": "alice"}, "run_started_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:02:00Z"}'
  echo '  ]'
  echo '}'
} > "$planted"

run_script "$planted"; out1="$SCRIPT_OUT"; rc1=$LAST_RC
[ "$rc1" -eq 0 ] || fail "planted-waste run exited $rc1 (expected 0 for WARN):\n$out1"
echo "$out1" | grep -q "^STATUS=WARN$" \
  || fail "expected STATUS=WARN on planted waste, got:\n$out1"
echo "$out1" | grep -q "^SKIPPED_RUNS=6$" \
  || fail "expected SKIPPED_RUNS=6, got:\n$out1"
echo "$out1" | grep -q "^BOT_TRIGGERED_RUNS=2$" \
  || fail "expected BOT_TRIGGERED_RUNS=2, got:\n$out1"
echo "$out1" | grep -q "^HIGH_FREQUENCY_WORKFLOWS=1$" \
  || fail "expected HIGH_FREQUENCY_WORKFLOWS=1, got:\n$out1"
echo "$out1" | grep -q "TYPE=skipped_runs" \
  || fail "expected a skipped_runs issue, got:\n$out1"
echo "$out1" | grep -q "TYPE=bot_triggered" \
  || fail "expected a bot_triggered issue, got:\n$out1"
echo "$out1" | grep -q "TYPE=high_frequency" \
  || fail "expected a high_frequency issue, got:\n$out1"
echo "$out1" | grep -q "^ISSUE_COUNT=3$" \
  || fail "expected ISSUE_COUNT=3, got:\n$out1"
echo "$out1" | grep -q "^BILLING_AVAILABLE=true$" \
  || fail "expected BILLING_AVAILABLE=true from fixture billing, got:\n$out1"
echo "$out1" | grep -q "^BILLING_TOTAL_MINUTES_USED=1500$" \
  || fail "expected BILLING_TOTAL_MINUTES_USED=1500, got:\n$out1"
# duration: noisy.yml has 51×300s = 15300s, dominates calm.yml (120s)
echo "$out1" | grep -q "^WORKFLOW_DURATION_SECONDS=noisy.yml|15300$" \
  || fail "expected noisy.yml duration 15300s, got:\n$out1"
pass "planted waste yields STATUS=WARN, correct counts, three fix suggestions, billing + duration"

# -----------------------------------------------------------------------------
# Case 2: clean data — no skipped, no bots, low frequency.
# Expect STATUS=OK, zero counts, ISSUE_COUNT=0, no ISSUES block.
# -----------------------------------------------------------------------------
clean="${fixtures_dir}/clean.json"
cat > "$clean" <<'JSON'
{
  "workflow_runs": [
    {"name": "ci.yml", "conclusion": "success", "triggering_actor": {"type": "User", "login": "alice"}, "run_started_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:03:00Z"},
    {"name": "ci.yml", "conclusion": "success", "triggering_actor": {"type": "User", "login": "bob"}, "run_started_at": "2026-01-01T01:00:00Z", "updated_at": "2026-01-01T01:04:00Z"},
    {"name": "release.yml", "conclusion": "success", "triggering_actor": {"type": "User", "login": "alice"}, "run_started_at": "2026-01-01T02:00:00Z", "updated_at": "2026-01-01T02:01:00Z"}
  ]
}
JSON

run_script "$clean"; out2="$SCRIPT_OUT"; rc2=$LAST_RC
[ "$rc2" -eq 0 ] || fail "clean run exited $rc2 (expected 0):\n$out2"
echo "$out2" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK on clean data, got:\n$out2"
echo "$out2" | grep -q "^SKIPPED_RUNS=0$" \
  || fail "expected SKIPPED_RUNS=0, got:\n$out2"
echo "$out2" | grep -q "^BOT_TRIGGERED_RUNS=0$" \
  || fail "expected BOT_TRIGGERED_RUNS=0, got:\n$out2"
echo "$out2" | grep -q "^HIGH_FREQUENCY_WORKFLOWS=0$" \
  || fail "expected HIGH_FREQUENCY_WORKFLOWS=0, got:\n$out2"
echo "$out2" | grep -q "^ISSUE_COUNT=0$" \
  || fail "expected ISSUE_COUNT=0, got:\n$out2"
echo "$out2" | grep -q "^ISSUES:$" \
  && fail "expected no ISSUES block on clean data, got:\n$out2"
echo "$out2" | grep -q "^BILLING_AVAILABLE=false$" \
  || fail "expected BILLING_AVAILABLE=false when fixture omits billing, got:\n$out2"
pass "clean data yields STATUS=OK, zero counts, no issues, no billing"

# -----------------------------------------------------------------------------
# Case 3: empty payload — workflow_runs present but empty.
# Graceful degradation: STATUS=OK, TOTAL_RUNS=0, SKIPPED_PERCENT=0, no crash.
# -----------------------------------------------------------------------------
empty="${fixtures_dir}/empty.json"
echo '{"workflow_runs": []}' > "$empty"

run_script "$empty"; out3="$SCRIPT_OUT"; rc3=$LAST_RC
[ "$rc3" -eq 0 ] || fail "empty run exited $rc3 (expected 0):\n$out3"
echo "$out3" | grep -q "^STATUS=OK$" \
  || fail "expected STATUS=OK on empty payload, got:\n$out3"
echo "$out3" | grep -q "^TOTAL_RUNS=0$" \
  || fail "expected TOTAL_RUNS=0, got:\n$out3"
echo "$out3" | grep -q "^SKIPPED_PERCENT=0$" \
  || fail "expected SKIPPED_PERCENT=0 (no divide-by-zero), got:\n$out3"
echo "$out3" | grep -q "^ISSUE_COUNT=0$" \
  || fail "expected ISSUE_COUNT=0 on empty payload, got:\n$out3"
pass "empty payload degrades gracefully without crash or divide-by-zero"

# -----------------------------------------------------------------------------
# Case 4: missing fixture path → STATUS=ERROR, exit 1.
# -----------------------------------------------------------------------------
run_script "${fixtures_dir}/does-not-exist.json"; out4="$SCRIPT_OUT"; rc4=$LAST_RC
[ "$rc4" -eq 1 ] || fail "missing-fixture run exited $rc4 (expected 1):\n$out4"
echo "$out4" | grep -q "^STATUS=ERROR$" \
  || fail "expected STATUS=ERROR on missing fixture, got:\n$out4"
echo "$out4" | grep -q "TYPE=fixture_missing" \
  || fail "expected a fixture_missing issue, got:\n$out4"
pass "missing fixture yields STATUS=ERROR and exit 1"

# -----------------------------------------------------------------------------
# Case 5: section delimiters present and balanced.
# -----------------------------------------------------------------------------
echo "$out2" | grep -q "^=== GITHUB ACTIONS FINOPS ===$" \
  || fail "expected opening section header, got:\n$out2"
echo "$out2" | grep -q "^=== END GITHUB ACTIONS FINOPS ===$" \
  || fail "expected closing section footer, got:\n$out2"
pass "structured-output section delimiters present"

echo "ALL TESTS PASSED"
