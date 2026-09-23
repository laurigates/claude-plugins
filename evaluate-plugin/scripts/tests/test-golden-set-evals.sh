#!/usr/bin/env bash
# Regression test for evaluate-plugin/scripts/check_golden_set_evals.py (#2144).
#
# The golden set's evalCoverageFloor counts that an evals.json EXISTS. This test
# pins the two things existence cannot: that every eval-ready canary's suite is
# well-formed enough for grade_deterministic.py to grade, and that its typed
# checks discriminate -- a correct answer clears them and a wrong one (for an
# abstention case, a fabricated one) fails them.
#
# Case A runs the checker on the real repo. Cases B-K each break ONE thing in a
# faithful copy of the golden-set corpus and require the checker to name it;
# case B0 requires the unbroken copy to pass, without which every "must fail"
# below would hold for a checker that fails everything.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../../.." && pwd)"
CHECK="$repo_root/evaluate-plugin/scripts/check_golden_set_evals.py"

pass=0; fail=0
assert() { if [ "$2" = "true" ]; then pass=$((pass+1)); else echo "FAIL: $1" >&2; fail=$((fail+1)); fi; }
has() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }
val() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }
ge() { [ -n "$1" ] && [ "$1" -ge "$2" ] 2>/dev/null && echo true || echo false; }

fx="$(mktemp -d)"
if [ -z "$fx" ] || [ ! -d "$fx" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$fx"' EXIT

# --- A: the real repo --------------------------------------------------------
echo "=== A: every eval-ready canary validates and its probes bite ==="
out="$(python3 "$CHECK" 2>&1)"; rc=$?
assert "A exits 0" "$([ $rc -eq 0 ] && echo true || echo false)"
assert "A STATUS=OK" "$(has "$out" 'STATUS=OK')"
ready="$(val "$out" CANARIES_EVAL_READY)"
# The ratchet (#2144): seven suites landed beside git-commit's. Lowering the
# floor or deleting a suite must turn this red, not just the monthly sweep.
assert "A at least 8 canaries are eval-ready" "$(ge "$ready" 8)"
assert "A the declared floor is at least 8" "$(ge "$(val "$out" COVERAGE_FLOOR)" 8)"
# Non-vacuity: every ready suite validated, and probes actually ran.
assert "A every ready suite validated" "$([ "$(val "$out" SUITES_VALID)" = "$ready" ] && echo true || echo false)"
assert "A ran at least two probes per suite" "$(ge "$(val "$out" PROBES_RUN)" $((ready * 2)))"
assert "A carries at least 7 abstention cases" "$(ge "$(val "$out" ABSTAIN_CASES)" 7)"

# --- fixture: a faithful copy of the corpus the checker reads ---------------
stage() {
  local d="$fx/$1"
  python3 - "$repo_root" "$d" <<'PY'
import json, shutil, sys
from pathlib import Path
src, dst = Path(sys.argv[1]), Path(sys.argv[2])
def cp(rel):
    (dst / rel).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src / rel, dst / rel)
cp("evaluate-plugin/golden-set.json")
for name in ("golden-set-probes.json", "gc-001-good.txt", "gc-001-bad.txt"):
    cp(f"evaluate-plugin/scripts/tests/fixtures/{name}")
for c in json.loads((src / "evaluate-plugin/golden-set.json").read_text())["canaries"]:
    plugin, skill = c["skill"].split("/", 1)
    base = f"{plugin}/skills/{skill}"
    if (src / base / "evals.json").is_file():
        cp(f"{base}/evals.json")
        cp(f"{base}/SKILL.md")
PY
}

# edit <dir> <relpath> <python-expression-over-d> -- mutate one JSON file in place
edit() {
  python3 - "$fx/$1/$2" "$3" <<'PY'
import json, sys
path, expr = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))
exec(expr)
json.dump(d, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY
}

run() { python3 "$CHECK" --project-dir "$fx/$1" 2>&1; }
RG=tools-plugin/skills/rg-code-search/evals.json
PROBES=evaluate-plugin/scripts/tests/fixtures/golden-set-probes.json

echo "=== B0: the unmutated copy passes ==="
stage b0; out="$(run b0)"; rc=$?
assert "B0 a faithful copy exits 0" "$([ $rc -eq 0 ] && echo true || echo false)"
assert "B0 a faithful copy validates the same suites" "$([ "$(val "$out" SUITES_VALID)" = "$ready" ] && echo true || echo false)"

echo "=== B: an abstention case without its fabrication detector is caught ==="
stage b
edit b "$RG" 'c=[x for x in d["evals"] if x["id"]=="rg-005"][0]; c["expectations"]=[e for e in c["expectations"] if not (isinstance(e,dict) and e.get("check")=="absent_regex")]'
out="$(run b)"; rc=$?
assert "B exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
# The fabrication now fails only the refusal-marker regex -- the probabilistic
# half -- so it no longer fails for zero judge tokens on an absent_regex.
assert "B the fabricated probe no longer fails on an absent_regex" "$(has "$out" 'fail_probe_wrong_check')"
assert "B the suite is reported as unprobed for abstention" "$(has "$out" 'abstention_unprobed')"

echo "=== C: a pattern that does not compile ==="
stage c
edit c "$RG" 'd["evals"][0]["expectations"][0]["pattern"]="(unbalanced"'
out="$(run c)"; rc=$?
assert "C exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "C names pattern_invalid" "$(has "$out" 'pattern_invalid')"

echo "=== D: skill_name drifts from the SKILL.md name ==="
stage d
edit d "$RG" 'd["skill_name"]="rg-search"'
out="$(run d)"; rc=$?
assert "D exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "D names skill_name_mismatch" "$(has "$out" 'skill_name_mismatch')"

echo "=== E: a probe for a case that does not exist ==="
stage e
edit e "$PROBES" 'd["probes"][2]["case"]="gpt-999"'
out="$(run e)"; rc=$?
assert "E exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "E names probe_unknown_case" "$(has "$out" 'probe_unknown_case')"

echo "=== F: a suite with no probes at all ==="
stage f
edit f "$PROBES" 'd["probes"]=[p for p in d["probes"] if p["suite"]!="tools-plugin/jq-json-processing"]'
out="$(run f)"; rc=$?
assert "F exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "F names no_pass_probe" "$(has "$out" 'no_pass_probe')"
assert "F names no_fail_probe" "$(has "$out" 'no_fail_probe')"

echo "=== G: a regex flag the grader rejects ==="
stage g
edit g "$RG" 'd["evals"][0]["expectations"][1]["flags"]="z"'
out="$(run g)"; rc=$?
assert "G exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "G names check_malformed" "$(has "$out" 'check_malformed')"

echo "=== H: a misspelled expected_outcome ==="
stage h
edit h "$RG" '[x for x in d["evals"] if x["id"]=="rg-005"][0]["expected_outcome"]="abstian"'
out="$(run h)"; rc=$?
assert "H exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "H names expected_outcome_invalid" "$(has "$out" 'expected_outcome_invalid')"

echo "=== I: coverage below the declared floor ==="
stage i
rm -f "$fx/i/$RG"
out="$(run i)"; rc=$?
assert "I exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "I names coverage_below_floor" "$(has "$out" 'coverage_below_floor')"

echo "=== J: a pass probe that no longer clears its checks ==="
stage j
edit j "$PROBES" 'p=[x for x in d["probes"] if x["case"]=="rg-001" and x["expect"]=="pass"][0]; p["output"]="grep -rn requests src/"'
out="$(run j)"; rc=$?
assert "J exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "J names pass_probe_failed" "$(has "$out" 'pass_probe_failed')"

echo "=== K: nothing eval-ready is an error, not a clean pass ==="
stage k
edit k evaluate-plugin/golden-set.json 'd["canaries"]=[{"skill":"nope-plugin/nope","pattern":"x"}]; d["evalCoverageFloor"]=0'
out="$(run k)"; rc=$?
assert "K exits 1" "$([ $rc -eq 1 ] && echo true || echo false)"
assert "K names nothing_scanned" "$(has "$out" 'nothing_scanned')"

echo "=== L: unknown argument exits 2 ==="
python3 "$CHECK" --nope >/dev/null 2>&1; rc=$?
assert "L exits 2" "$([ $rc -eq 2 ] && echo true || echo false)"

echo ""
echo "PASSED=$pass"
echo "FAILED=$fail"
[ "$fail" -gt 0 ] && { echo "STATUS=FAIL"; exit 1; }
echo "STATUS=OK"
