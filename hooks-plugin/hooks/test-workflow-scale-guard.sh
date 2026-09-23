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
echo "== an unproven parse falls back to the #2668 scan (#2670 review) =="

# The walk above reads ${...} interpolations as code, and code holds things a
# quote-and-brace scanner cannot parse -- chiefly a regex literal. `/'/g` inside
# an interpolation opened a quote that never closed, blanked the rest of the
# file, and the hook went SILENT on a 32-agent pipeline that #2668 asked about.
# The walk is now used only when it proves itself. Each case below is rejected
# by exactly one check, names it, and reports the #2668 figure, because the
# #2668 scan decided. Removing any one check turns its case red.
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
# Control: the shape the walk exists for still proves itself.
fx nested_template_proves_itself <<'EOF'
const P = (c) => `head ${
  c ? `the skill's file` : `none`
} tail`
await pipeline(args.units, u => agent('edit'), e => agent('review'), r => agent('repair'), s => agent('rereview'))
EOF
# The four checks prove the walk kept every token that COUNTS, not every token
# that BOUNDS. A `{` regex in one template and a `}` regex in a later one keep
# the span between them inside one template: literals close, brackets balance,
# no agent()/fan-out token is lost -- and the declaration of `items` is
# blanked, so the fan-out costs 8 instead of 12 and the hook went silent
# (#2670 review, round 3). No list of checks is complete, so the estimator now
# costs both readings and keeps the higher: the flat scan decides here.
fx brace_pair_blanks_bound <<'EOF'
const open = (s) => `g ${s.replace(/{/g, "(")} h`;
const items = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const close = (s) => `e ${s.replace(/}/g, ")")} f`;
await parallel(items.map((i) => () => agent(open(i) + close(i))));
EOF
# The same pair around a pipeline source. Here the blanked declaration makes the
# structural reading HIGHER (unbounded, 2 x 8 = 16 against 2 x 6 = 12), and the
# higher reading decides whichever scan produced it.
fx brace_pair_raises_pipeline <<'EOF'
const open = (s) => `g ${s.replace(/{/g, "(")} h`;
const units = [1, 2, 3, 4, 5, 6];
const close = (s) => `e ${s.replace(/}/g, ")")} f`;
await pipeline(units, (u) => agent(open(u)), (u) => agent(close(u)));
EOF

assert_asks "regex holding ' inside \${...} still asks" "$(<"$FX_DIR/regex_squote_in_interp.js")"
assert_asks "regex holding \" inside \${...} still asks" "$(<"$FX_DIR/regex_dquote_in_interp.js")"
assert_asks "templates merged across a pipeline still ask" "$(<"$FX_DIR/brace_regex_blanks_calls.js")"
assert_asks "brace-regex pair around a bounding declaration still asks" "$(<"$FX_DIR/brace_pair_blanks_bound.js")"
assert_asks "brace-regex pair around a pipeline source still asks" "$(<"$FX_DIR/brace_pair_raises_pipeline.js")"

# assert_parse <desc> <estimate> <sanitizer> <fallback-substring> <fixture>
assert_parse() {
    local desc="$1" want_est="$2" want_mode="$3" want_why="$4" out est mode why ok=1
    out=$(python3 "$ESTIMATOR" 10 8 <"$FX_DIR/$5.js" 2>/dev/null)
    est=$(sed -n 's/^ESTIMATE=//p' <<<"$out")
    mode=$(sed -n 's/^SANITIZER=//p' <<<"$out")
    why=$(sed -n 's/^FALLBACK=//p' <<<"$out")
    [ "$est" = "$want_est" ] && [ "$mode" = "$want_mode" ] || ok=0
    if [ -z "$want_why" ]; then
        [ -z "$why" ] || ok=0
    else
        [[ "$why" == *"$want_why"* ]] || ok=0
    fi
    if [ "$ok" -eq 1 ]; then
        PASS=$((PASS + 1))
        printf '  PASS  ESTIMATE=%s SANITIZER=%s: %s\n' "$want_est" "$want_mode" "$desc"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL  expected %s/%s/"%s", got %s/%s/"%s": %s\n' \
            "$want_est" "$want_mode" "$want_why" "${est:-<none>}" "${mode:-<none>}" "$why" "$desc"
    fi
}

assert_parse "quoted string reaching a newline (')"  32 flat "quoted string crosses a newline" regex_squote_in_interp
assert_parse "quoted string reaching a newline (\")" 16 flat "quoted string crosses a newline" regex_dquote_in_interp
assert_parse "literal reaching end of file"          8  flat "runs to end of file"             literal_runs_to_eof
assert_parse "code left with unbalanced brackets"    8  flat "brackets do not balance"         brace_regex_blanks_parens
assert_parse "code token the #2668 scan kept"        16 flat "would blank the code token"      brace_regex_blanks_calls
assert_parse "nested template walked structurally"   32 structural "" nested_template_proves_itself
assert_parse "proven walk blanks a bound: flat is higher" 12 flat "flat scan costs it higher" brace_pair_blanks_bound
assert_parse "proven walk is the higher reading"         16 structural "" brace_pair_raises_pipeline

echo
echo "== differential against the #2668 estimator (#2670 review) =="

# The live estimator may cost a script LOWER than #2668 did only where the
# lower figure is the correct count, listed here; it may never report NO_AGENTS
# where #2668 found agents. Every bundled template is compared, plus shapes a
# review built to break the sanitizer. Raising an estimate is always allowed.
BASELINE="$(dirname "$0")/fixtures/workflow-scale-estimate-2668.py"

# correct_count <input> — the true agent count for an input whose live figure
# is below #2668's (a runtime-length list costed at 8, as both estimators do).
correct_count() {
    case "$1" in
        literal_4_thunks) echo 4 ;;               # four thunks, each run once
        literal_holding_nested_fanout) echo 9 ;;  # 8 for the inner map + 1
        literal_concat_mapped) echo 9 ;;          # 1 + 8
        blueprint-story-audit.workflow.js) echo 20 ;;
        verify-before-filing.workflow.js) echo 49 ;;
        *) echo none ;;
    esac
}

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

DIFF_N=0
DIFF_LOWERED=0
# diff_one <label> <file>
diff_one() {
    local label="$1" file="$2" base live bv be lv le want
    base=$(python3 "$BASELINE" 10 8 <"$file" 2>/dev/null)
    live=$(python3 "$ESTIMATOR" 10 8 <"$file" 2>/dev/null)
    bv=$(sed -n 's/^VERDICT=//p' <<<"$base")
    be=$(sed -n 's/^ESTIMATE=//p' <<<"$base")
    lv=$(sed -n 's/^VERDICT=//p' <<<"$live")
    le=$(sed -n 's/^ESTIMATE=//p' <<<"$live")
    DIFF_N=$((DIFF_N + 1))
    case "$lv" in
        OK | OVER_LIMIT | NO_AGENTS) : ;;
        *)
            FAIL=$((FAIL + 1))
            printf '  FAIL  differential: %s: live VERDICT=%s\n' "$label" "${lv:-<none>}"
            return
            ;;
    esac
    if [ "$lv" = "NO_AGENTS" ] && [ "$bv" != "NO_AGENTS" ]; then
        FAIL=$((FAIL + 1))
        printf '  FAIL  differential: %s: live NO_AGENTS where #2668 had %s/%s\n' "$label" "$bv" "$be"
        return
    fi
    if [ "${le:-0}" -lt "${be:-0}" ]; then
        want=$(correct_count "$label")
        if [ "$le" = "$want" ]; then
            DIFF_LOWERED=$((DIFF_LOWERED + 1))
            PASS=$((PASS + 1))
            printf '  PASS  differential: %s: %s -> %s, the correct count\n' "$label" "$be" "$le"
        else
            FAIL=$((FAIL + 1))
            printf '  FAIL  differential: %s: %s -> %s, below #2668 and not the listed count (%s)\n' \
                "$label" "$be" "$le" "$want"
        fi
        return
    fi
    PASS=$((PASS + 1))
    printf '  PASS  differential: %s: %s/%s -> %s/%s\n' "$label" "${bv}" "${be:--}" "${lv}" "${le:--}"
}

for f in "$FX_DIR"/*.js; do
    diff_one "$(basename "$f" .js)" "$f"
done

REPO_ROOT=$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)
N_TEMPLATES=0
if [ -n "$REPO_ROOT" ]; then
    while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        N_TEMPLATES=$((N_TEMPLATES + 1))
        diff_one "$(basename "$rel")" "$REPO_ROOT/$rel"
    done < <(git -C "$REPO_ROOT" ls-files '*/workflows/*.js')
fi

# Non-vacuous: a differential over nothing is green by construction.
if [ "$N_TEMPLATES" -gt 0 ] && [ "$DIFF_LOWERED" -gt 0 ] && [ -f "$BASELINE" ]; then
    PASS=$((PASS + 1))
    printf '  PASS  differential covered %d inputs (%d bundled templates), %d at a lower correct count\n' \
        "$DIFF_N" "$N_TEMPLATES" "$DIFF_LOWERED"
else
    FAIL=$((FAIL + 1))
    printf '  FAIL  differential is vacuous: %d templates, %d lowered, baseline %s\n' \
        "$N_TEMPLATES" "$DIFF_LOWERED" "$([ -f "$BASELINE" ] && echo present || echo missing)"
fi

echo
echo "== property: never below the flat reading (#2670 review, round 3) =="

# Three review rounds each found code the structural walk blanked that its
# proof checks missed. analyze() therefore costs the #2668 flat scan too and
# keeps the higher figure. This asserts that property directly, per input:
# the reported ESTIMATE is at least what the SAME analysis gives on the
# flat-sanitized text (NO_AGENTS ranks below any estimate). It is non-vacuous
# only if some input's proven structural reading is strictly LOWER than its
# flat reading -- the case the maximum exists for -- and a template was read.
# The program is passed with -c: `python3 -` would read it from the same stdin
# that carries the file list, and the list would be lost.
PROP_PY=$(
    cat <<'PY'
import importlib.util, sys

spec = importlib.util.spec_from_file_location("est", sys.argv[1])
est = importlib.util.module_from_spec(spec)
spec.loader.exec_module(est)

def rank(r):
    return r.get("ESTIMATE", -1)

n = templates = lower = 0
for path in sys.stdin.read().split("\n"):
    if not path:
        continue
    src = open(path, encoding="utf-8").read()
    n += 1
    templates += path.endswith(".workflow.js")
    live = est.analyze(src, 10, 8)
    flat = est.estimate_text(est._flat_sanitize(src), src, 10, 8)
    text, mode, _ = est.sanitize(src)
    if mode == "structural" and rank(est.estimate_text(text, src, 10, 8)) < rank(flat):
        lower += 1
    if rank(live) < rank(flat):
        print(f"VIOLATION {path.rsplit('/', 1)[-1]} live={rank(live)} flat={rank(flat)}")
print(f"INPUTS={n} TEMPLATES={templates} STRUCTURAL_LOWER={lower}")
PY
)
PROP_OUT=$(
    {
        for f in "$FX_DIR"/*.js; do printf '%s\n' "$f"; done
        [ -n "$REPO_ROOT" ] && git -C "$REPO_ROOT" ls-files '*/workflows/*.js' | sed "s|^|$REPO_ROOT/|"
    } | python3 -c "$PROP_PY" "$ESTIMATOR" 2>&1
)
while IFS= read -r line; do
    case "$line" in
        VIOLATION*)
            FAIL=$((FAIL + 1))
            printf '  FAIL  property: %s\n' "${line#VIOLATION }"
            ;;
    esac
done <<<"$PROP_OUT"
prop_n=$(sed -n 's/.*INPUTS=\([0-9]*\).*/\1/p' <<<"$PROP_OUT")
prop_t=$(sed -n 's/.*TEMPLATES=\([0-9]*\).*/\1/p' <<<"$PROP_OUT")
prop_l=$(sed -n 's/.*STRUCTURAL_LOWER=\([0-9]*\).*/\1/p' <<<"$PROP_OUT")
if [ "${prop_t:-0}" -gt 0 ] && [ "${prop_l:-0}" -gt 0 ] && ! grep -q '^VIOLATION' <<<"$PROP_OUT"; then
    PASS=$((PASS + 1))
    printf '  PASS  property held over %d inputs (%d templates); %d had a lower structural reading\n' \
        "$prop_n" "$prop_t" "$prop_l"
elif ! grep -q '^VIOLATION' <<<"$PROP_OUT"; then
    FAIL=$((FAIL + 1))
    printf '  FAIL  property is vacuous or did not run: %s\n' "${PROP_OUT:-<no output>}"
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

echo
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
