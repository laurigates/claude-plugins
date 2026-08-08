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
