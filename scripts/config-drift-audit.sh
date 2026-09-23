#!/usr/bin/env bash
# One run of the scheduled config-drift audit (issue #2554): analyze this repo's
# configuration corpus, report ONLY what is new since the last run, and write the
# comment the workflow posts to the rolling `config-drift` issue.
#
# The analyzer is health-plugin/scripts/config-drift.py (semantic tier:
# embeddings + promotion candidates); the delta is health-plugin/scripts/
# probe-delta.py. This script owns the decisions around them, so they can be
# exercised locally (scripts/tests/test-config-drift-audit.sh) rather than only
# on a scheduled runner:
#
#   * Exit-code discipline. The analyzer exits 1 whenever ANY warn finding
#     exists -- its normal state on a real corpus -- so 0 and 1 are both a
#     completed run. Anything else, or empty output, is an analyzer failure:
#     it is reported as an error comment and the run fails. It is never
#     reported as "nothing new", and the baseline is left untouched.
#   * First run vs. lost baseline. `--prior-success true` says a previous run
#     of this workflow completed, so a missing baseline is a LOSS (an evicted
#     cache), not a first run. probe-delta's `--expect-baseline` then
#     re-reports every finding beside a `baseline_lost` finding. A silent
#     re-record would swallow everything that appeared while the baseline was
#     gone -- the failure delta reporting exists to prevent.
#   * A degraded run (`semantic_pass_unavailable`: the model could not load)
#     is reported but does not roll the baseline forward, so the embedding
#     findings it could not compute are not re-reported as "new" later.
#   * `--plant-control` proves the delta logic end to end: after the audit
#     records its baseline, it plants two unrelated rules one scope apart,
#     injects a 0.95 similarity for exactly that pair through config-drift's
#     `--sim-fixture` seam, and requires the delta to report exactly one new
#     finding -- that pair, as a promotion_candidate, with its score and both
#     paths. Zero new findings from a planted duplicate means the delta logic
#     is broken, which "nothing changed" cannot otherwise be told apart from.
#     The planted files are removed on exit and the baseline is not updated.
#
# Usage:
#   bash scripts/config-drift-audit.sh --out-dir DIR --state-dir DIR
#       --prior-success true|false [--root DIR] [--waivers FILE]
#       [--plant-control] [--run-url URL]
#
#   --out-dir        where findings, delta, and comment.md are written
#   --state-dir      the cached state: baseline.json, embeddings.json, gitdates.json
#   --prior-success  whether a previous run of the audit completed (see above)
#   --root           corpus root (default: this script's repo)
#   --waivers        waiver file (default: <root>/health-plugin/config-drift-waivers.json)
#   --plant-control  run the planted-duplicate control after the audit
#   --run-url        link to the workflow run, quoted in the comment
#
# Test seams (environment):
#   CONFIG_DRIFT_AUDIT_CHEAP_TIER=1   run the audit as `python3 config-drift.py
#                                     --no-embed --fast` instead of `uv run --script`
#   CONFIG_DRIFT_AUDIT_ANALYZER       path to the analyzer script
#   CONFIG_DRIFT_AUDIT_PROBE_DELTA    path to the delta script
#
# Output: a `=== CONFIG DRIFT AUDIT ===` block (structured-script-output.md).
# COMMENT=true means <out-dir>/comment.md holds a comment to post.
#
# Exit codes:
#   0 - the audit completed (with or without new findings)
#   1 - analyzer or delta failure, or the planted control failed
#   2 - usage error

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ANALYZER="${CONFIG_DRIFT_AUDIT_ANALYZER:-$REPO_DIR/health-plugin/scripts/config-drift.py}"
PROBE_DELTA="${CONFIG_DRIFT_AUDIT_PROBE_DELTA:-$REPO_DIR/health-plugin/scripts/probe-delta.py}"

usage() {
  echo "Usage: config-drift-audit.sh --out-dir DIR --state-dir DIR --prior-success true|false [--root DIR] [--waivers FILE] [--plant-control] [--run-url URL]" >&2
}

die_usage() {
  echo "config-drift-audit.sh: $1" >&2
  usage
  exit 2
}

out_dir="" state_dir="" prior="" root="$REPO_DIR" waivers="" plant=0 run_url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) [ -n "${2:-}" ] || die_usage "--out-dir requires a value"; out_dir="$2"; shift 2 ;;
    --state-dir) [ -n "${2:-}" ] || die_usage "--state-dir requires a value"; state_dir="$2"; shift 2 ;;
    --prior-success) prior="${2:-}"; shift 2 ;;
    --root) [ -d "${2:-}" ] || die_usage "--root requires a directory"; root="$2"; shift 2 ;;
    --waivers) [ -n "${2:-}" ] || die_usage "--waivers requires a value"; waivers="$2"; shift 2 ;;
    --plant-control) plant=1; shift ;;
    --run-url) run_url="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done
[ -n "$out_dir" ] || die_usage "--out-dir is required"
[ -n "$state_dir" ] || die_usage "--state-dir is required"
case "$prior" in
  true|false) ;;
  *) die_usage "--prior-success must be true or false, got: '${prior}'" ;;
esac

root_abs="$(cd "$root" && pwd -P)"
waivers="${waivers:-$root_abs/health-plugin/config-drift-waivers.json}"
mkdir -p "$out_dir" "$state_dir"
out_dir="$(cd "$out_dir" && pwd -P)"
state_dir="$(cd "$state_dir" && pwd -P)"

baseline="$state_dir/baseline.json"
cache="$state_dir/embeddings.json"
findings="$out_dir/findings.json"
analyzer_err="$out_dir/analyzer.err"
delta="$out_dir/delta.txt"
delta_err="$out_dir/delta.err"
comment="$out_dir/comment.md"
rm -f "$comment"

# val KEY FILE -- the first `KEY=value` row of a structured block. awk reads the
# file itself, so no early-closing reader sits in a pipe (#1744).
val() { awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$2" 2>/dev/null; }

# render_rows DELTA FINDINGS -- a markdown table of the findings a delta block
# reported, joined back to the analyzer's JSON by (kind, summary) so each row
# carries its score and paths. A row with no analyzer counterpart (probe-delta's
# own `baseline_lost`) is rendered from the delta line alone.
render_rows() {
  python3 - "$1" "$2" "$root_abs" <<'PY'
import json, os, re, sys

delta_path, findings_path, root = sys.argv[1:4]
try:
    pool = json.load(open(findings_path, encoding="utf-8")).get("findings", [])
except (OSError, ValueError):
    pool = []
rows, in_issues = [], False
for line in open(delta_path, encoding="utf-8"):
    line = line.rstrip("\n")
    if line == "ISSUES:":
        in_issues = True
        continue
    if not in_issues:
        continue
    m = re.match(r"  - SEVERITY=(\S+) TYPE=(\S+) MSG=(.*)$", line)
    if m:
        rows.append(m.groups())


def cell(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def rel(path):
    try:
        return os.path.relpath(path, root) if os.path.isabs(path) else path
    except ValueError:
        return path


used = set()
print("| Severity | Kind | Score | Paths | Summary |")
print("|---|---|---|---|---|")
for severity, kind, msg in rows:
    match = None
    for i, f in enumerate(pool):
        if i not in used and f.get("kind") == kind and f.get("summary") == msg:
            used.add(i)
            match = f
            break
    score, paths = "—", "—"
    if match is not None:
        if match.get("score") is not None:
            score = str(match["score"])
        found = list(match.get("paths") or [])
        if match.get("path"):
            found.append(match["path"])
        if found:
            paths = "<br>".join(f"`{cell(rel(p))}`" for p in found)
    print(f"| {severity} | `{kind}` | {score} | {paths} | {cell(msg)} |")
PY
}

now_utc="$(date -u +%Y-%m-%dT%H:%MZ)"
run_line=""
[ -n "$run_url" ] && run_line="Run: $run_url"

issues=()
status="OK"
exit_rc=0
mode="audit"
[ "$plant" -eq 1 ] && mode="audit+control"

# ----------------------------------------------------------------- the audit
if [ "${CONFIG_DRIFT_AUDIT_CHEAP_TIER:-}" = "1" ]; then
  analyzer_cmd=(python3 "$ANALYZER" --no-embed --fast)
else
  analyzer_cmd=(uv run --script "$ANALYZER")
fi

start=$SECONDS
"${analyzer_cmd[@]}" --root "$root_abs" --format=json --waivers "$waivers" \
  --cache "$cache" > "$findings" 2> "$analyzer_err"
analyzer_rc=$?
analyzer_seconds=$((SECONDS - start))

analyzer_failed=0
failure_reason=""
if [ "$analyzer_rc" -ne 0 ] && [ "$analyzer_rc" -ne 1 ]; then
  analyzer_failed=1
  failure_reason="the analyzer exited ${analyzer_rc} (0 and 1 are the only completed-run codes)"
elif [ ! -s "$findings" ]; then
  analyzer_failed=1
  failure_reason="the analyzer exited ${analyzer_rc} with empty output"
fi

first_run="false" baseline_lost="false" new=0 total=0 recorded="false" degraded="false"
delta_status=""

if [ "$analyzer_failed" -eq 0 ]; then
  if grep -q '"kind": *"semantic_pass_unavailable"' "$findings"; then
    degraded="true"
  fi
  delta_args=(--findings "$findings" --baseline "$baseline" --probe config-drift
    --root "$root_abs" --section "CONFIG DRIFT DELTA")
  [ "$degraded" = "false" ] && delta_args+=(--record)
  [ "$prior" = "true" ] && delta_args+=(--expect-baseline)
  python3 "$PROBE_DELTA" "${delta_args[@]}" > "$delta" 2> "$delta_err"
  delta_rc=$?
  delta_status="$(val STATUS "$delta")"
  if [ "$delta_rc" -ne 0 ] && [ "$delta_rc" -ne 1 ]; then
    analyzer_failed=1
    failure_reason="probe-delta exited ${delta_rc}: $(head -c 400 "$delta_err" | tr '\n' ' ')"
  elif [ "$(val TYPE "$delta")" = "analyzer_failed" ]; then
    analyzer_failed=1
    failure_reason="probe-delta could not parse the analyzer output: $(val MSG "$delta")"
  else
    first_run="$(val FIRST_RUN "$delta")"
    baseline_lost="$(val BASELINE_LOST "$delta")"
    baseline_lost="${baseline_lost:-false}"
    new="$(val NEW "$delta")"
    new="${new:-0}"
    total="$(val TOTAL_FINDINGS "$delta")"
    [ "$(val BASELINE_WRITTEN "$delta")" = "true" ] && recorded="true"
  fi
fi

if [ "$analyzer_failed" -eq 1 ]; then
  status="ERROR"
  exit_rc=1
  issues+=("  - SEVERITY=ERROR TYPE=analyzer_failed MSG=${failure_reason}")
  exc_line="$(grep -E '^[A-Za-z_.]*(Error|Exception):' "$analyzer_err" | tail -n 1)"
  {
    echo "### Config drift audit — analyzer failed (${now_utc})"
    echo
    [ -n "$run_line" ] && { echo "$run_line"; echo; }
    echo "Nothing was compared this run, and the baseline was left untouched: ${failure_reason}."
    [ -n "$exc_line" ] && { echo; echo "\`${exc_line}\`"; }
    echo
    echo "<details><summary>analyzer stderr (last 30 lines)</summary>"
    echo
    echo '```'
    tail -n 30 "$analyzer_err"
    echo '```'
    echo
    echo "</details>"
  } > "$comment"
elif [ "$new" -gt 0 ] || [ "$baseline_lost" = "true" ]; then
  # BASELINE_LOST counts only the analyzer's findings in NEW, so a lost
  # baseline over a clean corpus is NEW=0 and must still be said out loud.
  status="WARN"
  if [ "$baseline_lost" = "true" ]; then
    headline="Baseline lost — re-reporting all ${new} finding(s), since none could be compared against a previous run."
    issues+=("  - SEVERITY=WARN TYPE=baseline_lost MSG=no trusted baseline on a run after a completed one")
  else
    headline="${new} new finding(s) since the last recorded baseline."
  fi
  {
    echo "### Config drift audit — ${now_utc}"
    echo
    [ -n "$run_line" ] && { echo "$run_line"; echo; }
    echo "$headline"
    [ "$degraded" = "true" ] && { echo; echo "The semantic pass was unavailable this run, so the baseline was **not** rolled forward."; }
    echo
    render_rows "$delta" "$findings"
    echo
    echo "Totals: ${total} finding(s) now, reported once each. Waive a finding judged not to be a defect in \`health-plugin/config-drift-waivers.json\`."
  } > "$comment"
fi

# --------------------------------------------------------- planted control
control="not_run"
control_reason=""
planted_parent="$root_abs/.claude/rules/zz-config-drift-control-parent.md"
planted_dir="$root_abs/zz-config-drift-control"
planted_child="$planted_dir/.claude/rules/zz-config-drift-control-child.md"
made_rules_dir=0

cleanup_control() {
  rm -f "$planted_parent" "$planted_child"
  [ -d "$planted_dir" ] && rm -rf "$planted_dir"
  if [ "$made_rules_dir" -eq 1 ]; then
    rmdir "$root_abs/.claude/rules" 2>/dev/null
    rmdir "$root_abs/.claude" 2>/dev/null
  fi
  return 0
}

if [ "$plant" -eq 1 ]; then
  if [ "$analyzer_failed" -eq 1 ] || [ "$recorded" != "true" ]; then
    control="failed"
    control_reason="the audit did not record a fresh baseline this run, so the control has nothing exact to compare against"
  elif [ -e "$planted_parent" ] || [ -e "$planted_dir" ]; then
    control="failed"
    control_reason="refusing to plant: ${planted_parent#"$root_abs"/} or ${planted_dir#"$root_abs"/} already exists"
  else
    trap cleanup_control EXIT
    trap 'cleanup_control; exit 130' INT TERM
    [ -d "$root_abs/.claude/rules" ] || made_rules_dir=1
    mkdir -p "$root_abs/.claude/rules" "$planted_dir/.claude/rules"
    # Two rules on unrelated subjects, so no real similarity -- lexical or
    # embedding -- can pair them. The only thing that can is the injected score.
    cat > "$planted_parent" <<'RULE'
---
reviewed: 2026-09-01
paths: ["zz-config-drift-control/**"]
---
# Torque Baseline (config-drift control)

Planted by scripts/config-drift-audit.sh --plant-control and removed when the
run ends. Every assembly line records a torque baseline before the first shift
of the week. The baseline is captured from the calibration jig, logged against
the jig's serial number, and signed off by whoever ran the jig that morning.

A baseline older than seven shifts is treated as absent: the jig drifts with
ambient temperature, and a stale figure reads as authoritative while being
wrong. Re-run the jig rather than extrapolating from the previous week.
RULE
    cat > "$planted_child" <<'RULE'
---
reviewed: 2026-09-01
paths: ["zz-config-drift-control/**"]
---
# Sourdough Levain Schedule (config-drift control)

Planted by scripts/config-drift-audit.sh --plant-control and removed when the
run ends. Feed the levain twice a day at a one-to-five-to-five ratio of starter,
flour and water, and keep it in the warm cabinet between feeds so it peaks
within six hours of each one.

Bake only from a levain that has doubled and domed; a collapsed top means it
peaked early and the dough will under-proof. Discard rather than rescue a
levain that smells of acetone, and restart it from the reserve jar.
RULE
    control_baseline="$out_dir/control-baseline.json"
    sim="$out_dir/control-sim.json"
    control_findings="$out_dir/control-findings.json"
    control_delta="$out_dir/control-delta.txt"
    # The delta runs against a COPY, so the control can never write the baseline.
    cp "$baseline" "$control_baseline"
    python3 - "$sim" "$planted_child" "$planted_parent" <<'PY'
import hashlib, json, sys
out, a, b = sys.argv[1:4]
def h(p):
    # config-drift keys a document by sha256(body)[:16]; see fixture_sim_fn.
    return hashlib.sha256(open(p, encoding="utf-8").read().encode()).hexdigest()[:16]
json.dump({"|".join(sorted((h(a), h(b)))): 0.95}, open(out, "w"))
PY
    # Cheap tier on purpose: `--fast` reads the git dates the audit just cached
    # and `--no-embed` drops only the embedding findings, which read as resolved
    # (never reported), so the one difference from the recorded baseline is the
    # planted pair.
    python3 "$ANALYZER" --root "$root_abs" --format=json --waivers "$waivers" \
      --cache "$cache" --no-embed --fast --sim-fixture "$sim" \
      > "$control_findings" 2>> "$analyzer_err"
    control_rc=$?
    cleanup_control
    trap - EXIT INT TERM
    if [ "$control_rc" -ne 0 ] && [ "$control_rc" -ne 1 ]; then
      control="failed"
      control_reason="the control analyzer run exited ${control_rc}"
    else
      python3 "$PROBE_DELTA" --findings "$control_findings" --baseline "$control_baseline" \
        --probe config-drift --root "$root_abs" --section "CONFIG DRIFT CONTROL" \
        > "$control_delta" 2>> "$delta_err"
      control_verdict="$(python3 - "$control_delta" "$control_findings" "$planted_child" "$planted_parent" <<'PY'
import json, sys
delta_path, findings_path, child, parent = sys.argv[1:5]
keys = {}
for line in open(delta_path, encoding="utf-8"):
    k, sep, v = line.rstrip("\n").partition("=")
    if sep and k.isupper() and k not in keys:
        keys[k] = v
new = keys.get("NEW")
promo = keys.get("FINDING_PROMOTION_CANDIDATE", "0")
if new != "1" or promo != "1":
    print(f"expected exactly 1 new finding, a promotion_candidate; got NEW={new} "
          f"FINDING_PROMOTION_CANDIDATE={promo}")
    sys.exit()
found = [f for f in json.load(open(findings_path, encoding="utf-8"))["findings"]
         if f.get("kind") == "promotion_candidate"]
if len(found) != 1:
    print(f"expected exactly 1 promotion_candidate in the analyzer output, got {len(found)}")
elif found[0].get("paths") != [child, parent]:
    print(f"the new finding names {found[0].get('paths')}, not the planted pair")
elif found[0].get("score") != 0.95:
    print(f"the new finding scores {found[0].get('score')}, not the injected 0.95")
else:
    print("ok")
PY
)"
      if [ "$control_verdict" = "ok" ]; then
        control="passed"
      else
        control="failed"
        control_reason="$control_verdict"
      fi
    fi
  fi

  had_audit_comment=0
  [ -s "$comment" ] && had_audit_comment=1
  {
    [ "$had_audit_comment" -eq 1 ] && echo
    echo "### Config drift control — ${control} (${now_utc})"
    echo
    [ "$had_audit_comment" -eq 1 ] || { [ -n "$run_line" ] && { echo "$run_line"; echo; }; }
    echo "A planted pair of unrelated rules, one scope apart, was given an injected similarity of 0.95. The delta must report exactly that pair as one new finding; zero means the delta logic is broken. The planted files were removed and the baseline was not updated."
    if [ "$control" = "passed" ]; then
      echo
      render_rows "$control_delta" "$control_findings"
    else
      echo
      echo "**Control failed:** ${control_reason}."
    fi
  } >> "$comment"
  if [ "$control" = "failed" ]; then
    status="ERROR"
    exit_rc=1
    issues+=("  - SEVERITY=ERROR TYPE=control_failed MSG=${control_reason}")
  fi
fi

comment_ready="false"
[ -s "$comment" ] && comment_ready="true"

echo "=== CONFIG DRIFT AUDIT ==="
echo "MODE=${mode}"
echo "ROOT=${root_abs}"
echo "PRIOR_SUCCESS=${prior}"
echo "ANALYZER_RC=${analyzer_rc}"
echo "ANALYZER_SECONDS=${analyzer_seconds}"
echo "DELTA_STATUS=${delta_status:-none}"
echo "TOTAL_FINDINGS=${total:-0}"
echo "FIRST_RUN=${first_run:-false}"
echo "BASELINE_LOST=${baseline_lost}"
echo "NEW=${new}"
echo "DEGRADED=${degraded}"
echo "RECORDED=${recorded}"
echo "CONTROL=${control}"
echo "COMMENT=${comment_ready}"
echo "COMMENT_FILE=${comment}"
echo "STATUS=${status}"
echo "ISSUE_COUNT=${#issues[@]}"
if [ "${#issues[@]}" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END CONFIG DRIFT AUDIT ==="
exit "$exit_rc"
