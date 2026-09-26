#!/usr/bin/env bash
# Regression tests for workflow-scale-guard.sh and its count-or-ask estimator.
#
# The rule under test (workflow-scale-estimate.py docstring): a site is counted
# only when every construct around it is bounded by a literal; anything else is
# UNBOUNDED and asks. Each row below is one shape of that rule:
#
#   silent  a counted script within the limit — the contract that keeps the
#           guard from being disabled (a guard that asks on everything is noise)
#   ask     an unbounded site, a counted total over the limit, or a parse error
#
# Plus the structural guards (resume, other tool, saved-by-name, opt-out, limit
# override), the no-node fallback to the pre-parser estimator, and the shape of
# the ask payload.
#
# Run: bash hooks-plugin/hooks/test-workflow-scale-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/workflow-scale-guard.sh"
ESTIMATOR="$(dirname "$HOOK")/workflow-scale-estimate.py"
PASS=0
FAIL=0

# Explicitly unset the tunables: a developer shell that exports them would make
# this suite pass locally and fail in clean CI (or the reverse).
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

decision_of() {
    printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null
}

ok() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

# t <silent|ask> <description> <script> [env assignments…]
t() {
    local want="$1" desc="$2" script="$3" out got
    shift 3
    out=$(run_hook "$(payload_for "$script")" "$@")
    got=$(decision_of "$out")
    [ -n "$out" ] || got=silent
    if [ "$got" = "$want" ]; then ok "$want: $desc"; else bad "expected $want, got ${got:-<malformed>}: $desc"; fi
}

# est <KEY> <expected> <description> <script> — assert one rollup field.
est() {
    local key="$1" want="$2" desc="$3" script="$4" got
    got=$(printf '%s' "$script" | python3 "$ESTIMATOR" 10 | grep -m1 "^$key=" | cut -d= -f2-)
    if [ "$got" = "$want" ]; then ok "$key=$want: $desc"; else bad "expected $key=$want, got '$got': $desc"; fi
}

echo "== counted and within the limit: silent =="
t silent "three plain agent calls"            'await agent(1); await agent(2); await agent(3)'
t silent "fan-out over an array literal"      'await parallel([1, 2, 3].map(x => () => agent(x)))'
t silent "runtime list capped by .slice(0, 5)" 'await parallel(args.units.slice(0, 5).map(u => () => agent(u)))'
t silent "classic counted for"                'for (let i = 0; i < 4; i++) await agent(i)'
t silent "nested product 2 x 3"               'for (const a of [1, 2]) for (const b of ["x", "y", "z"]) await agent(a + b)'
t silent "parallel of literal thunks"         'await parallel([() => agent(1), async () => { await agent(2) }])'
t silent "pipeline over a literal, 2 stages"  'await pipeline(["a", "b"], x => agent(x), async y => agent(y))'
t silent "forEach and flatMap over literals"  '[1, 2].forEach(x => agent(x)); [3].flatMap(y => [agent(y)])'
t silent "counted loop writing another name"  'const r = []; for (let i = 0; i < 3; i += 1) { r[i] = await agent(i) }'
t silent "no agent() calls at all"            'export const meta = { name: "noop" }; return { ok: true }'
# shellcheck disable=SC2016  # the ${x} below is JS fixture text, not shell
t silent "agent( only in strings and comments" '// items.map(x => agent(x))
const p = "call agent( for each of 200 items"; const q = `agent( ${x}`
await agent(p)'

echo
echo "== unbounded: ask =="
t ask "one agent per runtime item"            'await parallel(changedFiles.map(f => () => agent(f)))'
t ask "const holding a literal (can be pushed)" 'const DIMS = [1, 2]; await parallel(DIMS.map(d => () => agent(d)))'
t ask "single-argument .slice(0) copy"        'await pipeline(args.units.slice(0), u => agent(u))'
t ask "for over a runtime .length"            'for (let i = 0; i < xs.length; i++) await agent(xs[i])'
t ask "counted for whose body writes i"       'for (let i = 0; i < 3; i++) { await agent(i); i-- }'
t ask "while loop"                            'let n = 0; while (n < 3) { await agent(n); n++ }'
t ask "do...while loop"                       'do { await agent(1) } while (again())'
t ask "for...in loop"                         'for (const k in obj) await agent(k)'
t ask "site in a named function"              'async function run() { return agent(1) } await run()'
t ask "site in a function value"              'const run = () => agent(1); await run()'
t ask "site in a class method"                'class A { go() { return agent(1) } } await new A().go()'
t ask "recursion"                             'async function rec(d) { await agent(d); if (d) await rec(d - 1) } await rec(3)'
t ask "thunks built outside parallel()"       'const th = [1, 2].map(x => () => agent(x)); await parallel(th)'
t ask "workflow() child"                      'await workflow("review", { x: 1 })'
t ask "nested runtime fan-out"                'await pipeline(gaps, g => agent(g), r => parallel(r.findings.map(f => () => agent(f))))'
t ask "script that does not parse"            'await agent(1'

echo
echo "== counted but over the limit: ask =="
t ask "counted for of 11"                     'for (let i = 0; i < 11; i++) await agent(i)'
t ask "nested product 3 x 4 = 12"             'for (const a of [1, 2, 3]) await parallel([1, 2, 3, 4].map(b => () => agent(a, b)))'
t ask "inclusive bound 0..10 = 11"            'for (let i = 0; i <= 10; i++) await agent(i)'
t silent "limit raised above the count"       'for (let i = 0; i < 11; i++) await agent(i)' CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=20

echo
echo "== rollup fields =="
est ESTIMATE 6   "nested product counted exactly"   'for (const a of [1, 2]) for (const b of [1, 2, 3]) await agent(a)'
est ESTIMATE 7   "step 3 over 0..20 is 7 passes"    'for (let i = 0; i < 20; i += 3) await agent(i)'
est ESTIMATE 2   "counted sites summed beside an unbounded one" 'await agent(1); await agent(2); await parallel(xs.map(x => () => agent(x)))'
est UNBOUNDED 1  "one unbounded site"               'await agent(1); await parallel(xs.map(x => () => agent(x)))'
est VERDICT PARSE_ERROR "syntax error is not a fallback" 'await agent(1'
est PARSER acorn "the parser ran"                   'await agent(1)'

echo
echo "== structural guards: silent =="
assert_silent_payload() {
    local desc="$1" payload="$2" out
    shift 2
    out=$(run_hook "$payload" "$@")
    if [ -z "$out" ]; then ok "silent: $desc"; else bad "expected silence: $desc"; fi
}
UNBOUNDED_SCRIPT='await parallel(xs.map(x => () => agent(x)))'
assert_silent_payload "resume of an earlier run" \
    "$(jq -nc --arg s "$UNBOUNDED_SCRIPT" '{tool_name:"Workflow", tool_input:{resumeFromRunId:"wf_abc123def", script:$s}}')"
assert_silent_payload "a different tool" "$(jq -nc '{tool_name:"Bash", tool_input:{command:"ls"}}')"
assert_silent_payload "saved workflow referenced by name" "$(jq -nc '{tool_name:"Workflow", tool_input:{name:"review-changes"}}')"
assert_silent_payload "opt-out env var set" "$(payload_for "$UNBOUNDED_SCRIPT")" CLAUDE_HOOKS_DISABLE_WORKFLOW_SCALE_GUARD=1

echo
echo "== no node on PATH: main's pre-parser estimator decides =="
# A PATH holding only the tools the guard needs, so `node` is provably absent.
BIN=$(mktemp -d)
trap 'rm -rf "$BIN"' EXIT
ln -s "$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))')" "$BIN/python3"
for tool in bash jq cat grep head cut dirname; do ln -s "$(command -v "$tool")" "$BIN/$tool"; done
if PATH="$BIN" command -v node >/dev/null 2>&1; then bad "fixture PATH still resolves node"; fi
FB=$(printf '%s' 'await agent(1)' | PATH="$BIN" python3 "$ESTIMATOR" 10)
if grep -qx 'PARSER=fallback' <<<"$FB" && grep -qx 'FALLBACK=node not on PATH' <<<"$FB"; then
    ok "estimator reports PARSER=fallback without node"
else
    bad "estimator without node: $FB"
fi
# Main's behaviour: one agent per runtime item costs 1 x 8 (silent); two per
# item cost 16 (ask). The same one-per-item script asks under the parser.
t silent "fallback: one agent per runtime item" "$UNBOUNDED_SCRIPT" PATH="$BIN"
t ask "fallback: two agents per runtime item" 'await pipeline(args.units, a => agent(a), b => agent(b))' PATH="$BIN"
t ask "parser: one agent per runtime item" "$UNBOUNDED_SCRIPT"

echo
echo "== the ask payload names the lines and the remedy =="
OUT=$(run_hook "$(payload_for 'export const meta = { name: "named-check" }
await agent(0)
await parallel(args.units.map(u => () => agent(u)))')")
REASON=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
# shellcheck disable=SC2016  # literal backticks in the expected reason text
for needle in 'workflow:  named-check' 'line 3: parallel over `args.units`' 'the counted ones spawn 1' '.slice(0, 6)'; do
    if grep -qF "$needle" <<<"$REASON"; then ok "reason contains: $needle"; else bad "reason lacks '$needle': $REASON"; fi
done
OUT=$(run_hook "$(payload_for 'for (let i = 0; i < 12; i++) await agent(i)')")
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse" and (.hookSpecificOutput.permissionDecisionReason | test("spawn about 12 agents, over the limit of 10"))' >/dev/null; then
    ok "over-limit reason states the count and the limit"
else
    bad "over-limit payload: $OUT"
fi

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
