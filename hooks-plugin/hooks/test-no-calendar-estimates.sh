#!/usr/bin/env bash
# Regression tests for no-calendar-estimates.sh
#
# Verifies that the Stop hook:
#  - Stays silent when CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES is unset (opt-in).
#  - Stays silent on stop_hook_active=true (one-nudge guard).
#  - Blocks with the positive-guidance reason when the last assistant response
#    contains future-tense calendar estimates.
#  - Allows past-tense observations, frequency descriptions, and config values
#    that mention time units.
#
# Run: bash hooks-plugin/hooks/test-no-calendar-estimates.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

HOOK="$(dirname "$0")/no-calendar-estimates.sh"
PASS=0
FAIL=0

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Build a JSONL transcript containing one assistant message with the given text.
# jq -c emits one compact line per object (JSONL format the hook expects).
make_transcript() {
    local text="$1"
    local path="$2"
    jq -nc --arg text "$text" '{
        message: { role: "assistant", content: [{ type: "text", text: $text }] }
    }' > "$path"
}

# Run the hook with a synthesized transcript and return its stdout.
run_hook_output() {
    local transcript="$1"
    local stop_active="${2:-false}"
    printf '{"transcript_path":"%s","stop_hook_active":%s}' "$transcript" "$stop_active" \
        | CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES=1 bash "$HOOK" 2>/dev/null || true
}

# Run the hook without the opt-in env var set.
run_hook_optout() {
    local transcript="$1"
    # Unset explicitly: the developer's shell may export the opt-in var,
    # which made this test fail locally while passing in clean CI.
    printf '{"transcript_path":"%s"}' "$transcript" \
        | env -u CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES bash "$HOOK" 2>/dev/null || true
}

assert_blocks() {
    local desc="$1" text="$2"
    local t="$TMPDIR/transcript-$RANDOM.jsonl"
    make_transcript "$text" "$t"
    local out
    out=$(run_hook_output "$t")
    if echo "$out" | grep -q '"decision": "block"'; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected block, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

assert_allows() {
    local desc="$1" text="$2"
    local t="$TMPDIR/transcript-$RANDOM.jsonl"
    make_transcript "$text" "$t"
    local out
    out=$(run_hook_output "$t")
    if [ -z "$out" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected silent allow, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== no-calendar-estimates hook tests ==="

# ── opt-in guard ──────────────────────────────────────────────────────────────
echo ""
echo "opt-in guard:"
t="$TMPDIR/transcript-optout.jsonl"
make_transcript "This will take 3 hours to finish." "$t"
out=$(run_hook_optout "$t")
if [ -z "$out" ]; then
    printf "  PASS: %s\n" "hook is silent when CLAUDE_HOOKS_ENABLE_CALENDAR_ESTIMATES is unset"
    PASS=$((PASS + 1))
else
    printf "  FAIL: hook fired without opt-in (output: %s)\n" "$out"
    FAIL=$((FAIL + 1))
fi

# ── stop_hook_active guard ────────────────────────────────────────────────────
echo ""
echo "stop_hook_active guard:"
t="$TMPDIR/transcript-active.jsonl"
make_transcript "This will take 3 hours to finish." "$t"
out=$(run_hook_output "$t" "true")
if [ -z "$out" ]; then
    printf "  PASS: %s\n" "stop_hook_active=true exits 0 (no re-blocking on revised response)"
    PASS=$((PASS + 1))
else
    printf "  FAIL: stop_hook_active=true still blocked (output: %s)\n" "$out"
    FAIL=$((FAIL + 1))
fi

# ── future-tense calendar estimates SHOULD block ──────────────────────────────
echo ""
echo "future-tense calendar estimates block:"
assert_blocks "this'll take 3 hours"                "This'll take 3 hours to wire up."
assert_blocks "should take about 2 weeks"           "The migration should take about 2 weeks."
assert_blocks "would take roughly 5 minutes"        "Refactoring this would take roughly 5 minutes."
assert_blocks "will need 30 minutes"                "We'll need 30 minutes to refactor the loader."
assert_blocks "going to require 2 days"             "This is going to require 2 days of work."
assert_blocks "could take a few weeks"              "Migrating could take a few weeks if we hit edge cases."

# ── explicit estimate markers SHOULD block ────────────────────────────────────
echo ""
echo "explicit estimate markers block:"
assert_blocks "ETA: 30 minutes"                     "ETA: 30 minutes for the rollout."
assert_blocks "estimated 2 days"                    "I've estimated 2 days for this refactor."
assert_blocks "approximately 5 hours"               "Approximately 5 hours of engineering effort."
assert_blocks "expect this in 2 weeks"              "Expect this work in 2 weeks if priorities hold."
assert_blocks "roughly 4 hours"                     "Roughly 4 hours to finish the migration."

# ── past-tense and observational mentions SHOULD pass ─────────────────────────
echo ""
echo "past-tense and observational mentions pass:"
assert_allows "past-tense took"                     "The migration took 2 hours to finish."
assert_allows "modified N days ago"                 "The file was modified 2 days ago."
assert_allows "frequency (every N hours)"           "The cron job runs every 3 hours."
assert_allows "config timeout in seconds"           "The API timeout is 30 seconds."
assert_allows "ran for N minutes"                   "The build ran for 5 minutes before failing."

# ── unrelated content SHOULD pass ─────────────────────────────────────────────
echo ""
echo "unrelated content passes:"
assert_allows "no time mentions at all"             "I've refactored the loader and updated the tests."
assert_allows "number without time unit"            "There are 47 files in the dist directory."
assert_allows "time unit without number"            "I'll add a few comments to the loader."

# ── reason text carries positive guidance ─────────────────────────────────────
echo ""
echo "block reason carries positive guidance:"
t="$TMPDIR/transcript-reason.jsonl"
make_transcript "Would take about 3 hours" "$t"
out=$(run_hook_output "$t")
for token in "tokens" "context-window" "effort tier" "tool-call count"; do
    if echo "$out" | grep -q "$token"; then
        printf "  PASS: reason mentions '%s'\n" "$token"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: reason missing '%s' (output: %s)\n" "$token" "$out"
        FAIL=$((FAIL + 1))
    fi
done

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
