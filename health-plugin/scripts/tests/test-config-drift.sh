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

echo "TEST 9: the lib/probe.py sibling import resolves, and fails LOUDLY if broken"
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

echo "TEST 10: lib/probe.py is stdlib-only and carries no PEP-723 block"
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

echo "TEST 11: the module is callable from outside config-drift.py (second consumer)"
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

echo "TEST 12: fingerprint() is stable across reordering and rescoring"
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

echo "TEST 13: a deliberately introduced duplicate is exactly ONE new fingerprint"
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

echo "TEST 14: the cheap tier imports neither fastembed nor numpy"
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
