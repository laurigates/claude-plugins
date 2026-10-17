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
# HERMETIC: `gh` is a stub on PATH serving `run list` JSON, `run view --log`
# text, and `run view <id> --json jobs` from jobs/<id>.json per case. The jobs
# files are hand-written in the shape gh returns (.jobs[].name, .jobs[].conclusion):
# no verbatim capture of that call is in the repo. The logs under
# fixtures/workflow-run-cost/ are VERBATIM
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
# Single-line needles only: grep -F splits a multi-line pattern into one
# pattern per line, and an empty line matches everything.
contains() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }
lacks()    { grep -qF -- "$2" <<<"$1" && echo false || echo true; }
# has_line: a WHOLE-line match, so the header's MAX_TURNS= is not satisfied by
# a row's "MAX_TURNS=60 NEAR_CAP=..." and NEAR_CAP_RUNS=2 by no other key.
has_line() { grep -qxF -- "$2" <<<"$1" && echo true || echo false; }

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
    # --json jobs: the per-job conclusions the run-level gate reads. A missing
    # file fails the call, which the script must treat as "unknown", not "gated".
    for a in "$@"; do
      [ "$a" = --json ] || continue
      [ -f "$WRC_FX/jobs/$3.json" ] || exit 1
      cat "$WRC_FX/jobs/$3.json"; exit 0
    done
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
# write_wf <path> <cap-line> [job-key] -- the invoking job's key, default sweep.
write_wf() {
  local job="${3:-sweep}"
  cat > "$1" <<WF
name: fixture
jobs:
  $job:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          # A comment ending in a cap must not be read as the cap: was --max-turns 25
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
  mkdir -p "$c/logs" "$c/jobs"
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
# log_fetches <case-dir> <run-id> -- how many `gh run view <id> --log` calls the
# case made. A run's log is read once: the backstop reuses its accounting.
log_fetches() { grep -cF -- "STUB-GH run view $2 --log" "$1/calls.log"; }

echo "=== CASE A: 59 of --max-turns 60 is near the cap (the golden-set run) ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml"
assert "A: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "A: row carries COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true" \
  "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-15T14:25:49Z COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true DENIALS=6")"
assert "A: file cap parsed from the flag line, not the comment" "$(has_line "$out" "MAX_TURNS=60")"
assert "A: STATUS=WARN" "$(has_line "$out" "STATUS=WARN")"
assert "A: a near_cap issue row names the run" "$(contains "$out" "SEVERITY=WARN TYPE=near_cap RUN=111 MSG=59 turns against --max-turns 60")"
assert "A: TOTAL_COST_USD=32.59" "$(has_line "$out" "TOTAL_COST_USD=32.59")"
assert "A: the stub served the log" "$(contains "$(cat "$c/calls.log")" "STUB-GH run view 111 --log")"

echo "=== CASE B: 55 of 60 is not near the cap; the margin is two turns ==="
for t in 55:false 57:false 58:true; do
  new_case "$one_run"
  sed "s/\"num_turns\": 59,/\"num_turns\": ${t%%:*},/" "$GOLDEN" > "$c/logs/111.txt"
  write_wf "$c/wf.yml" "            --max-turns 60"
  run_cost "$c" "$c/wf.yml"
  assert "B: ${t%%:*}/60 -> NEAR_CAP=${t##*:}" "$(contains "$out" "TURNS=${t%%:*} MAX_TURNS=60 NEAR_CAP=${t##*:}")"
  if [ "${t##*:}" = false ]; then
    assert "B: ${t%%:*}/60 -> STATUS=OK" "$(has_line "$out" "STATUS=OK")"
    assert "B: ${t%%:*}/60 -> NEAR_CAP_RUNS=0" "$(has_line "$out" "NEAR_CAP_RUNS=0")"
  fi
done

echo "=== CASE C: a run whose Claude job ran but logged no accounting is unknown, never 0 (negative control) ==="
runs='[{"databaseId":111,"conclusion":"failure","createdAt":"2026-09-08T13:35:33Z"},{"databaseId":222,"conclusion":"success","createdAt":"2026-09-01T13:35:33Z"}]'
new_case "$runs"
# 111: the Claude job ran and failed before the action printed any accounting.
printf 'claude-review\tRun claude-code-action\t2026-09-08T13:35:40.1234567Z Error: OIDC token exchange failed\n' > "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"claude-review","conclusion":"failure"}]}' > "$c/jobs/111.json"
# 222: no job list and no log (expired). Unreadable is not a gate: it is sampled.
write_wf "$c/wf.yml" "            --max-turns 40" claude-review
run_cost "$c" "$c/wf.yml"
assert "C: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "C: ran-without-accounting -> COST_USD=unknown TURNS=unknown, still sampled" "$(contains "$out" "RUN=111 CONCLUSION=failure CREATED=2026-09-08T13:35:33Z COST_USD=unknown TURNS=unknown MAX_TURNS=40 NEAR_CAP=unknown DENIALS=unknown")"
assert "C: unreadable job list and expired log -> COST_USD=unknown, still sampled" "$(contains "$out" "RUN=222 CONCLUSION=success CREATED=2026-09-01T13:35:33Z COST_USD=unknown")"
assert "C: a job that ran is not counted as gated off" "$(has_line "$out" "GATED_OFF_RUNS=0")"
assert "C: TOTAL_COST_USD=unknown" "$(has_line "$out" "TOTAL_COST_USD=unknown")"
assert "C: COSTED_RUNS=0" "$(has_line "$out" "COSTED_RUNS=0")"
assert "C: no zero cost anywhere" "$(lacks "$out" "COST_USD=0")"
assert "C: STATUS=OK (no data is not a finding)" "$(has_line "$out" "STATUS=OK")"

echo "=== CASE D: the cap the run used wins over the file's current cap ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 90"
run_cost "$c" "$c/wf.yml"
assert "D: header MAX_TURNS is the file's current 90" "$(has_line "$out" "MAX_TURNS=90")"
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
assert "G: RUNS_SAMPLED=2" "$(has_line "$out" "RUNS_SAMPLED=2")"
assert "G: skipped runs absent" "$(lacks "$out" "RUN=90")"
assert "G: the third model-reaching run is beyond --limit" "$(lacks "$out" "RUN=333")"
assert "G: TOTAL_COST_USD sums the unrounded costs (32.5936 + 10.2948 = 42.89)" "$(has_line "$out" "TOTAL_COST_USD=42.89")"
assert "G: NEAR_CAP_RUNS=2" "$(has_line "$out" "NEAR_CAP_RUNS=2")"
assert "G: ISSUE_COUNT=2" "$(has_line "$out" "ISSUE_COUNT=2")"
assert "G: STATUS=WARN" "$(has_line "$out" "STATUS=WARN")"

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
assert "I: STATUS=ERROR TYPE=run_list_failed" "$(has_line "$out" "STATUS=ERROR")"
assert "I: run_list_failed issue" "$(contains "$out" "TYPE=run_list_failed")"

echo "=== CASE J: usage errors exit 2 ==="
new_case "$one_run"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c"; assert "J: no args -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run_cost "$c" "$c/nope.yml"; assert "J: missing file -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run_cost "$c" "$c/wf.yml" --limit 0; assert "J: --limit 0 -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run_cost "$c" "$c/wf.yml" --scan 0; assert "J: --scan 0 -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"
run_cost "$c" "$c/wf.yml" --limit 3 --scan 2; assert "J: --scan below --limit -> 2 (got $rc)" "$([ "$rc" -eq 2 ] && echo true || echo false)"

echo "=== CASE K: the CLI-call cap shape (trailing backslash) is read, and is the fallback ==="
new_case "$one_run"; grep -v 'claude_args:' "$GOLDEN" > "$c/logs/111.txt"
assert "K: control - the log echoes no claude_args" "$(lacks "$(cat "$c/logs/111.txt")" "claude_args:")"
write_wf "$c/wf.yml" "            --max-turns 60 \\"
run_cost "$c" "$c/wf.yml"
assert "K: header MAX_TURNS=60 from '--max-turns 60 \\'" "$(has_line "$out" "MAX_TURNS=60")"
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

echo "=== CASE M: a newest run whose Claude job was gated off is not a sample; --limit 1 reaches the costed run behind it ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$NOACCT" "$c/logs/900.txt"; cp "$GOLDEN" "$c/logs/111.txt"
# The obsidian shape: check-cli-doc ran, claude-review skipped by its own `if:`,
# and the run still concluded success at run level.
printf '%s\n' '{"jobs":[{"name":"check-cli-doc","conclusion":"success"},{"name":"claude-review","conclusion":"skipped"}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"check-cli-doc","conclusion":"success"},{"name":"claude-review","conclusion":"success"}]}' > "$c/jobs/111.json"
write_wf "$c/wf.yml" "            --max-turns 60" claude-review
run_cost "$c" "$c/wf.yml" --limit 1
assert "M: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "M: the costed older run is the sample: COST_USD=32.59" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true DENIALS=6")"
assert "M: the gated-off newest run is not a sample" "$(lacks "$out" "RUN=900")"
assert "M: RUNS_SAMPLED=1" "$(has_line "$out" "RUNS_SAMPLED=1")"
assert "M: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"
assert "M: RUNS_SCANNED=2 (the gated run was examined, then the sample filled)" "$(has_line "$out" "RUNS_SCANNED=2")"
assert "M: SCAN_TRUNCATED=false (the listing ran out before --scan)" "$(has_line "$out" "SCAN_TRUNCATED=false")"
assert "M: the gated run's job list was read" "$(contains "$(cat "$c/calls.log")" "STUB-GH run view 900 --json jobs")"
assert "M: the gated run's log is read once, as the backstop (got $(log_fetches "$c" 900))" "$([ "$(log_fetches "$c" 900)" -eq 1 ] && echo true || echo false)"
assert "M: TOTAL_COST_USD=32.59 (the gated run adds nothing)" "$(has_line "$out" "TOTAL_COST_USD=32.59")"

echo "=== CASE N: the Claude job is matched by its display name; a matrix suffix still matches ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$NOACCT" "$c/logs/900.txt"; cp "$GOLDEN" "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"Claude: sweep (opus)","conclusion":"skipped"}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"Claude: sweep (opus)","conclusion":"success"}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  sweep:
    name: "Claude: sweep"
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "N: the display-named gated run is not a sample" "$(lacks "$out" "RUN=900")"
assert "N: the display-named run that ran is the sample" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=32.59")"
assert "N: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"

echo "=== CASE O: --scan bounds the walk; a walk that runs out before --limit is reported ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-22T00:00:00Z"},{"databaseId":901,"conclusion":"success","createdAt":"2026-09-21T00:00:00Z"},{"databaseId":902,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"}]'
new_case "$runs"
for r in 900 901 902; do printf '%s\n' '{"jobs":[{"name":"claude-review","conclusion":"skipped"}]}' > "$c/jobs/$r.json"; done
write_wf "$c/wf.yml" "            --max-turns 60" claude-review
run_cost "$c" "$c/wf.yml" --limit 1 --scan 2
assert "O: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "O: RUNS_SCANNED=2 (the walk stops at --scan)" "$(has_line "$out" "RUNS_SCANNED=2")"
assert "O: GATED_OFF_RUNS=2" "$(has_line "$out" "GATED_OFF_RUNS=2")"
assert "O: RUNS_SAMPLED=0" "$(has_line "$out" "RUNS_SAMPLED=0")"
assert "O: SCAN_TRUNCATED=true (older runs were not examined)" "$(has_line "$out" "SCAN_TRUNCATED=true")"
assert "O: the run beyond --scan was never queried" "$(lacks "$(cat "$c/calls.log")" "STUB-GH run view 902")"
assert "O: no sample, so no cost is claimed" "$(has_line "$out" "TOTAL_COST_USD=unknown")"

echo "=== CASE P: plugin-pr-checks shape: the job succeeded, its Claude step was skipped by a step-level if: ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$NOACCT" "$c/logs/900.txt"; cp "$GOLDEN" "$c/logs/111.txt"
# The job concludes success either way: only the Claude step's own `if:` differs.
printf '%s\n' '{"jobs":[{"name":"compliance","conclusion":"success","steps":[{"name":"Run plugin compliance checks","conclusion":"success"},{"name":"Claude Skill Quality Review","conclusion":"skipped"}]}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"compliance","conclusion":"success","steps":[{"name":"Run plugin compliance checks","conclusion":"success"},{"name":"Claude Skill Quality Review","conclusion":"success"}]}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - name: Run plugin compliance checks
        run: bash scripts/check.sh
      - name: Claude Skill Quality Review
        id: review
        if: steps.changed.outputs.skill_count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --model opus
            --effort low
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "P: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "P: the costed run behind the step-gated one is the sample" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=32.59 TURNS=59 MAX_TURNS=60 NEAR_CAP=true DENIALS=6")"
assert "P: the run whose Claude step was skipped is not a sample" "$(lacks "$out" "RUN=900")"
assert "P: RUNS_SAMPLED=1" "$(has_line "$out" "RUNS_SAMPLED=1")"
assert "P: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"
assert "P: the gated run's log is read once, as the backstop (got $(log_fetches "$c" 900))" "$([ "$(log_fetches "$c" 900)" -eq 1 ] && echo true || echo false)"
assert "P: TOTAL_COST_USD=32.59 (the gated run adds nothing)" "$(has_line "$out" "TOTAL_COST_USD=32.59")"

echo "=== CASE Q: a Claude step that ran with no accounting is sampled as unknown; the step-gated run beside it is not ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"
printf '%s\n' '{"jobs":[{"name":"compliance","conclusion":"success","steps":[{"name":"Claude Skill Quality Review","conclusion":"skipped"}]}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"compliance","conclusion":"success","steps":[{"name":"Claude Skill Quality Review","conclusion":"failure"}]}]}' > "$c/jobs/111.json"
# 111: the Claude step ran and failed before the action printed any accounting.
printf 'compliance\tClaude Skill Quality Review\t2026-09-19T13:35:40.1234567Z Error: OIDC token exchange failed\n' > "$c/logs/111.txt"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: review
        name: Claude Skill Quality Review
        if: steps.changed.outputs.skill_count != '0'
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "Q: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "Q: the ran-without-accounting run is sampled as COST_USD=unknown, not dropped" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=unknown TURNS=unknown MAX_TURNS=60 NEAR_CAP=unknown DENIALS=unknown")"
assert "Q: the step-gated run is not a sample" "$(lacks "$out" "RUN=900")"
assert "Q: RUNS_SAMPLED=1" "$(has_line "$out" "RUNS_SAMPLED=1")"
assert "Q: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"
assert "Q: COSTED_RUNS=0" "$(has_line "$out" "COSTED_RUNS=0")"
assert "Q: TOTAL_COST_USD=unknown" "$(has_line "$out" "TOTAL_COST_USD=unknown")"
assert "Q: no zero cost anywhere" "$(lacks "$out" "COST_USD=0")"

echo "=== CASE R: a job list naming no Claude job is unclassifiable: sampled as unknown, never gated ==="
runs='[{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$NOACCT" "$c/logs/111.txt"
# The file names its Claude job with a templated name the parser cannot read, and
# gh reports a rendered name. Nothing matches, so the run cannot be called gated.
printf '%s\n' '{"jobs":[{"name":"Claude security","conclusion":"skipped"}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  sweep:
    name: 'Claude ${{ matrix.lens }}'
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "R: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "R: the run is sampled as COST_USD=unknown" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=unknown")"
assert "R: RUNS_SAMPLED=1" "$(has_line "$out" "RUNS_SAMPLED=1")"
assert "R: GATED_OFF_RUNS=0" "$(has_line "$out" "GATED_OFF_RUNS=0")"

echo "=== CASE S: a job list that is not JSON is unknown, never gated ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
printf '%s\n' 'not json' > "$c/jobs/111.json"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml"
assert "S: sampled and costed: RUN=111 COST_USD=32.59" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-15T14:25:49Z COST_USD=32.59")"
assert "S: GATED_OFF_RUNS=0" "$(has_line "$out" "GATED_OFF_RUNS=0")"

echo "=== CASE T: two Claude jobs, one skipped and one ran: the run reached the model ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"claude-review","conclusion":"skipped"},{"name":"claude-triage","conclusion":"success"}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  claude-review:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
  claude-triage:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "T: sampled and costed: COST_USD=32.59" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-15T14:25:49Z COST_USD=32.59")"
assert "T: GATED_OFF_RUNS=0" "$(has_line "$out" "GATED_OFF_RUNS=0")"

echo "=== CASE U: a comment that names claude-code-action does not make a job a Claude job ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$GOLDEN" "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"checks","conclusion":"success"},{"name":"sweep","conclusion":"skipped"}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"checks","conclusion":"success"},{"name":"sweep","conclusion":"success"}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  checks:
    runs-on: ubuntu-latest
    steps:
      # The review itself runs in the sweep job (anthropics/claude-code-action).
      - run: echo checks
  sweep:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "U: the gated run (sweep skipped, checks ran) is not a sample" "$(lacks "$out" "RUN=900")"
assert "U: the costed run is the sample" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=32.59")"
assert "U: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"

echo "=== CASE V: a job key with a trailing comment opens its own job block, so its skipped job gates the run ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$GOLDEN" "$c/logs/111.txt"
# The key is readable only if the trailing comment is accepted: the claude job
# is then the skipped one. Read as part of notify, the run would be sampled.
printf '%s\n' '{"jobs":[{"name":"notify","conclusion":"success"},{"name":"claude","conclusion":"skipped"}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"notify","conclusion":"success"},{"name":"claude","conclusion":"success"}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  notify:
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - run: echo notify
  claude:  # the model job
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "V: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "V: the run whose claude job was skipped is gated, not sampled" "$(lacks "$out" "RUN=900")"
assert "V: the claude job that ran is the sample: COST_USD=32.59" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=32.59")"
assert "V: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"

echo "=== CASE W: a job key the parser cannot read does not inherit the previous job's Claude invocation ==="
# A log without accounting, so the log backstop cannot rescue the run: only the
# close-on-unreadable-key rule keeps `notify` from reading as a skipped Claude job.
new_case "$one_run"; cp "$NOACCT" "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"notify","conclusion":"skipped"},{"name":"claude","conclusion":"success"}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  notify:
    if: failure()
    runs-on: ubuntu-latest
    steps:
      - run: echo notify
  "claude":
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml"
assert "W: the run is not gated: it stays sampled, unclassified" "$(has_line "$out" "GATED_OFF_RUNS=0")"
assert "W: the run is sampled as a row" "$(contains "$out" "RUN=111 CONCLUSION=success")"

echo "=== CASE X: two Claude steps in one job, one skipped and one ran: the job reached the model ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"review","conclusion":"success","steps":[{"name":"Claude review","conclusion":"skipped"},{"name":"Claude fix","conclusion":"success"}]}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - name: Claude review
        if: github.event_name == 'pull_request'
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
      - name: Claude fix
        if: github.event_name == 'push'
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "X: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "X: the run is sampled and costed: COST_USD=32.59" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-15T14:25:49Z COST_USD=32.59")"
assert "X: GATED_OFF_RUNS=0 (one Claude step ran)" "$(has_line "$out" "GATED_OFF_RUNS=0")"

# blind_case <log> -- a case whose job list calls run 111 gated: its only Claude
# job (`gated`) was skipped by its own `if:`, and the job that really invoked
# the model (`cli`, a `claude<prompt.md` run line the parser does not read) ran.
# Only the log can say whether the run was billed.
blind_case() {
  new_case "$one_run"; cp "$1" "$c/logs/111.txt"
  printf '%s\n' '{"jobs":[{"name":"gated","conclusion":"skipped","steps":[{"name":"Claude review","conclusion":"skipped"}]},{"name":"cli","conclusion":"success"}]}' > "$c/jobs/111.json"
  cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  gated:
    if: false
    runs-on: ubuntu-latest
    steps:
      - name: Claude review
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 40
  cli:
    runs-on: ubuntu-latest
    steps:
      - run: claude<prompt.md
WF
}

echo "=== CASE Y: a run the job list calls gated, whose log carries accounting, is sampled at its cost (a billed run is never dropped) ==="
blind_case "$OVER"
run_cost "$c" "$c/wf.yml"
assert "Y: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "Y: sampled with its measured cost: COST_USD=10.29 TURNS=72 MAX_TURNS=40 NEAR_CAP=true DENIALS=8" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-15T14:25:49Z COST_USD=10.29 TURNS=72 MAX_TURNS=40 NEAR_CAP=true DENIALS=8")"
assert "Y: RUNS_SAMPLED=1" "$(has_line "$out" "RUNS_SAMPLED=1")"
assert "Y: GATED_OFF_RUNS=0" "$(has_line "$out" "GATED_OFF_RUNS=0")"
assert "Y: COSTED_RUNS=1" "$(has_line "$out" "COSTED_RUNS=1")"
assert "Y: TOTAL_COST_USD=10.29" "$(has_line "$out" "TOTAL_COST_USD=10.29")"
assert "Y: the log is fetched once and its accounting reused (got $(log_fetches "$c" 111))" "$([ "$(log_fetches "$c" 111)" -eq 1 ] && echo true || echo false)"

echo "=== CASE Z: the same gated shape with no accounting in its log stays gated off (negative control) ==="
blind_case "$NOACCT"
run_cost "$c" "$c/wf.yml"
assert "Z: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "Z: the run is not a sample" "$(lacks "$out" "RUN=111")"
assert "Z: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"
assert "Z: RUNS_SAMPLED=0" "$(has_line "$out" "RUNS_SAMPLED=0")"
assert "Z: TOTAL_COST_USD=unknown" "$(has_line "$out" "TOTAL_COST_USD=unknown")"
assert "Z: the log is fetched once, as the backstop (got $(log_fetches "$c" 111))" "$([ "$(log_fetches "$c" 111)" -eq 1 ] && echo true || echo false)"

echo "=== CASE AA: a matrix job named 'resolve (123)' matches its key, and its skipped Claude step gates it ==="
runs='[{"databaseId":900,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":111,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$NOACCT" "$c/logs/900.txt"; cp "$GOLDEN" "$c/logs/111.txt"
printf '%s\n' '{"jobs":[{"name":"resolve (123)","conclusion":"success","steps":[{"name":"Claude triage","conclusion":"skipped"}]}]}' > "$c/jobs/900.json"
printf '%s\n' '{"jobs":[{"name":"resolve (123)","conclusion":"success","steps":[{"name":"Claude triage","conclusion":"success"}]}]}' > "$c/jobs/111.json"
cat > "$c/wf.yml" <<'WF'
name: fixture
jobs:
  resolve:
    strategy:
      matrix:
        pr: [123, 124]
    runs-on: ubuntu-latest
    steps:
      - name: Claude triage
        if: steps.changed.outputs.any == 'true'
        uses: anthropics/claude-code-action@v1
        with:
          claude_args: >-
            --max-turns 60
WF
run_cost "$c" "$c/wf.yml" --limit 1
assert "AA: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "AA: the matrix run whose Claude step was skipped is not a sample" "$(lacks "$out" "RUN=900")"
assert "AA: the costed run behind it is the sample" "$(contains "$out" "RUN=111 CONCLUSION=success CREATED=2026-09-19T00:00:00Z COST_USD=32.59")"
assert "AA: GATED_OFF_RUNS=1" "$(has_line "$out" "GATED_OFF_RUNS=1")"

echo "=== CASE AB: a listing shorter than --scan is exhausted, not truncated, even with the sample short ==="
runs='[{"databaseId":111,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":222,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$GOLDEN" "$c/logs/111.txt"; cp "$OVER" "$c/logs/222.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml" --limit 3
assert "AB: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "AB: both listed runs are sampled, short of --limit 3" "$(has_line "$out" "RUNS_SAMPLED=2")"
assert "AB: SCAN_TRUNCATED=false: the two listed runs were all there was" "$(has_line "$out" "SCAN_TRUNCATED=false")"

echo "=== CASE AC: the default walk asks gh for the 20 newest runs, the floor of the default --scan ==="
new_case "$one_run"; cp "$GOLDEN" "$c/logs/111.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml" --limit 3
assert "AC: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "AC: gh run list is asked for -L 20 by default (4 x --limit 3 = 12 is floored to 20)" "$(contains "$(cat "$c/calls.log")" "STUB-GH run list --workflow wf.yml -L 20 --json databaseId,conclusion,createdAt")"

echo "=== CASE AD: a sample that fills is not truncated, even when the listing reaches --scan ==="
runs='[{"databaseId":111,"conclusion":"success","createdAt":"2026-09-20T00:00:00Z"},{"databaseId":222,"conclusion":"success","createdAt":"2026-09-19T00:00:00Z"}]'
new_case "$runs"; cp "$GOLDEN" "$c/logs/111.txt"; cp "$GOLDEN" "$c/logs/222.txt"
write_wf "$c/wf.yml" "            --max-turns 60"
run_cost "$c" "$c/wf.yml" --limit 1 --scan 2
assert "AD: exit 0 (got $rc)" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "AD: RUNS_SAMPLED=1" "$(has_line "$out" "RUNS_SAMPLED=1")"
assert "AD: SCAN_TRUNCATED=false: the sample filled, so nothing is short" "$(has_line "$out" "SCAN_TRUNCATED=false")"
assert "AD: RUNS_SCANNED=1: the walk stops when the sample fills" "$(has_line "$out" "RUNS_SCANNED=1")"
assert "AD: the run after the filled sample was never queried" "$(lacks "$(cat "$c/calls.log")" "STUB-GH run view 222")"

echo "=== RESULT: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
