#!/usr/bin/env bash
# test-probe-lib.sh — regression suite for health-plugin/scripts/lib/probe.py
#
# SEMANTIC, not syntactic: every case EXECUTES the shipped module (or a script
# that imports it) and asserts on real behaviour. A grep for `sys.path` or for a
# function name would pass against a module that no consumer can import — and a
# broken import here fails SILENTLY, because the SessionStart hook reads empty
# analyzer output as "no findings". That is the highest-risk defect in the
# extraction, so case (a) is a reachability test with its own control rather
# than a spelling check.
#
# Isolation: HOME is redirected to the fixture root, so every case reads the
# fixture's ~/.claude/rules and writes its caches there, never the real ones.
# Every analyzer invocation passes --fast, so no git is spawned and the
# shared-checkout git hazards (#1692/#1745) cannot arise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANALYZER="${SCRIPTS_DIR}/config-drift.py"
DELTA="${SCRIPTS_DIR}/probe-delta.py"
LIBFILE="${SCRIPTS_DIR}/lib/probe.py"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available"
    exit 0
fi
for f in "$ANALYZER" "$DELTA" "$LIBFILE"; do
    if [ ! -f "$f" ]; then
        echo "FAIL: missing $f"
        exit 1
    fi
done

PASS=0
FAIL=0

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n     wanted: %s\n     got:    %s\n' "$1" "$2" "$3"; }

# if/else, not `A && B || C` — in an assertion helper the short-circuit form
# runs `bad` whenever `ok` returns non-zero, which silently double-reports.
assert_eq() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$3" "$2"; fi
}
assert_contains() {
    case "$2" in
        *"$3"*) ok "$1" ;;
        *) bad "$1" "output containing '$3'" "$(printf '%s' "$2" | head -c 300)" ;;
    esac
}
assert_absent() {
    case "$2" in
        *"$3"*) bad "$1" "output WITHOUT '$3'" "$(printf '%s' "$2" | head -c 300)" ;;
        *) ok "$1" ;;
    esac
}

# --- fixture corpus -------------------------------------------------------
# The guard is spelled in check-git-sandbox-guards.sh's recognised form
# (`[ -n ]`/`[ -d ]` within two lines of the assignment), not an equivalent
# negated one: this file now runs real git ops in a sandbox (the D2/D3 gate
# fixtures), so an empty $FIXROOT would put `git -C ""` on the shared checkout
# (issue #1692).
FIXROOT=$(mktemp -d) || { echo "FAIL: mktemp failed"; exit 1; }
if [ -z "$FIXROOT" ] || [ ! -d "$FIXROOT" ]; then
    echo "FAIL: could not create fixture root"
    exit 1
fi
trap 'rm -rf "$FIXROOT"' EXIT

mkdir -p "$FIXROOT/home/.claude/rules"
mkdir -p "$FIXROOT/proj/repo-a/.claude/rules"
mkdir -p "$FIXROOT/proj/repo-b/.claude/rules"
mkdir -p "$FIXROOT/proj/some-plugin/skills/widget-wrangling"
export HOME="$FIXROOT/home"

cat > "$FIXROOT/proj/some-plugin/skills/widget-wrangling/SKILL.md" <<'SKILL'
---
name: widget-wrangling
description: Wrangle widgets across the fleet. Use when calibrating widget torque or auditing widget inventory.
---
# widget-wrangling
Calibrating widget torque requires the fleet inventory. Audit widget torque
calibration across every widget in the inventory before adjusting any widget.
SKILL

cat > "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" <<'RULE'
# Alpha
The torque calibration procedure requires the fleet inventory manifest before
any widget adjustment is attempted on the assembly line.
RULE
cp "$FIXROOT/proj/repo-a/.claude/rules/alpha.md" "$FIXROOT/proj/repo-b/.claude/rules/beta.md"

STUB_PATH="$FIXROOT/home/.claude/rules/ghost-stuff.md"
cat > "$STUB_PATH" <<'RULE'
# Ghost Stuff

Promoted to a skill: invoke `no-such-skill-anywhere` before doing the thing —
it carries the whole procedure.
RULE

# Run a python program that lives OUTSIDE the scripts dir, with the scripts dir
# on PYTHONPATH. PEP 420 resolves `lib.probe` from a path entry exactly as it
# does from sys.path[0], so this exercises the same resolution the real callers
# get without needing to plant a file inside the shipped tree.
py() { PYTHONPATH="$SCRIPTS_DIR" python3 "$1" 2>&1; }

echo "TEST a: import reachability from an unrelated cwd"
# The analyzer is invoked by the hook with an absolute path from whatever cwd
# the session happens to be in. A relative-import regression would make it print
# nothing and exit non-zero -- which the hook cannot tell from "no findings".
out=$(cd / && python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=status 2>&1)
rc=$?
assert_eq "analyzer runs from cd / with an absolute path (exit 0/1, not an ImportError)" \
    "$([ "$rc" -le 1 ] && echo yes || echo "no (rc=$rc)")" "yes"
assert_contains "analyzer emitted its section header" "$out" "=== CONFIG DRIFT ==="
# CONTROL: without this, "the analyzer ran" would also pass against an analyzer
# that no longer imports lib.probe at all.
ctl=$(cd / && PYTHONPATH="$SCRIPTS_DIR" python3 -c 'from lib.probe import Finding; print("IMPORT_OK", Finding("info","x_kind","s")["kind"])' 2>&1)
assert_contains "a direct 'from lib.probe import Finding' resolves and constructs" "$ctl" "IMPORT_OK x_kind"
# ...and the namespace form works under the REAL invocation shape too: sys.path[0]
# is the script's directory, with no PYTHONPATH help.
ctl2=$(cd / && python3 "$DELTA" --help 2>&1)
assert_contains "probe-delta.py imports lib.probe via sys.path[0] under bare python3" "$ctl2" "--baseline"

echo "TEST b: key order per kind comes from **extra, not a canonical list"
cat > "$FIXROOT/keyorder.py" <<'PY'
from lib.probe import Finding

shapes = [
    ("broken_pointer_stub", Finding("error", "broken_pointer_stub", "s", path="/p")),
    ("review_staleness", Finding("warn", "review_staleness", "s", path="/p", gap_days=9)),
    ("always_loaded_budget", Finding("warn", "always_loaded_budget", "s", tokens=1)),
    ("frontmatter_coverage", Finding("info", "frontmatter_coverage", "s")),
    ("duplicate_rule_lexical", Finding("warn", "duplicate_rule_lexical", "s", score=0.5, paths=["/a", "/b"])),
    ("rule_covered_by_skill", Finding("info", "rule_covered_by_skill", "s", score=0.6, paths=["/a", "/b"], always_loaded=True)),
    ("coverage_metric_broken", Finding("error", "coverage_metric_broken", "s")),
    ("semantic_overlap_rule_skill", Finding("warn", "semantic_overlap_rule_skill", "s", score=0.92, paths=["/a", "/b"])),
    ("semantic_pass_unavailable", Finding("info", "semantic_pass_unavailable", "s")),
]
for name, f in shapes:
    print("SHAPE %s %s" % (name, ",".join(f.to_dict())))

# CONTROL: the same kind with the kwargs in a DIFFERENT order must emit a
# DIFFERENT key order. Without it, every assertion above would also pass
# against a to_dict() that returned a fixed schema per kind.
swapped = Finding("warn", "review_staleness", "s", gap_days=9, path="/p")
print("CONTROL %s" % ",".join(swapped.to_dict()))
PY
out=$(py "$FIXROOT/keyorder.py")
assert_contains "broken_pointer_stub key order"        "$out" "SHAPE broken_pointer_stub severity,kind,summary,path"
assert_contains "review_staleness key order"           "$out" "SHAPE review_staleness severity,kind,summary,path,gap_days"
assert_contains "always_loaded_budget key order"       "$out" "SHAPE always_loaded_budget severity,kind,summary,tokens"
assert_contains "frontmatter_coverage key order"       "$out" "SHAPE frontmatter_coverage severity,kind,summary"
assert_contains "duplicate_rule_lexical key order"     "$out" "SHAPE duplicate_rule_lexical severity,kind,summary,score,paths"
assert_contains "rule_covered_by_skill key order"      "$out" "SHAPE rule_covered_by_skill severity,kind,summary,score,paths,always_loaded"
assert_contains "coverage_metric_broken key order"     "$out" "SHAPE coverage_metric_broken severity,kind,summary"
assert_contains "semantic_overlap_rule_skill key order" "$out" "SHAPE semantic_overlap_rule_skill severity,kind,summary,score,paths"
assert_contains "semantic_pass_unavailable key order"  "$out" "SHAPE semantic_pass_unavailable severity,kind,summary"
assert_contains "CONTROL: reordered kwargs emit a different key order" \
    "$out" "CONTROL severity,kind,summary,gap_days,path"

echo "TEST b2: Finding validates its own shape"
cat > "$FIXROOT/validate.py" <<'PY'
from lib.probe import Finding

def rejects(label, fn):
    try:
        fn()
    except ValueError:
        print("REJECTED %s" % label)
    else:
        print("ACCEPTED %s" % label)

rejects("bad_severity", lambda: Finding("critical", "k_kind", "s"))
rejects("bad_kind_case", lambda: Finding("warn", "Kind", "s"))
rejects("bad_kind_dash", lambda: Finding("warn", "some-kind", "s"))
rejects("empty_summary", lambda: Finding("warn", "k_kind", ""))
rejects("path_and_paths", lambda: Finding("warn", "k_kind", "s", path="/a", paths=["/b"]))
# A dynamic f-string kind is legal -- the check is a SHAPE, not an enum.
print("DYNAMIC %s" % Finding("warn", "semantic_overlap_rule_skill", "s")["kind"])
PY
out=$(py "$FIXROOT/validate.py")
assert_contains "an unknown severity is rejected"        "$out" "REJECTED bad_severity"
assert_contains "an uppercase kind is rejected"          "$out" "REJECTED bad_kind_case"
assert_contains "a hyphenated kind is rejected"          "$out" "REJECTED bad_kind_dash"
assert_contains "an empty summary is rejected"           "$out" "REJECTED empty_summary"
assert_contains "path and paths together are rejected"   "$out" "REJECTED path_and_paths"
assert_contains "a dynamic semantic_overlap_* kind is accepted" "$out" "DYNAMIC semantic_overlap_rule_skill"

echo "TEST c: waivers match in both orientations and expire on either side"
cat > "$FIXROOT/waivers.py" <<'PY'
import json
import os
import sys

from lib.probe import Waivers

root = sys.argv[1]
a = {"path": os.path.join(root, "a.md"), "hash": "aaaaaaaaaaaaaaaa"}
b = {"path": os.path.join(root, "b.md"), "hash": "bbbbbbbbbbbbbbbb"}

def write(entry):
    p = os.path.join(root, "waivers.json")
    with open(p, "w", encoding="utf-8") as fh:
        json.dump({"waivers": [entry]}, fh)
    return p

forward = write({"a": a["path"], "b": b["path"],
                 "a_hash": a["hash"], "b_hash": b["hash"], "reason": "test"})
w = Waivers.load(forward)
print("LEN %d" % len(w))
print("FORWARD %s" % w.waived(a, b))
print("REVERSED_LOOKUP %s" % w.waived(b, a))
mutated = dict(b, hash="cccccccccccccccc")
print("MUTATED %s" % w.waived(a, mutated))

# The waiver filed the OTHER way round: (b, a). The scan still yields (a, b),
# so a probe that tried one orientation only would silently ignore the file.
reversed_file = write({"a": b["path"], "b": a["path"],
                       "a_hash": b["hash"], "b_hash": a["hash"], "reason": "test"})
w2 = Waivers.load(reversed_file)
print("REVERSED_ENTRY %s" % w2.waived(a, b))
# ...and the hash pair must be swapped to match the orientation that hit, not
# compared positionally.
print("REVERSED_ENTRY_MUTATED %s" % w2.waived(a, mutated))
print("MISSING_FILE %d" % len(Waivers.load(os.path.join(root, "nope.json"))))
PY
out=$(PYTHONPATH="$SCRIPTS_DIR" python3 "$FIXROOT/waivers.py" "$FIXROOT" 2>&1)
assert_contains "one waiver loads"                          "$out" "LEN 1"
assert_contains "waived while both hashes match"            "$out" "FORWARD True"
assert_contains "waived when the pair is looked up (b, a)"  "$out" "REVERSED_LOOKUP True"
assert_contains "NOT waived after mutating one side's hash" "$out" "MUTATED False"
assert_contains "waived when the ENTRY is stored (b, a)"    "$out" "REVERSED_ENTRY True"
assert_contains "the reversed entry still expires on a hash change" "$out" "REVERSED_ENTRY_MUTATED False"
assert_contains "a missing waiver file loads as empty"      "$out" "MISSING_FILE 0"

echo "TEST d: fingerprint same/different ladder"
# The `different` half is load-bearing: without it a fingerprint() that returned
# a constant would pass every `same` case below.
cat > "$FIXROOT/fp.py" <<'PY'
from lib.probe import Finding, fingerprint as fp

base = Finding("warn", "duplicate_rule_lexical", "a and b are 60% identical",
               score=0.6, paths=["/x/a.md", "/y/b.md"])
print("SAME_REORDER %s" % (fp(base) == fp(Finding(
    "warn", "duplicate_rule_lexical", "a and b are 60% identical",
    score=0.6, paths=["/y/b.md", "/x/a.md"]))))
print("SAME_SCORE %s" % (fp(base) == fp(Finding(
    "warn", "duplicate_rule_lexical", "a and b are 60% identical",
    score=0.91, paths=["/x/a.md", "/y/b.md"]))))
print("SAME_SUMMARY %s" % (fp(base) == fp(Finding(
    "warn", "duplicate_rule_lexical", "completely different prose",
    score=0.6, paths=["/x/a.md", "/y/b.md"]))))

stale = Finding("warn", "review_staleness", "r changed 200d after", path="/x/r.md", gap_days=200)
print("SAME_GAP %s" % (fp(stale) == fp(Finding(
    "warn", "review_staleness", "r changed 900d after", path="/x/r.md", gap_days=900))))

budget_a = Finding("warn", "always_loaded_budget", "51 rules cost ~39,000 tok", tokens=39000)
budget_b = Finding("warn", "always_loaded_budget", "52 rules cost ~41,000 tok", tokens=41000)
print("SAME_BUDGET %s" % (fp(budget_a) == fp(budget_b)))

print("DIFF_KIND %s" % (fp(base) != fp(Finding(
    "warn", "duplicate_rule_lexical_x", "a and b are 60% identical",
    score=0.6, paths=["/x/a.md", "/y/b.md"]))))
print("DIFF_PATH %s" % (fp(base) != fp(Finding(
    "warn", "duplicate_rule_lexical", "a and b are 60% identical",
    score=0.6, paths=["/x/a.md", "/y/c.md"]))))

# The singular-path collision. Read naively as "paths only", these two collapse
# to ONE fingerprint and the second broken stub is invisible in every delta
# report forever.
s1 = Finding("error", "broken_pointer_stub", "one points at a ghost", path="/x/one.md")
s2 = Finding("error", "broken_pointer_stub", "two points at a ghost", path="/x/two.md")
print("DIFF_SINGULAR_PATH %s" % (fp(s1) != fp(s2)))
# ...and a singular `path` must fold into the same set a `paths` list would give.
print("FOLDED %s" % (fp(s1) == fp(Finding(
    "error", "broken_pointer_stub", "one points at a ghost", paths=["/x/one.md"]))))
# Pathless kinds get one stable fingerprint per kind, and different kinds differ.
print("DIFF_PATHLESS_KINDS %s" % (fp(Finding("info", "frontmatter_coverage", "s"))
                                  != fp(Finding("error", "coverage_metric_broken", "s"))))
PY
out=$(py "$FIXROOT/fp.py")
assert_contains "same: reordered paths"                       "$out" "SAME_REORDER True"
assert_contains "same: changed score"                         "$out" "SAME_SCORE True"
assert_contains "same: changed summary"                       "$out" "SAME_SUMMARY True"
assert_contains "same: changed gap_days"                      "$out" "SAME_GAP True"
assert_contains "same: always_loaded_budget at other token counts" "$out" "SAME_BUDGET True"
assert_contains "different: changed kind"                     "$out" "DIFF_KIND True"
assert_contains "different: changed one path"                 "$out" "DIFF_PATH True"
assert_contains "different: two stubs on DIFFERENT files"     "$out" "DIFF_SINGULAR_PATH True"
assert_contains "a singular path folds into the path set"     "$out" "FOLDED True"
assert_contains "different pathless kinds do not collide"     "$out" "DIFF_PATHLESS_KINDS True"

echo "TEST e: delta three-point ladder"
cat > "$FIXROOT/delta.py" <<'PY'
import os
import sys

from lib.probe import Baseline, Finding

root = sys.argv[1]
path = os.path.join(root, "baseline.json")
here = "/corpus"

f1 = Finding("error", "broken_pointer_stub", "one", path="/corpus/one.md")
f2 = Finding("warn", "review_staleness", "two", path="/corpus/two.md", gap_days=200)
f3 = Finding("error", "broken_pointer_stub", "three", path="/corpus/three.md")

b = Baseline.load(path, root=here, probe="p")
print("NO_BASELINE %s" % (b is None))
b = b or Baseline("p", here, "2026-01-01T00:00:00+00:00")
d = b.delta([f1, f2])
print("FIRST_RUN %s" % d.first_run)
b.record([f1, f2]).save(path)

b2 = Baseline.load(path, root=here, probe="p")
d2 = b2.delta([f1, f2])
print("UNCHANGED new=%d resolved=%d carried=%d first_run=%s"
      % (len(d2.new), len(d2.resolved), len(d2.carried), d2.first_run))

d3 = b2.delta([f1, f2, f3])
print("ADDED new=%d resolved=%d kind=%s"
      % (len(d3.new), len(d3.resolved), d3.new[0]["kind"] if d3.new else "-"))

d4 = b2.delta([f1])
print("REMOVED new=%d resolved=%d" % (len(d4.new), len(d4.resolved)))
PY
out=$(PYTHONPATH="$SCRIPTS_DIR" python3 "$FIXROOT/delta.py" "$FIXROOT" 2>&1)
assert_contains "no baseline on disk loads as None"       "$out" "NO_BASELINE True"
assert_contains "a fresh baseline reports first_run"      "$out" "FIRST_RUN True"
assert_contains "unchanged: nothing new, nothing resolved" "$out" "UNCHANGED new=0 resolved=0 carried=2 first_run=False"
assert_contains "one extra finding is exactly 1 new"      "$out" "ADDED new=1 resolved=0 kind=broken_pointer_stub"
assert_contains "removing one finding is exactly 1 resolved" "$out" "REMOVED new=0 resolved=1"

echo "TEST f: baseline durability"
cat > "$FIXROOT/durable.py" <<'PY'
import json
import os
import sys

from lib.probe import BASELINE_SCHEMA, Baseline, Finding

root = sys.argv[1]
d = os.path.join(root, "baselines")
path = os.path.join(d, "nested", "b.json")
here = "/corpus"
f1 = Finding("error", "broken_pointer_stub", "one", path="/corpus/one.md")

# save() must mkdir -p; a scheduled job's state dir does not exist on run one.
Baseline("p", here, "2026-01-01T00:00:00+00:00").record([f1]).save(path)
print("ROUNDTRIP %s" % (Baseline.load(path, root=here, probe="p") is not None))
print("TMP_LEFT %s" % sorted(x for x in os.listdir(os.path.dirname(path)) if x.endswith(".tmp")))

corrupt = os.path.join(d, "corrupt.json")
with open(corrupt, "w", encoding="utf-8") as fh:
    fh.write('{"schema": 1, "findings": {')   # truncated mid-write
print("CORRUPT %s" % (Baseline.load(corrupt, root=here, probe="p") is None))

raw = json.loads(open(path, encoding="utf-8").read())
print("SCHEMA_FIELD %s" % (raw["schema"] == BASELINE_SCHEMA))

wrong_root = os.path.join(d, "wrongroot.json")
with open(wrong_root, "w", encoding="utf-8") as fh:
    json.dump(dict(raw, root="/somewhere/else"), fh)
b = Baseline.load(wrong_root, root=here, probe="p")
print("ROOT_MISMATCH %s" % (b is None))

bad_schema = os.path.join(d, "schema99.json")
with open(bad_schema, "w", encoding="utf-8") as fh:
    json.dump(dict(raw, schema=99), fh)
print("SCHEMA_MISMATCH %s" % (Baseline.load(bad_schema, root=here, probe="p") is None))

# Guard integrity: a root/schema mismatch must be indistinguishable from a
# missing file at the CALLER, and the caller's answer is "record fresh and stay
# silent" -- never "every finding is new".
b = Baseline.load(wrong_root, root=here, probe="p") or Baseline("p", here, "t")
print("MISMATCH_IS_FIRST_RUN %s" % b.delta([f1]).first_run)
print("MISSING %s" % (Baseline.load(os.path.join(d, "nope.json"), root=here) is None))
PY
out=$(PYTHONPATH="$SCRIPTS_DIR" python3 "$FIXROOT/durable.py" "$FIXROOT" 2>&1)
assert_contains "a saved baseline round-trips"                   "$out" "ROUNDTRIP True"
assert_contains "no .tmp file is left behind after save()"        "$out" "TMP_LEFT []"
assert_contains "a truncated baseline loads as None, not {}"      "$out" "CORRUPT True"
assert_contains "the schema version is recorded"                  "$out" "SCHEMA_FIELD True"
assert_contains "a ROOT mismatch loads as None (not 'all new')"   "$out" "ROOT_MISMATCH True"
assert_contains "schema 99 loads as None"                         "$out" "SCHEMA_MISMATCH True"
assert_contains "a mismatch degrades to a silent first run"       "$out" "MISMATCH_IS_FIRST_RUN True"
assert_contains "a missing baseline loads as None"                "$out" "MISSING True"

echo "TEST g/i: probe-delta is a second consumer with a conformant block"
FINDINGS_JSON="$FIXROOT/findings.json"
BASELINE_JSON="$FIXROOT/probe-delta-baseline.json"
python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json > "$FINDINGS_JSON" 2>/dev/null
# Guard integrity: the planted corpus must actually produce findings, or every
# ISSUE_COUNT assertion below is satisfied by an analyzer that found nothing.
planted=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["findings"]))' "$FINDINGS_JSON")
assert_eq "the fixture corpus produces a NON-EMPTY finding set" \
    "$([ "${planted:-0}" -ge 2 ] && echo yes || echo "no ($planted)")" "yes"

out=$(cd / && python3 "$DELTA" --findings "$FINDINGS_JSON" --baseline "$BASELINE_JSON" \
    --probe config-drift --root "$FIXROOT/proj" --section "CONFIG DRIFT DELTA" 2>&1)
rc=$?
assert_eq "first run exits 0" "$rc" "0"
assert_contains "opening delimiter"      "$out" "=== CONFIG DRIFT DELTA ==="
assert_contains "closing delimiter"      "$out" "=== END CONFIG DRIFT DELTA ==="
assert_contains "STATUS= is present"     "$out" "STATUS=OK"
assert_contains "ISSUE_COUNT= is present" "$out" "ISSUE_COUNT=0"
assert_contains "first run is announced" "$out" "FIRST_RUN=true"
# structured-script-output.md fixes the verdict vocabulary at OK|WARN|ERROR. A
# rollup greps that alternation, so a fourth word (the `CLEAN` this renderer
# used to emit) drops the whole section out of the table with no error anywhere.
assert_eq "STATUS is drawn from OK|WARN|ERROR and nothing else" \
    "$(printf '%s\n' "$out" | grep -cE '^STATUS=(OK|WARN|ERROR)$')" "1"
assert_eq "exactly one STATUS= line is emitted" \
    "$(printf '%s\n' "$out" | grep -c '^STATUS=')" "1"
# The delta's severity counters are computed over the NEW findings while
# `counts` carries the total, so they must not reuse the key names
# config-drift's own emit_status writes over the FULL set — a combined-log
# rollup grepping '^ERRORS=' would otherwise get two contradictory answers.
assert_contains "the delta counts new errors under its own key"   "$out" "NEW_ERRORS=0"
assert_contains "the delta counts new warnings under its own key" "$out" "NEW_WARNINGS=0"
assert_eq "no bare ERRORS= line collides with emit_status" \
    "$(printf '%s\n' "$out" | grep -cE '^(ERRORS|WARNINGS)=')" "0"
assert_eq "the first run wrote a baseline" "$([ -s "$BASELINE_JSON" ] && echo yes || echo no)" "yes"
assert_contains "the first run carried the whole corpus forward" "$out" "TOTAL_FINDINGS=$planted"

out=$(cd / && python3 "$DELTA" --findings "$FINDINGS_JSON" --baseline "$BASELINE_JSON" \
    --probe config-drift --root "$FIXROOT/proj" --section "CONFIG DRIFT DELTA" 2>&1)
assert_contains "an unchanged second run is OK"     "$out" "STATUS=OK"
assert_contains "an unchanged second run has 0 new" "$out" "NEW=0"
assert_contains "an unchanged second run carries them" "$out" "CARRIED=$planted"

# Plant one more broken stub: exactly one NEW finding must surface, and only it.
cat > "$FIXROOT/home/.claude/rules/second-ghost.md" <<'RULE'
# Second Ghost

Promoted to a skill: invoke `also-no-such-skill` before doing the other thing —
it carries the whole procedure.
RULE
python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json > "$FIXROOT/findings2.json" 2>/dev/null
out=$(cd / && python3 "$DELTA" --findings "$FIXROOT/findings2.json" --baseline "$BASELINE_JSON" \
    --probe config-drift --root "$FIXROOT/proj" --section "CONFIG DRIFT DELTA" 2>&1)
rc=$?
assert_contains "one new finding is reported"        "$out" "NEW=1"
assert_contains "ISSUE_COUNT reflects the new set"   "$out" "ISSUE_COUNT=1"
assert_contains "the report names the new stub only" "$out" "TYPE=broken_pointer_stub"
assert_absent  "the carried findings are not re-listed" "$out" "TYPE=review_staleness"
assert_contains "an error-severity delta is ERROR"   "$out" "STATUS=ERROR"
assert_contains "the new error is counted under NEW_ERRORS" "$out" "NEW_ERRORS=1"
assert_eq "a non-empty delta still emits no bare ERRORS= line" \
    "$(printf '%s\n' "$out" | grep -cE '^(ERRORS|WARNINGS)=')" "0"
assert_eq "an error-severity delta exits 1" "$rc" "1"
rm -f "$FIXROOT/home/.claude/rules/second-ghost.md"

# A root the baseline was NOT recorded at must degrade to a silent first run,
# never to "every finding is new plus every old one resolved".
out=$(cd / && python3 "$DELTA" --findings "$FINDINGS_JSON" --baseline "$BASELINE_JSON" \
    --probe config-drift --root "$FIXROOT" --section "CONFIG DRIFT DELTA" 2>&1)
assert_contains "a root mismatch reports FIRST_RUN=true" "$out" "FIRST_RUN=true"
assert_contains "a root mismatch stays OK"               "$out" "STATUS=OK"

echo "TEST i2: empty / unparseable analyzer output is ERROR, never a clean sweep"
out=$(cd / && printf '' | python3 "$DELTA" --findings - --baseline "$FIXROOT/e.json" \
    --probe config-drift --root "$FIXROOT/proj" 2>&1)
rc=$?
assert_contains "empty stdin reports analyzer_failed" "$out" "TYPE=analyzer_failed"
assert_contains "empty stdin is ERROR"                "$out" "STATUS=ERROR"
assert_absent  "empty stdin never reports a clean verdict" "$out" "STATUS=OK"
assert_eq "empty stdin exits non-zero" "$([ "$rc" -ne 0 ] && echo yes || echo no)" "yes"
assert_eq "empty stdin wrote no baseline" "$([ -e "$FIXROOT/e.json" ] && echo yes || echo no)" "no"

out=$(cd / && printf 'not json at all' | python3 "$DELTA" --findings - --baseline "$FIXROOT/u.json" \
    --probe config-drift --root "$FIXROOT/proj" 2>&1)
assert_contains "unparseable stdin reports analyzer_failed" "$out" "TYPE=analyzer_failed"
assert_contains "unparseable stdin closing delimiter"       "$out" "=== END CONFIG-DRIFT DELTA ==="

echo "TEST i3: an unknown argument exits 2 with usage (#2057)"
err=$(cd / && python3 "$DELTA" --findings - --baseline "$FIXROOT/x.json" --probe p \
    --root "$FIXROOT/proj" --no-such-flag </dev/null 2>&1)
rc=$?
assert_eq "unknown flag exits 2" "$rc" "2"
assert_contains "unknown flag prints usage" "$err" "usage: probe-delta.py"

echo "TEST h: the cheap tier imports neither fastembed nor numpy"
POISON="$FIXROOT/poison"
mkdir -p "$POISON"
for mod in numpy fastembed; do
    cat > "$POISON/$mod.py" <<'PY'
import os
open(os.environ["EMBED_IMPORT_MARKER"], "a").close()
PY
done
export EMBED_IMPORT_MARKER="$FIXROOT/embed-import-happened"
rm -f "$EMBED_IMPORT_MARKER"
PYTHONPATH="$POISON" python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=status >/dev/null 2>&1
assert_eq "--no-embed imports neither numpy nor fastembed" \
    "$([ -f "$EMBED_IMPORT_MARKER" ] && echo present || echo absent)" "absent"
# CONTROL: without this, the assertion above would also pass against an analyzer
# whose embed path is unreachable for some entirely different reason.
rm -f "$EMBED_IMPORT_MARKER"
PYTHONPATH="$POISON" python3 "$ANALYZER" --root "$FIXROOT/proj" --fast --format=status >/dev/null 2>&1
assert_eq "CONTROL: without --no-embed the embed path IS reached" \
    "$([ -f "$EMBED_IMPORT_MARKER" ] && echo present || echo absent)" "present"
rm -f "$EMBED_IMPORT_MARKER"
unset EMBED_IMPORT_MARKER

echo "TEST j: current bugs pinned deliberately (inverted by the follow-up PR)"
# j1. `--since <ref>` keeps `not f.get("paths")` as its escape hatch, and a
# singular-`path` finding has no `paths` key -- so a broken_pointer_stub whose
# file was NOT touched survives the filter while a paths-carrying duplicate is
# correctly dropped. The follow-up PR normalises path -> paths, which INVERTS
# this assertion; when it does, this case is the record of what changed.
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json \
    --since HEAD 2>/dev/null)
kinds() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for f in d["findings"] if f["kind"]==sys.argv[1]))' "$2" 2>/dev/null || echo ERR; }
assert_eq "PINNED BUG: --since retains an untouched singular-path stub finding" \
    "$(kinds "$out" broken_pointer_stub)" "1"
assert_eq "CONTROL: --since correctly drops an untouched paths-carrying finding" \
    "$(kinds "$out" duplicate_rule_lexical)" "0"

# j2. emit_report prints `f.get("paths", [])[:2]` only, so a singular-`path`
# finding's file is never shown -- the reader is told a stub is broken and not
# which one. Also inverted by the follow-up PR.
rep=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=report 2>/dev/null)
assert_contains "the report does list the broken stub finding" "$rep" "broken_pointer_stub"
assert_absent "PINNED BUG: --format=report never prints that stub's path" "$rep" "$STUB_PATH"

# =====================================================================
# Round-2 repair regressions (D1-D5). Every case EXECUTES the failing
# condition; every negative carries its control, because a hook that always
# reports failure -- or a gate that always harness-errors -- passes the naive
# form of each of these.
# =====================================================================

REPO_ROOT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
PROTO_SRC="${REPO_ROOT}/hooks-plugin/hooks/lib/drift-protocol.sh"
HOOK_SRC="${REPO_ROOT}/health-plugin/hooks/config-drift-probe.sh"

if ! command -v jq >/dev/null 2>&1 || [ ! -f "$PROTO_SRC" ] || [ ! -f "$HOOK_SRC" ]; then
    echo "  note  skipping hook/gate regressions (need jq + drift-protocol.sh + the hook)"
else
    # The hook is copied into a fixture tree so its own relative resolution
    # (SCRIPT_DIR/../scripts/config-drift.py) picks up a STUB analyzer. The
    # shipped hook file is copied byte-for-byte -- never retyped -- so the thing
    # under test is the thing that ships.
    HK="$FIXROOT/hookfix"
    mkdir -p "$HK/health-plugin/hooks" "$HK/health-plugin/scripts" \
             "$HK/hooks-plugin/hooks/lib" "$HK/sig" "$HK/cwd"
    cp "$HOOK_SRC" "$HK/health-plugin/hooks/config-drift-probe.sh"
    cp "$PROTO_SRC" "$HK/hooks-plugin/hooks/lib/drift-protocol.sh"
    STUB="$HK/health-plugin/scripts/config-drift.py"

    # run_hook <session-tag> -> sets HOOK_RC and HOOK_FINDINGS (compact JSON
    # array, or the literal "NO-SIGNAL-FILE" when the probe wrote nothing).
    run_hook() {
        local tag="$1"
        rm -rf "$HK/sig/$tag"
        printf '{"session_id":"%s","cwd":"%s"}' "$tag" "$HK/cwd" \
            | CLAUDE_DRIFT_SIGNALS_DIR="$HK/sig" \
              bash "$HK/health-plugin/hooks/config-drift-probe.sh" >/dev/null 2>&1
        HOOK_RC=$?
        if [ -f "$HK/sig/$tag/config-drift.json" ]; then
            HOOK_FINDINGS=$(jq -c '.findings' "$HK/sig/$tag/config-drift.json" 2>/dev/null || echo BAD-JSON)
        else
            HOOK_FINDINGS="NO-SIGNAL-FILE"
        fi
    }

    echo "TEST D1: an analyzer that exits 0 with nothing usable is never a clean sweep"
    # --format=json prints unconditionally, so empty output IS the proof the
    # analyzer did not run. Pre-repair both of these fell through to a bare
    # drift_emit, whose empty findings array IS the "checked, no drift" verdict
    # (hooks-plugin/hooks/lib/drift-protocol.sh) -- a false all-clear signed by a
    # dead analyzer. Reproduces a truncated / 0-byte analyzer: an interrupted
    # plugin install, a partial write.
    : > "$STUB"
    run_hook d1-empty
    assert_eq "exit 0 + EMPTY stdout does not write the clean-sweep empty array" \
        "$([ "$HOOK_FINDINGS" = "[]" ] && echo clean-sweep-verdict || echo reported)" "reported"
    assert_contains "exit 0 + EMPTY stdout reports the analyzer as failed" \
        "$HOOK_FINDINGS" '"kind":"analyzer_failed"'
    assert_eq "exit 0 + EMPTY stdout emits exactly one finding" \
        "$(printf '%s' "$HOOK_FINDINGS" | jq 'length' 2>/dev/null)" "1"
    # A SessionStart probe reports drift; it never fails the session. Reporting
    # the dead analyzer must not become a non-zero exit.
    assert_eq "the hook still exits 0 while reporting the dead analyzer" "$HOOK_RC" "0"

    printf 'print("this is not json")\n' > "$STUB"
    run_hook d1-nonjson
    assert_contains "exit 0 + NON-JSON stdout reports the analyzer as failed" \
        "$HOOK_FINDINGS" '"kind":"analyzer_failed"'

    # CONTROL. Without it, every assertion above is satisfied by a hook that
    # cries analyzer_failed unconditionally -- which would bury the real findings
    # under a permanent false alarm and is a worse bug than the one being fixed.
    cat > "$STUB" <<'PY'
import json, sys
print(json.dumps({"findings": [{"severity": "warn", "kind": "review_staleness",
                                "summary": "42 rules unreviewed"}],
                  "counts": {}}))
sys.exit(1)
PY
    run_hook d1-healthy
    assert_absent "CONTROL: a HEALTHY analyzer (exit 1 + full JSON) is not called failed" \
        "$HOOK_FINDINGS" 'analyzer_failed'
    assert_contains "CONTROL: a healthy analyzer's own findings are forwarded" \
        "$HOOK_FINDINGS" '"kind":"review_staleness"'

    # CONTROL 2: a genuinely CLEAN corpus must still produce the empty-array
    # "checked, no drift" verdict -- the repair must not make emptiness itself
    # suspicious, only emptiness on STDOUT.
    cat > "$STUB" <<'PY'
import json
print(json.dumps({"findings": [], "counts": {}}))
PY
    run_hook d1-clean
    assert_eq "CONTROL: a clean corpus still writes the empty findings array" \
        "$HOOK_FINDINGS" "[]"

    echo "TEST D4: the summary names the exception, not whatever wrote last"
    # atexit handlers, CPython's shutdown chatter, and a wrapping python3 shim
    # (mise/asdf/uv -- this machine uses mise) all write AFTER the traceback, so
    # `tail -n 1` names the noise and discards the real cause.
    cat > "$STUB" <<'PY'
import sys
print("Traceback (most recent call last):", file=sys.stderr)
print('  File "config-drift.py", line 271, in collect', file=sys.stderr)
print("RuntimeError: the corpus index is corrupt", file=sys.stderr)
print("[gc] cleaning up temporary buffers", file=sys.stderr)
sys.exit(1)
PY
    run_hook d4-trailing
    assert_contains "the exception line is reported even when it is not last" \
        "$HOOK_FINDINGS" "RuntimeError: the corpus index is corrupt"
    assert_absent "the trailing atexit noise is not reported as the summary" \
        "$HOOK_FINDINGS" "cleaning up temporary buffers"

    # CONTROL: a failure with NO exception-shaped line must still report
    # something -- the fallback to tail -n 1 has to survive. A shim that cannot
    # find an interpreter writes no traceback at all.
    cat > "$STUB" <<'PY'
import sys
print("mise: no python3 runtime installed for this directory", file=sys.stderr)
sys.exit(1)
PY
    run_hook d4-noexc
    assert_contains "CONTROL: with no exception-shaped line, the last line is used" \
        "$HOOK_FINDINGS" "mise: no python3 runtime installed"

    echo "TEST D5: argument and corpus errors are not packaged as analyzer failures"
    # (a) exit 3 is config-drift.py's ARGUMENT VALIDATION return (`root not
    # found`), not a failure. A cwd that is not a directory produced a permanent
    # error/analyzer_failed nudge blaming a healthy analyzer.
    cat > "$STUB" <<'PY'
import sys
print("root not found: /nope/not/a/dir", file=sys.stderr)
sys.exit(3)
PY
    run_hook d5-badroot
    assert_contains "exit 3 gets its own kind"      "$HOOK_FINDINGS" '"kind":"analyzer_bad_root"'
    assert_contains "exit 3 is warn, not error"     "$HOOK_FINDINGS" '"severity":"warn"'
    assert_absent  "exit 3 is not analyzer_failed"  "$HOOK_FINDINGS" 'analyzer_failed'

    # (b) An unresolvable symlink under any .claude/rules/ is a CORPUS problem.
    # Symlinked rules directories are normal under chezmoi/stow, and
    # drift-aggregator.sh sorts error first and caps at MAX_LINES=5 across ALL
    # plugins -- so error/analyzer_failed occupied slot 1 of 5 on every
    # SessionStart, with a remediation that would not locate the file.
    cat > "$STUB" <<'PY'
import sys
print("Traceback (most recent call last):", file=sys.stderr)
print('  File "config-drift.py", line 296, in collect', file=sys.stderr)
print("FileNotFoundError: [Errno 2] No such file or directory: "
      "'/Users/x/.claude/rules/dangling.md'", file=sys.stderr)
sys.exit(1)
PY
    run_hook d5-corpus
    assert_contains "a file-read exception gets its own kind" \
        "$HOOK_FINDINGS" '"kind":"corpus_unreadable"'
    assert_contains "a file-read exception is warn, not error" \
        "$HOOK_FINDINGS" '"severity":"warn"'
    assert_contains "the summary blames the CORPUS, not the analyzer" \
        "$HOOK_FINDINGS" "could not read a file in the config corpus"
    assert_contains "the offending path survives into the summary" \
        "$HOOK_FINDINGS" "dangling.md"

    # CONTROL for both (a) and (b): a GENUINE analyzer failure must stay at
    # error/analyzer_failed. Without this, downgrading everything to warn passes
    # every assertion above while silencing the failure class the hook exists to
    # surface.
    cat > "$STUB" <<'PY'
import sys
print("Traceback (most recent call last):", file=sys.stderr)
print("ModuleNotFoundError: No module named 'lib'", file=sys.stderr)
sys.exit(1)
PY
    run_hook d5-genuine
    assert_contains "CONTROL: an import error is still error/analyzer_failed" \
        "$HOOK_FINDINGS" '"kind":"analyzer_failed"'
    assert_contains "CONTROL: an import error is still severity error" \
        "$HOOK_FINDINGS" '"severity":"error"'

    # ---------------------------------------------------------------- the gate
    # compare-ref-output.sh resolves REPO_ROOT as SCRIPT_DIR/../../.. and reads
    # the baseline out of git, so the fixture reproduces that layout exactly.
    # HOME is already redirected to $FIXROOT/home, so $HOME/repos/laurigates does
    # not exist and only the fixture root is compared.
    GATE_SRC="${REPO_ROOT}/health-plugin/scripts/tests/compare-ref-output.sh"
    if [ ! -f "$GATE_SRC" ]; then
        echo "  note  skipping D2/D3 (compare-ref-output.sh absent)"
    else
        # An inherited absolute GIT_DIR / GIT_WORK_TREE OVERRIDES `git -C`, so a
        # leaked one would point every sandbox git op below at the shared
        # checkout (issue #1745). Neutralise the whole family before any of them.
        unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
              GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

        # build_gate_fixture <before-body-file> <after-body-file> -> GATE_DIR
        build_gate_fixture() {
            local before="$1" after="$2"
            GATE_DIR=$(mktemp -d) || return 1
            [ -n "$GATE_DIR" ] && [ -d "$GATE_DIR" ] || return 1
            mkdir -p "$GATE_DIR/health-plugin/scripts/tests"
            cp "$GATE_SRC" "$GATE_DIR/health-plugin/scripts/tests/compare-ref-output.sh"
            cp "$before" "$GATE_DIR/health-plugin/scripts/config-drift.py"
            git -C "$GATE_DIR" init -q
            git -C "$GATE_DIR" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
            git -C "$GATE_DIR" -c user.email=t@t -c user.name=t \
                -c commit.gpgsign=false -c core.hooksPath=/dev/null \
                commit -q -m baseline >/dev/null 2>&1
            cp "$after" "$GATE_DIR/health-plugin/scripts/config-drift.py"
        }
        run_gate() {
            GATE_OUT=$(bash "$GATE_DIR/health-plugin/scripts/tests/compare-ref-output.sh" HEAD 2>&1)
            GATE_RC=$?
        }

        echo "TEST D2: a baseline that produced 0 bytes is a harness error, never a content diff"
        # A base ref whose analyzer dies before printing writes NOTHING on either
        # stream, so the stderr guard alone never fires -- and cmp then reports
        # the whole AFTER report as newly added: content FAILs, 0 harness errors,
        # exactly the outcome harness_fail's own docstring says is impossible.
        cat > "$FIXROOT/gate-dead.py" <<'PY'
import sys
sys.exit(1)
PY
        cat > "$FIXROOT/gate-live.py" <<'PY'
import sys
print("{}")
sys.exit(1)
PY
        build_gate_fixture "$FIXROOT/gate-dead.py" "$FIXROOT/gate-live.py"
        run_gate
        assert_contains "an empty baseline is classified as a harness error" \
            "$GATE_OUT" "0 bytes on stdout"
        assert_contains "an empty baseline reports STATUS=HARNESS_ERROR" "$GATE_OUT" "STATUS=HARNESS_ERROR"
        assert_contains "an empty baseline reports no content failures"   "$GATE_OUT" "FAILED=0"
        assert_eq "an empty baseline exits 2, not 1" "$GATE_RC" "2"
        rm -rf "$GATE_DIR"

        # CONTROL: a baseline that DID run and genuinely differs must still be
        # reported as a content FAIL. Without this, classifying every difference
        # as a harness error passes the assertions above and destroys the gate.
        cat > "$FIXROOT/gate-live2.py" <<'PY'
import sys
print("{\"different\": true}")
sys.exit(1)
PY
        build_gate_fixture "$FIXROOT/gate-live.py" "$FIXROOT/gate-live2.py"
        run_gate
        assert_contains "CONTROL: a real content difference is still a FAIL" \
            "$GATE_OUT" "  FAIL json @"
        assert_absent "CONTROL: a real content difference is NOT a harness error" \
            "$GATE_OUT" "HARNESS ERROR json @"
        rm -rf "$GATE_DIR"

        echo "TEST D3: a baseline identical to the analyzer under test compares nothing"
        # BASE_REF defaults to origin/main, so this is the state the gate enters
        # the moment this PR merges -- and it is silent: 7 green assertions over
        # a file compared with itself.
        build_gate_fixture "$FIXROOT/gate-live.py" "$FIXROOT/gate-live.py"
        run_gate
        assert_contains "an identical baseline is a harness error" \
            "$GATE_OUT" "byte-identical to the analyzer under test"
        assert_contains "an identical baseline reports STATUS=HARNESS_ERROR" "$GATE_OUT" "STATUS=HARNESS_ERROR"
        assert_contains "an identical baseline scores no passes"             "$GATE_OUT" "PASSED=0"
        assert_eq "an identical baseline exits 2, not 0" "$GATE_RC" "2"
        rm -rf "$GATE_DIR"

        # CONTROL: files that genuinely DIFFER must still be compared, even when
        # their output is identical. Without it, "always harness-error" passes
        # every D3 assertion and the gate never compares anything again.
        cat > "$FIXROOT/gate-live-cmt.py" <<'PY'
# a comment that changes the file but not a byte of its output
import sys
print("{}")
sys.exit(1)
PY
        build_gate_fixture "$FIXROOT/gate-live.py" "$FIXROOT/gate-live-cmt.py"
        run_gate
        assert_absent "CONTROL: differing files are not called byte-identical" \
            "$GATE_OUT" "byte-identical to the analyzer under test"
        assert_contains "CONTROL: differing files with identical output still PASS" \
            "$GATE_OUT" "  ok   json @"
        rm -rf "$GATE_DIR"
    fi
fi

echo "TEST D5c: an unreadable corpus file costs that file, not the whole sweep"
# collect() read every rule and skill unguarded, so ONE dangling symlink under
# any .claude/rules/ aborted the inventory before a single finding existed --
# and symlinked rules dirs are normal under chezmoi/stow.
DR="$FIXROOT/dangling"
mkdir -p "$DR/home/.claude/rules" "$DR/proj/repo-c/.claude/rules"
cat > "$DR/proj/repo-c/.claude/rules/ghost-c.md" <<'RULE'
# Ghost C

Promoted to a skill: invoke `no-such-skill-at-all` before doing the thing —
it carries the whole procedure.
RULE
cat > "$DR/proj/repo-c/.claude/rules/plain-c.md" <<'RULE'
# Plain C
Ordinary readable prose about torque calibration on the assembly line.
RULE
ln -s "$DR/proj/repo-c/.claude/rules/gone-forever.md" \
      "$DR/proj/repo-c/.claude/rules/dangling-c.md"
[ -e "$DR/proj/repo-c/.claude/rules/dangling-c.md" ] && echo "  note  fixture symlink unexpectedly resolves"

out=$(HOME="$DR/home" python3 "$ANALYZER" --root "$DR/proj" --no-embed --fast \
    --format=json 2>"$DR/err")
rc=$?
# Exit code alone is not the test: an unguarded read_text raises, python exits 1,
# and 1 is ALSO the analyzer's normal "found something" return -- so the
# discriminator is the traceback on stderr.
assert_eq "the run survives a dangling symlink (exit 0/1, not a traceback)" \
    "$([ "$rc" -le 1 ] && [ ! -s "$DR/err" ] && echo yes || echo "no (rc=$rc, stderr=$(tail -n 1 "$DR/err" 2>/dev/null))")" "yes"
assert_eq "the run emits a parseable document" \
    "$(printf '%s' "$out" | jq -e 'has("findings")' >/dev/null 2>&1 && echo yes || echo no)" "yes"
# CONTROL: the corpus must still be ANALYZED, not merely survived. A run that
# skipped everything would also be parseable and exit cleanly.
assert_eq "CONTROL: both readable rules are still inventoried" \
    "$(printf '%s' "$out" | jq -r '.counts.rules' 2>/dev/null)" "2"
assert_contains "CONTROL: the readable stub's finding still fires" "$out" "broken_pointer_stub"

# Skipping is not swallowing. Degrading by one file SILENTLY is the worse bug:
# a corpus two thirds of which failed to open would report a clean sweep, which
# is the same false all-clear the hook repair (D1) exists to prevent, one layer
# down. So the skip must be REPORTED, and it must name the path -- nothing else
# locates the file for the reader.
assert_contains "the skipped file is reported, not silently dropped" "$out" "corpus_unreadable"
assert_eq "the unreadable path is named in the finding" \
    "$(printf '%s' "$out" | jq -r '[.findings[] | select(.kind=="corpus_unreadable") | .paths[]] | map(select(endswith("dangling-c.md"))) | length' 2>/dev/null)" "1"
assert_eq "it is warn, not error (the aggregator sorts error first across all plugins, cap 5)" \
    "$(printf '%s' "$out" | jq -r '.findings[] | select(.kind=="corpus_unreadable") | .severity' 2>/dev/null)" "warn"
# CONTROL: a corpus with nothing unreadable must NOT emit it -- otherwise the
# three assertions above pass against an analyzer that always cries wolf, and
# every clean SessionStart would carry a phantom warning.
mkdir -p "$DR/clean/repo-d/.claude/rules"
cp "$DR/proj/repo-c/.claude/rules/plain-c.md" "$DR/clean/repo-d/.claude/rules/plain-d.md"
clean_out=$(HOME="$DR/home" python3 "$ANALYZER" --root "$DR/clean" --no-embed --fast --format=json 2>/dev/null)
assert_eq "CONTROL fixture is non-vacuous: the clean corpus was actually read" \
    "$(printf '%s' "$clean_out" | jq -r '.counts.rules' 2>/dev/null)" "1"
assert_eq "CONTROL: a corpus with no unreadable file emits no corpus_unreadable" \
    "$(printf '%s' "$clean_out" | jq -r '[.findings[] | select(.kind=="corpus_unreadable")] | length' 2>/dev/null)" "0"

echo
echo "=== PROBE LIB TESTS ==="
echo "PASSED=$PASS"
echo "FAILED=$FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "STATUS=FAIL"
    exit 1
fi
echo "STATUS=OK"
exit 0
