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
#  - Costs every fixture at or above its TRUE count, measured by running it in
#    node with a counting agent() (fixtures/workflow-scale/truecount.mjs), and
#    never below the frozen #2668 estimator where #2668 asks except at a
#    listed, measured correct count.
#  - Falls back to the #2668 estimator, figure for figure, when the JavaScript
#    parse cannot run.
#
# Needs node on PATH: the estimator parses with it, and the ground truth runs
# in it. Without node the suite fails rather than testing only the fallback.
#
# Run: bash hooks-plugin/hooks/test-workflow-scale-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

if ! command -v node >/dev/null 2>&1; then
    echo "FATAL: node is not on PATH; this suite measures the parse and the ground truth with it" >&2
    exit 1
fi

# The differential below asks git for the bundled templates. Under a git
# commit hook, GIT_DIR/GIT_INDEX_FILE are exported and override `git -C`, so
# --show-toplevel resolves to the cwd instead of the repo (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

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
echo "== estimator arithmetic (#2670): the figure the guard shows is the figure paid =="

# The estimate is the agent count a template author states and the ask names, so
# an arithmetic error is a wrong cost statement, not just a wrong verdict. These
# assert the ESTIMATE= number itself, straight from the estimator. Before #2670
# the literal-array case costed blueprint-story-audit at 71 (true: 20) and
# verify-before-filing at 81 (true: 49), and the nested-template case hid a live
# agent() call in evaluate-skill. The trailing-comma case changes no shipped
# template's figure; it guards a .map over a declared array written in house style.
ESTIMATOR="$(dirname "$0")/workflow-scale-estimate.py"

estimate_of() {
    printf '%s\n' "$1" | python3 "$ESTIMATOR" 10 8 2>/dev/null
}

assert_estimate() {
    local desc="$1" want="$2" script="$3"
    local got
    got=$(estimate_of "$script" | sed -n 's/^ESTIMATE=//p')
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1))
        printf '  PASS  ESTIMATE=%s: %s\n' "$want" "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  expected ESTIMATE=%s, got "%s": %s\n' "$want" "${got:-<none>}" "$desc"
    fi
}

# parallel([thunkA, thunkB]) runs each thunk ONCE. A site inside one element of a
# literal array is not multiplied by the array's length.
assert_estimate "literal array of distinct thunks counts each once" 2 '
await parallel([() => agent("a", { label: "a" }), () => agent("b", { label: "b" })])
'

# A trailing comma is not an element. The fixture maps over a declared array
# because that is the path that reads the item count: a site inside a literal
# thunk array runs once and never consults the length, so a trailing comma
# there cannot change the figure and would pin nothing.
assert_estimate "trailing comma in a mapped array is not an element" 3 '
const D = [
  1,
  2,
  3,
]
await parallel(D.map(d => () => agent("a", { label: "a" })))
'

# Control for the two above: a .map over a literal array DOES multiply — its one
# site runs once per element. Without this, "never multiply literal arrays" would
# pass both cases above.
assert_estimate "map over a literal array still multiplies" 3 '
const D = [1, 2, 3]
await parallel(D.map(d => () => agent("a", { label: "a" })))
'

# A template literal nested inside a ${...} interpolation (a prompt with a
# conditional section) must not desync the sanitizer. Before #2670 the inner
# backticks closed the outer template, the apostrophe opened a quote that never
# closed, and every later agent() call was blanked as string content.
# shellcheck disable=SC2016  # the ${...} below is JS fixture text, not shell
assert_estimate "calls after a nested template literal stay visible" 2 "
const P = (c) => \`head \${
  c ? \`the skill's file\` : \`none\`
} tail\`
const x = await agent('one', { label: 'a' })
const y = await agent('two', { label: 'b' })
"

# An array declared empty and filled by push() is as long as the loop makes it,
# not zero. The empty literal read as "0 items" costed evaluate-skill's whole
# rollout+grade pipeline at nothing; the nested-template desync above had been
# hiding the declaration, which is the only reason it ever read as 8.
assert_estimate "array filled by push() is unbounded, not zero" 16 '
const CELLS = []
for (const id of ids) CELLS.push({ id })
await pipeline(CELLS,
  c => agent("rollout", { label: "r" }),
  r => agent("grade", { label: "g" }))
'

# A pushed array's initializer is a FLOOR the push adds to, not something it
# discards. Read as merely unbounded, a 12-item array was costed at ASSUMED (8),
# below #2668's 12, and the hook went silent on a script #2668 asked about
# (#2670 review, round 4). It holds at least 12 + 1.
PUSHED_12='
const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
if (extra) items.push(extra);
await parallel(items.map((i) => () => agent("w " + i)));
'
assert_estimate "pushed literal longer than ASSUMED costs its length plus the push" 13 "$PUSHED_12"
assert_asks "pushed literal longer than ASSUMED still asks" "$PUSHED_12"

# The literal-element rule covers sites reached through the literal's elements
# and modeled fan-outs only. A site in a .filter()-style callback runs once per
# element, and no such callback is a fan-out here, so it keeps #2668's
# multiplier rather than dropping to 1.
assert_estimate "agent() in a .filter() callback over a literal source keeps the multiplier" 3 '
await parallel([1, 2, 3].filter((x) => agent("a " + x)))
'

# A loop window bounds CONCURRENCY, not the agent count: a for-loop stepping by
# WAVE over a runtime list still creates one agent per item. Reading
# .slice(i, i + WAVE) as a bound of WAVE would understate cost by the number of
# waves — the opposite of what this estimator exists to report.
LOOP_OUT=$(estimate_of '
const WAVE = 5
for (let i = 0; i < ITEMS.length; i += WAVE) {
  const batch = ITEMS.slice(i, i + WAVE)
  await parallel(batch.map(x => () => agent("a", { label: "a" })))
}
')
if grep -q '^ASSUMED=8$' <<<"$LOOP_OUT" && grep -q '^ESTIMATE=8$' <<<"$LOOP_OUT"; then
    PASS=$((PASS + 1))
    printf '  PASS  loop window .slice(i, i + WAVE) stays unbounded (costed at ASSUMED)\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  loop window read as a bound: %s\n' "$(tr '\n' ' ' <<<"$LOOP_OUT")"
fi

# End to end: the nested-template desync made the hook go SILENT on a real
# runaway, because the fan-out after the prompt was blanked away.
# shellcheck disable=SC2016  # the ${...} below is JS fixture text, not shell
assert_asks "4-site fan-out after a nested template literal still asks" "
const P = (c) => \`head \${
  c ? \`the skill's file\` : \`none\`
} tail\`
await pipeline(args.units,
  u => agent('edit', { label: 'edit' }),
  e => agent('review', { label: 'review' }),
  r => agent('repair', { label: 'repair' }),
  s => agent('rereview', { label: 'rereview' }))
"

echo
echo "== regex literals and nested templates the text scans misread (#2670 review) =="

# Eight review rounds found spellings a quote-and-brace text scanner misreads:
# a regex literal holding a quote or brace (`/'/g`, `/[{}`]/`) opened a
# "string" that swallowed the agent code after it, and a template nested in a
# ${...} interpolation ended the outer one early. Each blanked code and the
# hook went SILENT where #2668 asked. The estimator now parses the script with
# acorn, which tokenizes a regex and a template as JavaScript does, so these
# are pins that the parse decides (PARSER=acorn) at the true count. The one
# script here that is not valid JavaScript (quote_regex_on_proven_parse
# declares `a2` twice) is costed by the #2668 estimator instead.
FX_DIR=$(mktemp -d) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
if [ -z "$FX_DIR" ] || [ ! -d "$FX_DIR" ]; then echo "FATAL: bad fixture dir" >&2; exit 1; fi
trap 'rm -rf "$FX_DIR"' EXIT
fx() { cat >"$FX_DIR/$1.js"; }

fx regex_squote_in_interp <<'EOF'
const p = (s) => `x ${s.replace(/'/g, "")} y`
await pipeline(args.units,
  u => agent('edit', { label: 'edit' }),
  e => agent('review', { label: 'review' }),
  r => agent('repair', { label: 'repair' }),
  s => agent('rereview', { label: 'rereview' }))
EOF
fx regex_dquote_in_interp <<'EOF'
const p = (s) => `Prompt: ${s.replace(/"/g, '\\"')} end`
await parallel(args.items.map(x => () => agent(p(x), { label: 'a' })))
await parallel(args.items.map(x => () => agent(p(x), { label: 'b' })))
EOF
# Walked structurally, the template runs to end of file and blanks the
# declaration of L, so L reads as unbounded: 32 instead of 8.
fx literal_runs_to_eof <<'EOF'
await pipeline(L, u => agent('a'), e => agent('b'), r => agent('c'), s => agent('d'))
const p = `x ${s.replace(/{/g, '')} y`
const L = [1, 2]
EOF
# Walked structurally, the first template ends inside the second, which blanks
# the fan-out's closing parens: the fan-out drops out and costs 1 instead of 8.
fx brace_regex_blanks_parens <<'EOF'
await parallel(args.xs.map(x => () => agent(`p ${x.replace(/{/g, '')}`)))
const q = `x ${s.replace(/}/g, '')} y`
EOF
# Walked structurally, the two templates merge and the pipeline between them is
# blanked: NO_AGENTS, and silence, instead of 16.
fx brace_regex_blanks_calls <<'EOF'
const p = `x ${s.replace(/{/g, '')} y`
await pipeline(args.units, u => agent('a'), e => agent('b'))
const q = `x ${s.replace(/}/g, '')} y`
EOF
# Control: the shape the round-1 structural walk existed for.
fx nested_template_proves_itself <<'EOF'
const P = (c) => `head ${
  c ? `the skill's file` : `none`
} tail`
await pipeline(args.units, u => agent('edit'), e => agent('review'), r => agent('repair'), s => agent('rereview'))
EOF
# A `{` regex in one template and a `}` regex in a later one kept the span
# between them inside one template for the structural walk, which blanked the
# declaration of `items`: 8 instead of 12, and the hook went silent (#2670
# review, round 3).
fx brace_pair_blanks_bound <<'EOF'
const open = (s) => `g ${s.replace(/{/g, "(")} h`;
const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const close = (s) => `e ${s.replace(/}/g, ")")} f`;
await parallel(items.map((i) => () => agent(open(i) + close(i))));
EOF
# The same pair around a pipeline source. The walk read the blanked list as
# unbounded (2 x 8 = 16); it holds 6 items, so the count is 2 x 6 = 12.
fx brace_pair_raises_pipeline <<'EOF'
const open = (s) => `g ${s.replace(/{/g, "(")} h`;
const units = [1, 2, 3, 4, 5, 6];
const close = (s) => `e ${s.replace(/}/g, ")")} f`;
await pipeline(units, (u) => agent(open(u)), (u) => agent(close(u)));
EOF
# Both text scans lost the pipeline to the quote regex; #2668 asked only because
# it tripled the literal array beside it, and the literal-element rule (30 ->
# 10) turned that into silence on a script whose true count is 34 (#2670
# review, round 4).
fx unproven_literal_beside_quote_regex <<'EOF'
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
const w2 = s.replace(/'/g, "");
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
EOF
# A regex holding a backtick opened a template in both text scans and the next
# one closed it, so the pipeline between them was blanked while every check the
# walk ran still passed: #2668's 30 became a silent 10 (#2670 review, round 5).
# This one also declares `a2` twice, which is a SyntaxError, so acorn rejects
# it and the #2668 estimator decides: the fallback, pinned on a real input.
fx quote_regex_on_proven_parse <<'EOF'
const a2 = s.match(/[{}`]/);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
const a2 = s.match(/[{}`]/);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
# Rounds 5-8 grew a list of positions a regex can follow, one missed spelling
# per round: after `=>` and `return`, a control header's `)`, a block comment,
# a header across lines or three parens deep, a spread, `export default`, and
# a division. Each is the same script with the regex in another position.
fx quote_regex_after_arrow <<'EOF'
const f = (s) => /[{}`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
const g = (s) => /[{}`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_return <<'EOF'
function f(s) { return /[{}`]/.test(s) }
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
function g(s) { return /[{}`]/.test(s) }
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_if_header <<'EOF'
if (ok(trim(s))) /[{}`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
if (ok(trim(s))) /[{}`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_block_comment <<'EOF'
/* strip */ /[{}`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
/* strip */ /[{}`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_multiline_header <<'EOF'
if (a &&
    b) /[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
if (a &&
    b) /[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_three_deep_header <<'EOF'
if (f(g(h(x)))) /[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
if (f(g(h(x)))) /[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_paren_string_header <<'EOF'
if (s === ")") /[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
if (s === ")") /[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_spread <<'EOF'
f(.../[`]/);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
f(.../[`]/);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_export_default <<'EOF'
export const meta = { name: "ed-flip3", description: "x", phases: [] }
export default /`/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
// the template opened above is closed by the backtick here `
const BT = 1;
await parallel([() => agent("r1"), () => agent("r2"), () => agent("r3"), () => agent("r4")]);
EOF
# Without the space, `a //re/` is a comment.
fx quote_regex_after_division <<'EOF'
x = a / /[`]/.test(s);
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
x = a / /[`]/.test(s);
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF
fx quote_regex_after_division_in_call <<'EOF'
f(a / /[`]/.test(s));
await pipeline(units, (u) => agent("a"), (u) => agent("b"), (u) => agent("c"));
f(a / /[`]/.test(s));
await parallel([() => agent("r"), () => agent("s"), ...args.units.map((u) => () => agent(u))]);
EOF

assert_asks "backtick regex after a header spanning two lines still asks" "$(<"$FX_DIR/quote_regex_after_multiline_header.js")"
assert_asks "backtick regex after a header nesting parens three deep still asks" "$(<"$FX_DIR/quote_regex_after_three_deep_header.js")"
assert_asks "backtick regex after a header holding \")\" in a string still asks" "$(<"$FX_DIR/quote_regex_after_paren_string_header.js")"
assert_asks "backtick regex after a spread still asks" "$(<"$FX_DIR/quote_regex_after_spread.js")"
assert_asks "backtick regex after export default still asks" "$(<"$FX_DIR/quote_regex_after_export_default.js")"
assert_asks "backtick regex after a division still asks" "$(<"$FX_DIR/quote_regex_after_division.js")"
assert_asks "backtick regex after a division inside a call still asks" "$(<"$FX_DIR/quote_regex_after_division_in_call.js")"

assert_asks "regex holding ' inside \${...} still asks" "$(<"$FX_DIR/regex_squote_in_interp.js")"
assert_asks "regex holding \" inside \${...} still asks" "$(<"$FX_DIR/regex_dquote_in_interp.js")"
assert_asks "templates merged across a pipeline still ask" "$(<"$FX_DIR/brace_regex_blanks_calls.js")"
assert_asks "brace-regex pair around a bounding declaration still asks" "$(<"$FX_DIR/brace_pair_blanks_bound.js")"
assert_asks "brace-regex pair around a pipeline source still asks" "$(<"$FX_DIR/brace_pair_raises_pipeline.js")"
assert_asks "literal array beside a quote regex still asks" "$(<"$FX_DIR/unproven_literal_beside_quote_regex.js")"
assert_asks "backtick regex in a script acorn rejects still asks (#2668 decides)" "$(<"$FX_DIR/quote_regex_on_proven_parse.js")"
assert_asks "backtick regex after => still asks" "$(<"$FX_DIR/quote_regex_after_arrow.js")"
assert_asks "backtick regex after return still asks" "$(<"$FX_DIR/quote_regex_after_return.js")"
assert_asks "backtick regex after an if header still asks" "$(<"$FX_DIR/quote_regex_after_if_header.js")"
assert_asks "backtick regex after a block comment still asks" "$(<"$FX_DIR/quote_regex_after_block_comment.js")"

# assert_parse <desc> <estimate> <parser> <fallback-substring> <fixture>
# The regex-era version of this asserted which text scan decided (SANITIZER=).
# There is one scan now, so it asserts the parser and the figure.
assert_parse() {
    local desc="$1" want_est="$2" want_parser="$3" want_why="$4" out est parser why ok=1
    out=$(python3 "$ESTIMATOR" 10 8 <"$FX_DIR/$5.js" 2>/dev/null)
    est=$(sed -n 's/^ESTIMATE=//p' <<<"$out")
    parser=$(sed -n 's/^PARSER=//p' <<<"$out")
    why=$(sed -n 's/^FALLBACK=//p' <<<"$out")
    [ "$est" = "$want_est" ] && [ "$parser" = "$want_parser" ] || ok=0
    if [ -z "$want_why" ]; then
        [ -z "$why" ] || ok=0
    else
        [[ "$why" == *"$want_why"* ]] || ok=0
    fi
    if [ "$ok" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf '  PASS  ESTIMATE=%s PARSER=%s: %s\n' "$want_est" "$want_parser" "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  expected %s/%s/"%s", got %s/%s/"%s": %s\n' \
            "$want_est" "$want_parser" "$want_why" "${est:-<none>}" "${parser:-<none>}" "$why" "$desc"
    fi
}

assert_parse "regex holding ' inside \${...}"             32 acorn "" regex_squote_in_interp
assert_parse "regex holding \" inside \${...}"            16 acorn "" regex_dquote_in_interp
assert_parse "declaration after a regex holding {"       8  acorn "" literal_runs_to_eof
assert_parse "fan-out between { and } regexes"            8  acorn "" brace_regex_blanks_parens
assert_parse "pipeline between { and } regexes"           16 acorn "" brace_regex_blanks_calls
assert_parse "nested template"                            32 acorn "" nested_template_proves_itself
assert_parse "bounding declaration between brace regexes" 12 acorn "" brace_pair_blanks_bound
# Was 16: the structural walk blanked `units`, and the higher reading was kept.
assert_parse "6-item pipeline source between brace regexes" 12 acorn "" brace_pair_raises_pipeline
# Was 30, #2668's reading, which had lost the pipeline: 3 x 8 + 2 + 8 = 34.
assert_parse "literal array beside a quote regex"         34 acorn "" unproven_literal_beside_quote_regex
assert_parse "quoted regex after a two-line header"       34 acorn "" quote_regex_after_multiline_header
# Was 16, #2668's reading: 3 x 8 + 4 = 28.
assert_parse "quoted regex after export default"          28 acorn "" quote_regex_after_export_default
assert_parse "quoted regex after a division"              34 acorn "" quote_regex_after_division
assert_parse "a script acorn rejects is costed by #2668"  30 fallback "not parsable as a module" quote_regex_on_proven_parse

echo
echo "== fixtures for the differential against the #2668 estimator and the true count =="

# The shapes review rounds 1-8 built to break the text-pattern estimator. The
# differential below runs each of them, the committed round 7-8 corpus
# (fixtures/workflow-scale/), and every bundled template.
BASELINE="$(dirname "$0")/lib/workflow-scale-estimate-2668.py"
CORPUS_DIR="$(dirname "$0")/fixtures/workflow-scale"
TRUECOUNT="$CORPUS_DIR/truecount.mjs"

fx spread_then_map <<'EOF'
await parallel([...args.items].map(x => () => agent("a", { label: "a" })))
EOF
fx spread_inner_map <<'EOF'
await parallel([...args.items.map(x => () => agent("a", { label: "a" }))])
EOF
fx literal_4_thunks <<'EOF'
await parallel([() => agent("a"), () => agent("b"), () => agent("c"), () => agent("d")])
EOF
fx literal_holding_nested_fanout <<'EOF'
await parallel([() => parallel(args.xs.map(x => () => agent("a"))), () => agent("b")])
EOF
fx pipeline_literal_source <<'EOF'
await pipeline([1, 2, 3, 4, 5, 6], s => agent("a"), t => agent("b"))
EOF
fx literal_concat_mapped <<'EOF'
await parallel([() => agent("a")].concat(args.xs.map(x => () => agent("b"))))
EOF
fx trailing_comma_mapped <<'EOF'
const D = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10,]
await parallel(D.map(d => () => agent("a")))
EOF
# A hole is an element (JS length 3), so it lowers nothing: only a FINAL empty
# segment is dropped.
fx holey_array_mapped <<'EOF'
const H = [1, , 3]
await parallel(H.map(h => () => agent("a")))
EOF
# A pushed array is costed at max(initializer + 1, ASSUMED). None of these may
# fall below #2668, which read the initializer alone (counting a trailing comma).
fx pushed_literal_over_assumed <<'EOF'
const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
if (extra) items.push(extra);
await parallel(items.map((i) => () => agent("w " + i)));
EOF
fx pushed_trailing_comma <<'EOF'
const D = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10,]
if (x) D.push(x)
await parallel(D.map(d => () => agent("a")))
EOF
fx pushed_capped_declaration <<'EOF'
const G = args.units.slice(0, 20)
if (x) G.push(x)
await parallel(G.map(g => () => agent("a")))
EOF
fx filter_callback_in_literal_source <<'EOF'
await parallel([1, 2, 3].filter((x) => agent("a " + x)))
EOF
# A literal-array element that repeats its own agent() call runs it more than
# once. Round 6 recognized only a list of iterating methods, so a loop, a
# `while`, or `Array.from({length: n}, fn)` inside an element dropped the
# multiplier and #2668's 110 or 200 became a silent 10 (#2670 review, round 7).
# Such a site is now costed as unbounded, and never below the literal's length.
fx loop_in_literal_element <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { for (const f of args.findings) await agent("verify " + f) },
]);
EOF
fx while_in_literal_element <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { let i = 0; while (i < args.findings.length) { await agent("v " + i); i++ } },
]);
EOF
fx array_from_in_literal_element <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  () => Array.from({ length: 20 }, (_, i) => agent("spawn " + i)),
]);
EOF
# With a short literal the literal's length is below ASSUMED; the loop still
# costs 8. Keeping only the literal's multiplier would read 3, under #2668's 4.
fx loop_in_short_literal_element <<'EOF'
await parallel([() => agent("a"), async () => { for (const f of args.findings) await agent(f) }])
EOF
# A function bound to a name and called by hand is not a thunk parallel() calls
# once: it holds no loop keyword, so only the function check refuses it.
fx hand_called_fn_in_literal_element <<'EOF'
await parallel([() => agent("a"), () => { const g = () => agent("b"); g(); g() }])
EOF
# A named function expression can call itself, so it is not run once either.
fx recursive_fn_literal_element <<'EOF'
await parallel([() => agent("a"), async function rec(n) { await agent("b"); if (n) await rec(n - 1) }])
EOF
# Control: a modeled .map inside an unmodeled call's ARGUMENT (not a callback
# to it) still runs once per element, so the literal rule still lowers it.
fx promise_all_map_in_literal_element <<'EOF'
await parallel([() => agent("a"), () => Promise.all(args.findings.map((f) => agent("v " + f)))])
EOF

assert_asks "loop inside a literal-array element still asks" "$(<"$FX_DIR/loop_in_literal_element.js")"
assert_asks "while inside a literal-array element still asks" "$(<"$FX_DIR/while_in_literal_element.js")"
assert_asks "Array.from mapper inside a literal-array element still asks" "$(<"$FX_DIR/array_from_in_literal_element.js")"
assert_estimate "loop in a short literal's element costs ASSUMED, not the literal length" 9 "$(<"$FX_DIR/loop_in_short_literal_element.js")"
# Regex era: 9, because the text scan could not see g's two calls and costed the
# element at ASSUMED. The parse counts the calls: 1 + 2 = 3, the true count.
assert_estimate "hand-called function in a literal's element costs its calls" 3 "$(<"$FX_DIR/hand_called_fn_in_literal_element.js")"
# Regex era: 9, max(literal length, ASSUMED) + 1. A recursive function is now
# costed as one entry plus ASSUMED re-entries per entry: 1 + (1 + 8) = 10.
assert_estimate "recursive named function as a literal's element costs 1 + ASSUMED re-entries" 10 "$(<"$FX_DIR/recursive_fn_literal_element.js")"
assert_estimate "modeled .map inside Promise.all in a literal's element runs once per item" 9 "$(<"$FX_DIR/promise_all_map_in_literal_element.js")"
# Round 7 saw only `=>` and `function` as functions, and accepted a thunk in ANY
# array literal as run once. A method, getter or class method holding the site,
# or a thunk in an inner array, can be called by a loop or .map placed AFTER the
# site, which the loop-keyword scan does not reach: #2668's 110 became a silent
# 10 (#2670 review, round 8). Each is now refused and costed as unbounded.
fx method_shorthand_loop_after <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const o = { async run(f) { await agent("v " + f) } }; for (const f of args.findings) await o.run(f) },
]);
EOF
fx method_shorthand_map_after <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const o = { run(f) { return agent("v " + f) } }; return Promise.all(args.findings.map((f) => o.run(f))) },
]);
EOF
fx class_method_map_after <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { class W { run(f) { return agent("v " + f) } }; const w = new W(); return Promise.all(args.findings.map((f) => w.run(f))) },
]);
EOF
fx getter_loop_after <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const o = { get go() { return agent("v") } }; for (const f of args.findings) await o.go },
]);
EOF
fx inner_array_thunk_map_after <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const fs = [(f) => agent("v " + f)]; return Promise.all(args.findings.map((f) => fs[0](f))) },
]);
EOF
fx inner_array_thunk_loop_after <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const fs = [(f) => agent("v " + f)]; for (const f of args.findings) await fs[0](f) },
]);
EOF
fx inner_array_recursive_thunk <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const fs = [async (n) => { await agent("v" + n); if (n) await fs[0](n - 1) }]; await fs[0](args.findings.length) },
]);
EOF
# A thunk returned by a .map callback is called once only when the mapped
# array becomes parallel()'s argument list. Indexed out of it, it is a plain
# function a later loop or .map can call any number of times.
fx map_returned_thunk_indexed_loop <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const run = [0].map(() => (f) => agent("v " + f))[0]; for (const f of args.findings) await run(f) },
]);
EOF
fx map_returned_thunk_indexed_map <<'EOF'
await parallel([
  () => agent("a"), () => agent("b"), () => agent("c"), () => agent("d"),
  () => agent("e"), () => agent("f"), () => agent("g"), () => agent("h"),
  () => agent("i"),
  async () => { const run = [0].map(() => (f) => agent("v " + f))[0]; return Promise.all(args.findings.map((f) => run(f))) },
]);
EOF
# Controls: a `{` after an `if` header or a `function` keyword's parameters is
# not a method body, and a stage of a pipeline inside an element is multiplied
# by that pipeline, so each still runs once per item.
fx if_block_in_literal_element <<'EOF'
await parallel([() => agent("a"), async () => { if (x) { await agent("b") } }])
EOF
fx anonymous_function_literal_element <<'EOF'
await parallel([() => agent("a"), async function () { await agent("b") }])
EOF
fx pipeline_stage_in_literal_element <<'EOF'
await parallel([() => agent("a"), () => pipeline(args.units, (u) => agent("b " + u))])
EOF
# The shape two bundled templates use: an element whose thunks a .map returns
# straight into parallel(), here with the trailing comma house style adds.
fx returned_thunks_into_parallel_element <<'EOF'
await parallel([
  () => agent("a"),
  () =>
    parallel(
      args.units.map((u) => () =>
        agent("b " + u),
      ),
    ),
]);
EOF

assert_asks "method shorthand called by a later loop still asks" "$(<"$FX_DIR/method_shorthand_loop_after.js")"
assert_asks "method shorthand called by a later .map still asks" "$(<"$FX_DIR/method_shorthand_map_after.js")"
assert_asks "class method called by a later .map still asks" "$(<"$FX_DIR/class_method_map_after.js")"
assert_asks "getter read by a later loop still asks" "$(<"$FX_DIR/getter_loop_after.js")"
assert_asks "inner-array thunk called by a later .map still asks" "$(<"$FX_DIR/inner_array_thunk_map_after.js")"
assert_asks "inner-array thunk called by a later loop still asks" "$(<"$FX_DIR/inner_array_thunk_loop_after.js")"
assert_asks "recursive inner-array thunk still asks" "$(<"$FX_DIR/inner_array_recursive_thunk.js")"
assert_asks "thunk indexed out of a .map, called by a later loop, still asks" "$(<"$FX_DIR/map_returned_thunk_indexed_loop.js")"
assert_asks "thunk indexed out of a .map, called by a later .map, still asks" "$(<"$FX_DIR/map_returned_thunk_indexed_map.js")"
assert_estimate "an if block inside a literal's element runs once" 2 "$(<"$FX_DIR/if_block_in_literal_element.js")"
assert_estimate "an anonymous function as a literal's element runs once" 2 "$(<"$FX_DIR/anonymous_function_literal_element.js")"
assert_estimate "a pipeline stage inside a literal's element runs once per item" 9 "$(<"$FX_DIR/pipeline_stage_in_literal_element.js")"
assert_estimate "thunks a .map returns into parallel() inside an element run once per item" 9 "$(<"$FX_DIR/returned_thunks_into_parallel_element.js")"
# Round 10 (#2670 review): rest parameters, template tags and block functions.
# Round 9 read every argument after a rest slot as never called, so twelve
# thunks through `(...tasks) => parallel(tasks)` cost 8 and the hook went
# silent where origin/main asked at 12. The shapes are corpus fixtures, which
# the differential holds at their true counts; these pin the ask end to end,
# the negative that keeps a small rest-parameter helper silent, and two
# branches a true count cannot pin.
assert_asks "thunks taken through a rest parameter still ask" "$(<"$CORPUS_DIR/rest_param_thunks_into_parallel.js")"
assert_asks "thunks a template tag receives still ask" "$(<"$CORPUS_DIR/tag_receives_thunks.js")"
assert_silent "two thunks through a rest-parameter helper stay silent" '
const runAll = (...fns) => Promise.all(fns.map((fn) => fn()))
await runAll(() => agent("a"), () => agent("b"))
'
# An exported function may be called from outside the script, so it costs
# ASSUMED even when the script never calls it. Its true count is 0.
assert_estimate "an exported function the script never calls costs ASSUMED" 8 '
export async function review(f) { return agent("review " + f) }
'
# Which of two block functions of one name the name holds depends on the run
# (Annex B), so each is charged every call: 12 + 12, where the true count is 12.
assert_estimate "two block functions of one name are each charged every call" 24 '
if (!ok()) { function spawn(i) { return agent("a" + i) } } else { function spawn(i) { return agent("b" + i) } }
for (let i = 0; i < 12; i++) await spawn(i)
'
# Round 11 (#2670 review): a loop the parse recognises but nothing in its text
# bounds -- no test, a counter it moves back or resets, a limit it raises, a
# list it grows -- a hand-built iterator, and a method the language calls with
# no visible call are costed at HIGH, one over the limit (11 here), where round
# 10 costed them at ASSUMED (8) and went silent. Their true counts vary, so each
# is pinned at HIGH here rather than at a true count in the corpus.
assert_estimate "a while (true) with no stated count costs HIGH" 11 '
while (true) { const r = await agent("poll"); if (r.verdict) break }
'
assert_estimate "a for (;;) with no stated count costs HIGH" 11 '
for (;;) { const r = await agent("poll"); if (r.verdict) break }
'
assert_estimate "a do...while (true) costs HIGH" 11 '
do { await agent("poll") } while (true)
'
assert_estimate "a counter the body moves back costs HIGH" 11 '
let r = 0
for (let i = 0; i < 3; i++) { await agent("x"); if (r++ < 12) i-- }
'
assert_estimate "a counter a closure resets costs HIGH" 11 '
let i = 0, r = 0
const back = () => { i = 0 }
while (i < 3) { await agent("x"); if (r++ < 12) back(); i++ }
'
assert_estimate "a counter that only moves away from its limit costs HIGH" 11 '
for (let i = 0; i < 3; i--) { await agent("x"); if (i < -10) break }
'
assert_estimate "a limit the loop raises costs HIGH" 11 '
let N = 2
for (let i = 0; i < N; i++) { await agent("x"); if (N < 14) N++ }
'
assert_estimate "a for...of over a list it pushes to costs HIGH" 11 '
const xs = [1, 2]
for (const x of xs) { await agent("x"); if (xs.length < 14) xs.push(0) }
'
assert_estimate "a while over a queue it refills costs HIGH" 11 '
const q = [1]
let n = 0
while (q.length) { q.shift(); await agent("x"); if (n++ < 12) q.push(1, 2) }
'
assert_estimate "a Set grown while it is iterated costs HIGH" 11 '
const s = new Set([1])
for (const x of s) { await agent("x"); if (s.size < 13) s.add(s.size + 1) }
'
assert_estimate "an object with a hand-built iterator costs HIGH" 11 '
const it = { [Symbol.iterator]() { let i = 0; return { next: () => ({ done: i >= 12, value: i++ }) } } }
for (const x of it) await agent(x)
'
# shellcheck disable=SC2016  # the ${o} below is JS fixture text, not shell
assert_estimate "an implicitly called toString costs HIGH" 11 '
const o = { toString() { agent("s"); return "x" } }
for (let i = 0; i < 20; i++) log(`${o}`)
'
assert_estimate "an awaited thenable costs HIGH" 11 '
const o = { then(res) { agent("t"); res(1) } }
for (let i = 0; i < 12; i++) await o
'
assert_estimate "a [Symbol.toPrimitive] method costs HIGH" 11 '
const o = { [Symbol.toPrimitive]() { agent("p"); return 1 } }
for (let i = 0; i < 12; i++) log(o * 2)
'
assert_estimate "a generator whose loop has no test costs HIGH" 11 '
function* gen() { for (let i = 0; ; i++) yield agent("g" + i) }
let k = 0
for (const p of gen()) { await p; if (++k >= 20) break }
'
assert_estimate "a zero step never moves its counter: HIGH" 11 '
let k = 0
for (let i = 0; i < 3; i += 0) { await agent("x"); if (++k >= 12) break }
'
assert_estimate "a list an index write grows costs HIGH" 11 '
const xs = [1, 2]
for (let i = 0; i < xs.length; i++) { await agent("x"); if (i < 12) xs[i + 1] = 1 }
'
# Pins for branches a true count cannot hold, each at the figure it must keep:
# an assignment in a for-init is not a reset; a class also built through
# `this.constructor`, an object with a `__proto__`, and a registry whose method
# hands `this` on fall back to ASSUMED rather than to what the text shows (the
# last would read 0); a named key written onto an array is one more key for
# for...in; and a recursion guard that does not stop its step (n < 10 while n
# falls) proves no depth.
assert_estimate "a counter assigned in its for-init is not reset by the loop" 8 '
let i
for (i = 0; i < args.limit; i++) await agent("x" + i)
'
assert_estimate "a class also built through this.constructor costs ASSUMED, not its one new" 8 '
class C { constructor() { agent("c") } clone() { return new this.constructor() } }
const c = new C()
for (let i = 0; i < 12; i++) c.clone()
'
assert_estimate "for...in over an object with a __proto__ costs ASSUMED" 8 '
const base = { a: 1, b: 2, c: 3, d: 4, e: 5, f: 6 }
const o = { __proto__: base, g: 7, h: 8, i: 9, j: 10, k: 11, l: 12 }
for (const k in o) await agent(k)
'
assert_estimate "for...in over an array given a named key costs its length plus one" 12 '
const xs = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
xs.extra = 1
for (const k in xs) await agent(k)
'
assert_estimate "a registry whose method hands on this is not followed: ASSUMED, not 0" 8 '
const reg = { run: () => agent("r"), self() { return this } }
const r2 = reg.self()
const k = "run"
for (let i = 0; i < 12; i++) r2[k]()
'
assert_estimate "a recursion guard that does not stop its step proves no depth" 12 '
let guard = 0
function f(n) { agent("r"); if (n < 10 && guard++ < 13) f(n - 1) }
f(5)
'
assert_estimate "a recursion guard that does not stop a rising step proves no depth" 9 '
let guard = 0
function f(n) { agent("r"); if (n > 0 && guard++ < 13) f(n + 1) }
f(1)
'
# HIGH is one over whatever limit is set, so a raised limit still asks.
high_out=$(printf '%s\n' 'while (true) { await agent("poll") }' | python3 "$ESTIMATOR" 50 8 2>/dev/null)
if grep -qx 'ESTIMATE=51' <<<"$high_out" && grep -qx 'VERDICT=OVER_LIMIT' <<<"$high_out" \
    && grep -qx 'HIGH=51' <<<"$high_out" && grep -q '^UNBOUNDED=a while loop' <<<"$high_out"; then
    PASS=$((PASS + 1))
    printf '  PASS  HIGH follows the limit: 51 over a limit of 50, named in UNBOUNDED=\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  HIGH did not follow a limit of 50: %s\n' "$(tr '\n' ' ' <<<"$high_out")"
fi
# The shapes HIGH must not catch: a flag beside a counter, a break test that
# states a small count, and a recursion whose depth the text proves.
assert_silent "a retry loop behind a flag and a counter stays silent" '
let done = false, tries = 0
while (!done && tries < 3) { const r = await agent("x"); tries++; if (r.verdict) done = true }
'
assert_silent "a while (true) whose break states 3 stays silent" '
let n = 0
while (true) { await agent("x"); if (++n >= 3) break }
'
assert_estimate "a recursion two levels deep with two calls each costs 7" 7 '
async function walk(node, depth) { await agent(node); if (depth < 2) for (const c of [1, 2]) await walk(c, depth + 1) }
await walk(0, 0)
'
assert_silent "results pushed to another list stay silent" '
const results = []
for (const u of args.units) results.push(await agent(u))
'
# Round 12 (#2670 review of round 11): paths round 11 added that costed a
# reachable agent() at 0 or once, or went silent where round 10 asked. The
# shapes with a true count the estimate meets are corpus fixtures (map keys,
# UTF-16 strings, this[k] dispatch, a spread in .call, Array(...[n]), a
# count-down to a negative constant); these pin the rest at the figure each
# must keep: a replace or pattern the string rules do not govern, and a spread
# ahead of .call's arguments, fall back to ASSUMED per callback.
assert_estimate "an object's own replace method is not the string one: ASSUMED, not 2" 16 '
const o = { replace(p, f) { for (let i = 0; i < 20; i++) f() } }
o.replace("x", () => { agent("a"); agent("b") })
'
assert_estimate "a pattern with its own [Symbol.replace] is not a regex: ASSUMED, not 4" 16 '
const pat = { [Symbol.replace](s, f) { for (let i = 0; i < 20; i++) f() } }
"x".replace(pat, () => { agent("a"); agent("b") })
'
assert_estimate "a rest list reached through .call(...spread) is not bounded by the spread" 16 '
function run(...fns) { for (let i = 0; i < fns.length; i++) { agent("a"); agent("b") } }
run.call(...[null, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
'
# A break's count bounds a while (true) only when its counter starts at a
# stated number and moves toward the break on every pass: a reset, a move on
# some passes only, a counter declared in the body, or a continue past it
# leaves nothing bounding the loop, so each costs HIGH where round 11 read the
# break's stated count (ASSUMED, silent).
assert_estimate "a while (true) whose break counter the body resets costs HIGH" 11 '
let n = 0, k = 0
while (true) { await agent("x"); if (++n >= 5) { if (k++ < 3) { n = 0; continue } break } }
'
assert_estimate "a while (true) whose break counter moves on some passes only costs HIGH" 11 '
let j = 0, k = 0
while (true) { await agent("x"); if (++j % 10 === 0) k++; if (k >= 3) break }
'
assert_estimate "a while (true) whose break counter a nested branch resets costs HIGH" 11 '
let n = 0, r = 0
while (true) { await agent("x"); if (++n >= 4) { if (r++ < 4) n = 0; else break } }
'
assert_estimate "a break counter declared in the loop body starts again every pass: HIGH" 11 '
while (true) { let n = 0; await agent("x"); if (++n >= 5) break }
'
assert_estimate "a break counter a continue may skip bounds nothing: HIGH" 11 '
let n = 0, k = 0
while (true) { await agent("x"); if (k++ < 20) continue; if (++n >= 3) break }
'
assert_estimate "a break counter moved only behind && bounds nothing: HIGH" 11 '
let n = 0
const go = false
while (true) { await agent("x"); go && n++; if (n >= 3) break }
'
assert_estimate "a break a try may skip bounds nothing: HIGH" 11 '
const f = () => { throw 1 }
let n = 0
while (true) { await agent("x"); if (++n >= 3) { try { f(); break } catch {} } }
'
assert_estimate "a count-down whose body moves its counter back costs HIGH" 11 '
let r = 0
for (let i = 3; i > 0; i--) { await agent("x"); if (r++ < 20) i++ }
'
assert_estimate "a Map whose set() result is used is not followed: ASSUMED, not 0" 8 '
const m = new Map()
m.set("a", () => agent("a"))
for (let i = 0; i < 20; i++) m.set("b", 1).get("a")()
'
assert_estimate "a break counter stepped by less than 1 bounds nothing: HIGH" 11 '
let n = 0
while (true) { await agent("x"); n += 0.5; if (n >= 5) break }
'
assert_estimate "an === break a step of 2 can jump past bounds nothing: HIGH" 11 '
let n = 0
while (true) { await agent("x"); n += 2; if (n === 7) break }
'
assert_estimate "a break counter set again before the loop does not start at its declaration: HIGH" 11 '
let n = 0
n = -15
while (true) { await agent("x"); if (++n >= 2) break }
'
assert_silent "a poll that breaks on a verdict or a counted try stays silent" '
let tries = 0
while (true) { const r = await agent("x"); if (r.verdict || ++tries >= 5) break }
'
assert_silent "a break counter stepped by n = n + 1 bounds its loop" '
let n = 0
while (true) { await agent("x"); n = n + 1; if (n >= 3) break }
'
# A recursion that resets the parameter its test reads -- directly, or through
# a sloppy-mode arguments[0] -- is costed HIGH levels deep, as a loop that
# resets its counter is; one that only reads arguments keeps its proven depth.
assert_estimate "a recursion that resets its tested parameter through arguments costs HIGH depth" 12 '
let k = 0
function rec(d) { if (k++ < 20) arguments[0] = 0; agent("r"); if (d < 3) rec(d + 1) }
rec(0)
'
assert_estimate "a recursion that resets its tested parameter costs HIGH depth" 12 '
let k = 0
function rec(d) { agent("r"); if (k++ < 20) d = 0; if (d < 3) rec(d + 1) }
rec(0)
'
assert_estimate "a recursion that only reads arguments keeps its proven depth" 4 '
function rec(d) { agent("r" + arguments.length); if (d < 3) rec(d + 1) }
rec(0)
'
assert_estimate "a recursion that moves its tested parameter both ways costs HIGH depth" 12 '
let k = 0
function rec(d) { agent("r"); if (k++ < 20) d--; d++; if (d < 3) rec(d + 1) }
rec(0)
'
assert_estimate "a recursion that only steps its tested parameter stays ASSUMED levels deep" 9 '
function rec(d) { agent("r"); d = d + 1; if (d < 3) rec(d) }
rec(0)
'
# Branches round 11 added that no fixture pinned (its verifier's surviving
# mutants): each figure is what a mutant of that branch lowers.
assert_estimate "a list grown through .length++ while iterated costs HIGH" 11 '
const xs = [1]
for (const x of xs) { await agent("x"); if (xs.length < 20) xs.length++ }
'
assert_estimate "a class a factory builds is not followed: ASSUMED, not 1" 8 '
class W { x = agent("w") }
function make(C) { return new C() }
for (let i = 0; i < 20; i++) make(W)
'
assert_estimate "a generator that delegates to itself costs ASSUMED, not 1" 9 '
function* g(n) { yield n; if (n < 19) yield* g(n + 1) }
for (const x of g(0)) await agent("x" + x)
'
assert_estimate "a recursion stepped by 0 proves no depth: ASSUMED levels, not the #2668 fallback" 18 '
function rec(d) { agent("a"); agent("b"); if (d < 3) rec(d + 0) }
rec(0)
'
assert_estimate "two copies of a runtime list flattened cost ASSUMED, not 2" 8 '
const inner = units.slice()
for (const x of [inner, inner].flat()) await agent(x)
'
# Costing a recursion counts the function twice, and each recursion it reaches
# is costed again inside both counts, so a ring of self-recursive functions
# doubled the work per function: 20 of them exceeded the step budget and the
# #2668 estimator decided, silently (OK/1 for a true 21). Past a budget of
# measured recursions the rest cost HIGH, so the parse still decides and asks.
ring=$(python3 -c '
n = 20
print("let budget = 0")
for i in range(n):
    body = "agent(); " if i == 0 else ""
    print(f"function f{i}(d) {{ if (budget++ > 400) return; {body}if (d < 2) f{i}(d + 1); f{(i + 1) % n}(0) }}")
print("f0(0)")
')
ring_out=$(printf '%s\n' "$ring" | python3 "$ESTIMATOR" 10 8 2>/dev/null)
if grep -qx 'PARSER=acorn' <<<"$ring_out" && grep -qx 'VERDICT=OVER_LIMIT' <<<"$ring_out"; then
    PASS=$((PASS + 1))
    printf '  PASS  a ring of 20 self-recursive functions is costed by the parse and asks\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  a ring of 20 self-recursive functions: %s\n' "$(grep -E '^(VERDICT|ESTIMATE|PARSER|FALLBACK)=' <<<"$ring_out" | tr '\n' ' ')"
fi
# Before this commit a missing newline joined the next `fx` line to the
# assertion above, so close_brace_regex_in_interp was fed to that assertion's
# stdin and never written, and the differential never ran it.
fx close_brace_regex_in_interp <<'EOF'
const p = (s) => `x ${s.replace(/}/g, '')} y`
await pipeline(args.units, u => agent('a'), e => agent('b'), r => agent('c'))
EOF
fx open_brace_regex_in_interp <<'EOF'
const p = (s) => `x ${s.replace(/{/g, '')} y`
await pipeline(args.units, u => agent('a'), e => agent('b'), r => agent('c'))
EOF
fx paren_regex_in_interp <<'EOF'
const p = (s) => `x ${s.replace(/\(/g, '')} y`
await parallel(args.xs.map(x => () => agent('a')))
await parallel(args.ys.map(y => () => agent('b')))
EOF
fx unterminated_block_comment <<'EOF'
await pipeline(args.units, u => agent('a'), e => agent('b'))
const re = /a\/*b/
await pipeline(args.units, u => agent('c'), e => agent('d'))
EOF

echo
echo "== differential: the true count, and the #2668 estimator where it asks =="

# Every inline fixture above, the committed corpus, and every bundled template
# is run three ways: the live estimator, the frozen #2668 estimator, and (for
# fixtures) node with a counting agent() and 8-item lists, which is the true
# count on the estimator's own ASSUMED=8 convention. The rules:
#   1. The estimate is never below a measured true count, and never NO_AGENTS
#      where a fixture creates agents. This is the no-fail-open property: the
#      guard never goes silent on a run it should ask about. The exceptions are
#      the KNOWN_UNDER fixtures, which pin the documented gaps instead.
#   2. Where #2668 asks, the estimate is below #2668's only for an input listed
#      in LOWERED with the #2668 over-count it corrects, and even then never
#      below the measured count (a template's, which cannot run, is its budget).
#   3. The parse decides (PARSER=acorn) on every input except the listed one
#      acorn rejects; a corpus of fallbacks would test #2668, not the parse.
#   4. Every committed corpus fixture runs under the harness and is costed at
#      exactly its true count, except the two listed in ABOVE, so a change
#      that over-counts is caught as well as one that under-counts.
# It is vacuous unless it ran templates, fixtures over the limit, and at least
# one lowered input.
DIFF_PY=$(
    cat <<'PY'
import concurrent.futures, subprocess, sys

estimator, baseline, truecount, limit = sys.argv[1], sys.argv[2], sys.argv[3], 10

# #2668 multiplied a thunk inside a literal array by the array's length, and
# read a trailing comma as an element. These inputs are costed below its
# figure at their measured count; nothing else may be.
LOWERED = {
    "literal array element run once": """
        literal_4_thunks literal_holding_nested_fanout literal_concat_mapped
        promise_all_map_in_literal_element pipeline_stage_in_literal_element
        returned_thunks_into_parallel_element array_from_in_literal_element
        loop_in_literal_element while_in_literal_element
        method_shorthand_loop_after method_shorthand_map_after class_method_map_after
        getter_loop_after inner_array_thunk_map_after inner_array_thunk_loop_after
        inner_array_recursive_thunk map_returned_thunk_indexed_loop
        map_returned_thunk_indexed_map element_const_arrow_map_after
        element_default_parameter element_forEach_callback element_function_array_for_of
        element_iife_arrow_loop_after element_map_callback element_named_function_map_after
        element_object_arrow_map_after element_pipeline_stage element_then_callback
        element_while_loop method_named_catch method_named_if class_method_named_catch
        method_named_switch_and_with
        setter_assigned_in_loop generator_beside_loop thunk_from_map_indexed_and_called
        blueprint-story-audit.workflow.js verify-before-filing.workflow.js
    """,
    "a trailing comma is not an element": "trailing_comma_mapped",
}
LOWERED = {name: why for why, names in LOWERED.items() for name in names.split()}
TEMPLATE_BUDGET = {"blueprint-story-audit.workflow.js": 20, "verify-before-filing.workflow.js": 49}
EXPECTED_FALLBACK = {"quote_regex_on_proven_parse"}
# Documented fail-opens, pinned so the docs stay true: each is costed at
# ASSUMED (8) where the script states a larger count. Fixing one turns its
# row red on purpose -- then delete it here and from the README's gap list.
KNOWN_UNDER = {
    "known_gap_array_grown_by_index": "an array grown by index is ASSUMED long",
}
# The committed corpus is costed at exactly its true count, so a change that
# over-counts fails too; these are above it by design. Each still fails if it
# drops below its true count, which is what pins the branch it covers.
ABOVE = {
    "enclosing_recursion": "go(8) is entered 9 times; the ninth returns before its 4 agents",
    "window_with_a_site_per_wave": "3 waves of 3 run the plan agent 3 times; the loop is costed at its list, 8",
    "tag_calls_returned_function": "a tag's use of a substitution's result is not followed: ASSUMED calls",
    "set_grown_by_add": "a Set grown by add() is costed at max(source + 1, ASSUMED), as a pushed array is",
    "rest_param_helper_passed_on": "a helper read other than by a plain call has a rest list ASSUMED long",
}
# A call through a callback's array parameter may reach any element, so each
# element is charged every such call: arr[i]() over 2 elements costs 2x (round 11).
for label in """
    element_array_param_index element_array_param_named_map element_array_param_filter
    element_array_param_reduce element_array_param_spread rest_param_array_param_index
""".split():
    ABOVE[label] = "a call through the array parameter is charged to every element"
ABOVE["element_rest_param_collects_array"] = "a rest parameter holding the array is not followed: ASSUMED calls per element"
ABOVE["loop_step_body_resets"] = "a counter the body also writes keeps its stated 20; the body's resets stop at 14"
ABOVE["while_true_stated_break"] = "a break test states 20 plus the pass that meets it; the break comes first"
ABOVE["string_replace_callback"] = "a pattern matches at most once per position: 20 characters, 21 positions"
ABOVE["loop_fractional_step"] = "a fractional step costs one pass more, for runtime rounding"
ABOVE["loop_half_step_over_list"] = "a fractional step costs one pass more, for runtime rounding"
ABOVE["while_true_labeled_break"] = "a break test states 20 plus the pass that meets it; the break comes first"
ABOVE["string_split_regex"] = "a regex split is costed at (length + 1) x (1 + its groups): 20 for 13 pieces"
ABOVE["recursion_unproven_branching"] = "an unproven depth is ASSUMED levels: 2 calls per entry cost 511"
ABOVE["recursion_restarted_elsewhere"] = "an outside call from inside the recursion leaves its depth unproven: 511"
# Round 12 (#2670 review of round 11).
ABOVE["while_true_break_negative_start"] = "a counter moved in its break's own test is counted one pass more: 13 for 12"
ABOVE["string_replace_regexp_object"] = "a pattern matches at most once per position: 20 characters, 21 positions"
ABOVE["string_replace_with_symbol_read"] = "a pattern matches at most once per position: 20 characters, 21 positions"
ABOVE["for_in_prototype_extended"] = "for...in after a prototype gains a key costs max(own keys + 1, ASSUMED) per pass"
for label in "registry_this_computed_dispatch registry_member_store_this_computed class_this_computed_dispatch".split():
    ABOVE[label] = "this[k]() with a key the text does not state may name any key, its own method's too: a recursion"
ABOVE["map_key_forEach_map_param"] = "a call through the Map forEach hands its callback is charged ASSUMED per key"


def rollup(path, script):
    out = subprocess.run([sys.executable, script, str(limit), "8"], stdin=open(path), capture_output=True, text=True).stdout
    return dict(line.split("=", 1) for line in out.splitlines() if "=" in line)


def truth(path):
    try:
        r = subprocess.run(["node", truecount, path], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return None
    out = r.stdout.strip()
    return int(out) if r.returncode == 0 and out.isdigit() else None


def run(item):
    label, path, kind = item
    return label, kind, rollup(path, estimator), rollup(path, baseline), None if kind == "template" else truth(path)


items = [line.split("\t") for line in sys.stdin.read().splitlines() if line]
n = templates = measured = over = lowered = 0
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results = list(pool.map(run, items))
def check(label, kind, live, base, true):
    """Violations for one input, and a one-line account of it."""
    bad = []
    lv, bv = live.get("VERDICT"), base.get("VERDICT")
    # NO_AGENTS carries no ESTIMATE: it is a count of zero.
    le, be = int(live.get("ESTIMATE") or 0), int(base.get("ESTIMATE") or 0)
    if lv not in ("OK", "OVER_LIMIT", "NO_AGENTS"):
        return [f"live VERDICT={lv}"], "", False
    parser = live.get("PARSER")
    if (parser == "acorn") == (label in EXPECTED_FALLBACK):
        bad.append(f"PARSER={parser} FALLBACK={live.get('FALLBACK', '')}")
    if label in KNOWN_UNDER:
        if true is None or le >= true:
            bad.append(f"no longer below its true count ({le} vs {true}): remove it from KNOWN_UNDER and the README")
        return bad, f"known gap, {le} for a true {true}: {KNOWN_UNDER[label]}", False
    if true is not None:
        if lv == "NO_AGENTS" and true > 0:
            bad.append(f"NO_AGENTS, true count {true}")
        elif le < true:
            bad.append(f"estimate {le} below the true count {true}")
        elif kind == "corpus" and le != true and label not in ABOVE:
            bad.append(f"estimate {le} above the true count {true} (corpus fixtures are exact)")
    elif kind == "corpus":
        bad.append("the corpus fixture did not run under truecount.mjs")
    elif lv == "NO_AGENTS" and bv != "NO_AGENTS":
        bad.append(f"NO_AGENTS where #2668 had {bv}/{be}")
    note, low = f"#2668 {be}, true {true if true is not None else '-'}, live {le}", False
    if bv == "OVER_LIMIT" and le < be:
        why = LOWERED.get(label)
        floor = TEMPLATE_BUDGET.get(label, true)
        if why is None:
            bad.append(f"{be} -> {le}, below #2668 and not listed in LOWERED")
        elif floor is None or le < floor or (label in TEMPLATE_BUDGET and le != floor):
            bad.append(f"{be} -> {le}, listed ({why}) but not at its measured count {floor}")
        else:
            note, low = f"#2668 {be} -> live {le}, the true count ({why})", True
    return bad, note, low


for label, kind, live, base, true in results:
    n += 1
    templates += kind == "template"
    measured += true is not None
    over += true is not None and true > limit
    bad, note, low = check(label, kind, live, base, true)
    lowered += low and not bad
    for b in bad:
        print(f"VIOLATION {label}: {b}")
    if not bad:
        print(f"OK {label}: {note}")
print(f"INPUTS={n} TEMPLATES={templates} MEASURED={measured} OVER_LIMIT_TRUE={over} LOWERED={lowered}")
PY
)
REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)
DIFF_INPUTS=$(
    for f in "$FX_DIR"/*.js; do printf '%s\t%s\tfixture\n' "$(basename "$f" .js)" "$f"; done
    for f in "$CORPUS_DIR"/*.js; do printf '%s\t%s\tcorpus\n' "$(basename "$f" .js)" "$f"; done
    if [ -n "$REPO_ROOT" ]; then
        git -C "$REPO_ROOT" ls-files '*/workflows/*.js' | while IFS= read -r rel; do
            printf '%s\t%s\ttemplate\n' "$(basename "$rel")" "$REPO_ROOT/$rel"
        done
    fi
)
DIFF_OUT=$(python3 -c "$DIFF_PY" "$ESTIMATOR" "$BASELINE" "$TRUECOUNT" <<<"$DIFF_INPUTS" 2>&1)
while IFS= read -r line; do
    case "$line" in
        VIOLATION*)
            FAIL=$((FAIL + 1))
            printf '  FAIL  differential: %s\n' "${line#VIOLATION }"
            ;;
        OK*)
            PASS=$((PASS + 1))
            printf '  PASS  differential: %s\n' "${line#OK }"
            ;;
    esac
done <<<"$DIFF_OUT"
d_n=$(sed -n 's/.*INPUTS=\([0-9]*\).*/\1/p' <<<"$DIFF_OUT")
d_t=$(sed -n 's/.*TEMPLATES=\([0-9]*\).*/\1/p' <<<"$DIFF_OUT")
d_m=$(sed -n 's/.*MEASURED=\([0-9]*\).*/\1/p' <<<"$DIFF_OUT")
d_o=$(sed -n 's/.*OVER_LIMIT_TRUE=\([0-9]*\).*/\1/p' <<<"$DIFF_OUT")
d_l=$(sed -n 's/.*LOWERED=\([0-9]*\).*/\1/p' <<<"$DIFF_OUT")
if [ "${d_t:-0}" -gt 0 ] && [ "${d_o:-0}" -gt 0 ] && [ "${d_l:-0}" -gt 0 ] && ! grep -q '^VIOLATION' <<<"$DIFF_OUT"; then
    PASS=$((PASS + 1))
    printf '  PASS  differential held over %d inputs (%d templates, %d measured, %d over the limit, %d lowered to their true count)\n' \
        "$d_n" "$d_t" "$d_m" "$d_o" "$d_l"
elif ! grep -q '^VIOLATION' <<<"$DIFF_OUT"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  differential is vacuous or did not run: %s\n' "$(tail -3 <<<"${DIFF_OUT:-<no output>}")"
fi

echo
echo "== the fallback is the #2668 estimator, figure for figure =="

# When the parse cannot run, the #2668 estimator decides. It asks more than the
# parse on a literal array, and less on loops, recursion and `agent?.()`, which
# it does not see. With node off PATH, every input must report exactly #2668's
# VERDICT and ESTIMATE, name the fallback, and say why.
FALLBACK_PY=$(
    cat <<'PY'
import os, subprocess, sys, tempfile

estimator, baseline = sys.argv[1], sys.argv[2]
nodeless = tempfile.mkdtemp()
n = mismatched = 0
for line in sys.stdin.read().splitlines():
    if not line:
        continue
    label, path, _ = line.split("\t")
    def rollup(script, env=None):
        out = subprocess.run([sys.executable, script, "10", "8"], stdin=open(path), capture_output=True, text=True, env=env).stdout
        return dict(l.split("=", 1) for l in out.splitlines() if "=" in l)
    live = rollup(estimator, {"PATH": nodeless})
    base = rollup(baseline)
    n += 1
    same = all(live.get(k) == base.get(k) for k in ("VERDICT", "ESTIMATE", "SITES"))
    named = live.get("PARSER") == "fallback" and "node not found" in live.get("FALLBACK", "")
    if not (same and named):
        mismatched += 1
        print(f"VIOLATION {label}: nodeless {live.get('VERDICT')}/{live.get('ESTIMATE')} {live.get('PARSER')} vs #2668 {base.get('VERDICT')}/{base.get('ESTIMATE')}")
    else:
        print(f"OK {label}: {base.get('VERDICT')}/{base.get('ESTIMATE', '-')}")
os.rmdir(nodeless)
print(f"FALLBACK_INPUTS={n}")
PY
)
FB_OUT=$(python3 -c "$FALLBACK_PY" "$ESTIMATOR" "$BASELINE" <<<"$DIFF_INPUTS" 2>&1)
while IFS= read -r line; do
    case "$line" in
        VIOLATION*)
            FAIL=$((FAIL + 1))
            printf '  FAIL  fallback: %s\n' "${line#VIOLATION }"
            ;;
        OK*)
            PASS=$((PASS + 1))
            printf '  PASS  fallback without node = #2668: %s\n' "${line#OK }"
            ;;
    esac
done <<<"$FB_OUT"
fb_n=$(sed -n 's/.*FALLBACK_INPUTS=\([0-9]*\).*/\1/p' <<<"$FB_OUT")
if [ "${fb_n:-0}" -gt 0 ] && ! grep -q '^VIOLATION' <<<"$FB_OUT"; then
    PASS=$((PASS + 1))
    printf '  PASS  without node, all %d inputs report the #2668 figure\n' "$fb_n"
elif ! grep -q '^VIOLATION' <<<"$FB_OUT"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  fallback check did not run: %s\n' "${FB_OUT:-<no output>}"
fi

# End to end through the hook, with a `node` that fails first on PATH: the four
# literal thunks the parse costs at 4 (silent) are costed by #2668 at 16, and
# the hook asks. The estimator's own FALLBACK= reason proves the stub is the
# node that ran; without that, a stub PATH lookup skipped would pass silently.
FAKE_BIN=$(mktemp -d) || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
printf '#!/bin/sh\nexit 3\n' >"$FAKE_BIN/node"
chmod +x "$FAKE_BIN/node"
fake_why=$(PATH="$FAKE_BIN:$PATH" python3 "$ESTIMATOR" 10 8 <"$FX_DIR/literal_4_thunks.js" | sed -n 's/^FALLBACK=//p')
out=$(run_hook "$(payload_for "$(<"$FX_DIR/literal_4_thunks.js")")" PATH="$FAKE_BIN:$PATH")
if [[ "$fake_why" == "parser exited 3"* ]] \
    && [ "$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null)" = "ask" ] \
    && [ -z "$(run_hook "$(payload_for "$(<"$FX_DIR/literal_4_thunks.js")")")" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  with a failing node the hook asks where #2668 does (4 thunks: 16), and is silent with a working one\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  failing-node hook did not fall back to asking: reason "%s", output %s\n' "$fake_why" "${out:-<silent>}"
fi
rm -rf "$FAKE_BIN"

# An error inside the analysis falls back too, rather than failing open.
ERR_OUT=$(python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("est", sys.argv[1])
est = importlib.util.module_from_spec(spec)
spec.loader.exec_module(est)
def boom(self, limit):
    raise KeyError("simulated")
est.Analysis.run = boom
r = est.analyze(open(sys.argv[2]).read(), 10, 8)
print(r.get("PARSER"), r.get("ESTIMATE"), r.get("FALLBACK"))
' "$ESTIMATOR" "$FX_DIR/literal_4_thunks.js" 2>&1)
if [[ "$ERR_OUT" == "fallback 16 analysis error (KeyError)"* ]]; then
    PASS=$((PASS + 1))
    printf '  PASS  an analysis error is costed by #2668 (16), not reported as ERROR\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  analysis error did not fall back: %s\n' "$ERR_OUT"
fi

# The fallback and the oracle are one frozen file. Pin it: an edit that made
# #2668 ask less would weaken the fallback and move the baseline in one go.
BASELINE_SHA=f7086551844fa8dcf9408f9fc91980d58220a490fdedc2acf25c5660b03f0945
got_sha=$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$BASELINE")
if [ "$got_sha" = "$BASELINE_SHA" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  the #2668 estimator is unchanged (sha256 pinned)\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  lib/workflow-scale-estimate-2668.py changed: sha256 %s\n' "$got_sha"
fi
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
# A repetition costed at HIGH is named in the reason, with the figure it got.
OUT=$(run_hook "$(payload_for 'while (true) { const r = await agent("poll"); if (r.verdict) break }')")
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1 \
   && printf '%s' "$OUT" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("nothing in the text bounds: a while loop whose test is always true[[:space:]]+[(]costed at 11, one over the limit[)]")' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
    printf '  PASS  reason names a repetition nothing bounds and its HIGH figure\n'
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  reason does not name the HIGH repetition: %s\n' "$OUT"
fi

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
