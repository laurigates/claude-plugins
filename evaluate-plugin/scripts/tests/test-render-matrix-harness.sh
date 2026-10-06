#!/usr/bin/env bash
# shellcheck disable=SC2016  # the expected markdown carries literal backticks
# Regression test for render_matrix_report.py's harness reporting.
#
# A model-matrix.json can now hold rollouts from two harnesses: the in-session
# Task subagent (the default; SKILL.md pasted in) and the headless `claude -p`
# child (rollout_headless.sh; plugin loaded, description routing exercised).
# Their pass rates are not comparable, so a file that mixes them must say so
# loudly instead of rendering a delta table that reads across the boundary.
#
# Pins: (a) a legacy file with no harness field renders as `subagent` with no
# warning, so every pre-headless matrix is unchanged apart from one line;
# (b) a file whose models share one explicit harness names it, no warning;
# (c) a per-model mix -- including an absent field beside an explicit
# `headless`, since absent means subagent -- emits the mixed-harness warning
# naming each alias; (d) metadata.harness is the default a model entry can
# override.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(dirname "$script_dir")"
fixtures="$script_dir/fixtures"
renderer="$scripts_dir/render_matrix_report.py"

fail_count=0
pass_count=0

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

has() { grep -qF -- "$2" <<<"$1" && echo true || echo false; }

tmp_dir="$(mktemp -d)"
if [ -z "$tmp_dir" ] || [ ! -d "$tmp_dir" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$tmp_dir"' EXIT

# variant <name> <python stmt over d> -- write a mutated copy of the example matrix
variant() {
  python3 - "$fixtures/example-model-matrix.json" "$tmp_dir/$1.json" "$2" <<'PY'
import json, sys
src, dst, stmt = sys.argv[1:4]
d = json.load(open(src, encoding="utf-8"))
exec(stmt)
json.dump(d, open(dst, "w", encoding="utf-8"), indent=2)
PY
}

render() { python3 "$renderer" "$1" 2>&1; }

echo "=== TEST: legacy matrix (no harness field) ==="
out="$(render "$fixtures/example-model-matrix.json")"; rc=$?
check "legacy: exit 0" "0" "$rc"
check "legacy: reads as subagent" "true" "$(has "$out" 'Harness: `subagent`')"
check "legacy: no mixed-harness warning" "false" "$(has "$out" 'Mixed-harness warning')"
check "legacy: delta table still renders" "true" "$(has "$out" '| Model | With skill | Baseline |')"

echo "=== TEST: one explicit harness for every model ==="
variant all-headless 'for m in d["metadata"]["models"]: m["harness"] = "headless"'
out="$(render "$tmp_dir/all-headless.json")"
check "uniform: names headless" "true" "$(has "$out" 'Harness: `headless`')"
check "uniform: no warning" "false" "$(has "$out" 'Mixed-harness warning')"

echo "=== TEST: metadata.harness is the default ==="
variant meta-default 'd["metadata"]["harness"] = "headless"'
out="$(render "$tmp_dir/meta-default.json")"
check "meta default: every model headless" "true" "$(has "$out" 'Harness: `headless`')"
check "meta default: no warning" "false" "$(has "$out" 'Mixed-harness warning')"

echo "=== TEST: a per-model mix warns ==="
# Only haiku ran headless; opus and sonnet carry no field, which means subagent.
variant mixed 'd["metadata"]["models"][-1]["harness"] = "headless"'
out="$(render "$tmp_dir/mixed.json")"
check "mixed: warning emitted" "true" "$(has "$out" 'Mixed-harness warning')"
check "mixed: names the headless alias" "true" "$(has "$out" '`haiku`=headless')"
check "mixed: names a defaulted alias" "true" "$(has "$out" '`opus`=subagent')"
check "mixed: no single-harness line" "false" "$(has "$out" 'Harness: `')"

echo "=== TEST: a model entry overrides metadata.harness ==="
variant override 'd["metadata"]["harness"] = "headless"; d["metadata"]["models"][0]["harness"] = "subagent"'
out="$(render "$tmp_dir/override.json")"
check "override: mix detected" "true" "$(has "$out" 'Mixed-harness warning')"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
