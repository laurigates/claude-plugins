#!/usr/bin/env bash
# test-config-drift.sh — regression suite for health-plugin/scripts/config-drift.py
#
# SEMANTIC, not syntactic: every case EXECUTES the analyzer against a planted
# fixture corpus and asserts on its structured output. A grep for a threshold
# constant or a function name would pass against a checker that never runs --
# the #1417 -> #1819 lesson (a syntactic pin on a semantic property let a
# non-working command ship twice).
#
# Isolation: HOME is redirected to the fixture root, so the suite reads the
# fixture's ~/.claude/rules and writes its caches there, never the real ones.
# Every case runs --fast, so the analyzer spawns no git at all and the
# shared-checkout git hazards (#1692/#1745) cannot arise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANALYZER="${SCRIPTS_DIR}/config-drift.py"
PROBE_MODULE="${SCRIPTS_DIR}/lib/probe.py"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available"
    exit 0
fi
if [ ! -f "$ANALYZER" ]; then
    echo "FAIL: analyzer not found at $ANALYZER"
    exit 1
fi
if [ ! -f "$PROBE_MODULE" ]; then
    echo "FAIL: probe module not found at $PROBE_MODULE"
    exit 1
fi

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     wanted: %s\n     got:    %s\n' "$1" "$2" "$3"; }

# if/else, not `A && B || C` — in an assertion helper the short-circuit form
# runs `bad` whenever `ok` returns non-zero, which silently double-reports.
assert_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$3" "$2"; fi
}
assert_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) bad "$1" "output containing '$3'" "$(printf '%s' "$2" | head -c 200)" ;;
    esac
}
assert_ge() {
    if [ "${2:-0}" -ge "$3" ] 2>/dev/null; then ok "$1 ($2)"; else bad "$1" ">=$3" "${2:-<empty>}"; fi
}
assert_not_contains() {
    case "$2" in
        *"$3"*) bad "$1" "output WITHOUT '$3'" "$(printf '%s' "$2" | head -c 200)" ;;
        *) ok "$1" ;;
    esac
}

# --- fixture corpus -------------------------------------------------------
FIXROOT=$(mktemp -d)
if [ -z "$FIXROOT" ] || [ ! -d "$FIXROOT" ]; then
    echo "FAIL: could not create fixture root"
    exit 1
fi
trap 'rm -rf "$FIXROOT"' EXIT

mkdir -p "$FIXROOT/home/.claude/rules"
mkdir -p "$FIXROOT/proj/repo-a/.claude/rules"
mkdir -p "$FIXROOT/proj/repo-b/.claude/rules"
mkdir -p "$FIXROOT/proj/some-plugin/skills/widget-wrangling"

cat > "$FIXROOT/proj/some-plugin/skills/widget-wrangling/SKILL.md" <<'SKILL'
---
name: widget-wrangling
description: Wrangle widgets across the fleet. Use when calibrating widget torque or auditing widget inventory.
---
# widget-wrangling
Calibrating widget torque requires the fleet inventory. Audit widget torque
calibration across every widget in the inventory before adjusting any widget.
SKILL

run() { python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json 2>/dev/null; }
run_status() { python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=status 2>/dev/null; }
count_kind() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for f in d["findings"] if f["kind"]==sys.argv[1]))' "$2" 2>/dev/null || echo ERR; }
count_key()  { printf '%s' "$1" | python3 -c 'import json,sys; print(json.load(sys.stdin)["counts"][sys.argv[1]])' "$2" 2>/dev/null || echo ERR; }

export HOME="$FIXROOT/home"

echo "TEST 1: empty corpus is OK, not an error"
out=$(run_status)
assert_contains "empty corpus reports STATUS=OK" "$out" "STATUS=OK"
python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=status >/dev/null 2>&1
assert_eq "empty corpus exits 0" "$?" "0"

echo "TEST 2: duplicate rules across scopes (three-point ladder)"
# A checker that reports a duplicate unconditionally, or never, passes only one
# of these three rungs.
cat > "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" <<'RULE'
# Alpha
The torque calibration procedure requires the fleet inventory manifest before
any widget adjustment is attempted on the assembly line.
RULE
out=$(run)
assert_eq "one rule, no duplicate reported" "$(count_kind "$out" duplicate_rule_lexical)" "0"

cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
out=$(run)
assert_eq "identical rule in a second scope is reported once" "$(count_kind "$out" duplicate_rule_lexical)" "1"

rm "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
out=$(run)
assert_eq "removing the copy clears the finding" "$(count_kind "$out" duplicate_rule_lexical)" "0"

echo "TEST 3: waiver suppresses, and expires when either side changes"
cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
hash_of() { python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],encoding="utf-8").read().encode()).hexdigest()[:16])' "$1"; }
ha=$(hash_of "$FIXROOT/proj/repo-a/.claude/rules/alpha.md")
hb=$(hash_of "$FIXROOT/proj/repo-b/.claude/rules/beta.md")
WAIVERS="$FIXROOT/waivers.json"
python3 - "$WAIVERS" "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$ha" "$FIXROOT/proj/repo-b/.claude/rules/beta.md" "$hb" <<'PY'
import json, sys
p, a, ha, b, hb = sys.argv[1:6]
json.dump({"waivers": [{"a": a, "b": b, "a_hash": ha, "b_hash": hb,
                        "reason": "deliberate for the test"}]}, open(p, "w"))
PY
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json --waivers "$WAIVERS" 2>/dev/null)
assert_eq "waived pair is suppressed" "$(count_kind "$out" duplicate_rule_lexical)" "0"

# Backups by cp, never by command substitution: `$(...)` strips trailing
# newlines, so a restored file would differ by one byte from the hash the
# waiver recorded -- and this test's whole subject is byte-level hashes.
cp "$FIXROOT/proj/repo-b/.claude/rules/beta.md" "$FIXROOT/beta.orig"
cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$FIXROOT/alpha.orig"

printf '\nAn edit that changes the content.\n' >> "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json --waivers "$WAIVERS" 2>/dev/null)
assert_eq "editing the b side revives the finding" "$(count_kind "$out" duplicate_rule_lexical)" "1"

# EITHER side, not just the one the waiver happens to list first. Restoring b
# and editing a instead must revive it too -- without this rung, a waiver that
# only ever checked its `a_hash` would pass the test above.
cp "$FIXROOT/beta.orig" "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json --waivers "$WAIVERS" 2>/dev/null)
assert_eq "restoring the b side re-suppresses (guard integrity)" "$(count_kind "$out" duplicate_rule_lexical)" "0"

printf '\nAn edit on the OTHER side.\n' >> "$FIXROOT/proj/repo-a/.claude/rules/alpha.md"
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json --waivers "$WAIVERS" 2>/dev/null)
assert_eq "editing the a side revives the finding too" "$(count_kind "$out" duplicate_rule_lexical)" "1"

cp "$FIXROOT/alpha.orig" "$FIXROOT/proj/repo-a/.claude/rules/alpha.md"
rm "$FIXROOT/proj/repo-b/.claude/rules/beta.md"

echo "TEST 4: pointer-stub integrity"
cat > "$FIXROOT/home/.claude/rules/widget-stuff.md" <<'RULE'
# Widget Stuff

Promoted to a skill: invoke `widget-wrangling` before calibrating widget
torque — it carries the fleet inventory procedure.
RULE
out=$(run)
assert_eq "a stub naming a real skill is not flagged" "$(count_kind "$out" broken_pointer_stub)" "0"

cat > "$FIXROOT/home/.claude/rules/ghost-stuff.md" <<'RULE'
# Ghost Stuff

Promoted to a skill: invoke `no-such-skill-anywhere` before doing the thing —
it carries the whole procedure.
RULE
out=$(run)
assert_eq "a stub naming a missing skill is an error" "$(count_kind "$out" broken_pointer_stub)" "1"
python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --gate --format=status >/dev/null 2>&1
assert_eq "--gate exits 2 on a broken stub" "$?" "2"
rm "$FIXROOT/home/.claude/rules/ghost-stuff.md"

# The false positive this check actually produced in use: the stub's TITLE
# carries an incidental backticked term, and "first backticked token" picked
# that instead of the delegation target. Verbatim shape of the real stub.
cat > "$FIXROOT/home/.claude/rules/titled-stuff.md" <<'RULE'
# Git-Based `uvx` Widget Servers Serve a Stale Cached Commit

Promoted to a skill: invoke `some-plugin:widget-wrangling` when a widget
server appears to run stale code — it carries the whole recipe.
RULE
out=$(run)
assert_eq "a backticked term in the title does not win over the invoke target" \
    "$(count_kind "$out" broken_pointer_stub)" "0"

# Guard integrity: the fix must not resolve EVERYTHING to something valid.
# Same title shape, but the invoke target is genuinely missing.
cat > "$FIXROOT/home/.claude/rules/titled-broken.md" <<'RULE'
# Git-Based `uvx` Widget Servers Serve a Stale Cached Commit

Promoted to a skill: invoke `some-plugin:no-such-skill-at-all` when a widget
server appears to run stale code — it carries the whole recipe.
RULE
out=$(run)
assert_eq "a broken invoke target is still caught despite a resolvable title term" \
    "$(count_kind "$out" broken_pointer_stub)" "1"
rm "$FIXROOT/home/.claude/rules/titled-stuff.md" "$FIXROOT/home/.claude/rules/titled-broken.md"

echo "TEST 5: path-scoped rules are not counted as always-loaded"
# The bug this pins: `paths:` parses to an EMPTY string value (its globs are on
# following lines), so a truthiness test silently counts every scoped rule as
# unconditional -- a ~24% over-count on the real corpus.
cat > "$FIXROOT/home/.claude/rules/scoped.md" <<'RULE'
---
created: 2026-01-01
modified: 2026-01-01
paths:
  - "**/*.tf"
---
# Scoped
Terraform state locking behaves differently under a remote backend, and the
lock is not released when the process is killed mid-apply.
RULE
out=$(run)
scoped_tokens=$(count_key "$out" always_loaded_tokens)
rm "$FIXROOT/home/.claude/rules/scoped.md"
out=$(run)
unscoped_tokens=$(count_key "$out" always_loaded_tokens)
assert_eq "a paths:-scoped rule adds nothing to the always-loaded budget" "$scoped_tokens" "$unscoped_tokens"

echo "TEST 6: guard integrity — the corpus is actually being read"
# Without this, every 'not flagged' assertion above would also pass against an
# analyzer that discovered nothing at all.
out=$(run)
rules=$(count_key "$out" rules)
skills=$(count_key "$out" skills)
assert_ge "fixture rules were discovered" "$rules" 2
assert_ge "fixture skills were discovered" "$skills" 1
assert_contains "semantic pass is reported off under --no-embed" "$(run_status)" "SEMANTIC_PASS=off"

echo "TEST 7: --fast spawns no git"
# Proven by putting a poisoned `git` first on PATH: if the analyzer shells out,
# the marker file appears.
GITDIR="$FIXROOT/fakebin"
mkdir -p "$GITDIR"
cat > "$GITDIR/git" <<'STUB'
#!/usr/bin/env bash
touch "$GIT_CALLED_MARKER"
exit 0
STUB
chmod +x "$GITDIR/git"
export GIT_CALLED_MARKER="$FIXROOT/git-was-called"
rm -f "$GIT_CALLED_MARKER"
PATH="$GITDIR:$PATH" python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=status >/dev/null 2>&1
if [ ! -f "$GIT_CALLED_MARKER" ]; then
    ok "--fast never invokes git"
else
    bad "--fast never invokes git" "no git call" "git was invoked"
fi

echo "TEST 8: unknown argument is rejected, not swallowed"
if python3 "$ANALYZER" --root "$FIXROOT/proj" --no-such-flag >/dev/null 2>&1; then
    bad "unknown flag exits non-zero" "non-zero exit" "exit 0"
else
    ok "unknown flag exits non-zero"
fi

echo "TEST 9: guard integrity -- nothing indented or list-shaped is a top-level key"
# What this case pins is the GUARD, not either named bug. Both decoys below are
# indented, and the original `^([a-z_]+):` anchor already rejected indented
# lines, so this case contributes zero regression protection for the
# block-scalar or `paths:` defects: run the whole suite against the pre-fix
# parser and it reports PASSED=26 FAILED=4, with all four failures in TEST 10.
# What it does kill, measured by mutating the shipped parser: 9b fails (2
# assertions) against a parser that strips a leading `- ` before matching. 9a is
# shielded twice -- by the column-0 anchor AND by the block-slurp loop that
# consumes those lines before the key matcher ever sees them -- so a bare
# lstrip() mutant passes the whole suite 51/51, and 9a only fires once the block
# indicator ALSO stops matching (lstrip + a dead FM_BLOCK fails 9a, 9b, and four
# of TEST 10).
#
# Two frontmatter keys have a consequence in --format=json that a parser change
# can actually move: `paths` (key presence -> always_loaded_rules /
# always_loaded_tokens) and `reviewed` (value truthiness -> the
# frontmatter_coverage numerator). Every case below is expressed through one of
# those two.
missing_reviewed() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); s=next((f["summary"] for f in d["findings"] if f["kind"]=="frontmatter_coverage"), "0/0"); print(s.split("/")[0])' 2>/dev/null || echo ERR; }

out=$(run)
base_rules=$(count_key "$out" always_loaded_rules)
base_missing=$(missing_reviewed "$out")

# 9a. GUARD INTEGRITY: nothing inside a block-scalar body is a top-level key.
# The body carries a `paths:` line and a `reviewed:` line at block indentation
# plus a list item. A parser that read either would (a) drop this rule from the
# always-loaded set and (b) stop counting it as missing a reviewed: date.
cat > "$FIXROOT/home/.claude/rules/blockscalar.md" <<'RULE'
---
created: 2026-01-01
description: |
  Calibrate widget torque against the fleet inventory manifest. Use when a
  widget reports a torque fault on the assembly line.
  paths: "**/*.tf"
  reviewed: 2026-01-01
  - "**/*.tfvars"
---
# Block Scalar
Two lines of the block-scalar body above look like top-level keys and one looks
like a list item. None of them is a key.
RULE
out=$(run)
assert_eq "a paths: line inside a block-scalar body does not scope the rule" \
    "$(count_key "$out" always_loaded_rules)" "$((base_rules + 1))"
assert_eq "a reviewed: line inside a block-scalar body is not captured" \
    "$(missing_reviewed "$out")" "$((base_missing + 1))"

# NOTE: the POSITIVE half -- that a block scalar's BODY is extracted rather
# than the empty string after the indicator -- has no assertion here, because
# it has no observable consequence in --format=json. NOT because `description`
# has no consumer: config-drift.py's containment metric builds a token set from
# `name + desc + body[:6000]`. The conclusion survives for a different reason --
# a skill's `body` is the WHOLE file including its frontmatter, so tokens(desc)
# is always a subset of tokens(body) and the union cannot move however desc is
# parsed. `reviewed:` is the only key whose value reaches the output on its own,
# and only through a truthiness test; the pre-fix parser captured the literal
# `|`, which is truthy, so an assertion phrased that way passes against the bug
# (verified by running this suite against the pre-fix parser). The positive half
# is pinned in TEST 10 instead.

# 9b. GUARD INTEGRITY: a flush-left YAML list item is not a key either. If the
# leading `- ` were stripped before matching, both decoys below would land.
cat > "$FIXROOT/home/.claude/rules/listitem.md" <<'RULE'
---
created: 2026-01-01
tags:
- reviewed: 2026-01-01
- paths: "**/*.tf"
---
# List Item
A flush-left list whose items are shaped exactly like top-level keys.
RULE
out=$(run)
assert_eq "a flush-left list item does not scope the rule" \
    "$(count_key "$out" always_loaded_rules)" "$((base_rules + 2))"
assert_eq "a flush-left list item is not captured as reviewed:" \
    "$(missing_reviewed "$out")" "$((base_missing + 2))"

# 9c. paths: still parses such that the KEY is present -- the constraint the
# block-scalar fix had to preserve. This is TEST 5's invariant restated as a
# rule count, so a scoped rule and an unscoped one are asserted in one pass.
# Its blind spot, and TEST 5's: consumers read KEY PRESENCE, so the naive fix
# (slurp the indented lines under any empty value) leaves `paths` present with
# a glob-list value and passes both. That the value stays "" is pinned in
# TEST 10, which is the only case that fails against that mutation.
before_rules=$(count_key "$out" always_loaded_rules)
before_tokens=$(count_key "$out" always_loaded_tokens)
cat > "$FIXROOT/home/.claude/rules/scoped-again.md" <<'RULE'
---
created: 2026-01-01
paths:
  - "**/*.tf"
---
# Scoped Again
Terraform state locking behaves differently under a remote backend, and the
lock is not released when the process is killed mid-apply.
RULE
out=$(run)
assert_eq "fm still carries the paths KEY (scoped rule is not always-loaded)" \
    "$(count_key "$out" always_loaded_rules)" "$before_rules"
assert_eq "a paths:-scoped rule still adds nothing to the token budget" \
    "$(count_key "$out" always_loaded_tokens)" "$before_tokens"
rm "$FIXROOT/home/.claude/rules/scoped-again.md" \
   "$FIXROOT/home/.claude/rules/blockscalar.md" \
   "$FIXROOT/home/.claude/rules/listitem.md"

echo "TEST 10: widened key pattern -- executed directly, see note"
# `allowed-tools`, `argument-hint` and `maxTurns` have NO consumer inside the
# analyzer. `description` does have one even under --no-embed -- the containment
# metric's token set at config-drift.py's `tset(name + desc + body[:6000])` --
# but a skill's body is the whole file including its frontmatter, so tokens(desc)
# is a subset of tokens(body) and no parse of it can move the token set. Nothing
# in --format=json output changes when any of these are captured, so there is no
# consequence to assert on and none is invented here. This case instead loads
# the SHIPPED frontmatter() out of the analyzer file and feeds it real input --
# still semantic (the real function, real frontmatter), never a grep for a name.
fm_get() {
    python3 - "$ANALYZER" "$1" "$2" <<'PYFM'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("config_drift", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.frontmatter(sys.argv[2]).get(sys.argv[3], "<absent>"))
PYFM
}

FM_BODY='---
name: widget-wrangling
allowed-tools: Bash, Read
argument-hint: "[flags]"
maxTurns: 5
description: |
  Wrangle widgets across the fleet.
  reviewed: 2026-01-01
paths:
  - "**/*.tf"
---
# widget-wrangling
'
assert_eq "a hyphenated key is captured" "$(fm_get "$FM_BODY" allowed-tools)" "Bash, Read"
assert_eq "a second hyphenated key is captured and unquoted" "$(fm_get "$FM_BODY" argument-hint)" "[flags]"
assert_eq "a camelCase key is captured" "$(fm_get "$FM_BODY" maxTurns)" "5"
assert_eq "a block-scalar body is joined, not left empty" \
    "$(fm_get "$FM_BODY" description)" "Wrangle widgets across the fleet. reviewed: 2026-01-01"
assert_eq "paths: after a block scalar is present and empty" "$(fm_get "$FM_BODY" paths)" ""
# `reviewed` is a key a real document carries and this fixture does NOT declare
# at top level, so an implementation that read the indented decoy line would
# emit it. The former decoy asserted on `not-a-key` -- the VALUE of the decoy
# line, a name no implementation could ever emit -- so it passed against
# `def frontmatter(b): return {}`, and even a parser that DID read the indented
# line would have had `paths` overwritten two lines later by the real column-0
# key, leaving the property unobservable.
assert_eq "a block-scalar body line is not a top-level key" "$(fm_get "$FM_BODY" reviewed)" "<absent>"

# D4. `raw.strip("\"'")` strips a character CLASS from both ends, not a matched
# pair, so a value that merely ENDS in a quote character loses it. Both bodies
# below are the verbatim frontmatter lines of live skills:
# agent-patterns-plugin/skills/adversarial-review (trailing ') and
# git-plugin/skills/git-api-pr (a matched '...' pair whose last inner character
# is a " that the class strip then eats as well).
FM_TRAILING_QUOTE='---
name: adversarial-review
argument-hint: path|PR|file|plan description; optional '"'"'focus on X'"'"'
---
# adversarial-review
'
assert_eq "an unmatched trailing quote survives" \
    "$(fm_get "$FM_TRAILING_QUOTE" argument-hint)" "path|PR|file|plan description; optional 'focus on X'"

FM_NESTED_QUOTE='---
name: git-api-pr
argument-hint: '"'"'<files...> --title "type(scope): description"'"'"'
---
# git-api-pr
'
assert_eq "only the matched outer pair is stripped, not the quote beneath it" \
    "$(fm_get "$FM_NESTED_QUOTE" argument-hint)" '<files...> --title "type(scope): description"'

# D5. A plain scalar continued over indented lines. Verbatim from
# git-plugin/skills/git-derive-docs/SKILL.md:5-7 -- the widened key regex turned
# "key absent" into "key present but truncated, with a dangling comma", which is
# worse, because the fragment reads as a complete value.
FM_CONTINUATION='---
name: git-derive-docs
allowed-tools: Bash(bash *), Bash(git log *),
               Bash(git show *), Bash(git rev-list *),
               Read, Grep, Glob
description: A short one-line description.
paths:
  - "**/*.tf"
---
# git-derive-docs
'
assert_eq "a multi-line plain scalar is joined, not truncated at the first line" \
    "$(fm_get "$FM_CONTINUATION" allowed-tools)" \
    "Bash(bash *), Bash(git log *), Bash(git show *), Bash(git rev-list *), Read, Grep, Glob"
# Guard integrity for D5: absorbing continuations must not swallow the NEXT
# top-level key, and must not turn `paths:` (bare-empty, followed by `- ` list
# items) into its glob list -- the constraint TEST 5 and TEST 9c pin from the
# analyzer side.
assert_eq "continuation absorption stops at the next top-level key" \
    "$(fm_get "$FM_CONTINUATION" description)" "A short one-line description."
assert_eq "continuation absorption does not swallow a paths: list" \
    "$(fm_get "$FM_CONTINUATION" paths)" ""

# D6. A block indicator may carry a chomping sign, an explicit indentation
# digit, and a trailing comment. Exact-set membership recognised only the six
# bare spellings, so `|2` and `| # notes` were captured as VALUES -- truthy
# junk, the original bug's shape wearing a different string.
FM_INDICATOR_DIGIT='---
name: widget-wrangling
description: |2
  Wrangle widgets across the fleet.
paths:
  - "**/*.tf"
---
# widget-wrangling
'
assert_eq "an explicit-indentation indicator is not captured as the value" \
    "$(fm_get "$FM_INDICATOR_DIGIT" description)" "Wrangle widgets across the fleet."

FM_INDICATOR_COMMENT='---
name: widget-wrangling
description: | # keep the line breaks
  Wrangle widgets across the fleet.
paths:
  - "**/*.tf"
---
# widget-wrangling
'
assert_eq "a commented indicator is not captured as the value" \
    "$(fm_get "$FM_INDICATOR_COMMENT" description)" "Wrangle widgets across the fleet."
assert_eq "a commented indicator still leaves paths: present and empty" \
    "$(fm_get "$FM_INDICATOR_COMMENT" paths)" ""

# D8. A comment line is never scalar content. Absorbing it as a continuation
# appended the comment to the value; for `reviewed:` that broke the
# \d{4}-\d{2}-\d{2} gate at check_review_staleness, so the file was skipped by
# the staleness check while check_frontmatter still counted it as reviewed --
# a rule that reads as reviewed and can never be reported stale. All three
# expectations below are PyYAML 6.0.3's, verified against it.
FM_COMMENT_LINE='---
reviewed: 2020-01-01
  # re-verified against the live corpus
paths:
  # terraform only
  - "**/*.tf"
---
# t
'
assert_eq "an indented comment is not absorbed into the value it follows" \
    "$(fm_get "$FM_COMMENT_LINE" reviewed)" "2020-01-01"
assert_eq "an indented comment does not make paths: truthy" \
    "$(fm_get "$FM_COMMENT_LINE" paths)" ""

# D9. `- ` and a nested `key:` can only follow a key whose INLINE value is
# empty; once a value sits on the key's own line YAML permits neither, so every
# indented line there is continuation. Breaking on one truncated the value --
# the same defect D5 fixed, wearing the guard that fixed it. Both bodies below
# are valid YAML and both were truncated at the first line.
FM_CONT_URL='---
name: x
description: See the upstream note at
  https://example.com/docs for the rest.
paths:
  - "**/*.tf"
---
# x
'
assert_eq "a continuation starting with a word-colon token is not a nested key" \
    "$(fm_get "$FM_CONT_URL" description)" \
    "See the upstream note at https://example.com/docs for the rest."
assert_eq "the D9 body still leaves paths: present and empty" \
    "$(fm_get "$FM_CONT_URL" paths)" ""

FM_CONT_DASH='---
name: x
description: Some text that continues
  - and this dash line is part of it
---
# x
'
assert_eq "a continuation starting with a dash is not a list item" \
    "$(fm_get "$FM_CONT_DASH" description)" \
    "Some text that continues - and this dash line is part of it"

# D10. The closing-fence scan runs to the end of the document, so a file with
# NO frontmatter that opens with a `---` thematic break and carries another one
# later had its prose read as the block. Prose says `Note:` at column 0, and the
# widened key pattern captures it -- a prose `paths:` would silently drop the
# rule out of the always-loaded budget. The heading is why the opener test
# cannot skip comment lines: `# Title` and a YAML comment are the same string.
FM_PROSE_BLOCK='---

# Title

Note: prose, not a key.
paths: neither is this
---

section
'
assert_eq "prose between two thematic breaks is not frontmatter" \
    "$(fm_get "$FM_PROSE_BLOCK" Note)" "<absent>"
assert_eq "prose between two thematic breaks cannot supply paths:" \
    "$(fm_get "$FM_PROSE_BLOCK" paths)" "<absent>"
# Guard integrity: the opener test must not reject real frontmatter. Without
# this, "<absent>" above would also pass against a parser that returns {}.
assert_eq "real frontmatter still parses after the opener test" \
    "$(fm_get "$FM_BODY" name)" "widget-wrangling"

# The cost of the opener test, pinned so it stays a decision rather than a
# surprise: frontmatter whose first non-blank line is a YAML comment parses to
# {}. That is a real narrowing, not a free win. It is accepted because the
# alternative reopens the prose-as-frontmatter hole above -- a markdown
# `# Heading` and a YAML comment are byte-identical, so no opener test can
# admit one and reject the other. 0 of 757 fenced documents in this corpus open
# with a comment, and the failure is visible (every key vanishes, so the file
# reports as missing `reviewed:`) rather than silent like the bug it replaces.
FM_COMMENT_FIRST='---
# just a note
name: widget-wrangling
---
# widget-wrangling
'
assert_eq "frontmatter opening with a YAML comment parses to {} (accepted cost)" \
    "$(fm_get "$FM_COMMENT_FIRST" name)" "<absent>"

echo "TEST 11: a --- inside frontmatter does not truncate it, via the analyzer"
# The bug: frontmatter() ended the block at the first `---` SUBSTRING anywhere
# in the body, not at the closing fence LINE. Every key after an inner `---` was
# dropped -- including `paths:`, so a path-scoped rule was billed to the
# always-loaded budget (always_loaded_rules 0 -> 1). 118 files in this corpus
# already use a bare `---` line as a thematic break in prose.
out=$(run)
base_all_rules=$(count_key "$out" always_loaded_rules)
base_all_tokens=$(count_key "$out" always_loaded_tokens)
base_total_rules=$(count_key "$out" rules)

cat > "$FIXROOT/home/.claude/rules/thematic-break.md" <<'RULE'
---
created: 2026-01-01
description: |
  Calibrate widget torque against the fleet inventory manifest.

  ---

  The separator above is a thematic break in prose, not the end of the
  frontmatter block.
paths:
  - "**/*.tf"
---
# Thematic Break
Terraform state locking behaves differently under a remote backend, and the
lock is not released when the process is killed mid-apply.
RULE
out=$(run)
# Guard integrity: without this, every "unchanged" assertion below would also
# pass against an analyzer that never discovered the fixture at all.
assert_eq "the thematic-break fixture was discovered" \
    "$(count_key "$out" rules)" "$((base_total_rules + 1))"
assert_eq "a --- thematic break does not drop paths: (rule count)" \
    "$(count_key "$out" always_loaded_rules)" "$base_all_rules"
assert_eq "a --- thematic break does not drop paths: (token budget)" \
    "$(count_key "$out" always_loaded_tokens)" "$base_all_tokens"
rm "$FIXROOT/home/.claude/rules/thematic-break.md"

# The same defect fires with no block scalar at all: a `---` substring on a
# plain value line truncated the frontmatter just as hard.
cat > "$FIXROOT/home/.claude/rules/inline-break.md" <<'RULE'
---
created: 2026-01-01
description: Use the --- separator form when splitting the manifest
paths:
  - "**/*.tf"
---
# Inline Break
Terraform state locking behaves differently under a remote backend, and the
lock is not released when the process is killed mid-apply.
RULE
out=$(run)
assert_eq "the inline-break fixture was discovered" \
    "$(count_key "$out" rules)" "$((base_total_rules + 1))"
assert_eq "an inline --- in a plain value does not drop paths: (rule count)" \
    "$(count_key "$out" always_loaded_rules)" "$base_all_rules"
assert_eq "an inline --- in a plain value does not drop paths: (token budget)" \
    "$(count_key "$out" always_loaded_tokens)" "$base_all_tokens"
# ...and the value itself survives intact rather than being cut at the `---`.
assert_eq "an inline --- does not truncate the value it sits in" \
    "$(fm_get "$(cat "$FIXROOT/home/.claude/rules/inline-break.md")" description)" \
    "Use the --- separator form when splitting the manifest"
rm "$FIXROOT/home/.claude/rules/inline-break.md"

# A document with NO closing fence must parse to {}. That is the contract the
# pre-fix parser honoured only by accident -- it returned {} when the body held
# fewer than two `---` SUBSTRINGS, so an unterminated block carrying a couple of
# inline dashes (below) parsed as though it were fenced, and yielded a truncated
# `description`. Ending at a fence LINE makes the contract hold for the reason
# it states.
FM_NO_FENCE='---
description: a --- b --- c
name: unterminated
'
assert_eq "a document with no closing fence still yields nothing" \
    "$(fm_get "$FM_NO_FENCE" description)" "<absent>"

echo "TEST 12: the embedding cache self-invalidates when the embed text changes"
# The bug: the cache was keyed on it["hash"] -- a sha of the raw FILE BYTES --
# while the vector was computed from "title\ndesc\nbody". A frontmatter fix
# changes `desc` for files whose bytes did not change, so a warm cache kept
# serving vectors computed from the old text: the fix was inert exactly where it
# mattered, and semantic_overlap findings became cache-state dependent (a cold
# cache and a warm cache disagreed on the same commit).
#
# check_semantic_dupes imports numpy and fastembed. Neither is a dependency of
# the cheap tier this suite exercises, so both are stubbed -- but the function
# under test is the SHIPPED one, loaded out of the analyzer file, and the stub
# embedder LOGS every text it is handed, so the assertions are about what was
# actually re-embedded rather than about the cache's shape.
EMBED_DRIVER="$FIXROOT/embed-driver.py"
cat > "$EMBED_DRIVER" <<'PYDRIVER'
import hashlib
import importlib.util
import json
import math
import pathlib
import sys
import types

analyzer, cache_path, log_path, desc_a = sys.argv[1:5]


class Arr:
    """Just enough of an ndarray for check_semantic_dupes' five operations."""

    def __init__(self, rows):
        self.rows = [[float(x) for x in r] for r in rows]

    def __add__(self, scalar):
        return Arr([[x + scalar for x in r] for r in self.rows])

    def __itruediv__(self, other):
        for row, denom in zip(self.rows, other.rows):
            for k in range(len(row)):
                row[k] /= denom[0]
        return self

    @property
    def T(self):
        return Arr([list(col) for col in zip(*self.rows)])

    def __matmul__(self, other):
        return Arr(
            [
                [
                    sum(a[k] * other.rows[k][j] for k in range(len(a)))
                    for j in range(len(other.rows[0]))
                ]
                for a in self.rows
            ]
        )

    def __getitem__(self, ij):
        return self.rows[ij[0]][ij[1]]


np = types.ModuleType("numpy")
np.array = lambda rows, dtype=None: Arr(rows)
np.triu_indices = lambda n, k=0: (
    [i for i in range(n) for j in range(n) if j >= i + k],
    [j for i in range(n) for j in range(n) if j >= i + k],
)
linalg = types.ModuleType("numpy.linalg")
linalg.norm = lambda a, axis=None, keepdims=False: Arr(
    [[math.sqrt(sum(x * x for x in row))] for row in a.rows]
)
np.linalg = linalg
sys.modules["numpy"] = np
sys.modules["numpy.linalg"] = linalg


class TextEmbedding:
    def __init__(self, model_name=None):
        pass

    def embed(self, texts):
        with open(log_path, "a", encoding="utf-8") as fh:
            for text in texts:
                fh.write(json.dumps(text) + "\n")
        for text in texts:
            digest = hashlib.sha256(text.encode()).digest()
            yield [1.0, float(digest[0]), float(digest[1])]


fastembed = types.ModuleType("fastembed")
fastembed.TextEmbedding = TextEmbedding
sys.modules["fastembed"] = fastembed

spec = importlib.util.spec_from_file_location("config_drift", analyzer)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# Two skills whose FILE BYTES never change across runs. Only alpha's parsed
# `desc` moves -- exactly the shape of a frontmatter repair.
items = [
    {
        "kind": "skill",
        "path": "/fixture/alpha/SKILL.md",
        "name": "alpha",
        "title": "alpha",
        "body": "Alpha body about widget torque calibration.",
        "desc": desc_a,
        "hash": "aaaaaaaaaaaaaaaa",
        "fm": {},
    },
    {
        "kind": "skill",
        "path": "/fixture/beta/SKILL.md",
        "name": "beta",
        "title": "beta",
        "body": "Beta body about fleet inventory manifests.",
        "desc": "beta description",
        "hash": "bbbbbbbbbbbbbbbb",
        "fm": {},
    },
]

if len(sys.argv) > 5:
    mod.EMBED_MODEL = sys.argv[5]

mod.check_semantic_dupes(items, {}, pathlib.Path(cache_path))
print("CACHE_KEYS=%d" % len(json.loads(pathlib.Path(cache_path).read_text())))
PYDRIVER

EMBED_CACHE="$FIXROOT/embeddings.json"
EMBED_LOG="$FIXROOT/embed-log.jsonl"
rm -f "$EMBED_CACHE" "$EMBED_LOG"
log_lines() { [ -f "$EMBED_LOG" ] && grep -c '' "$EMBED_LOG" || echo 0; }

python3 "$EMBED_DRIVER" "$ANALYZER" "$EMBED_CACHE" "$EMBED_LOG" "old description" >/dev/null 2>&1
assert_eq "a cold cache embeds both items" "$(log_lines)" "2"

# Guard integrity: without this, "the changed item is re-embedded" would also
# pass against a cache that never hits and re-embeds everything every run.
python3 "$EMBED_DRIVER" "$ANALYZER" "$EMBED_CACHE" "$EMBED_LOG" "old description" >/dev/null 2>&1
assert_eq "an unchanged run re-embeds nothing" "$(log_lines)" "2"

cache_keys=$(python3 "$EMBED_DRIVER" "$ANALYZER" "$EMBED_CACHE" "$EMBED_LOG" "new description" 2>/dev/null | grep '^CACHE_KEYS=' | cut -d= -f2)
assert_eq "changing desc alone re-embeds exactly that item" "$(log_lines)" "3"
assert_eq "the re-embedded text carries the new desc" \
    "$(tail -n 1 "$EMBED_LOG" | grep -c 'new description')" "1"
assert_eq "the superseded vector is kept under its own key, not overwritten" "$cache_keys" "3"

# The model is an input to the vector exactly as the text is. Keyed on text
# alone, swapping EMBED_MODEL hit the cache for every item and served the
# previous model's vectors -- every cosine then computed across two embedding
# spaces, silently, with no output the operator could tell apart. Same defect
# the text-keying fixed, one level up.
python3 "$EMBED_DRIVER" "$ANALYZER" "$EMBED_CACHE" "$EMBED_LOG" "new description" \
    "BAAI/bge-large-en-v1.5" >/dev/null 2>&1
assert_eq "swapping the embedding model re-embeds every item" "$(log_lines)" "5"

echo "TEST 13: the lib/probe.py sibling import resolves, and fails LOUDLY if broken"
# Why this needs its own test: config-drift-probe.sh treats empty analyzer
# output as "no findings", so an ImportError traceback on stderr is
# indistinguishable from a clean corpus (issue #2527). There is also no
# in-repo precedent for a Python sibling import -- every other scripts/lib is
# shell -- so nothing else exercises the mechanism.
#
# Run from an UNRELATED cwd: sys.path[0] is the SCRIPT's directory, never the
# caller's, and a test that happens to run from health-plugin/scripts would
# pass against an import form that only works by accident of cwd.
imp_out=$(cd / && python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json 2>"$FIXROOT/imp.err")
imp_rc=$?
imp_err=$(python3 -c 'import sys;sys.stdout.write(open(sys.argv[1]).read())' "$FIXROOT/imp.err")
# The exit code alone cannot discriminate: an ImportError traceback exits 1,
# which is also the analyzer's normal "warnings present" code. What separates
# them is that a broken import writes a traceback to stderr and NOTHING to
# stdout -- exactly the pair the hook reads as "clean corpus".
case "$imp_rc" in
    0|1|2) ok "analyzer exits with a documented code from an unrelated cwd ($imp_rc)" ;;
    *) bad "analyzer exits with a documented code from an unrelated cwd" "0, 1 or 2" "$imp_rc" ;;
esac
assert_eq "analyzer writes nothing to stderr from an unrelated cwd" "$imp_err" ""
assert_contains "analyzer still produces findings from an unrelated cwd" "$imp_out" '"findings"'
assert_ge "the corpus really was read from an unrelated cwd" "$(count_key "$imp_out" skills)" 1

# The flat form is what a future edit would reach for. Pin that it does NOT
# work, so the namespace form is never "simplified" back to it.
if (cd / && python3 -c "
import sys
sys.path.insert(0, sys.argv[1])
import probe
" "$SCRIPTS_DIR" >/dev/null 2>&1); then
    bad "flat 'import probe' does not resolve" "ModuleNotFoundError" "import succeeded"
else
    ok "flat 'import probe' does not resolve"
fi
if [ -e "${SCRIPTS_DIR}/lib/__init__.py" ]; then
    bad "no __init__.py beside probe.py" "absent" "present"
else
    ok "no __init__.py beside probe.py (PEP 420 namespace package)"
fi

echo "TEST 14: lib/probe.py is stdlib-only and carries no PEP-723 block"
# Both real callers (../../hooks/config-drift-probe.sh and this suite) invoke
# bare python3, bypassing the uv shebang -- so a dependency block would resolve
# only on the path nobody takes.
probe_src=$(python3 -c 'import sys;sys.stdout.write(open(sys.argv[1],encoding="utf-8").read())' "$PROBE_MODULE")
assert_not_contains "probe.py declares no PEP-723 script block" "$probe_src" "/// script"
assert_not_contains "probe.py declares no dependencies" "$probe_src" "dependencies ="
# Semantic half: import it with an EMPTY sys.path beyond stdlib + its own dir.
if (cd / && python3 -c "
import sys
sys.path = [p for p in sys.path if 'site-packages' not in p and 'dist-packages' not in p]
sys.path.insert(0, sys.argv[1])
from lib.probe import finding, fingerprint, waived  # noqa: F401
" "$SCRIPTS_DIR" >/dev/null 2>&1); then
    ok "probe.py imports with site-packages removed (stdlib only)"
else
    bad "probe.py imports with site-packages removed (stdlib only)" "import ok" "import failed"
fi

echo "TEST 15: the module is callable from outside config-drift.py (second consumer)"
# Proves the contract is reusable, which is the whole point of the extraction.
probe_out=$(cd / && python3 - "$SCRIPTS_DIR" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
from lib.probe import EXIT_CLEAN, EXIT_ERROR, EXIT_WARN, exit_code, finding

f = finding("warn", "duplicate_rule_lexical", "a and b overlap",
            score=0.9, paths=["/b/two.md", "/a/one.md"])
print("KEYS=" + ",".join(f))
print("EXIT_CLEAN=%d" % exit_code([]))
print("EXIT_WARN=%d" % exit_code([f]))
print("EXIT_GATE_WARN=%d" % exit_code([f], gate=True))
err = finding("error", "broken_pointer_stub", "x", path="/a/one.md")
print("EXIT_GATE_ERROR=%d" % exit_code([err], gate=True))
print("EXIT_NOGATE_ERROR=%d" % exit_code([err]))
print("CODES=%d,%d,%d" % (EXIT_CLEAN, EXIT_WARN, EXIT_ERROR))
for bad_call in (("nope", "k", "s"), ("warn", "", "s"), ("warn", "k", ""),
                 ("warn", "k", "s")):
    try:
        if len(bad_call) == 3 and bad_call == ("warn", "k", "s"):
            finding(*bad_call, paths="not-a-list")
        else:
            finding(*bad_call)
        print("ACCEPTED=%r" % (bad_call,))
    except ValueError:
        print("REJECTED=ok")
PY
)
assert_contains "key order is severity,kind,summary then extras" "$probe_out" \
    "KEYS=severity,kind,summary,score,paths"
assert_contains "no findings exits 0" "$probe_out" "EXIT_CLEAN=0"
assert_contains "a warn finding exits 1" "$probe_out" "EXIT_WARN=1"
assert_contains "--gate does not escalate a warn" "$probe_out" "EXIT_GATE_WARN=1"
assert_contains "--gate escalates an error to 2" "$probe_out" "EXIT_GATE_ERROR=2"
assert_contains "an error without --gate stays 1" "$probe_out" "EXIT_NOGATE_ERROR=1"
assert_contains "exit-code ladder is 0/1/2" "$probe_out" "CODES=0,1,2"
assert_eq "finding() rejects all four malformed shapes" \
    "$(printf '%s\n' "$probe_out" | grep -c '^REJECTED=ok$')" "4"
assert_not_contains "finding() accepts none of them" "$probe_out" "ACCEPTED="

echo "TEST 16: fingerprint() is stable across reordering and rescoring"
fp_out=$(cd / && python3 - "$SCRIPTS_DIR" <<'PY' 2>&1
import sys
sys.path.insert(0, sys.argv[1])
from lib.probe import delta, finding, fingerprint, fingerprints

a = finding("warn", "duplicate_rule_lexical", "a and b are 91% identical",
            score=0.91, paths=["/a/one.md", "/b/two.md"])
# Same finding, sides swapped, rescored, reworded, re-severitied.
b = finding("info", "duplicate_rule_lexical", "b and a are 47% identical",
            score=0.47, paths=["/b/two.md", "/a/one.md"])
c = finding("warn", "duplicate_rule_lexical", "a and c are 91% identical",
            score=0.91, paths=["/a/one.md", "/c/three.md"])
print("REORDER_RESCORE=%s" % (fingerprint(a) == fingerprint(b)))
print("DIFFERENT_PATHS=%s" % (fingerprint(a) != fingerprint(c)))
# The `path` (singular) spelling must fingerprint on its path too -- half the
# analyzer's findings use it (normalising that split is #2527 PR2).
p1 = finding("error", "broken_pointer_stub", "x", path="/a/one.md")
p2 = finding("error", "broken_pointer_stub", "y", path="/b/two.md")
print("SINGULAR_PATH_READ=%s" % (fingerprint(p1) != fingerprint(p2)))
# A pathless finding still fingerprints, on its kind alone.
n1 = finding("info", "frontmatter_coverage", "1/1 rules carry no reviewed: date")
n2 = finding("info", "frontmatter_coverage", "2/2 rules carry no reviewed: date")
print("PATHLESS_STABLE=%s" % (fingerprint(n1) == fingerprint(n2)))
# Kind must discriminate at a FIXED path set, or the assertion is really just
# re-testing the path half. The lexical and semantic checks genuinely can flag
# the same pair, so this collision is not hypothetical.
k1 = finding("warn", "duplicate_rule_lexical", "s", paths=["/a/one.md", "/b/two.md"])
k2 = finding("warn", "semantic_overlap_rule_rule", "s", paths=["/a/one.md", "/b/two.md"])
print("KIND_DISCRIMINATES=%s" % (fingerprint(k1) != fingerprint(k2)))
d = delta([a, c], fingerprints([b]))
print("NEW=%d RESOLVED=%d UNCHANGED=%d"
      % (len(d["new"]), len(d["resolved"]), len(d["unchanged"])))
PY
)
assert_contains "reordering paths and rescoring keep one fingerprint" "$fp_out" "REORDER_RESCORE=True"
assert_contains "a different path set is a different fingerprint" "$fp_out" "DIFFERENT_PATHS=True"
assert_contains "the singular 'path' spelling is fingerprinted" "$fp_out" "SINGULAR_PATH_READ=True"
assert_contains "a pathless finding fingerprints on its kind" "$fp_out" "PATHLESS_STABLE=True"
assert_contains "kind discriminates two findings over the SAME path set" "$fp_out" "KIND_DISCRIMINATES=True"
assert_contains "delta separates new from unchanged" "$fp_out" "NEW=1 RESOLVED=0 UNCHANGED=1"

echo "TEST 17: a deliberately introduced duplicate is exactly ONE new fingerprint"
# The control that matters: a run reporting zero deltas on an unchanged corpus
# and a run whose delta logic is broken produce the SAME output. So the ladder
# is three rungs -- unchanged corpus yields 0 new, one planted duplicate yields
# exactly 1 new, removing it yields exactly 1 resolved. An always-0 or always-N
# implementation fails at least one rung.
FPR="$FIXROOT/fpr"
mkdir -p "$FPR/home/.claude/rules" "$FPR/proj/repo-a/.claude/rules" "$FPR/proj/repo-b/.claude/rules"
cat > "$FPR/proj/repo-a/.claude/rules/alpha.md" <<'RULE'
# Alpha
The torque calibration procedure requires the fleet inventory manifest before
any widget adjustment is attempted on the assembly line by the crew.
RULE
fpr_run() { HOME="$FPR/home" python3 "$ANALYZER" --root "$FPR/proj" --no-embed --fast --format=json 2>/dev/null; }
fp_delta() {
    cd / && python3 - "$SCRIPTS_DIR" "$1" "$2" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
from lib.probe import delta, fingerprints
prev = fingerprints(json.loads(sys.argv[2])["findings"])
cur = json.loads(sys.argv[3])["findings"]
d = delta(cur, prev)
print("NEW=%d RESOLVED=%d" % (len(d["new"]), len(d["resolved"])))
PY
}
base_json=$(fpr_run)
same_json=$(fpr_run)
assert_contains "an unchanged corpus reports zero deltas" "$(fp_delta "$base_json" "$same_json")" "NEW=0 RESOLVED=0"
cp "$FPR/proj/repo-a/.claude/rules/alpha.md" "$FPR/proj/repo-b/.claude/rules/beta.md"
dupe_json=$(fpr_run)
assert_eq "the planted duplicate really is a new finding (fixture validity)" \
    "$(count_kind "$dupe_json" duplicate_rule_lexical)" "1"
assert_contains "one planted duplicate is exactly one new fingerprint" \
    "$(fp_delta "$base_json" "$dupe_json")" "NEW=1 RESOLVED=0"
rm "$FPR/proj/repo-b/.claude/rules/beta.md"
gone_json=$(fpr_run)
assert_contains "removing it reports exactly one resolved fingerprint" \
    "$(fp_delta "$dupe_json" "$gone_json")" "NEW=0 RESOLVED=1"

echo "TEST 18: the cheap tier imports neither fastembed nor numpy"
# Poison both module names onto PYTHONPATH so an import touches a marker file.
# The CONTROL is the second half: without it the assertion also passes against
# an analyzer that never reaches the embed path at all.
POISON="$FIXROOT/poison"
mkdir -p "$POISON"
for mod in numpy fastembed; do
    cat > "$POISON/${mod}.py" <<'STUB'
import os
open(os.environ["EMBED_IMPORT_MARKER"], "w").close()
STUB
done
export EMBED_IMPORT_MARKER="$FIXROOT/embed-import-marker"

rm -f "$EMBED_IMPORT_MARKER"
PYTHONPATH="$POISON" python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json >/dev/null 2>&1
if [ -f "$EMBED_IMPORT_MARKER" ]; then
    bad "--no-embed imports neither numpy nor fastembed" "no marker" "marker written"
else
    ok "--no-embed imports neither numpy nor fastembed"
fi

rm -f "$EMBED_IMPORT_MARKER"
PYTHONPATH="$POISON" python3 "$ANALYZER" --root "$FIXROOT/proj" --fast \
    --cache "$FIXROOT/cache/embeddings.json" --format=json >/dev/null 2>&1
if [ -f "$EMBED_IMPORT_MARKER" ]; then
    ok "control: WITHOUT --no-embed the poisoned import IS reached"
else
    bad "control: WITHOUT --no-embed the poisoned import IS reached" \
        "marker written" "no marker -- the poison never fires, so the assertion above is vacuous"
fi
unset EMBED_IMPORT_MARKER

echo
echo "=== CONFIG DRIFT TESTS ==="
echo "PASSED=$PASS"
echo "FAILED=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS=FAIL"
    exit 1
fi
echo "STATUS=OK"
exit 0
