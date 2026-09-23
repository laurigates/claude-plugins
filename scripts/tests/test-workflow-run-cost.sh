#!/usr/bin/env bash
# Regression test for scripts/workflow-run-cost.sh and its wiring into
# .github/workflows/workflow-model-audit.yml (issue #2669).
#
# The gap: the monthly model/effort audit's pre-compute step read only
# `gh run list --json conclusion`, so it could say which workflow was red but
# not which was expensive, and it could not see a binding `--max-turns`.
# golden-set-evaluation run 34981573686 cost $32.59 and stopped at 59 of
# `--max-turns 60`; claude-code-action prints that accounting only in the job
# log, and nothing in the repo read it.
#
# HERMETIC: `gh` is a stub on PATH serving `run list` JSON and `run view --log`
# text per case. The logs under fixtures/workflow-run-cost/ are VERBATIM
# excerpts of real `gh run view --log` output (runs 34981573686, 35737375212,
# 34232914851), not re-typed, so the parser is tested against the shape the
# action really prints. The stub logs a sentinel per call and the harness
# asserts the stub is the `gh` in effect, so a stub that failed to take effect
# cannot pass as the real CLI.
#
# Case L executes the audit workflow's own pre-compute `run:` block, extracted
# from the shipped YAML, against the stub: a grep for the script name would pass
# on a call that never reaches the prompt.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
SUBJECT="$repo_root/scripts/workflow-run-cost.sh"
AUDIT_WF="$repo_root/.github/workflows/workflow-model-audit.yml"
FX_DIR="$script_dir/fixtures/workflow-run-cost"
GOLDEN="$FX_DIR/golden-set-evaluation-34981573686.txt"   # 59 turns, $32.59, run cap 60, 6 denials
OVER="$FX_DIR/obsidian-cli-changelog-35737375212.txt"    # 72 turns, $10.29, run cap 40, 8 denials
NOACCT="$FX_DIR/obsidian-cli-changelog-34232914851.txt"  # Claude job skipped: no accounting object

pass=0; fail=0
assert() {
  if [ "$2" = "true" ]; then pass=$((pass + 1)); else
    echo "FAIL: $1" >&2; fail=$((fail + 1)); fi
}
contains() { printf '%s' "$1" | grep -qF -- "$2" && echo true || echo false; }
lacks()    { printf '%s' "$1" | grep -qF -- "$2" && echo false || echo true; }

for f in "$SUBJECT" "$GOLDEN" "$OVER" "$NOACCT"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; fail=$((fail + 1)); }
done
[ "$fail" -eq 0 ] || { echo "=== RESULT: 0 passed, $fail failed ===" >&2; exit 1; }

fx="$(mktemp -d)"
if [ -z "$fx" ] || [ ! -d "$fx" ]; then echo "mktemp failed" >&2; exit 1; fi
trap '[ -n "${KEEP_FX:-}" ] && echo "KEEP_FX=$fx" >&2 || rm -rf "$fx"' EXIT

shim="$fx/shim"; mkdir -p "$shim"
cat > "$shim/gh" <<'STUB'
#!/usr/bin/env bash
# gh stub. WRC_FX is the case directory: runs.json, logs/<id>.txt, list-fail.
echo "STUB-GH $*" >> "$WRC_FX/calls.log"
[ "${1:-}" = run ] || exit 3
case "${2:-}" in
  list)
    [ -f "$WRC_FX/list-fail" ] && exit 1
    for a in "$@"; do
      # The audit's existing health rollup asks for --jq; answer it in kind.
      [ "$a" = --jq ] && { echo "9 ok / 0 fail / 9 recent"; exit 0; }
    done
    cat "$WRC_FX/runs.json" ;;
  view)
    [ -f "$WRC_FX/logs/$3.txt" ] || exit 1   # an expired or missing log
    cat "$WRC_FX/logs/$3.txt" ;;
  *) exit 3 ;;
esac
STUB
chmod +x "$shim/gh"
assert "the gh stub is the gh in effect" \
  "$([ "$(PATH="$shim:$PATH" command -v gh)" = "$shim/gh" ] && echo true || echo false)"

# write_wf <path> <cap-line> -- an invoking workflow whose comment names an old
# cap, so the anchored parse is exercised on every case.
write_wf() {
  cat > "$1" <<WF
name: fixture
jobs:
  sweep:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          # --max-turns 25 was the old budget; this comment must not be read.
          claude_args: >-
            --model opus
            --effort medium
$2
WF
}

n=0
# new_case <runs-json> -- sets $c to a fresh case dir holding runs.json and
# logs/. Not a $(...) helper: the counter must advance in THIS shell, or every
# case would share one directory and inherit the previous case's state.
new_case() {
  n=$((n + 1))
  c="$fx/case$n"
  mkdir -p "$c/logs"
  : > "$c/calls.log"
  printf '%s\n' "$1" > "$c/runs.json"
}
one_run='[{"databaseId":111,"conclusion":"success","createdAt":"2026-09-15T14:25:49Z"}]'

out=""; rc=0
# run_cost <case-dir> <args...>
run_cost() {
  local c="$1"; shift
  out="$(WRC_FX="$c" PATH="$shim:$PATH" bash "$SUBJECT" "$@" 2>&1)"; rc=$?
}

echo "=== CASE A: 59 of --max-turns 60 is near the cap (the golden-set run) ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml"
assert "A: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "A: row carries COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true" \
  "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-15T14:25:49Z COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true DENIALS=6")"
assert "A: file cap parsed from the flag line, not the comment" "$(contains "$out" $'\nMAX_TURNS=60\n')"
assert "A: STATUS=WARN" "$(contains "$out" "STATUS=WARN")"
assert "A: a near_cap issue row names the run" "$(contains "$out" "SEVERITY=WARN TYPE=near_cap RUN=111 MSG=59 turns against --max-turns 60")"
assert "A: TOTAL_COST_USD=32.59" "$(contains "$out" "TOTAL_COST_USD=32.59")"
assert "A: the stub served the log" "$(contains "$(cat "$c/calls.log")" "STUB-GH run view 111 --log")"

echo "=== CASE B: 55 of 60 is not near the cap; the margin is two turns ==="
for t in 55:false 57:false 58:true; do
  new_case "$one_run"
  sed "s/\"num_turns\": 59,/\"num_turns\": ${t%%:*},/" "$GOLDEN" > "$c/logs/111.txt"
  write_wf "$c/wf.yml" "            --max-turns 60"
  run_cost "$c" "$c/wf.yml"
  assert "B: ${t%%:*}/60 -> NEAR_CAP=${t##*:}" "$(contains "$out" "TURNS=${t%%:*} MAX_TURNS=60 NEAR_CAP=${t##*:}")"
  if [ "${t##*:}" = false ]; then
    assert "B: ${t%%:*}/60 -> STATUS=OK" "$(contains "$out" "STATUS=OK")"
    assert "B: ${t%%:*}/60 -> NEAR_CAP_RUNS=0" "$(contains "$out" "NEAR_CAP_RUNS=0")"
  fi
done

echo "=== CASE C: no accounting object is unknown, never 0 ==="
runs='[{"databaseId":111,"conclusion":"success","createdAt":"2026-09-08T13:35:33Z"},{"databaseId":222,"conclusion":"success","createdAt":"2026-09-01T13:35:33Z"}]'
new_case "$runs"; cp "$NOACCT" "$c/logs/111.txt"   # 222 has no log: expired
write_wf "$c/wf.yml" "            --max-turns 40"
run_cost "$c" "$c/wf.yml"
assert "C: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "C: skipped-Claude-step run -> COST_USD=unknown TURNS=unknown" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-08T13:35:33Z COST_USD=unknown TURNS=unknown MAX_TURNS=40 NEAR_CAP=unknown DENIALS=unknown")"
assert "C: expired log -> COST_USD=unknown" "$(contains "$out" "RUN=222 CONCLUSION=success CREATED=2026-09-01T13:35:33Z COST_USD=unknown")"
assert "C: TOTAL_COST_USD=unknown" "$(contains "$out" "TOTAL_COST_USD=unknown")"
assert "C: COSTED_RUNS=0" "$(contains "$out" "COSTED_RUNS=0")"
assert "C: no zero cost anywhere" "$(lacks "$out" "COST_USD=0")"
assert "C: STATUS=OK (no data is not a finding)" "$(contains "$out" "STATUS=OK")"

echo "=== CASE D: the cap the run used wins over the file's current cap ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 90"
run_cost "$c" "$c/wf.yml"
assert "D: header MAX_TURNS is the file's current 90" "$(contains "$out" $'\nMAX_TURNS=90\n')"
assert "D: row MAX_TURNS is the run's echoed 60, and NEAR_CAP=true" "$(contains "$out" "TURNS=59 MAX_TURNS=60 NEAR_CAP=true")"

echo "=== CASE E: past the cap counts as near it (72 against 40) ==="
new_case "$one_run"; cp "$OVER" "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 40"
run_cost "$c" "$c/wf.yml"
assert "E: COST_USD=10.29 TURNS=72 MAX_TURNS=40 NEAR_CAP=true DENIALS=8" "$(contains "$out" "COST_USD=10.29 TURNS=72 MAX_TURNS=40 NEAR_CAP=true DENIALS=8")"

echo "=== CASE F: untimestamped prompt lines quoting accounting are ignored ==="
new_case "$one_run"
awk 'BEGIN { OFS = "\t" } { print } /  prompt: / {
  print "sweep", "UNKNOWN STEP", "{"
  print "sweep", "UNKNOWN STEP", "  \"type\": \"result\","
  print "sweep", "UNKNOWN STEP", "  \"num_turns\": 999,"
  print "sweep", "UNKNOWN STEP", "  \"total_cost_usd\": 999.99,"
  print "sweep", "UNKNOWN STEP", "  claude_args: --max-turns 5"
  print "sweep", "UNKNOWN STEP", "}"
}' "$GOLDEN" > "$c/logs/111.txt"
assert "F: control - the decoy lines are in the log" "$(contains "$(cat "$c/logs/111.txt")" '"num_turns": 999,')"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml"
assert "F: decoys ignored -> COST_USD=32.59 TURNS=59 MAX_TURNS=60" "$(contains "$out" "COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true")"
assert "F: no 999 leaked into the report" "$(lacks "$out" "999")"

echo "=== CASE G: skipped runs are not sampled, and --limit bounds the sample ==="
runs='[{"databaseId":900,"conclusion":"skipped","createdAt":"2026-09-22T00:00:00Z"},{"databaseId":901,"conclusion":"skipped","createdAt":"2026-09-21T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":222,"conclusion":"failure","createdAt":"2026-09-19T00:00:00Z"},{"databaseId":333,"conclusion":"success","createdAt":"2026-09-18T00:00:00Z"}]'
new_case "$runs"; cp "$GOLDEN" "$c/logs/111.txt"; cp "$OVER" "$c/logs/222.txt"; cp "$GOLDEN" "$c/logs/333.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml" --limit 2
assert "G: RUNS_SAMPLED=2" "$(contains "$out" "RUNS_SAMPLED=2")"
assert "G: skipped runs absent" "$(lacks "$out" "RUN=90")"
assert "G: the third model-reaching run is beyond --limit" "$(lacks "$out" "RUN=333")"
assert "G: TOTAL_COST_USD sums the unrounded costs (32.5936 + 10.2948 = 42.89)" "$(contains "$out" "TOTAL_COST_USD=42.89")"
assert "G: NEAR_CAP_RUNS=2 and ISSUE_COUNT=2" "$(contains "$out" $'NEAR_CAP_RUNS=2\nSTATUS=WARN\nISSUE_COUNT=2')"

echo "=== CASE H: several Claude steps in one run sum cost and denials, keep max turns ==="
new_case "$one_run"; cat "$GOLDEN" "$OVER" > "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml"
assert "H: COST_USD=42.89 TURNS=72 MAX_TURNS=60 DENIALS=14" "$(contains "$out" "COST_USD=42.89 TURNS=72 MAX_TURNS=60 NEAR_CAP=true DENIALS=14")"

echo "=== CASE I: gh run list failing is an ERROR, exit 1 ==="
new_case "$one_run"; : > "$c/list-fail"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml"
assert "I: exit 1 (got $rc)" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "I: STATUS=ERROR TYPE=run_list_failed" "$(contains "$out" "STATUS=ERROR")"
assert "I: run_list_failed issue" "$(contains "$out" "TYPE=run_list_failed")"

echo "=== CASE J: usage errors exit 2 ==="
new_case "$one_run"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c"; assert "J: no args -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run_cost "$c" "$c/nope.yml"; assert "J: missing file -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run_cost "$c" "$c/wf.yml" --limit 0; assert "J: --limit 0 -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"

echo "=== CASE K: the CLI-call cap shape (trailing backslash) is read, and is the fallback ==="
new_case "$one_run"; grep -v 'claude_args:' "$GOLDEN" > "$c/logs/111.txt"
assert "K: control - the log echoes no claude_args" "$(lacks "$(cat "$c/logs/111.txt")" "claude_args:")"
write_wf "$c/wf.yml" "            --max-turns 60 \\"
run_cost "$c" "$c/wf.yml"
assert "K: header MAX_TURNS=60 from '--max-turns 60 \\'" "$(contains "$out" $'\nMAX_TURNS=60\n')"
assert "K: row falls back to the file cap" "$(contains "$out" "TURNS=59 MAX_TURNS=60 NEAR_CAP=true")"

echo "=== CASE L: the audit's pre-compute step feeds the cost block into the prompt ==="
block="$fx/precompute.sh"
awk '
  /^[[:space:]]*id: precompute[[:space:]]*$/ { found = 1; next }
  found && !inrun && /^[[:space:]]*run: \|[[:space:]]*$/ {
    inrun = 1; match($0, /^[[:space:]]*/); base = RLENGTH; next
  }
  inrun {
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    match($0, /^[[:space:]]*/)
    if (RLENGTH <= base) exit
    if (!ind) ind = RLENGTH
    print substr($0, ind + 1)
  }' "$AUDIT_WF" > "$block"
assert "L: control - the pre-compute run block was extracted" "$(contains "$(cat "$block")" 'gh run list --workflow')"
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
repo="$fx/repo"; mkdir -p "$repo/.github/workflows" "$repo/scripts" "$fx/rt"
cp "$SUBJECT" "$repo/scripts/workflow-run-cost.sh"
printf '#!/usr/bin/env bash\necho "DRIFT-STUB"\n' > "$repo/scripts/check-workflow-model.sh"
write_wf "$repo/.github/workflows/invoking.yml" "            --max-turns 60"
printf 'name: plain\non: push\njobs: {}\n' > "$repo/.github/workflows/plain.yml"
: > "$fx/gho"
( cd "$repo" && WRC_FX="$c" GH_TOKEN=stub RUNNER_TEMP="$fx/rt" GITHUB_OUTPUT="$fx/gho" \
    PATH="$shim:$PATH" bash -e "$block" ) >/dev/null 2>&1; lrc=$?
gho="$(cat "$fx/gho")"
assert "L: the pre-compute block exits 0 under bash -e (got $lrc)" "$([ "$lrc" -eq 0 ] && echo true || echo false)"
assert "L: the output carries the cost block" "$(contains "$gho" "=== WORKFLOW RUN COST ===")"
assert "L: ...for the invoking workflow" "$(contains "$gho" "WORKFLOW=invoking.yml")"
assert "L: ...with the measured row" "$(contains "$gho" "COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true")"
assert "L: ...and not for a non-invoking workflow" "$(lacks "$gho" "WORKFLOW=plain.yml")"
assert "L: the run-health rollup is still there" "$(contains "$gho" "- invoking.yml: 9 ok / 0 fail / 9 recent")"
prompt="$(awk '/^[[:space:]]*prompt: \|/ { p = 1 } p' "$AUDIT_WF")"
assert "L: the prompt ranks by measured spend" "$(contains "$prompt" "TOTAL_COST_USD")"
assert "L: the prompt reads COST_USD=unknown as no data" "$(contains "$prompt" "COST_USD=unknown")"
assert "L: the prompt flags NEAR_CAP=true runs" "$(contains "$prompt" "NEAR_CAP=true")"

echo "=== RESULT: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
