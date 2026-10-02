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
# override), the no-node fallback to the pre-parser estimator, a node whose
# parser crashes or times out (asks; a cold first call is retried), a script
# file that is not UTF-8, a stdout that is not UTF-8, an estimator that stops
# without a verdict (asks), and the shape of the ask payload.
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
t silent "agent as an object key"            'const o = { agent: 1, workflow: 2 }; await agent(o)'
t silent "agent.call counted like agent()"    'for (let i = 0; i < 3; i++) await agent.call(null, i)'
t silent "property call counted like agent()" 'for (const x of [1, 2]) await globalThis.agent(x); await ctx["agent"](3)'
t silent "unnamed function callback inlined"  '[1, 2].forEach(function (d) { agent(d) })'
t silent "slice inline in the fan-out"        'for (const x of args.items.slice(0, 6)) await agent(x)'
t silent "destructured agent, counted calls"  'const { agent } = ctx; for (const x of [1, 2]) await agent(x)'
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
t ask "inner for-of reassigns the counter"    'for (let i = 0; i < 3; i++) { await agent(i); for (i of [0]) {} }'
t ask "var counter reset from outside"        'function reset() { i = 0 }
for (var i = 0; i < 3; i++) { await agent(i); reset() }'
t ask "agent.call over a runtime list"        'for (const x of args.xs) await agent.call(null, x)'
t ask "agent aliased then called"             'const a = agent; for (const x of args.xs) await a(x)'
t ask "agent passed as a callback"            'await Promise.all(args.xs.map(agent))'
t ask "agent aliased by destructuring"        'const { agent: a } = { agent }; for (const x of args.xs) await a(x)'
# PR #2831 review: named function expressions inlined as callbacks (can recurse).
t ask "named function expression in forEach"  '[1].forEach(function f(d) { agent(d); if (d < 50) f(d + 1) })'
t ask "named thunk in parallel([...])"         'await parallel([function f() { agent(1); return f() }])'
t ask "named pipeline stage"                  'await pipeline([1], function f(x) { agent(x); if (x) f(x - 1) })'
t ask "named thunk returned by a map callback" 'await parallel([1].map(x => function g() { agent(x); return g() }))'
# PR #2831 review: a capped copy held in a variable is not resolved.
t ask "slice held in a const"                 'const items = args.items.slice(0, 6); for (const x of items) await agent(x)'
# PR #2831 review: agent reached as a property, or renamed by destructuring.
t ask "property call in a while loop"         'while (true) await globalThis.agent("x")'
t ask "property call over a runtime list"     'for (const x of args.xs) await ctx.agent(x)'
t ask "workflow() reached as a property"      'await globalThis.workflow("review")'
t ask "property read as a value"              'const spawn = globalThis.agent; await spawn(1)'
t ask "object key read back as a value"       'const o = { agent: 1 }; await agent(o.agent)'
t ask "rename by destructuring, no other use" 'const { agent: spawn } = globalThis; await spawn(1)'
t ask "rename in a parameter pattern"         'export default async function ({ agent: spawn }) { await spawn(1) }'
t ask "rename in an assignment pattern"       'let spawn; ({ agent: spawn } = globalThis); await spawn(1)'
# PR #2831 review: sites the walker used to skip.
t ask "for-of left-side default"              'for (const { a = agent(1) } of args.xs) {}'
t ask "map-callback default under parallel()" 'await parallel(args.xs.map((x, y = agent(x)) => () => y))'
# A deeply nested expression parses but exceeds the walker's recursion limit.
DEEP="const P = $(python3 -c "print(' + '.join(\"'l%d'\" % k for k in range(4000)))")
await agent(P)"
t ask "estimator error on a parsed script"    "$DEEP"
est VERDICT ANALYSIS_ERROR "walker failure asks, not the lenient fallback" "$DEEP"

echo
echo "== counted but over the limit: ask =="
t ask "counted for of 11"                     'for (let i = 0; i < 11; i++) await agent(i)'
t ask "nested product 3 x 4 = 12"             'for (const a of [1, 2, 3]) await parallel([1, 2, 3, 4].map(b => () => agent(a, b)))'
t ask "inclusive bound 0..10 = 11"            'for (let i = 0; i <= 10; i++) await agent(i)'
t silent "limit raised above the count"       'for (let i = 0; i < 11; i++) await agent(i)' CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=20
# The guard's reading of CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS, as docs/feature-flags.md
# states it (the subagent-count tripwire reads the same variable differently).
t silent "a total equal to the limit"         'for (let i = 0; i < 10; i++) await agent(i)'
t ask "limit 0 asks on one counted agent"     'await agent(1)' CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=0
t silent "a non-numeric limit means 10"       'for (let i = 0; i < 10; i++) await agent(i)' CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS=ten

echo
echo "== rollup fields =="
est ESTIMATE 6   "nested product counted exactly"   'for (const a of [1, 2]) for (const b of [1, 2, 3]) await agent(a)'
est ESTIMATE 7   "step 3 over 0..20 is 7 passes"    'for (let i = 0; i < 20; i += 3) await agent(i)'
est ESTIMATE 2   "counted sites summed beside an unbounded one" 'await agent(1); await agent(2); await parallel(xs.map(x => () => agent(x)))'
est UNBOUNDED 1  "one unbounded site"               'await agent(1); await parallel(xs.map(x => () => agent(x)))'
est SITES 1      "destructured agent parameter is a declaration, not a use" 'export default async function ({ agent, parallel }) { await agent(1) }'
est ESTIMATE 2   "parameter default is ordinary code" 'await agent(0); [1].forEach((x, y = agent(x)) => y)'
est ESTIMATE 2   "for-of left-side default counted per item" 'for (const { a = agent(1) } of [1, 2]) {}'
est ESTIMATE 2   "map-callback default under parallel() counted" 'await parallel([1, 2].map((x, y = agent(x)) => () => y))'
est SITES 1      "rename recorded as its own site"  'const { agent: spawn } = globalThis; await spawn(1)'
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
echo "== node present but the parser fails: ask, never the lenient fallback (PR #2831 review) =="
# Stub `node`s placed first on PATH. `exec sleep` so the parser's timeout kills
# the sleeper itself (a forked sleep would hold the output pipe open).
REAL_NODE=$(command -v node)
STUBS=$(mktemp -d)
if [ -z "$STUBS" ] || [ ! -d "$STUBS" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$BIN" "$STUBS"' EXIT
mkdir -p "$STUBS/crash" "$STUBS/hang" "$STUBS/cold"
printf '#!/usr/bin/env bash\nexit 3\n' > "$STUBS/crash/node"
printf '#!/usr/bin/env bash\nexec sleep 5\n' > "$STUBS/hang/node"
# Cold start: the first call hangs past the 4 s timeout, later calls run node.
printf '#!/usr/bin/env bash\nif [ ! -e "%s" ]; then : > "%s"; exec sleep 5; fi\nexec "%s" "$@"\n' \
    "$STUBS/cold/first" "$STUBS/cold/first" "$REAL_NODE" > "$STUBS/cold/node"
chmod +x "$STUBS/crash/node" "$STUBS/hang/node" "$STUBS/cold/node"
t ask "parser crashes: one agent per runtime item" "$UNBOUNDED_SCRIPT" PATH="$STUBS/crash:$PATH"
got=$(printf '%s' "$UNBOUNDED_SCRIPT" | PATH="$STUBS/crash:$PATH" python3 "$ESTIMATOR" 10 | grep -m1 '^VERDICT=')
if [ "$got" = "VERDICT=ANALYSIS_ERROR" ]; then ok "crashed parser is ANALYSIS_ERROR"; else bad "crashed parser: $got"; fi
t ask "parser times out twice: one agent per runtime item" "$UNBOUNDED_SCRIPT" PATH="$STUBS/hang:$PATH"
# A cold first call is retried: the ask is the UNBOUNDED one, naming the line.
OUT=$(run_hook "$(payload_for "$UNBOUNDED_SCRIPT")" PATH="$STUBS/cold:$PATH")
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' | grep -qF 'not counted: line 1'; then
    ok "cold first parse retried: the unbounded ask, not a parser error"
else
    bad "cold first parse: $OUT"
fi

echo
echo "== a scriptPath that is not UTF-8 is still parsed (PR #2831 review) =="
LATIN1="$STUBS/latin1.js"
printf 'await parallel(args.xs.map(x => () => agent(x))) // caf\351\n' > "$LATIN1"
assert_ask_payload() {
    local desc="$1" payload="$2" out
    out=$(run_hook "$payload")
    if [ "$(decision_of "$out")" = ask ]; then ok "ask: $desc"; else bad "expected ask: $desc"; fi
}
assert_ask_payload "Latin-1 byte in a scriptPath file" "$(jq -nc --arg p "$LATIN1" '{tool_name:"Workflow", tool_input:{scriptPath:$p}}')"
for lc in C C.UTF-8; do
    got=$(LC_ALL=$lc python3 "$ESTIMATOR" 10 < "$LATIN1" | grep -E '^(VERDICT|PARSER)=' | tr '\n' ' ')
    if [ "$got" = "VERDICT=UNBOUNDED PARSER=acorn " ]; then ok "Latin-1 byte parsed under LC_ALL=$lc"; else bad "Latin-1 byte under LC_ALL=$lc: $got"; fi
done

echo
echo "== a non-UTF-8 stdout cannot crash the estimator (PR #2831 review) =="
# Under PYTHONIOENCODING=latin-1 or ascii (or an ISO-8859 locale), print() raised
# on the U+FFFD of a replaced byte or the `…` of a clipped snippet in
# UNBOUNDED_AT, the estimator exited 1, and the guard passed the run silently.
# The rollup is now UTF-8 bytes whatever the locale.
LATIN1_AT="$STUBS/latin1-at.js"
printf 'for (const u of args["caf\351"]) { await agent(u); }\n' > "$LATIN1_AT"
FFFD=$(printf 'caf\357\277\275')
LONG='for (const u of args.aVeryLongPropertyNameThatRunsPastForty) await agent(u)'
for enc in latin-1 ascii; do
    t ask "clipped snippet under PYTHONIOENCODING=$enc" "$LONG" PYTHONIOENCODING=$enc
    OUT=$(run_hook "$(jq -nc --arg p "$LATIN1_AT" '{tool_name:"Workflow", tool_input:{scriptPath:$p}}')" PYTHONIOENCODING=$enc)
    REASON=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
    if LC_ALL=C grep -qF "not counted: line 1: for-of over \`args[\"$FFFD\"]\`" <<<"$REASON"; then
        ok "replaced byte named in the ask under PYTHONIOENCODING=$enc"
    else
        bad "replaced byte under PYTHONIOENCODING=$enc: $OUT"
    fi
    got=$(PYTHONIOENCODING=$enc python3 "$ESTIMATOR" 10 < "$LATIN1_AT" 2>/dev/null; echo "EXIT=$?")
    if LC_ALL=C grep -qF "UNBOUNDED_AT=line 1: for-of over \`args[\"$FFFD\"]\`" <<<"$got" && grep -qx 'EXIT=0' <<<"$got"; then
        ok "estimator writes UTF-8 and exits 0 under PYTHONIOENCODING=$enc"
    else
        bad "estimator under PYTHONIOENCODING=$enc: $got"
    fi
done

echo
echo "== an estimator that stops without a verdict asks (PR #2831 review) =="
# Main's guard exited 0 on any estimator failure (`|| exit 0`), which contradicts
# count-or-ask: nothing was counted. A stand-in plugin root holds the estimator.
FAKE="$STUBS/fake-root"
mkdir -p "$FAKE/hooks"
cp "$HOOK" "$FAKE/hooks/"
printf 'import sys\nsys.stdout.write("VERDICT=OK\\n")\nsys.stdout.flush()\nsys.exit(1)\n' > "$FAKE/hooks/workflow-scale-estimate.py"
t ask "estimator exits 1 after a partial VERDICT=OK" "$UNBOUNDED_SCRIPT" CLAUDE_PLUGIN_ROOT="$FAKE"
OUT=$(run_hook "$(payload_for "$UNBOUNDED_SCRIPT")" CLAUDE_PLUGIN_ROOT="$FAKE")
if printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' | grep -qF 'the estimator stopped without a verdict (exit 1)'; then
    ok "crash ask names the estimator's exit status"
else
    bad "crash ask payload: $OUT"
fi
printf 'pass\n' > "$FAKE/hooks/workflow-scale-estimate.py"
t ask "estimator exits 0 with no output" "$UNBOUNDED_SCRIPT" CLAUDE_PLUGIN_ROOT="$FAKE"

echo
echo "== the ask payload names the lines and the remedy =="
OUT=$(run_hook "$(payload_for 'export const meta = { name: "named-check" }
await agent(0)
await parallel(args.units.map(u => () => agent(u)))')")
REASON=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
# shellcheck disable=SC2016  # literal backticks in the expected reason text
for needle in 'workflow:  named-check' 'line 3: parallel over `args.units`' 'the counted ones spawn 1' 'for (const x of items.slice(0, 6))' 'capped copy held in a variable still asks'; do
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
