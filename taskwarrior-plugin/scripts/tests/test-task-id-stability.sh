#!/usr/bin/env bash
# test-task-id-stability.sh — semantic regression test for the "resolve UUID
# once, mutate by UUID" pattern in task-claim / task-release / task-done
# (.claude/rules/task-id-stability.md).
#
# The pattern these three skills follow: load the task once (capturing both
# the numeric id and the uuid), then issue several LATER, separately-invoked
# `task` mutating commands over the following steps — with a real gap between
# resolve and mutate (an AskUserQuestion pause in task-release, a
# SlashCommand coworker-check in task-claim). If another agent's concurrent
# `task done` renumbers ids in that window, a later step addressed by the
# stale numeric id silently mutates the WRONG task. No error surfaces — this
# is the shape of the live incident that prompted this rule ("closed the
# wrong task — 282 now points to a gitops task").
#
# This test does two things a bare grep for the literal string "TASK_UUID"
# cannot (regression-testing.md's syntactic-vs-semantic gate — a plain
# substring check would still pass on a PARTIAL conversion where only one of
# several mutating calls in a skill was switched to UUID):
#
#   1. EXECUTES the underlying taskwarrior behavior against a scratch store to
#      prove numeric-ID addressing breaks under renumbering while UUID
#      addressing does not.
#   2. Greps each SKILL.md for the SPECIFIC mutating command lines (start,
#      modify, annotate, done, stop, depends: query) and asserts each one
#      uses $TASK_UUID, and that none of them still use the stale $TASKID —
#      catching a conversion that only fixed some of a skill's mutating calls.
#
# Requires the real `task` CLI; SKIPs cleanly when taskwarrior is unavailable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CLAIM_SKILL="${PLUGIN_DIR}/skills/task-claim/SKILL.md"
RELEASE_SKILL="${PLUGIN_DIR}/skills/task-release/SKILL.md"
DONE_SKILL="${PLUGIN_DIR}/skills/task-done/SKILL.md"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

if ! command -v task >/dev/null 2>&1; then
    echo "SKIP: task CLI not available" >&2
    exit 0
fi

# --- Part 1: behavioral proof (real taskwarrior store) ----------------------
#
# Create three tasks. T2 is the one a skill "claims" — capture its numeric id
# and uuid at read time. Then complete T1 (a LOWER numeric id), which shifts
# every higher id down by one: T2's old id now addresses T3, and T3's old id
# now addresses nothing. This reproduces the renumbering gap.

SCRATCH="$(mktemp -d)"
[ -n "$SCRATCH" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT
export TASKDATA="$SCRATCH" TASKRC="${SCRATCH}/.taskrc"
printf 'data.location=%s\n' "$SCRATCH" > "$TASKRC"

task rc.confirmation=no add "T1 first task" </dev/null >/dev/null 2>&1
task rc.confirmation=no add "T2 the one we claim" </dev/null >/dev/null 2>&1
task rc.confirmation=no add "T3 third task" </dev/null >/dev/null 2>&1

# Resolve T2 at read time (mirrors task-claim/task-release/task-done Step 1/2).
id_a="$(task status:pending export 2>/dev/null | jq -r '.[] | select(.description == "T2 the one we claim") | .id')"
uuid_a="$(task status:pending export 2>/dev/null | jq -r '.[] | select(.description == "T2 the one we claim") | .uuid')"

check "captured a numeric id for T2" "2" "$id_a"

# Simulate the gap: another agent completes T1 (a lower numeric id) while
# this skill is between its resolve step and its mutate step (the
# AskUserQuestion / SlashCommand window).
task rc.confirmation=no 1 "done" </dev/null >/dev/null 2>&1

# The stale numeric id now addresses a DIFFERENT task (T3, shifted down).
renumbered_desc="$(task "$id_a" export 2>/dev/null | jq -r '.[0].description // empty')"
check "stale numeric id now addresses a different task after the gap" \
    "T3 third task" "$renumbered_desc"

# The UUID still addresses the original task T2, unaffected by the gap.
uuid_desc="$(task "$uuid_a" export 2>/dev/null | jq -r '.[0].description // empty')"
check "UUID still addresses the original task after the gap" \
    "T2 the one we claim" "$uuid_desc"

# Prove the fix end-to-end: mutating by $TASK_UUID lands the annotation on
# T2, never on the task that now sits at the stale numeric id (T3).
task rc.confirmation=no "$uuid_a" annotate "resolved by uuid" </dev/null >/dev/null 2>&1

t2_annotated="$(task "$uuid_a" export 2>/dev/null | jq -r '.[0].annotations[0].description // empty')"
check "annotate-by-uuid lands on the originally-claimed task" \
    "resolved by uuid" "$t2_annotated"

t3_untouched="$(task "$id_a" export 2>/dev/null | jq -r '(.[0].annotations // []) | length')"
check "the task now sitting at the stale numeric id is untouched" "0" "$t3_untouched"

# --- Part 2: SKILL.md text — every mutating call uses $TASK_UUID -----------
#
# A bare grep for the substring "TASK_UUID" passes even when only ONE of
# several mutating calls was converted. Check each specific mutating command
# line individually, and assert the stale $TASKID form is gone from all of
# them (blockquote/prose mentions of $TASKID explaining the hazard are fine —
# only check the fenced command lines).

check_uuid_calls() { # check_uuid_calls <skill-label> <file> <verb...>
    local label="$1" file="$2"
    shift 2
    for verb in "$@"; do
        if grep -qE "task \"\\\$TASK_UUID\" ${verb}\\b" "$file"; then
            check "${label}: '${verb}' addressed by \$TASK_UUID" "present" "present"
        else
            check "${label}: '${verb}' addressed by \$TASK_UUID" "present" "absent"
        fi
        if grep -qE "task \"\\\$TASKID\" ${verb}\\b" "$file"; then
            check "${label}: '${verb}' no longer addressed by stale \$TASKID" "absent" "present"
        else
            check "${label}: '${verb}' no longer addressed by stale \$TASKID" "absent" "absent"
        fi
    done
}

check_uuid_calls "task-claim" "$CLAIM_SKILL" start modify annotate
check_uuid_calls "task-release" "$RELEASE_SKILL" annotate stop modify
check_uuid_calls "task-done" "$DONE_SKILL" annotate "done" modify

# task-done's Step 6 unblocked-siblings read query — the adversarial-review
# catch: this runs AFTER `task done`, when the closed task's own numeric id
# has already been freed/reassigned, so it must use $TASK_UUID too.
if grep -qE "task depends:\"\\\$TASK_UUID\"" "$DONE_SKILL"; then
    check "task-done: post-close depends: query uses \$TASK_UUID" "present" "present"
else
    check "task-done: post-close depends: query uses \$TASK_UUID" "present" "absent"
fi

# --- Part 3: citation-drift guard -------------------------------------------
#
# .claude/rules/taskwarrior-bulk-operations.md never existed on disk, yet was
# cited by name in 4 places across the repo (task-reconcile/REFERENCE.md,
# release-stale-claims.sh x2, task-add/SKILL.md) — a broken cross-reference,
# fixed to point at .claude/rules/task-id-stability.md instead. Assert the
# stale filename does not reappear anywhere in the repo, not just in the
# skill bodies plugin-compliance-check.sh's check_skill_body() scans (that
# function only walks SKILL.md; the broken citations also lived in
# REFERENCE.md and a .sh script). Excludes this test file and
# regression-testing.md's own Known Regressions row, both of which cite the
# stale filename deliberately as historical record, not as a live reference.

repo_root="$(cd "${PLUGIN_DIR}/.." && pwd)"
self_path="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
regression_log="${repo_root}/.claude/rules/regression-testing.md"
stale_hits="$(grep -rl "taskwarrior-bulk-operations" "$repo_root" \
    --include='*.md' --include='*.sh' 2>/dev/null \
    | grep -v '/\.git/' | grep -vF "$self_path" | grep -vF "$regression_log" || true)"
if [ -z "$stale_hits" ]; then
    check "no stale 'taskwarrior-bulk-operations.md' citations remain" "absent" "absent"
else
    check "no stale 'taskwarrior-bulk-operations.md' citations remain" "absent" "present: ${stale_hits//$'\n'/, }"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
