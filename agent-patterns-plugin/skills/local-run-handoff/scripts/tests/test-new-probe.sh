#!/usr/bin/env bash
# Regression suite for local-run-handoff: the scaffolder (new-probe.sh) and the
# shipped probe-root helpers (templates/lib/report.sh, templates/lib/probes.sh).
#
# Load-bearing invariants:
#   - exit codes carry the verdict class: decided 0, ERROR 1, INCONCLUSIVE 2, SKIP 3
#   - results/summary.txt holds the header and the one STATUS= line
#   - nothing leaves the machine (PR comment, clipboard) when results/ holds a
#     secret-shaped string, and --no-notify suppresses the PR comment
#   - archive moves only decided probes past the age limit
#
# Run: bash agent-patterns-plugin/skills/local-run-handoff/scripts/tests/test-new-probe.sh
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
scaffold="$here/../new-probe.sh"

sandbox=$(mktemp -d "${TMPDIR:-/tmp}/test-new-probe.XXXXXX") || exit 1
if [ -z "$sandbox" ] || [ ! -d "$sandbox" ]; then
  echo "FAIL: mktemp -d produced no directory" >&2
  exit 1
fi
cleanup() { rm -rf "$sandbox"; }
trap cleanup EXIT

pass=0
fail=0
ok() { printf 'PASS %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL %s\n' "$1"; fail=$((fail + 1)); }
assert_eq() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }
assert_has() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing '$3')"; fi; }
assert_lacks() { if grep -qF -- "$3" <<<"$2"; then bad "$1 (unexpected '$3')"; else ok "$1"; fi; }

# Stubs for outbound tools: each records its args/stdin under $sandbox/calls.
stubs="$sandbox/stubs"
mkdir -p "$stubs" "$sandbox/calls"
cat >"$stubs/pbcopy" <<EOF
#!/usr/bin/env bash
cat > "$sandbox/calls/clip"
EOF
cat >"$stubs/gh" <<EOF
#!/usr/bin/env bash
echo "\$*" > "$sandbox/calls/gh"
EOF
chmod +x "$stubs/pbcopy" "$stubs/gh"
[ -x "$stubs/pbcopy" ] && [ -x "$stubs/gh" ] || { echo "FAIL: stubs not executable" >&2; exit 1; }
export PATH="$stubs:$PATH"
assert_eq "stub pbcopy is first on PATH" "$(command -v pbcopy)" "$stubs/pbcopy"

root="$sandbox/root"
run_probe() { bash "$root/lib/probes.sh" run "$@" >"$sandbox/out" 2>&1; echo $?; }

# Make a probe decide: the control passes and the test arm yields $2.
decide() {
  local f="$1" outcome="$2"
  sed 's/^control_ok=0$/control_ok=1/; s/^test_outcome=""$/test_outcome="'"$outcome"'"/' "$f" >"$f.new" && mv "$f.new" "$f" && chmod +x "$f"
}

# --- scaffold -------------------------------------------------------------
out=$(bash "$scaffold" --root "$root" --slug alpha --ref o/r#7 --notify-pr o/r#7 --date 20260101)
assert_has "scaffold STATUS=OK" "$out" "STATUS=OK"
assert_has "scaffold prints the run line" "$out" "RUN=just -f $root/justfile run alpha"
pdir="$root/20260101-alpha"
for f in justfile lib/report.sh lib/probes.sh; do
  [ -f "$root/$f" ] && ok "root has $f" || bad "root has $f"
done
for f in run.sh README.md .handoff.json fixtures results; do
  [ -e "$pdir/$f" ] && ok "probe has $f" || bad "probe has $f"
done
[ -x "$pdir/run.sh" ] && ok "run.sh executable" || bad "run.sh executable"
assert_eq "handoff ref" "$(jq -r .ref "$pdir/.handoff.json")" "o/r#7"
assert_eq "handoff notify.pr" "$(jq -r .notify.pr "$pdir/.handoff.json")" "o/r#7"
assert_eq "handoff kind" "$(jq -r .kind "$pdir/.handoff.json")" "probe"
assert_has "default codes rendered" "$(cat "$pdir/run.sh")" 'YES) verdict YES'

out=$(bash "$scaffold" --root "$root" --slug alpha --date 20260101); rc=$?
assert_eq "duplicate slug exits 1" "$rc" "1"
assert_has "duplicate slug reason" "$out" "REASON=exists:"
out=$(bash "$scaffold" --root "$root" --slug 'Bad Slug'); rc=$?
assert_eq "bad slug exits 1" "$rc" "1"

bash "$scaffold" --root "$root" --slug bug --repro --date 20260102 >/dev/null
assert_has "repro codes rendered" "$(cat "$root/20260102-bug/run.sh")" 'REPRODUCED) verdict REPRODUCED'
assert_eq "repro kind" "$(jq -r .kind "$root/20260102-bug/.handoff.json")" "repro"

# --- verdict exit codes ---------------------------------------------------
rc=$(run_probe alpha --no-notify)
assert_eq "untouched template is INCONCLUSIVE (exit 2)" "$rc" "2"
assert_has "summary carries INCONCLUSIVE" "$(cat "$pdir/results/summary.txt")" "STATUS=INCONCLUSIVE"
assert_has "summary carries header" "$(cat "$pdir/results/summary.txt")" "=== PROBE ==="

decide "$pdir/run.sh" YES
rm -f "$sandbox/calls/gh"
rc=$(run_probe alpha --no-notify)
assert_eq "decided verdict exits 0" "$rc" "0"
assert_eq "one STATUS line" "$(grep -c '^STATUS=' "$pdir/results/summary.txt")" "1"
assert_has "summary carries YES" "$(cat "$pdir/results/summary.txt")" "STATUS=YES"
[ ! -f "$sandbox/calls/gh" ] && ok "--no-notify suppresses PR comment" || bad "--no-notify suppresses PR comment"

# --- notify + clipboard ---------------------------------------------------
rc=$(run_probe alpha --clip)
assert_eq "notify run exits 0" "$rc" "0"
assert_has "PR comment targets the ref" "$(cat "$sandbox/calls/gh" 2>/dev/null)" "pr comment 7 -R o/r"
assert_eq "clipboard holds summary" "$(cat "$sandbox/calls/clip" 2>/dev/null)" "$(cat "$pdir/results/summary.txt")"
assert_has "notify reported" "$(cat "$sandbox/out")" "NOTIFY_PR=sent o/r#7"

# A secret-shaped string in results/ blocks every outbound channel.
rm -f "$sandbox/calls/gh" "$sandbox/calls/clip"
sed 's|^section RESULTS$|section RESULTS\necho "token ghp_abcdefghijklmnopqrstuvwxyz0123456789" > "$RESULTS/raw.txt"|' "$pdir/run.sh" >"$pdir/run.sh.new" && mv "$pdir/run.sh.new" "$pdir/run.sh" && chmod +x "$pdir/run.sh"
rc=$(run_probe alpha --clip)
assert_eq "secret run still exits 0" "$rc" "0"
[ ! -f "$sandbox/calls/gh" ] && ok "secret blocks PR comment" || bad "secret blocks PR comment"
[ ! -f "$sandbox/calls/clip" ] && ok "secret blocks clipboard" || bad "secret blocks clipboard"
assert_has "secret warning printed" "$(cat "$sandbox/out")" "WARN: results/ contains something shaped like a secret"

# --- OS guard and setup errors -------------------------------------------
bash "$scaffold" --root "$root" --slug wrongos --os "$( [ "$(uname -s)" = Darwin ] && echo linux || echo darwin )" --date 20260103 >/dev/null
rc=$(run_probe wrongos)
assert_eq "wrong OS exits 3" "$rc" "3"
assert_has "wrong OS is SKIP" "$(cat "$root/20260103-wrongos/results/summary.txt")" "STATUS=SKIP"

bash "$scaffold" --root "$root" --slug notool --date 20260104 >/dev/null
sed 's/^need jq$/need definitely-not-a-real-tool-xyz/' "$root/20260104-notool/run.sh" >"$sandbox/t" && mv "$sandbox/t" "$root/20260104-notool/run.sh" && chmod +x "$root/20260104-notool/run.sh"
rc=$(run_probe notool)
assert_eq "missing tool exits 1" "$rc" "1"
assert_has "missing tool is ERROR" "$(cat "$root/20260104-notool/results/summary.txt")" "STATUS=ERROR missing tool(s): definitely-not-a-real-tool-xyz"

# --- list and archive -----------------------------------------------------
listing=$(bash "$root/lib/probes.sh" list)
assert_has "list shows alpha status" "$listing" "20260101-alpha"
assert_has "list shows pending probe" "$(grep 20260102-bug <<<"$listing")" "pending"

touch -d '20 days ago' "$pdir/results/summary.txt" "$root/20260103-wrongos/results/summary.txt" 2>/dev/null ||
  touch -t "$(date -v-20d +%Y%m%d%H%M 2>/dev/null)" "$pdir/results/summary.txt" "$root/20260103-wrongos/results/summary.txt"
out=$(bash "$root/lib/probes.sh" archive 14)
[ -d "$root/archive/20260101-alpha" ] && ok "archive moves old decided probe" || bad "archive moves old decided probe"
[ -d "$root/20260102-bug" ] && ok "archive keeps pending probe" || bad "archive keeps pending probe"
[ -d "$root/20260104-notool" ] && ok "archive keeps ERROR probe" || bad "archive keeps ERROR probe"

echo "PASSED=$pass FAILED=$fail"
[ "$fail" -eq 0 ]
