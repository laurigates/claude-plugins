#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail`: pass/fail both exit 0
# Regression test for score-run.py's id normalization (issue #2244).
#
# The router answers in whichever id form it prefers. Haiku emits the repo's
# `plugin:skill` form while the catalog ids are `plugin/skill`, and the scorer
# matched `/` literally — #2607's cluster-1 spot-check scored 14 of 16 correct
# picks as `correct=0` because of it. The two forms name the same skill and
# must score the same.
#
# SEMANTIC: every case EXECUTES a copy of the shipped scorer against a fixture
# catalog, task, and stream-json transcript, and reads the TSV row it emits.
# The guard-integrity cases carry equal weight: a WRONG skill in the colon
# form must still score 0, and an id outside the catalog must stay verbatim —
# otherwise "accept both separators" could degrade into "accept anything".
#
# Usage: bash experiments/skill-catalog-routing/scripts/tests/test-score-run.sh
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scorer="$here/../score-run.py"

if python3 -c 'import yaml' >/dev/null 2>&1; then
  runner=(python3)
elif command -v uv >/dev/null 2>&1; then
  runner=(uv run --script --quiet)
else
  echo "SKIP: neither python3+PyYAML nor uv is available"
  exit 0
fi

fixture="$(mktemp -d "${TMPDIR:-/tmp}/score-run-XXXXXX")"
[ -n "$fixture" ] && [ -d "$fixture" ] || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/scripts" "$fixture/catalogs" "$fixture/tasks" "$fixture/runs"
cp "$scorer" "$fixture/scripts/score-run.py"
cat >"$fixture/catalogs/catalog.names.json" <<'JSON'
{"entries": [
  {"id": "testing-plugin/test-run"},
  {"id": "testing-plugin/test-full"},
  {"id": "project-plugin/project-test-loop"}
]}
JSON
printf 'prompt: run the suite\ngold: testing-plugin/test-run\n' >"$fixture/tasks/t01.yaml"

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }

# score SKILL RUNNER_UP -> sets PRED, RUNNER, CORRECT, PARSE from the TSV row
n=0
score() {
  n=$((n + 1))
  local transcript="$fixture/runs/t01.C4.run$n.jsonl"
  python3 -c '
import json, sys
text = json.dumps({"skill": sys.argv[1], "runner_up": sys.argv[2], "confidence": "high"})
event = {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": text}]}}
print(json.dumps(event))
' "$1" "$2" >"$transcript"
  local row
  row="$("${runner[@]}" "$fixture/scripts/score-run.py" "$transcript" 2>&1)"
  PRED="$(awk -F'\t' '{print $5}' <<<"$row")"
  RUNNER="$(awk -F'\t' '{print $6}' <<<"$row")"
  CORRECT="$(awk -F'\t' '{print $8}' <<<"$row")"
  PARSE="$(awk -F'\t' '{print $9}' <<<"$row")"
}

# 1. The regression: `plugin:skill` for the gold scores as correct.
score "testing-plugin:test-run" "testing-plugin:test-full"
[ "$PARSE" = "ok" ] && pass || fail "1: transcript parsed (parse='$PARSE')"
[ "$PRED" = "testing-plugin/test-run" ] && pass || fail "1: colon form normalizes to the catalog id (got '$PRED')"
[ "$CORRECT" = "1" ] && pass || fail "1: colon form of the gold scores correct=1 (got '$CORRECT')"
[ "$RUNNER" = "testing-plugin/test-full" ] && pass || fail "1: the runner-up is normalized too (got '$RUNNER')"

# 2. Control: the slash form still scores correct.
score "testing-plugin/test-run" "NONE"
[ "$CORRECT" = "1" ] && pass || fail "2: slash form scores correct=1 (got '$CORRECT')"
[ "$RUNNER" = "NONE" ] && pass || fail "2: NONE runner-up stays NONE (got '$RUNNER')"

# 3. Guard: a WRONG skill in the colon form still scores 0.
score "testing-plugin:test-full" "testing-plugin:test-run"
[ "$PRED" = "testing-plugin/test-full" ] && pass || fail "3: a wrong colon-form pick resolves to its own id (got '$PRED')"
[ "$CORRECT" = "0" ] && pass || fail "3: a wrong skill scores correct=0 (got '$CORRECT')"

# 4. Guard: an id outside the catalog is kept verbatim and never matches.
score "agents-plugin:debug" "NONE"
[ "$PRED" = "agents-plugin:debug" ] && pass || fail "4: an out-of-catalog id stays verbatim (got '$PRED')"
[ "$CORRECT" = "0" ] && pass || fail "4: an out-of-catalog id scores correct=0 (got '$CORRECT')"

# 5. Existing behaviour: a bare, unambiguous skill name and mixed case.
score "test-run" "NONE"
[ "$CORRECT" = "1" ] && pass || fail "5: a bare unambiguous skill name scores correct=1 (got '$CORRECT')"
score "Testing-Plugin:Test-Run" "NONE"
[ "$CORRECT" = "1" ] && pass || fail "5: the colon form is case-insensitive like the slash form (got '$CORRECT')"

echo "PASSED=$PASSED FAILED=$FAILED"
[ "$FAILED" -eq 0 ]
