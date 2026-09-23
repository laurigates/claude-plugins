#!/usr/bin/env bash
# shellcheck disable=SC2016  # the backticks are literal markdown the comment must contain
# Regression test for scripts/config-drift-audit.sh (issue #2554) -- the logic
# behind .github/workflows/config-drift-audit.yml, executed against a planted
# corpus instead of waiting for a scheduled run to exercise it.
#
# Each acceptance item on #2554 is a case here:
#   first run records silently           -> A
#   unchanged corpus: no comment         -> B
#   a new finding is reported once, with score and both paths -> C
#   a committed waiver suppresses a pair and an edit revives it -> D
#   analyzer failure comments an error, never silence -> E
#   a lost baseline on a non-first run is loud -> F
#   the planted-duplicate control reports exactly one finding -> G
# and the control's own guard-integrity half: a broken delta must FAIL it (H).
#
# The analyzer runs in its cheap tier (CONFIG_DRIFT_AUDIT_CHEAP_TIER=1): no
# model, no network, no git. Everything else -- probe-delta, the baseline file,
# the planted control -- is the real code.
#
# `--expect-baseline` is added to probe-delta by #2749. The script passes it on
# every non-first run. Until #2749 is on this branch the steady-state cases run
# with --prior-success false, which exercises the same delta path whenever the
# baseline file is present; case F asserts the loud outcome in BOTH worlds.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
audit="$repo_root/scripts/config-drift-audit.sh"
real_analyzer="$repo_root/health-plugin/scripts/config-drift.py"
real_delta="$repo_root/health-plugin/scripts/probe-delta.py"

pass_count=0
fail_count=0
assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}
has_line() { printf '%s\n' "$1" | grep -qxF -- "$2" && echo true || echo false; }
contains() { grep -qF -- "$2" "$1" 2>/dev/null && echo true || echo false; }
lacks_file() { [ ! -e "$1" ] && echo true || echo false; }
rc_is() { [ "$1" -eq "$2" ] && echo true || echo false; }

fx="$(mktemp -d)"
if [ -z "$fx" ] || [ ! -d "$fx" ]; then echo "mktemp failed" >&2; exit 1; fi
fx="$(cd "$fx" && pwd -P)"
trap 'rm -rf "$fx"' EXIT

# The analyzer always scans ~/.claude/rules; point HOME at an empty dir so the
# developer's own rules never enter the corpus.
mkdir -p "$fx/home"
export HOME="$fx/home"
export CONFIG_DRIFT_AUDIT_CHEAP_TIER=1
unset CONFIG_DRIFT_AUDIT_ANALYZER CONFIG_DRIFT_AUDIT_PROBE_DELTA

if grep -qF -- '--expect-baseline' <<<"$(python3 "$real_delta" --help 2>&1)"; then
  expect_supported=true
  steady=true
else
  expect_supported=false
  steady=false
  echo "NOTE: probe-delta has no --expect-baseline yet (#2749); steady-state cases run with --prior-success false"
fi

root="$fx/root"
state="$fx/state"
mkdir -p "$root/.claude/rules"
rules="$root/.claude/rules"
cat > "$rules/log-rotation.md" <<'EOF'
---
reviewed: 2026-09-01
---
# Log Rotation

Rotate the application logs every night, compress the previous day's files,
and delete anything older than thirty days from the archive volume. A rotation
that fails leaves the old file in place and pages whoever is on call.
EOF
cat > "$rules/backup-window.md" <<'EOF'
---
reviewed: 2026-09-01
---
# Backup Window

Database snapshots run between two and four in the morning, when write traffic
is lowest. A snapshot that overruns the window is cancelled and retried the
next night rather than competing with the morning batch jobs.
EOF

# run <name> [audit args...] -- one audit run; sets $out and $rc.
run() {
  local name="$1"; shift
  out="$(bash "$audit" --root "$root" --out-dir "$fx/out-$name" --state-dir "$state" "$@" 2>&1)"
  rc=$?
  comment_file="$fx/out-$name/comment.md"
}

# --- A: the first run records a baseline and says nothing ---------------------
echo "=== A: first run ==="
run a --prior-success false
assert "A: first run exits 0" "$(rc_is "$rc" 0)"
assert "A: first run is FIRST_RUN=true" "$(has_line "$out" 'FIRST_RUN=true')"
assert "A: first run records the baseline" "$(has_line "$out" 'RECORDED=true')"
assert "A: the baseline file exists" "$([ -s "$state/baseline.json" ] && echo true || echo false)"
assert "A: first run writes no comment" "$(has_line "$out" 'COMMENT=false')"
assert "A: first run leaves no comment file" "$(lacks_file "$comment_file")"

# --- B: an unchanged corpus is silent -----------------------------------------
echo "=== B: unchanged corpus ==="
run b --prior-success "$steady"
assert "B: unchanged run exits 0" "$(rc_is "$rc" 0)"
assert "B: unchanged run is not a first run" "$(has_line "$out" 'FIRST_RUN=false')"
assert "B: unchanged run reports NEW=0" "$(has_line "$out" 'NEW=0')"
assert "B: unchanged run writes no comment" "$(has_line "$out" 'COMMENT=false')"
assert "B: unchanged run is STATUS=OK" "$(has_line "$out" 'STATUS=OK')"

# --- C: a new finding is reported once, with its score and both paths ----------
echo "=== C: new duplicate rule ==="
cp "$rules/log-rotation.md" "$rules/log-rotation-copy.md"
run c --prior-success "$steady"
assert "C: a new finding still exits 0 (a report, not a failure)" "$(rc_is "$rc" 0)"
assert "C: the run is STATUS=WARN" "$(has_line "$out" 'STATUS=WARN')"
assert "C: exactly one new finding" "$(has_line "$out" 'NEW=1')"
assert "C: a comment is written" "$(has_line "$out" 'COMMENT=true')"
assert "C: the comment names the finding kind" "$(contains "$comment_file" '`duplicate_rule_lexical`')"
assert "C: the comment carries the score" "$(contains "$comment_file" '| 1.0 |')"
assert "C: the comment names the original, relative to the root" "$(contains "$comment_file" '`.claude/rules/log-rotation.md`')"
assert "C: the comment names the copy, relative to the root" "$(contains "$comment_file" '`.claude/rules/log-rotation-copy.md`')"
assert "C: the comment does not leak the absolute root" "$([ "$(contains "$comment_file" "$root")" = false ] && echo true || echo false)"
run c2 --prior-success "$steady"
assert "C2: the same finding is not reported twice" "$(has_line "$out" 'NEW=0')"
assert "C2: the rerun writes no comment" "$(has_line "$out" 'COMMENT=false')"

# --- D: a committed waiver suppresses the pair; editing a side revives it ------
echo "=== D: waiver suppress + revive ==="
waivers="$fx/waivers.json"
python3 - "$waivers" "$rules/log-rotation.md" "$rules/log-rotation-copy.md" <<'PY'
import hashlib, json, os, sys
out, a, b = sys.argv[1:4]
def h(p):
    return hashlib.sha256(open(p, encoding="utf-8").read().encode()).hexdigest()[:16]
json.dump({"waivers": [{"a": os.path.realpath(a), "b": os.path.realpath(b),
                        "a_hash": h(a), "b_hash": h(b),
                        "reason": "test: deliberate copy"}]}, open(out, "w"))
PY
run d --prior-success "$steady" --waivers "$waivers"
assert "D: a waived pair exits 0" "$(rc_is "$rc" 0)"
assert "D: a waived pair reports nothing new" "$(has_line "$out" 'NEW=0')"
assert "D: a waived pair writes no comment" "$(has_line "$out" 'COMMENT=false')"
printf '\nOne edited line revives the waiver.\n' >> "$rules/log-rotation-copy.md"
run d2 --prior-success "$steady" --waivers "$waivers"
assert "D2: editing one side revives the finding" "$(has_line "$out" 'NEW=1')"
assert "D2: the revived finding is commented" "$(contains "$comment_file" '`duplicate_rule_lexical`')"
rm -f "$rules/log-rotation-copy.md"
run d3 --prior-success "$steady"

# --- E: an analyzer failure is an error comment, never silence -----------------
echo "=== E: analyzer failure ==="
cp "$state/baseline.json" "$fx/baseline.before"
cat > "$fx/crash.py" <<'PY'
import sys
print("Traceback (most recent call last):", file=sys.stderr)
print("ModuleNotFoundError: No module named 'lib'", file=sys.stderr)
sys.exit(1)
PY
CONFIG_DRIFT_AUDIT_ANALYZER="$fx/crash.py" run e --prior-success "$steady"
assert "E: an empty-output failure exits 1" "$(rc_is "$rc" 1)"
assert "E: an empty-output failure is STATUS=ERROR" "$(has_line "$out" 'STATUS=ERROR')"
assert "E: the failure is typed analyzer_failed" "$(grep -qF 'TYPE=analyzer_failed' <<<"$out" && echo true || echo false)"
assert "E: an error comment is written" "$(has_line "$out" 'COMMENT=true')"
assert "E: the comment says the analyzer failed" "$(contains "$comment_file" 'analyzer failed')"
assert "E: the comment quotes the exception line" "$(contains "$comment_file" "ModuleNotFoundError: No module named 'lib'")"
assert "E: the baseline is untouched" "$(cmp -s "$state/baseline.json" "$fx/baseline.before" && echo true || echo false)"
# Well-formed output with an exit code no completed run produces: the exit
# code alone must fail it, not just the empty-output check.
printf 'import sys\nprint("{\\"counts\\": {}, \\"findings\\": []}")\nsys.exit(3)\n' > "$fx/exit3.py"
CONFIG_DRIFT_AUDIT_ANALYZER="$fx/exit3.py" run e2 --prior-success "$steady"
assert "E2: exit 3 is a failure" "$(rc_is "$rc" 1)"
assert "E2: exit 3 is commented" "$(contains "$comment_file" 'exited 3')"
printf 'import sys\nprint("{not json")\nsys.exit(0)\n' > "$fx/garbage.py"
CONFIG_DRIFT_AUDIT_ANALYZER="$fx/garbage.py" run e3 --prior-success "$steady"
assert "E3: unparseable output exiting 0 is a failure" "$(rc_is "$rc" 1)"
assert "E3: unparseable output is commented" "$(contains "$comment_file" 'could not parse')"
assert "E3: the baseline is untouched" "$(cmp -s "$state/baseline.json" "$fx/baseline.before" && echo true || echo false)"

# --- F: a lost baseline on a non-first run is loud -----------------------------
echo "=== F: lost baseline ==="
# One real finding already in the baseline, so "re-report every finding" has
# something to re-report beyond the baseline_lost row itself.
cp "$rules/log-rotation.md" "$rules/log-rotation-copy.md"
run f0 --prior-success "$steady"
assert "F0: the pre-existing finding is recorded" "$(has_line "$out" 'NEW=1')"
cp "$state/baseline.json" "$fx/baseline.keep"
rm -f "$state/baseline.json"
run f --prior-success true
assert "F: a lost baseline writes a comment either way" "$(has_line "$out" 'COMMENT=true')"
assert "F: a lost baseline is never a silent first run" \
  "$([ "$(has_line "$out" 'FIRST_RUN=true')" = false ] && echo true || echo false)"
if [ "$expect_supported" = true ]; then
  assert "F: a lost baseline exits 0 (reported, not failed)" "$(rc_is "$rc" 0)"
  assert "F: a lost baseline is BASELINE_LOST=true" "$(has_line "$out" 'BASELINE_LOST=true')"
  assert "F: the comment says the baseline was lost" "$(contains "$comment_file" 'Baseline lost')"
  assert "F: the comment carries the baseline_lost row" "$(contains "$comment_file" '`baseline_lost`')"
  assert "F: the comment re-reports the already-known finding" "$(contains "$comment_file" '`duplicate_rule_lexical`')"
  assert "F: the baseline is re-recorded" "$([ -s "$state/baseline.json" ] && echo true || echo false)"
else
  # Without #2749 the script cannot re-report, so it must fail rather than
  # re-record silently.
  assert "F (pre-#2749): a lost baseline fails the run" "$(rc_is "$rc" 1)"
  assert "F (pre-#2749): the baseline is not silently re-recorded" "$(lacks_file "$state/baseline.json")"
  cp "$fx/baseline.keep" "$state/baseline.json"
fi
rm -f "$rules/log-rotation-copy.md"
run f2 --prior-success false
# A lost baseline over a CLEAN corpus: nothing to re-report but the loss itself,
# which must still be said -- NEW counts only the analyzer's findings.
cp "$state/baseline.json" "$fx/baseline.keep"
rm -f "$state/baseline.json"
run f4 --prior-success true
assert "F4: a lost baseline over a clean corpus is still commented" "$(has_line "$out" 'COMMENT=true')"
[ -s "$state/baseline.json" ] || cp "$fx/baseline.keep" "$state/baseline.json"
rm -f "$state/baseline.json"
run f3 --prior-success false
assert "F3: a missing baseline on a genuine first run stays silent" "$(has_line "$out" 'COMMENT=false')"
assert "F3: ...and is a first run" "$(has_line "$out" 'FIRST_RUN=true')"

# --- G: the planted-duplicate control -----------------------------------------
echo "=== G: planted control ==="
run g --prior-success "$steady" --plant-control
assert "G: the control passes" "$(has_line "$out" 'CONTROL=passed')"
assert "G: a passing control exits 0" "$(rc_is "$rc" 0)"
assert "G: the control is commented" "$(has_line "$out" 'COMMENT=true')"
assert "G: the comment reports the control" "$(contains "$comment_file" 'Config drift control — passed')"
assert "G: the comment carries the promotion finding" "$(contains "$comment_file" '`promotion_candidate`')"
assert "G: the comment carries the injected score" "$(contains "$comment_file" '| 0.95 |')"
assert "G: the comment names the planted child" \
  "$(contains "$comment_file" '`zz-config-drift-control/.claude/rules/zz-config-drift-control-child.md`')"
assert "G: the comment names the planted parent" \
  "$(contains "$comment_file" '`.claude/rules/zz-config-drift-control-parent.md`')"
assert "G: exactly one row in the control table" \
  "$([ "$(grep -c '^| [A-Z]* | `' "$comment_file")" -eq 1 ] && echo true || echo false)"
assert "G: the planted parent is removed" "$(lacks_file "$rules/zz-config-drift-control-parent.md")"
assert "G: the planted directory is removed" "$(lacks_file "$root/zz-config-drift-control")"
assert "G: the real rules survive" "$([ -f "$rules/log-rotation.md" ] && echo true || echo false)"
run g2 --prior-success "$steady"
assert "G2: the planted finding never entered the baseline" "$(has_line "$out" 'NEW=0')"

# --- H: a delta that reports nothing must FAIL the control -------------------
# Guard integrity for G: without this, a control that always passed would be
# indistinguishable from one that works.
echo "=== H: broken delta fails the control ==="
cat > "$fx/blind-delta.py" <<'PY'
import os, sys
if "CONFIG DRIFT CONTROL" in sys.argv:
    print("=== CONFIG DRIFT CONTROL ===\nNEW=0\nSTATUS=OK\nISSUE_COUNT=0\n=== END CONFIG DRIFT CONTROL ===")
    sys.exit(0)
os.execvp(sys.executable, [sys.executable, os.environ["REAL_DELTA"], *sys.argv[1:]])
PY
REAL_DELTA="$real_delta" CONFIG_DRIFT_AUDIT_PROBE_DELTA="$fx/blind-delta.py" \
  run h --prior-success "$steady" --plant-control
assert "H: a blind delta fails the control" "$(has_line "$out" 'CONTROL=failed')"
assert "H: a failed control exits 1" "$(rc_is "$rc" 1)"
assert "H: the failure is commented" "$(contains "$comment_file" 'Control failed')"
assert "H: the failure names what was missing" "$(contains "$comment_file" 'NEW=0')"
assert "H: the planted files are still removed" "$(lacks_file "$root/zz-config-drift-control")"

# --- I: a planted path that already exists is never clobbered ----------------
echo "=== I: planted path exists ==="
printf 'keep me\n' > "$rules/zz-config-drift-control-parent.md"
run i --prior-success "$steady" --plant-control
assert "I: an occupied planted path fails the control" "$(has_line "$out" 'CONTROL=failed')"
assert "I: the existing file is left as it was" "$(grep -qxF 'keep me' "$rules/zz-config-drift-control-parent.md" && echo true || echo false)"
rm -f "$rules/zz-config-drift-control-parent.md"

# --- J: a degraded run is reported but does not roll the baseline forward ------
echo "=== J: degraded run ==="
cat > "$fx/degraded.py" <<'PY'
import json, os, subprocess, sys
doc = json.loads(subprocess.run([sys.executable, os.environ["REAL_ANALYZER"], *sys.argv[1:]],
                                capture_output=True, text=True).stdout)
doc["findings"].append({"severity": "info", "kind": "semantic_pass_unavailable",
                        "summary": "semantic pass skipped: OSError: model download failed"})
print(json.dumps(doc, indent=1))
PY
cp "$state/baseline.json" "$fx/baseline.before-j"
REAL_ANALYZER="$real_analyzer" CONFIG_DRIFT_AUDIT_ANALYZER="$fx/degraded.py" \
  run j --prior-success "$steady"
assert "J: a degraded run is marked DEGRADED=true" "$(has_line "$out" 'DEGRADED=true')"
assert "J: a degraded run does not record" "$(has_line "$out" 'RECORDED=false')"
assert "J: the baseline is untouched" "$(cmp -s "$state/baseline.json" "$fx/baseline.before-j" && echo true || echo false)"
assert "J: the degradation is commented" "$(contains "$comment_file" 'semantic_pass_unavailable')"

# --- K: usage errors are rejected, not swallowed (#2057) ----------------------
echo "=== K: usage ==="
out="$(bash "$audit" --out-dir "$fx/o" --state-dir "$fx/s" --prior-success maybe 2>&1)"; rc=$?
assert "K: an invalid --prior-success exits 2" "$(rc_is "$rc" 2)"
out="$(bash "$audit" --out-dir "$fx/o" --state-dir "$fx/s" --prior-success false --bogus 2>&1)"; rc=$?
assert "K: an unknown argument exits 2" "$(rc_is "$rc" 2)"
assert "K: the unknown argument is named" "$(grep -qF 'unknown argument: --bogus' <<<"$out" && echo true || echo false)"

echo
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
