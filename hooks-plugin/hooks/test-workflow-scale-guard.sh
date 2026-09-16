#!/usr/bin/env bash
# Regression tests for workflow-scale-guard.sh and its estimator.
#
# Verifies that the PreToolUse hook:
#  - Asks for confirmation when a script's estimated agent count exceeds the
#    limit, including the shapes taken from the real 496-agent session.
#  - Stays SILENT on everything else. The negative cases carry the weight here:
#    a guard that asks on ordinary workflows gets disabled within a day, so the
#    small/bounded/capped/one-agent-per-item cases are the real contract.
#  - Honors the opt-out, ignores resumes and non-Workflow tools, and fails open
#    when there is no script text to read.
#
# Run: bash hooks-plugin/hooks/test-workflow-scale-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

HOOK="$(dirname "$0")/workflow-scale-guard.sh"
PASS=0
FAIL=0

# Explicitly unset the tunables: a developer shell that exports them would make
# this suite pass locally and fail in clean CI (or worse, the reverse).
run_hook() {
    local payload="$1"
    shift
    printf '%s' "$payload" | env \
        -u CLAUDE_HOOKS_DISABLE_WORKFLOW_SCALE_GUARD \
        -u CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS \
        -u CLAUDE_HOOKS_WORKFLOW_ASSUMED_WIDTH \
        "$@" bash "$HOOK" 2>/dev/null || true
}

payload_for() {
    jq -nc --arg s "$1" '{tool_name:"Workflow", tool_input:{script:$s}}'
}

assert_asks() {
    local desc="$1" script="$2"
    local out decision
    out=$(run_hook "$(payload_for "$script")")
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
    if [ "$decision" = "ask" ]; then
        PASS=$((PASS + 1))
        printf '  PASS  asks: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  expected ask, got "%s": %s\n' "${decision:-<silent>}" "$desc"
    fi
}

assert_silent() {
    local desc="$1" script="$2"
    local out
    out=$(run_hook "$(payload_for "$script")")
    if [ -z "$out" ]; then
        PASS=$((PASS + 1))
        printf '  PASS  silent: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  expected silence, got output: %s\n' "$desc"
    fi
}

assert_silent_payload() {
    local desc="$1" payload="$2"
    shift 2
    local out
    out=$(run_hook "$payload" "$@")
    if [ -z "$out" ]; then
        PASS=$((PASS + 1))
        printf '  PASS  silent: %s\n' "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  expected silence, got output: %s\n' "$desc"
    fi
}

echo "== over the limit: must ask =="

# The shape that actually ran: four agent() sites inside one pipeline over a
# runtime-length list. "Flat" fan-out, but 4 agents per item.
assert_asks "4 sites over a runtime list (the real patch-batch shape)" '
export const meta = { name: "patch-batch", description: "x", phases: [] }
const out = await pipeline(args.units,
  u => agent("edit", { label: "edit" }),
  e => agent("review", { label: "review" }),
  async st => {
    const repair = await agent("repair", { label: "repair" })
    return agent("rereview", { label: "rereview" })
  })
'

assert_asks "bounded literal array of 20" '
const DIMS = [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20]
await parallel(DIMS.map(d => () => agent("go", { label: "d" })))
'

assert_asks "unbounded fan-out nested inside another fan-out" '
await pipeline(gaps,
  g => agent("audit", { label: "a" }),
  review => parallel(review.findings.map(f => () => agent("verify", { label: "v" }))))
'

assert_asks "slice(0) array copy over a runtime list still asks" '
await pipeline(args.units.slice(0),
  u => agent("edit", { label: "edit" }),
  e => agent("review", { label: "review" }))
'

assert_asks "pipeline over mapped runtime list asks" '
await pipeline(args.units.map(u => ({id: u.id})),
  u => agent("edit", { label: "edit" }),
  e => agent("review", { label: "review" }))
'

echo
echo "== within the limit: must stay silent =="

assert_silent "three plain agent calls, no fan-out" '
const a = await agent("one", { label: "1" })
const b = await agent("two", { label: "2" })
const c = await agent("three", { label: "3" })
'

assert_silent "explicit .slice(0, 5) cap — the remedy the message names" '
await parallel(args.units.slice(0, 5).map(u => () => agent("go", { label: "u" })))
'

assert_silent "pipeline over capped .slice(0, 3).map list stays silent" '
await pipeline(args.units.slice(0, 3).map(u => ({id: u.id})),
  u => agent("edit", { label: "edit" }),
  e => agent("review", { label: "review" }))
'

assert_silent "one agent per runtime item (the common legitimate shape)" '
await parallel(changedFiles.map(f => () => agent("review", { label: "f" })))
'

assert_silent "bounded literal array of 4 with one site" '
const DIMS = [{k:"a"},{k:"b"},{k:"c"},{k:"d"}]
await parallel(DIMS.map(d => () => agent("go", { label: "d" })))
'

assert_silent "no agent() calls at all" '
export const meta = { name: "noop", description: "x", phases: [] }
return { ok: true }
'

# The estimator blanks string and comment bodies before counting. Without that,
# a prompt that discusses agent() — or a commented-out fan-out — would be read
# as live code and every workflow with documentation would ask.
# shellcheck disable=SC2016  # the ${x} below is JS fixture text, not shell
assert_silent "agent( appears only inside strings and comments" '
// const big = xs.map(x => agent("nope"))
const prompt = "call agent( repeatedly for each of the 200 items"
const t = `also agent( inside a template ${x}`
await agent("real", { label: "only-one" })
'

echo
echo "== structural guards: must stay silent =="

assert_silent_payload "resume of an earlier run" \
    "$(jq -nc '{tool_name:"Workflow", tool_input:{resumeFromRunId:"wf_abc123def", script:"await parallel(xs.map(x => () => agent(1)))\nawait parallel(ys.map(y => () => agent(2)))"}}')"

assert_silent_payload "a different tool" \
    "$(jq -nc '{tool_name:"Bash", tool_input:{command:"ls"}}')"

assert_silent_payload "saved workflow referenced by name (no script text)" \
    "$(jq -nc '{tool_name:"Workflow", tool_input:{name:"review-changes"}}')"

assert_silent_payload "opt-out env var set" \
    "$(payload_for 'await pipeline(args.units, a => agent(1), b => agent(2), c => agent(3), d => agent(4))')" \
    CLAUDE_HOOKS_DISABLE_WORKFLOW_SCALE_GUARD=1

assert_silent_payload "limit raised above the estimate" \
    "$(payload_for 'await pipeline(args.units, a => agent(1), b => agent(2), c => agent(3), d => agent(4))')" \
    CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=100

echo
echo "== the ask payload is well-formed =="
OUT=$(run_hook "$(payload_for 'export const meta = { name: "named-check" }
await pipeline(args.units, a => agent(1), b => agent(2), c => agent(3), d => agent(4))')")
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
   && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("workflow:[[:space:]]+named-check")' >/dev/null 2>&1 \
   && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("~32 agents")' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  PASS  reason names the estimate, workflow name, and the event\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  malformed ask payload: %s\n' "$OUT"
fi

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
