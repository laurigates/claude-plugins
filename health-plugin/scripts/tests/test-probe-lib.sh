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

echo "TEST j: the two singular-path bugs are FIXED (assertions inverted in place)"
# #2536 pinned these two as PINNED BUG assertions because its claim was that no
# output changed. #2527b normalises the two singular `path=` construction sites
# to `paths=[...]`, and both bugs fall out AS A CONSEQUENCE rather than as
# separate edits. The assertions are inverted IN PLACE, so the behaviour change
# reads as two flipped lines rather than a deleted case and an unrelated new one.
kinds() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(sum(1 for f in d["findings"] if f["kind"]==sys.argv[1]))' "$2" 2>/dev/null || echo ERR; }
stub_paths() { printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(" ".join(p for f in d["findings"] if f["kind"]=="broken_pointer_stub" for p in f.get("paths",[])))' 2>/dev/null || echo ERR; }

# j1. `--since <ref>` filters on `not f.get("paths") or any(p in touched ...)`.
# A singular-`path` finding has no `paths` key, so `not f.get("paths")` was True
# and it was NEVER filtered -- it rode through every delta-only report as though
# its file had been touched. Both halves are asserted, because "always filtered"
# passes the drop half on its own and destroys the feature.
#
# The RETAIN half needs a REAL git repo: `changed_since` resolves touched paths
# with `git diff --name-only <ref>`, so a non-repo fixture yields an empty
# touched-set and every path-carrying finding drops for the wrong reason. An
# inherited absolute GIT_DIR/GIT_WORK_TREE overrides `git -C`, so neutralise the
# whole family first (#1745) -- this block runs before the D2/D3 fixtures that
# do the same.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
SINCE_ROOT="$FIXROOT/since/proj"
SINCE_HOME="$FIXROOT/since/home"
mkdir -p "$SINCE_ROOT/.claude/rules" "$SINCE_HOME/.claude/rules"
# Names chosen so neither is a SUBSTRING of the other: `touched`/`untouched`
# would make every `assert_contains "...touched-stub.md"` match both.
cat > "$SINCE_ROOT/.claude/rules/edited-stub.md" <<'RULE'
# Edited Stub

Promoted to a skill: invoke `no-such-skill-edited` before doing the thing —
it carries the whole procedure.
RULE
cat > "$SINCE_ROOT/.claude/rules/pristine-stub.md" <<'RULE'
# Pristine Stub

Promoted to a skill: invoke `no-such-skill-pristine` before doing the thing —
it carries the whole procedure.
RULE
git -C "$SINCE_ROOT" init -q >/dev/null 2>&1
git -C "$SINCE_ROOT" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$SINCE_ROOT" -c user.email=t@t -c user.name=t \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q -m baseline >/dev/null 2>&1
printf '\nAn edit that changes the file but not its broken target.\n' \
    >> "$SINCE_ROOT/.claude/rules/edited-stub.md"

out=$(HOME="$SINCE_HOME" python3 "$ANALYZER" --root "$SINCE_ROOT" --no-embed --fast \
    --format=json 2>/dev/null)
# FIXTURE VALIDITY: without --since both stubs must fire, or the filtered count
# below is 1 because only one finding ever existed.
assert_eq "FIXTURE: both broken stubs are found with no --since" \
    "$(kinds "$out" broken_pointer_stub)" "2"

out=$(HOME="$SINCE_HOME" python3 "$ANALYZER" --root "$SINCE_ROOT" --no-embed --fast \
    --format=json --since HEAD 2>/dev/null)
assert_eq "--since now FILTERS a singular-path stub whose file was NOT touched" \
    "$(kinds "$out" broken_pointer_stub)" "1"
assert_contains "--since RETAINS the stub whose file WAS touched" \
    "$(stub_paths "$out")" "edited-stub.md"
assert_absent "the untouched stub's path is gone from the report" \
    "$(stub_paths "$out")" "pristine-stub.md"

# The original CONTROL stays: a paths-carrying finding in a NON-repo corpus has
# an empty touched-set, so it is still correctly dropped.
out=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json \
    --since HEAD 2>/dev/null)
assert_eq "CONTROL: --since still drops an untouched paths-carrying finding" \
    "$(kinds "$out" duplicate_rule_lexical)" "0"
assert_eq "the untouched singular-path stub is dropped here too" \
    "$(kinds "$out" broken_pointer_stub)" "0"

# TEST N6: --since is STRUCTURALLY BLIND to ~/.claude/rules. Pinned, not fixed.
# HOME_RULES is scanned regardless of --root, but changed_since() walks only
# root.rglob(".git") plus root -- so a home-rule path is outside every repo it
# asks and can never enter `touched`. Pre-normalisation the two singular-`path`
# kinds escaped through the `not f.get("paths")` arm by accident; now they are
# filtered like everything else. See the reasoning at the filter in
# config-drift.py: this is a recorded decision, and a change to it should fail
# here rather than pass silently.
cat > "$SINCE_HOME/.claude/rules/home-stub.md" <<'RULE'
# Home Stub

Promoted to a skill: invoke `no-such-skill-home` before doing the thing —
it carries the whole procedure.
RULE
out=$(HOME="$SINCE_HOME" python3 "$ANALYZER" --root "$SINCE_ROOT" --no-embed --fast \
    --format=json 2>/dev/null)
# FIXTURE VALIDITY: the home rule must be in the corpus at all. Without this the
# --since assertion below passes against an analyzer that never read HOME_RULES.
assert_eq "FIXTURE: the home-rule stub fires with no --since (3 stubs now)" \
    "$(kinds "$out" broken_pointer_stub)" "3"
assert_contains "FIXTURE: the home-rule stub's path is in the unfiltered report" \
    "$(stub_paths "$out")" "home-stub.md"
# Without this the case does not pin HOME-ness at all. Move the fixture into
# $SINCE_ROOT and every assertion below still passes -- an UNTRACKED file inside
# the repo is dropped by the same filter for a different reason, because
# `changed_since` uses `git diff --name-only HEAD`, which never lists untracked
# paths. The drop assertion's own wording ("no repo contains its path") would
# then be satisfied by a case where one does.
assert_eq "FIXTURE: the home-rule stub's path is OUTSIDE the sandbox repo" \
    "$(printf '%s' "$(stub_paths "$out")" | tr ' ' '\n' | grep -c "^$SINCE_HOME/")" "1"

out=$(HOME="$SINCE_HOME" python3 "$ANALYZER" --root "$SINCE_ROOT" --no-embed --fast \
    --format=json --since HEAD 2>/dev/null)
assert_absent "--since drops the home-rule finding (no repo contains its path)" \
    "$(stub_paths "$out")" "home-stub.md"
# CONTROL: the same filtered run must still RETAIN the in-repo touched stub, or
# "drops the home rule" is satisfied by a filter that drops everything.
assert_contains "CONTROL: the touched in-repo stub survives the same filter" \
    "$(stub_paths "$out")" "edited-stub.md"

# j2. `render_report` prints `f.get("paths", [])[:2]`, so a singular-`path`
# finding's file was never shown -- the reader was told a stub is broken and not
# which one. Inverted with N1: the path is now printed.
rep=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=report 2>/dev/null)
assert_contains "the report does list the broken stub finding" "$rep" "broken_pointer_stub"
assert_contains "--format=report now prints that stub's path" "$rep" "$STUB_PATH"

# The LARGER half of the same change: `review_staleness` also carried a singular
# `path` pre-N1, and it is the bulk of a real report (60 of 66 findings on this
# portfolio; the path lines in `render_report` went 10 -> 50). Asserting only
# the stub case leaves that half unpinned.
#
# It needs a REAL git repo and NO --fast: check_review_staleness reads a git
# commit date, and in fast mode a cache miss is SKIPPED rather than spawned, so
# the finding would never fire. SINCE_ROOT is already an initialised sandbox
# repo, and the git-env family was neutralised above (#1745).
cat > "$SINCE_ROOT/.claude/rules/stale-review.md" <<'RULE'
---
reviewed: 2000-01-01
---
# Stale Review

Provisioning the kiln requires the glaze schedule before any bisque firing is
scheduled on the studio calendar.
RULE
git -C "$SINCE_ROOT" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1
git -C "$SINCE_ROOT" -c user.email=t@t -c user.name=t \
    -c commit.gpgsign=false -c core.hooksPath=/dev/null \
    commit -q -m stale >/dev/null 2>&1
srep=$(HOME="$SINCE_HOME" python3 "$ANALYZER" --root "$SINCE_ROOT" --no-embed \
    --format=report 2>/dev/null)
# FIXTURE VALIDITY: the finding has to exist before its path line can be
# asserted -- a report missing the whole section passes an absence check.
assert_contains "FIXTURE: the review_staleness finding fires without --fast" \
    "$srep" "review_staleness"
assert_contains "--format=report prints the review_staleness path too" \
    "$srep" "stale-review.md"
# CONTROL: it is the INDENTED backticked path line render_report emits for
# `paths`, not an incidental mention of the filename in the summary (the summary
# names the rule as `stale-review`, with no extension). The absolute prefix is
# not asserted: --root is `.resolve()`d, so macOS reports /private/var/... where
# the fixture was created at /var/....
# shellcheck disable=SC2016  # the single quotes are deliberate: this is a
# literal ERE (backticks, `\.`) that must reach grep unexpanded.
assert_eq "the path is rendered as a paths line, not just named in prose" \
    "$(printf '%s\n' "$srep" | grep -cE '^  - `.*/\.claude/rules/stale-review\.md`$')" "1"

echo "TEST k: --format=status is the conformant structured-script-output block"
st=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=status 2>/dev/null)
# No `|| echo ERR` tail: the analyzer exits 1 whenever it has findings, and
# under `pipefail` that fails the whole pipeline, so the fallback would append
# ERR to a perfectly good count.
json_n=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["findings"]))' 2>/dev/null)
assert_contains "status carries the opening delimiter"   "$st" "=== CONFIG DRIFT ==="
assert_contains "status now carries the ISSUE_COUNT roll-up" "$st" "ISSUE_COUNT=$json_n"
assert_contains "status now carries the closing delimiter"   "$st" "=== END CONFIG DRIFT ==="
assert_eq "STATUS is drawn from OK|WARN|ERROR and nothing else" \
    "$(printf '%s\n' "$st" | grep -cE '^STATUS=(OK|WARN|ERROR)$')" "1"
# The two quirks that are NOT bugs, pinned so the shared renderer cannot quietly
# normalise them away. (1) the header block keeps the CALLER's order -- a sorted
# one would put ALWAYS_LOADED_RULES first, not RULES.
assert_eq "the counts header keeps the caller's order, unsorted" \
    "$(printf '%s\n' "$st" | sed -n '2p' | cut -d= -f1)" "RULES"
# (2) the derived FINDING_* counters ARE sorted, so the block does not depend on
# which finding happened to fire first.
assert_eq "FIXTURE: more than one FINDING_* line exists to be ordered" \
    "$([ "$(printf '%s\n' "$st" | grep -c '^FINDING_')" -ge 2 ] && echo yes || echo no)" "yes"
assert_eq "FINDING_* lines are sorted by kind" \
    "$(printf '%s\n' "$st" | grep '^FINDING_' | LC_ALL=C sort -c >/dev/null 2>&1 && echo sorted || echo unsorted)" "sorted"
# This caller renders EVERY finding, not a delta subset, so the severity
# counters keep their bare names -- probe-delta's NEW_* prefix answers a
# different question and a rollup grepping '^ERRORS=' must not get both.
assert_eq "the full-set counters stay ERRORS=/WARNINGS=" \
    "$(printf '%s\n' "$st" | grep -cE '^(ERRORS|WARNINGS)=')" "2"
assert_eq "no NEW_ERRORS=/NEW_WARNINGS= line appears here" \
    "$(printf '%s\n' "$st" | grep -cE '^NEW_(ERRORS|WARNINGS)=')" "0"
# The optional per-finding block is suppressed: a real corpus run reports 60+.
assert_absent "the corpus-sized ISSUES: block is not emitted" "$st" "ISSUES:"
# The status/report key transforms differ and both are deliberate.
assert_contains "status upper-cases count keys"        "$st"  "ALWAYS_LOADED_RULES="
assert_contains "the report humanises the same keys"   "$rep" "| always loaded rules |"
assert_absent  "the report does not emit KEY=VALUE"    "$rep" "ALWAYS_LOADED_RULES="

echo "TEST l: --format=probe is gone, and the three survivors still work"
err=$(python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=probe 2>&1)
rc=$?
assert_eq "--format=probe is rejected (argparse exit 2)" "$rc" "2"
assert_contains "the rejection names the removed choice" "$err" "invalid choice: 'probe'"
assert_absent "no probe document is emitted alongside the rejection" "$err" "remediation_skill"
for fmt in status report json; do
    python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format="$fmt" >/dev/null 2>&1
    frc=$?
    assert_eq "CONTROL: --format=$fmt still runs (exit 0/1)" \
        "$([ "$frc" -le 1 ] && echo yes || echo "no (rc=$frc)")" "yes"
done

echo "TEST m: normalising path -> paths is FINGERPRINT-NEUTRAL"
# This is the property that decides whether N1 was safe to ship at all: every
# baseline in existence was recorded from findings carrying a singular `path`.
# #2536's fingerprint() folds the singular into the path set precisely so this
# normalisation cannot invalidate them.
cat > "$FIXROOT/fpneutral.py" <<'PY'
from lib.probe import Finding, fingerprint

a = Finding("error", "broken_pointer_stub", "s", path="/x")
b = Finding("error", "broken_pointer_stub", "s", paths=["/x"])
print("STUB_EQUAL %s" % (fingerprint(a) == fingerprint(b)))
# CONTROL: a fingerprint that ignored paths entirely would also report EQUAL.
c = Finding("error", "broken_pointer_stub", "s", paths=["/y"])
print("STUB_DIFFERS %s" % (fingerprint(a) != fingerprint(c)))
# review_staleness carries a trailing gap_days that must not enter the identity:
# the same file drifting further must stay the SAME standing finding.
d = Finding("warn", "review_staleness", "s", path="/x", gap_days=9)
e = Finding("warn", "review_staleness", "s", paths=["/x"], gap_days=400)
print("STALENESS_EQUAL %s" % (fingerprint(d) == fingerprint(e)))
PY
out=$(py "$FIXROOT/fpneutral.py")
assert_contains "path='/x' and paths=['/x'] fingerprint identically" "$out" "STUB_EQUAL True"
assert_contains "CONTROL: a different path still fingerprints differently" "$out" "STUB_DIFFERS True"
assert_contains "the same fold holds for the review_staleness shape" "$out" "STALENESS_EQUAL True"

# ...and end to end, which is the claim that actually matters: a baseline
# recorded from the PRE-N1 document must see nothing new and nothing resolved
# when compared against the POST-N1 analyzer over the same corpus.
AFT="$FIXROOT/fp-after.json"
BEF="$FIXROOT/fp-before.json"
python3 "$ANALYZER" --root "$FIXROOT/proj" --no-embed --fast --format=json > "$AFT" 2>/dev/null
# The pre-N1 document is RECONSTRUCTED rather than produced by `git show`-ing the
# old analyzer: a ref-dependent case in a DISCOVERED test goes vacuous the moment
# this PR merges (origin/main would then BE the post-N1 analyzer and the
# comparison would assert nothing) -- the silent-identity trap
# compare-ref-output.sh documents. The reconstruction is a pure DOCUMENT
# transform of the shipped output, its fidelity is asserted below as fixture
# validity, and where the genuine pre-N1 analyzer is still reachable it is
# byte-compared against this reconstruction.
python3 - "$AFT" "$BEF" <<'PY'
import json, sys

doc = json.load(open(sys.argv[1]))
for f in doc["findings"]:
    p = f.get("paths")
    if f["kind"] in ("broken_pointer_stub", "review_staleness") and isinstance(p, list) and len(p) == 1:
        # Rebuild the key IN PLACE, not appended: the pre-N1 sites emitted
        # severity, kind, summary, path[, gap_days] in that order, and
        # Finding.to_dict() takes its order from the kwargs.
        rebuilt = {("path" if k == "paths" else k): (p[0] if k == "paths" else v) for k, v in f.items()}
        f.clear()
        f.update(rebuilt)
# The trailing newline is part of the shape: the analyzer's document reaches a
# file through `print(render_json(...))`, and `json.dump` alone would leave the
# byte comparison below failing on nothing but a missing final "\n".
open(sys.argv[2], "w").write(json.dumps(doc, indent=1) + "\n")
PY
singular_of() { python3 -c 'import json,sys; print(sum(1 for f in json.load(open(sys.argv[1]))["findings"] if "path" in f))' "$1" 2>/dev/null || echo ERR; }
assert_eq "FIXTURE: the reconstructed pre-N1 document carries singular path keys" \
    "$([ "$(singular_of "$BEF")" -ge 1 ] && echo yes || echo "no ($(singular_of "$BEF"))")" "yes"
assert_eq "FIXTURE: the current document carries none" "$(singular_of "$AFT")" "0"

# Where the genuine pre-N1 analyzer is still reachable, prove the reconstruction
# IS that analyzer's output rather than a plausible model of it.
GENUINE="$FIXROOT/genuine"
CHECKOUT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
mkdir -p "$GENUINE/lib"
if git -C "$CHECKOUT" show "origin/main:health-plugin/scripts/config-drift.py" \
        > "$GENUINE/config-drift.py" 2>/dev/null \
   && git -C "$CHECKOUT" show "origin/main:health-plugin/scripts/lib/probe.py" \
        > "$GENUINE/lib/probe.py" 2>/dev/null \
   && grep -q 'path=r\["path"\]' "$GENUINE/config-drift.py"; then
    python3 "$GENUINE/config-drift.py" --root "$FIXROOT/proj" --no-embed --fast \
        --format=json > "$FIXROOT/fp-genuine.json" 2>/dev/null
    assert_eq "the reconstruction is byte-identical to the genuine pre-N1 output" \
        "$(cmp -s "$FIXROOT/fp-genuine.json" "$BEF" && echo identical || echo differs)" "identical"
else
    echo "  note  genuine pre-N1 analyzer unreachable at origin/main — reconstruction stands on its fixture-validity assertions"
fi

BL="$FIXROOT/fp-baseline.json"
rm -f "$BL"
out=$(python3 "$DELTA" --findings "$BEF" --baseline "$BL" --probe config-drift \
    --root "$FIXROOT/proj" 2>&1)
assert_contains "the pre-N1 document records a baseline" "$out" "FIRST_RUN=true"
out=$(python3 "$DELTA" --findings "$AFT" --baseline "$BL" --probe config-drift \
    --root "$FIXROOT/proj" 2>&1)
assert_contains "a PRE-N1 baseline sees ZERO new findings post-N1" "$out" "NEW=0"
assert_contains "...and ZERO resolved"                             "$out" "RESOLVED=0"
assert_contains "so the normalisation invalidated no baseline"     "$out" "STATUS=OK"
assert_eq "every finding is CARRIED, not silently dropped" \
    "$([ "$(printf '%s\n' "$out" | grep -m1 '^CARRIED=' | cut -d= -f2)" -ge 1 ] && echo yes || echo no)" "yes"

# GUARD INTEGRITY: a delta that never reports anything would pass all four of
# those. Move ONE path in the pre-N1 document and the delta must notice.
BEF2="$FIXROOT/fp-before-moved.json"
python3 - "$BEF" "$BEF2" <<'PY'
import json, sys

doc = json.load(open(sys.argv[1]))
for f in doc["findings"]:
    if f["kind"] == "broken_pointer_stub":
        f["path"] = f["path"] + ".moved"
open(sys.argv[2], "w").write(json.dumps(doc, indent=1) + "\n")
PY
BL2="$FIXROOT/fp-baseline-moved.json"
rm -f "$BL2"
python3 "$DELTA" --findings "$BEF2" --baseline "$BL2" --probe config-drift \
    --root "$FIXROOT/proj" >/dev/null 2>&1
out=$(python3 "$DELTA" --findings "$AFT" --baseline "$BL2" --probe config-drift \
    --root "$FIXROOT/proj" 2>&1)
assert_contains "GUARD INTEGRITY: a genuinely moved path IS reported new" "$out" "NEW=1"
assert_contains "GUARD INTEGRITY: ...and the stale record resolves"       "$out" "RESOLVED=1"

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

echo "TEST N2: ISSUE_COUNT= collides across probes BY DESIGN, and the delimiter resolves it"
# `.claude/rules/structured-script-output.md` mandates the literal
# `ISSUE_COUNT=` in every conformant block, so two conformant blocks in one
# combined log necessarily both emit it. `severity_prefix` exists because
# `ERRORS=` COULD be split per probe; `ISSUE_COUNT=` cannot be, without leaving
# the block non-conformant. Pinned here so the collision reads as a deliberate
# consequence of conformance rather than an accident nobody measured.
N2ROOT="$FIXROOT/proj"
cd_status=$(python3 "$ANALYZER" --root "$N2ROOT" --no-embed --fast --format=status 2>/dev/null)
N2JSON="$FIXROOT/n2-findings.json"
N2BL="$FIXROOT/n2-baseline.json"
rm -f "$N2BL"
python3 "$ANALYZER" --root "$N2ROOT" --no-embed --fast --format=json > "$N2JSON" 2>/dev/null
# Run the delta TWICE: the first records the baseline, so the second reports a
# NEW count of 0 while config-drift reports the FULL corpus count. That gap is
# what a naive grep gets wrong.
python3 "$DELTA" --findings "$N2JSON" --baseline "$N2BL" --probe config-drift \
    --root "$N2ROOT" >/dev/null 2>&1
delta_status=$(python3 "$DELTA" --findings "$N2JSON" --baseline "$N2BL" --probe config-drift \
    --root "$N2ROOT" 2>&1)
COMBINED="$FIXROOT/n2-combined.log"
printf '%s\n%s\n' "$delta_status" "$cd_status" > "$COMBINED"

assert_eq "BOTH conformant blocks emit an ISSUE_COUNT= line" \
    "$(grep -c '^ISSUE_COUNT=' "$COMBINED")" "2"
cd_n=$(printf '%s\n' "$cd_status" | grep -m1 '^ISSUE_COUNT=' | cut -d= -f2)
dl_n=$(printf '%s\n' "$delta_status" | grep -m1 '^ISSUE_COUNT=' | cut -d= -f2)
# FIXTURE VALIDITY: a corpus where the two counts coincide asserts nothing about
# a collision.
assert_eq "FIXTURE: the two counts genuinely differ (full set vs delta)" \
    "$([ "$cd_n" != "$dl_n" ] && echo yes || echo "no (both $cd_n)")" "yes"
assert_eq "a naive grep -m1 over a combined log returns whichever printed FIRST" \
    "$(grep -m1 '^ISSUE_COUNT=' "$COMBINED" | cut -d= -f2)" "$dl_n"
# The resolution: both blocks now carry `=== END <section> ===`, so a parser can
# bracket a section and read the key inside it. config-drift's block carried no
# closing delimiter (and no ISSUE_COUNT= at all) before render_status became its
# only renderer, so section-aware parsing is possible for the first time.
assert_eq "each section is bracketed by its own closing delimiter" \
    "$(grep -c '^=== END ' "$COMBINED")" "2"
assert_eq "section-aware parsing reads the ANALYZER's own ISSUE_COUNT" \
    "$(awk '/^=== CONFIG DRIFT ===$/{f=1} f&&/^ISSUE_COUNT=/{print;exit}' "$COMBINED" | cut -d= -f2)" \
    "$cd_n"
assert_eq "section-aware parsing reads the DELTA's own ISSUE_COUNT" \
    "$(awk '/^=== CONFIG-DRIFT DELTA ===$/{f=1} f&&/^ISSUE_COUNT=/{print;exit}' "$COMBINED" | cut -d= -f2)" \
    "$dl_n"

echo "TEST N3: the hook's jq fix map covers every kind the analyzer can emit"
# The map in hooks/config-drift-probe.sh is the SINGLE SOURCE for
# kind -> remediation-skill since --format=probe was deleted, and a kind with no
# row falls to the "/health:check" fallback SILENTLY. Both sides are read out of
# the shipped files -- the kind set from config-drift.py's own `Finding(...)`
# call sites via the AST, the map keys out of the hook's own text -- so neither
# is a retyped copy (never-fabricate-test-identifiers.md § extract the code).
cat > "$FIXROOT/mapcover.py" <<'MAPCOVER'
import ast
import itertools
import re
import sys

src = open(sys.argv[1]).read()
hook = open(sys.argv[2]).read()
tree = ast.parse(src)

# The two values `Finding(... f"semantic_overlap_{a['kind']}_{b['kind']}" ...)`
# can interpolate, read off the analyzer's own SEMANTIC_KINDS assignment rather
# than assumed. That tuple is what `main()` feeds `check_semantic_dupes`, so it
# IS the interpolation domain -- and it is now the only honest source for it:
# the corpus carries four kinds but only two reach the semantic pass, so the
# former derivation (every `"kind": <const>` dict literal in the file) would
# expand 4x4 and demand map rows for twelve kinds the analyzer cannot emit.
# Since the shared `_doc()` constructor landed there are no such dict literals
# left either, so that derivation would now yield the EMPTY set and expand to
# nothing -- passing "no missing kinds" vacuously.
item_kinds = set()
for node in ast.walk(tree):
    if isinstance(node, ast.Assign) and any(
        isinstance(t, ast.Name) and t.id == "SEMANTIC_KINDS" for t in node.targets
    ):
        if isinstance(node.value, (ast.Tuple, ast.List)):
            item_kinds.update(
                e.value
                for e in node.value.elts
                if isinstance(e, ast.Constant) and isinstance(e.value, str)
            )

kinds = set()
for node in ast.walk(tree):
    if not (
        isinstance(node, ast.Call)
        and isinstance(node.func, ast.Name)
        and node.func.id == "Finding"
        and len(node.args) >= 2
    ):
        continue
    arg = node.args[1]
    if isinstance(arg, ast.Constant):
        kinds.add(arg.value)
    elif isinstance(arg, ast.JoinedStr):
        tmpl = "".join(
            p.value if isinstance(p, ast.Constant) else "{}" for p in arg.values
        )
        for combo in itertools.product(sorted(item_kinds), repeat=tmpl.count("{}")):
            kinds.add(tmpl.format(*combo))
    else:
        kinds.add("UNPARSEABLE_KIND_ARG")

m = re.search(r"def fix:\s*\{(.*?)\}\[\.kind\]", hook, re.S)
mapped = set(re.findall(r'"([a-z0-9_]+)"\s*:', m.group(1))) if m else set()

# UNREACHABLE, and deliberately unmapped: check_semantic_dupes is fed
# `rules + skills` and iterates np.triu_indices(k=1), so `a` is always the lower
# index -- a cross-kind pair is always (rule, skill), never (skill, rule).
unreachable = {"semantic_overlap_skill_rule"}
reachable = kinds - unreachable

print("ITEM_KINDS %s" % ",".join(sorted(item_kinds)))
print("DERIVED_N %d" % len(kinds))
print("REACHABLE_N %d" % len(reachable))
print("MAPPED_N %d" % len(mapped))
print("MISSING %s" % (",".join(sorted(reachable - mapped)) or "NONE"))
print("UNEMITTABLE_ROWS %s" % (",".join(sorted(mapped - kinds)) or "NONE"))
print("UNREACHABLE_ABSENT %s" % (not (unreachable & mapped)))
# CONTROL: the membership test must be able to FAIL. A kind that does not exist
# must not be reported as mapped.
print("CONTROL_FABRICATED_MAPPED %s" % ("no_such_kind_at_all" in mapped))
MAPCOVER
out=$(python3 "$FIXROOT/mapcover.py" "$ANALYZER" "$HOOK_SRC" 2>&1)
# FIXTURE VALIDITY first: an AST walk that matched nothing satisfies "no missing
# kinds" trivially, and a regex that matched no map keys satisfies "no unmapped
# rows" the same way.
assert_contains "the semantic-pass kinds are derived from SEMANTIC_KINDS, not assumed" "$out" "ITEM_KINDS rule,skill"
assert_contains "FIXTURE: the derivation found every construction site" "$out" "DERIVED_N 17"
assert_contains "FIXTURE: 16 of those kinds are reachable" "$out" "REACHABLE_N 16"
assert_contains "FIXTURE: the map's keys were actually parsed out of the hook" "$out" "MAPPED_N 16"
assert_absent "every Finding( kind argument was parseable" "$out" "UNPARSEABLE_KIND_ARG"
assert_contains "CONTROL: a fabricated kind is not reported as mapped" \
    "$out" "CONTROL_FABRICATED_MAPPED False"
# The claim itself.
assert_contains "every emittable kind has an EXPLICIT row (none falls to the fallback)" \
    "$out" "MISSING NONE"
assert_contains "the map carries no row for a kind the analyzer cannot emit" \
    "$out" "UNEMITTABLE_ROWS NONE"
assert_contains "semantic_overlap_skill_rule stays unmapped (triu makes it unreachable)" \
    "$out" "UNREACHABLE_ABSENT True"

echo "TEST N4: every remediation row names a skill that can SEE its finding's corpus"
# The defect this pins: the two widened duplicate kinds were routed to
# `/agent-patterns:meta-promote` by copying the `duplicate_rule_lexical` row.
# meta-promote builds its inventory from `<scope>/.claude/{rules,skills,commands,
# agents}/` and `<scope>/*/.claude/{...}/`. A repo-root CLAUDE.md is in NEITHER
# layer, and a plugin agent at `*-plugin/agents/*.md` is not under
# `.claude/agents/` either -- so both rows named a skill that structurally cannot
# open the file the finding is about. The rule row IS correct, which is exactly
# why copying it read as safe.
#
# SEMANTIC, not a spelling check: the map is parsed out of the SHIPPED hook, the
# target is RESOLVED to a real SKILL.md on disk, and that skill's own inventory
# text is what is asserted on. A grep for the string "meta-context-diet" would
# pass against a row naming a skill that does not exist.
MARKETPLACE_ROOT="$(cd "${SCRIPTS_DIR}/../.." && pwd)"
cat > "$FIXROOT/routing.py" <<'ROUTING'
import re
import sys
from pathlib import Path

hook, marketplace = sys.argv[1], Path(sys.argv[2])
m = re.search(r"def fix:\s*\{(.*?)\}\[\.kind\]", Path(hook).read_text(), re.S)
rows = dict(re.findall(r'"([a-z0-9_]+)"\s*:\s*"([^"]+)"', m.group(1))) if m else {}

# Inventory probes, spelled once. Each is a literal a skill's own Context block
# or discovery step uses to NAME the corpus it opens -- not a description.
AGENT_GLOBS = ("agents/*", "agents-plugin/agents", "-plugin/agents", "*/agents/")
DOT_CLAUDE_INVENTORY = ".claude/{rules,skills,commands,agents}/"


def sees_claude_md(body):
    return "CLAUDE.md" in body


def sees_plugin_agents(body):
    return any(g in body for g in AGENT_GLOBS)


def resolve(cmd):
    """`/ns:name` -> the SKILL.md that serves it, or None.

    The house spelling drops the plugin's leading segment (`health-check` is
    `/health:check`), so both the bare name and the `ns-name` join are tried.
    """
    ns, _, name = cmd.lstrip("/").partition(":")
    for candidate in (name, ns + "-" + name):
        for skill in marketplace.glob("*-plugin/skills/" + candidate + "/SKILL.md"):
            return skill
    return None


for kind in sorted(rows):
    cmd = rows[kind]
    skill = resolve(cmd)
    state = "RESOLVED" if skill else "UNRESOLVED"
    print("ROW %s %s %s" % (kind, cmd, state))
    if skill is None:
        continue
    body = skill.read_text()
    print("SEES_CLAUDE_MD %s %s" % (kind, sees_claude_md(body)))
    print("SEES_PLUGIN_AGENTS %s %s" % (kind, sees_plugin_agents(body)))

# FIXTURE VALIDITY for the claim that meta-promote was the WRONG target: read
# its own inventory and show it names neither widened corpus.
mp = resolve("/agent-patterns:meta-promote")
mp_body = mp.read_text() if mp else ""
print("META_PROMOTE_RESOLVED %s" % bool(mp))
print("META_PROMOTE_SEES_PLUGIN_AGENTS %s" % sees_plugin_agents(mp_body))
print("META_PROMOTE_INVENTORY_IS_DOT_CLAUDE %s" % (DOT_CLAUDE_INVENTORY in mp_body))
ROUTING
rout=$(python3 "$FIXROOT/routing.py" "$HOOK_SRC" "$MARKETPLACE_ROOT" 2>&1)

# FIXTURE VALIDITY first: an unresolvable target makes every "SEES_" line absent,
# which would satisfy an assert_absent trivially.
assert_contains "the agent-duplicate row resolves to a real skill" \
    "$rout" "ROW duplicate_agent_lexical /agents:analyze RESOLVED"
assert_contains "the CLAUDE.md-duplicate row resolves to a real skill" \
    "$rout" "ROW duplicate_claude_md_lexical /agent-patterns:meta-context-diet RESOLVED"
# The claim: each target's own inventory names the corpus its finding is about.
assert_contains "the CLAUDE.md-duplicate target inventories CLAUDE.md files" \
    "$rout" "SEES_CLAUDE_MD duplicate_claude_md_lexical True"
assert_contains "the agent-duplicate target inventories agent files" \
    "$rout" "SEES_PLUGIN_AGENTS duplicate_agent_lexical True"
# CONTROL, and the reason the original routing looked safe: the rule row is
# still meta-promote, and meta-promote is still the right answer for it. Without
# this, a map that routed everything to /health:check would pass the two rows
# above by never naming meta-promote at all.
assert_contains "CONTROL: the RULE duplicate still routes to meta-promote" \
    "$rout" "ROW duplicate_rule_lexical /agent-patterns:meta-promote RESOLVED"
# FIXTURE VALIDITY for the defect itself: meta-promote's inventory really is
# `.claude/`-scoped and names neither widened corpus.
assert_contains "FIXTURE: meta-promote resolves" "$rout" "META_PROMOTE_RESOLVED True"
assert_contains "FIXTURE: meta-promote's inventory is the .claude/ tree" \
    "$rout" "META_PROMOTE_INVENTORY_IS_DOT_CLAUDE True"
assert_contains "FIXTURE: meta-promote never inventories plugin agents" \
    "$rout" "META_PROMOTE_SEES_PLUGIN_AGENTS False"
# Every row must at least resolve -- a remediation naming a skill that does not
# exist is a dead pointer whichever corpus it could see.
assert_absent "no remediation row names a skill that does not exist" "$rout" "UNRESOLVED"

echo "TEST N5: the SessionStart nudge, through the hook's OWN jq pipeline"
# `duplicate_claude_md_lexical` sorts alphabetically first among the warns, so at
# both portfolio roots the widening put it in slot 1 and the displacing finding
# was a byte-identical CLAUDE.md between a VENDORED clone and its source --
# expected duplication, not drift. Demoting it to `info` is the fix for the
# HEADLINE. It is NOT a fix for the displacement, and this case pins both halves
# so the distinction stays a recorded decision rather than a hope.
#
# The pipeline is EXTRACTED from the shipped hook, never retyped: a retyped copy
# is not the code under test (never-fabricate-test-identifiers.md).
python3 - "$HOOK_SRC" > "$FIXROOT/forward.jq" <<'EXTRACT'
import re
import sys

src = open(sys.argv[1]).read()
m = re.search(r"(def rank:.*?\| \[\.severity, \.kind, \.summary, \.fix\] \| @tsv)", src, re.S)
if not m:
    sys.exit("could not extract the forwarding pipeline from the hook")
print(m.group(1))
EXTRACT
if [ ! -s "$FIXROOT/forward.jq" ]; then
    bad "FIXTURE: the forwarding pipeline was extracted from the hook" "non-empty jq" "empty"
elif ! command -v jq >/dev/null 2>&1; then
    ok "SKIP: jq not available for the forwarding-pipeline case"
else
    ok "FIXTURE: the forwarding pipeline was extracted from the hook"
    # Reproduces the ~/repos kind histogram measured 2026-08-29 with --fast
    # --no-embed: 7 duplicate_claude_md_lexical, 14 duplicate_rule_lexical,
    # 71 review_staleness, 19 rule_covered_by_skill, 1 frontmatter_coverage.
    # Severities are read from the ANALYZER rather than typed here, so a future
    # severity change moves this fixture with it.
    python3 - "$ANALYZER" > "$FIXROOT/histogram.json" <<'HIST'
import importlib.util
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))
spec = importlib.util.spec_from_file_location("config_drift", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

# The two duplicate kinds' severities come from the shipped constructor.
dup = {
    k: mod._lexical_finding(k, "s", 0.9, ["/a", "/b"])["severity"]
    for k in ("rule", "agent", "claude_md")
}
counts = {
    ("duplicate_claude_md_lexical", dup["claude_md"]): 7,
    ("duplicate_rule_lexical", dup["rule"]): 14,
    ("review_staleness", "warn"): 71,
    ("rule_covered_by_skill", "info"): 19,
    ("frontmatter_coverage", "info"): 1,
}
findings = [
    {"severity": sev, "kind": kind, "summary": f"{kind} #{i}"}
    for (kind, sev), n in counts.items()
    for i in range(n)
]
json.dump({"findings": findings, "counts": {}}, sys.stdout)
HIST
    fwd=$(jq -r -f "$FIXROOT/forward.jq" < "$FIXROOT/histogram.json" 2>&1)
    slot1=$(printf '%s\n' "$fwd" | sed -n '1p' | cut -f2)
    forwarded=$(printf '%s\n' "$fwd" | cut -f2 | sort | tr '\n' ',')

    assert_eq "FIXTURE: the cap forwards exactly 4 rows" \
        "$(printf '%s\n' "$fwd" | grep -c .)" "4"
    # The half the demotion DOES buy: slot 1 is real drift, not a vendored-clone
    # artifact. Pre-demotion this was duplicate_claude_md_lexical at both roots.
    assert_eq "slot 1 is the RULE duplicate, not the CLAUDE.md duplicate" \
        "$slot1" "duplicate_rule_lexical"
    assert_contains "the CLAUDE.md duplicate is still forwarded, below the warns" \
        "$forwarded" "duplicate_claude_md_lexical"
    # The half it does NOT buy, pinned so nobody claims otherwise: with five
    # kinds and a cap of four, one is dropped whatever the severities are, and
    # within `info` frontmatter_coverage beats rule_covered_by_skill on the
    # alphabetical tiebreak either way. The cap and the sort are shared across
    # every plugin and are not this probe's to change.
    assert_absent "RECORDED: rule_covered_by_skill is still displaced by the cap" \
        "$forwarded" "rule_covered_by_skill"
    # Guard integrity: the two rows above are about ORDER, so a pipeline that
    # forwarded nothing, or forwarded them in a fixed order regardless of
    # severity, must fail something. Re-run with the CLAUDE.md duplicate forced
    # back to `warn` and require slot 1 to move -- that is the pre-fix behaviour,
    # reproduced rather than asserted.
    warn_slot1=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for f in d["findings"]:
    if f["kind"] == "duplicate_claude_md_lexical":
        f["severity"] = "warn"
json.dump(d, sys.stdout)
' "$FIXROOT/histogram.json" | jq -r -f "$FIXROOT/forward.jq" | sed -n '1p' | cut -f2)
    assert_eq "CONTROL: at warn severity it takes slot 1 again (the pre-fix state)" \
        "$warn_slot1" "duplicate_claude_md_lexical"
fi

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
