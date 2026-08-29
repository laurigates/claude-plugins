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
ANALYZER="${SCRIPT_DIR}/../config-drift.py"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available"
    exit 0
fi
if [ ! -f "$ANALYZER" ]; then
    echo "FAIL: analyzer not found at $ANALYZER"
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

printf '\nAn edit that changes the content.\n' >> "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json --waivers "$WAIVERS" 2>/dev/null)
assert_eq "editing either side revives the finding" "$(count_kind "$out" duplicate_rule_lexical)" "1"
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
import os
import sys

# A real invocation (`python3 config-drift.py`) puts the ANALYZER's own
# directory on sys.path as sys.path[0], which is how its stdlib-only
# `from lib.probe import ...` resolves. Loading the module by file location out
# of a `python3 -` script does not, so the harness has to reproduce that entry
# itself -- otherwise this case dies on an ImportError no real caller can hit.
sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))

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

# Same reason as the fm_get loader above: a file-location import does not get
# the analyzer's directory on sys.path, so `from lib.probe import ...` would
# fail here for a reason no real invocation can produce.
sys.path.insert(0, str(pathlib.Path(analyzer).resolve().parent))

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

mod.check_semantic_dupes(items, mod.Waivers({}), pathlib.Path(cache_path))
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

# --- helpers for the widened corpus -----------------------------------------
finding_paths() {
    printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("\n".join(p for f in d["findings"] for p in f.get("paths", [])))' 2>/dev/null
}
count_worktree_paths() {
    finding_paths "$1" | awk '/\/\.claude\/worktrees\//{n++} END{print n+0}'
}
fm_coverage_summary() {
    printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(next((f["summary"] for f in d["findings"] if f["kind"] == "frontmatter_coverage"), "<none>"))' 2>/dev/null
}
# Appends spaces until the file length is a multiple of 4. The budget is
# `sum(chars) // 4`, and floor((S + c) / 4) == floor(S / 4) + c // 4 holds
# EXACTLY when c is a multiple of 4 -- otherwise the delta depends on the rest
# of the corpus and "raises it by exactly chars // 4" is not a testable claim.
pad_to_multiple_of_4() {
    local f="$1" n
    n=$(wc -c < "$f" | tr -d ' ')
    while [ $((n % 4)) -ne 0 ]; do printf ' ' >> "$f"; n=$((n + 1)); done
}

echo "TEST 13: agent-worktree copies are pruned, and the control proves discovery works"
# The pin, not new logic: SKIP_PARTS already contains `worktrees`, and the agent
# GLOB is anchored at depth 2 (`*-plugin/agents/*.md`) so a worktree copy is
# three levels deeper than it can reach. Both are load-bearing for four kinds
# now, and neither was asserted.
out=$(run)
wt_rules=$(count_key "$out" rules)
wt_skills=$(count_key "$out" skills)
wt_agents=$(count_key "$out" agents)
wt_claude=$(count_key "$out" claude_mds)
wt_pairs=$(count_key "$out" lexical_pairs)

WT="$FIXROOT/proj/.claude/worktrees/agent-deadbeef"
mkdir -p "$WT/repo-a/.claude/rules" "$WT/some-plugin/agents" \
         "$WT/some-plugin/skills/widget-wrangling"
cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$WT/repo-a/.claude/rules/alpha.md"
cp "$FIXROOT/proj/some-plugin/skills/widget-wrangling/SKILL.md" \
   "$WT/some-plugin/skills/widget-wrangling/SKILL.md"
cat > "$WT/some-plugin/agents/helper.md" <<'AGENT'
---
name: helper
description: A helper agent inside an agent worktree.
reviewed: 2026-01-01
---
# helper
Calibrate widget torque against the fleet inventory manifest before adjusting
any widget on the assembly line.
AGENT
cat > "$WT/CLAUDE.md" <<'CMD'
# CLAUDE.md
A CLAUDE.md inside an agent worktree clone. It must never enter the corpus.
CMD

out=$(run)
assert_eq "a worktree rule copy is not counted"      "$(count_key "$out" rules)"      "$wt_rules"
assert_eq "a worktree skill copy is not counted"     "$(count_key "$out" skills)"     "$wt_skills"
assert_eq "a worktree agent copy is not counted"     "$(count_key "$out" agents)"     "$wt_agents"
assert_eq "a worktree CLAUDE.md copy is not counted" "$(count_key "$out" claude_mds)" "$wt_claude"
assert_eq "a worktree copy adds no lexical pairs"    "$(count_key "$out" lexical_pairs)" "$wt_pairs"
assert_eq "no finding names a path inside .claude/worktrees/" "$(count_worktree_paths "$out")" "0"

# CONTROL, weighted equally: the SAME files at non-worktree paths must move
# every one of those counts. Without it "unchanged" also passes against a
# collector that discovers nothing at all.
mkdir -p "$FIXROOT/proj/repo-c/.claude/rules" "$FIXROOT/proj/other-plugin/agents" \
         "$FIXROOT/proj/other-plugin/skills/gadget-gauging" "$FIXROOT/proj/nested-doc"
cp "$WT/repo-a/.claude/rules/alpha.md" "$FIXROOT/proj/repo-c/.claude/rules/alpha.md"
cp "$WT/some-plugin/skills/widget-wrangling/SKILL.md" \
   "$FIXROOT/proj/other-plugin/skills/gadget-gauging/SKILL.md"
cp "$WT/some-plugin/agents/helper.md" "$FIXROOT/proj/other-plugin/agents/helper.md"
cp "$WT/CLAUDE.md" "$FIXROOT/proj/nested-doc/CLAUDE.md"
out=$(run)
assert_eq "CONTROL: the same rule outside a worktree IS counted"      "$(count_key "$out" rules)"      "$((wt_rules + 1))"
assert_eq "CONTROL: the same skill outside a worktree IS counted"     "$(count_key "$out" skills)"     "$((wt_skills + 1))"
assert_eq "CONTROL: the same agent outside a worktree IS counted"     "$(count_key "$out" agents)"     "$((wt_agents + 1))"
assert_eq "CONTROL: the same CLAUDE.md outside a worktree IS counted" "$(count_key "$out" claude_mds)" "$((wt_claude + 1))"

rm -rf "$WT" "$FIXROOT/proj/repo-c" "$FIXROOT/proj/other-plugin" "$FIXROOT/proj/nested-doc"
out=$(run)
assert_eq "cleanup restores the rule count" "$(count_key "$out" rules)" "$wt_rules"

echo "TEST 14: agents -- three-rung lexical ladder, plus the partition proof"
# A checker that reports a duplicate unconditionally, or never, passes exactly
# one of the three rungs.
mkdir -p "$FIXROOT/proj/some-plugin/agents" "$FIXROOT/proj/other-plugin/agents"
cat > "$FIXROOT/proj/some-plugin/agents/torque-auditor.md" <<'AGENT'
---
name: torque-auditor
description: Audit widget torque across the fleet.
reviewed: 2026-01-01
---
# torque-auditor
Audit the torque calibration of every widget against the fleet inventory
manifest. Read the manifest first, then walk the assembly line and record the
torque reading for each widget before proposing any adjustment.
AGENT
out=$(run)
assert_eq "one agent, no duplicate reported" "$(count_kind "$out" duplicate_agent_lexical)" "0"
assert_eq "the agent was discovered" "$(count_key "$out" agents)" "1"

# W1, asserted directly: discovery is a depth-anchored GLOB, not a walk for a
# directory NAMED `agents`. Two directories in the real corpus are Python source
# packages (`*/src/*/agents/`); a walk predicate ingests any stray `.md` landing
# in one as an agent prompt, silently.
mkdir -p "$FIXROOT/proj/some-plugin/src/some_plugin/agents"
cat > "$FIXROOT/proj/some-plugin/src/some_plugin/agents/README.md" <<'PKGDOC'
# agents
This is a Python source package, not an agent prompt directory.
PKGDOC
out=$(run)
assert_eq "a .md in a source package named 'agents' is not an agent" \
    "$(count_key "$out" agents)" "1"
rm -rf "$FIXROOT/proj/some-plugin/src"

sed 's/proposing any adjustment/proposing a single adjustment/' \
    "$FIXROOT/proj/some-plugin/agents/torque-auditor.md" \
    > "$FIXROOT/proj/other-plugin/agents/torque-auditor-copy.md"
out=$(run)
assert_eq "a near-identical agent in a second plugin is reported once" \
    "$(count_kind "$out" duplicate_agent_lexical)" "1"
assert_eq "an agent duplicate is not spelled as a rule duplicate" \
    "$(count_kind "$out" duplicate_rule_lexical)" "0"

rm "$FIXROOT/proj/other-plugin/agents/torque-auditor-copy.md"
out=$(run)
assert_eq "removing the copy clears the finding" "$(count_kind "$out" duplicate_agent_lexical)" "0"

# PARTITION PROOF: an agent whose body is byte-identical to a RULE. Pooled into
# one combinations() this pair scores 1.0 and fires; partitioned it is never
# compared, and there is no cross-kind kind name it could be spelled with.
cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" \
   "$FIXROOT/proj/other-plugin/agents/rule-clone.md"
out=$(run)
assert_eq "an agent byte-identical to a rule yields no duplicate_rule_lexical" \
    "$(count_kind "$out" duplicate_rule_lexical)" "0"
assert_eq "an agent byte-identical to a rule yields no duplicate_agent_lexical" \
    "$(count_kind "$out" duplicate_agent_lexical)" "0"
# Non-vacuity: the agent partition really did run over both agents (1 pair), so
# the two zeros above are a partition result rather than a dead comparison.
assert_eq "the agent partition compared its own pair" \
    "$(count_key "$out" agents)" "2"
rm "$FIXROOT/proj/other-plugin/agents/rule-clone.md"

echo "TEST 15: CLAUDE.md -- three-rung lexical ladder, and the budget"
mkdir -p "$FIXROOT/proj/nest-a" "$FIXROOT/proj/nest-b"
cat > "$FIXROOT/proj/nest-a/CLAUDE.md" <<'CMD'
# CLAUDE.md

This directory holds the assembly-line simulation harness. Run the harness from
the repository root, never from inside this directory, because the fixture
paths are resolved relative to the root and the harness will silently produce
an empty report otherwise.
CMD
out=$(run)
assert_eq "one CLAUDE.md, no duplicate reported" "$(count_kind "$out" duplicate_claude_md_lexical)" "0"
assert_eq "the nested CLAUDE.md was discovered" "$(count_key "$out" claude_mds)" "1"

sed 's/an empty report otherwise/an empty report in that case/' \
    "$FIXROOT/proj/nest-a/CLAUDE.md" > "$FIXROOT/proj/nest-b/CLAUDE.md"
out=$(run)
assert_eq "a near-identical CLAUDE.md is reported once" \
    "$(count_kind "$out" duplicate_claude_md_lexical)" "1"

rm "$FIXROOT/proj/nest-b/CLAUDE.md"
out=$(run)
assert_eq "removing the copy clears the finding" "$(count_kind "$out" duplicate_claude_md_lexical)" "0"

# Budget: only a ROOT CLAUDE.md is always-loaded.
out=$(run)
base_tokens=$(count_key "$out" always_loaded_tokens)
assert_eq "a NESTED CLAUDE.md is not always-loaded" "$(count_key "$out" always_loaded_claude_md)" "0"

cat > "$FIXROOT/proj/CLAUDE.md" <<'CMD'
---
created: 2026-01-01
modified: 2026-01-01
reviewed: 2026-01-01
---
# Assembly Line

The fleet inventory manifest is the source of truth for widget torque. Every
adjustment is recorded against the manifest, and the manifest is regenerated
nightly from the assembly-line telemetry feed.
CMD
pad_to_multiple_of_4 "$FIXROOT/proj/CLAUDE.md"
root_chars=$(wc -c < "$FIXROOT/proj/CLAUDE.md" | tr -d ' ')
# FIXTURE VALIDITY: the exact-delta claim below is only well-posed for a
# multiple of 4 (see pad_to_multiple_of_4).
assert_eq "FIXTURE: the root CLAUDE.md length is a multiple of 4" "$((root_chars % 4))" "0"
out=$(run)
assert_eq "a root CLAUDE.md sets ALWAYS_LOADED_CLAUDE_MD=1" "$(count_key "$out" always_loaded_claude_md)" "1"
assert_eq "a root CLAUDE.md raises always_loaded_tokens by exactly chars // 4" \
    "$(count_key "$out" always_loaded_tokens)" "$((base_tokens + root_chars / 4))"
rm "$FIXROOT/proj/CLAUDE.md"
out=$(run)
assert_eq "removing the root CLAUDE.md restores the token budget" \
    "$(count_key "$out" always_loaded_tokens)" "$base_tokens"
assert_eq "a nested CLAUDE.md raises the budget by 0" "$(count_key "$out" always_loaded_tokens)" "$base_tokens"

echo "TEST 16: generator-template exclusion, both polarities"
out=$(run)
base_claude=$(count_key "$out" claude_mds)
base_skills=$(count_key "$out" skills)
assert_eq "the exclusion counter is emitted even at 0" "$(count_key "$out" claude_md_templates_excluded)" "0"

# Signal 1 + 2 together: a `templates` path component AND a manifest sibling.
mkdir -p "$FIXROOT/proj/some-plugin/templates/thing"
printf '[values]\nname = "x"\n' > "$FIXROOT/proj/some-plugin/templates/thing/cargo-generate.toml"
cat > "$FIXROOT/proj/some-plugin/templates/thing/CLAUDE.md" <<'CMD'
# CLAUDE.md
Guidance for the generated module. Nothing here loads in any real session.
CMD
out=$(run)
assert_eq "a templates/ CLAUDE.md with a manifest is excluded" "$(count_key "$out" claude_mds)" "$base_claude"
assert_eq "the exclusion is reported" "$(count_key "$out" claude_md_templates_excluded)" "1"

# Signal 2 ALONE: a manifest at an ancestor, no `templates` component anywhere.
mkdir -p "$FIXROOT/proj/scaffold-x/inner"
printf '{"project_name": "x"}\n' > "$FIXROOT/proj/scaffold-x/cookiecutter.json"
cat > "$FIXROOT/proj/scaffold-x/inner/CLAUDE.md" <<'CMD'
# CLAUDE.md
Guidance for the generated project. A manifest at an ancestor declares this a
template tree even though no directory is named templates.
CMD
out=$(run)
assert_eq "a manifest at an ancestor alone excludes it" "$(count_key "$out" claude_mds)" "$base_claude"
assert_eq "both exclusions are reported" "$(count_key "$out" claude_md_templates_excluded)" "2"

# A `templates` component ALONE no longer excludes -- it is a CONVENTIONAL
# signal and needs corroboration. This assertion is INVERTED from the version
# that shipped with the widening, deliberately: the uncorroborated component
# match fired at any depth and took out every repo with a Flask/Django
# `app/templates/`, which is live configuration. TEST 20 carries that fixture and
# the full both-polarity matrix; this row is here so the exclusion counter's
# arithmetic below stays readable in one place.
mkdir -p "$FIXROOT/proj/other-plugin/templates/bare"
cat > "$FIXROOT/proj/other-plugin/templates/bare/CLAUDE.md" <<'CMD'
# CLAUDE.md
A template tree that ships no generator manifest at all.
CMD
out=$(run)
assert_eq "a templates/ component ALONE is NOT excluded (needs corroboration)" \
    "$(count_key "$out" claude_mds)" "$((base_claude + 1))"
assert_eq "so the exclusion count stays at two" "$(count_key "$out" claude_md_templates_excluded)" "2"

# THE ASSERTION THAT KILLS THE SKIP_PARTS IMPLEMENTATION: a real skill whose
# directory is literally named `templates`. Reproduces the shape of the live
# obsidian-plugin/skills/templates/SKILL.md. Adding `templates` to SKIP_PARTS
# passes every exclusion assertion above and silently drops this skill -- which
# also breaks check_stub_integrity for any stub that delegates to it.
mkdir -p "$FIXROOT/proj/other-plugin/skills/templates"
cat > "$FIXROOT/proj/other-plugin/skills/templates/SKILL.md" <<'SKILL'
---
name: templates
description: Create and apply note templates. Use when scaffolding a vault note from a template.
---
# templates
Scaffold a vault note from a stored template, filling the date and title fields
from the current context.
SKILL
out=$(run)
assert_eq "a skill directory named 'templates' is STILL discovered" \
    "$(count_key "$out" skills)" "$((base_skills + 1))"

# And a pointer stub delegating to it still resolves -- the second-order damage
# a global skip would do.
cat > "$FIXROOT/home/.claude/rules/templates-stub.md" <<'RULE'
# Note Templates

Promoted to a skill: invoke `other-plugin:templates` when scaffolding a vault
note — it carries the field-filling procedure.
RULE
out=$(run)
assert_eq "a stub delegating to the 'templates' skill still resolves" \
    "$(count_kind "$out" broken_pointer_stub)" "0"
rm "$FIXROOT/home/.claude/rules/templates-stub.md"

# An ordinary CLAUDE.md -- no marker, no manifest -- IS discovered.
mkdir -p "$FIXROOT/proj/plain-dir"
cat > "$FIXROOT/proj/plain-dir/CLAUDE.md" <<'CMD'
# CLAUDE.md
An ordinary nested CLAUDE.md at a path with no template signal of any kind.
CMD
out=$(run)
assert_eq "an ordinary CLAUDE.md IS discovered" "$(count_key "$out" claude_mds)" "$((base_claude + 2))"
assert_eq "discovering it excludes nothing new" "$(count_key "$out" claude_md_templates_excluded)" "2"
rm -rf "$FIXROOT/proj/some-plugin/templates" "$FIXROOT/proj/scaffold-x" \
       "$FIXROOT/proj/other-plugin/templates" "$FIXROOT/proj/plain-dir"

echo "TEST 17: the kind guards, as negative assertions"
out=$(run)
guard_missing=$(missing_reviewed "$out")
guard_covered=$(count_kind "$out" rule_covered_by_skill)
guard_stubs=$(count_kind "$out" broken_pointer_stub)

# check_frontmatter is RULE-only. An agent with no reviewed: must not enter the
# numerator, and the denominator must keep naming the set it counted.
cat > "$FIXROOT/proj/other-plugin/agents/undated.md" <<'AGENT'
---
name: undated
description: An agent carrying no reviewed: date at all.
---
# undated
Walk the assembly line and record every torque reading.
AGENT
out=$(run)
assert_eq "an agent with no reviewed: does not move frontmatter_coverage" \
    "$(missing_reviewed "$out")" "$guard_missing"
assert_contains "the frontmatter_coverage denominator still reads 'rules'" \
    "$(fm_coverage_summary "$out")" " rules carry no reviewed:"

# check_stub_integrity is guarded on the KIND, not on the `stub` substring. A
# CLAUDE.md quoting the house phrasing is describing the convention, not
# following it.
mkdir -p "$FIXROOT/proj/quoting-dir"
cat > "$FIXROOT/proj/quoting-dir/CLAUDE.md" <<'CMD'
# CLAUDE.md

House convention: a rule that has been promoted to a skill opens with
"Promoted to a skill: invoke `some-skill-that-does-not-exist`" and nothing else.
CMD
out=$(run)
assert_eq "a CLAUDE.md quoting the stub phrasing is not a broken stub" \
    "$(count_kind "$out" broken_pointer_stub)" "$guard_stubs"

# check_rule_covered_by_skill is RULE-only, and BOTH halves of that guard need
# a fixture that would really fire if it were widened -- an agent the metric
# simply scores low is not evidence about the guard.
#
# (i) a near-copy of the SKILL carrying NO stub phrasing. Widened, its
#     containment is far above T_COVERAGE and it emits rule_covered_by_skill.
cat > "$FIXROOT/proj/other-plugin/agents/widget-wrangling-clone.md" <<'AGENT'
---
name: widget-wrangling-clone
description: Wrangle widgets across the fleet. Use when calibrating widget torque or auditing widget inventory.
reviewed: 2026-01-01
---
# widget-wrangling-clone
Calibrating widget torque requires the fleet inventory. Audit widget torque
calibration across every widget in the inventory before adjusting any widget.
AGENT
# (ii) two stub-SHAPED agents naming nothing that exists and sharing no
#     vocabulary with any skill. Widened by an implementation that also computed
#     `stub` for every kind, they enter the CONTROL set and fail containment:
#     control_hits/control_total falls to 1/3, under the 0.7 gate, which emits
#     coverage_metric_broken and SUPPRESSES every coverage finding -- an
#     existing check silently disabled by a one-line widening.
for n in 1 2; do
    cat > "$FIXROOT/proj/other-plugin/agents/stubby-$n.md" <<AGENT
---
name: stubby-$n
description: Placeholder $n.
reviewed: 2026-01-01
---
# stubby-$n

Promoted to a skill: invoke \`no-such-skill-$n\` before harvesting the orchard,
because the almanac tabulates rainfall by parish and the ledger reconciles
tithes quarterly against the parish register.
AGENT
done
out=$(run)
assert_eq "an agent overlapping a skill yields no rule_covered_by_skill" \
    "$(count_kind "$out" rule_covered_by_skill)" "$guard_covered"
assert_eq "the coverage control gate is not tripped" \
    "$(count_kind "$out" coverage_metric_broken)" "0"
assert_eq "and no agent is reported as a broken stub either" \
    "$(count_kind "$out" broken_pointer_stub)" "$guard_stubs"
rm "$FIXROOT/proj/other-plugin/agents/undated.md" \
   "$FIXROOT/proj/other-plugin/agents/widget-wrangling-clone.md" \
   "$FIXROOT/proj/other-plugin/agents/stubby-1.md" \
   "$FIXROOT/proj/other-plugin/agents/stubby-2.md"
rm -rf "$FIXROOT/proj/quoting-dir"

echo "TEST 18: the lexical partition, asserted structurally rather than by timing"
# A fixture corpus is tiny, so a wall-clock bound would prove nothing. The
# partition has an exact arithmetic signature instead: the sum of each kind's
# own n(n-1)/2, which for any corpus with two non-empty lexical kinds is
# strictly less than the pooled N(N-1)/2.
mkdir -p "$FIXROOT/proj/repo-b/.claude/rules" "$FIXROOT/proj/nest-b"
cat > "$FIXROOT/proj/repo-b/.claude/rules/gamma.md" <<'RULE'
# Gamma
The nightly telemetry feed regenerates the fleet inventory manifest, and a
manual edit to the manifest is overwritten at the next run.
RULE
cat > "$FIXROOT/proj/other-plugin/agents/line-walker.md" <<'AGENT'
---
name: line-walker
description: Walk the assembly line and report anomalies.
reviewed: 2026-01-01
---
# line-walker
Walk the assembly line end to end and report any station whose telemetry feed
has stopped reporting.
AGENT
cat > "$FIXROOT/proj/nest-b/CLAUDE.md" <<'CMD'
# CLAUDE.md
A second nested CLAUDE.md, sharing no vocabulary with the first: this one
documents the release checklist and the tag naming convention.
CMD
out=$(run)
n_rules=$(count_key "$out" rules)
n_agents=$(count_key "$out" agents)
n_claude=$(count_key "$out" claude_mds)
expected=$(( n_rules * (n_rules - 1) / 2 + n_agents * (n_agents - 1) / 2 + n_claude * (n_claude - 1) / 2 ))
total=$(( n_rules + n_agents + n_claude ))
pooled=$(( total * (total - 1) / 2 ))
# FIXTURE VALIDITY: with fewer than two non-empty kinds the two formulas
# coincide and the assertion below is vacuous.
assert_eq "FIXTURE: all three lexical kinds are non-empty" \
    "$([ "$n_rules" -gt 0 ] && [ "$n_agents" -gt 0 ] && [ "$n_claude" -gt 0 ] && echo yes || echo no)" "yes"
if [ "$expected" -lt "$pooled" ]; then
    ok "FIXTURE: the partitioned and pooled counts genuinely differ ($expected vs $pooled)"
else
    bad "FIXTURE: the partitioned and pooled counts genuinely differ" "expected < pooled" "$expected >= $pooled"
fi
assert_eq "LEXICAL_PAIRS equals the sum of each kind's own n(n-1)/2" \
    "$(count_key "$out" lexical_pairs)" "$expected"
if [ "$(count_key "$out" lexical_pairs)" != "$pooled" ]; then
    ok "LEXICAL_PAIRS is NOT the pooled N(N-1)/2"
else
    bad "LEXICAL_PAIRS is NOT the pooled N(N-1)/2" "not $pooled" "$pooled"
fi
rm "$FIXROOT/proj/repo-b/.claude/rules/gamma.md" \
   "$FIXROOT/proj/other-plugin/agents/line-walker.md" \
   "$FIXROOT/proj/nest-b/CLAUDE.md"

# --- helpers for the D1/D2/D4 cases ----------------------------------------
finding_field() {
    printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(next((f[sys.argv[2]] for f in d["findings"] if f["kind"] == sys.argv[1]), "<none>"))' \
        "$2" "$3" 2>/dev/null || echo ERR
}
# An isolated root gets an EMPTY home: $FIXROOT/home carries pointer stubs whose
# target skill exists only in $FIXROOT/proj, so leaving HOME pointed there would
# manufacture a broken_pointer_stub ERROR in every isolated root and make the
# --gate assertions below exit 2 for the wrong reason.
mkdir -p "$FIXROOT/empty-home/.claude/rules"
run_root() { HOME="$FIXROOT/empty-home" python3 "$ANALYZER" --root "$1" --no-embed --fast --format=json 2>/dev/null; }

echo "TEST 19: agent discovery is depth-INDEPENDENT, and a misfire is distinguishable"
# THE DEFECT: discovery was `root.glob("*-plugin/agents/*.md")` -- pinned to
# depth 2 while rules, skills and CLAUDE.md all came from the recursive pruned
# walk. `hooks/config-drift-probe.sh` passes `--root "${DRIFT_CWD:-.}"`, the
# session cwd, and `~/repos` / `~/repos/laurigates` are documented Claude Code
# working roots one and two levels ABOVE where the plugins live. Measured
# pre-fix: 247 rules / 561 skills / 0 agents at `laurigates`, 367 / 591 / 0 at
# `repos`, against 21 real agents below each. The whole agent widening was inert
# exactly where the probe fires.
out=$(run)
base_agents=$(count_key "$out" agents)
base_agent_dirs=$(count_key "$out" agent_dirs)
# FIXTURE VALIDITY: without an agent already in the corpus, "one more was found"
# would also pass against a collector that found exactly one thing by luck.
assert_ge "FIXTURE: the corpus already holds an agent" "$base_agents" 1
assert_ge "FIXTURE: the corpus already holds an agents/ directory" "$base_agent_dirs" 1

mkdir -p "$FIXROOT/proj/portfolio/nested-plugin/agents"
cat > "$FIXROOT/proj/portfolio/nested-plugin/agents/deep-helper.md" <<'AGENT'
---
name: deep-helper
description: An agent two levels below the scan root.
reviewed: 2026-01-01
---
# deep-helper
Read the fleet inventory manifest, then walk the assembly line and record the
torque reading for every station before proposing an adjustment.
AGENT
out=$(run)
assert_eq "an agent BELOW the root's immediate children IS discovered" \
    "$(count_key "$out" agents)" "$((base_agents + 1))"
assert_eq "and its agents/ directory is counted at that depth too" \
    "$(count_key "$out" agent_dirs)" "$((base_agent_dirs + 1))"
# The two CONTROLs below assert against whatever discovery just reported, NOT
# against `base_agents + 1`: coupling them to the depth fix would make them fail
# as a knock-on whenever the depth assertion fails, and a control that cannot
# pass while the thing beside it fails is not a control.
deep_agents=$(count_key "$out" agents)
deep_agent_dirs=$(count_key "$out" agent_dirs)

# CONTROL, weighted equally with the assertion above: the `*-plugin/` PREFIX is
# what the old comment's source-package argument actually bought, and dropping
# the depth anchor must not drop that too. Both shapes below are the real ones
# (`git-repo-agent/src/git_repo_agent/agents`, `vault-agent/src/vault_agent/agents`)
# -- a directory NAMED `agents` inside a Python source package, at a depth the
# old glob could never have reached either.
mkdir -p "$FIXROOT/proj/portfolio/nested-plugin/src/nested_plugin/agents"
cat > "$FIXROOT/proj/portfolio/nested-plugin/src/nested_plugin/agents/README.md" <<'PKGDOC'
# agents
A Python source package. Its `.md` is documentation, not an agent prompt.
PKGDOC
mkdir -p "$FIXROOT/proj/portfolio/some-repo-agent/src/some_repo_agent/agents"
cat > "$FIXROOT/proj/portfolio/some-repo-agent/src/some_repo_agent/agents/README.md" <<'PKGDOC'
# agents
A second Python source package, in a repo whose own name ends in `-agent`.
PKGDOC
out=$(run)
assert_eq "CONTROL: a source package named 'agents' is still NOT an agent dir" \
    "$(count_key "$out" agents)" "$deep_agents"

# CONTROL: `Path.match` is fnmatch-based, so `*` DOES match a leading dot and
# `.claude-plugin` would otherwise qualify as a plugin.
mkdir -p "$FIXROOT/proj/.claude-plugin/agents"
cat > "$FIXROOT/proj/.claude-plugin/agents/marketplace-helper.md" <<'AGENT'
---
name: marketplace-helper
description: Marketplace metadata, not a plugin agent.
---
# marketplace-helper
Nothing here is an agent prompt.
AGENT
out=$(run)
assert_eq "CONTROL: .claude-plugin/agents is not an agent directory" \
    "$(count_key "$out" agents)" "$deep_agents"
assert_eq "CONTROL: .claude-plugin/agents is not counted as an agents/ directory" \
    "$(count_key "$out" agent_dirs)" "$deep_agent_dirs"

# THE MISFIRE DISCRIMINATOR (#2219/#2290, and `scripts/check-agent-model.sh`
# implements it for this exact shape). `AGENTS=0` alone cannot tell "this tree
# has no agents" from "discovery misfired" -- which is precisely the state the
# depth-anchored glob left `~/repos` in, silently, for the whole life of the
# widening. The denominator is `*-plugin/agents` DIRECTORIES, not plugin
# directories: most plugins define no agents (36 of 49 here), so the plugin-dir
# form is a false positive on almost every tree. It fired on TEST 1's own
# empty-corpus fixture, which is how that draft was caught. Three rungs below,
# so a check that reports the misfire unconditionally or never passes exactly
# one of them.
MISFIRE="$FIXROOT/misfire"
mkdir -p "$MISFIRE/foo-plugin/agents" "$MISFIRE/bar-plugin/agents" \
         "$MISFIRE/foo-plugin/skills/thing"
cat > "$MISFIRE/foo-plugin/skills/thing/SKILL.md" <<'SKILL'
---
name: thing
description: Do the thing. Use when the thing needs doing.
---
# thing
Do the thing against the fleet inventory manifest.
SKILL
printf 'placeholder\n' > "$MISFIRE/foo-plugin/agents/.gitkeep"
mout=$(run_root "$MISFIRE")
assert_eq "agents/ directories present and ZERO agent files raises the misfire" \
    "$(count_kind "$mout" agent_discovery_misfire)" "1"
assert_eq "the misfire is an error, not a warn" \
    "$(finding_field "$mout" agent_discovery_misfire severity)" "error"
assert_contains "it speaks the house vocabulary" \
    "$(finding_field "$mout" agent_discovery_misfire summary)" \
    "discovery misfire, not a clean tree"
assert_eq "AGENT_DIRS names the denominator that makes it a misfire" \
    "$(count_key "$mout" agent_dirs)" "2"
assert_eq "FIXTURE: the misfire root really did report zero agents" \
    "$(count_key "$mout" agents)" "0"
HOME="$FIXROOT/empty-home" python3 "$ANALYZER" --root "$MISFIRE" --no-embed --fast --gate --format=status >/dev/null 2>&1
assert_eq "--gate exits 2 on a discovery misfire" "$?" "2"

# Rung 2: an agent file clears it. Without this, an unconditional misfire
# finding passes every assertion above.
cat > "$MISFIRE/foo-plugin/agents/real.md" <<'AGENT'
---
name: real
description: A real agent in the misfire root.
---
# real
Walk the assembly line and record every torque reading.
AGENT
mout=$(run_root "$MISFIRE")
assert_eq "an agent file below an agents/ directory clears the misfire" \
    "$(count_kind "$mout" agent_discovery_misfire)" "0"
assert_eq "and the agent is counted" "$(count_key "$mout" agents)" "1"

# Rung 3, the OTHER polarity, and the one the first draft got wrong: a plugin
# that simply defines no agents is NOT a misfire. 36 of this repo's 49 plugin
# directories are in exactly that state, so a check keyed on plugin directories
# would fire on almost every tree and be trained away within a week.
NOAGENTS="$FIXROOT/noagents"
mkdir -p "$NOAGENTS/solo-plugin/skills/thing"
cat > "$NOAGENTS/solo-plugin/skills/thing/SKILL.md" <<'SKILL'
---
name: thing
description: Do the thing. Use when the thing needs doing.
---
# thing
Do the thing against the fleet inventory manifest.
SKILL
nout=$(run_root "$NOAGENTS")
assert_eq "a plugin with skills but no agents/ directory raises no misfire" \
    "$(count_kind "$nout" agent_discovery_misfire)" "0"
assert_eq "and reports the denominator as 0, emitted even at 0" \
    "$(count_key "$nout" agent_dirs)" "0"
assert_eq "FIXTURE: that root really was scanned (its skill was found)" \
    "$(count_key "$nout" skills)" "1"

out=$(run)
assert_eq "the main fixture -- agents/ dirs AND agents -- raises no misfire" \
    "$(count_kind "$out" agent_discovery_misfire)" "0"

rm -rf "$FIXROOT/proj/portfolio" "$FIXROOT/proj/.claude-plugin" "$MISFIRE" "$NOAGENTS"

echo "TEST 20: the generator-template predicate, as a both-polarity MATRIX"
# The predicate was wrong in BOTH directions and the over-exclude half is the
# worse one -- it silently drops LIVE configuration. Each case below is its own
# root, so the verdict is exact per fixture rather than inferred from a delta,
# and every row asserts BOTH the kept count and the excluded count so a
# predicate that excluded everything and one that excluded nothing each fail
# roughly half the matrix.
#
#   root                                     kept  excluded  which half
#   packages/create-widget/template/            0       1     under-excluded
#   scaff/{{cookiecutter.project_slug}}/        0       1     under-excluded
#   webapp/app/templates/                       1       0     OVER-excluded
#   my-copier-template/ (nested)                1       0     OVER-excluded
#   my-copier-template/ (as --root)             1       2     OVER-excluded
#   flat cargo-generate template                0       1     must STILL exclude
#   ordinary nested dir                         1       0     must STILL keep
MROOT="$FIXROOT/tmplmatrix"

# 20a. UNDER-EXCLUDED: singular `template/` under an npm `create-*` package.
# The old predicate matched only the PLURAL `templates`, so this unrendered
# document entered the corpus. Also copier's `_subdirectory: template` shape.
mkdir -p "$MROOT/a/packages/create-widget/template"
cat > "$MROOT/a/packages/create-widget/template/CLAUDE.md" <<'CMD'
# CLAUDE.md
Payload `npm create widget` copies into a repo that does not exist yet.
CMD
o=$(run_root "$MROOT/a")
assert_eq "a singular template/ under a create-* package is excluded" "$(count_key "$o" claude_mds)" "0"
assert_eq "...and the exclusion is reported" "$(count_key "$o" claude_md_templates_excluded)" "1"

# 20b. UNDER-EXCLUDED: an unrendered path component, corroborated by cruft.json
# -- which was not in the manifest list at all, though cruft-managed cookiecutter
# templates are the common case.
mkdir -p "$MROOT/b/scaff/{{cookiecutter.project_slug}}"
printf '{"template": "https://example.invalid/t.git"}\n' > "$MROOT/b/scaff/cruft.json"
cat > "$MROOT/b/scaff/{{cookiecutter.project_slug}}/CLAUDE.md" <<'CMD'
# CLAUDE.md
An UNRENDERED document whose own directory is literally a placeholder.
CMD
o=$(run_root "$MROOT/b")
assert_eq "an unrendered path component is excluded" "$(count_key "$o" claude_mds)" "0"
assert_eq "...and the exclusion is reported" "$(count_key "$o" claude_md_templates_excluded)" "1"
# ...and cruft.json alone, at an ancestor, is now a declaration in its own right.
mkdir -p "$MROOT/b2/scaff/inner"
printf '{"template": "https://example.invalid/t.git"}\n' > "$MROOT/b2/scaff/cruft.json"
cat > "$MROOT/b2/scaff/inner/CLAUDE.md" <<'CMD'
# CLAUDE.md
Below a cruft-managed template root, with no unrendered component anywhere.
CMD
o=$(run_root "$MROOT/b2")
assert_eq "cruft.json at an ancestor excludes on its own" "$(count_key "$o" claude_mds)" "0"
# ...and the unrendered-component signal ALONE, with no manifest anywhere. The
# two fixtures above are each corroborated by cruft.json, so the ancestor-manifest
# signal excludes the document before the unrendered one is ever consulted --
# deleting the unrendered signal outright left both suites green (mutation M4).
# An assertion that names one signal while measuring another pins nothing.
mkdir -p "$MROOT/b3/scaff/{{cookiecutter.project_slug}}"
cat > "$MROOT/b3/scaff/{{cookiecutter.project_slug}}/CLAUDE.md" <<'CMD'
# CLAUDE.md
Unrendered directory name, and deliberately NO generator manifest anywhere.
CMD
o=$(run_root "$MROOT/b3")
assert_eq "an unrendered component excludes with NO manifest anywhere" \
    "$(count_key "$o" claude_mds)" "0"
assert_eq "...and that exclusion is reported" \
    "$(count_key "$o" claude_md_templates_excluded)" "1"
# Guard integrity: the same tree with a rendered directory name must be KEPT,
# or the two assertions above pass against a predicate that excludes everything.
mkdir -p "$MROOT/b4/scaff/my-project"
cat > "$MROOT/b4/scaff/my-project/CLAUDE.md" <<'CMD'
# CLAUDE.md
Same shape, rendered directory name, no manifest. Ordinary live configuration.
CMD
o=$(run_root "$MROOT/b4")
assert_eq "CONTROL: the same tree with a rendered name is KEPT" \
    "$(count_key "$o" claude_mds)" "1"

# 20c. OVER-EXCLUDED: a Flask/Django Jinja directory. The bare component match
# fired at ANY depth with no corroborating manifest, so every repo with an
# `app/templates/` silently lost its CLAUDE.md.
mkdir -p "$MROOT/c/webapp/app/templates"
cat > "$MROOT/c/webapp/app/templates/CLAUDE.md" <<'CMD'
# CLAUDE.md
A Jinja template directory in a live web app. This file is live configuration.
CMD
o=$(run_root "$MROOT/c")
assert_eq "a Jinja app/templates/ CLAUDE.md is KEPT" "$(count_key "$o" claude_mds)" "1"
assert_eq "...and nothing is reported as excluded" "$(count_key "$o" claude_md_templates_excluded)" "0"

# 20d. OVER-EXCLUDED: a template repo's OWN root document is live config for
# whoever maintains the template. Asserted at BOTH scopes, because fixing it
# only at `dirpath == root` would leave the verdict depending on where you
# happened to point --root -- the same depth-anchoring disease as TEST 19.
mkdir -p "$MROOT/d/my-copier-template"
printf '_subdirectory: template\n' > "$MROOT/d/my-copier-template/copier.yml"
cat > "$MROOT/d/my-copier-template/CLAUDE.md" <<'CMD'
# CLAUDE.md
The template repo's own root document -- how to MAINTAIN this template.
CMD
o=$(run_root "$MROOT/d")
assert_eq "a NESTED template repo's own root CLAUDE.md is KEPT" "$(count_key "$o" claude_mds)" "1"
assert_eq "...and nothing is reported as excluded" "$(count_key "$o" claude_md_templates_excluded)" "0"

mkdir -p "$MROOT/d/my-copier-template/template" "$MROOT/d/my-copier-template/docs"
cat > "$MROOT/d/my-copier-template/template/CLAUDE.md" <<'CMD'
# CLAUDE.md
Payload, below the manifest that declares this tree a template.
CMD
cat > "$MROOT/d/my-copier-template/docs/CLAUDE.md" <<'CMD'
# CLAUDE.md
Also below the declaring manifest.
CMD
o=$(run_root "$MROOT/d/my-copier-template")
assert_eq "with --root ON the template repo, its own CLAUDE.md is still KEPT" \
    "$(count_key "$o" claude_mds)" "1"
# KNOWN RESIDUAL, pinned as a recorded decision rather than left to be
# rediscovered: a manifest at the root still excludes everything BELOW it. That
# is correct for a whole-repo template and conservative for a `_subdirectory`
# one; only the root's own document -- the one that certainly still loads in
# that session -- is protected.
assert_eq "RESIDUAL: documents below a declaring root manifest are still excluded" \
    "$(count_key "$o" claude_md_templates_excluded)" "2"

# 20e. GUARD INTEGRITY: the real shape in this repo must STILL be excluded.
# `foundryvtt-plugin/templates/foundryvtt-module/` carries cargo-generate.toml
# BESIDE its CLAUDE.md -- a flat layout where the manifest's own directory is the
# payload. Manifest-beside-the-document is corroboration, not a declaration, so
# it is the `templates` component that tips it.
mkdir -p "$MROOT/e/some-plugin/templates/some-module"
printf '[template]\ncargo_generate_version = ">=0.23.0"\n' \
    > "$MROOT/e/some-plugin/templates/some-module/cargo-generate.toml"
cat > "$MROOT/e/some-plugin/templates/some-module/CLAUDE.md" <<'CMD'
# CLAUDE.md
A flat cargo-generate template: the manifest's own directory is the payload.
CMD
o=$(run_root "$MROOT/e")
assert_eq "the flat cargo-generate shape is STILL excluded" "$(count_key "$o" claude_mds)" "0"
assert_eq "...and the exclusion is reported" "$(count_key "$o" claude_md_templates_excluded)" "1"

# ...while the SAME manifest-beside-the-document, without the conventional
# component, is kept. This is the pair that proves corroboration is really
# required rather than the manifest being sufficient on its own.
mkdir -p "$MROOT/e2/some-plugin/scaffolds/some-module"
printf '[template]\ncargo_generate_version = ">=0.23.0"\n' \
    > "$MROOT/e2/some-plugin/scaffolds/some-module/cargo-generate.toml"
cat > "$MROOT/e2/some-plugin/scaffolds/some-module/CLAUDE.md" <<'CMD'
# CLAUDE.md
A manifest beside a document, with no conventional component to corroborate it.
CMD
o=$(run_root "$MROOT/e2")
assert_eq "a manifest BESIDE a document, uncorroborated, KEEPS it" "$(count_key "$o" claude_mds)" "1"

# 20f. GUARD INTEGRITY, the plain case: an ordinary nested CLAUDE.md with no
# template signal of any kind. Without this row, every "KEPT" assertion above
# would also pass against a predicate that excluded nothing at all -- and
# without 20a/20b/20e, every "excluded" assertion would pass against one that
# excluded everything.
mkdir -p "$MROOT/f/plain/nested"
cat > "$MROOT/f/plain/nested/CLAUDE.md" <<'CMD'
# CLAUDE.md
An ordinary nested CLAUDE.md at a path with no template signal of any kind.
CMD
o=$(run_root "$MROOT/f")
assert_eq "an ordinary nested CLAUDE.md is KEPT" "$(count_key "$o" claude_mds)" "1"
assert_eq "...and nothing is reported as excluded" "$(count_key "$o" claude_md_templates_excluded)" "0"

rm -rf "$MROOT"

echo "TEST 21: duplicate severity is per kind, and the split is asserted both ways"
# `warn` asserts drift. For a CLAUDE.md pair that is very often wrong: a
# vendored clone and its upstream are byte-identical BY DESIGN, and the analyzer
# cannot tell that from a divergence. Measured at ~/repos, the top pair is
# exactly that (a vendored `external/facedancer` clone against the user's own
# `mcu-tinkering-lab` package). Two `.claude/rules/` scopes, and two
# `*-plugin/agents/*.md` in one marketplace, are both live and both loaded --
# duplication there IS drift.
mkdir -p "$FIXROOT/proj/repo-b/.claude/rules" "$FIXROOT/proj/nest-b" \
         "$FIXROOT/proj/other-plugin/agents"
cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$FIXROOT/proj/repo-b/.claude/rules/beta.md"
sed 's/proposing any adjustment/proposing a single adjustment/' \
    "$FIXROOT/proj/some-plugin/agents/torque-auditor.md" \
    > "$FIXROOT/proj/other-plugin/agents/torque-auditor-copy.md"
sed 's/an empty report otherwise/an empty report in that case/' \
    "$FIXROOT/proj/nest-a/CLAUDE.md" > "$FIXROOT/proj/nest-b/CLAUDE.md"
out=$(run)
# FIXTURE VALIDITY first: all three findings must actually exist, or every
# severity assertion below reads "<none>" and the case asserts nothing.
assert_eq "FIXTURE: a rule duplicate fired" "$(count_kind "$out" duplicate_rule_lexical)" "1"
assert_eq "FIXTURE: an agent duplicate fired" "$(count_kind "$out" duplicate_agent_lexical)" "1"
assert_eq "FIXTURE: a CLAUDE.md duplicate fired" "$(count_kind "$out" duplicate_claude_md_lexical)" "1"
assert_eq "a duplicate RULE is a warn" \
    "$(finding_field "$out" duplicate_rule_lexical severity)" "warn"
assert_eq "a duplicate AGENT is a warn" \
    "$(finding_field "$out" duplicate_agent_lexical severity)" "warn"
assert_eq "a duplicate CLAUDE.md is INFO, not warn" \
    "$(finding_field "$out" duplicate_claude_md_lexical severity)" "info"
# The severity split moves the roll-up, so pin the arithmetic rather than the
# label alone: an implementation that emitted the right string on a finding the
# renderer still counted as a warning would pass the three rows above.
assert_contains "the CLAUDE.md duplicate is counted as an info, not a warning" \
    "$(run_status)" "FINDING_DUPLICATE_CLAUDE_MD_LEXICAL=1"
rm "$FIXROOT/proj/repo-b/.claude/rules/beta.md" \
   "$FIXROOT/proj/other-plugin/agents/torque-auditor-copy.md" \
   "$FIXROOT/proj/nest-b/CLAUDE.md"

echo "TEST 22: promotion candidates -- the verdict, its discriminator, and its guards"
# THE VERDICT: the same thing said at two levels of the scope ladder is a
# candidate for promotion to the higher one. T_PROMOTE = 0.88, measured (see the
# constant's comment). Every case below injects the similarity through the
# hidden `--sim-fixture` seam, because `test-config-drift.sh` is listed in
# `scripts/required-to-run-tests.txt` where a SKIP is an ERROR and neither numpy
# nor fastembed is installed for the system python3 -- a case needing the real
# model would force that required gate to skip on every runner.
# `pwd -P` resolves the symlink macOS puts in front of every mktemp path
# (/var -> /private/var). The analyzer resolves its --root, so the paths in a
# finding come back canonicalised; without this the child-first assertion
# below compares two spellings of the same file.
PROOT=$(cd "$(mktemp -d)" && pwd -P)
mkdir -p "$PROOT/home/.claude/rules" "$PROOT/tie-home/.claude/rules" \
         "$PROOT/tie" "$PROOT/proj/.claude/rules" \
         "$PROOT/proj/alpha-repo/.claude/rules" \
         "$PROOT/proj/beta-repo/deep/.claude/rules"

# The similarity table is keyed by CONTENT HASH, and every fixture edit below
# changes a hash -- so the table is rewritten from the files themselves on every
# case rather than carried forward. Retyping a hash would be exactly the
# fabricated-identifier trap (`never-fabricate-test-identifiers.md`): a stale key
# scores 0.0, which is indistinguishable from "correctly suppressed".
write_sim() {  # write_sim <out.json> [<fileA> <fileB> <score>]...
    python3 - "$@" <<'PYSIM'
import hashlib, json, sys
out, rest = sys.argv[1], sys.argv[2:]
def h(p):
    return hashlib.sha256(
        open(p, encoding="utf-8", errors="replace").read().encode("utf-8", "replace")
    ).hexdigest()[:16]
table = {}
for i in range(0, len(rest), 3):
    a, b, s = rest[i], rest[i + 1], rest[i + 2]
    table["|".join(sorted((h(a), h(b))))] = float(s)
json.dump(table, open(out, "w"))
PYSIM
}
SIM="$PROOT/sim.json"
run_promo() {  # run_promo <root> [extra analyzer args...]
    HOME="$PROOT/home" python3 "$ANALYZER" --root "$1" --no-embed --fast \
        --format=json --sim-fixture "$SIM" "${@:2}" 2>/dev/null
}
promo_field() { finding_field "$1" promotion_candidate "$2"; }
promo_parents() {
    printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(",".join(sorted({f["proposed_parent"] for f in d["findings"]
                       if f["kind"] == "promotion_candidate"})))' 2>/dev/null || echo ERR
}
promo_paths_len() {
    printf '%s' "$1" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print(next((len(f["paths"]) for f in d["findings"] if f["kind"] == "promotion_candidate"), -1))' 2>/dev/null || echo ERR
}

# --- 22a. TRUE POSITIVE ------------------------------------------------------
# Two rules, two scopes, DIFFERENT names, neither referencing the other. Bodies
# are lexically dissimilar on purpose so `duplicate_rule_lexical` stays quiet and
# the only thing that can produce a finding is the injected cosine.
PARENT="$PROOT/home/.claude/rules/torque-baseline.md"
CHILD="$PROOT/proj/alpha-repo/.claude/rules/spindle-notes.md"
cat > "$PARENT" <<'RULE'
---
reviewed: 2026-08-01
---
# Torque Baseline

Every assembly line records a torque baseline before the first shift of the
week. The baseline is captured from the calibration jig, logged against the
jig's serial number, and signed off by whoever ran the jig that morning.

A baseline older than seven shifts is treated as absent: the jig drifts with
ambient temperature, and a stale figure reads as authoritative while being
wrong. Re-run the jig rather than extrapolating from the previous week.

When two baselines disagree by more than four percent, neither is used. The
discrepancy is escalated and the line runs on the manufacturer default until a
third capture agrees with one of them.
RULE
cat > "$CHILD" <<'RULE'
---
reviewed: 2026-08-01
---
# Spindle Notes

Before a shift opens, the spindle head is measured against the reference gauge
and the reading is written into the shift log beside the gauge identifier and
the operator initials.

Readings more than a week old count as missing. Ambient conditions move the
gauge, so an old number looks trustworthy while describing a machine that no
longer exists. Take a fresh reading instead of projecting the last one forward.

Two readings that differ by four percent or more cancel each other out. The
head then runs at the vendor default until a further measurement corroborates
one of the two.
RULE
write_sim "$SIM" "$CHILD" "$PARENT" 0.93
out=$(run_promo "$PROOT/proj")
assert_eq "a cross-scope pair above T_PROMOTE is one promotion_candidate" \
    "$(count_kind "$out" promotion_candidate)" "1"
assert_eq "...at severity info, so --gate cannot fail CI on it" \
    "$(promo_field "$out" severity)" "info"
assert_eq "...carrying exactly two paths" "$(promo_paths_len "$out")" "2"
assert_eq "...CHILD first, because emit_report prints only paths[:2]" \
    "$(printf '%s' "$out" | python3 -c 'import json,sys
print(next(f["paths"][0] for f in json.load(sys.stdin)["findings"] if f["kind"] == "promotion_candidate"))')" \
    "$CHILD"
assert_eq "...naming the higher scope as proposed_parent" \
    "$(promo_field "$out" proposed_parent)" "user-global"
assert_eq "...with scopes index-aligned to paths" \
    "$(printf '%s' "$out" | python3 -c 'import json,sys
print(",".join(next(f["scopes"] for f in json.load(sys.stdin)["findings"] if f["kind"]=="promotion_candidate")))')" \
    "alpha-repo,user-global"
assert_ge "GUARD: pairs were actually considered" \
    "$(count_key "$out" promotion_pairs_considered)" 1
assert_eq "GUARD: nothing was suppressed as declared in the positive case" \
    "$(count_key "$out" hierarchies_declared)" "0"

# --- 22b. --gate does not fail on an info-only run ---------------------------
# The whole reason the severity is `info`. A style suggestion that turns CI red
# gets the check switched off, and `--gate` returning 2 here would do exactly
# that on the first scheduled run that found a candidate.
gate_out=$(run_promo "$PROOT/proj" --gate --format=status)
gate_rc=0
run_promo "$PROOT/proj" --gate >/dev/null 2>&1 || gate_rc=$?
assert_contains "FIXTURE: the gate run really did produce the finding" \
    "$gate_out" "FINDING_PROMOTION_CANDIDATE=1"
assert_contains "FIXTURE: ...and produced no error-severity finding" "$gate_out" "ERRORS=0"
assert_eq "a run whose only finding is promotion_candidate exits 0 under --gate" \
    "$gate_rc" "0"

# --- 22c. the declared-hierarchy control (the required control) --------------
# The pair from 22a, unchanged except that the child now names the parent's
# file, which is what `structural_pair` reads. It is the ONLY suppressor on this
# axis and it is doing work the threshold cannot: the nearest real pair to the
# genuine candidate in the calibration corpus
# (`offload-to-deterministic-substrate` against itself one scope up, 0.8994)
# sits 0.0004 ABOVE it, so no number separates them.
#
# A pairwise PROSE discriminator (a phrase like "the shared baseline lives one
# level up", bound to the parent's scope) was built alongside this and then cut:
# measured over both corpora it suppressed 42 pairs at `claude-plugins` and 60
# at `~/repos` with NONE above T_PROMOTE, so it moved no emitted finding, while
# binding to a scope rather than a document -- one sentence exempted its child
# from every rule in the parent scope. There is deliberately no case here for a
# declaration that names no file; that shape is now a KNOWN LIMITATION recorded
# in `check_promotion_candidates`, not a behaviour.
python3 - "$CHILD" <<'PY'
import sys
p = sys.argv[1]
body = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(
    body.replace(
        "# Spindle Notes\n",
        "# Spindle Notes\n\nThe canonical statement lives at "
        "`~/.claude/rules/torque-baseline.md`; this file holds the deltas.\n",
    )
)
PY
write_sim "$SIM" "$CHILD" "$PARENT" 0.93
out=$(run_promo "$PROOT/proj")
assert_eq "a child naming the parent's file is not a promotion candidate" \
    "$(count_kind "$out" promotion_candidate)" "0"
assert_eq "...and the suppression is counted, not silent" \
    "$(count_key "$out" hierarchies_declared)" "1"
assert_ge "GUARD: the pair was still considered" \
    "$(count_key "$out" promotion_pairs_considered)" 1

rm "$PARENT" "$CHILD"

# --- 22e. the release-please shape: same basename, BELOW threshold ------------
# Two scopes, one basename, genuinely different documents (a policy and a
# package layout). Measured at 0.8114 in the calibration corpus, i.e. below any
# candidate threshold. It must not fire -- and the second half proves the reason
# is the SCORE and not the name, because the identical pair at 0.93 does fire.
RP_PARENT="$PROOT/proj/.claude/rules/release-please.md"
RP_CHILD="$PROOT/proj/beta-repo/deep/.claude/rules/release-please.md"
cat > "$RP_PARENT" <<'RULE'
---
reviewed: 2026-08-01
---
# Release Automation Policy

Generated release metadata is never hand-edited. The changelog, the version
fields and the manifest are outputs; editing an output makes the next generated
run conflict with a human decision nobody recorded.

When a version needs to move for a reason the tool cannot infer, record the
reason in a commit footer and let the tool re-derive the number. The commit
footer survives; a hand-typed version does not.

An override applied by hand is invisible to the next generated run, so the two
disagree from that point on and the disagreement is discovered at release time
rather than at review time. Prefer the footer even when it feels heavier.
RULE
cat > "$RP_CHILD" <<'RULE'
---
reviewed: 2026-08-01
---
# Package Layout In This Monorepo

Forty-four package directories are keyed by plugin name. A commit is routed to
every package whose directory it touches, so a scope string that matches no
package suppresses nothing at all.

To keep one package unpublished, change no file beneath its directory. The
scope is a changelog label; the file list is what decides which packages move.

A label naming a directory the commit never touched still renders in the
changelog of whatever it did touch, so a mislabelled entry misdescribes every
package it reached. Read the file list before choosing the label.
RULE
write_sim "$SIM" "$RP_CHILD" "$RP_PARENT" 0.81
out=$(run_promo "$PROOT/proj")
assert_eq "a same-basename pair BELOW threshold is not a candidate" \
    "$(count_kind "$out" promotion_candidate)" "0"
assert_ge "GUARD: it was considered, not skipped before scoring" \
    "$(count_key "$out" promotion_pairs_considered)" 1
assert_eq "GUARD: ...and it was the score, not a declared hierarchy" \
    "$(count_key "$out" hierarchies_declared)" "0"
write_sim "$SIM" "$RP_CHILD" "$RP_PARENT" 0.93
out=$(run_promo "$PROOT/proj")
assert_eq "the SAME pair above threshold fires -- same-name pairs are NOT skipped" \
    "$(count_kind "$out" promotion_candidate)" "1"
# Bracket T_PROMOTE tightly. The fixtures above only pin it to [0.82, 0.93]:
# 0.81 must not fire and 0.93 must, so any constant in between passes the suite
# and a -0.05 drift lands inside the gap undetected (mutation M7 survived on
# exactly that). These two straddle the shipped 0.88 by one hundredth each, so
# the band becomes (0.87, 0.89] and the constant is pinned to its own value
# rather than to a range nobody chose.
write_sim "$SIM" "$RP_CHILD" "$RP_PARENT" 0.87
out=$(run_promo "$PROOT/proj")
assert_eq "0.87 is BELOW the shipped threshold and does not fire" \
    "$(count_kind "$out" promotion_candidate)" "0"
assert_ge "GUARD: the 0.87 pair was scored, not skipped before scoring" \
    "$(count_key "$out" promotion_pairs_considered)" 1
write_sim "$SIM" "$RP_CHILD" "$RP_PARENT" 0.89
out=$(run_promo "$PROOT/proj")
assert_eq "0.89 is ABOVE it and does fire" \
    "$(count_kind "$out" promotion_candidate)" "1"
rm "$RP_PARENT" "$RP_CHILD"

# --- 22f. scope ordering and the ancestor constraint --------------------------
# One name at three scopes, ordered so the lowest RANK and the alphabetically
# first DISAGREE: ranks are portfolio(1) < alpha-repo(2) < beta-repo/deep(3),
# while alphabetically "alpha-repo" < "beta-repo/deep" < "portfolio". A check
# that sorted scopes as strings would name `alpha-repo` as the parent.
#
# It also pins the ancestor constraint: three scopes give three rank-strict
# pairs, but `alpha-repo` is not an ancestor of `beta-repo/deep` -- they are
# siblings -- so that pair must not appear. Rank is DEPTH, not ancestry, and at
# `~/repos`/0.88 rank alone admitted 47 unrelated cross-repo pairs out of 69.
F_TOP="$PROOT/proj/.claude/rules/fleet-manifest.md"
F_MID="$PROOT/proj/alpha-repo/.claude/rules/fleet-manifest.md"
F_LOW="$PROOT/proj/beta-repo/deep/.claude/rules/fleet-manifest.md"
cat > "$F_TOP" <<'RULE'
---
reviewed: 2026-08-01
---
# Fleet Manifest

The manifest enumerates every chassis currently in service together with the
depot that holds its paperwork. It is regenerated nightly from the depot
returns and is authoritative for billing.

A chassis missing from two consecutive regenerations is retired automatically,
because a gap of that length means the depot stopped reporting rather than that
the vehicle briefly left service.

Retirement is reversible for thirty days, after which the paperwork is archived
and a returning chassis is enrolled as new. Depots are notified on the day a
retirement lands so a reporting outage can be corrected before that window shuts.
RULE
cat > "$F_MID" <<'RULE'
---
reviewed: 2026-08-01
---
# Fleet Manifest

Trailers are tracked separately from tractors here. Each entry pairs a plate
with the yard responsible for it, and the pairing is what the invoicing run
reads at the end of the month.

An entry absent from two runs in a row is closed out; a two-run absence
indicates the yard has stopped filing, not a short trip away from base.

A closed entry can be reopened within a month; past that the plate is released
and a returning trailer is registered afresh. Yards receive a notice the day a
closure lands so a filing gap can be repaired before the plate is released.
RULE
cat > "$F_LOW" <<'RULE'
---
reviewed: 2026-08-01
---
# Fleet Manifest

Loading cranes carry their own register. A row binds a serial number to the
site holding its inspection certificate, and that binding drives the quarterly
charge raised against the site.

A serial that fails to appear twice running is struck off, since two silent
quarters mean the site has ceased filing rather than that the crane moved.

A struck serial may be reinstated for one further quarter; beyond that the
certificate lapses and the crane requires a fresh inspection. Sites are told the
quarter a strike is recorded so a filing lapse can be repaired in time.
RULE
write_sim "$SIM" "$F_MID" "$F_TOP" 0.93 "$F_LOW" "$F_TOP" 0.93 "$F_LOW" "$F_MID" 0.93
out=$(run_promo "$PROOT/proj")
assert_eq "three scopes, but only ANCESTOR pairs are candidates" \
    "$(count_kind "$out" promotion_candidate)" "2"
assert_eq "...both naming the lowest-RANK scope, not the alphabetically first" \
    "$(promo_parents "$out")" "portfolio"

rm "$F_TOP" "$F_MID" "$F_LOW"

# --- 22h. a scope_rank TIE is skipped, and still counted ---------------------
# Two rules at the SAME scope have no parent between them, so "promote to the
# parent" names no operation and the recommendation would be undefined.
#
# THE TIE HAS TO BE PINNED WHERE IT IS LOAD-BEARING. Two sibling scopes at equal
# depth under a project root are ALREADY rejected by the ancestor constraint, so
# a tie case built there passes whether or not the tie skip exists -- a mutation
# deleting `if ra == rb: continue` survives it, which is exactly what an earlier
# version of this case measured. The skip decides something only when the parent
# side is `user-global` or `portfolio`, which `_ancestor_scope` accepts
# unconditionally: without it, a `user-global` rule is reported as promotable
# into `user-global`. So both rules live in a HOME rules dir -- same scope, both
# rank 0 -- with the root left empty, which also makes the denominator exact:
# the universe is one pair, so `considered == 1` with zero findings proves the
# skip rather than an empty corpus. The injected score is 0.99, far above
# threshold, so nothing but the tie can be doing the suppressing.
TIE_A="$PROOT/tie-home/.claude/rules/one.md"
TIE_B="$PROOT/tie-home/.claude/rules/two.md"
cat > "$TIE_A" <<'RULE'
---
reviewed: 2026-08-01
---
# Coolant Schedule

Coolant is drained on the first Monday of each quarter and the sump is wiped
before refilling. The drained volume is logged so a slow leak shows up as a
shortfall against the previous quarter rather than as a sudden failure.

Refilling past the upper mark is treated as an error and reported, because the
overflow path routes into the swarf tray and contaminates the filtrate.

A quarter skipped for a shutdown is recorded as skipped rather than left blank,
so the next drain is compared against the last actual reading instead of
against a gap that reads like a missing log entry.
RULE
cat > "$TIE_B" <<'RULE'
---
reviewed: 2026-08-01
---
# Filter Rotation

Filters rotate on a three-station cycle and each station is stamped with the
date it entered service. Stamping at entry, not at removal, is what makes a
skipped rotation visible in the record instead of merely absent from it.

A station left in place beyond two cycles is pulled regardless of apparent
condition; visual inspection does not detect the failure mode that matters.

A cycle deferred for a shutdown is stamped as deferred rather than omitted, so
the following rotation is measured from the last real entry instead of from a
hole that looks like a lost stamp.
RULE
write_sim "$SIM" "$TIE_A" "$TIE_B" 0.99
run_tie() {  # run_tie -- HOME is the tie corpus; the root is deliberately bare
    HOME="$PROOT/tie-home" python3 "$ANALYZER" --root "$PROOT/tie" \
        --no-embed --fast --format=json --sim-fixture "$SIM" 2>/dev/null
}
tie_out=$(run_tie)
assert_eq "GUARD: the tie pair is the entire considered universe" \
    "$(count_key "$tie_out" promotion_pairs_considered)" "1"
assert_eq "a scope_rank tie is skipped rather than reported" \
    "$(count_kind "$tie_out" promotion_candidate)" "0"
assert_eq "GUARD: ...and not because it was called a declared hierarchy" \
    "$(count_key "$tie_out" hierarchies_declared)" "0"
# THE CONTROL: the same two documents, one of them moved one rung DOWN so the
# ranks differ and nothing else changes. It fires -- which is what makes the
# three rows above an assertion about the TIE rather than about this pair.
mkdir -p "$PROOT/tie/repo-x/.claude/rules"
mv "$TIE_B" "$PROOT/tie/repo-x/.claude/rules/two.md"
TIE_B="$PROOT/tie/repo-x/.claude/rules/two.md"
write_sim "$SIM" "$TIE_A" "$TIE_B" 0.99
tie_out=$(run_tie)
assert_eq "CONTROL: the same pair one rung apart IS a candidate" \
    "$(count_kind "$tie_out" promotion_candidate)" "1"
assert_eq "CONTROL: ...promoting toward the shallower scope" \
    "$(promo_field "$tie_out" proposed_parent)" "user-global"
rm -rf "$PROOT/tie" "$PROOT/tie-home/.claude/rules"

# --- 22i. the degenerate-document floor --------------------------------------
# Cosine between two near-empty documents is meaningless and runs HIGH: 10 of
# the 22 ancestor-constrained survivors at `~/repos`/0.88 were 11-128 byte
# `@AGENTS.md` redirect stubs scoring 0.879-0.975 against each other. Both
# halves are asserted -- suppressed while short, reported once padded past
# MIN_PROMOTABLE_CHARS -- so the floor cannot silently become "suppress
# everything".
SHORT_P="$PROOT/home/.claude/rules/pointer-a.md"
SHORT_C="$PROOT/proj/alpha-repo/.claude/rules/pointer-b.md"
printf -- '---\nreviewed: 2026-08-01\n---\n# Pointer A\n\n@AGENTS.md\n' > "$SHORT_P"
printf -- '---\nreviewed: 2026-08-01\n---\n# Pointer B\n\n@AGENTS.md\n' > "$SHORT_C"
write_sim "$SIM" "$SHORT_C" "$SHORT_P" 0.97
out=$(run_promo "$PROOT/proj")
assert_eq "a pair of degenerate short documents is not a candidate" \
    "$(count_kind "$out" promotion_candidate)" "0"
assert_ge "GUARD: it was considered" "$(count_key "$out" promotion_pairs_considered)" 1
python3 - "$SHORT_P" "$SHORT_C" <<'PY'
import sys
# Pad each side past MIN_PROMOTABLE_CHARS with DIFFERENT filler, so the pair
# clears the length floor without becoming a lexical duplicate.
for path, word in zip(sys.argv[1:3], ("alpha", "bravo")):
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("\n" + " ".join(f"{word}{i}" for i in range(140)) + "\n")
PY
write_sim "$SIM" "$SHORT_C" "$SHORT_P" 0.97
out=$(run_promo "$PROOT/proj")
assert_eq "the SAME pair padded past the floor IS a candidate" \
    "$(count_kind "$out" promotion_candidate)" "1"
rm "$SHORT_P" "$SHORT_C"

# --- 22j. the counters are ABSENT when the pass did not run ------------------
# `even at 0` means "ran and found none"; the cheap tier must keep saying
# "did not run". A `PROMOTION_PAIRS_CONSIDERED=0` printed by --fast --no-embed
# would read as a clean promotable corpus scanned -- the false all-clear the
# counter exists to prevent.
cheap=$(HOME="$PROOT/home" python3 "$ANALYZER" --root "$PROOT/proj" --no-embed \
    --fast --format=json 2>/dev/null)
assert_eq "the cheap tier emits no PROMOTION_PAIRS_CONSIDERED at all" \
    "$(count_key "$cheap" promotion_pairs_considered)" "ERR"
assert_eq "...nor HIERARCHIES_DECLARED" \
    "$(count_key "$cheap" hierarchies_declared)" "ERR"

rm -rf "$PROOT"

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
