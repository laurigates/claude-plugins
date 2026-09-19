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
#  - Matches only the main agent's own trailing text: subagent (isSidechain)
#    turns and text blocks before the last tool_use are out of scope, while
#    transcripts lacking either marker keep their previous behaviour (#2650).
#  - Leads with rate x quantity, not the effort-unit list, when the blocked
#    text names a measured rate (#2650).
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

# (#2650) Transcript whose LAST assistant entry is a subagent turn
# (isSidechain: true). The main agent's own trailing message is $main_text.
make_transcript_sidechain() {
    local main_text="$1" sidechain_text="$2" path="$3"
    jq -nc --arg text "$main_text" '{
        message: { role: "assistant", content: [{ type: "text", text: $text }] }
    }' > "$path"
    jq -nc --arg text "$sidechain_text" '{
        isSidechain: true,
        message: { role: "assistant", content: [{ type: "text", text: $text }] }
    }' >> "$path"
}

# (#2650) One assistant entry holding [text, tool_use, text] — narration before
# a tool call, then the text the turn actually ends with.
make_transcript_blocks() {
    local pre_text="$1" post_text="$2" path="$3"
    jq -nc --arg pre "$pre_text" --arg post "$post_text" '{
        message: {
            role: "assistant",
            content: [
                { type: "text", text: $pre },
                { type: "tool_use", id: "toolu_test", name: "Bash", input: {} },
                { type: "text", text: $post }
            ]
        }
    }' > "$path"
}

# Assertions over an already-built transcript file (the builders above produce
# shapes make_transcript cannot express).
assert_blocks_file() {
    local desc="$1" transcript="$2"
    local out
    out=$(run_hook_output "$transcript")
    if echo "$out" | grep -q '"decision": "block"'; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected block, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

assert_allows_file() {
    local desc="$1" transcript="$2"
    local out
    out=$(run_hook_output "$transcript")
    if [ -z "$out" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected silent allow, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
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

# ── the narrowing must not stop real estimates firing (issue #2654) ───────────
# #2654 required the number to sit adjacent to a word-bounded time unit. These
# positives pin the forms that adjacency must keep covering, so a future
# tightening cannot quietly turn the hook off: a spelled-out range, a
# punctuation range, and the vague quantifier's idiomatic "of".
echo ""
echo "adjacent quantities still block after the #2654 narrowing:"
assert_blocks "spelled-out range"                   "This will take 3 to 4 days."
assert_blocks "hyphenated range"                    "Rollout will need 30-45 minutes."
assert_blocks "couple of days"                      "Finishing this would take a couple of days."

# ── control: the matcher is deliberately NOT narrowed (issue #2574) ───────────
# The reporter's exact blocked text. #2574 asked for the *message* to name the
# external-machine-work case (option 1), explicitly NOT for the matcher to stop
# firing near a measured rate (option 2 — a re-scoping decision with its own
# evidence bar, see .claude/rules/hook-block-vs-nudge.md). This control goes red
# if a future change silently narrows PATTERN_FUTURE / PATTERN_MARKER.
echo ""
echo "matcher stays unnarrowed (#2574 control):"
assert_blocks "measured render extrapolation still blocks" \
    "Roughly 70–80 minutes for 3870 frames at a measured 1.0 s/frame."

# ── match scope: the main agent's own trailing text (issue #2650) ─────────────
# The reported symptom was a block on "Seed hunt at 4 of 32." — a message with
# no duration in it at all. Two ways text outside that message reached the
# matcher: a subagent turn appended to the same transcript, and an earlier text
# block of the same entry (before a tool call). Both must stop firing; both
# fail-open paths (no isSidechain field, no tool_use) must keep firing, or the
# narrowing has quietly disabled the hook.
echo ""
echo "match is scoped to the agent's own trailing text (#2650):"

t="$TMPDIR/transcript-sidechain.jsonl"
make_transcript_sidechain "Seed hunt at 4 of 32." \
    "The remaining renders should take roughly 20 minutes." "$t"
assert_allows_file "subagent estimate after an estimate-free main message" "$t"

t="$TMPDIR/transcript-sidechain-blocks.jsonl"
make_transcript_sidechain "This will take 3 hours to finish." \
    "Cleaned up the scratch files." "$t"
assert_blocks_file "main-agent estimate still blocks when a subagent turn follows" "$t"

t="$TMPDIR/transcript-blocks-pre.jsonl"
make_transcript_blocks "34 renders, roughly 35 minutes." "Seed hunt at 4 of 32." "$t"
assert_allows_file "pre-tool-call estimate with an estimate-free closing block" "$t"

t="$TMPDIR/transcript-blocks-post.jsonl"
make_transcript_blocks "Seed hunt at 4 of 32." "This will take 3 hours to finish." "$t"
assert_blocks_file "estimate in the closing block of a multi-block entry still blocks" "$t"

# Fail-open control: a transcript carrying no isSidechain field anywhere and no
# tool_use in its content array must behave exactly as before the narrowing.
t="$TMPDIR/transcript-failopen.jsonl"
make_transcript "This will take 3 hours to finish." "$t"
assert_blocks_file "no isSidechain field and no tool_use — unchanged behaviour" "$t"

# ── past-tense and observational mentions SHOULD pass ─────────────────────────
echo ""
echo "past-tense and observational mentions pass:"
assert_allows "past-tense took"                     "The migration took 2 hours to finish."
assert_allows "modified N days ago"                 "The file was modified 2 days ago."
assert_allows "frequency (every N hours)"           "The cron job runs every 3 hours."
assert_allows "config timeout in seconds"           "The API timeout is 30 seconds."
assert_allows "ran for N minutes"                   "The build ran for 5 minutes before failing."

# ── currency rates and non-adjacent day counts SHOULD pass (issue #2654) ──────
# Reported from a cost-analysis session: three blocks, none of which contained a
# work estimate. Every match paired a money figure (or a count of calendar days)
# with a time unit several words away, and neither remediation branch — effort
# units or rate × quantity — had anything to say about a euro figure per year.
# The narrowing is purely syntactic (word-bounded unit + number adjacency), so
# the #2574 control above must stay green alongside these.
echo ""
echo "currency rates and non-adjacent day counts pass (#2654):"
assert_allows "currency rate per year"              "The saving is roughly €20 a year."
assert_allows "currency range per year"             "The saving is roughly €15–35 a year."
assert_allows "currency rate per hour"              "Contractors are roughly \$50 per hour."
assert_allows "day count, unit not adjacent"        "Holiday scaling would take 16 weekdays off a year."

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
for token in "tokens" "effort tier" "xhigh" "tool-call count"; do
    if echo "$out" | grep -q "$token"; then
        printf "  PASS: reason mentions '%s'\n" "$token"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: reason missing '%s' (output: %s)\n" "$token" "$out"
        FAIL=$((FAIL + 1))
    fi
done

# Regression: the reason must NOT ask the model to compute or state a
# remaining-context figure — that is exactly the countdown signal that
# invites context anxiety (see hooks-plugin/README.md's "Behavior Fit"
# section for this hook).
if echo "$out" | grep -q "context-window"; then
    printf "  FAIL: reason still asks for a remaining-context figure\n"
    FAIL=$((FAIL + 1))
else
    printf "  PASS: reason does not ask for a remaining-context figure\n"
    PASS=$((PASS + 1))
fi

# Regression (#2574): the offered units could not express external machine work
# the agent *measured* rather than *paced* — a render, CI run, build, model
# download, or long test suite. The reason must name that case and say how to
# phrase it (rate x quantity, measurement named), or the block is a dead end.
echo ""
echo "block reason names the external-machine-work case (#2574):"
for token in "external" "measured" "rate" "render" "CI run"; do
    if echo "$out" | grep -q "$token"; then
        printf "  PASS: reason mentions '%s'\n" "$token"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: reason missing '%s' (output: %s)\n" "$token" "$out"
        FAIL=$((FAIL + 1))
    fi
done

# The emitted block must stay valid JSON even though the reason carries an
# em-dash, parentheses, quotes and a multiplication sign.
if echo "$out" | jq -e '.decision == "block" and (.reason | length > 0)' >/dev/null 2>&1; then
    printf "  PASS: emitted block parses as valid JSON\n"
    PASS=$((PASS + 1))
else
    printf "  FAIL: emitted block is not valid JSON (output: %s)\n" "$out"
    FAIL=$((FAIL + 1))
fi

# ── reason branches on a measured rate (issue #2650) ──────────────────────────
# "Restate as tokens / effort tier" cannot express a render queue. When the
# blocked text names a measured rate, the message must LEAD with rate x quantity
# instead of the effort-unit list. The block itself is unchanged — this selects
# which remediation ships, it does not narrow the matcher (#2574 control above).
echo ""
echo "reason branches on a measured rate (#2650):"

t="$TMPDIR/transcript-measured.jsonl"
make_transcript "34 GPU renders at a measured 81 s/render, so roughly 35 minutes." "$t"
measured_out=$(run_hook_output "$t")

if echo "$measured_out" | grep -q '"decision": "block"'; then
    printf "  PASS: measured-rate estimate still blocks\n"
    PASS=$((PASS + 1))
else
    printf "  FAIL: measured-rate estimate no longer blocks (output: %s)\n" "$measured_out"
    FAIL=$((FAIL + 1))
fi

for token in "measured rate" "rate × quantity" "external machine work"; do
    if echo "$measured_out" | grep -qF "$token"; then
        printf "  PASS: measured-rate reason mentions '%s'\n" "$token"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: measured-rate reason missing '%s' (output: %s)\n" "$token" "$measured_out"
        FAIL=$((FAIL + 1))
    fi
done

# The units that cannot express a render queue must not lead the message.
for token in "effort tier" "xhigh"; do
    if echo "$measured_out" | grep -qF "$token"; then
        printf "  FAIL: measured-rate reason still offers '%s' (output: %s)\n" "$token" "$measured_out"
        FAIL=$((FAIL + 1))
    else
        printf "  PASS: measured-rate reason drops '%s'\n" "$token"
        PASS=$((PASS + 1))
    fi
done

# The generic branch must be unreachable-by-accident: an estimate with no
# measured rate keeps the original effort-unit message verbatim.
t="$TMPDIR/transcript-generic.jsonl"
make_transcript "Would take about 3 hours" "$t"
generic_out=$(run_hook_output "$t")
if echo "$generic_out" | grep -qF "effort tier" && ! echo "$generic_out" | grep -qF "That names a measured rate"; then
    printf "  PASS: estimate without a measured rate keeps the generic effort-unit reason\n"
    PASS=$((PASS + 1))
else
    printf "  FAIL: generic estimate got the machine-work reason (output: %s)\n" "$generic_out"
    FAIL=$((FAIL + 1))
fi

if echo "$measured_out" | jq -e '.decision == "block" and (.reason | length > 0)' >/dev/null 2>&1; then
    printf "  PASS: measured-rate block parses as valid JSON\n"
    PASS=$((PASS + 1))
else
    printf "  FAIL: measured-rate block is not valid JSON (output: %s)\n" "$measured_out"
    FAIL=$((FAIL + 1))
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────"
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
